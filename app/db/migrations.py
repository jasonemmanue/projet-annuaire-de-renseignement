# app/db/migrations.py
# ─────────────────────────────────────────────────────────────────────────────
# Schéma créé / complété au démarrage (comme l'API Prepaxia) :
#   1. create_all : tables et index manquants (idempotent) ;
#   2. MIGRATIONS : ajouts ultérieurs de colonnes (ALTER … IF NOT EXISTS),
#      une instruction SQL par entrée (asyncpg n'en accepte qu'une).
# Un verrou consultatif empêche deux processus de migrer en même temps.
# ─────────────────────────────────────────────────────────────────────────────
import logging

from sqlalchemy import text

from app.db.session import Base, engine
from app.models import models  # noqa: F401 — enregistre les tables

logger = logging.getLogger("migrations")

MIGRATIONS: list[tuple[str, str]] = [
    ("Index priorité des annonces",
     "CREATE INDEX IF NOT EXISTS ix_logements_priorite ON logements (is_sponsored, sponsored_until, created_at DESC)"),
    ("Index transactions en attente",
     "CREATE INDEX IF NOT EXISTS ix_tx_attente ON transactions (uid, type, statut, created_at DESC)"),
    ("Index jetons push",
     "CREATE INDEX IF NOT EXISTS ix_utilisateurs_fcm ON utilisateurs (id) WHERE fcm_token IS NOT NULL"),
    ("Index urgences actives",
     "CREATE INDEX IF NOT EXISTS ix_urgences_actives ON urgences (type_bien, expires_at) WHERE actif"),
]


async def run_migrations() -> None:
    async with engine.begin() as conn:
        await conn.execute(text("SELECT pg_advisory_xact_lock(724001)"))
        await conn.run_sync(Base.metadata.create_all)
        for description, sql in MIGRATIONS:
            try:
                await conn.execute(text(sql))
            except Exception as e:  # noqa: BLE001
                logger.error("❌ Migration « %s » : %s", description, e)
                raise
    logger.info("✅ Schéma à jour (%s migrations)", len(MIGRATIONS))
