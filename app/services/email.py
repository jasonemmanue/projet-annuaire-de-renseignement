# app/services/email.py
# ─────────────────────────────────────────────────────────────────────────────
# Envoi d'e-mails. Railway bloque le SMTP sortant : API HTTP Gmail (refresh
# token OAuth, comme l'API Prepaxia) puis Resend en secours.
# ─────────────────────────────────────────────────────────────────────────────
import base64
import html
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr

import httpx

from app.core.config import settings

logger = logging.getLogger("email")
NOM_EXPEDITEUR = "Horem+"


async def _jeton_gmail(client: httpx.AsyncClient) -> str | None:
    if not (settings.GMAIL_API_CLIENT_ID and settings.GMAIL_API_CLIENT_SECRET
            and settings.GMAIL_API_REFRESH_TOKEN):
        return None
    r = await client.post("https://oauth2.googleapis.com/token", data={
        "client_id": settings.GMAIL_API_CLIENT_ID,
        "client_secret": settings.GMAIL_API_CLIENT_SECRET,
        "refresh_token": settings.GMAIL_API_REFRESH_TOKEN,
        "grant_type": "refresh_token",
    })
    if r.status_code == 200:
        return r.json().get("access_token")
    logger.error("Gmail refresh HTTP %s : %s", r.status_code, r.text[:200])
    return None


async def envoyer(dest: str, sujet: str, corps_html: str, texte: str = "") -> bool:
    async with httpx.AsyncClient(timeout=15.0) as client:
        if settings.GMAIL_API_SENDER:
            try:
                acces = await _jeton_gmail(client)
                if acces:
                    msg = MIMEMultipart("alternative")
                    msg["Subject"] = sujet
                    msg["From"] = formataddr((NOM_EXPEDITEUR, settings.GMAIL_API_SENDER))
                    msg["To"] = dest
                    if texte:
                        msg.attach(MIMEText(texte, "plain", "utf-8"))
                    msg.attach(MIMEText(corps_html, "html", "utf-8"))
                    brut = base64.urlsafe_b64encode(msg.as_bytes()).decode()
                    r = await client.post(
                        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
                        headers={"Authorization": f"Bearer {acces}"}, json={"raw": brut})
                    if r.status_code in (200, 202):
                        return True
                    logger.error("Gmail API HTTP %s : %s", r.status_code, r.text[:300])
            except Exception as e:  # noqa: BLE001
                logger.error("Gmail API : %s", e)
        if settings.RESEND_API_KEY:
            try:
                r = await client.post("https://api.resend.com/emails", headers={
                    "Authorization": f"Bearer {settings.RESEND_API_KEY}"}, json={
                    "from": settings.RESEND_FROM_EMAIL, "to": [dest],
                    "subject": sujet, "html": corps_html, "text": texte or None})
                if r.status_code in (200, 201, 202):
                    return True
                logger.error("Resend HTTP %s : %s", r.status_code, r.text[:300])
            except Exception as e:  # noqa: BLE001
                logger.error("Resend : %s", e)
    logger.warning("Aucun e-mail envoyé à %s (Gmail API / Resend non configurés)", dest)
    return False


def _e(v) -> str:
    return html.escape(str(v if v not in (None, "") else "–"))


def html_nouvelle_publication(log: dict, logement_id: str) -> str:
    lat, lng = log.get("latitude"), log.get("longitude")
    carte = f"https://www.google.com/maps?q={lat},{lng}" if lat and lng else ""
    prix = f"{int(log['prix']):,} XAF".replace(",", " ") if log.get("prix") else "Gratuit"
    lignes = [
        ("Annonce", log.get("titre")), ("Type", log.get("typeBien")),
        ("Ville / Quartier", f"{log.get('ville') or '–'} · {log.get('quartier') or '–'}"),
        ("Prix", prix), ("Prestataire", log.get("prestatireNom")),
        ("Téléphone", log.get("prestatirePhone")), ("UID", log.get("uid_prestataire")),
        ("ID Annonce", logement_id),
    ]
    td = 'style="padding:8px;border:1px solid #ddd;"'
    th = 'style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;"'
    corps = "".join(f"<tr><td {th}>{_e(a)}</td><td {td}>{_e(b)}</td></tr>" for a, b in lignes)
    if carte:
        corps += f'<tr><td {th}>GPS</td><td {td}><a href="{_e(carte)}">{_e(lat)}, {_e(lng)}</a></td></tr>'
    return (f'<h2>🏠 Nouvelle publication sur Horem+</h2>'
            f'<table style="border-collapse:collapse;width:100%;font-family:sans-serif;">{corps}</table>'
            f'<p style="margin-top:16px;color:#666;font-size:12px;">Horem+ — notification automatique.</p>')


def html_lien_paiement(url: str, libelle: str, description: str, prenom: str, ttl_h: int) -> str:
    bonjour = f"Bonjour {_e(prenom)}," if prenom else "Bonjour,"
    u = _e(url)
    return f"""<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Horem+</title></head>
<body style="margin:0;padding:0;background:#f4f4f2;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#1a1a18;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f2;padding:32px 16px;"><tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;">
<tr><td style="background:#1e3a8a;padding:32px;text-align:center;"><div style="color:#fff;font-size:24px;font-weight:700;">Horem+</div>
<div style="color:#c7d2fe;font-size:13px;margin-top:4px;">Activation de votre service</div></td></tr>
<tr><td style="padding:32px;"><p style="margin:0 0 16px;font-size:16px;">{bonjour}</p>
<p style="margin:0 0 16px;font-size:15px;color:#4a4a45;">Pour finaliser l'activation de votre service <strong>{_e(libelle)}</strong>, cliquez sur le bouton ci-dessous.</p>
<p style="margin:0 0 24px;font-size:15px;color:#4a4a45;">{_e(description)}</p>
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px auto;"><tr><td align="center" style="background:#d4622b;border-radius:8px;">
<a href="{u}" style="display:inline-block;padding:14px 32px;color:#fff;font-size:15px;font-weight:600;text-decoration:none;">Finaliser l'activation →</a></td></tr></table>
<p style="margin:24px 0 0;font-size:13px;color:#8a877e;text-align:center;">Ce lien est valable pendant {ttl_h} heures.<br>
Si le bouton ne fonctionne pas, copiez ce lien :<br><a href="{u}" style="color:#d4622b;word-break:break-all;">{u}</a></p></td></tr>
<tr><td style="background:#faf9f6;padding:20px 32px;border-top:1px solid #e2dfd8;text-align:center;">
<p style="margin:0;font-size:12px;color:#8a877e;">Horem+ — Petites annonces immobilières<br>Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.</p></td></tr>
</table></td></tr></table></body></html>"""
