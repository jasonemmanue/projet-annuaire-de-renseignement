# app/core/dependencies.py
# ─────────────────────────────────────────────────────────────────────────────
# Qui appelle l'API ?
#   • un compte Firebase (prestataire, admin, ou visiteur en session anonyme) :
#     en-tête  Authorization: Bearer <jeton d'identité Firebase>
#   • un visiteur sans compte (messagerie) : en-tête  X-Visiteur-Id:
#     visiteur_<uuid v4> (identifiant aléatoire gardé par l'app).
#
# Le profil (table utilisateurs) est créé au premier appel d'un compte, comme
# le faisait l'app avec Firestore.
# ─────────────────────────────────────────────────────────────────────────────
import re
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.firebase import verifier_jeton
from app.db.session import get_db
from app.models.models import Utilisateur

_VISITEUR = re.compile(r"^visiteur_[0-9a-fA-F-]{16,64}$")


@dataclass
class Appelant:
    id: str
    user: Utilisateur | None = None

    @property
    def est_visiteur(self) -> bool:
        return self.user is None

    @property
    def est_admin(self) -> bool:
        return bool(self.user and self.user.role == "admin")


def _jeton(request: Request) -> str | None:
    h = request.headers.get("authorization") or ""
    if h.lower().startswith("bearer "):
        j = h[7:].strip()
        return j or None
    return None


async def _charger(db: AsyncSession, claims: dict) -> Utilisateur:
    uid = claims["uid"]
    user = await db.get(Utilisateur, uid)
    anonyme = (claims.get("firebase") or {}).get("sign_in_provider") == "anonymous"
    email = (claims.get("email") or "").strip().lower() or None
    if user is None:
        # INSERT … ON CONFLICT : deux premières requêtes simultanées ne
        # créent pas deux profils.
        await db.execute(pg_insert(Utilisateur).values(
            id=uid, email=email, nom="", prenom="", telephone=claims.get("phone_number") or "",
            role="client" if anonyme else "prestataire", anonyme=anonyme, extra={},
            is_verifie=False, is_premium=False, phone_verified=False, compte_gratuit=False,
            notif_messages=True, suspendu=False,
        ).on_conflict_do_nothing(index_elements=["id"]))
        await db.flush()
        user = await db.get(Utilisateur, uid)
    # Administrateurs déclarés dans ADMIN_EMAILS (Railway).
    if email and email in settings.admin_emails and user.role != "admin":
        user.role = "admin"
    if email and not user.email:
        user.email = email
    return user


async def utilisateur_optionnel(
    request: Request, db: AsyncSession = Depends(get_db),
) -> Utilisateur | None:
    jeton = _jeton(request)
    if not jeton:
        return None
    try:
        claims = await verifier_jeton(jeton)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session invalide ou expirée")
    user = await _charger(db, claims)
    if user.suspendu:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte suspendu")
    request.state.uid = user.id
    return user


async def utilisateur_courant(
    user: Utilisateur | None = Depends(utilisateur_optionnel),
) -> Utilisateur:
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentification requise",
                            headers={"WWW-Authenticate": "Bearer"})
    return user


async def compte_requis(user: Utilisateur = Depends(utilisateur_courant)) -> Utilisateur:
    """Compte réel (pas une session anonyme de visiteur)."""
    if user.anonyme:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte prestataire requis")
    return user


async def admin_requis(user: Utilisateur = Depends(utilisateur_courant)) -> Utilisateur:
    if user.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Accès réservé aux administrateurs")
    return user


async def appelant(
    user: Utilisateur | None = Depends(utilisateur_optionnel),
    x_visiteur_id: str | None = Header(default=None),
) -> Appelant:
    """Compte Firebase OU visiteur identifié par X-Visiteur-Id."""
    if user is not None and not user.anonyme:
        return Appelant(id=user.id, user=user)
    if x_visiteur_id and _VISITEUR.match(x_visiteur_id):
        return Appelant(id=x_visiteur_id)
    if user is not None:
        return Appelant(id=user.id, user=user)
    raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Identification requise")
