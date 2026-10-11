# app/services/geniuspay.py
# ─────────────────────────────────────────────────────────────────────────────
# Adaptateur GeniusPay (https://geniuspay.ci) — portage fidèle de
# functions/geniuspay.js. Paiement via PawaPay (Mobile Money CM / CI).
# Devise XOF obligatoire (même cours que le XAF).
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import hashlib
import hmac
import logging
from urllib.parse import quote

import httpx

from app.core.config import settings

logger = logging.getLogger("geniuspay")

SUCCES = {"COMPLETED", "SUCCESS", "SUCCESSFUL", "PAID", "ACCEPTED"}
ECHECS = {"FAILED", "CANCELLED", "EXPIRED", "REFUSED", "DECLINED"}
_ERREURS_PASSERELLE = {502, 503, 504, 522, 524}

# Un seul client HTTP partagé (connexions réutilisées : indispensable en charge).
_http: httpx.AsyncClient | None = None


def _client() -> httpx.AsyncClient:
    global _http
    if _http is None:
        _http = httpx.AsyncClient(timeout=25.0, limits=httpx.Limits(max_connections=50))
    return _http


class GeniusPayErreur(Exception):
    pass


def _entetes() -> dict:
    if not settings.GENIUSPAY_API_KEY:
        raise GeniusPayErreur("GENIUSPAY_API_KEY absent (variables Railway).")
    return {
        "Content-Type": "application/json",
        "Accept": "application/json",  # sinon Laravel redirige (302)
        "X-API-Key": settings.GENIUSPAY_API_KEY,
        "X-API-Secret": settings.GENIUSPAY_SECRET_KEY or settings.GENIUSPAY_API_KEY,
    }


def mmo_provider_cm(op: str) -> str | None:
    o = (op or "").lower()
    if "mtn" in o:
        return "MTN_MOMO_CMR"
    if "orange" in o:
        return "ORANGE_CMR"
    return None


def mmo_provider_ci(op: str) -> str | None:
    o = (op or "").lower()
    if "wave" in o:
        return "WAVE_CIV"
    if "moov" in o:
        return "MOOV_CIV"
    if "mtn" in o:
        return "MTN_MOMO_CIV"
    if "orange" in o:
        return "ORANGE_CIV"
    return None


def resoudre_pays(pays: str | None, operateur: str | None) -> tuple[str, str | None]:
    o = (operateur or "").lower()
    pays = (pays or "").upper() or ("CI" if o.endswith("_ci") else "CM")
    return pays, (mmo_provider_ci(o) if pays == "CI" else mmo_provider_cm(o))


async def creer_paiement(*, reference: str, montant: int, description: str, email: str,
                         telephone: str, pays: str, mmo_provider: str | None,
                         metadata: dict, callback_url: str) -> dict:
    corps = {
        "amount": montant,
        "currency": "XOF",
        "payment_method": "pawapay",
        "description": description or "Paiement Horem+",
        "customer": {"email": email or "", "phone": telephone, "country": pays},
        "metadata": {**metadata, "internal_reference": reference},
        "callback_url": callback_url,
        "success_url": settings.PAIEMENT_SUCCESS_URL or "",
        "error_url": settings.PAIEMENT_ERROR_URL or settings.PAIEMENT_SUCCESS_URL or "",
    }
    if mmo_provider:
        corps["mmo_provider"] = mmo_provider
    entetes = _entetes()
    url = f"{settings.GENIUSPAY_BASE_URL}/payments"
    rep = None
    data: dict = {}
    for tentative in range(1, 4):
        try:
            rep = await _client().post(url, json=corps, headers=entetes)
        except httpx.HTTPError as e:
            logger.warning("GeniusPay tentative %s : %s", tentative, e)
            if tentative == 3:
                raise GeniusPayErreur("GeniusPay injoignable. Réessayez dans un instant.") from e
            await asyncio.sleep(1.5 * tentative)
            continue
        try:
            data = rep.json()
        except ValueError:
            data = {}
        if rep.status_code in _ERREURS_PASSERELLE and tentative < 3:
            await asyncio.sleep(1.5 * tentative)
            continue
        break
    if rep is None or rep.status_code >= 400:
        code = rep.status_code if rep is not None else 0
        if code in _ERREURS_PASSERELLE:
            raise GeniusPayErreur(f"Service de paiement temporairement indisponible (HTTP {code}).")
        raise GeniusPayErreur(f"Création du paiement refusée (HTTP {code}) : {str(data)[:300]}")
    d = data.get("data") or data
    return {
        "payment_url": d.get("payment_url") or d.get("paymentUrl") or d.get("url")
        or d.get("checkout_url") or d.get("payment_link") or d.get("link") or "",
        "reference": d.get("reference") or reference,
        "transaction_id": str(d.get("transaction_id") or d.get("id") or reference),
    }


async def verifier_paiement(reference: str) -> str:
    """Statut GeniusPay en MAJUSCULES (PENDING si introuvable)."""
    try:
        entetes = _entetes()
    except GeniusPayErreur:
        return "PENDING"
    base = settings.GENIUSPAY_BASE_URL
    for url in (f"{base}/transactions/{reference}", f"{base}/payments/{reference}",
                f"{base}/payments?reference={quote(reference)}"):
        try:
            rep = await _client().get(url, headers=entetes, timeout=15.0)
            data = rep.json()
        except Exception:  # noqa: BLE001
            continue
        if isinstance(data, dict) and data.get("success") is False:
            continue
        obj = data.get("data") if isinstance(data, dict) else None
        if isinstance(obj, list):
            obj = obj[0] if obj else None
        obj = obj or data
        if isinstance(obj, dict):
            v = obj.get("status") or obj.get("state") or obj.get("payment_status") \
                or obj.get("transaction_status")
            if v:
                return str(v).upper()
    return "PENDING"


def signature_valide(corps_brut: bytes, recue: str) -> bool:
    secret = settings.GENIUSPAY_WEBHOOK_SECRET
    if not secret or not recue:
        logger.warning("GeniusPay : vérification de signature désactivée.")
        return True
    attendue = hmac.new(secret.encode(), corps_brut, hashlib.sha256).hexdigest()
    return hmac.compare_digest(attendue, recue.replace("sha256=", "").strip())
