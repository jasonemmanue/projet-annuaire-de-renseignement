import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'api_client.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import '../models/models.dart';

// ============================================================
// FICHIER : lib/services/messagerie_service.dart
// Messagerie via l'API Horem+ (remplace les collections Firestore
// « conversations » / « messages »). Les pièces jointes restent dans
// Firebase Storage ; seule leur adresse passe par l'API.
// « Temps réel » : interrogation versionnée (voir ApiClient.sonder).
// ============================================================

class MessagerieService {
  static final _api = ApiClient.instance;
  static final _storage = FirebaseStorage.instance;

  // ============================================================
  // Créer ou récupérer une conversation (l'appelant est le client :
  // compte connecté ou visiteur identifié par X-Visiteur-Id)
  // ============================================================
  static Future<String> getOrCreateConversation({
    required String clientId,
    required String prestataireId,
    required String logementId,
    required String logementTitre,
    String? logementPhoto,
  }) async {
    final rep = await _api.post('/conversations', {
      'prestataireId': prestataireId,
      'logementId': logementId,
      'logementTitre': logementTitre,
      if (logementPhoto != null) 'logementPhoto': logementPhoto,
    }) as Map<String, dynamic>;
    return rep['id'] as String;
  }

  // Profils publics déjà demandés (une requête par personne et par session).
  static final Map<String, Future<Map<String, dynamic>?>> _profils = {};

  /// Nom, photo et téléphone d'un utilisateur (null si introuvable).
  static Future<Map<String, dynamic>?> profilPublic(String uid) {
    return _profils.putIfAbsent(uid, () async {
      try {
        return Map<String, dynamic>.from(
            await _api.get('/users/$uid/public') as Map);
      } catch (_) {
        _profils.remove(uid);
        return null;
      }
    });
  }

  /// Une conversation (null si introuvable ou inaccessible).
  static Future<Doc?> getConversation(String conversationId) async {
    try {
      return Doc.depuis(
          await _api.get('/conversations/$conversationId') as Map<String, dynamic>);
    } on ApiException {
      return null;
    }
  }

  // ============================================================
  // Flux des conversations de l'utilisateur courant
  // ============================================================
  static Stream<List<Doc>> getConversations(String uid) =>
      _api.sonder('/conversations', Doc.liste);

  /// Total des messages non lus (badges).
  static Stream<int> watchNonLus() => _api.sonder(
      '/conversations/non-lus', (rep) => (rep['total'] as num?)?.toInt() ?? 0);

  // ============================================================
  // Flux des messages d'une conversation (ordre chronologique)
  // ============================================================
  static Stream<List<Doc>> getMessages(String conversationId) => _api.sonder(
      '/conversations/$conversationId/messages', Doc.liste,
      intervalle: const Duration(seconds: 3));

  static Future<void> _poster(String conversationId, Map<String, dynamic> corps) =>
      _api.post('/conversations/$conversationId/messages', corps);

  // ============================================================
  // Envoyer un message texte (le serveur notifie le destinataire)
  // ============================================================
  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
    required String recipientId,
    ReplyTo? replyTo,
  }) async {
    await _poster(conversationId, {
      'type': 'text',
      'text': text,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
    });

    try {
      final senderUser = AuthService.instance.currentUser;
      final senderName = senderUser != null
          ? '${senderUser.prenom} ${senderUser.nom}'.trim()
          : 'Visiteur';
      final conv = await getConversation(conversationId);
      await NotificationService.showMessageNotification(
        senderName: senderName.isEmpty ? 'Visiteur' : senderName,
        messageText: text,
        conversationId: conversationId,
        logementTitre: conv?['logement_titre'] as String? ?? '',
      );
    } catch (_) {}
  }

  static Future<String> _televerser(
      String chemin, File fichier, String? typeMime) async {
    final task = await _storage.ref().child(chemin).putFile(
        fichier, typeMime != null ? SettableMetadata(contentType: typeMime) : null);
    return task.ref.getDownloadURL();
  }

  // ============================================================
  // Envoyer une image (prestataire uniquement)
  // ============================================================
  static Future<void> sendImage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required File imageFile,
  }) async {
    final safeId = senderId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeId.jpg';
    final url = await _televerser(
        'messages/$conversationId/images/$fileName', imageFile, 'image/jpeg');
    await _poster(conversationId, {'type': 'image', 'imageUrl': url});
  }

  // ============================================================
  // Envoyer un fichier (prestataire uniquement)
  // ============================================================
  static Future<void> sendFile({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required File file,
    required String fileName,
  }) async {
    final safeFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final url = await _televerser(
        'messages/$conversationId/files/$safeFileName', file, null);
    await _poster(conversationId,
        {'type': 'file', 'fileUrl': url, 'fileName': fileName});
  }

  // ============================================================
  // Envoyer une vidéo (prestataire uniquement)
  // ============================================================
  static Future<void> sendVideo({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required File videoFile,
  }) async {
    final safeId = senderId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeId.mp4';
    final url = await _televerser(
        'messages/$conversationId/videos/$fileName', videoFile, 'video/mp4');
    await _poster(conversationId, {'type': 'video', 'videoUrl': url});
  }

  // ============================================================
  // Modifier un message texte (auteur seulement)
  // ============================================================
  static Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
  }) =>
      _api.patch('/conversations/$conversationId/messages/$messageId',
          {'text': newText});

  // ============================================================
  // Supprimer un message (suppression douce)
  // ============================================================
  static Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) =>
      _api.delete('/conversations/$conversationId/messages/$messageId');

  // ============================================================
  // Marquer comme lu
  // ============================================================
  static Future<void> markAsRead(String conversationId, String userId) async {
    try {
      await _api.post('/conversations/$conversationId/lu');
    } catch (_) {}
  }

  // ============================================================
  // Supprimer une conversation + ses messages
  // ============================================================
  static Future<void> deleteConversation(String conversationId) =>
      _api.delete('/conversations/$conversationId');

  // ============================================================
  // Les conversations d'une annonce supprimée sont effacées par le
  // serveur avec l'annonce : plus rien à faire côté app.
  // ============================================================
  static Future<void> deleteConversationsByLogement(String logementId) async {}
}
