import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';

// ============================================================
// SERVICE : PubliciteService
// Gestion des publicités prestataires — collection "publicites"
// ============================================================

class PubliciteService {
  static final _db = FirebaseFirestore.instance;

  /// Tarif & durée d'une période de diffusion publicitaire.
  static const int montantParPeriode = 500; // XAF
  static const int dureeJours = 4;
  static const String devise = 'XAF';

  // ── Upload médias ─────────────────────────────────────────

  static FirebaseStorage get _storageRef => FirebaseStorage.instance;

  static Future<String> _uploadPhoto(String pubId, XFile image) async {
    final bytes = await image.readAsBytes();
    final ref = _storageRef
        .ref()
        .child('publicites/$pubId/${DateTime.now().millisecondsSinceEpoch}.jpg');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  static Future<String> _uploadVideo(String pubId, XFile video) async {
    final bytes = await video.readAsBytes();
    final ref = _storageRef
        .ref()
        .child('publicites/$pubId/video_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'video/mp4'),
    );
    return task.ref.getDownloadURL();
  }

  // ── Création brouillon (avant paiement) ─────────────────────
  //
  // La pub est créée en mode `paymentPending: true, actif: false` (brouillon).
  // Le paiement de 500 XAF / 4 jours doit être confirmé pour qu'elle devienne
  // diffusable : le webhook GeniusPay (Cloud Function appliquerTransactionReussie)
  // fixera `paymentPending: false, actif: true, expiresAt: now + 4j`.

  static Future<String> creerBrouillon({
    required String prestataireId,
    required String prestataireNom,
    required String prestatairePhone,
    String? prestatairePhoto,
    required String titre,
    required String description,
    required List<XFile> photos,
    XFile? video,
  }) async {
    final docRef = _db.collection('publicites').doc();
    final pubId = docRef.id;

    final photoUrls = await Future.wait(
      photos.map((img) => _uploadPhoto(pubId, img)),
    );

    String? videoUrl;
    if (video != null) {
      videoUrl = await _uploadVideo(pubId, video);
    }

    final pub = Publicite(
      id: pubId,
      prestataireId: prestataireId,
      prestataireNom: prestataireNom,
      prestatairePhone: prestatairePhone,
      prestatairePhoto: prestatairePhoto,
      titre: titre,
      description: description,
      photos: photoUrls,
      videoUrl: videoUrl,
      dateCreation: DateTime.now(),
      actif: false,           // pas encore diffusable
      paymentPending: true,   // en attente du paiement initial
    );

    await docRef.set(pub.toMap());
    return pubId;
  }

  // ── Mise à jour (gratuite, tant que la pub courante est active) ────
  static Future<void> mettreAJour(
    String pubId, {
    String? titre,
    String? description,
  }) async {
    final updates = <String, dynamic>{};
    if (titre != null) updates['titre'] = titre;
    if (description != null) updates['description'] = description;
    if (updates.isEmpty) return;
    await _db.collection('publicites').doc(pubId).update(updates);
  }

  // ── Lecture ───────────────────────────────────────────────

  /// Publicités diffusables côté visiteur : actif + non expirées.
  /// Note : le filtrage `expiresAt > now` est fait côté client pour éviter
  /// le besoin d'un index composite (actif + expiresAt).
  static Stream<List<Publicite>> watchPublicitesDiffusables() {
    return _db
        .collection('publicites')
        .where('actif', isEqualTo: true)
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => Publicite.fromMap(d.id, d.data()))
          .where((p) =>
              !p.paymentPending &&
              p.expiresAt != null &&
              p.expiresAt!.isAfter(now))
          .toList();
    });
  }

  /// Toutes les publicités actives (legacy, conservée pour compat).
  static Stream<QuerySnapshot> getPublicitesActives() =>
      _db
          .collection('publicites')
          .where('actif', isEqualTo: true)
          .orderBy('dateCreation', descending: true)
          .snapshots();

  /// Publicités d'un prestataire spécifique (pour son dashboard)
  static Stream<QuerySnapshot> getPublicitesPrestataire(String uid) =>
      _db
          .collection('publicites')
          .where('prestataireId', isEqualTo: uid)
          .snapshots();

  // ── Admin ─────────────────────────────────────────────────

  /// Active ou désactive une publicité (admin)
  static Future<void> setActif(String id, bool actif) async =>
      _db.collection('publicites').doc(id).update({'actif': actif});

  /// Supprime une publicité (prestataire propriétaire ou admin).
  /// Aucun remboursement même si la pub était encore active.
  static Future<void> supprimer(String id) async =>
      _db.collection('publicites').doc(id).delete();

  // Toutes les publicités (admin uniquement)
  static Stream<QuerySnapshot> getToutesPublicites() =>
      _db
          .collection('publicites')
          .orderBy('dateCreation', descending: true)
          .snapshots();
}
