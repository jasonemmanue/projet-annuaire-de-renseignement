# app/services/fichiers.py
# ─────────────────────────────────────────────────────────────────────────────
# Les fichiers (photos, vidéos, documents) restent dans Firebase Storage :
# l'app les envoie directement et n'enregistre que leur adresse dans l'API.
# Ici : suppression des fichiers d'une annonce / publicité supprimée (avant,
# l'app le faisait elle-même), via le compte de service Firebase.
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import logging
from urllib.parse import unquote, urlsplit

from app.core.config import settings
from app.core.firebase import a_compte_service

logger = logging.getLogger("fichiers")


def chemin_storage(url: str | None) -> str | None:
    """https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<chemin encodé>?…
    → <chemin>. None pour tout autre lien."""
    if not url or "firebasestorage" not in url:
        return None
    morceaux = urlsplit(url).path.split("/o/", 1)
    return unquote(morceaux[1]) if len(morceaux) == 2 and morceaux[1] else None


def _supprimer(chemins: list[str]) -> None:
    from firebase_admin import storage
    bucket = storage.bucket(settings.FIREBASE_STORAGE_BUCKET)
    for c in chemins:
        try:
            bucket.blob(c).delete()
        except Exception as e:  # noqa: BLE001 — déjà supprimé, etc.
            logger.debug("suppression %s : %s", c, e)


async def supprimer_liens(_db, liens) -> None:
    chemins = [c for c in (chemin_storage(x) for x in (liens or [])) if c]
    if not chemins or not a_compte_service():
        return
    try:
        await asyncio.to_thread(_supprimer, chemins)
    except Exception as e:  # noqa: BLE001
        logger.warning("suppression Storage : %s", e)
