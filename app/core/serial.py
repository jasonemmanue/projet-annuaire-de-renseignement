# app/core/serial.py
# ─────────────────────────────────────────────────────────────────────────────
# Conversion lignes SQL ↔ JSON de l'API.
#
# L'API renvoie les MÊMES noms de champs que les anciens documents Firestore
# (titre, uid_prestataire, isSponsored, createdAt…) : l'app Flutter et le
# dashboard gardent leurs modèles, seules les dates changent de forme (texte
# ISO 8601 UTC au lieu de Timestamp).
#
# Chaque modèle déclare CHAMPS = [(clé_api, attribut, type), …] :
#   s texte · f nombre · i entier · b booléen · d date · j JSON
#   u lien de fichier (chemin interne → adresse complète à la lecture)
# ─────────────────────────────────────────────────────────────────────────────
from __future__ import annotations

import secrets
import string
from datetime import datetime, timezone
from typing import Any, Iterable

from app.core.config import settings

_ALPHABET = string.ascii_letters + string.digits
PREFIXE_FICHIER = "/api/v1/fichiers/"

# Base publique de la requête en cours (posée par un middleware) : sert quand
# PUBLIC_BASE_URL n'est pas réglée.
_base_requete: str = ""


def nouvel_id(n: int = 20) -> str:
    """Identifiant aléatoire au format des identifiants Firestore."""
    return "".join(secrets.choice(_ALPHABET) for _ in range(n))


def maintenant() -> datetime:
    return datetime.now(timezone.utc)


def poser_base_requete(base: str) -> None:
    global _base_requete
    _base_requete = base.rstrip("/")


def base_publique() -> str:
    return (settings.PUBLIC_BASE_URL or _base_requete).rstrip("/")


def lien_public(v: Any) -> Any:
    """Chemin interne d'un fichier → adresse complète (les liens externes,
    ex. anciennes URL Firebase Storage, sont rendus tels quels)."""
    if isinstance(v, str) and v.startswith(PREFIXE_FICHIER):
        return base_publique() + v
    if isinstance(v, list):
        return [lien_public(x) for x in v]
    return v


def lien_interne(v: Any) -> Any:
    """Adresse complète d'un fichier de l'API → chemin interne (stockage)."""
    if isinstance(v, str):
        i = v.find(PREFIXE_FICHIER)
        if i > 0:
            return v[i:]
        return v
    if isinstance(v, list):
        return [lien_interne(x) for x in v]
    return v


# ─── Dates ───────────────────────────────────────────────────────────────────

def date_vers_texte(d: datetime | None) -> str | None:
    if d is None:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def texte_vers_date(v: Any) -> datetime | None:
    """Accepte : texte ISO, millisecondes epoch, {seconds, nanoseconds}
    (Timestamp Firestore sérialisé), {_seconds} ou datetime."""
    if v is None or v == "":
        return None
    if isinstance(v, datetime):
        return v if v.tzinfo else v.replace(tzinfo=timezone.utc)
    if isinstance(v, (int, float)):
        secondes = v / 1000 if v > 1e11 else v
        return datetime.fromtimestamp(secondes, tz=timezone.utc)
    if isinstance(v, dict):
        s = v.get("seconds", v.get("_seconds"))
        if s is not None:
            return datetime.fromtimestamp(float(s), tz=timezone.utc)
        return None
    if isinstance(v, str):
        t = v.strip().replace("Z", "+00:00")
        try:
            d = datetime.fromisoformat(t)
        except ValueError:
            return None
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    return None


# ─── Conversion par type ─────────────────────────────────────────────────────

def _entree(v: Any, t: str) -> Any:
    if v is None:
        return None
    if t == "s":
        return str(v)
    if t == "f":
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    if t == "i":
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return None
    if t == "b":
        if isinstance(v, str):
            return v.strip().lower() in ("1", "true", "oui", "yes")
        return bool(v)
    if t == "d":
        return texte_vers_date(v)
    if t == "u":
        return lien_interne(v)
    return v  # j


def _sortie(v: Any, t: str) -> Any:
    if t == "d":
        return date_vers_texte(v)
    if t == "u":
        return lien_public(v)
    return v


def vers_api(obj: Any, champs: Iterable[tuple[str, str, str]], id_cle: str = "id") -> dict:
    """Ligne SQL → dict JSON (champs libres `extra` d'abord, typés ensuite)."""
    out: dict[str, Any] = {}
    extra = getattr(obj, "extra", None)
    if isinstance(extra, dict):
        out.update(extra)
    if id_cle:
        out[id_cle] = getattr(obj, "id", None)
    for cle, attr, t in champs:
        out[cle] = _sortie(getattr(obj, attr, None), t)
    return out


def appliquer(
    obj: Any,
    data: dict,
    champs: Iterable[tuple[str, str, str]],
    autorises: set[str] | None = None,
    extra_libre: bool = False,
    interdits: set[str] | None = None,
) -> list[str]:
    """Copie les clés de `data` sur la ligne. Renvoie les clés appliquées.

    - `autorises` : liste blanche des clés API acceptées (None = toutes) ;
    - `interdits` : clés refusées en silence (champs gérés par le serveur) ;
    - `extra_libre` : une clé inconnue va dans la colonne JSON `extra`.
    """
    carte = {cle: (attr, t) for cle, attr, t in champs}
    faits: list[str] = []
    extra = dict(getattr(obj, "extra", None) or {}) if extra_libre else None
    for cle, v in (data or {}).items():
        if cle in ("id",) or (interdits and cle in interdits):
            continue
        if autorises is not None and cle not in autorises:
            continue
        if cle in carte:
            attr, t = carte[cle]
            setattr(obj, attr, _entree(v, t))
            faits.append(cle)
        elif extra is not None:
            extra[cle] = v
            faits.append(cle)
    if extra is not None:
        obj.extra = extra
    return faits
