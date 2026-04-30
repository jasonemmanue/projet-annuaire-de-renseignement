// ============================================================
// FICHIER : lib/models/models.dart
// Modèle principal - Bien immobilier
// ============================================================

class Logement {
  final String id;
  final String titre;
  final String description;
  final double prix;         // en XAF
  final String typeLocation; // 'location' | 'vente'
  final String typeBien;    // 'studio' | 'F2' | 'F3' | 'villa' | 'terrain'
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
  final String? documentPdf; // URL PDF si présent

  const Logement({
    required this.id,
    required this.titre,
    required this.description,
    required this.prix,
    required this.typeLocation,
    required this.typeBien,
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
    this.documentPdf,
  });

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
      typeLocation == 'location' ? '${prixFormate}/mois' : prixFormate;

  factory Logement.fromJson(Map<String, dynamic> json) => Logement(
    id: json['id'],
    titre: json['titre'],
    description: json['description'],
    prix: (json['prix'] as num).toDouble(),
    typeLocation: json['typeLocation'],
    typeBien: json['typeBien'],
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titre': titre,
    'description': description,
    'prix': prix,
    'typeLocation': typeLocation,
    'typeBien': typeBien,
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

class Message {
  final String id;
  final String conversationId;
  final String expediteurId;
  final String? texte;
  final String? photoUrl;
  final String? fichierUrl;
  final DateTime dateEnvoi;
  final bool estLu;
  final String type; // 'texte' | 'photo' | 'fichier'

  const Message({
    required this.id,
    required this.conversationId,
    required this.expediteurId,
    this.texte,
    this.photoUrl,
    this.fichierUrl,
    required this.dateEnvoi,
    required this.estLu,
    required this.type,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    conversationId: json['conversationId'],
    expediteurId: json['expediteurId'],
    texte: json['texte'],
    photoUrl: json['photoUrl'],
    fichierUrl: json['fichierUrl'],
    dateEnvoi: DateTime.parse(json['dateEnvoi']),
    estLu: json['estLu'],
    type: json['type'],
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