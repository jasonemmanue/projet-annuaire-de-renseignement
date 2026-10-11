# app/api/v1/routes/paiements.py
# ─────────────────────────────────────────────────────────────────────────────
# Paiements Mobile Money (remplacent les Cloud Functions initierXxx,
# verifierPaiement, geniuspayWebhook, envoyerLienPaiementEmail et
# initierPaiementDepuisWeb). Réponses au même format qu'avant :
#   { success, reference, checkoutUrl, montant, message }
# ─────────────────────────────────────────────────────────────────────────────
import json
import logging
import re
import secrets
import time
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import PlainTextResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.core import cache
from app.core.config import settings
from app.core.dependencies import compte_requis, utilisateur_courant
from app.core.serial import maintenant, vers_api
from app.db.session import get_db, marquer
from app.models.models import Logement, PaiementWeb, Publicite, Transaction, Urgence, Utilisateur
from app.services import email, geniuspay, paiements, tarifs

logger = logging.getLogger("routes.paiements")
router = APIRouter(prefix="/paiements", tags=["Paiements"])

_EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def _reponse(tx: Transaction, message: str = "Paiement initié. Confirmez sur votre téléphone.") -> dict:
    return {"success": True, "reference": tx.id, "checkoutUrl": tx.checkout_url or "",
            "montant": tx.montant, "message": message}


def _tel(data: dict) -> str:
    tel = str((data or {}).get("telephone") or "").strip()
    if not tel:
        raise HTTPException(400, {"success": False, "error": "Numéro de téléphone requis"})
    return tel


def _op(data: dict) -> str | None:
    return (data or {}).get("operateur") or (data or {}).get("channel")


async def _limiter(uid: str) -> None:
    if await cache.depasse_limite(f"paiement:{uid}", 10, 600):
        raise HTTPException(429, {"success": False, "error": "Trop de tentatives de paiement. Patientez."})


async def _logement_a_moi(db: AsyncSession, logement_id: str | None, uid: str) -> Logement:
    if not logement_id:
        raise HTTPException(400, {"success": False, "error": "Paramètres manquants"})
    log = await db.get(Logement, logement_id)
    if log is None:
        raise HTTPException(404, {"success": False, "error": "Annonce introuvable"})
    if log.uid_prestataire != uid:
        raise HTTPException(403, {"success": False, "error": "Cette annonce ne vous appartient pas"})
    return log


# ═════════════════════════════════════════════════════════════════════════════
# Initiation (Android : paiement dans l'app)
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/premium")
async def premium(data: dict, db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(compte_requis)):
    if user.role != "prestataire":
        raise HTTPException(403, {"success": False, "error": "Compte prestataire requis"})
    await _limiter(user.id)
    deja = await paiements.transaction_recente(db, user.id, "premium", None)
    if deja:
        return _reponse(deja, "Paiement déjà en cours. Finalisez-le via Mobile Money.")
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="premium", montant=tarifs.PREMIUM_MONTANT, telephone=_tel(data),
        operateur=_op(data), pays=data.get("pays"), description="Pack Premium Horem+ — 1 mois",
        email=user.email or "", internal_ref=f"premium_{user.id}_{int(time.time() * 1000)}")
    return _reponse(tx)


@router.post("/sponsorisation")
async def sponsorisation(data: dict, db: AsyncSession = Depends(get_db),
                         user: Utilisateur = Depends(compte_requis)):
    await _limiter(user.id)
    log = await _logement_a_moi(db, data.get("logementId"), user.id)
    code = data.get("duree") if data.get("duree") in tarifs.SPONSOR_TARIFS else "1m"
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="sponsorisation", montant=tarifs.SPONSOR_TARIFS[code],
        telephone=_tel(data), operateur=_op(data), pays=data.get("pays"),
        description=f"Mise en avant Horem+ — {log.titre or 'annonce'}", email=user.email or "",
        internal_ref=f"sponsor_{log.id}_{int(time.time() * 1000)}",
        champs={"logement_id": log.id, "duree": code})
    return _reponse(tx)


@router.post("/publication")
async def publication(data: dict, db: AsyncSession = Depends(get_db),
                      user: Utilisateur = Depends(compte_requis)):
    """Montant calculé ICI (3 % du prix ou forfait hébergement) : le montant
    éventuellement envoyé par l'app est ignoré."""
    await _limiter(user.id)
    log = await _logement_a_moi(db, data.get("logementId"), user.id)
    montant, jours = tarifs.montant_publication(log.type_bien, log.prix, data.get("dureeJours"))
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="publication", montant=montant, telephone=_tel(data),
        operateur=_op(data), pays=data.get("pays"),
        description=f"Publication Horem+ — {log.titre or 'annonce'}", email=user.email or "",
        internal_ref=f"pub_{log.id}_{int(time.time() * 1000)}",
        champs={"logement_id": log.id, "duree_jours": jours})
    return _reponse(tx)


@router.post("/visibilite")
async def visibilite(data: dict, db: AsyncSession = Depends(get_db),
                     user: Utilisateur = Depends(compte_requis)):
    await _limiter(user.id)
    log = await _logement_a_moi(db, data.get("logementId"), user.id)
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="visibilite", montant=tarifs.montant_visibilite(log.type_bien),
        telephone=_tel(data), operateur=_op(data), pays=data.get("pays"),
        description=f"Visibilité 1 an — {log.titre or log.type_bien or 'fiche'}", email=user.email or "",
        internal_ref=f"visib_{log.id}_{int(time.time() * 1000)}", champs={"logement_id": log.id})
    return _reponse(tx)


@router.post("/publicite")
async def publicite(data: dict, db: AsyncSession = Depends(get_db),
                    user: Utilisateur = Depends(compte_requis)):
    await _limiter(user.id)
    pub = await db.get(Publicite, data.get("publiciteId") or "")
    if pub is None:
        raise HTTPException(404, {"success": False, "error": "Publicité introuvable"})
    if pub.prestataire_id != user.id:
        raise HTTPException(403, {"success": False, "error": "Cette publicité ne vous appartient pas"})
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="publicite", montant=tarifs.PUBLICITE_MONTANT, telephone=_tel(data),
        operateur=_op(data), pays=data.get("pays"),
        description=f"Publicité {tarifs.PUBLICITE_DUREE_JOURS} jours — {pub.titre or 'Horem+'}",
        email=user.email or "", internal_ref=f"publicite_{pub.id}_{int(time.time() * 1000)}",
        champs={"publicite_id": pub.id})
    pub.payment_pending = True
    return _reponse(tx)


@router.post("/urgence")
async def urgence(data: dict, db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(utilisateur_courant)):
    """Alerte prioritaire 48 H (visiteur en session anonyme). `alerteId`
    (ou l'ancien nom `logementId`) = identifiant de l'alerte."""
    await _limiter(user.id)
    alerte_id = data.get("alerteId") or data.get("logementId")
    alerte = await db.get(Urgence, alerte_id or "")
    if alerte is None or alerte.uid != user.id:
        raise HTTPException(404, {"success": False, "error": "Alerte introuvable"})
    desc = f"{alerte.type_bien or 'Bien'} — {alerte.description or ''}"[:80]
    tx = await paiements.creer_transaction(
        db, uid=user.id, type_="urgence", montant=tarifs.URGENCE_MONTANT, telephone=_tel(data),
        operateur=_op(data), pays=data.get("pays"), description=f"Alerte prioritaire 48H — {desc}",
        email=user.email or "", internal_ref=f"urgence_{user.id}_{alerte.id}_{int(time.time() * 1000)}",
        champs={"logement_id": alerte.id})
    return _reponse(tx)


# ═════════════════════════════════════════════════════════════════════════════
# Suivi du statut
# ═════════════════════════════════════════════════════════════════════════════

async def _tx_a_moi(db: AsyncSession, reference: str, uid: str) -> Transaction:
    tx = await db.get(Transaction, reference)
    if tx is None:
        raise HTTPException(404, {"success": False, "error": "Transaction introuvable"})
    if tx.uid != uid:
        raise HTTPException(403, {"success": False, "error": "Accès refusé"})
    return tx


@router.post("/verifier")
async def verifier(data: dict, db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(utilisateur_courant)):
    """Vérification ACTIVE auprès de GeniusPay (indépendante du webhook)."""
    tx = await _tx_a_moi(db, str((data or {}).get("reference") or ""), user.id)
    if tx.statut in ("reussi", "echoue"):
        return {"success": True, "statut": tx.statut}
    # Une vérification GeniusPay toutes les 4 s au plus par transaction.
    if await cache.depasse_limite(f"verif:{tx.id}", 1, 4):
        return {"success": True, "statut": tx.statut}
    statut = await paiements.verifier_actif(db, tx)
    return {"success": True, "statut": statut}


@router.get("/statut/{reference}")
async def statut(reference: str, request: Request, db: AsyncSession = Depends(get_db),
                 user: Utilisateur = Depends(utilisateur_courant)):
    """Statut connu (lecture seule, polling léger)."""
    async def produire():
        tx = await _tx_a_moi(db, reference, user.id)
        return {"statut": tx.statut}
    return await versionne(request, f"tx:{reference}", produire)


@router.post("/webhook")
async def webhook(request: Request, db: AsyncSession = Depends(get_db)):
    """Webhook GeniusPay : signature HMAC, re-vérification API, effet métier."""
    brut = await request.body()
    if not geniuspay.signature_valide(brut, request.headers.get("x-geniuspay-signature", "")):
        logger.warning("webhook : signature invalide")
        return PlainTextResponse("Signature invalide", status_code=401)
    try:
        corps = json.loads(brut or b"{}")
    except ValueError:
        return PlainTextResponse("OK (corps illisible)")
    d = corps.get("data") or corps
    reference = d.get("reference") or d.get("transaction_reference") or d.get("id") \
        or corps.get("reference") or corps.get("transaction_id")
    logger.info("webhook reçu : %s", str(corps)[:300])
    if not reference:
        return PlainTextResponse("OK (référence manquante)")
    tx = await db.get(Transaction, str(reference))
    if tx is None:
        return PlainTextResponse("OK (transaction inconnue)")
    if tx.statut in ("reussi", "echoue"):
        return PlainTextResponse("OK (déjà traité)")
    evenement = str(corps.get("event") or corps.get("type") or "").lower()
    statut_payload = str(d.get("status") or d.get("state") or d.get("payment_status") or "").lower()
    derive = ""
    if "success" in evenement or statut_payload in ("success", "completed", "paid"):
        derive = "COMPLETED"
    elif any(m in evenement for m in ("fail", "cancel")) or statut_payload in (
            "failed", "cancelled", "expired", "declined"):
        derive = "FAILED"
    statut_api = await geniuspay.verifier_paiement(str(reference))
    final = statut_api if statut_api in geniuspay.SUCCES | geniuspay.ECHECS else (derive or statut_api)
    await paiements.finaliser(db, str(reference), final)
    return PlainTextResponse("OK")


# ═════════════════════════════════════════════════════════════════════════════
# Flow iOS (App Store 3.1.1) : lien par e-mail → page web /pay/[token]
# ═════════════════════════════════════════════════════════════════════════════

@router.post("/lien-email")
async def lien_email(data: dict, db: AsyncSession = Depends(get_db), user: Utilisateur = Depends(utilisateur_courant)):
    type_ = (data or {}).get("type")
    adresse = str((data or {}).get("email") or "").strip()
    if type_ not in tarifs.TYPES_ACTIVATION:
        raise HTTPException(400, {"success": False, "error": "Type de service invalide"})
    if not _EMAIL.match(adresse):
        raise HTTPException(400, {"success": False, "error": "Email invalide"})
    if await cache.depasse_limite(f"lien:{user.id}", 5, 3600):
        raise HTTPException(429, {"success": False, "error": "Trop de demandes. Réessayez plus tard."})
    params = dict(data.get("params") or {})
    cible = data.get("targetId")
    # Montant d'une publication recalculé depuis l'annonce (jamais celui de l'app).
    if type_ in ("publication", "visibilite") and cible:
        log = await db.get(Logement, cible)
        if log is None or log.uid_prestataire != user.id:
            raise HTTPException(404, {"success": False, "error": "Annonce introuvable"})
        if type_ == "publication":
            params["montant"], params["dureeJours"] = tarifs.montant_publication(
                log.type_bien, log.prix, params.get("dureeJours"))
        else:
            params["typeBien"] = log.type_bien
        params.setdefault("titre", log.titre)
    try:
        service = tarifs.service_activation(type_, params)
    except ValueError as e:
        raise HTTPException(400, {"success": False, "error": str(e)})
    jeton = secrets.token_hex(16)
    expire = maintenant() + timedelta(hours=tarifs.PAIEMENT_WEB_TTL_H)
    db.add(PaiementWeb(id=jeton, uid=user.id, type=type_, target_id=cible, params=params,
                       montant=service["montant"], libelle=service["libelle"],
                       description=service["description"], email=adresse, statut="en_attente",
                       expires_at=expire))
    await db.flush()
    url = f"{settings.WEB_PAY_BASE_URL.rstrip('/')}/{jeton}"
    ok = await email.envoyer(
        adresse, "Horem+ — Finalisez l'activation de votre service",
        email.html_lien_paiement(url, service["libelle"], service["description"],
                                 user.prenom or user.nom or "", tarifs.PAIEMENT_WEB_TTL_H),
        f"Bonjour,\n\nPour finaliser l'activation de votre service {service['libelle']}, "
        f"ouvrez ce lien :\n{url}\n\nCe lien est valable {tarifs.PAIEMENT_WEB_TTL_H} heures.\n\nHorem+")
    if not ok:
        raise HTTPException(500, {"success": False, "error": "Impossible d'envoyer l'email"})
    return {"success": True, "token": jeton, "expiresAt": expire.isoformat()}


def _jeton_valide(jeton: str) -> None:
    if not re.fullmatch(r"[a-f0-9]{32}", jeton or ""):
        raise HTTPException(400, {"success": False, "error": "Token invalide"})


def _public_web(pw: PaiementWeb) -> dict:
    d = vers_api(pw, PaiementWeb.CHAMPS)
    for cle in ("uid", "email", "params"):
        d.pop(cle, None)
    return d


@router.get("/web/{jeton}")
async def lien_web(jeton: str, request: Request, db: AsyncSession = Depends(get_db)):
    """Page /pay/[token] : description et statut du lien (polling ?v=…)."""
    _jeton_valide(jeton)

    async def produire():
        pw = await db.get(PaiementWeb, jeton)
        if pw is None:
            raise HTTPException(404, {"success": False, "error": "Lien introuvable"})
        if pw.statut in ("en_attente", "initie") and pw.expires_at and pw.expires_at < maintenant():
            pw.statut = "expire"
        # Paiement lancé : on vérifie activement (sans dépendre du webhook).
        if pw.statut == "initie" and pw.reference and not await cache.depasse_limite(f"verif:{pw.reference}", 1, 4):
            tx = await db.get(Transaction, pw.reference)
            if tx:
                await paiements.verifier_actif(db, tx)
                await db.refresh(pw)
        return _public_web(pw)
    return await versionne(request, f"pw:{jeton}", produire)


@router.post("/web/{jeton}/initier")
async def initier_web(jeton: str, data: dict, request: Request, db: AsyncSession = Depends(get_db)):
    """Appelée par la page web (sans compte : le jeton aléatoire de 128 bits
    sert de clé)."""
    _jeton_valide(jeton)
    ip = request.client.host if request.client else "?"
    if await cache.depasse_limite(f"pw_init:{ip}", 10, 600):
        raise HTTPException(429, {"success": False, "error": "Trop de tentatives. Patientez."})
    pw = await db.get(PaiementWeb, jeton, with_for_update=True)
    if pw is None:
        raise HTTPException(404, {"success": False, "error": "Lien introuvable"})
    if pw.expires_at and pw.expires_at < maintenant():
        pw.statut = "expire"
        marquer(db, f"pw:{jeton}")
        raise HTTPException(410, {"success": False, "error": "Lien expiré"})
    if pw.statut == "reussi":
        return {"success": True, "alreadyPaid": True}
    if not pw.montant:
        raise HTTPException(500, {"success": False, "error": "Montant invalide"})
    u = await db.get(Utilisateur, pw.uid)
    p = pw.params or {}
    champs: dict = {"source": "ios_web", "payment_token": jeton}
    if p.get("duree"):
        champs["duree"] = p["duree"]
    if p.get("dureeJours"):
        champs["duree_jours"] = int(p["dureeJours"])
    if pw.target_id:
        champs["publicite_id" if pw.type == "publicite" else "logement_id"] = pw.target_id
    tx = await paiements.creer_transaction(
        db, uid=pw.uid, type_=pw.type, montant=pw.montant, telephone=_tel(data), operateur=_op(data),
        pays=data.get("pays"), description=f"Horem+ — {pw.libelle or pw.type}",
        email=pw.email or (u.email if u else "") or "",
        internal_ref=f"web_{pw.type}_{jeton[:8]}_{int(time.time() * 1000)}", champs=champs)
    pw.statut, pw.reference, pw.checkout_url, pw.initie_at = "initie", tx.id, tx.checkout_url, maintenant()
    marquer(db, f"pw:{jeton}")
    return {"success": True, "reference": tx.id, "checkoutUrl": tx.checkout_url or ""}
