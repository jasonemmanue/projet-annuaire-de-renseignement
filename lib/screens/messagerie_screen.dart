import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

// ============================================================
// FICHIER : lib/screens/messagerie_screen.dart
// Écran 5 - Messagerie / Chat (§4.1.5)
// Liste des conversations + Chat individuel style WhatsApp
// Textes, photos, documents, indicateur lu/non lu, notifs push
// ============================================================

// ─── LISTE DES CONVERSATIONS ─────────────────────────────────

class MessagerieScreen extends StatelessWidget {
  const MessagerieScreen({super.key});

  // Mock conversations
  List<Conversation> get _conversations => [
    Conversation(
      id: 'conv_1', logementId: '1', logementTitre: 'Studio à Bastos',
      logementPhoto: 'https://picsum.photos/seed/l1/100/100',
      prestatireId: 'p1', prestatireNom: 'Jean Dupont',
      dernierMessage: Message(id: 'm1', conversationId: 'conv_1', expediteurId: 'p1',
          texte: 'Bonjour, le studio est toujours disponible.', dateEnvoi: DateTime.now().subtract(const Duration(minutes: 5)), estLu: false, type: 'texte'),
      nbNonLus: 2, dateDernierMessage: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    Conversation(
      id: 'conv_2', logementId: '2', logementTitre: 'Villa F4 Bonanjo',
      logementPhoto: 'https://picsum.photos/seed/l2/100/100',
      prestatireId: 'p2', prestatireNom: 'Marie Bello',
      dernierMessage: Message(id: 'm2', conversationId: 'conv_2', expediteurId: 'client',
          texte: 'Merci pour les informations !', dateEnvoi: DateTime.now().subtract(const Duration(hours: 2)), estLu: true, type: 'texte'),
      nbNonLus: 0, dateDernierMessage: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Conversation(
      id: 'conv_3', logementId: '3', logementTitre: 'Appartement F2 Akwa',
      prestatireId: 'p3', prestatireNom: 'Paul Ngono',
      dernierMessage: Message(id: 'm3', conversationId: 'conv_3', expediteurId: 'p3',
          texte: 'Je vous envoie les photos.', dateEnvoi: DateTime.now().subtract(const Duration(days: 1)), estLu: true, type: 'texte'),
      nbNonLus: 0, dateDernierMessage: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: _conversations.isEmpty
          ? const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text('Aucun message', style: AppTextStyles.h3),
            SizedBox(height: 8),
            Text('Contactez un prestataire depuis une annonce', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      )
          : ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
        itemBuilder: (_, i) => _ConversationTile(
          conversation: _conversations[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(conversation: _conversations[i])),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// TUILE CONVERSATION
// ----------------------------------------------------------
class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.nbNonLus > 0;
    final dernierMsg = conversation.dernierMessage;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: conversation.prestatirePhoto != null
                ? NetworkImage(conversation.prestatirePhoto!)
                : null,
            child: conversation.prestatirePhoto == null
                ? Text(
              conversation.prestatireNom[0],
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 20),
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
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    conversation.nbNonLus.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        conversation.prestatireNom,
        style: AppTextStyles.bodyLarge.copyWith(fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversation.logementTitre,
            style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (dernierMsg?.expediteurId == 'client') ...[
                Icon(
                  dernierMsg!.estLu ? Icons.done_all : Icons.done,
                  size: 14,
                  color: dernierMsg.estLu ? AppColors.primary : AppColors.textHint,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  dernierMsg?.texte ?? '',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                    color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: Text(
        _formatDate(conversation.dateDernierMessage),
        style: AppTextStyles.caption.copyWith(
          color: hasUnread ? AppColors.primary : AppColors.textHint,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}j';
    return '${date.day}/${date.month}';
  }
}

// ─── ÉCRAN CHAT INDIVIDUEL ────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _chargerMessages();
  }

  void _chargerMessages() {
    // Mock messages (à remplacer par Firebase Realtime DB / Stream.io - §7.2)
    setState(() {
      _messages.addAll([
        Message(id: 'm1', conversationId: widget.conversation.id, expediteurId: 'client',
            texte: 'Bonjour, est-ce que le logement est toujours disponible ?',
            dateEnvoi: DateTime.now().subtract(const Duration(hours: 2)), estLu: true, type: 'texte'),
        Message(id: 'm2', conversationId: widget.conversation.id, expediteurId: widget.conversation.prestatireId,
            texte: 'Bonjour ! Oui, tout à fait disponible. À partir de quand souhaiteriez-vous emménager ?',
            dateEnvoi: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)), estLu: true, type: 'texte'),
        Message(id: 'm3', conversationId: widget.conversation.id, expediteurId: 'client',
            texte: 'Idéalement dès le 1er du mois prochain. Est-ce qu\'il y a possibilité de visiter ?',
            dateEnvoi: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)), estLu: true, type: 'texte'),
        Message(id: 'm4', conversationId: widget.conversation.id, expediteurId: widget.conversation.prestatireId,
            texte: 'Bien sûr ! Je suis disponible samedi matin. Votre numéro pour confirmer ?',
            dateEnvoi: DateTime.now().subtract(const Duration(minutes: 5)), estLu: false, type: 'texte'),
      ]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _envoyerMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: widget.conversation.id,
        expediteurId: 'client',
        texte: text,
        dateEnvoi: DateTime.now(),
        estLu: false,
        type: 'texte',
      ));
      _msgController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Simule indicateur "en train de taper" et réponse
    setState(() => _isTyping = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isTyping = false);
    });
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
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              child: Text(widget.conversation.prestatireNom[0],
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.conversation.prestatireNom,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                  Text(widget.conversation.logementTitre,
                      style: const TextStyle(fontSize: 11, color: Colors.white70), maxLines: 1),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // ─── EN-TÊTE LOGEMENT ──────────────────────────────
          _LogementHeader(conversation: widget.conversation),

          // ─── LISTE DES MESSAGES ────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (_isTyping && i == _messages.length) {
                  return _TypingIndicator(nom: widget.conversation.prestatireNom);
                }
                final msg = _messages[i];
                final isMe = msg.expediteurId == 'client';
                final showDate = i == 0 || !_sameDay(_messages[i - 1].dateEnvoi, msg.dateEnvoi);

                return Column(
                  children: [
                    if (showDate) _DateSeparator(date: msg.dateEnvoi),
                    _MessageBubble(message: msg, isMe: isMe),
                  ],
                );
              },
            ),
          ),

          // ─── BARRE DE SAISIE ───────────────────────────────
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

  void _envoyerPhoto() {
    // TODO: Intégrer image_picker (§4.1.5 - envoi photos)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sélection photo bientôt disponible')),
    );
  }

  void _envoyerDocument() {
    // TODO: Intégrer file_picker (§4.1.5 - envoi documents)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sélection document bientôt disponible')),
    );
  }
}

// ----------------------------------------------------------
// EN-TÊTE LOGEMENT dans le chat
// ----------------------------------------------------------
class _LogementHeader extends StatelessWidget {
  final Conversation conversation;
  const _LogementHeader({required this.conversation});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: AppColors.primaryLight,
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: conversation.logementPhoto != null
              ? Image.network(conversation.logementPhoto!, width: 40, height: 40, fit: BoxFit.cover)
              : Container(width: 40, height: 40, color: AppColors.primary.withOpacity(0.2),
              child: const Icon(Icons.home, color: AppColors.primary, size: 20)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(conversation.logementTitre,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Icon(Icons.open_in_new, color: AppColors.primary, size: 16),
      ],
    ),
  );
}

// ----------------------------------------------------------
// BULLE DE MESSAGE
// ----------------------------------------------------------
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.texte ?? '',
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
                  '${message.dateEnvoi.hour.toString().padLeft(2, '0')}:${message.dateEnvoi.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : AppColors.textHint,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.estLu ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.estLu ? Colors.white : Colors.white60,
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

// ----------------------------------------------------------
// SÉPARATEUR DE DATE
// ----------------------------------------------------------
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.day == now.day) {
      label = "Aujourd'hui";
    } else if (date.day == now.day - 1) {
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

// ----------------------------------------------------------
// INDICATEUR "EN TRAIN DE TAPER"
// ----------------------------------------------------------
class _TypingIndicator extends StatefulWidget {
  final String nom;
  const _TypingIndicator({required this.nom});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) => AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final offset = (((_ctrl.value * 3) - i).clamp(0.0, 1.0));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7, height: 7,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.4 + 0.6 * (1 - offset)),
                shape: BoxShape.circle,
              ),
            );
          },
        )),
      ),
    ),
  );
}

// ----------------------------------------------------------
// BARRE DE SAISIE
// ----------------------------------------------------------
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
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.white,
      child: Row(
        children: [
          // Bouton photo
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined, color: AppColors.textSecondary),
            onPressed: onPhoto,
          ),
          // Bouton document
          IconButton(
            icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
            onPressed: onDocument,
          ),
          // Champ texte
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Écrire un message...',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBackground
                    : AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Bouton envoyer
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}