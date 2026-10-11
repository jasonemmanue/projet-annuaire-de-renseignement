# app/main.py
# ─────────────────────────────────────────────────────────────────────────────
# API Horem+ — remplace Firestore et les Cloud Functions.
# Firebase reste utilisé pour : l'authentification, le stockage des fichiers
# (Storage) et les notifications push (FCM).
# ─────────────────────────────────────────────────────────────────────────────
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")

from contextlib import asynccontextmanager  # noqa: E402

from fastapi import FastAPI, HTTPException, Request  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.middleware.gzip import GZipMiddleware  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.api.v1.routes import (  # noqa: E402
    admin, conversations, divers, logements, paiements, publicites, users,
)
from app.core import cache  # noqa: E402
from app.core.config import settings  # noqa: E402
from app.core.serial import poser_base_requete  # noqa: E402
from app.db.session import engine  # noqa: E402

log = logging.getLogger("startup")

if settings.SENTRY_DSN:
    import sentry_sdk
    sentry_sdk.init(dsn=settings.SENTRY_DSN, environment=settings.ENVIRONMENT, traces_sample_rate=0.05)


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        from app.db.migrations import run_migrations
        await run_migrations()
    except Exception as e:  # noqa: BLE001 — l'API démarre quand même
        log.error("❌ Migrations : %s", e)
    from app.core.firebase import ensure_firebase
    ensure_firebase()
    from app.services import taches
    taches.demarrer()
    yield
    taches.arreter()
    await engine.dispose()


docs = not settings.est_production or settings.DOCS_ENABLED
app = FastAPI(
    title=settings.APP_NAME, version=settings.APP_VERSION, lifespan=lifespan,
    docs_url="/docs" if docs else None, redoc_url=None, openapi_url="/openapi.json" if docs else None,
)

origines = settings.cors_origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=origines or ["*"],
    allow_credentials="*" not in origines,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1024)


@app.middleware("http")
async def contexte(request: Request, call_next):
    if not settings.PUBLIC_BASE_URL:
        proto = request.headers.get("x-forwarded-proto", request.url.scheme)
        poser_base_requete(f"{proto}://{request.headers.get('host', request.url.netloc)}")
    # Limite globale anti-abus : 600 requêtes / minute par adresse IP.
    ip = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or \
        (request.client.host if request.client else "?")
    if request.url.path.startswith("/api/") and not request.url.path.endswith("/webhook") \
            and await cache.depasse_limite(f"ip:{ip}", 600, 60):
        return JSONResponse({"detail": "Trop de requêtes, réessayez dans un instant."}, status_code=429)
    return await call_next(request)


@app.exception_handler(HTTPException)
async def erreur_http(request: Request, exc: HTTPException):
    """Erreur au format des anciennes Cloud Functions : {success:false, error}
    (et `detail` pour les clients FastAPI)."""
    d = exc.detail
    if isinstance(d, dict):
        corps = {"success": False, **d}
        corps.setdefault("detail", d.get("error"))
    else:
        corps = {"success": False, "error": d, "detail": d}
    return JSONResponse(corps, status_code=exc.status_code, headers=getattr(exc, "headers", None))


PREFIXE = "/api/v1"
for module in (users, logements, conversations, divers, publicites, paiements, admin):
    app.include_router(module.router, prefix=PREFIXE)


@app.get("/")
async def racine():
    return {"service": settings.APP_NAME, "version": settings.APP_VERSION}


@app.get("/health")
async def sante():
    etat = {"status": "ok", "base": "ok", "redis": "absent"}
    try:
        async with engine.connect() as c:
            await c.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001
        etat["base"], etat["status"] = "erreur", "degrade"
    r = cache.client()
    if r:
        try:
            await r.ping()
            etat["redis"] = "ok"
        except Exception:  # noqa: BLE001
            etat["redis"] = "erreur"
    return etat
