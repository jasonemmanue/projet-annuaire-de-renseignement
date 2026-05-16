import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'notification_service.dart';
import 'auth_service.dart';

// ============================================================
// FICHIER : lib/services/messagerie_service.dart
// Les notifications push sont gérées automatiquement par
// Cloud Functions (functions/index.js) à chaque nouveau
// message écrit dans Firestore – rien à faire côté Flutter.
// ============================================================

class MessagerieService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  // ============================================================
  // Créer ou récupérer une conversation existante
  // clientId : UID Firebase Auth OU identifiant visiteur anonyme
  // ============================================================
  static Future<String> getOrCreateConversation({
    required String clientId,
    required String prestataireId,
    required String logementId,
    required String logementTitre,
    String? logementPhoto,
  }) async {
    // Cherche une conversation existante entre ces deux participants
    final existing = await _db
        .collection('conversations')
        .where('participants', arrayContains: clientId)
        .where('logement_id', isEqualTo: logementId)
        .get();

    for (final doc in existing.docs) {
      final participants = List<String>.from(doc['participants']);
      if (participants.contains(prestataireId)) {
        return doc.id;
      }
    }

    // Compte les conversations existantes du prestataire pour numéroter le contact
    final existingConvs = await _db
        .collection('conversations')
        .where('participants', arrayContains: prestataireId)
        .get();
    final contactNumber = existingConvs.docs.length + 1;

    // Génère le label du contact visiteur
    final contactLabel = clientId.startsWith('visiteur_')
        ? 'Contact $contactNumber'
        : null; // sera résolu depuis le profil Firebase Auth

    // Crée une nouvelle conversation
    final conv = await _db.collection('conversations').add({
      'participants': [clientId, prestataireId],
      'logement_id': logementId,
      'logement_titre': logementTitre,
      'logement_photo': logementPhoto,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$clientId': 0,
      'unread_$prestataireId': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'contact_number': contactNumber,        // numéro séquentiel
      if (contactLabel != null) 'contact_label': contactLabel, // "Contact N"
    });

    return conv.id;
  }

  // ============================================================
  // Stream des conversations d'un utilisateur
  // Tri côté client pour éviter l'index composite Firestore
  // ============================================================
  static Stream<QuerySnapshot> getConversations(String uid) {
    return _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        // Pas d'orderBy → pas d'index composite requis
        // Le tri par date est fait côté client dans le StreamBuilder
        .snapshots();
  }

  // ============================================================
  // Stream des messages d'une conversation (temps réel)
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
  // La Cloud Function sendChatNotification se déclenche
  // automatiquement sur la création du document message.
  // ============================================================
  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
    required String recipientId,
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
    });

    final convRef = _db.collection('conversations').doc(conversationId);
    batch.update(convRef, {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$recipientId': FieldValue.increment(1),
    });

    await batch.commit();

    // ── Notification locale foreground pour le destinataire ──
    // (la Cloud Function gère le push en background/terminated)
    try {
      final senderUser = AuthService.instance.currentUser;
      final senderName = senderUser != null
          ? '${senderUser.prenom} ${senderUser.nom}'.trim()
          : 'Visiteur';

      // Récupère le titre du logement depuis la conversation
      final convData = (await _db.collection('conversations').doc(conversationId).get()).data();
      final logementTitre = convData?['logement_titre'] as String? ?? '';

      await NotificationService.showMessageNotification(
        senderName: senderName.isEmpty ? 'Visiteur' : senderName,
        messageText: text,
        conversationId: conversationId,
        logementTitre: logementTitre,
      );
    } catch (_) {
      // Non bloquant
    }
    // ✅ Cloud Function sendChatNotification gère le push distant.
  }

  // ============================================================
  // Envoyer une image
  // ============================================================
  static Future<void> sendImage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required File imageFile,
  }) async {
    final ref = _storage.ref().child(
        'messages/$conversationId/${DateTime.now().millisecondsSinceEpoch}.jpg');

    final task = await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final imageUrl = await task.ref.getDownloadURL();

    final batch = _db.batch();

    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId': senderId,
      'imageUrl': imageUrl,
      'type': 'image',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    final convRef = _db.collection('conversations').doc(conversationId);
    batch.update(convRef, {
      'lastMessage': '📷 Photo',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$recipientId': FieldValue.increment(1),
    });

    await batch.commit();
  }

  // ============================================================
  // Envoyer un fichier (PDF, doc...)
  // ============================================================
  static Future<void> sendFile({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required File file,
    required String fileName,
  }) async {
    final ref = _storage
        .ref()
        .child('messages/$conversationId/files/$fileName');

    final task = await ref.putFile(file);
    final fileUrl = await task.ref.getDownloadURL();

    final batch = _db.batch();

    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId': senderId,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'type': 'file',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    final convRef = _db.collection('conversations').doc(conversationId);
    batch.update(convRef, {
      'lastMessage': '📎 $fileName',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$recipientId': FieldValue.increment(1),
    });

    await batch.commit();
  }

  // ============================================================
  // Marquer les messages comme lus + réinitialiser compteur
  // ============================================================
  static Future<void> markAsRead(
      String conversationId, String userId) async {
    // Remet le compteur non-lus à 0
    await _db.collection('conversations').doc(conversationId).update({
      'unread_$userId': 0,
    });

    // Marque les messages individuels comme lus
    final unreadMessages = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .where('senderId', isNotEqualTo: userId)
        .get();

    if (unreadMessages.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}