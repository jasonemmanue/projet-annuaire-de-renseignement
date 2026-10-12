import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import 'api_client.dart';

// ============================================================
// SERVICE : PubliciteService
// Gestion des publicités prestataires — collection "publicites"
// ============================================================

class PubliciteService {
  static final _api = ApiClient.instance;

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
    String? logementId,
    String? logementTitre,
    String? logementPhoto,
  }) async {
    // Dossier Storage provisoire (l'identifiant définitif vient de l'API).
    final dossier = 'p${DateTime.now().millisecondsSinceEpoch}_$prestataireId';

    final photoUrls = await Future.wait(
      photos.map((img) => _uploadPhoto(dossier, img)),
    );

    String? videoUrl;
    if (video != null) {
      videoUrl = await _uploadVideo(dossier, video);
    }

    final rep = await _api.post('/publicites', {
      'prestataireNom': prestataireNom,
      'prestatairePhone': prestatairePhone,
      if (prestatairePhoto != null) 'prestatairePhoto': prestatairePhoto,
      'titre': titre,
      'description': description,
      'photos': photoUrls,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (logementId != null) 'logementId': logementId,
      if (logementTitre != null) 'logementTitre': logementTitre,
      if (logementPhoto != null) 'logementPhoto': logementPhoto,
    }) as Map<String, dynamic>;
    return rep['id'] as String;
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
    await _api.patch('/publicites/$pubId', updates);
  }

  // ── Lecture ───────────────────────────────────────────────

  /// Publicités diffusables côté visiteur : actives, payées, non expirées.
  static Stream<List<Publicite>> watchPublicitesDiffusables() => _api.sonder(
        '/publicites/diffusables',
        (rep) => ApiClient.items(rep)
            .map((m) => Publicite.fromMap(m['id'] as String, m))
            .where((p) => p.estDiffusable)
            .toList(),
        intervalle: const Duration(seconds: 30),
      );

  /// Publicités du prestataire connecté (son dashboard).
  static Stream<List<Publicite>> getPublicitesPrestataire(String uid) =>
      _api.sonder(
        '/publicites/mes',
        (rep) => ApiClient.items(rep)
            .map((m) => Publicite.fromMap(m['id'] as String, m))
            .toList(),
      );

  /// Compte offert : diffusion de 4 jours sans paiement.
  static Future<void> activerGratuit(String id) =>
      _api.post('/publicites/$id/activer-gratuit');

  // ── Admin ─────────────────────────────────────────────────

  /// Active ou désactive une publicité (admin).
  static Future<void> setActif(String id, bool actif) =>
      _api.patch('/admin/publicites/$id', {'actif': actif});

  /// Supprime une publicité et ses médias (propriétaire ou admin).
  /// Aucun remboursement même si la pub était encore active.
  static Future<void> supprimer(String id) => _api.delete('/publicites/$id');
}
