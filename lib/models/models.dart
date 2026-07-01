// ============================================================
// FICHIER : lib/models/models.dart
// Modèle principal - Bien immobilier
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';

class Logement {
  final String id;
  final String titre;
  final String description;
  final double prix;         // en XAF
  final String typeLocation; // 'location' | 'vente'
  final String typeBien;    // 'studio' | 'F2' | 'F3' | 'villa' | 'terrain'
  final String grade;       // 'standards' | 'haut_standing' | 'meubles' | 'a_louer'
  final String ville;
  final String quartier;
  final double latitude;
  final double longitude;
  final List<String> photos; // URLs images
  final int surface;         // en m²
  final int nbPieces;
  final List<String> equipements;
  final bool estVerifie;
  final bool estSponsorie;
  final String prestatireId;
  final String prestatireNom;
  final String prestatirePhone;
  final String? prestatirePhoto;
  final DateTime datePublication;
  final int nbVues;
  final bool disponible;
  /// True tant que les frais de publication ne sont pas confirmés.
  final bool paymentPending;
  final String? documentPdf; // URL PDF si présent
  final DateTime? sponsoredUntil; // fin de la sponsorisation (null si non sponsorisé)
  final String? heureOuverture;   // Format 'HH:MM' — pharmacies/restaurants/entreprises
  final String? heureFermeture;   // Format 'HH:MM'
  final List<String> joursGarde;  // Jours de garde/ouverture ex: ['Lun','Mer','Ven']
  final DateTime? visibiliteExpiry; // Fin de la visibilité annuelle (entreprise/restaurant/école)
  final DateTime? publicationExpiry; // Fin de la visibilité 1 mois après publication (immobilier)

  /// Annonce visible côté visiteur : disponible, paiement validé, et non expirée.
  bool get estVisiblePourVisiteur {
    if (!disponible || paymentPending) return false;
    if (typeBien == 'Pharmacie') return true;
    if (publicationExpiry != null && publicationExpiry!.isBefore(DateTime.now())) return false;
    return true;
  }

  const Logement({
    required this.id,
    required this.titre,
    required this.description,
    required this.prix,
    required this.typeLocation,
    required this.typeBien,
    this.grade = 'standards',
    required this.ville,
    required this.quartier,
    required this.latitude,
    required this.longitude,
    required this.photos,
    required this.surface,
    required this.nbPieces,
    required this.equipements,
    required this.estVerifie,
    required this.estSponsorie,
    required this.prestatireId,
    required this.prestatireNom,
    required this.prestatirePhone,
    this.prestatirePhoto,
    required this.datePublication,
    required this.nbVues,
    required this.disponible,
    this.paymentPending = false,
    this.documentPdf,
    this.sponsoredUntil,
    this.heureOuverture,
    this.heureFermeture,
    this.joursGarde = const [],
    this.visibiliteExpiry,
    this.publicationExpiry,
  });

  bool get estOuvertMaintenant {
    if (heureOuverture == null || heureFermeture == null) return true;
    final now = DateTime.now();
    final nowM = now.hour * 60 + now.minute;
    final ouv = _parseHeure(heureOuverture!);
    final ferm = _parseHeure(heureFermeture!);
    if (ouv == null || ferm == null) return true;
    return nowM >= ouv && nowM <= ferm;
  }

  static int? _parseHeure(String h) {
    final parts = h.split(':');
    if (parts.length != 2) return null;
    final hr = int.tryParse(parts[0]);
    final min = int.tryParse(parts[1]);
    if (hr == null || min == null) return null;
    return hr * 60 + min;
  }

  // Formatage prix en XAF avec séparateur
  String get prixFormate {
    final formatted = prix.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]} ',
    );
    return '$formatted XAF';
  }

  // Sous-titre prix pour location
  String get prixLabel =>
      typeLocation == 'location' ? '$prixFormate/mois' : prixFormate;


  // ── Firestore ────────────────────────────────────────────
  factory Logement.fromMap(String docId, Map<String, dynamic> map) => Logement(
    id: docId,
    titre: map['titre'] ?? '',
    description: map['description'] ?? '',
    prix: (map['prix'] as num?)?.toDouble() ?? 0,
    typeLocation: map['typeLocation'] ?? 'location',
    typeBien: map['typeBien'] ?? 'Studio',
    grade: map['grade'] ?? 'standards',
    ville: map['ville'] ?? '',
    quartier: map['quartier'] ?? '',
    latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
    photos: List<String>.from(map['photos'] ?? []),
    surface: (map['surface'] as num?)?.toInt() ?? 0,
    nbPieces: (map['nbPieces'] as num?)?.toInt() ?? 1,
    equipements: List<String>.from(map['equipements'] ?? []),
    estVerifie: map['estVerifie'] ?? false,
    estSponsorie: map['isSponsored'] ?? map['estSponsorie'] ?? false,
    prestatireId: map['uid_prestataire'] ?? map['prestatireId'] ?? '',
    prestatireNom: map['prestatireNom'] ?? '',
    prestatirePhone: map['prestatirePhone'] ?? '',
    prestatirePhoto: map['prestatirePhoto'],
    datePublication: map['createdAt'] != null
        ? (map['createdAt'] as dynamic).toDate()
        : DateTime.now(),
    nbVues: (map['vues'] as num?)?.toInt() ?? 0,
    disponible: map['disponible'] ?? true,
    paymentPending: map['paymentPending'] ?? false,
    documentPdf: map['documentPdf'],
    sponsoredUntil: map['sponsoredUntil'] is Timestamp
        ? (map['sponsoredUntil'] as Timestamp).toDate()
        : null,
    heureOuverture: map['heureOuverture'],
    heureFermeture: map['heureFermeture'],
    joursGarde: List<String>.from(map['joursGarde'] ?? []),
    visibiliteExpiry: map['visibiliteExpiry'] is Timestamp
        ? (map['visibiliteExpiry'] as Timestamp).toDate()
        : null,
    publicationExpiry: map['publicationExpiry'] is Timestamp
        ? (map['publicationExpiry'] as Timestamp).toDate()
        : null,
  );

  factory Logement.fromJson(Map<String, dynamic> json) => Logement(
    id: json['id'],
    titre: json['titre'],
    description: json['description'],
    prix: (json['prix'] as num).toDouble(),
    typeLocation: json['typeLocation'],
    typeBien: json['typeBien'],
    grade: json['grade'] ?? 'standards',
    ville: json['ville'],
    quartier: json['quartier'],
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    photos: List<String>.from(json['photos']),
    surface: json['surface'],
    nbPieces: json['nbPieces'],
    equipements: List<String>.from(json['equipements']),
    estVerifie: json['estVerifie'],
    estSponsorie: json['estSponsorie'],
    prestatireId: json['prestatireId'],
    prestatireNom: json['prestatireNom'],
    prestatirePhone: json['prestatirePhone'],
    prestatirePhoto: json['prestatirePhoto'],
    datePublication: DateTime.parse(json['datePublication']),
    nbVues: json['nbVues'],
    disponible: json['disponible'],
    documentPdf: json['documentPdf'],
    sponsoredUntil: json['sponsoredUntil'] != null
        ? DateTime.tryParse(json['sponsoredUntil'])
        : null,
    heureOuverture: json['heureOuverture'],
    heureFermeture: json['heureFermeture'],
    joursGarde: List<String>.from(json['joursGarde'] ?? []),
    visibiliteExpiry: json['visibiliteExpiry'] != null
        ? DateTime.tryParse(json['visibiliteExpiry'])
        : null,
    publicationExpiry: json['publicationExpiry'] != null
        ? DateTime.tryParse(json['publicationExpiry'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titre': titre,
    'description': description,
    'prix': prix,
    'typeLocation': typeLocation,
    'typeBien': typeBien,
    'grade': grade,
    'ville': ville,
    'quartier': quartier,
    'latitude': latitude,
    'longitude': longitude,
    'photos': photos,
    'surface': surface,
    'nbPieces': nbPieces,
    'equipements': equipements,
    'estVerifie': estVerifie,
    'estSponsorie': estSponsorie,
    'prestatireId': prestatireId,
    'prestatireNom': prestatireNom,
    'prestatirePhone': prestatirePhone,
    'prestatirePhoto': prestatirePhoto,
    'datePublication': datePublication.toIso8601String(),
    'nbVues': nbVues,
    'disponible': disponible,
    'documentPdf': documentPdf,
    'sponsoredUntil': sponsoredUntil?.toIso8601String(),
    'heureOuverture': heureOuverture,
    'heureFermeture': heureFermeture,
    'joursGarde': joursGarde,
    'visibiliteExpiry': visibiliteExpiry?.toIso8601String(),
    'publicationExpiry': publicationExpiry?.toIso8601String(),
  };
}

// ============================================================
// FICHIER : lib/models/utilisateur.dart
// Modèle Prestataire (seul type avec compte)
// ============================================================

class Utilisateur {
  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String? photoUrl;
  final bool estVerifie;
  final bool estPremium;
  final DateTime dateInscription;
  final int nbAnnonces;
  final double noteGlobale; // 0 à 5

  const Utilisateur({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    this.photoUrl,
    required this.estVerifie,
    required this.estPremium,
    required this.dateInscription,
    required this.nbAnnonces,
    required this.noteGlobale,
  });

  String get nomComplet => '$prenom $nom';

  factory Utilisateur.fromJson(Map<String, dynamic> json) => Utilisateur(
    id: json['id'],
    nom: json['nom'],
    prenom: json['prenom'],
    email: json['email'],
    telephone: json['telephone'],
    photoUrl: json['photoUrl'],
    estVerifie: json['estVerifie'],
    estPremium: json['estPremium'],
    dateInscription: DateTime.parse(json['dateInscription']),
    nbAnnonces: json['nbAnnonces'],
    noteGlobale: (json['noteGlobale'] as num).toDouble(),
  );
}

// ============================================================
// FICHIER : lib/models/message.dart
// Modèle Message pour le chat (§4.1.5)
// ============================================================

// Citation d'un message parent (réponse)
class ReplyTo {
  final String messageId;
  final String extrait;
  final String senderId;

  const ReplyTo({
    required this.messageId,
    required this.extrait,
    required this.senderId,
  });

  factory ReplyTo.fromMap(Map<String, dynamic> map) => ReplyTo(
    messageId: map['messageId'] as String? ?? '',
    extrait: map['extrait'] as String? ?? '',
    senderId: map['senderId'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'extrait': extrait,
    'senderId': senderId,
  };
}

class Message {
  final String id;
  final String conversationId;
  final String expediteurId;
  final String? texte;
  final String? photoUrl;
  final String? videoUrl;
  final String? fichierUrl;
  final DateTime dateEnvoi;
  final bool estLu;
  final String type; // 'texte' | 'photo' | 'video' | 'fichier'
  final ReplyTo? replyTo;

  const Message({
    required this.id,
    required this.conversationId,
    required this.expediteurId,
    this.texte,
    this.photoUrl,
    this.videoUrl,
    this.fichierUrl,
    required this.dateEnvoi,
    required this.estLu,
    required this.type,
    this.replyTo,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    conversationId: json['conversationId'],
    expediteurId: json['expediteurId'],
    texte: json['texte'],
    photoUrl: json['photoUrl'],
    videoUrl: json['videoUrl'],
    fichierUrl: json['fichierUrl'],
    dateEnvoi: DateTime.parse(json['dateEnvoi']),
    estLu: json['estLu'],
    type: json['type'],
    replyTo: json['replyTo'] != null
        ? ReplyTo.fromMap(json['replyTo'] as Map<String, dynamic>)
        : null,
  );
}

class Conversation {
  final String id;
  final String logementId;
  final String logementTitre;
  final String? logementPhoto;
  final String prestatireId;
  final String prestatireNom;
  final String? prestatirePhoto;
  final Message? dernierMessage;
  final int nbNonLus;
  final DateTime dateDernierMessage;

  const Conversation({
    required this.id,
    required this.logementId,
    required this.logementTitre,
    this.logementPhoto,
    required this.prestatireId,
    required this.prestatireNom,
    this.prestatirePhoto,
    this.dernierMessage,
    required this.nbNonLus,
    required this.dateDernierMessage,
  });
}

// ============================================================
// FICHIER : lib/models/filtre_recherche.dart
// Filtres de recherche (§4.1.1, §3.1 UC-C02)
// ============================================================

class FiltreRecherche {
  final String? ville;
  final String? quartier;
  final String? typeBien;      // studio, F2, F3, villa, terrain
  final String? typeLocation;  // location, vente
  final double? prixMin;
  final double? prixMax;
  final int? surfaceMin;
  final int? nbPiecesMin;
  final double? distanceKm;   // pour le filtre carte
  final bool seulementVerifies;
  final bool seulementDisponibles;
  final String tri;            // 'recents' | 'prix_asc' | 'prix_desc' | 'populaires'

  const FiltreRecherche({
    this.ville,
    this.quartier,
    this.typeBien,
    this.typeLocation,
    this.prixMin,
    this.prixMax,
    this.surfaceMin,
    this.nbPiecesMin,
    this.distanceKm,
    this.seulementVerifies = false,
    this.seulementDisponibles = true,
    this.tri = 'recents',
  });

  FiltreRecherche copyWith({
    String? ville,
    String? quartier,
    String? typeBien,
    String? typeLocation,
    double? prixMin,
    double? prixMax,
    int? surfaceMin,
    int? nbPiecesMin,
    double? distanceKm,
    bool? seulementVerifies,
    bool? seulementDisponibles,
    String? tri,
  }) =>
      FiltreRecherche(
        ville: ville ?? this.ville,
        quartier: quartier ?? this.quartier,
        typeBien: typeBien ?? this.typeBien,
        typeLocation: typeLocation ?? this.typeLocation,
        prixMin: prixMin ?? this.prixMin,
        prixMax: prixMax ?? this.prixMax,
        surfaceMin: surfaceMin ?? this.surfaceMin,
        nbPiecesMin: nbPiecesMin ?? this.nbPiecesMin,
        distanceKm: distanceKm ?? this.distanceKm,
        seulementVerifies: seulementVerifies ?? this.seulementVerifies,
        seulementDisponibles: seulementDisponibles ?? this.seulementDisponibles,
        tri: tri ?? this.tri,
      );

  bool get aDesFiltres =>
      ville != null || quartier != null || typeBien != null ||
          typeLocation != null || prixMin != null || prixMax != null ||
          surfaceMin != null || nbPiecesMin != null || seulementVerifies;
}
// ============================================================
// MODÈLE : Publicite — Publicités des prestataires
// Collection Firestore : "publicites"
// ============================================================

class Publicite {
  final String id;
  final String prestataireId;
  final String prestataireNom;
  final String prestatairePhone;
  final String? prestatairePhoto;
  final String titre;
  final String description;
  final List<String> photos;
  final String? videoUrl;
  final DateTime dateCreation;
  final bool actif;
  /// Date d'expiration : la pub se désactive automatiquement après.
  final DateTime? expiresAt;
  /// Référence de la transaction GeniusPay qui a financé la diffusion.
  final String? transactionRef;
  /// Brouillon en attente du paiement initial (true) ou diffusable (false).
  final bool paymentPending;

  const Publicite({
    required this.id,
    required this.prestataireId,
    required this.prestataireNom,
    required this.prestatairePhone,
    this.prestatairePhoto,
    required this.titre,
    required this.description,
    required this.photos,
    this.videoUrl,
    required this.dateCreation,
    this.actif = true,
    this.expiresAt,
    this.transactionRef,
    this.paymentPending = false,
  });

  /// Indique si la pub est dans sa période de diffusion (actif + non expirée).
  bool get estDiffusable {
    if (!actif || paymentPending) return false;
    if (expiresAt == null) return false;
    return expiresAt!.isAfter(DateTime.now());
  }

  /// Indique si la pub est expirée (et donc nécessite un repaiement).
  bool get estExpiree {
    if (expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  factory Publicite.fromMap(String docId, Map<String, dynamic> map) => Publicite(
        id: docId,
        prestataireId: map['prestataireId'] ?? '',
        prestataireNom: map['prestataireNom'] ?? '',
        prestatairePhone: map['prestatairePhone'] ?? '',
        prestatairePhoto: map['prestatairePhoto'],
        titre: map['titre'] ?? '',
        description: map['description'] ?? '',
        photos: List<String>.from(map['photos'] ?? []),
        videoUrl: map['videoUrl'],
        dateCreation: map['dateCreation'] is Timestamp
            ? (map['dateCreation'] as Timestamp).toDate()
            : DateTime.now(),
        actif: map['actif'] ?? true,
        expiresAt: map['expiresAt'] is Timestamp
            ? (map['expiresAt'] as Timestamp).toDate()
            : null,
        transactionRef: map['transactionRef'] as String?,
        paymentPending: map['paymentPending'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'prestataireId': prestataireId,
        'prestataireNom': prestataireNom,
        'prestatairePhone': prestatairePhone,
        if (prestatairePhoto != null) 'prestatairePhoto': prestatairePhoto,
        'titre': titre,
        'description': description,
        'photos': photos,
        if (videoUrl != null) 'videoUrl': videoUrl,
        'dateCreation': Timestamp.fromDate(dateCreation),
        'actif': actif,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
        if (transactionRef != null) 'transactionRef': transactionRef,
        'paymentPending': paymentPending,
      };
}

// ============================================================
// MODÈLE : SignalementModel (§ bouton Signaler)
// ============================================================

class SignalementModel {
  final String? id;              // null avant écriture Firestore
  final String logementId;
  final String logementTitre;
  final String motif;            // motif sélectionné parmi les 6 options
  final String? motifLibre;      // rempli seulement si motif == "Autre (préciser)"
  final String signalePar;       // uid Firebase OU identifiant visiteur local
  final String signaleParType;   // 'visiteur' | 'prestataire'
  final DateTime dateSignalement;
  final String statut;           // 'en_attente' | 'traite' | 'rejete'

  const SignalementModel({
    this.id,
    required this.logementId,
    required this.logementTitre,
    required this.motif,
    this.motifLibre,
    required this.signalePar,
    required this.signaleParType,
    required this.dateSignalement,
    this.statut = 'en_attente',
  });

  // ── Sérialisation vers Firestore ─────────────────────────────
  Map<String, dynamic> toMap() => {
        'logementId': logementId,
        'logementTitre': logementTitre,
        'motif': motif,
        if (motifLibre != null && motifLibre!.isNotEmpty)
          'motifLibre': motifLibre,
        'signalePar': signalePar,
        'signaleParType': signaleParType,
        'dateSignalement': Timestamp.fromDate(dateSignalement),
        'statut': statut,
      };

  // ── Désérialisation depuis Firestore ─────────────────────────
  factory SignalementModel.fromMap(String docId, Map<String, dynamic> map) =>
      SignalementModel(
        id: docId,
        logementId: map['logementId'] ?? '',
        logementTitre: map['logementTitre'] ?? '',
        motif: map['motif'] ?? '',
        motifLibre: map['motifLibre'],
        signalePar: map['signalePar'] ?? '',
        signaleParType: map['signaleParType'] ?? 'visiteur',
        dateSignalement: map['dateSignalement'] != null
            ? (map['dateSignalement'] as Timestamp).toDate()
            : DateTime.now(),
        statut: map['statut'] ?? 'en_attente',
      );

  // ── Copie avec modification ───────────────────────────────────
  SignalementModel copyWith({
    String? id,
    String? logementId,
    String? logementTitre,
    String? motif,
    String? motifLibre,
    String? signalePar,
    String? signaleParType,
    DateTime? dateSignalement,
    String? statut,
  }) =>
      SignalementModel(
        id: id ?? this.id,
        logementId: logementId ?? this.logementId,
        logementTitre: logementTitre ?? this.logementTitre,
        motif: motif ?? this.motif,
        motifLibre: motifLibre ?? this.motifLibre,
        signalePar: signalePar ?? this.signalePar,
        signaleParType: signaleParType ?? this.signaleParType,
        dateSignalement: dateSignalement ?? this.dateSignalement,
        statut: statut ?? this.statut,
      );
}
