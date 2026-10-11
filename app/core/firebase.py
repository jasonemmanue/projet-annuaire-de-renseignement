# app/core/firebase.py
# ─────────────────────────────────────────────────────────────────────────────
# Firebase n'est plus utilisé QUE pour :
#   • l'authentification (l'app et l'admin se connectent avec Firebase Auth,
#     l'API vérifie le jeton d'identité envoyé dans Authorization: Bearer) ;
#   • l'envoi des notifications push (FCM), seul canal possible vers Android/iOS.
# Toutes les données (Firestore) et tous les fichiers (Storage) sont dans
# PostgreSQL, et les Cloud Functions sont remplacées par cette API.
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import base64
import json
import logging

import firebase_admin
from firebase_admin import auth as fb_auth
from firebase_admin import credentials

from app.core.config import settings

logger = logging.getLogger("firebase")
_init_tente = False


def ensure_firebase() -> bool:
    """Initialise Firebase Admin une seule fois. Sans compte de service, la
    vérification des jetons marche encore (clés publiques Google), mais pas
    les notifications push ni la création de comptes par l'admin."""
    global _init_tente
    if firebase_admin._apps:
        return True
    if _init_tente:
        return False
    _init_tente = True
    try:
        if settings.FIREBASE_CREDENTIALS:
            brut = base64.b64decode(settings.FIREBASE_CREDENTIALS).decode("utf-8")
            info = json.loads(brut)
            firebase_admin.initialize_app(credentials.Certificate(info))
            logger.info("✅ Firebase Admin initialisé (projet %s)", info.get("project_id"))
        else:
            firebase_admin.initialize_app(options={"projectId": settings.FIREBASE_PROJECT_ID})
            logger.warning("⚠️ FIREBASE_CREDENTIALS absent : push FCM et création de "
                           "comptes désactivés (vérification des jetons active).")
        return True
    except Exception as e:  # noqa: BLE001
        logger.error("❌ Firebase Admin non initialisé : %s", e)
        return False


def a_compte_service() -> bool:
    return bool(settings.FIREBASE_CREDENTIALS) and ensure_firebase()


async def verifier_jeton(jeton: str) -> dict:
    """Vérifie un jeton d'identité Firebase et renvoie ses revendications.
    Lève ValueError si le jeton est invalide ou expiré."""
    if not ensure_firebase():
        raise ValueError("Firebase indisponible")
    try:
        return await asyncio.to_thread(fb_auth.verify_id_token, jeton, None, False, 60)
    except Exception as e:  # noqa: BLE001
        raise ValueError(str(e)) from e
