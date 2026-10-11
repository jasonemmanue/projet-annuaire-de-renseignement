# app/core/cache.py
# ─────────────────────────────────────────────────────────────────────────────
# Redis : tout ce qui permet de tenir des dizaines de milliers d'utilisateurs.
#
#  • Cache court des réponses publiques (liste des annonces, stories) : des
#    milliers de visiteurs qui ouvrent l'accueil = une seule requête SQL par
#    période de cache.
#  • Versions : chaque conversation / boîte de réception / liste porte un
#    compteur incrémenté à chaque changement. Les écrans qui « écoutent »
#    (ancien snapshot Firestore) interrogent l'API avec la version connue ;
#    tant que rien ne bouge, l'API répond « inchangé » sans toucher à la base.
#  • Limitation de débit (anti-abus) et verrous des tâches planifiées (une
#    seule exécution quand plusieurs processus tournent).
#
# Redis absent ou en panne : chaque fonction se replie sans lever (pas de
# cache, versions toujours « changées », pas de limitation). L'API reste juste.
# ─────────────────────────────────────────────────────────────────────────────
import json
import logging
from typing import Any

import redis.asyncio as aioredis

from app.core.config import settings

logger = logging.getLogger("cache")
_client: aioredis.Redis | None = None


def client() -> aioredis.Redis | None:
    global _client
    if _client is None and settings.REDIS_URL:
        _client = aioredis.from_url(
            settings.REDIS_URL, decode_responses=True,
            socket_timeout=2, socket_connect_timeout=2, health_check_interval=30,
        )
    return _client


async def lire_json(cle: str) -> Any | None:
    r = client()
    if not r:
        return None
    try:
        brut = await r.get(cle)
        return json.loads(brut) if brut else None
    except Exception as e:  # noqa: BLE001
        logger.debug("cache lire %s : %s", cle, e)
        return None


async def ecrire_json(cle: str, valeur: Any, ttl: int) -> None:
    r = client()
    if not r:
        return
    try:
        await r.set(cle, json.dumps(valeur, default=str), ex=ttl)
    except Exception as e:  # noqa: BLE001
        logger.debug("cache écrire %s : %s", cle, e)


async def effacer_prefixe(prefixe: str) -> None:
    r = client()
    if not r:
        return
    try:
        async for cle in r.scan_iter(match=f"{prefixe}*", count=500):
            await r.delete(cle)
    except Exception as e:  # noqa: BLE001
        logger.debug("cache effacer %s : %s", prefixe, e)


# ─── Versions (polling léger) ────────────────────────────────────────────────

async def version(cle: str) -> str:
    r = client()
    if not r:
        return ""
    try:
        v = await r.get(f"v:{cle}")
        if v is None:
            # Première lecture : on pose une version pour que les suivantes
            # puissent répondre « inchangé ».
            await r.set(f"v:{cle}", "1", nx=True)
            v = await r.get(f"v:{cle}")
        return v or ""
    except Exception:  # noqa: BLE001
        return ""


async def changer(*cles: str) -> None:
    r = client()
    if not r or not cles:
        return
    try:
        pipe = r.pipeline()
        for c in cles:
            pipe.incr(f"v:{c}")
            pipe.expire(f"v:{c}", 7 * 24 * 3600)
        await pipe.execute()
    except Exception as e:  # noqa: BLE001
        logger.debug("version %s : %s", cles, e)


# ─── Limitation de débit ─────────────────────────────────────────────────────

async def depasse_limite(cle: str, maximum: int, fenetre_s: int) -> bool:
    r = client()
    if not r:
        return False
    try:
        k = f"rl:{cle}"
        n = await r.incr(k)
        if n == 1:
            await r.expire(k, fenetre_s)
        return n > maximum
    except Exception:  # noqa: BLE001
        return False


# ─── Verrous des tâches planifiées ───────────────────────────────────────────

async def prendre_verrou(nom: str, duree_s: int) -> bool:
    r = client()
    if not r:
        return True  # sans Redis : un verrou SQL prend le relais (taches.py)
    try:
        return bool(await r.set(f"lock:{nom}", "1", nx=True, ex=duree_s))
    except Exception:  # noqa: BLE001
        return True
