# tests/conftest.py
# Tests de bout en bout sur un vrai PostgreSQL local.
#   TEST_DATABASE_URL=postgresql://… pytest      (sinon : pgserver embarqué)
# Les jetons Firebase sont simulés : « tok:<uid>[:anon][:email] ».
import asyncio
import os

import pytest
import pytest_asyncio


def _url_base() -> str:
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        return url
    import pgserver
    srv = pgserver.get_server(os.path.join(os.environ.get("TEMP", "/tmp"), "horem_pg"), cleanup_mode=None)
    return srv.get_uri()


async def _recreer(url_admin: str, nom: str) -> None:
    import asyncpg
    c = await asyncpg.connect(url_admin)
    await c.execute(f"DROP DATABASE IF EXISTS {nom} WITH (FORCE)")
    await c.execute(f"CREATE DATABASE {nom}")
    await c.close()


_BASE = _url_base()
asyncio.run(_recreer(_BASE, "horem_test"))
os.environ["DATABASE_URL"] = _BASE.rsplit("/", 1)[0] + "/horem_test"
os.environ["REDIS_URL"] = os.environ.get("TEST_REDIS_URL", "")
os.environ["PAIEMENTS_SIMULES"] = "true"
os.environ["ADMIN_EMAILS"] = "admin@horem.test"
os.environ["PUBLIC_BASE_URL"] = "https://api.test"

import httpx  # noqa: E402

from app.core import dependencies  # noqa: E402
from app.main import app  # noqa: E402


async def _faux_jeton(jeton: str) -> dict:
    if not jeton.startswith("tok:"):
        raise ValueError("jeton invalide")
    morceaux = jeton.split(":")
    uid = morceaux[1]
    claims = {"uid": uid, "firebase": {"sign_in_provider": "password"}}
    if "anon" in morceaux:
        claims["firebase"]["sign_in_provider"] = "anonymous"
    for m in morceaux[2:]:
        if "@" in m:
            claims["email"] = m
    return claims


dependencies.verifier_jeton = _faux_jeton

if os.environ.get("TEST_FAKEREDIS"):
    import fakeredis
    from app.core import cache as _cache
    _cache._client = fakeredis.aioredis.FakeRedis(decode_responses=True)


@pytest_asyncio.fixture(scope="session", loop_scope="session")
async def client():
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test/api/v1") as c:
            yield c


def h(uid: str, *extra: str) -> dict:
    return {"Authorization": "Bearer " + ":".join(["tok", uid, *extra])}
