# app/db/session.py
# ─────────────────────────────────────────────────────────────────────────────
# Moteur async + session par requête (même schéma que l'API Prepaxia).
# La session n'est commitée que si la requête a écrit quelque chose.
# ─────────────────────────────────────────────────────────────────────────────
import os

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Session

from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,
    pool_size=int(os.getenv("DB_POOL_SIZE", "10")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "20")),
    pool_recycle=1800,
)

AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


@event.listens_for(Session, "do_orm_execute")
def _marquer_ecriture(etat) -> None:
    if not etat.is_select:
        etat.session.info["ecrit"] = True


@event.listens_for(Session, "after_flush")
def _marquer_flush(session, _contexte) -> None:
    session.info["ecrit"] = True


def _a_ecrit(s: Session) -> bool:
    return bool(s.info.get("ecrit") or s.new or s.dirty or s.deleted)


def marquer(db: AsyncSession, *cles: str) -> None:
    """Versions (app/core/cache.py) à incrémenter APRÈS le commit : un écran
    qui interroge entre-temps ne doit pas voir la nouvelle version avec les
    anciennes données."""
    db.sync_session.info.setdefault("versions", set()).update(c for c in cles if c)


def apres_commit(db: AsyncSession, fabrique, nom: str = "apres_commit") -> None:
    """Tâche de fond (push, e-mail, cache…) lancée seulement une fois les
    écritures validées. `fabrique` : fonction sans argument → coroutine."""
    db.sync_session.info.setdefault("apres", []).append((fabrique, nom))


async def _publier_versions(session: AsyncSession) -> None:
    cles = session.sync_session.info.pop("versions", None)
    if cles:
        from app.core import cache
        await cache.changer(*cles)
    taches = session.sync_session.info.pop("apres", None)
    if taches:
        from app.services.fond import lancer
        for fabrique, nom in taches:
            lancer(fabrique(), nom)


async def valider(session: AsyncSession) -> None:
    """Commit explicite (sessions hors requête) + versions et tâches."""
    await session.commit()
    await _publier_versions(session)


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
            if _a_ecrit(session.sync_session):
                await session.commit()
                await _publier_versions(session)
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
