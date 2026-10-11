# tests/test_parcours.py — parcours complets de l'app et de l'admin.
import asyncio

import pytest

from tests.conftest import h

pytestmark = pytest.mark.asyncio(loop_scope="session")

PREST = "prest1"
ADMIN = "adm1"
VISITEUR = {"X-Visiteur-Id": "visiteur_0b6f3f0e-8c1a-4c55-9d5e-2f3a4b5c6d7e"}


async def test_sante(client):
    r = await client.get("http://test/health")
    assert r.json()["base"] == "ok"


async def test_profil_cree_au_premier_appel(client):
    r = await client.get("/users/me", headers=h(PREST))
    assert r.status_code == 200 and r.json()["role"] == "prestataire"
    r = await client.put("/users/me", headers=h(PREST), json={
        "prenom": "Jean", "nom": "Dupont", "telephone": "+237600000000", "role": "admin",
        "compteGratuit": True})
    d = r.json()
    assert d["prenom"] == "Jean" and d["role"] == "prestataire" and d["compteGratuit"] is False
    r = await client.get("/users/me", headers=h(ADMIN, "admin@horem.test"))
    assert r.json()["role"] == "admin"
    r = await client.get(f"/users/{PREST}/public")
    assert r.json()["telephone"] == "+237600000000"


async def test_sans_jeton_refuse(client):
    assert (await client.get("/users/me")).status_code == 401
    assert (await client.get("/users/me", headers={"Authorization": "Bearer faux"})).status_code == 401
    assert (await client.get("/admin/stats", headers=h(PREST))).status_code == 403


async def test_annonce_brouillon_paiement_publication(client):
    r = await client.post("/logements", headers=h(PREST), json={
        "titre": "Studio Bastos", "prix": 50000, "typeBien": "Studio", "ville": "Yaoundé",
        "quartier": "Bastos", "latitude": 3.87, "longitude": 11.52, "photos": ["https://x/a.jpg"],
        "disponible": True, "visibleAdmin": True, "paymentPending": False, "estVerifie": True})
    assert r.status_code == 200, r.text
    log = r.json()
    assert log["paymentPending"] is True and log["disponible"] is False and log["estVerifie"] is False
    assert log["prestatireNom"] == "Jean Dupont" and log["uid_prestataire"] == PREST
    lid = log["id"]

    # Invisible pour les visiteurs tant que non payé.
    ids = [x["id"] for x in (await client.get("/logements")).json()["items"]]
    assert lid not in ids
    # Impossible de l'activer sans payer.
    r = await client.patch(f"/logements/{lid}", headers=h(PREST), json={"disponible": True})
    assert r.status_code in (402, 403)

    # Paiement : montant calculé par le serveur (3 % de 50 000 = 1 500).
    r = await client.post("/paiements/publication", headers=h(PREST), json={
        "logementId": lid, "telephone": "+237600000000", "operateur": "orange_money_cm", "montant": 1})
    tx = r.json()
    assert tx["success"] and tx["montant"] == 1500
    r = await client.post("/paiements/verifier", headers=h(PREST), json={"reference": tx["reference"]})
    assert r.json()["statut"] == "en_attente"
    await asyncio.sleep(4.2)
    r = await client.post("/paiements/verifier", headers=h(PREST), json={"reference": tx["reference"]})
    assert r.json()["statut"] == "reussi"
    # Deux vérifications simultanées n'appliquent pas deux fois.
    await asyncio.gather(*[client.post("/paiements/verifier", headers=h(PREST),
                                       json={"reference": tx["reference"]}) for _ in range(3)])
    d = (await client.get(f"/logements/{lid}")).json()
    assert d["disponible"] and not d["paymentPending"] and d["publicationExpiry"]
    await asyncio.sleep(0.3)
    ids = [x["id"] for x in (await client.get("/logements")).json()["items"]]
    assert lid in ids
    # Notification admin créée une seule fois.
    r = await client.get("/admin/notifications", headers=h(ADMIN, "admin@horem.test"))
    assert sum(1 for n in r.json()["items"] if n["logementId"] == lid) == 1

    # Un autre prestataire ne peut ni modifier ni payer.
    assert (await client.patch(f"/logements/{lid}", headers=h("autre"), json={"titre": "x"})).status_code == 403
    assert (await client.post("/paiements/sponsorisation", headers=h("autre"), json={
        "logementId": lid, "telephone": "1"})).status_code == 403


async def test_pharmacie_et_validation_admin(client):
    r = await client.post("/logements", headers=h(PREST), json={"titre": "Pharmacie du Lac",
                                                                 "typeBien": "Pharmacie", "ville": "Douala"})
    p = r.json()
    assert p["disponible"] and p["visibleAdmin"] is False and not p["paymentPending"]
    ids = [x["id"] for x in (await client.get("/logements", params={"ville": "Douala"})).json()["items"]]
    assert p["id"] not in ids
    r = await client.patch(f"/admin/logements/{p['id']}", headers=h(ADMIN, "admin@horem.test"),
                           json={"visibleAdmin": True, "estVerifie": True})
    assert r.json()["visibleAdmin"] and r.json()["estVerifie"]
    await asyncio.sleep(0.3)
    ids = [x["id"] for x in (await client.get("/logements", params={"ville": "Douala"})).json()["items"]]
    assert p["id"] in ids


async def test_messagerie_visiteur_et_polling(client):
    logs = (await client.get("/logements/mes", headers=h(PREST))).json()["items"]
    lid = logs[0]["id"]
    r = await client.post("/conversations", headers=VISITEUR, json={
        "prestataireId": PREST, "logementId": lid, "logementTitre": "Studio"})
    conv = r.json()
    assert conv["contact_label"] == "Contact1"
    r2 = await client.post("/conversations", headers=VISITEUR, json={
        "prestataireId": PREST, "logementId": lid})
    assert r2.json()["id"] == conv["id"]
    cid = conv["id"]
    r = await client.post(f"/conversations/{cid}/messages", headers=VISITEUR, json={"type": "text", "text": "Bonjour"})
    assert r.status_code == 200
    inbox = (await client.get("/conversations", headers=h(PREST))).json()
    assert inbox["items"][0][f"unread_{PREST}"] == 1
    msgs = (await client.get(f"/conversations/{cid}/messages", headers=h(PREST))).json()
    assert [m["text"] for m in msgs["items"]] == ["Bonjour"]
    # Un tiers n'a pas accès.
    assert (await client.get(f"/conversations/{cid}/messages", headers=h("intrus"))).status_code == 403
    assert (await client.get(f"/conversations/{cid}/messages",
                             headers={"X-Visiteur-Id": "visiteur_ffffffff-ffff-ffff-ffff-ffffffffffff"})).status_code == 403
    await client.post(f"/conversations/{cid}/lu", headers=h(PREST))
    n = (await client.get("/conversations/non-lus", headers=h(PREST))).json()
    assert n["total"] == 0


async def test_urgence_visiteur_anonyme(client):
    anon = h("anon1", "anon")
    r = await client.post("/urgences", headers=anon, json={"typeBien": "Studio", "prixMin": 10000,
                                                           "prixMax": 60000, "actif": True})
    a = r.json()
    assert a["actif"] is False and a["paymentPending"] is True
    r = await client.post("/paiements/urgence", headers=anon, json={"alerteId": a["id"], "telephone": "1"})
    assert r.json()["montant"] == 200
    await asyncio.sleep(4.2)
    await client.post("/paiements/verifier", headers=anon, json={"reference": r.json()["reference"]})
    a = (await client.get("/urgences", headers=anon)).json()["items"][0]
    assert a["actif"] and a["expiresAt"]


async def test_publicite_et_stories(client):
    r = await client.post("/publicites", headers=h(PREST), json={"titre": "Promo", "photos": ["https://x/p.jpg"],
                                                                 "actif": True})
    pub = r.json()
    assert pub["actif"] is False and pub["paymentPending"] is True
    r = await client.post("/paiements/publicite", headers=h(PREST), json={"publiciteId": pub["id"], "telephone": "1"})
    await asyncio.sleep(4.2)
    await client.post("/paiements/verifier", headers=h(PREST), json={"reference": r.json()["reference"]})
    await asyncio.sleep(0.3)
    stories = (await client.get("/publicites/diffusables")).json()["items"]
    assert pub["id"] in [s["id"] for s in stories]


async def test_compte_gratuit(client):
    adm = h(ADMIN, "admin@horem.test")
    await client.get("/users/me", headers=h("gratuit1"))
    await client.patch("/admin/users/gratuit1", headers=adm, json={"compteGratuit": True})
    r = await client.post("/logements", headers=h("gratuit1"), json={"titre": "Villa", "prix": 900000,
                                                                     "typeBien": "Villa", "ville": "Kribi"})
    lid = r.json()["id"]
    r = await client.post(f"/logements/{lid}/activer-gratuit", headers=h("gratuit1"))
    assert r.json()["disponible"] and r.json()["publicationExpiry"]
    # Un compte normal ne peut pas.
    assert (await client.post(f"/logements/{lid}/activer-gratuit", headers=h(PREST))).status_code == 402


async def test_vues_et_stats(client):
    lid = (await client.get("/logements/mes", headers=h(PREST))).json()["items"][0]["id"]
    for i in range(3):
        await client.post(f"/logements/{lid}/vue", headers={"X-Visiteur-Id": f"visiteur_{i:08d}-0000-0000-0000-000000000000"})
    s = (await client.get("/logements/mes/statistiques", headers=h(PREST))).json()
    assert s["totalVues"] >= 3
    e = (await client.get(f"/logements/{lid}/evolution-vues?jours=7", headers=h(PREST))).json()
    assert e["points"][-1]["vues"] >= 3


async def test_admin_listes(client):
    adm = h(ADMIN, "admin@horem.test")
    for chemin in ("/admin/stats", "/admin/logements?filtre=brouillon", "/admin/users?q=Jean",
                   "/admin/conversations", "/admin/transactions", "/admin/urgences",
                   "/admin/publicites", "/admin/signalements"):
        r = await client.get(chemin, headers=adm)
        assert r.status_code == 200, (chemin, r.text)
    r = await client.post("/signalements", headers=VISITEUR, json={"logementId": "x", "motif": "Arnaque"})
    assert r.json()["signalePar"].startswith("visiteur_")


async def test_lien_web_ios(client):
    lid = (await client.get("/logements/mes", headers=h(PREST))).json()["items"][0]["id"]
    from app.models.models import PaiementWeb
    from app.db.session import AsyncSessionLocal
    async with AsyncSessionLocal() as s:
        s.add(PaiementWeb(id="a" * 32, uid=PREST, type="sponsorisation", target_id=lid,
                          params={"duree": "1s"}, montant=500, libelle="Mise en avant", description="",
                          email="j@x.cm", statut="en_attente"))
        await s.commit()
    r = await client.get(f"/paiements/web/{'a' * 32}")
    assert r.json()["montant"] == 500 and "email" not in r.json()
    r = await client.post(f"/paiements/web/{'a' * 32}/initier", json={"telephone": "1", "operateur": "mtn"})
    assert r.json()["success"]
    await asyncio.sleep(4.2)
    r = await client.get(f"/paiements/web/{'a' * 32}")
    assert r.json()["statut"] == "reussi"
    d = (await client.get(f"/logements/{lid}")).json()
    assert d["isSponsored"]


async def test_suppression_annonce(client):
    lid = (await client.get("/logements/mes", headers=h(PREST))).json()["items"][-1]["id"]
    assert (await client.delete(f"/logements/{lid}", headers=h(PREST))).json()["success"]
    assert (await client.get(f"/logements/{lid}")).status_code == 404


async def test_polling_inchange(client):
    import os
    if not os.environ.get("TEST_FAKEREDIS"):
        pytest.skip("Redis requis")
    r1 = (await client.get("/conversations", headers=h(PREST))).json()
    r2 = (await client.get("/conversations", headers=h(PREST), params={"v": r1["v"]})).json()
    assert r2 == {"inchange": True, "v": r1["v"]}
    cid = r1["items"][0]["id"]
    await client.post(f"/conversations/{cid}/messages", headers=VISITEUR, json={"type": "text", "text": "Re"})
    r3 = (await client.get("/conversations", headers=h(PREST), params={"v": r1["v"]})).json()
    assert "items" in r3 and r3["v"] != r1["v"]
