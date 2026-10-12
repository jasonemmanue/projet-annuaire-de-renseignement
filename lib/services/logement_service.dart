import 'dart:math';
import 'api_client.dart';
import 'notification_service.dart';
import '../models/models.dart';

// ============================================================
// FICHIER : lib/services/logement_service.dart
// Annonces via l'API Horem+ (remplace la collection Firestore
// « logements »). L'état d'une annonce (disponible, visibleAdmin,
// paiement, expirations) est décidé par le serveur.
// ============================================================

class LogementService {
  static final _api = ApiClient.instance;

  static List<Logement> _liste(dynamic rep) => ApiClient.items(rep)
      .map((m) => Logement.fromMap(m['id'] as String, m))
      .toList();

  /// Annonces visibles par les visiteurs, déjà triées par priorité
  /// (sponsorisées, actives, expirées) puis par date.
  static Future<List<Logement>> getFutureLogements({
    String? ville,
    String? type,
    double? prixMax,
    double? prixMin,
    String? recherche,
    int limit = 500,
  }) async {
    final rep = await _api.get('/logements', params: {
      'ville': ville,
      'typeBien': type,
      'prixMin': prixMin,
      'prixMax': prixMax,
      'q': recherche,
      'limit': limit,
    });
    return _liste(rep);
  }

  /// Flux des annonces visibles (carte) : rafraîchi toutes les 30 s.
  static Stream<List<Logement>> getLogements({
    String? ville,
    String? type,
    double? prixMax,
    double? prixMin,
  }) async* {
    while (true) {
      try {
        yield await getFutureLogements(
            ville: ville, type: type, prixMax: prixMax, prixMin: prixMin);
      } catch (_) {
        // Réseau indisponible : on réessaie au prochain tour.
      }
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  /// Une annonce par son identifiant (null si introuvable).
  static Future<Logement?> getLogement(String id) async {
    try {
      final m = await _api.get('/logements/$id') as Map<String, dynamic>;
      return Logement.fromMap(m['id'] as String, m);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Annonces du prestataire connecté (tous états), « temps réel ».
  static Stream<List<Logement>> getMesLogements(String uid) =>
      _api.sonder('/logements/mes', _liste,
          intervalle: const Duration(seconds: 4));

  /// Lecture immédiate des annonces du prestataire.
  static Future<List<Logement>> getMesLogementsMaintenant() async =>
      _liste(await _api.get('/logements/mes'));

  /// Crée une annonce. Pharmacie : publiée tout de suite ; autres types :
  /// brouillon en attente de paiement. Renvoie l'identifiant.
  /// Actualisation gratuite (repousse de 21 jours le masquage automatique).
  static Future<void> actualiser(String logementId) async {
    await _api.post('/logements/$logementId/actualiser');
  }

  static Future<String> addLogement(Map<String, dynamic> data) async {
    final rep = await _api.post('/logements', data) as Map<String, dynamic>;
    final id = rep['id'] as String;
    if (rep['disponible'] == true) {
      try {
        await NotificationService.showNouvelleAnnonceNotification(
          titre: data['titre'] as String? ?? 'Nouvelle annonce',
          ville: data['ville'] as String? ?? '',
          quartier: data['quartier'] as String? ?? '',
          logementId: id,
        );
      } catch (_) {
        // Non bloquant
      }
    }
    return id;
  }

  /// Modifie le contenu (et/ou `disponible`). Lève [ApiException] si la
  /// bascule est refusée (code `admin_visibility_required` ou
  /// `paiement_requis`).
  static Future<Logement> updateLogement(
      String id, Map<String, dynamic> data) async {
    final m = await _api.patch('/logements/$id', data) as Map<String, dynamic>;
    return Logement.fromMap(m['id'] as String, m);
  }

  /// Compte offert : publie le brouillon sans paiement.
  static Future<void> activerGratuit(String id) =>
      _api.post('/logements/$id/activer-gratuit');

  /// Compte offert : mise en avant sans paiement ('1s' | '2s' | '1m').
  static Future<void> sponsoriserGratuit(String id, String duree) =>
      _api.post('/logements/$id/sponsoriser-gratuit', {'duree': duree});

  /// Supprime l'annonce, ses photos (Storage) et ses conversations
  /// (fait par le serveur).
  static Future<void> deleteLogement(String id) => _api.delete('/logements/$id');

  // Compteurs publics (le serveur limite à une vue par appareil / 10 min).
  static Future<void> incrementVues(String id) async {
    try {
      await _api.post('/logements/$id/vue');
    } catch (_) {}
  }

  static Future<void> incrementContacts(String id) async {
    try {
      await _api.post('/logements/$id/contact');
    } catch (_) {}
  }

  /// Annonces sponsorisées en cours (3 max), rafraîchies toutes les 60 s.
  static Stream<List<Logement>> getSponsored() async* {
    while (true) {
      try {
        yield _liste(await _api.get('/logements/sponsorises'));
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 60));
    }
  }

  // ============================================================
  // ── STATISTIQUES PRESTATAIRE ─────────────────────────────────
  // ============================================================

  /// Agrégat des statistiques du prestataire connecté :
  /// totalVues, totalContacts, totalAnnonces, totalAnnoncesSponsorisees,
  /// tauxConversion, meilleurAnnonce, vuesParAnnonce.
  static Future<Map<String, dynamic>> getStatistiquesPrestataire(
      String uid) async {
    final rep = Map<String, dynamic>.from(
        await _api.get('/logements/mes/statistiques') as Map);
    rep['vuesParAnnonce'] = ((rep['vuesParAnnonce'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (rep['meilleurAnnonce'] != null) {
      rep['meilleurAnnonce'] =
          Map<String, dynamic>.from(rep['meilleurAnnonce'] as Map);
    }
    rep['tauxConversion'] = (rep['tauxConversion'] as num?)?.toDouble() ?? 0.0;
    return rep;
  }

  /// Évolution des vues sur [dernierNJours] jours (vues réelles par jour,
  /// enregistrées par l'API). Pour une annonce plus ancienne que cet
  /// historique, les vues déjà cumulées sont réparties (courbe estimée).
  ///
  /// Retourne : [{'jour': 'Lun', 'date': DateTime, 'vues': int}, ...]
  static Future<List<Map<String, dynamic>>> getEvolutionVues(
      String logementId, int dernierNJours) async {
    final rep = await _api.get('/logements/$logementId/evolution-vues',
        params: {'jours': dernierNJours}) as Map<String, dynamic>;
    final points = (rep['points'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final totalVues = (rep['totalVues'] as num?)?.toInt() ?? 0;
    final sommeHistorique =
        points.fold<int>(0, (s, p) => s + ((p['vues'] as num?)?.toInt() ?? 0));

    if (sommeHistorique > 0 || totalVues == 0) {
      return points.map((p) {
        final date = DateTime.tryParse(p['date'] as String? ?? '') ?? DateTime.now();
        return {
          'jour': _jourAbrege(date),
          'date': date,
          'vues': (p['vues'] as num?)?.toInt() ?? 0,
        };
      }).toList();
    }

    // Pas encore d'historique : répartition déterministe des vues cumulées.
    final rng = Random(logementId.hashCode);
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    final baseParJour = (totalVues / dernierNJours).clamp(0.5, double.infinity);
    for (int i = dernierNJours - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final trend = 0.7 + (0.6 * (dernierNJours - i) / dernierNJours);
      final bruit = 0.7 + rng.nextDouble() * 0.6;
      final vues = (baseParJour * trend * bruit).round().clamp(0, 9999);
      result.add({'jour': _jourAbrege(date), 'date': date, 'vues': vues});
    }
    return result;
  }

  // ── Helpers internes ─────────────────────────────────────────

  static const _joursAbreges = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];

  static String _jourAbrege(DateTime date) => _joursAbreges[date.weekday % 7];
}
