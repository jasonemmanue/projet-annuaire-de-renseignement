# app/models/models.py
# ─────────────────────────────────────────────────────────────────────────────
# Tables PostgreSQL de Horem+ (remplacent les collections Firestore).
#
# Les identifiants restent des chaînes : ceux de Firestore sont repris tels
# quels à la migration, et l'id d'un utilisateur est son uid Firebase Auth.
# Chaque modèle déclare CHAMPS (voir app/core/serial.py) : la correspondance
# entre ses colonnes et les clés JSON historiques de l'app.
# ─────────────────────────────────────────────────────────────────────────────
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Date, DateTime, Float, ForeignKey, Index, Integer, String, Text, func,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


def _maintenant() -> datetime:
    return datetime.now(timezone.utc)


def _ts(**kw):
    return mapped_column(DateTime(timezone=True), **kw)


# ═════════════════════════════════════════════════════════════════════════════
# Utilisateurs (anciennement users/{uid})
# ═════════════════════════════════════════════════════════════════════════════
class Utilisateur(Base):
    __tablename__ = "utilisateurs"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)  # uid Firebase
    email: Mapped[str | None] = mapped_column(String(255), index=True)
    nom: Mapped[str] = mapped_column(String(120), default="")
    prenom: Mapped[str] = mapped_column(String(120), default="")
    telephone: Mapped[str] = mapped_column(String(40), default="")
    role: Mapped[str] = mapped_column(String(20), default="prestataire", index=True)
    is_premium: Mapped[bool] = mapped_column(Boolean, default=False)
    premium_expiry: Mapped[datetime | None] = _ts(nullable=True)
    photo_url: Mapped[str | None] = mapped_column(Text)
    fcm_token: Mapped[str | None] = mapped_column(Text)
    is_verifie: Mapped[bool] = mapped_column(Boolean, default=False)
    phone_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    phone_verified_at: Mapped[datetime | None] = _ts(nullable=True)
    compte_gratuit: Mapped[bool] = mapped_column(Boolean, default=False)
    notif_messages: Mapped[bool] = mapped_column(Boolean, default=True)
    # Préférences push prestataire : annonce validée/refusée, fin de sponsorisation.
    notif_moderation: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    notif_fin_sponsor: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    suspendu: Mapped[bool] = mapped_column(Boolean, default=False)
    # Carte nationale d'identité du prestataire (photos dans Firebase Storage).
    # Jamais exposée publiquement : profil personnel et admin seulement.
    cni_numero: Mapped[str | None] = mapped_column(String(40))
    cni_recto: Mapped[str | None] = mapped_column(Text)
    cni_verso: Mapped[str | None] = mapped_column(Text)
    cni_soumise_le: Mapped[datetime | None] = _ts(nullable=True)
    anonyme: Mapped[bool] = mapped_column(Boolean, default=False)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())
    updated_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), onupdate=_maintenant)

    CHAMPS = [
        ("uid", "id", "s"),
        ("email", "email", "s"),
        ("nom", "nom", "s"),
        ("prenom", "prenom", "s"),
        ("telephone", "telephone", "s"),
        ("role", "role", "s"),
        ("isPremium", "is_premium", "b"),
        ("premiumExpiry", "premium_expiry", "d"),
        ("photoUrl", "photo_url", "u"),
        ("fcmToken", "fcm_token", "s"),
        ("isVerifie", "is_verifie", "b"),
        ("estVerifie", "is_verifie", "b"),
        ("phoneVerified", "phone_verified", "b"),
        ("phoneVerifiedAt", "phone_verified_at", "d"),
        ("compteGratuit", "compte_gratuit", "b"),
        ("notifMessages", "notif_messages", "b"),
        ("notifModeration", "notif_moderation", "b"),
        ("notifFinSponsor", "notif_fin_sponsor", "b"),
        ("suspendu", "suspendu", "b"),
        ("cniNumero", "cni_numero", "s"),
        ("cniRecto", "cni_recto", "u"),
        ("cniVerso", "cni_verso", "u"),
        ("cniSoumiseLe", "cni_soumise_le", "d"),
        ("createdAt", "created_at", "d"),
        ("updatedAt", "updated_at", "d"),
    ]

    @property
    def cni_complete(self) -> bool:
        return bool(self.cni_numero and self.cni_recto and self.cni_verso)


# ═════════════════════════════════════════════════════════════════════════════
# Annonces (logements/{id}) : biens immobiliers ET fiches de services
# ═════════════════════════════════════════════════════════════════════════════
class Logement(Base):
    __tablename__ = "logements"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    uid_prestataire: Mapped[str] = mapped_column(String(128), index=True, default="")
    titre: Mapped[str] = mapped_column(String(300), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    prix: Mapped[float] = mapped_column(Float, default=0)
    # Détail du coût pour le chercheur (location) ; prix_total = ce qu'il paie
    # à l'entrée, calculé par le serveur (services/tarifs.prix_total).
    charges: Mapped[float] = mapped_column(Float, default=0)
    frais_agence: Mapped[float] = mapped_column(Float, default=0)
    caution: Mapped[float] = mapped_column(Float, default=0)
    mois_avance: Mapped[int] = mapped_column(Integer, default=1)
    prix_total: Mapped[float] = mapped_column(Float, default=0, index=True)
    type_location: Mapped[str] = mapped_column(String(40), default="location")
    type_bien: Mapped[str] = mapped_column(String(80), default="Studio", index=True)
    # « autre » quand typeBien est un texte libre saisi par le prestataire.
    type_bien_base: Mapped[str | None] = mapped_column(String(80))
    grade: Mapped[str] = mapped_column(String(40), default="standards")
    ville: Mapped[str] = mapped_column(String(120), default="", index=True)
    quartier: Mapped[str] = mapped_column(String(160), default="")
    latitude: Mapped[float] = mapped_column(Float, default=0)
    longitude: Mapped[float] = mapped_column(Float, default=0)
    photos: Mapped[list] = mapped_column(JSONB, default=list)
    surface: Mapped[int] = mapped_column(Integer, default=0)
    nb_pieces: Mapped[int] = mapped_column(Integer, default=1)
    equipements: Mapped[list] = mapped_column(JSONB, default=list)
    est_verifie: Mapped[bool] = mapped_column(Boolean, default=False)
    is_sponsored: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    sponsored_until: Mapped[datetime | None] = _ts(nullable=True)
    sponsored_at: Mapped[datetime | None] = _ts(nullable=True)
    prestataire_nom: Mapped[str] = mapped_column(String(250), default="")
    prestataire_phone: Mapped[str] = mapped_column(String(40), default="")
    prestataire_photo: Mapped[str | None] = mapped_column(Text)
    disponible: Mapped[bool] = mapped_column(Boolean, default=True)
    # NULL = règle historique : visible sauf pharmacie (approbation admin).
    visible_admin: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    payment_pending: Mapped[bool] = mapped_column(Boolean, default=False)
    document_pdf: Mapped[str | None] = mapped_column(Text)
    heure_ouverture: Mapped[str | None] = mapped_column(String(10))
    heure_fermeture: Mapped[str | None] = mapped_column(String(10))
    jours_garde: Mapped[list] = mapped_column(JSONB, default=list)
    visibilite_expiry: Mapped[datetime | None] = _ts(nullable=True)
    publication_expiry: Mapped[datetime | None] = _ts(nullable=True)
    vues: Mapped[int] = mapped_column(Integer, default=0)
    contacts: Mapped[int] = mapped_column(Integer, default=0)
    vues_milestones: Mapped[list] = mapped_column(JSONB, default=list)
    # Modération : en_attente | valide | rejete. NULL = annonce antérieure à la
    # modération, traitée comme validée.
    statut_moderation: Mapped[str | None] = mapped_column(String(20), index=True)
    motif_rejet: Mapped[str | None] = mapped_column(Text)
    # Une annonce non actualisée depuis 21 jours est masquée aux visiteurs.
    actualise_le: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), index=True)
    rappel_actualisation: Mapped[bool] = mapped_column(Boolean, default=False)
    # Vrai une fois la notification « nouvelle annonce » envoyée.
    annonce_diffusee: Mapped[bool] = mapped_column(Boolean, default=False)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), index=True)
    updated_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), onupdate=_maintenant)

    CHAMPS = [
        ("uid_prestataire", "uid_prestataire", "s"),
        ("prestatireId", "uid_prestataire", "s"),
        ("titre", "titre", "s"),
        ("description", "description", "s"),
        ("prix", "prix", "f"),
        ("charges", "charges", "f"),
        ("fraisAgence", "frais_agence", "f"),
        ("caution", "caution", "f"),
        ("moisAvance", "mois_avance", "i"),
        ("prixTotal", "prix_total", "f"),
        ("actualiseLe", "actualise_le", "d"),
        ("typeLocation", "type_location", "s"),
        ("typeBien", "type_bien", "s"),
        ("typeBienBase", "type_bien_base", "s"),
        ("grade", "grade", "s"),
        ("ville", "ville", "s"),
        ("quartier", "quartier", "s"),
        ("latitude", "latitude", "f"),
        ("longitude", "longitude", "f"),
        ("photos", "photos", "u"),
        ("surface", "surface", "i"),
        ("nbPieces", "nb_pieces", "i"),
        ("equipements", "equipements", "j"),
        ("estVerifie", "est_verifie", "b"),
        ("statutModeration", "statut_moderation", "s"),
        ("motifRejet", "motif_rejet", "s"),
        ("isSponsored", "is_sponsored", "b"),
        ("estSponsorie", "is_sponsored", "b"),
        ("sponsoredUntil", "sponsored_until", "d"),
        ("sponsoredAt", "sponsored_at", "d"),
        ("prestatireNom", "prestataire_nom", "s"),
        ("prestatirePhone", "prestataire_phone", "s"),
        ("prestatirePhoto", "prestataire_photo", "u"),
        ("disponible", "disponible", "b"),
        ("visibleAdmin", "visible_admin", "b"),
        ("paymentPending", "payment_pending", "b"),
        ("documentPdf", "document_pdf", "u"),
        ("heureOuverture", "heure_ouverture", "s"),
        ("heureFermeture", "heure_fermeture", "s"),
        ("joursGarde", "jours_garde", "j"),
        ("visibiliteExpiry", "visibilite_expiry", "d"),
        ("publicationExpiry", "publication_expiry", "d"),
        ("vues", "vues", "i"),
        ("nbVues", "vues", "i"),
        ("contacts", "contacts", "i"),
        ("vues_milestones_notified", "vues_milestones", "j"),
        ("createdAt", "created_at", "d"),
        ("updatedAt", "updated_at", "d"),
    ]

    @property
    def visible_admin_effectif(self) -> bool:
        if self.visible_admin is not None:
            return self.visible_admin
        return self.type_bien != "Pharmacie"

    @property
    def moderation_ok(self) -> bool:
        return self.statut_moderation in (None, "valide")


Index("ix_logements_visiteur", Logement.disponible, Logement.payment_pending)


# Vues par jour (graphique « Évolution des vues » du prestataire).
class VueJournaliere(Base):
    __tablename__ = "vues_journalieres"

    logement_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("logements.id", ondelete="CASCADE"), primary_key=True)
    jour: Mapped[datetime] = mapped_column(Date, primary_key=True)
    vues: Mapped[int] = mapped_column(Integer, default=0)


# ═════════════════════════════════════════════════════════════════════════════
# Messagerie (conversations/{id} + sous-collection messages)
# ═════════════════════════════════════════════════════════════════════════════
class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    participants: Mapped[list[str]] = mapped_column(ARRAY(String(160)), default=list)
    client_uid: Mapped[str] = mapped_column(String(160), default="")
    prestataire_uid: Mapped[str] = mapped_column(String(160), default="", index=True)
    logement_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    logement_titre: Mapped[str] = mapped_column(String(300), default="")
    logement_photo: Mapped[str | None] = mapped_column(Text)
    last_message: Mapped[str] = mapped_column(Text, default="")
    last_message_time: Mapped[datetime | None] = _ts(default=_maintenant, server_default=func.now())
    # Non-lus par participant : {"<uid>": 3}
    unread: Mapped[dict] = mapped_column(JSONB, default=dict)
    contact_label: Mapped[str | None] = mapped_column(String(60))
    contact_number: Mapped[int | None] = mapped_column(Integer)
    visitor_uid: Mapped[str | None] = mapped_column(String(160))
    urgence_until: Mapped[datetime | None] = _ts(nullable=True)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())

    CHAMPS = [
        ("participants", "participants", "j"),
        ("client_uid", "client_uid", "s"),
        ("prestataire_uid", "prestataire_uid", "s"),
        ("logement_id", "logement_id", "s"),
        ("logement_titre", "logement_titre", "s"),
        ("logement_photo", "logement_photo", "u"),
        ("lastMessage", "last_message", "s"),
        ("lastMessageTime", "last_message_time", "d"),
        ("lastMessageAt", "last_message_time", "d"),
        ("contact_label", "contact_label", "s"),
        ("contact_number", "contact_number", "i"),
        ("visitor_uid", "visitor_uid", "s"),
        ("urgenceUntil", "urgence_until", "d"),
        ("createdAt", "created_at", "d"),
    ]


Index("ix_conversations_participants", Conversation.participants, postgresql_using="gin")


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("conversations.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[str] = mapped_column(String(160), default="")
    type: Mapped[str] = mapped_column(String(20), default="text")
    text: Mapped[str] = mapped_column(Text, default="")
    image_url: Mapped[str | None] = mapped_column(Text)
    video_url: Mapped[str | None] = mapped_column(Text)
    file_url: Mapped[str | None] = mapped_column(Text)
    file_name: Mapped[str | None] = mapped_column(String(300))
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    edited: Mapped[bool] = mapped_column(Boolean, default=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    reply_to: Mapped[dict | None] = mapped_column(JSONB)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    timestamp: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), index=True)

    CHAMPS = [
        ("senderId", "sender_id", "s"),
        ("type", "type", "s"),
        ("text", "text", "s"),
        ("imageUrl", "image_url", "u"),
        ("videoUrl", "video_url", "u"),
        ("fileUrl", "file_url", "u"),
        ("fileName", "file_name", "s"),
        ("isRead", "is_read", "b"),
        ("edited", "edited", "b"),
        ("deleted", "deleted", "b"),
        ("replyTo", "reply_to", "j"),
        ("timestamp", "timestamp", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Favoris (users/{uid}/favoris/{logementId})
# ═════════════════════════════════════════════════════════════════════════════
class Favori(Base):
    __tablename__ = "favoris"

    utilisateur_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    logement_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    donnees: Mapped[dict] = mapped_column(JSONB, default=dict)
    added_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())


# ═════════════════════════════════════════════════════════════════════════════
# Signalements
# ═════════════════════════════════════════════════════════════════════════════
class Signalement(Base):
    __tablename__ = "signalements"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    logement_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    logement_titre: Mapped[str] = mapped_column(String(300), default="")
    motif: Mapped[str] = mapped_column(String(200), default="")
    motif_libre: Mapped[str | None] = mapped_column(Text)
    signale_par: Mapped[str] = mapped_column(String(160), default="")
    signale_par_type: Mapped[str] = mapped_column(String(20), default="visiteur")
    statut: Mapped[str] = mapped_column(String(20), default="en_attente", index=True)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    date_signalement: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())

    CHAMPS = [
        ("logementId", "logement_id", "s"),
        ("logementTitre", "logement_titre", "s"),
        ("motif", "motif", "s"),
        ("motifLibre", "motif_libre", "s"),
        ("signalePar", "signale_par", "s"),
        ("signaleurId", "signale_par", "s"),
        ("signaleParType", "signale_par_type", "s"),
        ("statut", "statut", "s"),
        ("dateSignalement", "date_signalement", "d"),
        ("createdAt", "date_signalement", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Transactions GeniusPay (id = référence GeniusPay MTX-…)
# ═════════════════════════════════════════════════════════════════════════════
class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[str] = mapped_column(String(120), primary_key=True)  # référence
    uid: Mapped[str] = mapped_column(String(128), default="", index=True)
    type: Mapped[str] = mapped_column(String(30), default="", index=True)
    logement_id: Mapped[str | None] = mapped_column(String(64))
    publicite_id: Mapped[str | None] = mapped_column(String(64))
    duree: Mapped[str | None] = mapped_column(String(10))
    duree_jours: Mapped[int | None] = mapped_column(Integer)
    montant: Mapped[int] = mapped_column(Integer, default=0)
    devise: Mapped[str] = mapped_column(String(6), default="XOF")
    statut: Mapped[str] = mapped_column(String(20), default="en_attente", index=True)
    internal_ref: Mapped[str | None] = mapped_column(String(200))
    telephone: Mapped[str | None] = mapped_column(String(40))
    channel: Mapped[str | None] = mapped_column(String(40))
    pays: Mapped[str | None] = mapped_column(String(4))
    checkout_url: Mapped[str | None] = mapped_column(Text)
    geniuspay_transaction_id: Mapped[str | None] = mapped_column(String(200))
    source: Mapped[str | None] = mapped_column(String(30))
    payment_token: Mapped[str | None] = mapped_column(String(64), index=True)
    dernier_statut_brut: Mapped[str | None] = mapped_column(String(40))
    simulation: Mapped[bool] = mapped_column(Boolean, default=False)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), index=True)
    confirmed_at: Mapped[datetime | None] = _ts(nullable=True)

    CHAMPS = [
        ("reference", "id", "s"),
        ("uid", "uid", "s"),
        ("type", "type", "s"),
        ("logementId", "logement_id", "s"),
        ("publiciteId", "publicite_id", "s"),
        ("duree", "duree", "s"),
        ("dureeJours", "duree_jours", "i"),
        ("montant", "montant", "i"),
        ("devise", "devise", "s"),
        ("statut", "statut", "s"),
        ("internalRef", "internal_ref", "s"),
        ("telephone", "telephone", "s"),
        ("channel", "channel", "s"),
        ("pays", "pays", "s"),
        ("checkoutUrl", "checkout_url", "s"),
        ("geniuspayTransactionId", "geniuspay_transaction_id", "s"),
        ("source", "source", "s"),
        ("paymentToken", "payment_token", "s"),
        ("dernierStatutBrut", "dernier_statut_brut", "s"),
        ("createdAt", "created_at", "d"),
        ("confirmedAt", "confirmed_at", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Alertes prioritaires visiteurs (urgences)
# ═════════════════════════════════════════════════════════════════════════════
class RendezVous(Base):
    """Demande de visite d'un bien : le chercheur propose une date et une
    heure, le prestataire accepte ou refuse."""
    __tablename__ = "rendez_vous"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    logement_id: Mapped[str] = mapped_column(String(64), index=True)
    logement_titre: Mapped[str] = mapped_column(String(300), default="")
    prestataire_id: Mapped[str] = mapped_column(String(128), index=True)
    demandeur_id: Mapped[str] = mapped_column(String(128), index=True)  # compte ou visiteur_…
    demandeur_nom: Mapped[str] = mapped_column(String(250), default="")
    demandeur_telephone: Mapped[str] = mapped_column(String(40), default="")
    date_heure: Mapped[datetime] = _ts()
    message: Mapped[str] = mapped_column(Text, default="")
    # en_attente | accepte | refuse | annule
    statut: Mapped[str] = mapped_column(String(20), default="en_attente", index=True)
    reponse: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())
    updated_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), onupdate=_maintenant)

    CHAMPS = [
        ("logementId", "logement_id", "s"),
        ("logementTitre", "logement_titre", "s"),
        ("prestataireId", "prestataire_id", "s"),
        ("demandeurId", "demandeur_id", "s"),
        ("demandeurNom", "demandeur_nom", "s"),
        ("demandeurTelephone", "demandeur_telephone", "s"),
        ("dateHeure", "date_heure", "d"),
        ("message", "message", "s"),
        ("statut", "statut", "s"),
        ("reponse", "reponse", "s"),
        ("createdAt", "created_at", "d"),
        ("updatedAt", "updated_at", "d"),
    ]


class Urgence(Base):
    __tablename__ = "urgences"

    id: Mapped[str] = mapped_column(String(200), primary_key=True)
    uid: Mapped[str] = mapped_column(String(128), default="", index=True)
    type_bien: Mapped[str] = mapped_column(String(80), default="", index=True)
    description: Mapped[str] = mapped_column(Text, default="")
    prix_min: Mapped[float] = mapped_column(Float, default=0)
    prix_max: Mapped[float] = mapped_column(Float, default=0)
    actif: Mapped[bool] = mapped_column(Boolean, default=False)
    payment_pending: Mapped[bool] = mapped_column(Boolean, default=True)
    expires_at: Mapped[datetime | None] = _ts(nullable=True)
    reference: Mapped[str | None] = mapped_column(String(120))
    logement_id: Mapped[str | None] = mapped_column(String(64))
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())

    CHAMPS = [
        ("uid", "uid", "s"),
        ("typeBien", "type_bien", "s"),
        ("description", "description", "s"),
        ("prixMin", "prix_min", "f"),
        ("prixMax", "prix_max", "f"),
        ("actif", "actif", "b"),
        ("paymentPending", "payment_pending", "b"),
        ("expiresAt", "expires_at", "d"),
        ("reference", "reference", "s"),
        ("logementId", "logement_id", "s"),
        ("createdAt", "created_at", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Publicités prestataires (stories)
# ═════════════════════════════════════════════════════════════════════════════
class Publicite(Base):
    __tablename__ = "publicites"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    prestataire_id: Mapped[str] = mapped_column(String(128), default="", index=True)
    prestataire_nom: Mapped[str] = mapped_column(String(250), default="")
    prestataire_phone: Mapped[str] = mapped_column(String(40), default="")
    prestataire_photo: Mapped[str | None] = mapped_column(Text)
    titre: Mapped[str] = mapped_column(String(300), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    photos: Mapped[list] = mapped_column(JSONB, default=list)
    video_url: Mapped[str | None] = mapped_column(Text)
    actif: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    expires_at: Mapped[datetime | None] = _ts(nullable=True)
    transaction_ref: Mapped[str | None] = mapped_column(String(120))
    payment_pending: Mapped[bool] = mapped_column(Boolean, default=True)
    logement_id: Mapped[str | None] = mapped_column(String(64))
    logement_titre: Mapped[str | None] = mapped_column(String(300))
    logement_photo: Mapped[str | None] = mapped_column(Text)
    dernier_paiement_at: Mapped[datetime | None] = _ts(nullable=True)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    date_creation: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())

    CHAMPS = [
        ("prestataireId", "prestataire_id", "s"),
        ("prestataireNom", "prestataire_nom", "s"),
        ("prestatairePhone", "prestataire_phone", "s"),
        ("prestatairePhoto", "prestataire_photo", "u"),
        ("titre", "titre", "s"),
        ("description", "description", "s"),
        ("photos", "photos", "u"),
        ("videoUrl", "video_url", "u"),
        ("actif", "actif", "b"),
        ("expiresAt", "expires_at", "d"),
        ("transactionRef", "transaction_ref", "s"),
        ("paymentPending", "payment_pending", "b"),
        ("logementId", "logement_id", "s"),
        ("logementTitre", "logement_titre", "s"),
        ("logementPhoto", "logement_photo", "u"),
        ("dernierPaiementAt", "dernier_paiement_at", "d"),
        ("dateCreation", "date_creation", "d"),
        ("createdAt", "date_creation", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Notifications admin (nouvelles publications payées)
# ═════════════════════════════════════════════════════════════════════════════
class NotificationAdmin(Base):
    __tablename__ = "admin_notifications"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    type: Mapped[str] = mapped_column(String(40), default="nouvelle_publication")
    logement_id: Mapped[str] = mapped_column(String(64), default="")
    titre: Mapped[str] = mapped_column(String(300), default="")
    type_bien: Mapped[str] = mapped_column(String(80), default="")
    ville: Mapped[str] = mapped_column(String(120), default="")
    quartier: Mapped[str] = mapped_column(String(160), default="")
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    prestataire_nom: Mapped[str] = mapped_column(String(250), default="")
    prestataire_phone: Mapped[str] = mapped_column(String(40), default="")
    uid_prestataire: Mapped[str] = mapped_column(String(128), default="", index=True)
    lu: Mapped[bool] = mapped_column(Boolean, default=False)
    extra: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now(), index=True)

    CHAMPS = [
        ("type", "type", "s"),
        ("logementId", "logement_id", "s"),
        ("titre", "titre", "s"),
        ("typeBien", "type_bien", "s"),
        ("ville", "ville", "s"),
        ("quartier", "quartier", "s"),
        ("latitude", "latitude", "f"),
        ("longitude", "longitude", "f"),
        ("prestatireNom", "prestataire_nom", "s"),
        ("prestatirePhone", "prestataire_phone", "s"),
        ("uid_prestataire", "uid_prestataire", "s"),
        ("lu", "lu", "b"),
        ("createdAt", "created_at", "d"),
    ]


# ═════════════════════════════════════════════════════════════════════════════
# Liens de paiement web (flow iOS : e-mail → page /pay/[token])
# ═════════════════════════════════════════════════════════════════════════════
class PaiementWeb(Base):
    __tablename__ = "paiements_web"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # token
    uid: Mapped[str] = mapped_column(String(128), default="")
    type: Mapped[str] = mapped_column(String(30), default="")
    target_id: Mapped[str | None] = mapped_column(String(200))
    params: Mapped[dict] = mapped_column(JSONB, default=dict)
    montant: Mapped[int] = mapped_column(Integer, default=0)
    libelle: Mapped[str] = mapped_column(String(300), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    email: Mapped[str] = mapped_column(String(255), default="")
    statut: Mapped[str] = mapped_column(String(20), default="en_attente")
    reference: Mapped[str | None] = mapped_column(String(120))
    checkout_url: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _ts(default=_maintenant, server_default=func.now())
    expires_at: Mapped[datetime | None] = _ts(nullable=True)
    initie_at: Mapped[datetime | None] = _ts(nullable=True)
    confirmed_at: Mapped[datetime | None] = _ts(nullable=True)

    CHAMPS = [
        ("token", "id", "s"),
        ("uid", "uid", "s"),
        ("type", "type", "s"),
        ("targetId", "target_id", "s"),
        ("params", "params", "j"),
        ("montant", "montant", "i"),
        ("libelle", "libelle", "s"),
        ("description", "description", "s"),
        ("email", "email", "s"),
        ("statut", "statut", "s"),
        ("reference", "reference", "s"),
        ("checkoutUrl", "checkout_url", "s"),
        ("createdAt", "created_at", "d"),
        ("expiresAt", "expires_at", "d"),
        ("initieAt", "initie_at", "d"),
        ("confirmedAt", "confirmed_at", "d"),
    ]
