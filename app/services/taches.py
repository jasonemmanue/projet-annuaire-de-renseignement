# app/services/taches.py
# ─────────────────────────────────────────────────────────────────────────────
# Tâches planifiées (remplacent les Cloud Functions onSchedule) :
#   • toutes les heures : fin des sponsorisations et des publicités expirées,
#     liens de paiement web expirés ;
#   • chaque semaine : suppression des messages de plus de 90 jours.
# Plusieurs processus (workers / réplicas) tournent : un verrou Redis fait
# qu'une seule exécution a lieu par créneau. Requêtes UPDATE/DELETE en masse
# (une seule instruction SQL, quel que soit le volume).
# ─────────────────────────────────────────────────────────────────────────────
import logging
from datetime import timedelta

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import delete, select, update

from app.core import cache
from app.core.serial import maintenant
from app.db.session import AsyncSessionLocal
from app.models.models import Logement, Message, PaiementWeb, Publicite

logger = logging.getLogger("taches")
_planificateur: AsyncIOScheduler | None = None


async def expirations() -> None:
    if not await cache.prendre_verrou("expirations", 50 * 60):
        return
    t = maintenant()
    async with AsyncSessionLocal() as s:
        sponsors = (await s.execute(update(Logement).where(
            Logement.is_sponsored.is_(True), Logement.sponsored_until < t)
            .values(is_sponsored=False, sponsored_until=None).returning(Logement.uid_prestataire))).scalars().all()
        pubs = (await s.execute(update(Publicite).where(
            Publicite.actif.is_(True), Publicite.expires_at < t)
            .values(actif=False).returning(Publicite.prestataire_id))).scalars().all()
        await s.execute(update(PaiementWeb).where(
            PaiementWeb.statut.in_(("en_attente", "initie")), PaiementWeb.expires_at < t)
            .values(statut="expire"))
        await s.commit()
    if sponsors:
        await cache.effacer_prefixe("pub:logements:")
        await cache.changer(*{f"mes_logements:{u}" for u in sponsors})
    if pubs:
        await cache.effacer_prefixe("pub:stories")
        await cache.changer("stories", *{f"mes_pubs:{u}" for u in pubs})
    logger.info("expirations : %s sponsorisations, %s publicités", len(sponsors), len(pubs))


async def purge_messages() -> None:
    if not await cache.prendre_verrou("purge_messages", 6 * 24 * 3600):
        return
    async with AsyncSessionLocal() as s:
        res = await s.execute(delete(Message).where(Message.timestamp < maintenant() - timedelta(days=90)))
        await s.commit()
    logger.info("purge : %s messages de plus de 90 jours supprimés", res.rowcount)


def demarrer() -> None:
    global _planificateur
    if _planificateur:
        return
    _planificateur = AsyncIOScheduler(timezone="UTC")
    _planificateur.add_job(expirations, "interval", hours=1, id="expirations",
                           next_run_time=maintenant() + timedelta(minutes=2), coalesce=True, max_instances=1)
    _planificateur.add_job(purge_messages, "interval", days=7, id="purge_messages",
                           next_run_time=maintenant() + timedelta(minutes=10), coalesce=True, max_instances=1)
    _planificateur.start()


def arreter() -> None:
    if _planificateur:
        _planificateur.shutdown(wait=False)
