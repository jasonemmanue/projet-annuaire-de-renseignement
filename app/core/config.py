# app/core/config.py
# ─────────────────────────────────────────────────────────────────────────────
# Réglages de l'API Horem+, lus dans les variables d'environnement (Railway →
# Variables) ou dans un fichier .env en local.
# ─────────────────────────────────────────────────────────────────────────────
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    APP_NAME: str = "Horem+ API"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    DEBUG: bool = False
    # /docs masqué en production sauf DOCS_ENABLED=true.
    DOCS_ENABLED: bool = False

    # Base de données (Railway : ${{Postgres.DATABASE_URL}})
    DATABASE_URL: str

    # Redis (Railway : ${{Redis.REDIS_URL}}) : cache des listes publiques,
    # compteurs de version (polling léger), limitation de débit, verrous des
    # tâches planifiées. Vide = l'API fonctionne sans (mode dégradé).
    REDIS_URL: str = ""

    # URL publique de l'API, SANS /api/v1 (ex. https://horem-api-production.up.railway.app).
    # Sert à construire les liens des fichiers et l'adresse du webhook GeniusPay.
    # Vide = déduite de la requête entrante.
    PUBLIC_BASE_URL: str = ""

    # CORS : origines séparées par des virgules (« * » = toutes).
    CORS_ORIGINS: str = "*"

    # Firebase : UNIQUEMENT l'authentification (vérification des jetons) et
    # l'envoi des notifications push (FCM). JSON du compte de service encodé
    # en base64 (une seule ligne).
    FIREBASE_CREDENTIALS: str = ""
    # Identifiant du projet Firebase (audience des jetons). Lu dans le compte
    # de service s'il est fourni.
    FIREBASE_PROJECT_ID: str = "sgk-home"

    # Administrateurs : e-mails séparés par des virgules. À chaque connexion,
    # un compte dont l'e-mail figure ici reçoit le rôle admin.
    ADMIN_EMAILS: str = ""
    # E-mail qui reçoit les alertes « nouvelle publication » (vide = aucun).
    # L'ancienne adresse des Cloud Functions (« Horem+49@gmail.com ») était
    # issue d'un renommage automatique : à remplacer par la vraie adresse.
    ADMIN_NOTIF_EMAIL: str = ""

    # GeniusPay (Mobile Money via PawaPay)
    GENIUSPAY_BASE_URL: str = "https://geniuspay.ci/api/v1/merchant"
    GENIUSPAY_API_KEY: str = ""
    GENIUSPAY_SECRET_KEY: str = ""
    GENIUSPAY_WEBHOOK_SECRET: str = ""
    # Simulation des paiements (tests sans argent réel) : le paiement réussit
    # tout seul après quelques secondes. JAMAIS en production.
    PAIEMENTS_SIMULES: bool = False
    PAIEMENT_SUCCESS_URL: str = ""
    PAIEMENT_ERROR_URL: str = ""

    # Page web de paiement iOS (dashboard admin) : https://<admin>/pay
    WEB_PAY_BASE_URL: str = "https://immoconnect-admin.up.railway.app/pay"

    # E-mails : Railway bloque le SMTP sortant → API HTTP Gmail ou Resend.
    GMAIL_API_CLIENT_ID: str = ""
    GMAIL_API_CLIENT_SECRET: str = ""
    GMAIL_API_REFRESH_TOKEN: str = ""
    GMAIL_API_SENDER: str = ""
    RESEND_API_KEY: str = ""
    RESEND_FROM_EMAIL: str = "Horem+ <onboarding@resend.dev>"

    # Bucket Firebase Storage (les fichiers restent dans Firebase Storage ;
    # l'API supprime ceux d'une annonce / pub supprimée).
    FIREBASE_STORAGE_BUCKET: str = "sgk-home.firebasestorage.app"

    # Sentry (facultatif)
    SENTRY_DSN: str = ""

    @field_validator("DATABASE_URL")
    @classmethod
    def _asyncpg(cls, v: str) -> str:
        """Railway fournit postgresql:// : SQLAlchemy async veut +asyncpg, et
        asyncpg ne comprend pas sslmode (il veut ssl)."""
        if v.startswith("postgres://"):
            v = "postgresql://" + v[len("postgres://"):]
        if v.startswith("postgresql://"):
            v = "postgresql+asyncpg://" + v[len("postgresql://"):]
        parts = urlsplit(v)
        query = dict(parse_qsl(parts.query))
        if "sslmode" in query:
            mode = query.pop("sslmode")
            if mode in ("require", "verify-ca", "verify-full"):
                query["ssl"] = "require"
        return urlunsplit(parts._replace(query=urlencode(query)))

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @property
    def admin_emails(self) -> set[str]:
        return {e.strip().lower() for e in self.ADMIN_EMAILS.split(",") if e.strip()}

    @property
    def est_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"


settings = Settings()
