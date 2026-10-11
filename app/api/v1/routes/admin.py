# app/api/v1/routes/admin.py
# ─────────────────────────────────────────────────────────────────────────────
# Back-office (dashboard Next.js + panneau admin de l'app). Réservé au rôle
# admin. Toutes les listes sont paginées (limit/offset) : rien ne charge une
# table entière, même avec des dizaines de milliers de lignes.
# ─────────────────────────────────────────────────────────────────────────────
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import Select, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.api.v1.routes.conversations import api_conv, api_msg
from app.api.v1.routes.logements import api as api_logement, supprimer_logement
from app.core import cache
from app.core.dependencies import admin_requis
from app.core.firebase import a_compte_service
from app.core.serial import appliquer, maintenant, vers_api
from app.db.session import apres_commit, get_db, marquer
from app.models.models import (
    Conversation, Logement, Message, NotificationAdmin, Publicite, Signalement, Transaction,
    Urgence, Utilisateur,
)
from app.services import annonces, fichiers, push

router = APIRouter(prefix="/admin", tags=["Admin"], dependencies=[Depends(admin_requis)])


def _page(limit: int, offset: int) -> tuple[int, int]:
    return max(1, min(limit or 50, 200)), max(0, offset or 0)


async def _liste(db: AsyncSession, q: Select, conv, limit: int, offset: int, total: bool = True) -> dict:
    n, o = _page(limit, offset)
    lignes = (await db.execute(q.offset(o).limit(n + 1))).scalars().all()
    rep = {"items": [conv(x) for x in lignes[:n]], "suivant": o + n if len(lignes) > n else None}
    if total:
        rep["total"] = (await db.execute(select(func.count()).select_from(
            q.order_by(None).subquery()))).scalar_one()
    return rep


# ═════════════════════════════════════════════════════════════════════════════
# Statistiques
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/stats")
async def stats(db: AsyncSession = Depends(get_db)):
    en_cache = await cache.lire_json("admin:stats")
    if en_cache:
        return en_cache
    t = maintenant()
    debut_jour = t.replace(hour=0, minute=0, second=0, microsecond=0)
    debut_mois = debut_jour.replace(day=1)

    async def compter(modele, *conds):
        return (await db.execute(select(func.count()).select_from(modele).where(*conds))).scalar_one()

    revenus = (await db.execute(select(
        func.coalesce(func.sum(Transaction.montant), 0),
        func.coalesce(func.sum(Transaction.montant).filter(Transaction.created_at >= debut_mois), 0),
        func.count()).where(Transaction.statut == "reussi", Transaction.simulation.is_(False)))).one()
    d = {
        "totalAnnonces": await compter(Logement),
        "annoncesVerifiees": await compter(Logement, Logement.est_verifie.is_(True)),
        "annoncesNonVerifiees": await compter(Logement, Logement.est_verifie.is_(False)),
        "annoncesSponsorisees": await compter(Logement, Logement.is_sponsored.is_(True)),
        "brouillons": await compter(Logement, Logement.payment_pending.is_(True)),
        "totalUtilisateurs": await compter(Utilisateur, Utilisateur.anonyme.is_(False)),
        "prestataires": await compter(Utilisateur, Utilisateur.role == "prestataire"),
        "comptesGratuits": await compter(Utilisateur, Utilisateur.compte_gratuit.is_(True)),
        "conversationsAujourdhui": await compter(Conversation, Conversation.last_message_time >= debut_jour),
        "totalConversations": await compter(Conversation),
        "signalementsEnAttente": await compter(Signalement, Signalement.statut == "en_attente"),
        "publicitesEnAttente": await compter(Publicite, Publicite.payment_pending.is_(True)),
        "publicitesActives": await compter(Publicite, Publicite.actif.is_(True), Publicite.expires_at > t),
        "urgencesActives": await compter(Urgence, Urgence.actif.is_(True), Urgence.expires_at > t),
        "notificationsNonLues": await compter(NotificationAdmin, NotificationAdmin.lu.is_(False)),
        "revenusTotal": int(revenus[0]), "revenusMois": int(revenus[1]), "paiementsReussis": int(revenus[2]),
    }
    await cache.ecrire_json("admin:stats", d, 30)
    return d


# ═════════════════════════════════════════════════════════════════════════════
# Annonces
# ═════════════════════════════════════════════════════════════════════════════

_FILTRES_LOGEMENTS = {
    "non_verifie": Logement.est_verifie.is_(False),
    "verifie": Logement.est_verifie.is_(True),
    "sponsorie": Logement.is_sponsored.is_(True),
    "indisponible": Logement.disponible.is_(False),
    "brouillon": Logement.payment_pending.is_(True),
    "bloque": Logement.visible_admin.is_(False),
}


@router.get("/logements")
async def logements(filtre: str | None = None, q: str | None = Query(None, max_length=120),
                    prestataire: str | None = None, limit: int = 50, offset: int = 0,
                    db: AsyncSession = Depends(get_db)):
    req = select(Logement)
    if filtre in _FILTRES_LOGEMENTS:
        req = req.where(_FILTRES_LOGEMENTS[filtre])
    if prestataire:
        req = req.where(Logement.uid_prestataire == prestataire)
    if q:
        m = f"%{q}%"
        req = req.where(or_(Logement.titre.ilike(m), Logement.ville.ilike(m), Logement.quartier.ilike(m),
                            Logement.prestataire_nom.ilike(m), Logement.id == q))
    return await _liste(db, req.order_by(Logement.created_at.desc()), api_logement, limit, offset)


@router.patch("/logements/{logement_id}")
async def modifier_logement(logement_id: str, data: dict, db: AsyncSession = Depends(get_db)):
    """L'admin peut tout régler (vérification, visibilité, sponsoring…)."""
    l = await db.get(Logement, logement_id, with_for_update=True)
    if l is None:
        raise HTTPException(404, "Annonce introuvable")
    etait_visible = l.disponible and not l.payment_pending and l.visible_admin_effectif
    appliquer(l, data, Logement.CHAMPS, interdits={"createdAt", "updatedAt"})
    if "isSponsored" in data and not l.is_sponsored:
        l.sponsored_until = None
    await db.flush()
    if not etait_visible and l.disponible and not l.payment_pending and l.visible_admin_effectif:
        annonces.annonce_publiee(db, l.id, payee=False)
    annonces.annonce_modifiee(db, l.uid_prestataire)
    lid = l.id
    apres_commit(db, lambda: cache.effacer_prefixe(f"pub:logements:un:{lid}"), "cache_logement")
    apres_commit(db, lambda: cache.effacer_prefixe("admin:stats"), "cache_stats")
    return api_logement(l)


@router.delete("/logements/{logement_id}")
async def supprimer_logement_admin(logement_id: str, db: AsyncSession = Depends(get_db)):
    l = await db.get(Logement, logement_id, with_for_update=True)
    if l is None:
        raise HTTPException(404, "Annonce introuvable")
    await supprimer_logement(db, l)
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# Utilisateurs
# ═════════════════════════════════════════════════════════════════════════════

def _user(u: Utilisateur) -> dict:
    d = vers_api(u, Utilisateur.CHAMPS)
    d["aJetonPush"] = bool(u.fcm_token)
    d.pop("fcmToken", None)
    return d


@router.get("/users")
async def users(q: str | None = Query(None, max_length=120), role: str | None = None,
                filtre: str | None = None, limit: int = 50, offset: int = 0,
                db: AsyncSession = Depends(get_db)):
    req = select(Utilisateur).where(Utilisateur.anonyme.is_(False))
    if role:
        req = req.where(Utilisateur.role == role)
    if filtre == "gratuit":
        req = req.where(Utilisateur.compte_gratuit.is_(True))
    elif filtre == "premium":
        req = req.where(Utilisateur.is_premium.is_(True))
    elif filtre == "verifie":
        req = req.where(Utilisateur.is_verifie.is_(True))
    elif filtre == "suspendu":
        req = req.where(Utilisateur.suspendu.is_(True))
    if q:
        m = f"%{q}%"
        req = req.where(or_(Utilisateur.prenom.ilike(m), Utilisateur.nom.ilike(m),
                            Utilisateur.email.ilike(m), Utilisateur.telephone.ilike(m), Utilisateur.id == q))
    return await _liste(db, req.order_by(Utilisateur.prenom, Utilisateur.nom, Utilisateur.id), _user, limit, offset)


@router.get("/users/{uid}")
async def user(uid: str, db: AsyncSession = Depends(get_db)):
    u = await db.get(Utilisateur, uid)
    if u is None:
        raise HTTPException(404, "Utilisateur introuvable")
    return _user(u)


@router.patch("/users/{uid}")
async def modifier_user(uid: str, data: dict, db: AsyncSession = Depends(get_db)):
    u = await db.get(Utilisateur, uid)
    if u is None:
        raise HTTPException(404, "Utilisateur introuvable")
    if "role" in data and data["role"] not in ("client", "prestataire", "admin"):
        raise HTTPException(400, "Rôle invalide")
    appliquer(u, data, Utilisateur.CHAMPS, interdits={"uid", "fcmToken", "createdAt", "updatedAt"})
    apres_commit(db, lambda: cache.effacer_prefixe(f"pub:user:{uid}"), "cache_profil")
    return _user(u)


@router.delete("/users/{uid}")
async def supprimer_user(uid: str, db: AsyncSession = Depends(get_db)):
    await db.execute(delete(Utilisateur).where(Utilisateur.id == uid))
    return {"success": True}


@router.post("/comptes-gratuits")
async def creer_compte_gratuit(data: dict, db: AsyncSession = Depends(get_db)):
    """Crée (ou met à jour) un compte prestataire 100 % gratuit
    (email + mot de passe Firebase Auth, e-mail considéré vérifié)."""
    from firebase_admin import auth as fb_auth
    email = str(data.get("email") or "").strip().lower()
    mdp = str(data.get("password") or "")
    nom, prenom = str(data.get("nom") or "").strip(), str(data.get("prenom") or "").strip()
    if not (email and mdp and nom and prenom):
        raise HTTPException(400, {"success": False, "error": "Paramètres manquants (email, password, nom, prenom)"})
    if len(mdp) < 6:
        raise HTTPException(400, {"success": False, "error": "Le mot de passe doit contenir au moins 6 caractères"})
    if not a_compte_service():
        raise HTTPException(503, {"success": False, "error": "FIREBASE_CREDENTIALS absent sur l'API"})
    tel = str(data.get("telephone") or "").strip()
    if tel and not tel.startswith("+"):
        tel = f"+237{tel}"
    import asyncio
    try:
        try:
            existant = await asyncio.to_thread(fb_auth.get_user_by_email, email)
            uid = existant.uid
            await asyncio.to_thread(fb_auth.update_user, uid, password=mdp, email_verified=True,
                                    display_name=f"{prenom} {nom}")
        except fb_auth.UserNotFoundError:
            nouveau = await asyncio.to_thread(fb_auth.create_user, email=email, password=mdp,
                                              email_verified=True, display_name=f"{prenom} {nom}")
            uid = nouveau.uid
    except Exception as e:  # noqa: BLE001
        raise HTTPException(500, {"success": False, "error": str(e)})
    u = await db.get(Utilisateur, uid)
    if u is None:
        u = Utilisateur(id=uid, extra={})
        db.add(u)
    u.email, u.nom, u.prenom, u.telephone = email, nom, prenom, tel or (u.telephone or "")
    u.role, u.compte_gratuit, u.is_verifie, u.anonyme, u.suspendu = "prestataire", True, True, False, False
    u.is_premium = bool(u.is_premium)
    return {"success": True, "uid": uid, "email": email}


@router.post("/notification-globale")
async def notification_globale(data: dict):
    titre, corps = str(data.get("titre") or "").strip(), str(data.get("corps") or "").strip()
    if not titre or not corps:
        raise HTTPException(400, {"success": False, "error": "Titre et corps requis"})
    if not a_compte_service():
        raise HTTPException(503, {"success": False, "error": "FIREBASE_CREDENTIALS absent sur l'API"})
    from app.services.fond import lancer
    lancer(push.diffuser(titre, corps, {"type": "annonce_globale"}), "notif_globale")
    return {"success": True, "message": "Diffusion lancée en arrière-plan"}


# ═════════════════════════════════════════════════════════════════════════════
# Conversations
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/conversations")
async def conversations(q: str | None = None, limit: int = 50, offset: int = 0,
                        db: AsyncSession = Depends(get_db)):
    req = select(Conversation)
    if q:
        m = f"%{q}%"
        req = req.where(or_(Conversation.logement_titre.ilike(m), Conversation.last_message.ilike(m),
                            Conversation.contact_label.ilike(m)))
    rep = await _liste(db, req.order_by(Conversation.last_message_time.desc().nulls_last()),
                       api_conv, limit, offset)
    # Noms des participants en une requête.
    ids = {p for c in rep["items"] for p in c.get("participants") or [] if not p.startswith("visiteur_")}
    noms = {}
    if ids:
        for uid, prenom, nom in (await db.execute(select(Utilisateur.id, Utilisateur.prenom, Utilisateur.nom)
                                                  .where(Utilisateur.id.in_(ids)))).all():
            noms[uid] = f"{prenom} {nom}".strip()
    rep["noms"] = noms
    return rep


@router.get("/conversations/{conv_id}/messages")
async def conversation_messages(conv_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    async def produire():
        lignes = (await db.execute(select(Message).where(Message.conversation_id == conv_id)
                                   .order_by(Message.timestamp.desc()).limit(500))).scalars().all()
        return {"items": [api_msg(m) for m in reversed(lignes)]}
    return await versionne(request, f"conv:{conv_id}", produire)


@router.delete("/conversations/{conv_id}")
async def supprimer_conversation(conv_id: str, db: AsyncSession = Depends(get_db)):
    c = await db.get(Conversation, conv_id)
    if c:
        marquer(db, *[f"inbox:{p}" for p in c.participants or []], f"conv:{conv_id}")
        await db.delete(c)
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# Notifications, signalements, publicités, transactions, urgences
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/notifications")
async def notifications(non_lues: bool = False, limit: int = 100, offset: int = 0,
                        db: AsyncSession = Depends(get_db)):
    req = select(NotificationAdmin)
    if non_lues:
        req = req.where(NotificationAdmin.lu.is_(False))
    return await _liste(db, req.order_by(NotificationAdmin.created_at.desc()),
                        lambda n: vers_api(n, NotificationAdmin.CHAMPS), limit, offset)


@router.post("/notifications/{notif_id}/lu")
async def notification_lue(notif_id: str, db: AsyncSession = Depends(get_db)):
    n = await db.get(NotificationAdmin, notif_id)
    if n:
        n.lu = True
        marquer(db, f"notifs:{n.uid_prestataire}")
    return {"success": True}


@router.get("/signalements")
async def signalements(statut: str | None = None, limit: int = 100, offset: int = 0,
                       db: AsyncSession = Depends(get_db)):
    req = select(Signalement)
    if statut and statut != "tous":
        req = req.where(Signalement.statut == statut)
    return await _liste(db, req.order_by(Signalement.date_signalement.desc()),
                        lambda s: vers_api(s, Signalement.CHAMPS), limit, offset)


@router.patch("/signalements/{sig_id}")
async def modifier_signalement(sig_id: str, data: dict, db: AsyncSession = Depends(get_db)):
    s = await db.get(Signalement, sig_id)
    if s is None:
        raise HTTPException(404, "Signalement introuvable")
    if data.get("statut") not in (None, "en_attente", "traite", "rejete"):
        raise HTTPException(400, "Statut invalide")
    appliquer(s, data, Signalement.CHAMPS, autorises={"statut", "motifLibre"})
    return vers_api(s, Signalement.CHAMPS)


@router.delete("/signalements/{sig_id}")
async def supprimer_signalement(sig_id: str, db: AsyncSession = Depends(get_db)):
    await db.execute(delete(Signalement).where(Signalement.id == sig_id))
    return {"success": True}


@router.get("/publicites")
async def publicites(filtre: str | None = None, limit: int = 100, offset: int = 0,
                     db: AsyncSession = Depends(get_db)):
    req = select(Publicite)
    if filtre == "actives":
        req = req.where(Publicite.actif.is_(True), Publicite.expires_at > maintenant())
    elif filtre == "en_attente":
        req = req.where(Publicite.payment_pending.is_(True))
    return await _liste(db, req.order_by(Publicite.date_creation.desc()),
                        lambda p: vers_api(p, Publicite.CHAMPS), limit, offset)


@router.patch("/publicites/{pub_id}")
async def modifier_publicite(pub_id: str, data: dict, db: AsyncSession = Depends(get_db)):
    p = await db.get(Publicite, pub_id)
    if p is None:
        raise HTTPException(404, "Publicité introuvable")
    appliquer(p, data, Publicite.CHAMPS, interdits={"dateCreation", "createdAt"})
    marquer(db, "stories", f"mes_pubs:{p.prestataire_id}")
    apres_commit(db, lambda: cache.effacer_prefixe("pub:stories"), "cache_stories")
    return vers_api(p, Publicite.CHAMPS)


@router.delete("/publicites/{pub_id}")
async def supprimer_publicite(pub_id: str, db: AsyncSession = Depends(get_db)):
    p = await db.get(Publicite, pub_id)
    if p:
        liens = list(p.photos or []) + [p.video_url]
        apres_commit(db, lambda: fichiers.supprimer_liens(None, liens), "storage")
        marquer(db, "stories", f"mes_pubs:{p.prestataire_id}")
        apres_commit(db, lambda: cache.effacer_prefixe("pub:stories"), "cache_stories")
        await db.delete(p)
    return {"success": True}


@router.get("/transactions")
async def transactions(statut: str | None = None, type: str | None = None, uid: str | None = None,
                       limit: int = 100, offset: int = 0, db: AsyncSession = Depends(get_db)):
    req = select(Transaction)
    if statut:
        req = req.where(Transaction.statut == statut)
    if type:
        req = req.where(Transaction.type == type)
    if uid:
        req = req.where(Transaction.uid == uid)
    return await _liste(db, req.order_by(Transaction.created_at.desc()),
                        lambda t: vers_api(t, Transaction.CHAMPS), limit, offset)


@router.get("/urgences")
async def urgences(limit: int = 100, offset: int = 0, db: AsyncSession = Depends(get_db)):
    rep = await _liste(db, select(Urgence).order_by(Urgence.created_at.desc()),
                       lambda u: vers_api(u, Urgence.CHAMPS), limit, offset)
    ids = {u["uid"] for u in rep["items"] if u.get("uid")}
    infos = {}
    if ids:
        for uid, prenom, nom, tel, email in (await db.execute(select(
                Utilisateur.id, Utilisateur.prenom, Utilisateur.nom, Utilisateur.telephone,
                Utilisateur.email).where(Utilisateur.id.in_(ids)))).all():
            infos[uid] = {"nom": f"{prenom} {nom}".strip(), "telephone": tel, "email": email}
    rep["utilisateurs"] = infos
    return rep


# ═════════════════════════════════════════════════════════════════════════════
# Reprise des données Firestore (une fois, relançable sans doublon)
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/migration-firestore")
async def lancer_migration():
    if not a_compte_service():
        raise HTTPException(503, {"success": False, "error": "FIREBASE_CREDENTIALS absent sur l'API"})
    from app.services import migration_firestore
    from app.services.fond import lancer
    lancer(migration_firestore.migrer(), "migration_firestore")
    return {"success": True, "message": "Migration lancée. Suivi : GET /admin/migration-firestore"}


@router.get("/migration-firestore")
async def etat_migration():
    from app.services import migration_firestore
    return await migration_firestore.etat()
