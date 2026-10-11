# app/services/migration_firestore.py
# ─────────────────────────────────────────────────────────────────────────────
# Reprise UNIQUE des données Firestore (projet sgk-home) dans PostgreSQL.
#
# Lancée depuis l'admin (POST /api/v1/admin/migration-firestore) : elle tourne
# DANS l'API sur Railway (la base n'est pas exposée sur Internet) avec le
# compte de service FIREBASE_CREDENTIALS. Idempotente : chaque document est
# inséré ou mis à jour par son identifiant Firestore, on peut la relancer.
# Les identifiants (y compris les uid) sont conservés : les liens entre
# annonces, conversations, transactions… restent valides.
# Les fichiers ne bougent pas (ils restent dans Firebase Storage).
# ─────────────────────────────────────────────────────────────────────────────
import asyncio
import logging
from datetime import datetime

from app.core import cache
from app.core.serial import appliquer, date_vers_texte, texte_vers_date
from app.db.session import AsyncSessionLocal
from app.models.models import (
    Conversation, Favori, Logement, Message, NotificationAdmin, PaiementWeb, Publicite,
    Signalement, Transaction, Urgence, Utilisateur,
)

logger = logging.getLogger("migration")
ETAT: dict = {"statut": "jamais lancée"}
_LOT = 300


def _propre(v):
    """Valeur Firestore → JSON (dates en texte, GeoPoint, références…)."""
    if isinstance(v, datetime):
        return date_vers_texte(v)
    if isinstance(v, dict):
        return {str(k): _propre(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_propre(x) for x in v]
    if hasattr(v, "latitude") and hasattr(v, "longitude"):
        return {"latitude": v.latitude, "longitude": v.longitude}
    if hasattr(v, "path") and hasattr(v, "id"):
        return v.path
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    return str(v)


def _client():
    from firebase_admin import firestore
    return firestore.client()


async def _lire(chemin_ou_ref) -> list:
    def _go():
        ref = _client().collection(chemin_ou_ref) if isinstance(chemin_ou_ref, str) else chemin_ou_ref
        return [(d.id, d.to_dict() or {}) for d in ref.stream()]
    return await asyncio.to_thread(_go)


async def _enregistrer(objets: list) -> None:
    for i in range(0, len(objets), _LOT):
        async with AsyncSessionLocal() as s:
            for o in objets[i:i + _LOT]:
                await s.merge(o)
            await s.commit()


def _construire(modele, doc_id: str, data: dict, **fixes):
    o = modele(id=doc_id, **fixes) if "id" not in fixes else modele(**fixes)
    if hasattr(o, "extra"):
        o.extra = {}
    propre = {k: _propre(v) for k, v in data.items()}
    appliquer(o, propre, modele.CHAMPS, extra_libre=hasattr(o, "extra"),
              interdits={"reference"} if modele is Transaction else None)
    return o, propre


async def _users() -> int:
    docs = await _lire("users")
    objets = []
    for doc_id, data in docs:
        data.pop("uid", None)
        o, _ = _construire(Utilisateur, doc_id, data)
        o.role = o.role if o.role in ("client", "prestataire", "admin") else "prestataire"
        o.anonyme = False
        for attr, defaut in (("nom", ""), ("prenom", ""), ("telephone", ""), ("is_premium", False),
                             ("is_verifie", False), ("phone_verified", False), ("compte_gratuit", False),
                             ("notif_messages", True), ("suspendu", False)):
            if getattr(o, attr) is None:
                setattr(o, attr, defaut)
        objets.append(o)
    await _enregistrer(objets)
    # Favoris (sous-collection).
    favs = []
    for doc_id, _ in docs:
        ref = _client().collection("users").document(doc_id).collection("favoris")
        for fid, fdata in await _lire(ref):
            propre = {k: _propre(v) for k, v in fdata.items()}
            favs.append(Favori(utilisateur_id=doc_id, logement_id=propre.get("logementId") or fid,
                               donnees={k: v for k, v in propre.items() if k not in ("addedAt",)},
                               added_at=texte_vers_date(propre.get("addedAt")) or datetime.now().astimezone()))
    await _enregistrer(favs)
    ETAT["favoris"] = len(favs)
    return len(objets)


async def _logements() -> int:
    objets = []
    for doc_id, data in await _lire("logements"):
        uid = data.get("uid_prestataire") or data.get("prestatireId") or data.get("prestataireId") or ""
        data.pop("prestataireId", None)
        o, propre = _construire(Logement, doc_id, data)
        o.uid_prestataire = uid
        # Champ « visibleAdmin » absent = règle historique (NULL).
        if "visibleAdmin" not in propre:
            o.visible_admin = None
        o.annonce_diffusee = True  # déjà publiées : pas de nouvelle diffusion
        for attr, defaut in (("titre", ""), ("description", ""), ("prix", 0), ("type_location", "location"),
                             ("type_bien", "Studio"), ("grade", "standards"), ("ville", ""), ("quartier", ""),
                             ("latitude", 0), ("longitude", 0), ("photos", []), ("surface", 0),
                             ("nb_pieces", 1), ("equipements", []), ("est_verifie", False),
                             ("is_sponsored", False), ("prestataire_nom", ""), ("prestataire_phone", ""),
                             ("disponible", True), ("payment_pending", False), ("jours_garde", []),
                             ("vues", 0), ("contacts", 0), ("vues_milestones", [])):
            if getattr(o, attr) is None:
                setattr(o, attr, defaut)
        objets.append(o)
    await _enregistrer(objets)
    return len(objets)


async def _conversations() -> tuple[int, int]:
    docs = await _lire("conversations")
    convs, msgs = [], []
    for doc_id, data in docs:
        unread = {k[len("unread_"):]: int(v or 0) for k, v in data.items() if k.startswith("unread_")}
        data = {k: v for k, v in data.items() if not k.startswith("unread_")}
        o, _ = _construire(Conversation, doc_id, data)
        o.unread = unread
        o.participants = [str(p) for p in (o.participants or [])]
        for attr, defaut in (("client_uid", ""), ("prestataire_uid", ""), ("logement_id", ""),
                             ("logement_titre", ""), ("last_message", "")):
            if getattr(o, attr) is None:
                setattr(o, attr, defaut)
        if not o.client_uid and o.participants:
            o.client_uid = o.participants[0]
        convs.append(o)
    await _enregistrer(convs)
    for doc_id, _ in docs:
        ref = _client().collection("conversations").document(doc_id).collection("messages")
        for mid, mdata in await _lire(ref):
            m, _ = _construire(Message, mid, mdata)
            m.conversation_id = doc_id
            for attr, defaut in (("sender_id", ""), ("type", "text"), ("text", ""), ("is_read", False),
                                 ("edited", False), ("deleted", False)):
                if getattr(m, attr) is None:
                    setattr(m, attr, defaut)
            if m.timestamp is None:
                m.timestamp = datetime.now().astimezone()
            msgs.append(m)
    await _enregistrer(msgs)
    return len(convs), len(msgs)


async def _simple(collection: str, modele, defauts: tuple = ()) -> int:
    objets = []
    for doc_id, data in await _lire(collection):
        o, _ = _construire(modele, doc_id, data)
        for attr, defaut in defauts:
            if getattr(o, attr) is None:
                setattr(o, attr, defaut)
        objets.append(o)
    await _enregistrer(objets)
    return len(objets)


async def _sauver() -> None:
    await cache.ecrire_json("migration:etat", ETAT, 7 * 24 * 3600)


async def etat() -> dict:
    return await cache.lire_json("migration:etat") or ETAT


async def migrer() -> None:
    # Un seul lancement à la fois, tous processus confondus.
    if not await cache.prendre_verrou("migration_firestore", 3600):
        return
    ETAT.clear()
    ETAT["statut"] = "en cours"
    await _sauver()
    etapes = [
        ("utilisateurs", _users),
        ("logements", _logements),
        ("conversations", _conversations),
        ("signalements", lambda: _simple("signalements", Signalement, (
            ("logement_id", ""), ("logement_titre", ""), ("motif", ""), ("signale_par", ""),
            ("signale_par_type", "visiteur"), ("statut", "en_attente")))),
        ("transactions", lambda: _simple("transactions", Transaction, (
            ("uid", ""), ("type", ""), ("montant", 0), ("devise", "XOF"), ("statut", "en_attente"),
            ("simulation", False)))),
        ("urgences", lambda: _simple("urgences", Urgence, (
            ("uid", ""), ("type_bien", ""), ("description", ""), ("prix_min", 0), ("prix_max", 0),
            ("actif", False), ("payment_pending", True)))),
        ("publicites", lambda: _simple("publicites", Publicite, (
            ("prestataire_id", ""), ("prestataire_nom", ""), ("prestataire_phone", ""), ("titre", ""),
            ("description", ""), ("photos", []), ("actif", False), ("payment_pending", False)))),
        ("admin_notifications", lambda: _simple("admin_notifications", NotificationAdmin, (
            ("type", "nouvelle_publication"), ("logement_id", ""), ("titre", ""), ("type_bien", ""),
            ("ville", ""), ("quartier", ""), ("prestataire_nom", ""), ("prestataire_phone", ""),
            ("uid_prestataire", ""), ("lu", False)))),
        ("paiements_web", lambda: _simple("paiements_web", PaiementWeb, (
            ("uid", ""), ("type", ""), ("params", {}), ("montant", 0), ("libelle", ""),
            ("description", ""), ("email", ""), ("statut", "expire")))),
    ]
    try:
        for nom, fonction in etapes:
            ETAT["etape"] = nom
            await _sauver()
            resultat = await fonction()
            if nom == "conversations":
                ETAT["conversations"], ETAT["messages"] = resultat
            else:
                ETAT[nom] = resultat
        ETAT["statut"] = "terminée"
        ETAT.pop("etape", None)
        await cache.effacer_prefixe("pub:")
        await cache.effacer_prefixe("v:")
    except Exception as e:  # noqa: BLE001
        logger.exception("migration Firestore")
        ETAT["statut"] = "erreur"
        ETAT["erreur"] = str(e)[:500]
    await _sauver()
    logger.info("migration Firestore : %s", ETAT)
