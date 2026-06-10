import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'notification_service.dart';
import '../models/models.dart';

class LogementService {
  static final _db = FirebaseFirestore.instance;

  // Stream logements pour l'accueil (conservé pour compatibilité)
  static Stream<QuerySnapshot> getLogements({
    String? ville,
    String? type,
    double? prixMax,
    double? prixMin,
  }) {
    Query q = _db
        .collection('logements')
        .orderBy('createdAt', descending: true);

    if (ville != null && ville.isNotEmpty) {
      q = q.where('ville', isEqualTo: ville);
    }
    if (type != null && type.isNotEmpty) {
      q = q.where('type', isEqualTo: type);
    }
    if (prixMax != null) {
      q = q.where('prix', isLessThanOrEqualTo: prixMax);
    }
    if (prixMin != null) {
      q = q.where('prix', isGreaterThanOrEqualTo: prixMin);
    }

    return q.snapshots();
  }

  // Future<List<Logement>> — utilisé par accueil_screen et liste_logements_screen
  static Future<List<Logement>> getFutureLogements({
    String? ville,
    String? type,
    double? prixMax,
    double? prixMin,
  }) async {
    Query q = _db
        .collection('logements')
        .orderBy('createdAt', descending: true);

    if (ville != null && ville.isNotEmpty) {
      q = q.where('ville', isEqualTo: ville);
    }
    if (type != null && type.isNotEmpty) {
      q = q.where('type', isEqualTo: type);
    }
    if (prixMax != null) {
      q = q.where('prix', isLessThanOrEqualTo: prixMax);
    }
    if (prixMin != null) {
      q = q.where('prix', isGreaterThanOrEqualTo: prixMin);
    }

    final snap = await q.get();
    return snap.docs
        .map((d) => Logement.fromMap(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // Logements d'un prestataire
  static Stream<QuerySnapshot> getMesLogements(String uid) {
    return _db
        .collection('logements')
        .where('uid_prestataire', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Ajouter un logement
  static Future<String> addLogement(Map<String, dynamic> data) async {
    final doc = await _db.collection('logements').add({
      ...data,
      'vues': 0,
      'contacts': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ── Notification locale nouvelle annonce ──
    try {
      await NotificationService.showNouvelleAnnonceNotification(
        titre: data['titre'] as String? ?? 'Nouvelle annonce',
        ville: data['ville'] as String? ?? '',
        quartier: data['quartier'] as String? ?? '',
        logementId: doc.id,
      );
    } catch (_) {
      // Non bloquant
    }

    return doc.id;
  }

  // Modifier un logement
  static Future<void> updateLogement(
      String id, Map<String, dynamic> data) async {
    await _db.collection('logements').doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Supprimer un logement
  static Future<void> deleteLogement(String id) async {
    // 1. Supprime les photos du Storage
    try {
      final doc = await _db.collection('logements').doc(id).get();
      final data = doc.data();
      if (data != null) {
        final photos = List<String>.from(data['photos'] ?? []);
        for (final url in photos) {
          try {
            await FirebaseStorage.instance.refFromURL(url).delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Supprime toutes les conversations liées à ce logement
    try {
      final convs = await _db
          .collection('conversations')
          .where('logement_id', isEqualTo: id)
          .get();
      for (final conv in convs.docs) {
        final msgs = await conv.reference
            .collection('messages')
            .get();
        final batch = _db.batch();
        for (final msg in msgs.docs) {
          batch.delete(msg.reference);
        }
        batch.delete(conv.reference);
        await batch.commit();
      }
    } catch (_) {}

    // 3. Supprime le document logement
    await _db.collection('logements').doc(id).delete();
  }

  // Incrémenter les vues
  static Future<void> incrementVues(String id) async {
    await _db.collection('logements').doc(id).update({
      'vues': FieldValue.increment(1),
    });
  }

  // Incrémenter les contacts
  static Future<void> incrementContacts(String id) async {
    await _db.collection('logements').doc(id).update({
      'contacts': FieldValue.increment(1),
    });
  }

  // Logements sponsorisés (exclut les sponsorisations expirées)
  // ⚠️ Nécessite un index composite Firestore : isSponsored (==) + sponsoredUntil (>).
  // Firebase proposera un lien de création de l'index au 1er appel.
  static Stream<QuerySnapshot> getSponsored() {
    return _db
        .collection('logements')
        .where('isSponsored', isEqualTo: true)
        .where('sponsoredUntil', isGreaterThan: Timestamp.now())
        .limit(3)
        .snapshots();
  }

  // ============================================================
  // ── STATISTIQUES PRESTATAIRE ─────────────────────────────────
  // ============================================================

  /// Retourne un agrégat complet des statistiques du prestataire.
  ///
  /// Champs retournés :
  ///   totalVues                  (int)
  ///   totalContacts              (int)
  ///   totalAnnonces              (int)
  ///   totalAnnoncesSponsorisees  (int)
  ///   tauxConversion             (double) — contacts/vues * 100
  ///   meilleurAnnonce            (Map?)  — {titre, vues, photoUrl?}
  ///   vuesParAnnonce             (List<Map>) — [{id, titre, vues, contacts}]
  static Future<Map<String, dynamic>> getStatistiquesPrestataire(
      String uid) async {
    final snap = await _db
        .collection('logements')
        .where('uid_prestataire', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();

    if (snap.docs.isEmpty) {
      return {
        'totalVues': 0,
        'totalContacts': 0,
        'totalAnnonces': 0,
        'totalAnnoncesSponsorisees': 0,
        'tauxConversion': 0.0,
        'meilleurAnnonce': null,
        'vuesParAnnonce': <Map<String, dynamic>>[],
      };
    }

    int totalVues = 0;
    int totalContacts = 0;
    int totalSponsorisees = 0;
    Map<String, dynamic>? meilleur;
    int meilleurVues = -1;
    final List<Map<String, dynamic>> vuesParAnnonce = [];

    for (final doc in snap.docs) {
      final d = doc.data();
      final vues = (d['vues'] as num? ?? 0).toInt();
      final contacts = (d['contacts'] as num? ?? 0).toInt();
      final titre = d['titre'] as String? ?? 'Sans titre';
      final photos = List<String>.from(d['photos'] ?? []);
      final isSponsored = d['isSponsored'] as bool? ?? false;

      totalVues += vues;
      totalContacts += contacts;
      if (isSponsored) totalSponsorisees++;

      vuesParAnnonce.add({
        'id': doc.id,
        'titre': titre,
        'vues': vues,
        'contacts': contacts,
        'photoUrl': photos.isNotEmpty ? photos.first : null,
      });

      if (vues > meilleurVues) {
        meilleurVues = vues;
        meilleur = {
          'id': doc.id,
          'titre': titre,
          'vues': vues,
          'contacts': contacts,
          'photoUrl': photos.isNotEmpty ? photos.first : null,
        };
      }
    }

    final tauxConversion = totalVues > 0
        ? (totalContacts / totalVues) * 100.0
        : 0.0;

    // Trier par vues décroissantes pour le graphique barres (max 5)
    vuesParAnnonce.sort((a, b) =>
        (b['vues'] as int).compareTo(a['vues'] as int));

    return {
      'totalVues': totalVues,
      'totalContacts': totalContacts,
      'totalAnnonces': snap.docs.length,
      'totalAnnoncesSponsorisees': totalSponsorisees,
      'tauxConversion': tauxConversion,
      'meilleurAnnonce': meilleur,
      'vuesParAnnonce': vuesParAnnonce.take(5).toList(),
    };
  }

  /// Retourne une liste de [dernierNJours] points de données simulant
  /// l'évolution des vues d'un logement sur la période.
  ///
  /// Si une sous-collection `historique_vues` existe dans Firestore,
  /// on l'utilise. Sinon, on répartit les vues actuelles avec une légère
  /// variation aléatoire (seed déterministe par logementId).
  ///
  /// Retourne : List<Map<String, dynamic>>
  ///   [{'jour': 'Lun', 'date': DateTime, 'vues': int}, ...]
  static Future<List<Map<String, dynamic>>> getEvolutionVues(
      String logementId, int dernierNJours) async {
    // 1. Tenter de lire une sous-collection historique réelle
    try {
      final histSnap = await _db
          .collection('logements')
          .doc(logementId)
          .collection('historique_vues')
          .orderBy('date', descending: false)
          .limitToLast(dernierNJours)
          .get();

      if (histSnap.docs.length >= dernierNJours) {
        return histSnap.docs.map((d) {
          final data = d.data();
          final ts = data['date'] as Timestamp?;
          final date = ts?.toDate() ?? DateTime.now();
          return {
            'jour': _jourAbrege(date),
            'date': date,
            'vues': (data['vues'] as num? ?? 0).toInt(),
          };
        }).toList();
      }
    } catch (_) {
      // Pas de sous-collection — on passe à la simulation
    }

    // 2. Simulation déterministe basée sur les vues actuelles
    final doc = await _db.collection('logements').doc(logementId).get();
    final totalVues = (doc.data()?['vues'] as num? ?? 0).toInt();

    final rng = Random(logementId.hashCode);
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    // Répartir les vues sur N jours avec une courbe légèrement croissante
    // et un bruit aléatoire contrôlé
    final baseParJour = totalVues > 0
        ? (totalVues / dernierNJours).clamp(0.5, double.infinity)
        : 1.0;

    for (int i = dernierNJours - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      // Tendance légèrement croissante vers aujourd'hui
      final trend = 0.7 + (0.6 * (dernierNJours - i) / dernierNJours);
      // Bruit aléatoire ±30 %
      final bruit = 0.7 + rng.nextDouble() * 0.6;
      final vues = (baseParJour * trend * bruit).round().clamp(0, 9999);
      result.add({
        'jour': _jourAbrege(date),
        'date': date,
        'vues': vues,
      });
    }

    return result;
  }

  // ── Helpers internes ─────────────────────────────────────────

  static const _joursAbreges = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];

  static String _jourAbrege(DateTime date) =>
      _joursAbreges[date.weekday % 7];
}