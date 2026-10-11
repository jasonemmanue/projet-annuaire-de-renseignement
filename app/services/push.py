# app/services/push.py
# ─────────────────────────────────────────────────────────────────────────────
# Notifications push FCM (portage des envois des Cloud Functions).
#
# Montée en charge : la diffusion à tous les utilisateurs lit les jetons par
# pages de 500 (jamais toute la table en mémoire), envoie par lots de 500
# (limite FCM) et retire les jetons morts. Elle tourne en tâche de fond : la
# requête qui la déclenche répond tout de suite.
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import logging

from firebase_admin import messaging
from sqlalchemy import select, update

from app.core.firebase import a_compte_service
from app.db.session import AsyncSessionLocal
from app.models.models import Utilisateur

logger = logging.getLogger("push")

CANAL_MESSAGES = "sgkhome_messages"
CANAL_ANNONCES = "sgkhome_annonces"
_JETONS_MORTS = ("registration-token-not-registered", "invalid-registration-token",
                 "NOT_FOUND", "UNREGISTERED", "INVALID_ARGUMENT")


def _message(titre: str, corps: str, data: dict, canal: str):
    d = {k: str(v) for k, v in (data or {}).items() if v is not None}
    d["click_action"] = "FLUTTER_NOTIFICATION_CLICK"
    return dict(
        notification=messaging.Notification(title=titre, body=corps),
        data=d,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id=canal, click_action="FLUTTER_NOTIFICATION_CLICK", sound="default"),
        ),
        apns=messaging.APNSConfig(payload=messaging.APNSPayload(
            aps=messaging.Aps(alert=messaging.ApsAlert(title=titre, body=corps),
                              sound="default", badge=1))),
    )


def _mort(exc) -> bool:
    texte = f"{getattr(exc, 'code', '')} {exc}"
    return any(m in texte for m in _JETONS_MORTS)


async def _retirer_jetons(jetons: list[str]) -> None:
    if not jetons:
        return
    async with AsyncSessionLocal() as s:
        await s.execute(update(Utilisateur).where(Utilisateur.fcm_token.in_(jetons))
                        .values(fcm_token=None))
        await s.commit()
    logger.info("%s jetons FCM invalides retirés", len(jetons))


async def envoyer_jeton(jeton: str | None, titre: str, corps: str, data: dict | None = None,
                        canal: str = CANAL_ANNONCES) -> bool:
    if not jeton or not a_compte_service():
        return False
    try:
        msg = messaging.Message(token=jeton, **_message(titre, corps, data or {}, canal))
        await asyncio.to_thread(messaging.send, msg)
        return True
    except Exception as e:  # noqa: BLE001
        if _mort(e):
            await _retirer_jetons([jeton])
        else:
            logger.warning("push : %s", e)
        return False


async def notifier_utilisateur(uid: str, titre: str, corps: str, data: dict | None = None,
                               canal: str = CANAL_ANNONCES, respecter_pref_messages: bool = False) -> bool:
    """Push à un utilisateur (silencieux s'il n'a pas de jeton)."""
    if not uid or uid.startswith("visiteur_"):
        return False
    async with AsyncSessionLocal() as s:
        u = await s.get(Utilisateur, uid)
        if u is None or not u.fcm_token:
            return False
        if respecter_pref_messages and u.notif_messages is False:
            return False
        jeton = u.fcm_token
    return await envoyer_jeton(jeton, titre, corps, data, canal)


async def _envoyer_lot(jetons: list[str], titre: str, corps: str, data: dict, canal: str) -> int:
    msg = messaging.MulticastMessage(tokens=jetons, **_message(titre, corps, data, canal))
    try:
        rep = await asyncio.to_thread(messaging.send_each_for_multicast, msg)
    except Exception as e:  # noqa: BLE001
        logger.warning("push lot : %s", e)
        return 0
    morts = [jetons[i] for i, r in enumerate(rep.responses) if not r.success and _mort(r.exception)]
    await _retirer_jetons(morts)
    return rep.success_count


async def diffuser(titre: str, corps: str, data: dict | None = None, canal: str = CANAL_ANNONCES,
                   exclure: str | None = None) -> int:
    """Push à TOUS les utilisateurs ayant un jeton (par pages de 500)."""
    if not a_compte_service():
        logger.warning("diffusion ignorée : FIREBASE_CREDENTIALS absent")
        return 0
    envoyes, dernier = 0, ""
    while True:
        async with AsyncSessionLocal() as s:
            q = (select(Utilisateur.id, Utilisateur.fcm_token)
                 .where(Utilisateur.fcm_token.is_not(None), Utilisateur.fcm_token != "",
                        Utilisateur.id > dernier)
                 .order_by(Utilisateur.id).limit(500))
            lignes = (await s.execute(q)).all()
        if not lignes:
            break
        dernier = lignes[-1][0]
        jetons = list({t for uid, t in lignes if uid != exclure and t})
        if jetons:
            envoyes += await _envoyer_lot(jetons, titre, corps, data or {}, canal)
    logger.info("diffusion « %s » : %s envois réussis", titre, envoyes)
    return envoyes
