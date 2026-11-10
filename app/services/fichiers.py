# app/services/fichiers.py
# ─────────────────────────────────────────────────────────────────────────────
# Fichiers (photos, vidéos, documents) : rangés sur le volume Railway du
# service API (STOCKAGE_DIR). Les anciens fichiers restent sur Firebase Storage
# et gardent leur lien d'origine ; leur suppression passe par le compte de
# service Firebase.
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import logging
import os
import re
import secrets
import shutil
from pathlib import Path
from urllib.parse import unquote, urlsplit

from starlette.datastructures import UploadFile

from app.core.config import settings
from app.core.firebase import a_compte_service
from app.core.serial import PREFIXE_FICHIER

logger = logging.getLogger("fichiers")

MO = 1024 * 1024
TAILLE_MAX = {"image": 15 * MO, "video": 100 * MO, "audio": 30 * MO, "pdf": 30 * MO, "document": 30 * MO}
AUTORISES = {
    "logements": {"image", "pdf"},
    "profils": {"image"},
    "publicites": {"image", "video"},
    "messages": {"image", "video", "audio", "pdf", "document"},
    "cni": {"image"},
}
# extension → (type MIME, famille)
_TYPES = {
    "jpg": ("image/jpeg", "image"), "png": ("image/png", "image"), "webp": ("image/webp", "image"),
    "gif": ("image/gif", "image"), "heic": ("image/heic", "image"),
    "mp4": ("video/mp4", "video"), "mov": ("video/quicktime", "video"), "3gp": ("video/3gpp", "video"),
    "m4a": ("audio/mp4", "audio"), "mp3": ("audio/mpeg", "audio"),
    "pdf": ("application/pdf", "pdf"),
    "zip": ("application/octet-stream", "document"), "doc": ("application/octet-stream", "document"),
}
_CHEMIN = re.compile(r"(logements|profils|publicites|messages|cni)/[0-9a-f]{32}\.[a-z0-9]{2,4}")


class FichierRefuse(Exception):
    def __init__(self, message: str, statut: int = 415):
        super().__init__(message)
        self.statut = statut


def reconnaitre(e: bytes) -> str | None:
    """Extension déduite des premiers octets (le nom et le type déclarés par
    le client ne comptent pas)."""
    if e[:3] == b"\xff\xd8\xff":
        return "jpg"
    if e[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if e[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if e[:4] == b"RIFF" and e[8:12] == b"WEBP":
        return "webp"
    if e[:5] == b"%PDF-":
        return "pdf"
    if e[:4] == b"PK\x03\x04":
        return "zip"  # docx, xlsx, zip : toujours servis en téléchargement
    if e[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        return "doc"
    if e[4:8] == b"ftyp":
        marque = e[8:12]
        if marque in (b"heic", b"heix", b"mif1", b"msf1", b"hevc"):
            return "heic"
        if marque[:3] == b"M4A" or marque[:3] == b"M4B":
            return "m4a"
        if marque[:2] == b"qt":
            return "mov"
        return "3gp" if marque[:3] in (b"3gp", b"3g2") else "mp4"
    if e[:3] == b"ID3" or (len(e) > 1 and e[0] == 0xFF and e[1] & 0xE0 == 0xE0):
        return "mp3"
    return None


def chemin_valide(chemin: str) -> bool:
    return _CHEMIN.fullmatch(chemin or "") is not None


def absolu(chemin: str) -> Path:
    return Path(settings.STOCKAGE_DIR) / chemin


def description(chemin: str) -> tuple[str, bool]:
    """(type MIME, affichable directement)."""
    mime, famille = _TYPES.get(chemin.rsplit(".", 1)[-1], ("application/octet-stream", "document"))
    return mime, famille != "document"


def _ecrire(source, chemin: str) -> None:
    final = absolu(chemin)
    final.parent.mkdir(parents=True, exist_ok=True)
    partiel = final.with_suffix(".part")
    try:
        with open(partiel, "wb") as sortie:
            shutil.copyfileobj(source, sortie, MO)
        os.replace(partiel, final)
    finally:
        partiel.unlink(missing_ok=True)


async def enregistrer(dossier: str, envoi: UploadFile) -> str:
    """Contrôle et range le fichier. Renvoie son chemin interne."""
    entete = await envoi.read(32)
    await envoi.seek(0)
    ext = reconnaitre(entete)
    famille = _TYPES[ext][1] if ext else None
    if famille not in AUTORISES[dossier]:
        raise FichierRefuse("Type de fichier non accepté.")
    if (envoi.size or 0) > TAILLE_MAX[famille]:
        raise FichierRefuse("Fichier trop volumineux.", 413)
    chemin = f"{dossier}/{secrets.token_hex(16)}.{ext}"
    await asyncio.to_thread(_ecrire, envoi.file, chemin)
    return PREFIXE_FICHIER + chemin


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


def _supprimer_locaux(chemins: list[str]) -> None:
    for c in chemins:
        try:
            absolu(c).unlink(missing_ok=True)
        except OSError as e:
            logger.warning("suppression %s : %s", c, e)


async def supprimer_liens(_db, liens) -> None:
    liens = [x for x in (liens or []) if isinstance(x, str)]
    locaux = [c for c in (x[len(PREFIXE_FICHIER):] for x in liens if x.startswith(PREFIXE_FICHIER))
              if chemin_valide(c)]
    if locaux:
        await asyncio.to_thread(_supprimer_locaux, locaux)
    chemins = [c for c in (chemin_storage(x) for x in liens) if c]
    if not chemins or not a_compte_service():
        return
    try:
        await asyncio.to_thread(_supprimer, chemins)
    except Exception as e:  # noqa: BLE001
        logger.warning("suppression Storage : %s", e)
