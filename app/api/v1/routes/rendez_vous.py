# app/api/v1/routes/rendez_vous.py
# ─────────────────────────────────────────────────────────────────────────────
# Rendez-vous de visite : le chercheur (compte ou visiteur X-Visiteur-Id)
# propose une date et une heure depuis une annonce ; le prestataire accepte
# ou refuse ; le demandeur peut annuler. Chaque partie lit ses rendez-vous en
# polling versionné (clé rdv:<id>) et reçoit un push quand l'autre agit.
# ─────────────────────────────────────────────────────────────────────────────
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes._commun import versionne
from app.core.dependencies import Appelant, appelant
from app.core.serial import maintenant, nouvel_id, texte_vers_date, vers_api
from app.db.session import apres_commit, get_db, marquer
from app.models.models import Logement, RendezVous
from app.services import push

router = APIRouter(prefix="/rendez-vous", tags=["Rendez-vous"])

MAX_EN_ATTENTE_PAR_ANNONCE = 3


def api(r: RendezVous) -> dict:
    return vers_api(r, RendezVous.CHAMPS)


def _date_fr(d) -> str:
    return d.strftime("%d/%m/%Y à %H:%M")


@router.get("")
async def mes_rendez_vous(request: Request, db: AsyncSession = Depends(get_db),
                          qui: Appelant = Depends(appelant)):
    """Rendez-vous où l'appelant est demandeur ou prestataire."""
    async def produire() -> dict:
        lignes = (await db.execute(
            select(RendezVous).where(or_(RendezVous.demandeur_id == qui.id,
                                         RendezVous.prestataire_id == qui.id))
            .order_by(RendezVous.date_heure.desc()).limit(200))).scalars().all()
        return {"items": [api(r) for r in lignes]}
    return await versionne(request, f"rdv:{qui.id}", produire)


@router.post("")
async def demander(data: dict, db: AsyncSession = Depends(get_db), qui: Appelant = Depends(appelant)):
    """Corps : {logementId, dateHeure (ISO 8601), message?, nom?, telephone?}."""
    l = await db.get(Logement, str(data.get("logementId") or ""))
    if l is None:
        raise HTTPException(404, "Annonce introuvable")
    if l.uid_prestataire == qui.id:
        raise HTTPException(400, "Vous ne pouvez pas demander une visite de votre propre annonce")
    quand = texte_vers_date(data.get("dateHeure"))
    t = maintenant()
    if quand is None or quand < t + timedelta(minutes=30) or quand > t + timedelta(days=90):
        raise HTTPException(400, {"code": "date_invalide",
                                  "error": "Choisissez une date entre 30 minutes et 90 jours."})
    en_attente = (await db.execute(select(func.count()).select_from(RendezVous).where(
        RendezVous.logement_id == l.id, RendezVous.demandeur_id == qui.id,
        RendezVous.statut == "en_attente"))).scalar_one()
    if en_attente >= MAX_EN_ATTENTE_PAR_ANNONCE:
        raise HTTPException(429, {"code": "trop_de_demandes",
                                  "error": "Vous avez déjà des demandes en attente pour cette annonce."})
    nom, tel = str(data.get("nom") or "").strip(), str(data.get("telephone") or "").strip()
    if qui.user is not None and not qui.user.anonyme:
        nom = nom or f"{qui.user.prenom} {qui.user.nom}".strip()
        tel = tel or qui.user.telephone or ""
    r = RendezVous(id=nouvel_id(), logement_id=l.id, logement_titre=l.titre or l.type_bien or "",
                   prestataire_id=l.uid_prestataire, demandeur_id=qui.id,
                   demandeur_nom=(nom or "Visiteur")[:250], demandeur_telephone=tel[:40],
                   date_heure=quand, message=str(data.get("message") or "")[:1000],
                   statut="en_attente", reponse="")
    db.add(r)
    await db.flush()
    marquer(db, f"rdv:{r.prestataire_id}", f"rdv:{r.demandeur_id}")
    prest, titre, quand_txt, qui_nom = r.prestataire_id, r.logement_titre, _date_fr(quand), r.demandeur_nom
    apres_commit(db, lambda: push.notifier_utilisateur(
        prest, "📅 Demande de visite",
        f"{qui_nom} souhaite visiter « {titre} » le {quand_txt}.",
        {"type": "rendez_vous", "rendezVousId": r.id, "logementId": r.logement_id}), "push_rdv")
    return api(r)


@router.patch("/{rdv_id}")
async def repondre(rdv_id: str, data: dict, db: AsyncSession = Depends(get_db),
                   qui: Appelant = Depends(appelant)):
    """Prestataire : {statut: accepte|refuse, reponse?}. Demandeur : {statut: annule}."""
    r = await db.get(RendezVous, rdv_id, with_for_update=True)
    if r is None or qui.id not in (r.prestataire_id, r.demandeur_id):
        raise HTTPException(404, "Rendez-vous introuvable")
    statut = data.get("statut")
    if qui.id == r.prestataire_id and statut in ("accepte", "refuse"):
        if r.statut != "en_attente":
            raise HTTPException(409, "Ce rendez-vous a déjà reçu une réponse")
        dest = r.demandeur_id
    elif qui.id == r.demandeur_id and statut == "annule":
        if r.statut not in ("en_attente", "accepte"):
            raise HTTPException(409, "Ce rendez-vous ne peut plus être annulé")
        dest = r.prestataire_id
    else:
        raise HTTPException(400, "Action non autorisée")
    r.statut = statut
    r.reponse = str(data.get("reponse") or "")[:1000]
    await db.flush()
    marquer(db, f"rdv:{r.prestataire_id}", f"rdv:{r.demandeur_id}")
    titres = {"accepte": "✅ Visite confirmée", "refuse": "❌ Visite refusée", "annule": "Visite annulée"}
    corps = f"« {r.logement_titre} » — {_date_fr(r.date_heure)}"
    if r.reponse:
        corps += f" : {r.reponse}"
    apres_commit(db, lambda: push.notifier_utilisateur(
        dest, titres[statut], corps,
        {"type": "rendez_vous", "rendezVousId": r.id, "logementId": r.logement_id}), "push_rdv")
    return api(r)

