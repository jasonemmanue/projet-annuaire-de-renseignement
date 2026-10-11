# app/api/v1/routes/_commun.py
# Outils partagés par les routes : pagination par curseur et réponses
# « versionnées » (polling léger, voir app/core/cache.py).
import base64
import json
from typing import Any, Awaitable, Callable

from fastapi import HTTPException, Request

from app.core import cache

TAILLE_MAX = 200


def limite(n: int | None, defaut: int = 50) -> int:
    if not n or n <= 0:
        return defaut
    return min(n, TAILLE_MAX)


def encoder_curseur(*valeurs: Any) -> str:
    return base64.urlsafe_b64encode(json.dumps(valeurs, default=str).encode()).decode()


def decoder_curseur(c: str | None) -> list | None:
    if not c:
        return None
    try:
        return json.loads(base64.urlsafe_b64decode(c.encode()).decode())
    except Exception:  # noqa: BLE001
        raise HTTPException(400, "Curseur invalide")


async def versionne(request: Request, cle: str, produire: Callable[[], Awaitable[dict]]) -> dict:
    """Si le client envoie ?v=<version connue> et que rien n'a changé depuis,
    répond {"inchange": true} sans requête SQL. Sinon renvoie les données
    avec la version courante dans "v"."""
    v = await cache.version(cle)
    if v and request.query_params.get("v") == v:
        return {"inchange": True, "v": v}
    data = await produire()
    data["v"] = v
    return data
