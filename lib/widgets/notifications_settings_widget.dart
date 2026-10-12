// ============================================================
// FICHIER : lib/widgets/notifications_settings_widget.dart
//
// Réglages des notifications par catégorie, partagés entre le profil
// visiteur et l'espace prestataire. Chaque interrupteur est persisté
// (SharedPreferences) et appliqué par NotificationService.setCategory :
// topics FCM pour annonces/prix, préférence côté API pour messages,
// modération et fin de sponsorisation.
// ============================================================

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class NotifCategorie {
  final String cle;
  final IconData icone;
  final String titreKey;
  final String sousTitreKey;
  const NotifCategorie(this.cle, this.icone, this.titreKey, this.sousTitreKey);

  static const visiteur = [
    NotifCategorie(NotificationService.kNotifAnnonces, Icons.home_outlined,
        'profil_new_listings', 'profil_new_listings_sub'),
    NotifCategorie(NotificationService.kNotifMessages, Icons.chat_bubble_outline,
        'profil_messages_notif', 'profil_messages_notif_sub'),
    NotifCategorie(NotificationService.kNotifPrix, Icons.trending_down,
        'profil_price_alerts', 'profil_price_alerts_sub'),
  ];

  static const prestataire = [
    NotifCategorie(NotificationService.kNotifMessages, Icons.chat_bubble_outline,
        'prest_notif_messages', 'prest_notif_messages_sub'),
    NotifCategorie(NotificationService.kNotifPrestaModeration, Icons.verified_outlined,
        'prest_notif_moderation', 'prest_notif_moderation_sub'),
    NotifCategorie(NotificationService.kNotifPrestaSponsor, Icons.rocket_launch_outlined,
        'prest_notif_sponsor_end', 'prest_notif_sponsor_end_sub'),
  ];
}

/// Liste d'interrupteurs, à placer dans une section de réglages.
class NotificationsSettingsWidget extends StatefulWidget {
  final List<NotifCategorie> categories;
  const NotificationsSettingsWidget({super.key, required this.categories});

  @override
  State<NotificationsSettingsWidget> createState() =>
      _NotificationsSettingsWidgetState();
}

class _NotificationsSettingsWidgetState extends State<NotificationsSettingsWidget> {
  Map<String, bool> _valeurs = const {};

  @override
  void initState() {
    super.initState();
    NotificationService.loadAllPreferences().then((v) {
      if (mounted) setState(() => _valeurs = v);
    });
  }

  Future<void> _changer(String cle, bool v) async {
    setState(() => _valeurs = {..._valeurs, cle: v});
    await NotificationService.setCategory(cle, v);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cats = widget.categories;
    return Column(children: [
      for (var i = 0; i < cats.length; i++) ...[
        if (i > 0) const Divider(indent: 68, height: 1),
        SwitchListTile(
          secondary: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
            child: Icon(cats[i].icone, color: AppColors.primary, size: 20),
          ),
          title: Text(l.t(cats[i].titreKey), style: AppTextStyles.bodyLarge),
          subtitle: Text(l.t(cats[i].sousTitreKey), style: const TextStyle(fontSize: 12)),
          value: _valeurs[cats[i].cle] ?? cats[i].cle != NotificationService.kNotifPrix,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => _changer(cats[i].cle, v),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    ]);
  }
}
