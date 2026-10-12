# app/api/v1/routes/users.py
# Profil de l'utilisateur connecté + profil public d'un prestataire.
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.dependencies import utilisateur_courant
from app.core.serial import appliquer, maintenant, vers_api
from app.db.session import apres_commit, get_db
from app.models.models import Logement, Utilisateur
from app.services import annonces

router = APIRouter(prefix="/users", tags=["Utilisateurs"])

# Ce que l'utilisateur peut changer lui-même (jamais rôle, premium, gratuit…).
_MODIFIABLES = {"nom", "prenom", "telephone", "email", "photoUrl", "notifMessages", "notifModeration",
                "notifFinSponsor", "fcmToken", "cniNumero", "cniRecto", "cniVerso"}
_CNI = {"cniNumero", "cniRecto", "cniVerso"}


def normaliser_telephone(numero: str | None) -> str:
    """Chiffres seuls avec indicatif : 6XXXXXXXX → 2376XXXXXXXX (Cameroun),
    0XXXXXXXXX → 2250XXXXXXXXX (Côte d'Ivoire)."""
    n = "".join(c for c in (numero or "") if c.isdigit())
    if n.startswith("00"):
        n = n[2:]
    if len(n) == 9:
        n = "237" + n
    elif len(n) == 10 and n.startswith("0"):
        n = "225" + n
    return n


async def telephone_pris(db: AsyncSession, numero: str, sauf_uid: str | None = None) -> bool:
    """Un numéro de téléphone = un seul compte (formats différents comparés)."""
    norm = normaliser_telephone(numero)
    if len(norm) < 8:
        return False
    req = select(Utilisateur.id, Utilisateur.telephone).where(
        Utilisateur.telephone.like(f"%{norm[-8:]}"), Utilisateur.anonyme.is_(False))
    for uid, tel in (await db.execute(req)).all():
        if uid != sauf_uid and normaliser_telephone(tel) == norm:
            return True
    return False


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
    if data.get("telephone") and normaliser_telephone(data["telephone"]) != normaliser_telephone(user.telephone):
        if await telephone_pris(db, str(data["telephone"]), sauf_uid=user.id):
            raise HTTPException(409, {"code": "telephone_utilise",
                                      "error": "Ce numéro de téléphone est déjà utilisé par un autre compte."})
    ancienne_photo = user.photo_url
    faits = appliquer(user, data, Utilisateur.CHAMPS, autorises=_MODIFIABLES)
    if "fcmToken" in faits and user.fcm_token == "":
        user.fcm_token = None
    if _CNI & set(faits) and user.cni_complete:
        user.cni_soumise_le = maintenant()
    # La photo de contact affichée sur les annonces suit la photo de profil.
    if "photoUrl" in faits and user.photo_url != ancienne_photo:
        await db.execute(update(Logement).where(Logement.uid_prestataire == user.id)
                         .values(prestataire_photo=user.photo_url))
        apres_commit(db, annonces.invalider_listes, "invalider_listes")
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


@router.get("/telephone-disponible")
async def telephone_disponible(numero: str, db: AsyncSession = Depends(get_db)):
    """Vérifié par l'app AVANT de créer le compte Firebase."""
    return {"disponible": not await telephone_pris(db, numero)}


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
