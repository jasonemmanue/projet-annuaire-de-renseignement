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

  // ── Publier une nouvelle publicité ────────────────────────

  static Future<String> publier({
    required String prestataireId,
    required String prestataireNom,
    required String prestatairePhone,
    String? prestatairePhoto,
    required String titre,
    required String description,
    required List<XFile> photos,
    XFile? video,
  }) async {
    // Créer le document d'abord pour avoir l'ID
    final docRef = _db.collection('publicites').doc();
    final pubId = docRef.id;

    // Upload photos
    final photoUrls = await Future.wait(
      photos.map((img) => _uploadPhoto(pubId, img)),
    );

    // Upload vidéo si présente
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
      actif: true,
    );

    await docRef.set(pub.toMap());
    return pubId;
  }

  // ── Lecture ───────────────────────────────────────────────

  /// Toutes les publicités actives (pour l'accueil visiteur)
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

  /// Supprime une publicité (prestataire propriétaire ou admin)
  static Future<void> supprimer(String id) async =>
      _db.collection('publicites').doc(id).delete();

  // Toutes les publicités (admin uniquement)
  static Stream<QuerySnapshot> getToutesPublicites() =>
      _db
          .collection('publicites')
          .orderBy('dateCreation', descending: true)
          .snapshots();
}
