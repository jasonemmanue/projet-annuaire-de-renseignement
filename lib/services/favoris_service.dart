import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'auth_service.dart';

// ============================================================
// FICHIER : lib/services/favoris_service.dart
// Gestion des favoris : Firestore (connecté) + SharedPrefs (visiteur/offline)
// ✅ Visiteur anonyme → SharedPreferences clé "favoris_visiteur"
// ✅ Prestataire connecté → users/{uid}/favoris/{logementId}
// ✅ Fusion automatique visiteur → Firestore à la connexion
// ✅ Mode hors connexion : lecture depuis le cache local
// ============================================================

/// Snapshot minimal d'un favori tel que stocké en local ou Firestore.
class _FavoriData {
  final String logementId;
  final String titre;
  final double prix;
  final String ville;
  final String quartier;
  final String? photo;
  final DateTime addedAt;

  const _FavoriData({
    required this.logementId,
    required this.titre,
    required this.prix,
    required this.ville,
    required this.quartier,
    this.photo,
    required this.addedAt,
  });

  // ── Sérialisation JSON (SharedPreferences) ──────────────────────────────
  Map<String, dynamic> toJson() => {
    'logementId': logementId,
    'titre': titre,
    'prix': prix,
    'ville': ville,
    'quartier': quartier,
    'photo': photo,
    'addedAt': addedAt.toIso8601String(),
  };

  factory _FavoriData.fromJson(Map<String, dynamic> json) => _FavoriData(
    logementId: json['logementId'] as String,
    titre: json['titre'] as String,
    prix: (json['prix'] as num).toDouble(),
    ville: json['ville'] as String,
    quartier: json['quartier'] as String,
    photo: json['photo'] as String?,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );

  // ── Conversion Firestore ─────────────────────────────────────────────────
  Map<String, dynamic> toFirestore() => {
    'logementId': logementId,
    'titre': titre,
    'prix': prix,
    'ville': ville,
    'quartier': quartier,
    'photo': photo,
    'addedAt': Timestamp.fromDate(addedAt),
  };

  factory _FavoriData.fromFirestore(Map<String, dynamic> data) => _FavoriData(
    logementId: data['logementId'] as String,
    titre: data['titre'] as String,
    prix: (data['prix'] as num).toDouble(),
    ville: data['ville'] as String,
    quartier: data['quartier'] as String,
    photo: data['photo'] as String?,
    addedAt: data['addedAt'] is Timestamp
        ? (data['addedAt'] as Timestamp).toDate()
        : DateTime.parse(data['addedAt'] as String),
  );

  /// Construit un _FavoriData à partir du modèle Logement complet.
  factory _FavoriData.fromLogement(Logement logement) => _FavoriData(
    logementId: logement.id,
    titre: logement.titre,
    prix: logement.prix,
    ville: logement.ville,
    quartier: logement.quartier,
    photo: logement.photos.isNotEmpty ? logement.photos.first : null,
    addedAt: DateTime.now(),
  );

  /// Reconstruit un Logement minimal depuis le snapshot (pour l'affichage offline).
  Logement toLogement() => Logement(
    id: logementId,
    titre: titre,
    description: '',
    prix: prix,
    typeLocation: 'location',
    typeBien: '',
    ville: ville,
    quartier: quartier,
    latitude: 0,
    longitude: 0,
    photos: photo != null ? [photo!] : [],
    surface: 0,
    nbPieces: 0,
    equipements: const [],
    estVerifie: false,
    estSponsorie: false,
    prestatireId: '',
    prestatireNom: '',
    prestatirePhone: '',
    datePublication: addedAt,
    nbVues: 0,
    disponible: true,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

const _kFavorisVisiteur = 'favoris_visiteur'; // clé SharedPreferences
const _kFavorisCache = 'favoris_cache';       // clé cache offline (connecté)

class FavorisService {
  FavorisService._internal();
  static final FavorisService instance = FavorisService._internal();

  final _db = FirebaseFirestore.instance;
  final _auth = AuthService.instance;

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _estConnecte => _auth.isLoggedIn;
  String? get _uid => _auth.currentUser?.id;

  CollectionReference<Map<String, dynamic>> get _firestoreFavoris =>
      _db.collection('users').doc(_uid!).collection('favoris');

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // ─── LECTURE ──────────────────────────────────────────────────────────────

  /// Retourne la liste des favoris :
  /// - Connecté + internet : Firestore en temps réel (Stream)
  /// - Connecté + hors connexion : cache SharedPreferences
  /// - Visiteur : SharedPreferences
  ///
  /// Utilisez [watchFavoris] pour un Stream réactif.
  Future<List<Logement>> getFavoris() async {
    if (_estConnecte) {
      final hasNet = await _hasInternet();
      if (hasNet) {
        final snap = await _firestoreFavoris.orderBy('addedAt', descending: true).get();
        final logements = snap.docs.map((d) {
          final data = _FavoriData.fromFirestore(d.data());
          return data.toLogement();
        }).toList();
        // Mise à jour du cache offline
        await _saveCacheConnecte(snap.docs.map((d) => _FavoriData.fromFirestore(d.data())).toList());
        return logements;
      } else {
        // Mode hors connexion : lecture depuis le cache
        return _getFavorisDepuisCache();
      }
    } else {
      return _getFavorisVisiteur();
    }
  }

  /// Stream réactif (Firestore) pour les utilisateurs connectés.
  /// Retourne null pour les visiteurs (utiliser [getFavoris] à la place).
  Stream<List<Logement>>? watchFavoris() {
    if (!_estConnecte) return null;
    return _firestoreFavoris
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = _FavoriData.fromFirestore(d.data());
      return data.toLogement();
    }).toList());
  }

  // ─── ÉCRITURE ─────────────────────────────────────────────────────────────

  /// Ajoute un logement aux favoris (Firestore ou SharedPrefs selon l'état).
  Future<void> ajouterFavori(Logement logement) async {
    final data = _FavoriData.fromLogement(logement);

    if (_estConnecte) {
      await _firestoreFavoris.doc(logement.id).set(data.toFirestore());
      await _updateCacheConnecte(logement.id, data, add: true);
    } else {
      await _saveVisiteurFavori(data);
    }
  }

  /// Supprime un favori par son ID.
  Future<void> supprimerFavori(String logementId) async {
    if (_estConnecte) {
      await _firestoreFavoris.doc(logementId).delete();
      await _updateCacheConnecte(logementId, null, add: false);
    } else {
      await _removeVisiteurFavori(logementId);
    }
  }

  /// Vérifie si un logement est dans les favoris.
  Future<bool> isFavori(String logementId) async {
    if (_estConnecte) {
      final hasNet = await _hasInternet();
      if (hasNet) {
        final doc = await _firestoreFavoris.doc(logementId).get();
        return doc.exists;
      } else {
        // Fallback sur le cache
        final cached = await _getFavorisDepuisCache();
        return cached.any((l) => l.id == logementId);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFavorisVisiteur);
      if (raw == null) return false;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.any((e) => e['logementId'] == logementId);
    }
  }

  // ─── FUSION VISITEUR → FIRESTORE ──────────────────────────────────────────

  /// À appeler juste après une connexion réussie.
  /// Migre les favoris visiteur vers Firestore et nettoie SharedPreferences.
  Future<void> fusionnerFavorisVisiteur() async {
    final visiteurFavoris = await _getVisiteurFavorisData();
    if (visiteurFavoris.isEmpty) return;

    final batch = _db.batch();
    for (final data in visiteurFavoris) {
      final ref = _firestoreFavoris.doc(data.logementId);
      // SetOptions(merge: true) pour ne pas écraser un favori déjà présent
      batch.set(ref, data.toFirestore(), SetOptions(merge: true));
    }
    await batch.commit();

    // Nettoyage SharedPreferences visiteur
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFavorisVisiteur);
  }

  // ─── GESTION VISITEUR (SharedPreferences) ─────────────────────────────────

  Future<List<_FavoriData>> _getVisiteurFavorisData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavorisVisiteur);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(_FavoriData.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Logement>> _getFavorisVisiteur() async {
    final data = await _getVisiteurFavorisData();
    return data.map((d) => d.toLogement()).toList();
  }

  Future<void> _saveVisiteurFavori(_FavoriData data) async {
    final existing = await _getVisiteurFavorisData();
    // Pas de doublon
    if (existing.any((e) => e.logementId == data.logementId)) return;
    existing.insert(0, data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kFavorisVisiteur,
      jsonEncode(existing.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _removeVisiteurFavori(String logementId) async {
    final existing = await _getVisiteurFavorisData();
    existing.removeWhere((e) => e.logementId == logementId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kFavorisVisiteur,
      jsonEncode(existing.map((e) => e.toJson()).toList()),
    );
  }

  // ─── CACHE OFFLINE (utilisateur connecté) ────────────────────────────────

  Future<void> _saveCacheConnecte(List<_FavoriData> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kFavorisCache,
      jsonEncode(data.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<Logement>> _getFavorisDepuisCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavorisCache);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map((e) => _FavoriData.fromJson(e).toLogement()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Met à jour le cache offline suite à une opération (add/remove).
  Future<void> _updateCacheConnecte(
      String logementId,
      _FavoriData? data, {
        required bool add,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavorisCache);
    List<_FavoriData> cached = [];
    if (raw != null) {
      try {
        cached = (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(_FavoriData.fromJson)
            .toList();
      } catch (_) {}
    }

    if (add && data != null) {
      cached.removeWhere((e) => e.logementId == logementId);
      cached.insert(0, data);
    } else {
      cached.removeWhere((e) => e.logementId == logementId);
    }

    await prefs.setString(
      _kFavorisCache,
      jsonEncode(cached.map((e) => e.toJson()).toList()),
    );
  }
}