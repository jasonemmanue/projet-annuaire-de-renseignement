import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'notification_service.dart';
import 'auth_service.dart';
import '../models/models.dart';

class MessagerieService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  // ============================================================
  // Créer ou récupérer une conversation
  // ============================================================
  static Future<String> getOrCreateConversation({
    required String clientId,
    required String prestataireId,
    required String logementId,
    required String logementTitre,
    String? logementPhoto,
  }) async {
    // ── 1. Recherche conversation existante ──────────────────
    final existing = await _db
        .collection('conversations')
        .where('participants', arrayContains: clientId)
        .get();

    for (final doc in existing.docs) {
      final d = doc.data();
      final parts = List<String>.from(d['participants'] ?? []);
      if (parts.contains(prestataireId) &&
          d['logement_id'] == logementId) {
        return doc.id;
      }
    }

    // ── 2. Numérotation Contact N (visiteurs uniquement) ─────
    String contactLabel = '';
    int contactNumber = 0;

    if (clientId.startsWith('visiteur_')) {
      // Récupère TOUTES les convs du prestataire
      final allConvs = await _db
          .collection('conversations')
          .where('participants', arrayContains: prestataireId)
          .get();

      // Collecte les numéros déjà attribués aux visiteurs
      // clé = visiteur_uid, valeur = numéro Contact
      final Map<String, int> visiteurNumeros = {};
      int maxNumero = 0;

      for (final doc in allConvs.docs) {
        final d = doc.data();
        final uid = d['client_uid'] as String?;
        final n = d['contact_number'] as int?;

        // Compte uniquement les vrais visiteurs
        if (uid != null &&
            uid.startsWith('visiteur_') &&
            n != null &&
            n > 0) {
          visiteurNumeros[uid] = n;
          if (n > maxNumero) maxNumero = n;
        }
      }

      if (visiteurNumeros.containsKey(clientId)) {
        // Ce visiteur a déjà un numéro chez ce prestataire
        contactNumber = visiteurNumeros[clientId]!;
      } else {
        // Nouveau visiteur → prochain numéro disponible
        contactNumber = maxNumero + 1;
      }

      contactLabel = 'Contact$contactNumber';
    }

    // ── 3. Lecture d'une éventuelle urgence active pour ce client+logement ─
    Timestamp? urgenceUntil;
    try {
      final urgDoc = await _db
          .collection('urgences')
          .doc('${clientId}_$logementId')
          .get();
      final exp = urgDoc.data()?['expiresAt'];
      if (exp is Timestamp && exp.toDate().isAfter(DateTime.now())) {
        urgenceUntil = exp;
      }
    } catch (_) {}

    // ── 4. Création de la conversation ───────────────────────
    final conv = await _db.collection('conversations').add({
      'participants': [clientId, prestataireId],
      'client_uid': clientId,
      'prestataire_uid': prestataireId,
      'logement_id': logementId,
      'logement_titre': logementTitre,
      'logement_photo': logementPhoto,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$clientId': 0,
      'unread_$prestataireId': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (clientId.startsWith('visiteur_')) 'visitor_uid': clientId,
      if (contactLabel.isNotEmpty) 'contact_label': contactLabel,
      if (contactNumber > 0) 'contact_number': contactNumber,
      if (urgenceUntil != null) 'urgenceUntil': urgenceUntil,
    });

    return conv.id;
  }

  // ============================================================
  // Stream des conversations d'un utilisateur
  // ============================================================
  static Stream<QuerySnapshot> getConversations(String uid) {
    return _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots();
  }

  // ============================================================
  // Stream des messages
  // ============================================================
  static Stream<QuerySnapshot> getMessages(String conversationId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // ============================================================
  // Envoyer un message texte
  // ============================================================
  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
    required String recipientId,
    ReplyTo? replyTo,
  }) async {
    final batch = _db.batch();

    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId': senderId,
      'text': text,
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
    });

    batch.update(
      _db.collection('conversations').doc(conversationId),
      {
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$recipientId': FieldValue.increment(1),
      },
    );

    await batch.commit();

    try {
      final senderUser = AuthService.instance.currentUser;
      final senderName = senderUser != null
          ? '${senderUser.prenom} ${senderUser.nom}'.trim()
          : 'Visiteur';
      final convData = (await _db
              .collection('conversations')
              .doc(conversationId)
              .get())
          .data();
      await NotificationService.showMessageNotification(
        senderName: senderName.isEmpty ? 'Visiteur' : senderName,
        messageText: text,
        conversationId: conversationId,
        logementTitre:
            convData?['logement_titre'] as String? ?? '',
      );
    } catch (_) {}
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
    final safeId =
        senderId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_$safeId.jpg';
    final ref = _storage
        .ref()
        .child('messages/$conversationId/images/$fileName');

    final task = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'));
    final imageUrl = await task.ref.getDownloadURL();

    final batch = _db.batch();
    batch.set(
      _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(),
      {
        'senderId': senderId,
        'imageUrl': imageUrl,
        'type': 'image',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      },
    );
    batch.update(
      _db.collection('conversations').doc(conversationId),
      {
        'lastMessage': '📷 Photo',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$recipientId': FieldValue.increment(1),
      },
    );
    await batch.commit();
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
    final safeFileName =
        '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final ref = _storage
        .ref()
        .child('messages/$conversationId/files/$safeFileName');

    final task = await ref.putFile(file);
    final fileUrl = await task.ref.getDownloadURL();

    final batch = _db.batch();
    batch.set(
      _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(),
      {
        'senderId': senderId,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'type': 'file',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      },
    );
    batch.update(
      _db.collection('conversations').doc(conversationId),
      {
        'lastMessage': '📎 $fileName',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$recipientId': FieldValue.increment(1),
      },
    );
    await batch.commit();
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
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_$safeId.mp4';
    final ref = _storage
        .ref()
        .child('messages/$conversationId/videos/$fileName');

    final task = await ref.putFile(
        videoFile, SettableMetadata(contentType: 'video/mp4'));
    final videoUrl = await task.ref.getDownloadURL();

    final batch = _db.batch();
    batch.set(
      _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(),
      {
        'senderId': senderId,
        'videoUrl': videoUrl,
        'type': 'video',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      },
    );
    batch.update(
      _db.collection('conversations').doc(conversationId),
      {
        'lastMessage': '🎬 Vidéo',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$recipientId': FieldValue.increment(1),
      },
    );
    await batch.commit();
  }

  // ============================================================
  // Modifier un message texte
  // ============================================================
  static Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
  }) async {
    await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({'text': newText, 'edited': true});
  }

  // ============================================================
  // Supprimer un message (soft delete)
  // ============================================================
  static Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'deleted': true,
      'text': '',
      'type': 'deleted',
    });
  }

  // ============================================================
  // Marquer comme lu
  // ============================================================
  static Future<void> markAsRead(
      String conversationId, String userId) async {
    await _db
        .collection('conversations')
        .doc(conversationId)
        .update({'unread_$userId': 0});

    final unread = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .where('senderId', isNotEqualTo: userId)
        .get();

    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ============================================================
  // Supprimer une conversation + ses messages
  // ============================================================
  static Future<void> deleteConversation(
      String conversationId) async {
    final messages = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();

    final batch = _db.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    try {
      final notifs = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('visitor_notifications')
          .get();
      for (final doc in notifs.docs) {
        batch.delete(doc.reference);
      }
    } catch (_) {}

    batch.delete(
        _db.collection('conversations').doc(conversationId));
    await batch.commit();
  }

  // ============================================================
  // Supprimer TOUTES les conversations d'un logement
  // Appelé lors de la suppression d'une annonce
  // ============================================================
  static Future<void> deleteConversationsByLogement(
      String logementId) async {
    final convs = await _db
        .collection('conversations')
        .where('logement_id', isEqualTo: logementId)
        .get();

    for (final conv in convs.docs) {
      await deleteConversation(conv.id);
    }
  }
}
