# app/services/paiements.py
# ─────────────────────────────────────────────────────────────────────────────
# Cycle d'un paiement Mobile Money (portage de functions/index.js) :
#   1. creer_transaction : GeniusPay + ligne `transactions` en attente ;
#   2. finaliser : webhook OU vérification active (polling de l'app) ;
#   3. appliquer_reussite : effet métier (annonce publiée, sponsoring, pub,
#      visibilité, alerte urgence, premium) + notifications.
#
# Une transaction n'est appliquée qu'UNE fois : la ligne est verrouillée
# (SELECT … FOR UPDATE) et son statut testé sous ce verrou, ce qui protège du
# webhook et du polling qui arrivent en même temps.
# ─────────────────────────────────────────────────────────────────────────────
import logging
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.config import settings
from app.core.serial import base_publique, maintenant
from app.models.models import Logement, PaiementWeb, Publicite, Transaction, Urgence, Utilisateur
from app.services import annonces, geniuspay, push, tarifs
from app.db.session import apres_commit, marquer

logger = logging.getLogger("paiements")


def url_webhook() -> str:
    return f"{base_publique()}/api/v1/paiements/webhook"


async def creer_transaction(db: AsyncSession, *, uid: str, type_: str, montant: int,
                            telephone: str, operateur: str | None, pays: str | None,
                            description: str, email: str = "", internal_ref: str,
                            champs: dict | None = None) -> Transaction:
    pays_iso, mmo = geniuspay.resoudre_pays(pays, operateur)
    champs = champs or {}
    if settings.PAIEMENTS_SIMULES:
        reference = f"SIMU-{type_}-{internal_ref[-12:]}-{int(maintenant().timestamp() * 1000)}"
        paiement = {"reference": reference, "payment_url": "", "transaction_id": reference}
    else:
        try:
            paiement = await geniuspay.creer_paiement(
                reference=internal_ref, montant=montant, description=description, email=email,
                telephone=telephone, pays=pays_iso, mmo_provider=mmo,
                metadata={"uid": uid, "type": type_, "pays": pays_iso,
                          **{k: v for k, v in champs.items() if isinstance(v, (str, int))}},
                callback_url=url_webhook())
        except geniuspay.GeniusPayErreur as e:
            logger.error("initiation %s : %s", type_, e)
            raise HTTPException(502, {"success": False, "error": "Erreur lors de l'initiation du paiement.",
                                      "geniuspayError": str(e)})
    tx = Transaction(
        id=str(paiement["reference"]), uid=uid, type=type_, montant=montant, devise="XOF",
        statut="en_attente", internal_ref=internal_ref, telephone=telephone,
        channel=operateur, pays=pays_iso, checkout_url=paiement["payment_url"],
        geniuspay_transaction_id=paiement["transaction_id"],
        simulation=settings.PAIEMENTS_SIMULES, extra={}, **champs)
    db.add(tx)
    await db.flush()
    return tx


async def transaction_recente(db: AsyncSession, uid: str, type_: str, cible: str | None) -> Transaction | None:
    """Anti-doublon : un paiement identique lancé il y a moins de 5 minutes."""
    q = select(Transaction).where(
        Transaction.uid == uid, Transaction.type == type_, Transaction.statut == "en_attente",
        Transaction.created_at > maintenant() - timedelta(minutes=5))
    if cible:
        q = q.where((Transaction.logement_id == cible) | (Transaction.publicite_id == cible))
    return (await db.execute(q.order_by(Transaction.created_at.desc()).limit(1))).scalar_one_or_none()


def _push(db: AsyncSession, uid: str, titre: str, corps: str, data: dict) -> None:
    apres_commit(db, lambda: push.notifier_utilisateur(uid, titre, corps, data), "push")


def _date_fr(d) -> str:
    return d.strftime("%d/%m/%Y")


async def appliquer_reussite(db: AsyncSession, tx: Transaction) -> None:
    """Effet métier d'un paiement réussi. Appelé sous le verrou de `tx`."""
    t = maintenant()
    uid = tx.uid
    if tx.type == "premium":
        u = await db.get(Utilisateur, uid)
        if u:
            u.is_premium = True
            u.premium_expiry = t + timedelta(days=tarifs.PREMIUM_DUREE_JOURS)
        _push(db, uid, "🎉 Bienvenue dans le Pack Premium !",
                                         "Vos avantages Premium sont activés.",
                                         {"type": "transaction", "reference": tx.id})

    elif tx.type in ("publication", "visibilite"):
        log = await db.get(Logement, tx.logement_id or "", with_for_update=True)
        if log:
            if tx.type == "visibilite":
                fin = t + timedelta(days=tarifs.VISIBILITE_DUREE_JOURS)
                log.visibilite_expiry = fin
                titre_push, corps = "✅ Fiche activée !", f"Votre fiche « {log.titre or 'votre fiche'} » est visible jusqu'au {_date_fr(fin)}."
            else:
                jours = tx.duree_jours if (tx.duree_jours or 0) > 0 else tarifs.PUBLICATION_DUREE_JOURS
                fin = t + timedelta(days=jours)
                log.publication_expiry = fin
                lib = "1 an" if jours >= 360 else "6 mois" if jours >= 175 else "3 mois" if jours >= 85 else "1 mois"
                titre_push = "✅ Annonce publiée !"
                corps = f"Votre annonce « {log.titre or 'votre annonce'} » est visible pendant {lib} (jusqu'au {_date_fr(fin)})."
            log.disponible = True
            log.payment_pending = False
            log.actualise_le, log.rappel_actualisation = t, False
            # Une annonce payée est visible par défaut (l'admin peut la bloquer).
            if log.visible_admin is not True:
                log.visible_admin = True
            await db.flush()
            annonces.annonce_publiee(db, log.id, payee=True)
            _push(db, uid, titre_push, corps, {
                "type": "logement_update", "logementId": log.id, "reference": tx.id})
            marquer(db, f"mes_logements:{log.uid_prestataire}")

    elif tx.type == "sponsorisation":
        log = await db.get(Logement, tx.logement_id or "", with_for_update=True)
        if log:
            code = tx.duree if tx.duree in tarifs.SPONSOR_DUREES else "1m"
            fin = t + timedelta(days=tarifs.SPONSOR_DUREES[code])
            log.is_sponsored, log.sponsored_until, log.sponsored_at = True, fin, t
            await db.flush()
            annonces.annonce_modifiee(db)
            marquer(db, f"mes_logements:{log.uid_prestataire}")
            _push(db, 
                uid, "🚀 Annonce mise en avant !",
                f"Votre annonce « {log.titre or 'votre annonce'} » est mise en avant pendant "
                f"{tarifs.SPONSOR_LIBELLES[code]} (jusqu'au {_date_fr(fin)}).",
                {"type": "logement_update", "logementId": log.id, "reference": tx.id})

    elif tx.type == "publicite":
        pub = await db.get(Publicite, tx.publicite_id or "", with_for_update=True)
        if pub:
            fin = t + timedelta(days=tarifs.PUBLICITE_DUREE_JOURS)
            pub.actif, pub.payment_pending, pub.expires_at = True, False, fin
            pub.transaction_ref, pub.dernier_paiement_at = tx.id, t
            await db.flush()
            apres_commit(db, lambda: cache.effacer_prefixe("pub:stories"), "cache_stories")
            marquer(db, "stories", f"mes_pubs:{pub.prestataire_id}")
            _push(db, uid, "📣 Publicité en ligne !",
                                             f"Votre publicité est diffusée jusqu'au {_date_fr(fin)}.",
                                             {"type": "publicite", "publiciteId": pub.id,
                                              "reference": tx.id})

    elif tx.type == "urgence":
        alerte = await db.get(Urgence, tx.logement_id or "", with_for_update=True)
        if alerte:
            alerte.actif, alerte.payment_pending = True, False
            alerte.expires_at = t + timedelta(hours=tarifs.URGENCE_DUREE_HEURES)
            alerte.reference = tx.id
            await db.flush()
            marquer(db, f"urgences:{alerte.uid}")
            _push(db, 
                uid, "✅ Alerte prioritaire activée (48 H)",
                "Vous serez notifié en premier dès qu'un bien correspondant sera publié.",
                {"type": "urgence", "alerteId": alerte.id, "reference": tx.id})


async def finaliser(db: AsyncSession, reference: str, statut_brut: str) -> str:
    """Applique un statut GeniusPay. Renvoie en_attente | reussi | echoue."""
    tx = (await db.execute(select(Transaction).where(Transaction.id == reference)
                           .with_for_update())).scalar_one_or_none()
    if tx is None:
        return "inconnue"
    if tx.statut in ("reussi", "echoue"):
        return tx.statut
    statut_brut = (statut_brut or "PENDING").upper()
    tx.dernier_statut_brut = statut_brut
    if statut_brut in geniuspay.SUCCES:
        tx.statut, tx.confirmed_at = "reussi", maintenant()
        await appliquer_reussite(db, tx)
    elif statut_brut in geniuspay.ECHECS:
        tx.statut, tx.confirmed_at = "echoue", maintenant()
        _push(db, 
            tx.uid, "Paiement échoué",
            "Votre paiement Mobile Money n'a pas abouti. Vérifiez votre solde et réessayez.",
            {"type": "transaction", "reference": tx.id})
    if tx.payment_token and tx.statut in ("reussi", "echoue"):
        pw = await db.get(PaiementWeb, tx.payment_token)
        if pw:
            pw.statut, pw.reference, pw.confirmed_at = tx.statut, tx.id, maintenant()
    await db.flush()
    marquer(db, f"tx:{tx.id}", f"pw:{tx.payment_token}" if tx.payment_token else "")
    return tx.statut


async def verifier_actif(db: AsyncSession, tx: Transaction) -> str:
    """Interroge GeniusPay (ou la simulation) puis finalise."""
    if tx.statut in ("reussi", "echoue"):
        return tx.statut
    if tx.simulation:
        age = (maintenant() - tx.created_at).total_seconds()
        return await finaliser(db, tx.id, "COMPLETED" if age >= 4 else "PENDING")
    statut = await geniuspay.verifier_paiement(tx.id)
    return await finaliser(db, tx.id, statut)
