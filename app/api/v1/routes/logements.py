# app/api/v1/routes/logements.py
# ─────────────────────────────────────────────────────────────────────────────
# Annonces (biens immobiliers et fiches de services).
#
# Règles tenues PAR LE SERVEUR (avant : dans l'app, contournables) :
#   • l'état d'une annonce (disponible, visibleAdmin, paymentPending, dates
#     d'expiration, sponsoring, vérification, compteurs) ne se règle pas par
#     une simple modification : création, paiement, activation gratuite
#     (compte offert) ou admin ;
#   • une annonce bloquée par l'admin ne peut pas être rendue visible ;
#   • un bien immobilier standard expiré ne se réactive qu'en repayant.
#
# Montée en charge : la liste publique est servie depuis Redis (30 s), les
# compteurs de vues sont incrémentés en SQL atomique (pas de lecture-écriture).
# ─────────────────────────────────────────────────────────────────────────────
import hashlib
import json
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import and_, case, delete, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import limite, versionne
from app.core import cache
from app.core.dependencies import compte_requis
from app.core.serial import appliquer, maintenant, nouvel_id, vers_api
from app.db.session import apres_commit, get_db, marquer
from app.models.models import Conversation, Favori, Logement, Utilisateur, VueJournaliere
from app.services import annonces, fichiers, tarifs

router = APIRouter(prefix="/logements", tags=["Annonces"])

# Champs de contenu que le prestataire peut écrire.
CONTENU = {
    "titre", "description", "prix", "typeLocation", "typeBien", "grade", "ville", "quartier",
    "latitude", "longitude", "photos", "surface", "nbPieces", "equipements",
    "prestatireNom", "prestatirePhone", "prestatirePhoto", "documentPdf",
    "heureOuverture", "heureFermeture", "joursGarde",
}
# Champs gérés par le serveur : jamais acceptés d'un prestataire.
GERES = {
    "uid_prestataire", "prestatireId", "estVerifie", "isSponsored", "estSponsorie",
    "sponsoredUntil", "sponsoredAt", "visibleAdmin", "paymentPending", "disponible",
    "publicationExpiry", "visibiliteExpiry", "vues", "nbVues", "contacts",
    "vues_milestones_notified", "createdAt", "updatedAt",
}


def api(l: Logement) -> dict:
    d = vers_api(l, Logement.CHAMPS)
    d["visibleAdmin"] = l.visible_admin_effectif
    return d


def _visible_visiteur():
    return and_(
        Logement.disponible.is_(True),
        Logement.payment_pending.is_(False),
        or_(Logement.visible_admin.is_(True),
            and_(Logement.visible_admin.is_(None), Logement.type_bien != "Pharmacie")),
    )


def _priorite():
    """0 = sponsorisé actif · 1 = publication active · 2 = expirée."""
    t = maintenant()
    return case(
        (and_(Logement.is_sponsored.is_(True),
              or_(Logement.sponsored_until.is_(None), Logement.sponsored_until > t)), 0),
        (or_(Logement.type_bien == "Pharmacie", Logement.publication_expiry.is_(None),
             Logement.publication_expiry > t), 1),
        else_=2,
    )


async def _charger(db: AsyncSession, logement_id: str, verrou: bool = False) -> Logement:
    l = await db.get(Logement, logement_id, with_for_update=verrou)
    if l is None:
        raise HTTPException(404, "Annonce introuvable")
    return l


def _proprietaire(l: Logement, user: Utilisateur) -> None:
    if l.uid_prestataire != user.id and user.role != "admin":
        raise HTTPException(403, "Cette annonce ne vous appartient pas")


# ═════════════════════════════════════════════════════════════════════════════
# Lecture publique
# ═════════════════════════════════════════════════════════════════════════════

@router.get("")
async def lister(
    ville: str | None = None,
    typeBien: str | None = None,
    typeLocation: str | None = None,
    prixMin: float | None = None,
    prixMax: float | None = None,
    q: str | None = Query(None, max_length=120),
    latMin: float | None = None, latMax: float | None = None,
    lngMin: float | None = None, lngMax: float | None = None,
    sponsorises: bool = False,
    limit: int = 100,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """Annonces visibles par les visiteurs, triées par priorité
    (sponsorisées, puis actives, puis expirées) puis par date."""
    n = max(1, min(limit or 100, 500))
    params = {k: v for k, v in dict(ville=ville, typeBien=typeBien, typeLocation=typeLocation,
              prixMin=prixMin, prixMax=prixMax, q=q, latMin=latMin, latMax=latMax,
              lngMin=lngMin, lngMax=lngMax, sponsorises=sponsorises, n=n,
              offset=max(offset, 0)).items() if v not in (None, "", False)}
    cle = "pub:logements:" + hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()
    en_cache = await cache.lire_json(cle)
    if en_cache is not None:
        return en_cache

    conds = [_visible_visiteur()]
    if ville:
        conds.append(Logement.ville == ville)
    if typeBien:
        conds.append(Logement.type_bien == typeBien)
    if typeLocation:
        conds.append(Logement.type_location == typeLocation)
    if prixMin is not None:
        conds.append(Logement.prix >= prixMin)
    if prixMax is not None:
        conds.append(Logement.prix <= prixMax)
    if None not in (latMin, latMax, lngMin, lngMax):
        conds += [Logement.latitude.between(latMin, latMax), Logement.longitude.between(lngMin, lngMax)]
    if q:
        motif = f"%{q.strip()}%"
        conds.append(or_(Logement.titre.ilike(motif), Logement.quartier.ilike(motif),
                         Logement.ville.ilike(motif), Logement.type_bien.ilike(motif),
                         Logement.description.ilike(motif)))
    if sponsorises:
        conds += [Logement.is_sponsored.is_(True), Logement.sponsored_until > maintenant()]
    req = (select(Logement).where(*conds)
           .order_by(_priorite(), Logement.created_at.desc()).offset(max(offset, 0)).limit(n + 1))
    lignes = (await db.execute(req)).scalars().all()
    items = [api(l) for l in lignes[:n]]
    rep = {"items": items, "suivant": (offset + n) if len(lignes) > n else None}
    await cache.ecrire_json(cle, rep, 30)
    return rep


@router.get("/sponsorises")
async def sponsorises(limit: int = 3, db: AsyncSession = Depends(get_db)):
    # Appel direct : les valeurs par défaut Query(...) ne sont pas résolues, q doit être passé.
    return await lister(q=None, sponsorises=True, limit=limite(limit, 3), db=db)


@router.get("/mes")
async def mes_logements(request: Request, db: AsyncSession = Depends(get_db),
                        user: Utilisateur = Depends(compte_requis)):
    """Annonces du prestataire connecté (tous états). Polling : ?v=…"""
    async def produire():
        lignes = (await db.execute(select(Logement).where(Logement.uid_prestataire == user.id)
                                   .order_by(Logement.created_at.desc()).limit(500))).scalars().all()
        return {"items": [api(l) for l in lignes]}
    return await versionne(request, f"mes_logements:{user.id}", produire)


@router.get("/mes/statistiques")
async def statistiques(db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(compte_requis)):
    lignes = (await db.execute(select(Logement).where(Logement.uid_prestataire == user.id))).scalars().all()
    tv = sum(l.vues or 0 for l in lignes)
    tc = sum(l.contacts or 0 for l in lignes)
    par = [{"id": l.id, "titre": l.titre or "Sans titre", "vues": l.vues or 0,
            "contacts": l.contacts or 0, "photoUrl": api(l)["photos"][0] if l.photos else None}
           for l in lignes]
    par.sort(key=lambda x: x["vues"], reverse=True)
    return {
        "totalVues": tv, "totalContacts": tc, "totalAnnonces": len(lignes),
        "totalAnnoncesSponsorisees": sum(1 for l in lignes if l.is_sponsored),
        "tauxConversion": (tc / tv * 100.0) if tv else 0.0,
        "meilleurAnnonce": par[0] if par else None,
        "vuesParAnnonce": par[:5],
    }


@router.get("/{logement_id}")
async def detail(logement_id: str, db: AsyncSession = Depends(get_db)):
    cle = f"pub:logements:un:{logement_id}"
    en_cache = await cache.lire_json(cle)
    if en_cache:
        return en_cache
    d = api(await _charger(db, logement_id))
    await cache.ecrire_json(cle, d, 20)
    return d


@router.get("/{logement_id}/evolution-vues")
async def evolution_vues(logement_id: str, jours: int = 7, db: AsyncSession = Depends(get_db),
                         user: Utilisateur = Depends(compte_requis)):
    l = await _charger(db, logement_id)
    _proprietaire(l, user)
    jours = max(1, min(jours, 90))
    debut = date.today() - timedelta(days=jours - 1)
    lignes = dict((await db.execute(select(VueJournaliere.jour, VueJournaliere.vues).where(
        VueJournaliere.logement_id == logement_id, VueJournaliere.jour >= debut))).all())
    return {"totalVues": l.vues or 0, "points": [
        {"date": (debut + timedelta(days=i)).isoformat(), "vues": lignes.get(debut + timedelta(days=i), 0)}
        for i in range(jours)]}


# ═════════════════════════════════════════════════════════════════════════════
# Compteurs publics (vues, contacts)
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/{logement_id}/vue")
async def compter_vue(logement_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    ip = request.client.host if request.client else "?"
    # Une vue par appareil et par annonce toutes les 10 minutes.
    if await cache.depasse_limite(f"vue:{logement_id}:{ip}:{request.headers.get('x-visiteur-id', '')}", 1, 600):
        return {"success": True, "comptee": False}
    res = await db.execute(update(Logement).where(Logement.id == logement_id)
                           .values(vues=Logement.vues + 1).returning(Logement.vues))
    apres = res.scalar_one_or_none()
    if apres is None:
        raise HTTPException(404, "Annonce introuvable")
    await db.execute(pg_insert(VueJournaliere).values(logement_id=logement_id, jour=date.today(), vues=1)
                     .on_conflict_do_update(index_elements=["logement_id", "jour"],
                                            set_={"vues": VueJournaliere.vues + 1}))
    apres_commit(db, lambda: annonces.verifier_seuils_vues(logement_id, apres - 1, apres), "seuils_vues")
    return {"success": True, "comptee": True, "vues": apres}


@router.post("/{logement_id}/contact")
async def compter_contact(logement_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    ip = request.client.host if request.client else "?"
    if await cache.depasse_limite(f"contact:{logement_id}:{ip}", 3, 600):
        return {"success": True}
    await db.execute(update(Logement).where(Logement.id == logement_id)
                     .values(contacts=Logement.contacts + 1))
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# Prestataire : créer, modifier, supprimer
# ═════════════════════════════════════════════════════════════════════════════

def _remplir_contact(l: Logement, user: Utilisateur) -> None:
    if not l.prestataire_nom:
        l.prestataire_nom = f"{user.prenom} {user.nom}".strip()
    if not l.prestataire_phone:
        l.prestataire_phone = user.telephone or ""
    if not l.prestataire_photo and user.photo_url:
        l.prestataire_photo = user.photo_url


@router.post("")
async def creer(data: dict, db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(compte_requis)):
    """Pharmacie : publiée tout de suite (gratuite ; approbation admin sauf
    compte offert). Autres types : brouillon en attente de paiement."""
    if user.role not in ("prestataire", "admin"):
        raise HTTPException(403, "Compte prestataire requis")
    l = Logement(id=nouvel_id(), uid_prestataire=user.id, extra={}, photos=[], equipements=[],
                 jours_garde=[], vues_milestones=[], vues=0, contacts=0)
    appliquer(l, data, Logement.CHAMPS, autorises=CONTENU)
    _remplir_contact(l, user)
    if not l.titre and not l.type_bien:
        raise HTTPException(400, "Titre ou type requis")
    l.is_sponsored = False
    if tarifs.est_pharmacie(l.type_bien):
        l.disponible, l.payment_pending = True, False
        l.visible_admin = bool(user.compte_gratuit)
    else:
        l.disponible, l.payment_pending, l.visible_admin = False, True, False
    db.add(l)
    await db.flush()
    if l.disponible and l.visible_admin_effectif:
        annonces.annonce_publiee(db, l.id, payee=False)
    annonces.annonce_modifiee(db, user.id)
    return api(l)


@router.patch("/{logement_id}")
async def modifier(logement_id: str, data: dict, db: AsyncSession = Depends(get_db),
                   user: Utilisateur = Depends(compte_requis)):
    """Contenu de l'annonce + bascule « disponible » (règles de visibilité)."""
    l = await _charger(db, logement_id, verrou=True)
    _proprietaire(l, user)
    appliquer(l, data, Logement.CHAMPS, autorises=CONTENU)
    if "disponible" in data:
        await _basculer_disponible(l, bool(data["disponible"]), user)
    await db.flush()
    _invalider_un(db, l)
    return api(l)


async def _basculer_disponible(l: Logement, voulu: bool, user: Utilisateur) -> None:
    if not voulu:
        l.disponible = False  # désactiver : toujours libre
        return
    if l.disponible:
        return
    gratuit = bool(user.compte_gratuit) or user.role == "admin"
    if not l.visible_admin_effectif and not gratuit:
        raise HTTPException(403, {"code": "admin_visibility_required",
                                  "error": "L'administrateur doit d'abord autoriser cette annonce."})
    if l.payment_pending and not gratuit:
        raise HTTPException(402, {"code": "paiement_requis", "error": "Paiement de publication requis."})
    t = maintenant()
    if tarifs.est_pharmacie(l.type_bien) or l.type_bien in tarifs.TYPES_FORFAIT:
        l.disponible = True
        if gratuit and not l.visible_admin_effectif:
            l.visible_admin = True
        return
    # Bien standard : libre tant que la période payée court, sinon repaiement.
    if l.publication_expiry and l.publication_expiry > t:
        l.disponible = True
        return
    if gratuit:
        l.disponible, l.visible_admin, l.payment_pending = True, True, False
        l.publication_expiry = t + timedelta(days=tarifs.PUBLICATION_DUREE_JOURS)
        return
    raise HTTPException(402, {"code": "paiement_requis", "error": "Republication payante requise."})


def _invalider_un(db: AsyncSession, l: Logement) -> None:
    lid = l.id
    apres_commit(db, lambda: cache.effacer_prefixe(f"pub:logements:un:{lid}"), "cache_logement")
    annonces.annonce_modifiee(db, l.uid_prestataire)


@router.post("/{logement_id}/activer-gratuit")
async def activer_gratuit(logement_id: str, db: AsyncSession = Depends(get_db),
                          user: Utilisateur = Depends(compte_requis)):
    """Compte offert : publie un brouillon sans paiement."""
    if not user.compte_gratuit and user.role != "admin":
        raise HTTPException(402, "Paiement requis")
    l = await _charger(db, logement_id, verrou=True)
    _proprietaire(l, user)
    t = maintenant()
    l.disponible, l.visible_admin, l.payment_pending = True, True, False
    if tarifs.est_visibilite(l.type_bien):
        l.visibilite_expiry = t + timedelta(days=tarifs.VISIBILITE_DUREE_JOURS)
    elif not tarifs.est_pharmacie(l.type_bien):
        l.publication_expiry = t + timedelta(days=tarifs.PUBLICATION_DUREE_JOURS)
    await db.flush()
    annonces.annonce_publiee(db, l.id, payee=False)
    _invalider_un(db, l)
    return api(l)


@router.post("/{logement_id}/sponsoriser-gratuit")
async def sponsoriser_gratuit(logement_id: str, data: dict, db: AsyncSession = Depends(get_db),
                              user: Utilisateur = Depends(compte_requis)):
    if not user.compte_gratuit and user.role != "admin":
        raise HTTPException(402, "Paiement requis")
    l = await _charger(db, logement_id, verrou=True)
    _proprietaire(l, user)
    code = (data or {}).get("duree") if (data or {}).get("duree") in tarifs.SPONSOR_DUREES else "1m"
    t = maintenant()
    l.is_sponsored, l.sponsored_at = True, t
    l.sponsored_until = t + timedelta(days=tarifs.SPONSOR_DUREES[code])
    await db.flush()
    _invalider_un(db, l)
    return api(l)


async def supprimer_logement(db: AsyncSession, l: Logement) -> None:
    """Annonce + photos + conversations liées + favoris."""
    liens = list(l.photos or []) + [l.document_pdf]
    apres_commit(db, lambda: fichiers.supprimer_liens(None, liens), "storage")
    convs = (await db.execute(select(Conversation.id, Conversation.participants)
                              .where(Conversation.logement_id == l.id))).all()
    if convs:
        await db.execute(delete(Conversation).where(Conversation.id.in_([c[0] for c in convs])))
    await db.execute(delete(Favori).where(Favori.logement_id == l.id))
    _invalider_un(db, l)
    marquer(db, *{f"inbox:{p}" for _, parts in convs for p in (parts or [])})
    await db.delete(l)


@router.delete("/{logement_id}")
async def supprimer(logement_id: str, db: AsyncSession = Depends(get_db),
                    user: Utilisateur = Depends(compte_requis)):
    l = await _charger(db, logement_id, verrou=True)
    _proprietaire(l, user)
    await supprimer_logement(db, l)
    return {"success": True}
