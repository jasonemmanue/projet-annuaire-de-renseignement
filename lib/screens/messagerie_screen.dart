import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/messagerie_service.dart';

// ============================================================
// FICHIER : lib/screens/messagerie_screen.dart
// Messagerie temps réel – Firestore StreamBuilder
// Visiteur anonyme : UUID persisté en SharedPreferences
// Prestataire : UID Firebase Auth
// ============================================================

// ─── Identifiant visiteur persisté ───────────────────────────
Future<String> getOrCreateVisitorId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'visiteur_uid';
  String? uid = prefs.getString(key);
  if (uid == null) {
    uid = 'visiteur_${const Uuid().v4()}';
    await prefs.setString(key, uid);
  }
  return uid;
}

// ── Retourne "Visiteur XXXX" depuis l'UUID persisté ─────────
String _getVisitorLabel(String uid) {
  if (!uid.startsWith('visiteur_')) return uid;
  // Extraire les chiffres de l'UUID pour générer un numéro court unique
  final digits = uid.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 'Visiteur 1000';
  final shortNum = (int.parse(digits.substring(digits.length > 4 ? digits.length - 4 : 0)) % 9000 + 1000).toString();
  return 'Visiteur $shortNum';
}

// ============================================================
// LISTE DES CONVERSATIONS
// ============================================================
class MessagerieScreen extends StatefulWidget {
  /// Si fourni, cet UID est utilisé directement (ex: dashboard prestataire).
  /// Sinon, on détecte automatiquement visiteur ou connecté.
  final String? forceUid;
  const MessagerieScreen({super.key, this.forceUid});

  @override
  State<MessagerieScreen> createState() => _MessagerieScreenState();
}

class _MessagerieScreenState extends State<MessagerieScreen> {
  String? _uid;

  @override
  void initState() {
    super.initState();
    _initUid();
  }

  Future<void> _initUid() async {
    if (widget.forceUid != null) {
      if (mounted) setState(() => _uid = widget.forceUid);
      return;
    }
    final auth = AuthService.instance;
    final uid = auth.isLoggedIn
        ? auth.currentUser!.id
        : await getOrCreateVisitorId();
    if (mounted) setState(() => _uid = uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: _uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
        stream: MessagerieService.getConversations(_uid!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Gestion erreur (ex: index manquant)
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text('Impossible de charger les messages.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            );
          }

          // Tri côté client par date décroissante
          final docs = List.from(snapshot.data?.docs ?? []);
          docs.sort((a, b) {
            final tA = (a.data() as Map)['lastMessageTime'] as Timestamp?;
            final tB = (b.data() as Map)['lastMessageTime'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('Aucun message', style: AppTextStyles.h3),
                  SizedBox(height: 8),
                  Text(
                    'Contactez un prestataire depuis une annonce',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 80),
            itemBuilder: (_, i) {
              final data =
              docs[i].data() as Map<String, dynamic>;
              final convId = docs[i].id;
              final unread =
                  (data['unread_${_uid!}'] as int?) ?? 0;
              final participants =
              List<String>.from(data['participants'] ?? []);
              final otherId = participants
                  .firstWhere((p) => p != _uid!, orElse: () => '');
              // Récupère le label "Contact N" stocké dans Firestore
              final contactLabel = data['contact_label'] as String?;

              return _ConversationTile(
                conversationId: convId,
                logementTitre:
                data['logement_titre'] ?? 'Logement',
                logementPhoto: data['logement_photo'],
                otherId: otherId,
                contactLabel: contactLabel,
                lastMessage: data['lastMessage'] ?? '',
                lastMessageTime:
                (data['lastMessageTime'] as Timestamp?)
                    ?.toDate(),
                nbNonLus: unread,
                currentUid: _uid!,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      conversationId: convId,
                      logementTitre:
                      data['logement_titre'] ?? 'Logement',
                      logementPhoto: data['logement_photo'],
                      otherId: otherId,
                      currentUid: _uid!,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// TUILE DE CONVERSATION
// ============================================================
class _ConversationTile extends StatelessWidget {
  final String conversationId;
  final String logementTitre;
  final String? logementPhoto;
  final String otherId;
  final String? contactLabel; // "Contact N" stocké dans Firestore
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int nbNonLus;
  final String currentUid;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversationId,
    required this.logementTitre,
    required this.otherId,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.nbNonLus,
    required this.currentUid,
    required this.onTap,
    this.logementPhoto,
    this.contactLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = nbNonLus > 0;

    return FutureBuilder<DocumentSnapshot?>(
      future: otherId.startsWith('visiteur_') || otherId.isEmpty
          ? Future.value(null)
          : FirebaseFirestore.instance
          .collection('users')
          .doc(otherId)
          .get(),
      builder: (context, snap) {
        final otherData = snap.data?.data() as Map<String, dynamic>?;
        // Priorité : label Firestore > nom Auth > fallback visiteur
        final otherName = contactLabel != null && otherId.startsWith('visiteur_')
            ? contactLabel!
            : otherId.startsWith('visiteur_')
                ? _getVisitorLabel(otherId)
                : otherData != null
                    ? '${otherData['prenom'] ?? ''} ${otherData['nom'] ?? ''}'.trim()
                    : '...';
        final otherPhoto = otherData?['photoUrl'] as String?;

        return ListTile(
          onTap: onTap,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: otherPhoto != null
                    ? NetworkImage(otherPhoto)
                    : null,
                child: otherPhoto == null
                    ? Text(
                  otherName.isNotEmpty
                      ? otherName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 20),
                )
                    : null,
              ),
              if (hasUnread)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        nbNonLus.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            otherName,
            style: TextStyle(
                fontWeight:
                hasUnread ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15),
          ),
          subtitle: Text(
            lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasUnread
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontWeight:
              hasUnread ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lastMessageTime != null
                    ? _formatTime(lastMessageTime!)
                    : '',
                style: TextStyle(
                    fontSize: 11,
                    color: hasUnread
                        ? AppColors.primary
                        : AppColors.textHint),
              ),
              const SizedBox(height: 4),
              Text(
                logementTitre,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textHint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(date).inDays == 1) {
      return 'Hier';
    } else {
      return '${date.day}/${date.month}';
    }
  }
}

// ============================================================
// ÉCRAN CHAT – temps réel Firestore
// ============================================================
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String logementTitre;
  final String? logementPhoto;
  final String otherId;
  final String currentUid;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.logementTitre,
    required this.otherId,
    required this.currentUid,
    this.logementPhoto,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Marquer comme lu à l'ouverture
    MessagerieService.markAsRead(widget.conversationId, widget.currentUid);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _envoyerMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    await MessagerieService.sendMessage(
      conversationId: widget.conversationId,
      senderId: widget.currentUid,
      text: text,
      recipientId: widget.otherId,
    );
    _scrollToBottom();
  }

  void _envoyerPhoto() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sélection photo bientôt disponible')),
    );
  }

  void _envoyerDocument() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Sélection document bientôt disponible')),
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: FutureBuilder<DocumentSnapshot?>(
          future: widget.otherId.startsWith('visiteur_') ||
              widget.otherId.isEmpty
              ? Future.value(null)
              : FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherId)
              .get(),
          builder: (context, snap) {
            final data =
            snap.data?.data() as Map<String, dynamic>?;
            final name = widget.otherId.startsWith('visiteur_')
                ? _getVisitorLabel(widget.otherId)
                : data != null
                ? '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'
                .trim()
                : '...';
            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      Text(widget.logementTitre,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70),
                          maxLines: 1),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          // En-tête logement
          _LogementHeader(
            logementTitre: widget.logementTitre,
            logementPhoto: widget.logementPhoto,
          ),

          // Messages en temps réel
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
              MessagerieService.getMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isNotEmpty) _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data =
                    docs[i].data() as Map<String, dynamic>;
                    final senderId =
                        data['senderId'] as String? ?? '';
                    final isMe = senderId == widget.currentUid;
                    final timestamp =
                        (data['timestamp'] as Timestamp?)
                            ?.toDate() ??
                            DateTime.now();
                    final isRead =
                        data['isRead'] as bool? ?? false;
                    final type =
                        data['type'] as String? ?? 'text';

                    final showDate = i == 0 ||
                        !_sameDay(
                          (docs[i - 1].data()
                          as Map<String, dynamic>)['timestamp']
                          is Timestamp
                              ? ((docs[i - 1].data()
                          as Map<String, dynamic>)[
                          'timestamp'] as Timestamp)
                              .toDate()
                              : DateTime.now(),
                          timestamp,
                        );

                    return Column(
                      children: [
                        if (showDate)
                          _DateSeparator(date: timestamp),
                        _MessageBubble(
                          text: data['text'] as String? ?? '',
                          imageUrl: data['imageUrl'] as String?,
                          fileName: data['fileName'] as String?,
                          type: type,
                          isMe: isMe,
                          timestamp: timestamp,
                          isRead: isRead,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Barre de saisie
          _SaisieBar(
            controller: _msgController,
            onSend: _envoyerMessage,
            onPhoto: _envoyerPhoto,
            onDocument: _envoyerDocument,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;
}

// ============================================================
// EN-TÊTE LOGEMENT dans le chat
// ============================================================
class _LogementHeader extends StatelessWidget {
  final String logementTitre;
  final String? logementPhoto;
  const _LogementHeader(
      {required this.logementTitre, this.logementPhoto});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: AppColors.primaryLight,
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: logementPhoto != null
              ? Image.network(logementPhoto!,
              width: 40, height: 40, fit: BoxFit.cover)
              : Container(
              width: 40,
              height: 40,
              color: AppColors.primary.withValues(alpha: 0.2),
              child: const Icon(Icons.home,
                  color: AppColors.primary, size: 20)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            logementTitre,
            style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// BULLE DE MESSAGE
// ============================================================
class _MessageBubble extends StatelessWidget {
  final String text;
  final String? imageUrl;
  final String? fileName;
  final String type;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;

  const _MessageBubble({
    required this.text,
    required this.type,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    this.imageUrl,
    this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary
              : (Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkCard
              : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (type == 'image' && imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl!,
                    width: 200, fit: BoxFit.cover),
              )
            else if (type == 'file' && fileName != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_file,
                      color:
                      isMe ? Colors.white70 : AppColors.primary,
                      size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(fileName!,
                        style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontSize: 13,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              )
            else
              Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: isMe ? Colors.white70 : AppColors.textHint,
                      fontSize: 10),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: isRead ? Colors.white : Colors.white60,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SÉPARATEUR DE DATE
// ============================================================
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      label = "Aujourd'hui";
    } else if (now.difference(date).inDays == 1) {
      label = 'Hier';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: AppTextStyles.caption),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

// ============================================================
// BARRE DE SAISIE
// ============================================================
class _SaisieBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onDocument;

  const _SaisieBar({
    required this.controller,
    required this.onSend,
    required this.onPhoto,
    required this.onDocument,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkCard
          : Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined,
                color: AppColors.textSecondary),
            onPressed: onPhoto,
          ),
          IconButton(
            icon: const Icon(Icons.attach_file,
                color: AppColors.textSecondary),
            onPressed: onDocument,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Écrire un message...',
                filled: true,
                fillColor:
                Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBackground
                    : AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}