# app/api/v1/routes/publicites.py
# Publicités des prestataires (stories affichées aux visiteurs).
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.core import cache
from app.core.dependencies import compte_requis
from app.core.serial import appliquer, maintenant, nouvel_id, vers_api
from app.db.session import apres_commit, get_db, marquer
from app.models.models import Publicite, Utilisateur
from app.services import fichiers, tarifs

router = APIRouter(prefix="/publicites", tags=["Publicités"])

_CONTENU = {"titre", "description", "photos", "videoUrl", "logementId", "logementTitre",
            "logementPhoto", "prestataireNom", "prestatairePhone", "prestatairePhoto"}


def api(p: Publicite) -> dict:
    return vers_api(p, Publicite.CHAMPS)


def _changement(db: AsyncSession, p: Publicite) -> None:
    marquer(db, "stories", f"mes_pubs:{p.prestataire_id}", "admin_publicites")
    apres_commit(db, lambda: cache.effacer_prefixe("pub:stories"), "cache_stories")


@router.get("/diffusables")
async def diffusables(request: Request, db: AsyncSession = Depends(get_db)):
    """Stories en cours de diffusion (actives, payées, non expirées)."""
    async def produire():
        en_cache = await cache.lire_json("pub:stories")
        if en_cache is not None:
            return {"items": en_cache}
        lignes = (await db.execute(select(Publicite).where(
            Publicite.actif.is_(True), Publicite.payment_pending.is_(False),
            Publicite.expires_at > maintenant()).order_by(Publicite.date_creation.desc())
            .limit(100))).scalars().all()
        items = [api(p) for p in lignes]
        await cache.ecrire_json("pub:stories", items, 60)
        return {"items": items}
    return await versionne(request, "stories", produire)


@router.get("/mes")
async def mes_publicites(request: Request, db: AsyncSession = Depends(get_db),
                         user: Utilisateur = Depends(compte_requis)):
    async def produire():
        lignes = (await db.execute(select(Publicite).where(Publicite.prestataire_id == user.id)
                                   .order_by(Publicite.date_creation.desc()).limit(200))).scalars().all()
        return {"items": [api(p) for p in lignes]}
    return await versionne(request, f"mes_pubs:{user.id}", produire)


@router.post("")
async def creer_brouillon(data: dict, db: AsyncSession = Depends(get_db),
                          user: Utilisateur = Depends(compte_requis)):
    """Brouillon en attente du paiement (500 XAF / 4 jours)."""
    p = Publicite(id=nouvel_id(), prestataire_id=user.id, actif=False, payment_pending=True,
                  photos=[], extra={}, date_creation=maintenant())
    appliquer(p, data, Publicite.CHAMPS, autorises=_CONTENU)
    if not p.prestataire_nom:
        p.prestataire_nom = f"{user.prenom} {user.nom}".strip()
    if not p.prestataire_phone:
        p.prestataire_phone = user.telephone or ""
    if not p.prestataire_photo:
        p.prestataire_photo = user.photo_url
    db.add(p)
    _changement(db, p)
    return api(p)


async def _a_moi(db: AsyncSession, pub_id: str, user: Utilisateur) -> Publicite:
    p = await db.get(Publicite, pub_id, with_for_update=True)
    if p is None:
        raise HTTPException(404, "Publicité introuvable")
    if p.prestataire_id != user.id and user.role != "admin":
        raise HTTPException(403, "Cette publicité ne vous appartient pas")
    return p


@router.patch("/{pub_id}")
async def modifier(pub_id: str, data: dict, db: AsyncSession = Depends(get_db),
                   user: Utilisateur = Depends(compte_requis)):
    """Modification gratuite du texte (et des médias)."""
    p = await _a_moi(db, pub_id, user)
    appliquer(p, data, Publicite.CHAMPS, autorises=_CONTENU)
    _changement(db, p)
    return api(p)


@router.post("/{pub_id}/activer-gratuit")
async def activer_gratuit(pub_id: str, db: AsyncSession = Depends(get_db),
                          user: Utilisateur = Depends(compte_requis)):
    if not user.compte_gratuit and user.role != "admin":
        raise HTTPException(402, "Paiement requis")
    p = await _a_moi(db, pub_id, user)
    p.actif, p.payment_pending = True, False
    p.expires_at = maintenant() + timedelta(days=tarifs.PUBLICITE_DUREE_JOURS)
    _changement(db, p)
    return api(p)


@router.delete("/{pub_id}")
async def supprimer(pub_id: str, db: AsyncSession = Depends(get_db),
                    user: Utilisateur = Depends(compte_requis)):
    p = await _a_moi(db, pub_id, user)
    liens = list(p.photos or []) + [p.video_url]
    apres_commit(db, lambda: fichiers.supprimer_liens(None, liens), "storage")
    _changement(db, p)
    await db.delete(p)
    return {"success": True}
