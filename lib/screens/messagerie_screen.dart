// ============================================================
// FICHIER : lib/screens/messagerie_screen.dart
//
// RÈGLE FONDAMENTALE — UN SEUL UID ACTIF À LA FOIS
// ─────────────────────────────────────────────────
// • Connecté (prestataire)  → UID = Auth UID UNIQUEMENT
// • Non connecté (visiteur) → UID = visiteur_uid UNIQUEMENT
//
// Les deux modes sont mutuellement exclusifs.
// getAllMyUids() retourne exactement UN seul UID selon l'état.
// Jamais les deux en même temps → pas de confusion de boîtes.
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/messagerie_service.dart';
import '../services/analytics_service.dart';
import '../services/logement_service.dart';

// ─── UID visiteur persisté ────────────────────────────────────
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

// ─── UID actif selon l'état de connexion ─────────────────────
// Connecté   → Auth UID seul
// Déconnecté → visiteur_uid seul
// JAMAIS les deux ensemble
Future<String> resolveCurrentUid() async {
  final auth = AuthService.instance;
  if (auth.isLoggedIn) return auth.currentUser!.id;
  return getOrCreateVisitorId();
}

// ─── Liste d'UIDs pour isMe ───────────────────────────────────
// Retourne UN SEUL UID selon l'état de connexion.
// Si connecté  → [Auth UID]      (ignore le visiteur_uid)
// Si déconnecté → [visiteur_uid] (ignore tout Auth UID)
Future<List<String>> getAllMyUids() async {
  final auth = AuthService.instance;
  if (auth.isLoggedIn) {
    // Prestataire connecté : UNIQUEMENT son Auth UID
    return [auth.currentUser!.id];
  }
  // Visiteur anonyme : UNIQUEMENT son visiteur_uid
  final visitorUid = await getOrCreateVisitorId();
  return [visitorUid];
}

// ============================================================
// LISTE DES CONVERSATIONS
// ============================================================
class MessagerieScreen extends StatefulWidget {
  final String? forceUid;
  const MessagerieScreen({super.key, this.forceUid});

  @override
  State<MessagerieScreen> createState() => _MessagerieScreenState();
}

class _MessagerieScreenState extends State<MessagerieScreen> {
  String? _uid;
  bool _isPrestataire = false;

  @override
  void initState() {
    super.initState();
    _initUid();
  }

  Future<void> _initUid() async {
    if (widget.forceUid != null) {
      setState(() {
        _uid = widget.forceUid;
        _isPrestataire = AuthService.instance.isLoggedIn;
      });
      return;
    }
    final uid = await resolveCurrentUid();
    if (mounted) {
      setState(() {
        _uid = uid;
        _isPrestataire = AuthService.instance.isLoggedIn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('messages_title')),
        actions: [
          if (_uid != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(
                  _isPrestataire ? l.t('role_prestataire') : l.t('role_visiteur'),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
                backgroundColor: _isPrestataire
                    ? AppColors.primary
                    : AppColors.success,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
      body: _uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: MessagerieService.getConversations(_uid!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off_outlined,
                            size: 48, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text(l.t('messages_error'),
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: context.appTextSecondary)),
                      ]),
                    ),
                  );
                }

                final docs = List.from(snapshot.data?.docs ?? []);
                final now = DateTime.now();
                bool urgenceActive(dynamic doc) {
                  final u = (doc.data() as Map)['urgenceUntil'] as Timestamp?;
                  return u != null && u.toDate().isAfter(now);
                }

                docs.sort((a, b) {
                  // Urgences actives en tête.
                  final ua = urgenceActive(a);
                  final ub = urgenceActive(b);
                  if (ua && !ub) return -1;
                  if (!ua && ub) return 1;
                  // Sinon : date du dernier message décroissante.
                  final tA =
                      (a.data() as Map)['lastMessageTime'] as Timestamp?;
                  final tB =
                      (b.data() as Map)['lastMessageTime'] as Timestamp?;
                  if (tA == null && tB == null) return 0;
                  if (tA == null) return 1;
                  if (tB == null) return -1;
                  return tB.compareTo(tA);
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(l.t('messages_empty'), style: AppTextStyles.h3),
                        const SizedBox(height: 8),
                        Text(
                          _isPrestataire
                              ? l.t('messages_empty_prestataire')
                              : l.t('messages_empty_desc'),
                          style: TextStyle(
                              color: context.appTextSecondary),
                          textAlign: TextAlign.center,
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

                    // Résolution otherId : champs explicites ou fallback participants[]
                    final clientUid =
                        data['client_uid'] as String? ?? '';
                    final prestataireUid =
                        data['prestataire_uid'] as String? ?? '';

                    String otherId;
                    if (clientUid.isNotEmpty &&
                        prestataireUid.isNotEmpty) {
                      otherId = _uid == clientUid
                          ? prestataireUid
                          : clientUid;
                    } else {
                      final parts = List<String>.from(
                          data['participants'] ?? []);
                      otherId = parts.firstWhere(
                          (p) => p != _uid!,
                          orElse: () => '');
                    }

                    final isOtherVisitor =
                        otherId.startsWith('visiteur_');
                    final contactLabel =
                        data['contact_label'] as String?;

                    final urgenceUntilTs =
                        data['urgenceUntil'] as Timestamp?;
                    final estUrgent = urgenceUntilTs != null &&
                        urgenceUntilTs.toDate().isAfter(now);

                    return _ConversationTile(
                      conversationId: convId,
                      logementTitre:
                          data['logement_titre'] ?? 'Logement',
                      logementPhoto: data['logement_photo'],
                      otherId: otherId,
                      contactLabel: contactLabel,
                      isOtherVisitor: isOtherVisitor,
                      lastMessage: data['lastMessage'] ?? '',
                      lastMessageTime:
                          (data['lastMessageTime'] as Timestamp?)
                              ?.toDate(),
                      nbNonLus: unread,
                      currentUid: _uid!,
                      isCurrentUserPrestataire: _isPrestataire,
                      urgenceUntil: urgenceUntilTs?.toDate(),
                      estUrgent: estUrgent,
                      onTap: () async {
                        // UID unique selon mode courant
                        final myUids = await getAllMyUids();
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              conversationId: convId,
                              logementTitre:
                                  data['logement_titre'] ??
                                      'Logement',
                              logementPhoto:
                                  data['logement_photo'],
                              otherId: otherId,
                              currentUid: _uid!,
                              myUids: myUids,
                              contactLabel: contactLabel,
                              isOtherVisitor: isOtherVisitor,
                              isCurrentUserPrestataire:
                                  _isPrestataire,
                            ),
                          ),
                        );
                      },
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
  final String? contactLabel;
  final bool isOtherVisitor;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int nbNonLus;
  final String currentUid;
  final bool isCurrentUserPrestataire;
  final VoidCallback onTap;
  final DateTime? urgenceUntil;
  final bool estUrgent;

  const _ConversationTile({
    required this.conversationId,
    required this.logementTitre,
    required this.otherId,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.nbNonLus,
    required this.currentUid,
    required this.onTap,
    required this.isOtherVisitor,
    required this.isCurrentUserPrestataire,
    this.logementPhoto,
    this.contactLabel,
    this.urgenceUntil,
    this.estUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = nbNonLus > 0;

    if (isOtherVisitor) {
      final name = contactLabel ?? 'Visiteur';
      return _buildTile(context, name, null, hasUnread);
    }

    // Guard contre otherId vide
    if (otherId.isEmpty) {
      return _buildTile(context, 'Inconnu', null, hasUnread);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(otherId)
          .get(),
      builder: (context, snap) {
        String name = 'Prestataire';
        String? photoUrl;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final n =
              '${d['prenom'] ?? ''} ${d['nom'] ?? ''}'.trim();
          if (n.isNotEmpty) name = n;
          photoUrl = d['photoUrl'] as String?;
        }
        return _buildTile(context, name, photoUrl, hasUnread);
      },
    );
  }

  Widget _buildTile(BuildContext context, String name,
      String? photoUrl, bool hasUnread) {
    return Container(
      // Surlignage rouge pâle pour les conversations en urgence.
      color: estUrgent
          ? AppColors.error.withValues(alpha: 0.07)
          : Colors.transparent,
      child: ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: isOtherVisitor
                ? AppColors.success.withValues(alpha: 0.15)
                : context.appPrimaryLight,
            backgroundImage:
                photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: isOtherVisitor
                            ? AppColors.success
                            : AppColors.primary,
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
                  child: Text(nbNonLus.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
      title: Row(children: [
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight:
                      hasUnread ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 15)),
        ),
        if (estUrgent) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt, color: Colors.white, size: 11),
              SizedBox(width: 2),
              Text('URGENT 48h',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
        ],
      ]),
      subtitle: Text(lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: hasUnread
                ? context.appTextPrimary
                : context.appTextSecondary,
            fontWeight:
                hasUnread ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          )),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            lastMessageTime != null ? _fmt(lastMessageTime!) : '',
            style: TextStyle(
                fontSize: 11,
                color: hasUnread
                    ? AppColors.primary
                    : AppColors.textHint),
          ),
          const SizedBox(height: 4),
          Text(logementTitre,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
      ),
    );
  }

  String _fmt(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(date).inDays == 1) {
      return 'Hier';
    }
    return '${date.day}/${date.month}';
  }
}

// ============================================================
// ÉCRAN CHAT
// ============================================================
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String logementTitre;
  final String? logementPhoto;
  final String otherId;
  final String currentUid;
  final List<String> myUids;
  final String? contactLabel;
  final bool isOtherVisitor;
  final bool isCurrentUserPrestataire;
  final String? logementId; // [ANALYTICS] nouveau

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.logementTitre,
    required this.otherId,
    required this.currentUid,
    this.myUids = const [],
    this.logementPhoto,
    this.contactLabel,
    this.isOtherVisitor = false,
    this.isCurrentUserPrestataire = false,
    this.logementId, // [ANALYTICS] optionnel
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isUploading = false;
  late List<String> _myUids;
  ReplyTo? _pendingReply;
  String? _editingMessageId;
  String? _editingOriginalText;

  @override
  void initState() {
    super.initState();
    // UN SEUL UID actif selon mode connexion
    _myUids = widget.myUids.isNotEmpty
        ? widget.myUids
        : [widget.currentUid];
    _refreshMyUids();
    MessagerieService.markAsRead(
        widget.conversationId, widget.currentUid);
  }

  Future<void> _refreshMyUids() async {
    // Recharge les UIDs — retourne toujours UN seul UID
    final uids = await getAllMyUids();
    if (mounted) setState(() => _myUids = uids);
  }

  // isMe : vrai seulement si senderId == l'UID actif courant
  bool _isMe(String senderId) => _myUids.contains(senderId);

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

  void _setReply(ReplyTo reply) => setState(() => _pendingReply = reply);
  void _clearReply() => setState(() => _pendingReply = null);

  void _startEditing(String messageId, String text) {
    setState(() {
      _editingMessageId = messageId;
      _editingOriginalText = text;
      _pendingReply = null;
    });
    _msgController.text = text;
    _msgController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length));
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
    });
    _msgController.clear();
  }

  Future<void> _envoyerMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    // Mode édition
    if (_editingMessageId != null) {
      final messageId = _editingMessageId!;
      _cancelEditing();
      await MessagerieService.editMessage(
        conversationId: widget.conversationId,
        messageId: messageId,
        newText: text,
      );
      return;
    }

    final replyTo = _pendingReply;
    _clearReply();

    // [ANALYTICS] Détecter le 1er message de la conversation
    // On vérifie AVANT l'envoi si la collection messages est vide.
    // Seuls les visiteurs (non-prestataires) génèrent le lead.
    if (!widget.isCurrentUserPrestataire) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) {
          // C'est bien le tout premier message : on logue generate_lead
          AnalyticsService.instance.logContactPrestataire(
            widget.logementId ?? widget.conversationId,
            widget.otherId,
          );
          // Incrémente le compteur `contacts` du logement → alimente le
          // taux de conversion et les graphiques du dashboard prestataire.
          if (widget.logementId != null && widget.logementId!.isNotEmpty) {
            LogementService.incrementContacts(widget.logementId!);
          }
        }
      } catch (_) {
        // Non bloquant — analytics silencieuse
      }
    }

    await MessagerieService.sendMessage(
      conversationId: widget.conversationId,
      senderId: widget.currentUid,
      text: text,
      recipientId: widget.otherId,
      replyTo: replyTo,
    );
    _scrollToBottom();
  }

  Future<void> _envoyerPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      await MessagerieService.sendImage(
        conversationId: widget.conversationId,
        senderId: widget.currentUid,
        recipientId: widget.otherId,
        imageFile: File(picked.path),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur envoi photo : $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _envoyerVideo() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      await MessagerieService.sendVideo(
        conversationId: widget.conversationId,
        senderId: widget.currentUid,
        recipientId: widget.otherId,
        videoFile: File(picked.path),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur envoi vidéo : $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _envoyerDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'png', 'jpg'
      ],
    );
    if (result == null || result.files.single.path == null) {
      return;
    }
    if (!mounted) return;
    final file = result.files.single;
    setState(() => _isUploading = true);
    try {
      await MessagerieService.sendFile(
        conversationId: widget.conversationId,
        senderId: widget.currentUid,
        recipientId: widget.otherId,
        file: File(file.path!),
        fileName: file.name,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur envoi fichier : $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _supprimerConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_forever_rounded,
              color: AppColors.error, size: 24),
          SizedBox(width: 8),
          Expanded(child: Text('Supprimer la conversation')),
        ]),
        content: const Text(
          'Cette conversation sera définitivement supprimée pour vous et votre interlocuteur.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await MessagerieService.deleteConversation(
          widget.conversationId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Conversation supprimée')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  void _showMessageOptions({
    required String messageId,
    required String text,
    required String type,
    required DateTime timestamp,
  }) {
    final age = DateTime.now().difference(timestamp);
    final withinWindow = age < const Duration(minutes: 2);
    final canEdit = withinWindow && type == 'text';
    final canDelete = withinWindow;

    if (!canEdit && !canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Modification impossible après 2 minutes'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppColors.primary),
                title: const Text('Modifier'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startEditing(messageId, text);
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Colors.red.shade700),
                title: Text('Supprimer',
                    style: TextStyle(color: Colors.red.shade700)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await MessagerieService.deleteMessage(
                    conversationId: widget.conversationId,
                    messageId: messageId,
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    if (widget.isOtherVisitor) {
      return _AppBarTitleContent(
          name: widget.contactLabel ?? 'Visiteur',
          logementTitre: widget.logementTitre,
          isVisitor: true);
    }
    if (widget.otherId.isEmpty) {
      return _AppBarTitleContent(
          name: 'Inconnu',
          logementTitre: widget.logementTitre,
          isVisitor: false);
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherId)
          .get(),
      builder: (context, snap) {
        String name = 'Prestataire';
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final n =
              '${d['prenom'] ?? ''} ${d['nom'] ?? ''}'.trim();
          if (n.isNotEmpty) name = n;
        }
        return _AppBarTitleContent(
            name: name,
            logementTitre: widget.logementTitre,
            isVisitor: false);
      },
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
        title: _buildAppBarTitle(),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: widget.isCurrentUserPrestataire
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppColors.success.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.isCurrentUserPrestataire
                  ? 'Prestataire'
                  : 'Visiteur',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 26),
            tooltip: 'Supprimer la conversation',
            onPressed: _supprimerConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          _LogementHeader(
              logementTitre: widget.logementTitre,
              logementPhoto: widget.logementPhoto),
          if (_isUploading)
            Container(
              color: context.appPrimaryLight,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: const Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary)),
                SizedBox(width: 10),
                Text('Envoi en cours...',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: MessagerieService.getMessages(
                  widget.conversationId),
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

                    // ── isMe : UN seul UID actif ──────────
                    final isMe = _isMe(senderId);

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
                          ((docs[i - 1].data()
                                      as Map<String, dynamic>)[
                                  'timestamp'] is Timestamp)
                              ? ((docs[i - 1].data()
                                      as Map<String, dynamic>)[
                                      'timestamp'] as Timestamp)
                                  .toDate()
                              : DateTime.now(),
                          timestamp,
                        );

                    final replyRaw = data['replyTo']
                        as Map<String, dynamic>?;
                    final replyTo = replyRaw != null
                        ? ReplyTo.fromMap(replyRaw)
                        : null;

                    final deleted =
                        data['deleted'] as bool? ?? false;
                    final edited =
                        data['edited'] as bool? ?? false;
                    final text =
                        data['text'] as String? ?? '';
                    final extrait = text.length > 60
                        ? '${text.substring(0, 60)}…'
                        : text;

                    return Column(
                      children: [
                        if (showDate)
                          _DateSeparator(date: timestamp),
                        GestureDetector(
                          onHorizontalDragEnd: (details) {
                            if (deleted) return;
                            final v = details.primaryVelocity ?? 0;
                            if ((!isMe && v > 250) ||
                                (isMe && v < -250)) {
                              _setReply(ReplyTo(
                                messageId: docs[i].id,
                                extrait: extrait.isNotEmpty
                                    ? extrait
                                    : '📎 Pièce jointe',
                                senderId: senderId,
                              ));
                            }
                          },
                          onLongPress: isMe && !deleted
                              ? () => _showMessageOptions(
                                    messageId: docs[i].id,
                                    text: text,
                                    type: type,
                                    timestamp: timestamp,
                                  )
                              : null,
                          child: _MessageBubble(
                            text: text,
                            imageUrl:
                                data['imageUrl'] as String?,
                            videoUrl:
                                data['videoUrl'] as String?,
                            fileUrl:
                                data['fileUrl'] as String?,
                            fileName:
                                data['fileName'] as String?,
                            type: type,
                            isMe: isMe,
                            timestamp: timestamp,
                            isRead: isRead,
                            replyTo: replyTo,
                            deleted: deleted,
                            edited: edited,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_editingMessageId != null)
            _EditBanner(
                originalText: _editingOriginalText ?? '',
                onClose: _cancelEditing),
          if (_pendingReply != null)
            _ReplyBanner(
                reply: _pendingReply!, onClose: _clearReply),
          _SaisieBar(
            controller: _msgController,
            onSend: _envoyerMessage,
            onPhoto: _envoyerPhoto,
            onVideo: _envoyerVideo,
            onDocument: _envoyerDocument,
            isUploading: _isUploading,
            isPrestataire: widget.isCurrentUserPrestataire,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;
}

// ─── Titre AppBar ─────────────────────────────────────────────
class _AppBarTitleContent extends StatelessWidget {
  final String name;
  final String logementTitre;
  final bool isVisitor;
  const _AppBarTitleContent(
      {required this.name,
      required this.logementTitre,
      required this.isVisitor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: isVisitor
              ? AppColors.success.withValues(alpha: 0.3)
              : context.appPrimaryLight,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                color: isVisitor
                    ? AppColors.success
                    : AppColors.primary,
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
              Text(logementTitre,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// EN-TÊTE LOGEMENT
// ============================================================
class _LogementHeader extends StatelessWidget {
  final String logementTitre;
  final String? logementPhoto;
  const _LogementHeader(
      {required this.logementTitre, this.logementPhoto});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 8),
        color: context.appPrimaryLight,
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
                      color: AppColors.primary
                          .withValues(alpha: 0.2),
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
  final String? videoUrl;
  final String? fileUrl;
  final String? fileName;
  final String type;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final ReplyTo? replyTo;
  final bool deleted;
  final bool edited;

  const _MessageBubble({
    required this.text,
    required this.type,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    this.imageUrl,
    this.videoUrl,
    this.fileUrl,
    this.fileName,
    this.replyTo,
    this.deleted = false,
    this.edited = false,
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Impossible d'ouvrir le fichier")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Message supprimé
    if (deleted) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.primary.withValues(alpha: 0.35)
                : (Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkCard
                    : Colors.grey.shade100),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block,
                  size: 13,
                  color: isMe ? Colors.white54 : AppColors.textHint),
              const SizedBox(width: 6),
              Text(
                'Message supprimé',
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color:
                        isMe ? Colors.white54 : AppColors.textHint),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment:
          isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
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
            // Encart citation (réponse)
            if (replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.primary
                          .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(
                      color: isMe
                          ? Colors.white
                          : AppColors.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  replyTo!.extrait,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isMe
                        ? Colors.white70
                        : AppColors.textHint,
                  ),
                ),
              ),
            if (type == 'image' && imageUrl != null)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _MediaViewerPage(imageUrl: imageUrl!),
                )),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(imageUrl!,
                      width: 200,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, prog) =>
                          prog == null
                              ? child
                              : const SizedBox(
                                  width: 200,
                                  height: 120,
                                  child: Center(
                                      child:
                                          CircularProgressIndicator()))),
                ),
              )
            else if (type == 'video' && videoUrl != null)
              _VideoMessageWidget(videoUrl: videoUrl!, isMe: isMe)
            else if (type == 'file' && fileName != null)
              GestureDetector(
                onTap: fileUrl != null
                    ? () => _openUrl(context, fileUrl!)
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file,
                        color: isMe
                            ? Colors.white70
                            : AppColors.primary,
                        size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(fileName!,
                          style: TextStyle(
                              color: isMe
                                  ? Colors.white
                                  : context.appTextPrimary,
                              fontSize: 13,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                  ],
                ),
              )
            else
              Text(text,
                  style: TextStyle(
                      color: isMe
                          ? Colors.white
                          : context.appTextPrimary,
                      fontSize: 14)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: isMe
                          ? Colors.white70
                          : AppColors.textHint,
                      fontSize: 10),
                ),
                if (edited) ...[
                  const SizedBox(width: 4),
                  Text('modifié',
                      style: TextStyle(
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                          color: isMe
                              ? Colors.white54
                              : AppColors.textHint)),
                ],
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(isRead ? Icons.done_all : Icons.done,
                      size: 14,
                      color: isRead
                          ? const Color(0xFF4ADE80)
                          : Colors.white60),
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
// BANNIÈRE DE RÉPONSE (au-dessus de la barre de saisie)
// ============================================================
class _ReplyBanner extends StatelessWidget {
  final ReplyTo reply;
  final VoidCallback onClose;
  const _ReplyBanner({required this.reply, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.appPrimaryLight,
      child: Row(
        children: [
          Container(
              width: 3,
              height: 36,
              color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Répondre à',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                Text(
                  reply.extrait,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BANNIÈRE D'ÉDITION (au-dessus de la barre de saisie)
// ============================================================
class _EditBanner extends StatelessWidget {
  final String originalText;
  final VoidCallback onClose;
  const _EditBanner({required this.originalText, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  Icon(Icons.edit, size: 12, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('Modification',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ]),
                Text(
                  originalText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VIGNETTE VIDÉO — affiche le 1er frame, tap → plein écran
// ============================================================
class _VideoMessageWidget extends StatefulWidget {
  final String videoUrl;
  final bool isMe;
  const _VideoMessageWidget({required this.videoUrl, required this.isMe});

  @override
  State<_VideoMessageWidget> createState() => _VideoMessageWidgetState();
}

class _VideoMessageWidgetState extends State<_VideoMessageWidget> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final ctrl =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.seekTo(Duration.zero);
      await ctrl.pause();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // URL invalide ou réseau — on garde l'état _ready=false
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _MediaViewerPage(videoUrl: widget.videoUrl),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 200,
          height: 120,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && _ctrl != null)
                VideoPlayer(_ctrl!)
              else
                Container(color: Colors.black45,
                    child: const Center(
                      child: SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                    )),
              // Voile léger pour lisibilité des icônes
              Container(color: Colors.black.withValues(alpha: 0.25)),
              const Center(
                child: Icon(Icons.play_circle_fill,
                    color: Colors.white, size: 48),
              ),
              Positioned(
                bottom: 6, right: 6,
                child: Icon(Icons.fullscreen,
                    color: Colors.white.withValues(alpha: 0.8), size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// VISIONNEUSE PLEIN ÉCRAN — photos & vidéos
// ============================================================
class _MediaViewerPage extends StatefulWidget {
  final String? imageUrl;
  final String? videoUrl;
  const _MediaViewerPage({this.imageUrl, this.videoUrl});

  @override
  State<_MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<_MediaViewerPage> {
  VideoPlayerController? _ctrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.videoUrl != null) {
      _ctrl =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
            ..initialize().then((_) {
              if (mounted) {
                setState(() => _videoReady = true);
                _ctrl!.play();
              }
            });
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: widget.imageUrl != null
                ? PhotoView(
                    imageProvider: NetworkImage(widget.imageUrl!),
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    loadingBuilder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white)),
                  )
                : _buildVideo(),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideo() {
    if (!_videoReady || _ctrl == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: _ctrl!.value.aspectRatio,
          child: VideoPlayer(_ctrl!),
        ),
        VideoProgressIndicator(
          _ctrl!,
          allowScrubbing: true,
          colors:
              const VideoProgressColors(playedColor: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _ctrl!,
          builder: (_, value, __) => IconButton(
            icon: Icon(
                value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 36),
            onPressed: () =>
                value.isPlaying ? _ctrl!.pause() : _ctrl!.play(),
          ),
        ),
      ],
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12),
            child:
                Text(label, style: AppTextStyles.caption),
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
  final VoidCallback? onPhoto;
  final VoidCallback? onVideo;
  final VoidCallback? onDocument;
  final bool isUploading;
  final bool isPrestataire;

  const _SaisieBar({
    required this.controller,
    required this.onSend,
    required this.isPrestataire,
    this.onPhoto,
    this.onVideo,
    this.onDocument,
    this.isUploading = false,
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
          // Boutons média : prestataire uniquement
          if (isPrestataire) ...[
            IconButton(
              icon: Icon(Icons.photo_camera_outlined,
                  color: context.appTextSecondary),
              onPressed: isUploading ? null : onPhoto,
            ),
            IconButton(
              icon: Icon(Icons.videocam_outlined,
                  color: context.appTextSecondary),
              onPressed: isUploading ? null : onVideo,
            ),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Écrire un message...',
                filled: true,
                fillColor: Theme.of(context).brightness ==
                        Brightness.dark
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
            onTap: isUploading ? null : onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: isUploading
                      ? AppColors.textHint
                      : AppColors.primary,
                  shape: BoxShape.circle),
              child: const Icon(Icons.send,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
