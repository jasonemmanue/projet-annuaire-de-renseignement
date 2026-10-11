# app/api/v1/routes/conversations.py
# ─────────────────────────────────────────────────────────────────────────────
# Messagerie visiteur ↔ prestataire (anciennement conversations/{id} et sa
# sous-collection messages).
#
# Temps réel sans Firestore : l'app interroge régulièrement avec la version
# connue (?v=…). Tant que la conversation ne change pas, la réponse est
# {"inchange": true} servie par Redis, sans requête SQL : des milliers de
# conversations ouvertes ne chargent pas la base.
#
# Contrôle d'accès (plus strict qu'avant : Firestore laissait lire toutes les
# conversations sans compte) : seuls les participants et l'admin y accèdent.
# ─────────────────────────────────────────────────────────────────────────────
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.core import cache
from app.core.dependencies import Appelant, appelant
from app.core.serial import appliquer, maintenant, nouvel_id, vers_api
from app.db.session import apres_commit, get_db, marquer
from app.models.models import Conversation, Message, Urgence, Utilisateur
from app.services import push

router = APIRouter(prefix="/conversations", tags=["Messagerie"])

TYPES = {"text", "image", "video", "file", "audio"}
APERCU = {"image": "📷 Photo", "video": "🎬 Vidéo", "audio": "🎤 Message vocal"}


def api_conv(c: Conversation) -> dict:
    d = vers_api(c, Conversation.CHAMPS)
    for uid, n in (c.unread or {}).items():
        d[f"unread_{uid}"] = n
    for p in c.participants or []:
        d.setdefault(f"unread_{p}", 0)
    return d


def api_msg(m: Message) -> dict:
    return vers_api(m, Message.CHAMPS)


async def _conv(db: AsyncSession, conv_id: str, qui: Appelant, verrou: bool = False) -> Conversation:
    c = await db.get(Conversation, conv_id, with_for_update=verrou)
    if c is None:
        raise HTTPException(404, "Conversation introuvable")
    if qui.id not in (c.participants or []) and not qui.est_admin:
        raise HTTPException(403, "Accès refusé")
    return c


def _autre(c: Conversation, moi: str) -> str:
    return next((p for p in (c.participants or []) if p != moi), "")


@router.get("")
async def mes_conversations(request: Request, db: AsyncSession = Depends(get_db),
                            qui: Appelant = Depends(appelant)):
    async def produire():
        lignes = (await db.execute(
            select(Conversation).where(Conversation.participants.contains([qui.id]))
            .order_by(Conversation.last_message_time.desc().nulls_last()).limit(300))).scalars().all()
        return {"items": [api_conv(c) for c in lignes]}
    return await versionne(request, f"inbox:{qui.id}", produire)


@router.get("/non-lus")
async def non_lus(request: Request, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    """Total des messages non lus (badge des onglets)."""
    async def produire():
        total = (await db.execute(text(
            "SELECT COALESCE(SUM((unread ->> :u)::int), 0) FROM conversations "
            "WHERE participants @> ARRAY[:u]::varchar[]"), {"u": qui.id})).scalar_one()
        return {"total": int(total or 0)}
    return await versionne(request, f"inbox:{qui.id}", produire)


@router.post("")
async def ouvrir(data: dict, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    """Récupère ou crée la conversation (moi, prestataire, annonce)."""
    prest = (data or {}).get("prestataireId") or ""
    logement_id = (data or {}).get("logementId") or ""
    if not prest or not logement_id:
        raise HTTPException(400, "prestataireId et logementId requis")
    if prest == qui.id:
        raise HTTPException(400, "Impossible de vous écrire à vous-même")
    # Verrou transactionnel : deux ouvertures simultanées ne créent pas deux
    # conversations.
    await db.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"),
                     {"k": f"conv:{qui.id}:{prest}:{logement_id}"})
    existante = (await db.execute(select(Conversation).where(
        Conversation.participants.contains([qui.id, prest]),
        Conversation.logement_id == logement_id).limit(1))).scalar_one_or_none()
    if existante:
        return api_conv(existante)

    label, numero = None, None
    if qui.id.startswith("visiteur_"):
        # « ContactN » : numéro stable par visiteur chez ce prestataire.
        deja = (await db.execute(select(Conversation.contact_number).where(
            Conversation.prestataire_uid == prest, Conversation.client_uid == qui.id,
            Conversation.contact_number.is_not(None)).limit(1))).scalar_one_or_none()
        if deja:
            numero = deja
        else:
            maxi = (await db.execute(select(func.max(Conversation.contact_number)).where(
                Conversation.prestataire_uid == prest))).scalar_one_or_none()
            numero = (maxi or 0) + 1
        label = f"Contact{numero}"

    urgence = await db.get(Urgence, f"{qui.id}_{logement_id}")
    c = Conversation(
        id=nouvel_id(), participants=[qui.id, prest], client_uid=qui.id, prestataire_uid=prest,
        logement_id=logement_id, logement_titre=(data.get("logementTitre") or "")[:300],
        logement_photo=data.get("logementPhoto"), last_message="", last_message_time=maintenant(),
        unread={qui.id: 0, prest: 0}, contact_label=label, contact_number=numero,
        visitor_uid=qui.id if qui.id.startswith("visiteur_") else None,
        urgence_until=urgence.expires_at if urgence and urgence.expires_at
        and urgence.expires_at > maintenant() else None, extra={})
    appliquer(c, {"logement_photo": data.get("logementPhoto")}, Conversation.CHAMPS)
    db.add(c)
    await db.flush()
    marquer(db, f"inbox:{qui.id}", f"inbox:{prest}", "admin_conversations")
    return api_conv(c)


@router.get("/{conv_id}")
async def une(conv_id: str, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    return api_conv(await _conv(db, conv_id, qui))


@router.get("/{conv_id}/messages")
async def messages(conv_id: str, request: Request, db: AsyncSession = Depends(get_db),
                   qui: Appelant = Depends(appelant)):
    # Contrôle d'accès mis en cache : le polling ne relit pas la conversation.
    cle_acces = f"acces:{conv_id}:{qui.id}"
    if not await cache.lire_json(cle_acces):
        await _conv(db, conv_id, qui)
        await cache.ecrire_json(cle_acces, 1, 600)

    async def produire():
        lignes = (await db.execute(select(Message).where(Message.conversation_id == conv_id)
                                   .order_by(Message.timestamp.desc()).limit(500))).scalars().all()
        return {"items": [api_msg(m) for m in reversed(lignes)]}
    return await versionne(request, f"conv:{conv_id}", produire)


@router.post("/{conv_id}/messages")
async def envoyer(conv_id: str, data: dict, db: AsyncSession = Depends(get_db),
                  qui: Appelant = Depends(appelant)):
    if await cache.depasse_limite(f"msg:{qui.id}", 60, 60):
        raise HTTPException(429, "Trop de messages, patientez un instant.")
    c = await _conv(db, conv_id, qui, verrou=True)
    type_ = (data or {}).get("type") or "text"
    if type_ not in TYPES:
        raise HTTPException(400, "Type de message invalide")
    m = Message(id=nouvel_id(), conversation_id=conv_id, sender_id=qui.id, type=type_,
                is_read=False, edited=False, deleted=False, extra={}, text="")
    appliquer(m, data, Message.CHAMPS, autorises={"text", "imageUrl", "videoUrl", "fileUrl",
                                                  "fileName", "replyTo"}, extra_libre=False)
    m.text = (m.text or "")[:5000]
    if type_ == "text" and not m.text.strip():
        raise HTTPException(400, "Message vide")
    m.timestamp = maintenant()
    db.add(m)
    dest = _autre(c, qui.id)
    apercu = m.text if type_ == "text" else APERCU.get(type_, f"📎 {m.file_name or 'Fichier'}")
    c.last_message = apercu[:300]
    c.last_message_time = m.timestamp
    unread = dict(c.unread or {})
    unread[dest] = int(unread.get(dest, 0)) + 1
    c.unread = unread
    await db.flush()
    marquer(db, f"conv:{conv_id}", f"inbox:{qui.id}", f"inbox:{dest}")

    if dest and not dest.startswith("visiteur_"):
        if qui.id.startswith("visiteur_"):
            nom = c.contact_label or "Visiteur"
        else:
            u = await db.get(Utilisateur, qui.id)
            nom = (f"{u.prenom} {u.nom}".strip() if u else "") or "Nouveau message"
        corps = apercu if len(apercu) <= 100 else apercu[:100] + "…"
        titre_log = c.logement_titre or ""
        apres_commit(db, lambda: push.notifier_utilisateur(
            dest, f"💬 {nom}", corps,
            {"type": "message", "conversationId": conv_id, "logementTitre": titre_log},
            canal=push.CANAL_MESSAGES, respecter_pref_messages=True), "push_message")
    return api_msg(m)


@router.patch("/{conv_id}/messages/{msg_id}")
async def modifier_message(conv_id: str, msg_id: str, data: dict, db: AsyncSession = Depends(get_db),
                           qui: Appelant = Depends(appelant)):
    await _conv(db, conv_id, qui)
    m = await db.get(Message, msg_id)
    if m is None or m.conversation_id != conv_id:
        raise HTTPException(404, "Message introuvable")
    if m.sender_id != qui.id:
        raise HTTPException(403, "Seul l'auteur peut modifier ce message")
    m.text = str((data or {}).get("text") or "")[:5000]
    m.edited = True
    marquer(db, f"conv:{conv_id}")
    return api_msg(m)


@router.delete("/{conv_id}/messages/{msg_id}")
async def supprimer_message(conv_id: str, msg_id: str, db: AsyncSession = Depends(get_db),
                            qui: Appelant = Depends(appelant)):
    await _conv(db, conv_id, qui)
    m = await db.get(Message, msg_id)
    if m is None or m.conversation_id != conv_id:
        raise HTTPException(404, "Message introuvable")
    if m.sender_id != qui.id and not qui.est_admin:
        raise HTTPException(403, "Seul l'auteur peut supprimer ce message")
    m.deleted, m.text, m.type = True, "", "deleted"
    marquer(db, f"conv:{conv_id}")
    return {"success": True}


@router.post("/{conv_id}/lu")
async def marquer_lu(conv_id: str, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    c = await _conv(db, conv_id, qui, verrou=True)
    deja_lu = int((c.unread or {}).get(qui.id, 0)) == 0
    if not deja_lu:
        unread = dict(c.unread or {})
        unread[qui.id] = 0
        c.unread = unread
    res = await db.execute(update(Message).where(
        Message.conversation_id == conv_id, Message.is_read.is_(False), Message.sender_id != qui.id)
        .values(is_read=True))
    if not deja_lu or res.rowcount:
        marquer(db, f"conv:{conv_id}", f"inbox:{qui.id}")
    return {"success": True}


@router.delete("/{conv_id}")
async def supprimer(conv_id: str, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    c = await _conv(db, conv_id, qui)
    marquer(db, *[f"inbox:{p}" for p in (c.participants or [])], f"conv:{conv_id}", "admin_conversations")
    await db.execute(delete(Conversation).where(Conversation.id == conv_id))
    return {"success": True}
