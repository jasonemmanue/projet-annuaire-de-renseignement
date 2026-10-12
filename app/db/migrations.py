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
    ("Logement : statut de modération",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS statut_moderation VARCHAR(20)"),
    ("Logement : motif de rejet",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS motif_rejet TEXT"),
    ("Index modération",
     "CREATE INDEX IF NOT EXISTS ix_logements_statut_moderation ON logements (statut_moderation)"),
    ("Logement : type de base (Autre)",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS type_bien_base VARCHAR(80)"),
    ("Utilisateur : préférence push modération",
     "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS notif_moderation BOOLEAN NOT NULL DEFAULT TRUE"),
    ("Utilisateur : préférence push fin de sponsorisation",
     "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS notif_fin_sponsor BOOLEAN NOT NULL DEFAULT TRUE"),
    ("Utilisateur : numéro CNI", "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS cni_numero VARCHAR(40)"),
    ("Utilisateur : CNI recto", "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS cni_recto TEXT"),
    ("Utilisateur : CNI verso", "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS cni_verso TEXT"),
    ("Utilisateur : date CNI", "ALTER TABLE utilisateurs ADD COLUMN IF NOT EXISTS cni_soumise_le TIMESTAMPTZ"),
    ("Logement : charges", "ALTER TABLE logements ADD COLUMN IF NOT EXISTS charges DOUBLE PRECISION NOT NULL DEFAULT 0"),
    ("Logement : frais d'agence",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS frais_agence DOUBLE PRECISION NOT NULL DEFAULT 0"),
    ("Logement : caution", "ALTER TABLE logements ADD COLUMN IF NOT EXISTS caution DOUBLE PRECISION NOT NULL DEFAULT 0"),
    ("Logement : mois d'avance", "ALTER TABLE logements ADD COLUMN IF NOT EXISTS mois_avance INTEGER NOT NULL DEFAULT 1"),
    ("Logement : prix total", "ALTER TABLE logements ADD COLUMN IF NOT EXISTS prix_total DOUBLE PRECISION NOT NULL DEFAULT 0"),
    # Annonces antérieures au détail du prix : total = prix (idempotent).
    ("Logement : prix total initial", "UPDATE logements SET prix_total = prix WHERE prix_total = 0 AND prix > 0"),
    ("Index prix total", "CREATE INDEX IF NOT EXISTS ix_logements_prix_total ON logements (prix_total)"),
    # Les annonces existantes repartent pour 21 jours à l'ajout de la colonne.
    ("Logement : date d'actualisation",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS actualise_le TIMESTAMPTZ NOT NULL DEFAULT now()"),
    ("Index actualisation", "CREATE INDEX IF NOT EXISTS ix_logements_actualise_le ON logements (actualise_le)"),
    ("Logement : rappel d'actualisation",
     "ALTER TABLE logements ADD COLUMN IF NOT EXISTS rappel_actualisation BOOLEAN NOT NULL DEFAULT FALSE"),
    ("Index téléphone utilisateur", "CREATE INDEX IF NOT EXISTS ix_utilisateurs_telephone ON utilisateurs (telephone)"),
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
