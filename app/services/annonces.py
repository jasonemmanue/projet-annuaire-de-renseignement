# app/services/annonces.py
# ─────────────────────────────────────────────────────────────────────────────
# Effets d'une annonce qui devient visible (anciens déclencheurs Firestore) :
#   • push « Nouvelle annonce » à tous (une seule fois par annonce) ;
#   • push immédiat aux visiteurs dont l'alerte prioritaire correspond ;
#   • notification + e-mail admin pour une publication payée.
# Tout part en tâche de fond : la réponse HTTP n'attend pas.
# ─────────────────────────────────────────────────────────────────────────────
import logging

from sqlalchemy import select, update

from app.core import cache
from app.core.config import settings
from app.core.serial import maintenant, nouvel_id, vers_api
from app.db.session import AsyncSessionLocal, apres_commit, marquer
from app.models.models import Logement, NotificationAdmin, Urgence
from app.services import email, push

logger = logging.getLogger("annonces")
SEUILS_VUES = (10, 50, 100, 500)


async def invalider_listes() -> None:
    """Les listes publiques en cache ne sont plus à jour."""
    await cache.effacer_prefixe("pub:logements:")
    await cache.changer("logements")


async def _diffuser_nouvelle(logement_id: str) -> None:
    async with AsyncSessionLocal() as s:
        # UPDATE … WHERE annonce_diffusee = false : une seule diffusion même
        # si deux événements arrivent en même temps.
        res = await s.execute(
            update(Logement).where(Logement.id == logement_id, Logement.annonce_diffusee.is_(False))
            .values(annonce_diffusee=True).returning(Logement.titre, Logement.ville,
                                                     Logement.quartier, Logement.uid_prestataire))
        ligne = res.first()
        await s.commit()
    if not ligne:
        return
    titre, ville, quartier, auteur = ligne
    await push.diffuser(
        "🏠 Nouvelle annonce", f"{titre or 'Nouvelle annonce'} – {quartier or ''}, {ville or ''}",
        {"type": "nouvelle_annonce", "logementId": logement_id, "titre": titre or "",
         "ville": ville or "", "quartier": quartier or ""},
        exclure=auteur)


async def _alertes_urgence(logement_id: str) -> None:
    async with AsyncSessionLocal() as s:
        log = await s.get(Logement, logement_id)
        if not log or not log.type_bien:
            return
        prix = log.prix or 0
        alertes = (await s.execute(select(Urgence).where(
            Urgence.actif.is_(True), Urgence.type_bien == log.type_bien,
            Urgence.expires_at > maintenant(), Urgence.prix_min <= prix))).scalars().all()
        cibles = [(a.id, a.uid) for a in alertes if not (a.prix_max and prix > a.prix_max)]
        titre, ville, type_bien = log.titre or "Nouveau bien", log.ville or "", log.type_bien
    for alerte_id, uid in cibles:
        await push.notifier_utilisateur(
            uid, f"🔴 {titre} — {ville}",
            f"Un {type_bien} à {int(prix)} XAF correspond à votre alerte ! Consultez-le en priorité.",
            {"type": "alerte_urgence", "logementId": logement_id, "alerteId": alerte_id})
    if cibles:
        logger.info("alertes urgence : %s visiteurs notifiés pour %s", len(cibles), logement_id)


async def _notifier_admin(logement_id: str, type_: str) -> None:
    async with AsyncSessionLocal() as s:
        log = await s.get(Logement, logement_id)
        if not log:
            return
        s.add(NotificationAdmin(
            id=nouvel_id(), type=type_, logement_id=log.id, titre=log.titre or log.type_bien or "",
            type_bien=log.type_bien or "", ville=log.ville or "", quartier=log.quartier or "",
            latitude=log.latitude, longitude=log.longitude, prestataire_nom=log.prestataire_nom or "",
            prestataire_phone=log.prestataire_phone or "", uid_prestataire=log.uid_prestataire or "",
            lu=False, extra={}))
        donnees = vers_api(log, Logement.CHAMPS)
        await s.commit()
    await cache.changer("admin_notifications", f"notifs:{donnees.get('uid_prestataire')}")
    if settings.ADMIN_NOTIF_EMAIL:
        await email.envoyer(
            settings.ADMIN_NOTIF_EMAIL,
            f"[Horem+] Nouvelle annonce : {donnees.get('titre') or donnees.get('typeBien') or 'sans titre'}",
            email.html_nouvelle_publication(donnees, logement_id))


def annonce_publiee(db, logement_id: str, payee: bool) -> None:
    """À appeler quand une annonce devient visible pour les visiteurs. Les
    effets partent une fois les écritures de `db` validées."""
    apres_commit(db, invalider_listes, "invalider_listes")
    apres_commit(db, lambda: _diffuser_nouvelle(logement_id), "diffuser_annonce")
    apres_commit(db, lambda: _alertes_urgence(logement_id), "alertes_urgence")
    if payee:
        apres_commit(db, lambda: _notifier_admin(logement_id, "nouvelle_publication"), "notifier_admin")


def annonce_modifiee(db, *uids: str) -> None:
    """Listes publiques + « Mes annonces » à rafraîchir après le commit."""
    apres_commit(db, invalider_listes, "invalider_listes")
    marquer(db, *[f"mes_logements:{u}" for u in uids if u])


async def verifier_seuils_vues(logement_id: str, avant: int, apres: int) -> None:
    franchis = [s for s in SEUILS_VUES if avant < s <= apres]
    if not franchis:
        return
    async with AsyncSessionLocal() as s:
        log = await s.get(Logement, logement_id, with_for_update=True)
        if not log:
            return
        deja = list(log.vues_milestones or [])
        nouveaux = [x for x in franchis if x not in deja]
        if not nouveaux:
            return
        log.vues_milestones = deja + nouveaux
        uid, titre = log.uid_prestataire, log.titre or "Votre annonce"
        await s.commit()
    for seuil in nouveaux:
        await push.notifier_utilisateur(
            uid, "🎉 Milestone atteint !",
            f"Votre annonce « {titre} » vient d'atteindre {seuil} vues !",
            {"type": "logement_update", "logementId": logement_id, "vues": apres, "seuil": seuil})
