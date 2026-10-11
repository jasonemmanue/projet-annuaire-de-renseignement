# app/api/v1/routes/divers.py
# Favoris, signalements, notifications du prestataire, alertes urgence.
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.core import cache
from app.core.dependencies import Appelant, appelant, compte_requis, utilisateur_courant
from app.core.serial import appliquer, date_vers_texte, maintenant, nouvel_id, vers_api
from app.db.session import get_db, marquer
from app.models.models import Favori, NotificationAdmin, Signalement, Urgence, Utilisateur

router = APIRouter(tags=["Divers"])


# ═════════════════════════════════════════════════════════════════════════════
# Favoris (compte connecté ; les visiteurs gardent les leurs sur le téléphone)
# ═════════════════════════════════════════════════════════════════════════════

def _favori(f: Favori) -> dict:
    d = dict(f.donnees or {})
    d["logementId"] = f.logement_id
    d["addedAt"] = date_vers_texte(f.added_at)
    return d


@router.get("/favoris")
async def favoris(request: Request, db: AsyncSession = Depends(get_db),
                  user: Utilisateur = Depends(utilisateur_courant)):
    async def produire():
        lignes = (await db.execute(select(Favori).where(Favori.utilisateur_id == user.id)
                                   .order_by(Favori.added_at.desc()).limit(1000))).scalars().all()
        return {"items": [_favori(f) for f in lignes]}
    return await versionne(request, f"favoris:{user.id}", produire)


@router.put("/favoris/{logement_id}")
async def ajouter_favori(logement_id: str, data: dict, db: AsyncSession = Depends(get_db),
                         user: Utilisateur = Depends(utilisateur_courant)):
    donnees = {k: v for k, v in (data or {}).items() if k not in ("logementId", "addedAt")}
    await db.execute(pg_insert(Favori).values(
        utilisateur_id=user.id, logement_id=logement_id, donnees=donnees, added_at=maintenant())
        .on_conflict_do_update(index_elements=["utilisateur_id", "logement_id"],
                               set_={"donnees": donnees}))
    marquer(db, f"favoris:{user.id}")
    return {"success": True}


@router.post("/favoris/fusion")
async def fusionner_favoris(data: dict, db: AsyncSession = Depends(get_db),
                            user: Utilisateur = Depends(utilisateur_courant)):
    """Favoris enregistrés hors connexion → compte (à la connexion)."""
    for item in ((data or {}).get("items") or [])[:500]:
        lid = item.get("logementId")
        if not lid:
            continue
        donnees = {k: v for k, v in item.items() if k not in ("logementId", "addedAt")}
        await db.execute(pg_insert(Favori).values(
            utilisateur_id=user.id, logement_id=lid, donnees=donnees, added_at=maintenant())
            .on_conflict_do_nothing())
    marquer(db, f"favoris:{user.id}")
    return {"success": True}


@router.delete("/favoris/{logement_id}")
async def retirer_favori(logement_id: str, db: AsyncSession = Depends(get_db),
                         user: Utilisateur = Depends(utilisateur_courant)):
    await db.execute(delete(Favori).where(Favori.utilisateur_id == user.id,
                                          Favori.logement_id == logement_id))
    marquer(db, f"favoris:{user.id}")
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# Signalements (ouverts à tous, visiteurs compris)
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/signalements")
async def signaler(data: dict, request: Request, db: AsyncSession = Depends(get_db),
                   qui: Appelant = Depends(appelant)):
    ip = request.client.host if request.client else "?"
    if await cache.depasse_limite(f"signal:{ip}", 10, 3600):
        raise HTTPException(429, "Trop de signalements, réessayez plus tard.")
    s = Signalement(id=nouvel_id(), statut="en_attente", extra={}, date_signalement=maintenant())
    appliquer(s, data, Signalement.CHAMPS, autorises={"logementId", "logementTitre", "motif",
                                                      "motifLibre", "signaleParType"})
    if not s.logement_id or not s.motif:
        raise HTTPException(400, "logementId et motif requis")
    s.signale_par = qui.id
    db.add(s)
    marquer(db, "admin_signalements")
    return vers_api(s, Signalement.CHAMPS)


# ═════════════════════════════════════════════════════════════════════════════
# Notifications du prestataire (nouvelles publications validées)
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/notifications")
async def mes_notifications(request: Request, db: AsyncSession = Depends(get_db),
                            user: Utilisateur = Depends(compte_requis)):
    async def produire():
        lignes = (await db.execute(select(NotificationAdmin)
                                   .where(NotificationAdmin.uid_prestataire == user.id)
                                   .order_by(NotificationAdmin.created_at.desc()).limit(50))).scalars().all()
        return {"items": [vers_api(n, NotificationAdmin.CHAMPS) for n in lignes]}
    return await versionne(request, f"notifs:{user.id}", produire)


@router.post("/notifications/{notif_id}/lu")
async def notification_lue(notif_id: str, db: AsyncSession = Depends(get_db),
                           user: Utilisateur = Depends(compte_requis)):
    await db.execute(update(NotificationAdmin).where(
        NotificationAdmin.id == notif_id, NotificationAdmin.uid_prestataire == user.id).values(lu=True))
    marquer(db, f"notifs:{user.id}")
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# Alertes prioritaires (urgences) du visiteur — session Firebase anonyme
# ═════════════════════════════════════════════════════════════════════════════

_URGENCE_MODIF = {"typeBien", "description", "prixMin", "prixMax"}


@router.get("/urgences")
async def mes_urgences(request: Request, db: AsyncSession = Depends(get_db),
                       user: Utilisateur = Depends(utilisateur_courant)):
    async def produire():
        lignes = (await db.execute(select(Urgence).where(Urgence.uid == user.id)
                                   .order_by(Urgence.created_at.desc()).limit(100))).scalars().all()
        return {"items": [vers_api(u, Urgence.CHAMPS) for u in lignes]}
    return await versionne(request, f"urgences:{user.id}", produire)


@router.post("/urgences")
async def creer_urgence(data: dict, db: AsyncSession = Depends(get_db),
                        user: Utilisateur = Depends(utilisateur_courant)):
    u = Urgence(id=nouvel_id(), uid=user.id, actif=False, payment_pending=True, extra={},
                created_at=maintenant())
    appliquer(u, data, Urgence.CHAMPS, autorises=_URGENCE_MODIF)
    if not u.type_bien:
        raise HTTPException(400, "Type de bien requis")
    db.add(u)
    marquer(db, f"urgences:{user.id}", "admin_urgences")
    return vers_api(u, Urgence.CHAMPS)


@router.patch("/urgences/{urgence_id}")
async def modifier_urgence(urgence_id: str, data: dict, db: AsyncSession = Depends(get_db),
                           user: Utilisateur = Depends(utilisateur_courant)):
    u = await db.get(Urgence, urgence_id)
    if u is None or u.uid != user.id:
        raise HTTPException(404, "Alerte introuvable")
    appliquer(u, data, Urgence.CHAMPS, autorises=_URGENCE_MODIF)
    marquer(db, f"urgences:{user.id}", "admin_urgences")
    return vers_api(u, Urgence.CHAMPS)


@router.delete("/urgences/{urgence_id}")
async def supprimer_urgence(urgence_id: str, db: AsyncSession = Depends(get_db),
                            user: Utilisateur = Depends(utilisateur_courant)):
    await db.execute(delete(Urgence).where(Urgence.id == urgence_id, Urgence.uid == user.id))
    marquer(db, f"urgences:{user.id}", "admin_urgences")
    return {"success": True}
