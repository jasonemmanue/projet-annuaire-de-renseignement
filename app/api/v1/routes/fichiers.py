# app/api/v1/routes/fichiers.py
# ─────────────────────────────────────────────────────────────────────────────
# Envoi et lecture des fichiers, rangés sur le volume Railway du service API.
# Le type vient des premiers octets du fichier, jamais de ce que déclare le
# client ; le nom est tiré au hasard et aucun chemin fourni n'est utilisé.
# Photos de CNI : lecture seulement par un lien signé de courte durée, donné
# à leur titulaire et aux administrateurs.
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import os
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.datastructures import UploadFile

from app.core import cache
from app.core.dependencies import Appelant, appelant
from app.core.serial import lien_public, lien_signe_valide
from app.db.session import get_db, valider
from app.services import fichiers

router = APIRouter(prefix="/fichiers", tags=["Fichiers"])

_CORPS_MAX = 105 * 1024 * 1024
_MORCEAU = 256 * 1024
_PLAGE = re.compile(r"bytes=(\d*)-(\d*)")


@router.post("")
async def envoyer(request: Request, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    """Formulaire multipart : `dossier` + `fichier`. Renvoie {success, url}."""
    try:
        taille = int(request.headers.get("content-length") or "")
    except ValueError:
        raise HTTPException(411, "Taille du fichier requise")
    if taille > _CORPS_MAX:
        raise HTTPException(413, "Fichier trop volumineux")
    if await cache.depasse_limite(f"envoi:{qui.id}", 120, 3600):
        raise HTTPException(429, "Trop d'envois, réessayez plus tard.")
    compte = qui.user is not None and not qui.user.anonyme
    # Un envoi peut durer plusieurs minutes sur réseau mobile : la connexion
    # SQL ne reste pas réservée pendant ce temps.
    await valider(db)
    forme = await request.form(max_files=1, max_fields=4)
    dossier, envoi = str(forme.get("dossier") or ""), forme.get("fichier")
    if dossier not in fichiers.AUTORISES or not isinstance(envoi, UploadFile):
        raise HTTPException(400, "Paramètres manquants")
    if dossier != "messages" and not compte:
        raise HTTPException(403, "Compte requis")
    try:
        chemin = await fichiers.enregistrer(dossier, envoi)
    except fichiers.FichierRefuse as e:
        raise HTTPException(e.statut, str(e))
    except OSError:
        raise HTTPException(507, "Stockage indisponible, réessayez plus tard.")
    return {"success": True, "url": lien_public(chemin)}


@router.api_route("/{chemin:path}", methods=["GET", "HEAD"])
async def lire(chemin: str, request: Request, exp: int = 0, sig: str = ""):
    """Les lecteurs vidéo (iOS surtout) exigent les requêtes par plage."""
    if not fichiers.chemin_valide(chemin):
        raise HTTPException(404, "Fichier introuvable")
    prive = chemin.startswith("cni/")
    if prive and not lien_signe_valide(chemin, exp, sig):
        raise HTTPException(403, "Lien expiré ou invalide")
    cible = fichiers.absolu(chemin)
    try:
        taille = (await asyncio.to_thread(os.stat, cible)).st_size
    except OSError:
        raise HTTPException(404, "Fichier introuvable")
    mime, en_ligne = fichiers.description(chemin)
    entetes = {
        "Accept-Ranges": "bytes",
        "X-Content-Type-Options": "nosniff",
        # Évite la compression globale, qui casserait les plages d'octets.
        "Content-Encoding": "identity",
        "Cache-Control": "private, no-store" if prive else "public, max-age=31536000, immutable",
        "Content-Disposition": "inline" if en_ligne else "attachment",
    }
    debut, fin, statut = 0, taille - 1, 200
    plage = _PLAGE.fullmatch(request.headers.get("range") or "")
    if plage and (plage[1] or plage[2]) and taille:
        if plage[1]:
            debut = int(plage[1])
            fin = min(int(plage[2]), taille - 1) if plage[2] else taille - 1
        else:
            debut = max(taille - int(plage[2]), 0)
        if debut > fin or debut >= taille:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{taille}"})
        statut = 206
        entetes["Content-Range"] = f"bytes {debut}-{fin}/{taille}"
    entetes["Content-Length"] = str(fin - debut + 1)
    if request.method == "HEAD":
        return Response(status_code=statut, media_type=mime, headers=entetes)

    async def flux():
        with open(cible, "rb") as f:
            f.seek(debut)
            reste = fin - debut + 1
            while reste > 0:
                bloc = await asyncio.to_thread(f.read, min(_MORCEAU, reste))
                if not bloc:
                    return
                reste -= len(bloc)
                yield bloc
    return StreamingResponse(flux(), status_code=statut, media_type=mime, headers=entetes)
