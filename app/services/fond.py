# app/services/fond.py
# Lance une coroutine en tâche de fond (push, e-mails…) sans bloquer la
# réponse HTTP. Les références sont gardées pour que la tâche ne soit pas
# ramassée par le ramasse-miettes avant la fin.
import asyncio
import logging

logger = logging.getLogger("fond")
_taches: set[asyncio.Task] = set()


def lancer(coro, nom: str = "tache") -> None:
    async def _enveloppe():
        try:
            await coro
        except Exception as e:  # noqa: BLE001
            logger.error("tâche de fond %s : %s", nom, e)

    t = asyncio.create_task(_enveloppe(), name=nom)
    _taches.add(t)
    t.add_done_callback(_taches.discard)
