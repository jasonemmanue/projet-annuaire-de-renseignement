import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'auth_service.dart';

// ============================================================
// FICHIER : lib/services/favoris_service.dart
// Gestion des favoris : API (connecté) + SharedPrefs (visiteur/offline)
// ✅ Visiteur anonyme → SharedPreferences clé "favoris_visiteur"
// ✅ Prestataire connecté → API /favoris
// ✅ Fusion automatique visiteur → compte à la connexion
// ✅ isFavori lit un ensemble en mémoire (aucun appel réseau par carte)
// ✅ Mode hors connexion : lecture depuis le cache local
// ============================================================

/// Snapshot minimal d'un favori tel que stocké en local ou dans l'API.
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

  // ── Conversion API ───────────────────────────────────────────────────────
  factory _FavoriData.fromApi(Map<String, dynamic> data) => _FavoriData(
    logementId: data['logementId'] as String,
    titre: data['titre'] as String? ?? '',
    prix: (data['prix'] as num?)?.toDouble() ?? 0,
    ville: data['ville'] as String? ?? '',
    quartier: data['quartier'] as String? ?? '',
    photo: data['photo'] as String?,
    addedAt: apiDate(data['addedAt']) ?? DateTime.now(),
  );

  /// Construit un _FavoriData à partir du modèle Logement complet.
  factory _FavoriData.fromLogement(Logement logement) => _FavoriData(
    logementId: logement.id,
    titre: logement.titre,
    prix: logement.prixAffiche,
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

  final _api = ApiClient.instance;
  final _auth = AuthService.instance;

  /// Identifiants favoris du compte connecté (null = pas encore chargés).
  Set<String>? _ids;
  String? _idsUid;

  // ── Stream de changements (visiteur / mode offline) ───────────────────────
  // Permet à FavorisScreen de se rafraîchir sans flux réseau.
  static final StreamController<void> _changeCtrl =
      StreamController<void>.broadcast();
  static Stream<void> get onFavoriChanged => _changeCtrl.stream;

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _estConnecte => _auth.isLoggedIn;
  String? get _uid => _auth.currentUser?.id;

  Future<List<_FavoriData>> _lireApi() async {
    final items = ApiClient.items(await _api.get('/favoris'));
    final data = items.map(_FavoriData.fromApi).toList();
    _ids = data.map((d) => d.logementId).toSet();
    _idsUid = _uid;
    return data;
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // ─── LECTURE ──────────────────────────────────────────────────────────────

  /// Retourne la liste des favoris :
  /// - Connecté + internet : API
  /// - Connecté + hors connexion : cache SharedPreferences
  /// - Visiteur : SharedPreferences
  ///
  /// Utilisez [watchFavoris] pour un Stream réactif.
  Future<List<Logement>> getFavoris() async {
    if (_estConnecte) {
      final hasNet = await _hasInternet();
      if (hasNet) {
        try {
          final data = await _lireApi();
          // Mise à jour du cache offline
          await _saveCacheConnecte(data);
          return data.map((d) => d.toLogement()).toList();
        } catch (_) {
          return _getFavorisDepuisCache();
        }
      } else {
        // Mode hors connexion : lecture depuis le cache
        return _getFavorisDepuisCache();
      }
    } else {
      return _getFavorisVisiteur();
    }
  }

  /// Stream réactif pour les utilisateurs connectés (interrogation
  /// versionnée). Retourne null pour les visiteurs ([getFavoris]).
  Stream<List<Logement>>? watchFavoris() {
    if (!_estConnecte) return null;
    return _api.sonder('/favoris', (rep) {
      final data = ApiClient.items(rep).map(_FavoriData.fromApi).toList();
      _ids = data.map((d) => d.logementId).toSet();
      _idsUid = _uid;
      return data.map((d) => d.toLogement()).toList();
    });
  }

  // ─── ÉCRITURE ─────────────────────────────────────────────────────────────

  /// Ajoute un logement aux favoris (API ou SharedPrefs selon l'état).
  Future<void> ajouterFavori(Logement logement) async {
    final data = _FavoriData.fromLogement(logement);

    if (_estConnecte) {
      await _api.put('/favoris/${logement.id}', data.toJson());
      _ids?.add(logement.id);
      await _updateCacheConnecte(logement.id, data, add: true);
    } else {
      await _saveVisiteurFavori(data);
    }
    _changeCtrl.add(null); // notifie tous les _FavoriteButton
  }

  /// Supprime un favori par son ID.
  Future<void> supprimerFavori(String logementId) async {
    if (_estConnecte) {
      await _api.delete('/favoris/$logementId');
      _ids?.remove(logementId);
      await _updateCacheConnecte(logementId, null, add: false);
    } else {
      await _removeVisiteurFavori(logementId);
    }
    _changeCtrl.add(null); // notifie tous les _FavoriteButton
  }

  /// Vérifie si un logement est dans les favoris.
  Future<bool> isFavori(String logementId) async {
    if (_estConnecte) {
      if (_ids != null && _idsUid == _uid) return _ids!.contains(logementId);
      final hasNet = await _hasInternet();
      if (hasNet) {
        try {
          await _lireApi();
          return _ids!.contains(logementId);
        } catch (_) {
          final cached = await _getFavorisDepuisCache();
          return cached.any((l) => l.id == logementId);
        }
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

  // ─── FUSION VISITEUR → COMPTE ─────────────────────────────────────────────

  /// À appeler juste après une connexion réussie.
  /// Migre les favoris visiteur vers le compte et nettoie SharedPreferences.
  Future<void> fusionnerFavorisVisiteur() async {
    final visiteurFavoris = await _getVisiteurFavorisData();
    if (visiteurFavoris.isEmpty) return;

    // Un favori déjà présent dans le compte n'est pas écrasé.
    await _api.post('/favoris/fusion',
        {'items': visiteurFavoris.map((d) => d.toJson()).toList()});
    _ids = null;

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