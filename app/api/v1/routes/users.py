# app/api/v1/routes/users.py
# Profil de l'utilisateur connecté + profil public d'un prestataire.
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.dependencies import utilisateur_courant
from app.core.serial import appliquer, vers_api
from app.db.session import apres_commit, get_db
from app.models.models import Utilisateur

router = APIRouter(prefix="/users", tags=["Utilisateurs"])

# Ce que l'utilisateur peut changer lui-même (jamais rôle, premium, gratuit…).
_MODIFIABLES = {"nom", "prenom", "telephone", "email", "photoUrl", "notifMessages", "notifModeration",
                "notifFinSponsor", "fcmToken"}


def profil(u: Utilisateur) -> dict:
    d = vers_api(u, Utilisateur.CHAMPS)
    d.pop("fcmToken", None)
    return d


@router.get("/me")
async def moi(user: Utilisateur = Depends(utilisateur_courant)):
    return profil(user)


@router.put("/me")
async def modifier_moi(data: dict, db: AsyncSession = Depends(get_db),
                       user: Utilisateur = Depends(utilisateur_courant)):
    faits = appliquer(user, data, Utilisateur.CHAMPS, autorises=_MODIFIABLES)
    if "fcmToken" in faits and user.fcm_token == "":
        user.fcm_token = None
    await db.flush()
    uid = user.id
    apres_commit(db, lambda: cache.effacer_prefixe(f"pub:user:{uid}"), "cache_profil")
    return profil(user)


@router.put("/me/fcm")
async def jeton_fcm(data: dict, db: AsyncSession = Depends(get_db),
                    user: Utilisateur = Depends(utilisateur_courant)):
    """Enregistre (ou efface avec null) le jeton de notifications push."""
    jeton = (data or {}).get("token") or None
    user.fcm_token = jeton
    await db.flush()
    return {"success": True}


@router.get("/{uid}/public")
async def profil_public(uid: str, request: Request, db: AsyncSession = Depends(get_db)):
    """Nom, photo et téléphone affichés aux visiteurs (contact prestataire)."""
    cle = f"pub:user:{uid}"
    en_cache = await cache.lire_json(cle)
    if en_cache:
        return en_cache
    u = await db.get(Utilisateur, uid)
    if u is None:
        raise HTTPException(404, "Utilisateur introuvable")
    d = {"uid": u.id, "id": u.id, "prenom": u.prenom, "nom": u.nom, "telephone": u.telephone,
         "photoUrl": vers_api(u, Utilisateur.CHAMPS)["photoUrl"], "role": u.role,
         "isVerifie": u.is_verifie}
    await cache.ecrire_json(cle, d, 300)
    return d
