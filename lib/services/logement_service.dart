import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'notification_service.dart';

class LogementService {
  static final _db = FirebaseFirestore.instance;

  // Stream logements pour l'accueil
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
    //    (les visiteurs ne voient plus la conv non plus)
    try {
      final convs = await _db
          .collection('conversations')
          .where('logement_id', isEqualTo: id)
          .get();
      for (final conv in convs.docs) {
        // Supprime les messages de la sous-collection
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

  // Logements sponsorisés
  static Stream<QuerySnapshot> getSponsored() {
    return _db
        .collection('logements')
        .where('isSponsored', isEqualTo: true)
        .limit(3)
        .snapshots();
  }
}