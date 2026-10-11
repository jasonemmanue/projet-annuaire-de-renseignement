# app/services/tarifs.py
# ─────────────────────────────────────────────────────────────────────────────
# Grilles de prix (miroir de lib/services/tarification_service.dart).
# Les montants sont TOUJOURS calculés ici, côté serveur : un montant envoyé
# par l'app n'est jamais cru.
# ─────────────────────────────────────────────────────────────────────────────
MIN_PAIEMENT = 200
PREMIUM_MONTANT = 200
PREMIUM_DUREE_JOURS = 30
PUBLICATION_DUREE_JOURS = 30
COMMISSION_STANDARD = 0.03

SPONSOR_TARIFS = {"1s": 500, "2s": 1000, "1m": 2000}
SPONSOR_DUREES = {"1s": 7, "2s": 14, "1m": 30}
SPONSOR_LIBELLES = {"1s": "1 semaine", "2s": "2 semaines", "1m": "1 mois"}

URGENCE_MONTANT = 200
URGENCE_DUREE_HEURES = 48

PUBLICITE_MONTANT = 500
PUBLICITE_DUREE_JOURS = 4

VISIBILITE_DUREE_JOURS = 365
VISIBILITE_TARIFS = {"entreprise": 3000, "restaurant / snack": 2000, "école": 1000}
TYPES_VISIBILITE = {"Entreprise", "Restaurant / Snack", "École"}

HEBERGEMENT_TARIFS = {
    "Meublé / Motel": {"1m": 2000, "3m": 5000, "6m": 10000, "1a": 20000},
    "Auberge": {"1m": 1000, "3m": 3000, "6m": 5000, "1a": 10000},
    "Hôtel": {"1m": 3000, "3m": 8000, "6m": 15000, "1a": 25000},
}
HEBERGEMENT_JOURS = {"1m": 30, "3m": 90, "6m": 180, "1a": 365}

# Réactivation sans repaiement : visibilité annuelle et hébergement forfait.
TYPES_FORFAIT = TYPES_VISIBILITE | set(HEBERGEMENT_TARIFS)

PAIEMENT_WEB_TTL_H = 24
TYPES_ACTIVATION = {"premium", "publication", "sponsorisation", "publicite", "urgence", "visibilite"}


def plancher(m: float) -> int:
    m = round(m)
    return MIN_PAIEMENT if m < MIN_PAIEMENT else m


def montant_visibilite(type_bien: str) -> int:
    return VISIBILITE_TARIFS.get((type_bien or "").lower(), 2000)


def est_pharmacie(type_bien: str) -> bool:
    return type_bien == "Pharmacie"


def est_visibilite(type_bien: str) -> bool:
    return type_bien in TYPES_VISIBILITE


def code_hebergement(jours: int | None) -> str:
    j = int(jours or 30)
    for code, n in sorted(HEBERGEMENT_JOURS.items(), key=lambda x: x[1]):
        if j <= n:
            return code
    return "1a"


def montant_publication(type_bien: str, prix_bien: float, duree_jours: int | None) -> tuple[int, int]:
    """(montant, durée en jours) d'une publication d'annonce."""
    if type_bien in HEBERGEMENT_TARIFS:
        code = code_hebergement(duree_jours)
        return HEBERGEMENT_TARIFS[type_bien][code], HEBERGEMENT_JOURS[code]
    return plancher((prix_bien or 0) * COMMISSION_STANDARD), PUBLICATION_DUREE_JOURS


def service_activation(type_: str, params: dict | None) -> dict:
    """Montant + libellés d'un service (flow iOS : e-mail puis page web)."""
    p = params or {}
    if type_ == "premium":
        return {"montant": PREMIUM_MONTANT, "libelle": "Pack Premium (30 jours)",
                "description": "Accès aux avantages Premium pendant 30 jours"}
    if type_ == "sponsorisation":
        duree = p.get("duree") if p.get("duree") in SPONSOR_TARIFS else "1m"
        lib = SPONSOR_LIBELLES[duree]
        titre = p.get("titre")
        return {"montant": SPONSOR_TARIFS[duree], "libelle": f"Mise en avant ({lib})",
                "description": f"Mise en avant de « {titre} » pendant {lib}" if titre
                else f"Mise en avant pendant {lib}", "duree": duree}
    if type_ == "publication":
        jours = int(p.get("dureeJours") or PUBLICATION_DUREE_JOURS)
        titre = p.get("titre")
        return {"montant": plancher(float(p.get("montant") or 500)), "libelle": "Publication d'annonce",
                "description": f"Publication de « {titre} » pendant {jours} jours" if titre
                else f"Publication d'annonce pendant {jours} jours", "dureeJours": jours}
    if type_ == "publicite":
        titre = p.get("titre")
        return {"montant": PUBLICITE_MONTANT,
                "libelle": f"Diffusion publicitaire ({PUBLICITE_DUREE_JOURS} jours)",
                "description": f"Diffusion de « {titre} » pendant {PUBLICITE_DUREE_JOURS} jours" if titre
                else f"Diffusion publicitaire pendant {PUBLICITE_DUREE_JOURS} jours"}
    if type_ == "urgence":
        return {"montant": URGENCE_MONTANT, "libelle": f"Alerte prioritaire ({URGENCE_DUREE_HEURES}h)",
                "description": f"Alerte prioritaire pendant {URGENCE_DUREE_HEURES} heures"}
    if type_ == "visibilite":
        tb = p.get("typeBien") or "Entreprise"
        titre = p.get("titre")
        return {"montant": montant_visibilite(tb), "libelle": f"Visibilité annuelle ({tb})",
                "description": f"Visibilité annuelle pour « {titre} »" if titre else "Visibilité annuelle"}
    raise ValueError(f"Type d'activation inconnu : {type_}")
