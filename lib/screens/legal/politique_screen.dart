import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

// ============================================================
// ÉCRAN : PolitiqueScreen — Politique de Confidentialité
// ============================================================

class PolitiqueScreen extends StatelessWidget {
  const PolitiqueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('politique_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Section('1. Données collectées',
              'Horem+ collecte uniquement les données nécessaires au fonctionnement de l\'Application : numéro de téléphone (authentification), prénom et nom (profil prestataire), photos de profil et d\'annonces, localisation approximative (carte), token FCM (notifications push).'),
          _Section('2. Finalités',
              'Vos données sont utilisées exclusivement pour : gérer votre compte et vos annonces, vous permettre de communiquer avec d\'autres utilisateurs, vous envoyer des notifications pertinentes, améliorer l\'Application.'),
          _Section('3. Conservation',
              'Les données sont conservées le temps de l\'utilisation du service. Un compte inactif depuis 24 mois est supprimé automatiquement. Vous pouvez demander la suppression de vos données à tout moment.'),
          _Section('4. Partage',
              'Horem+ ne vend ni ne partage vos données personnelles avec des tiers à des fins commerciales. Les données peuvent être transmises à nos sous-traitants techniques (Firebase / Google) dans le strict cadre du service.'),
          _Section('5. Sécurité',
              'Les données sont chiffrées en transit (HTTPS/TLS) et stockées dans l\'infrastructure Firebase (Google Cloud), conforme aux normes de sécurité internationales.'),
          _Section('6. Vos droits',
              'Conformément à la loi camerounaise sur les données personnelles, vous disposez d\'un droit d\'accès, de rectification et de suppression de vos données. Contactez-nous à horemplus@gmail.com.'),
          _Section('7. Cookies & analytics',
              'L\'Application utilise Firebase Analytics (données anonymisées) pour mesurer l\'utilisation et améliorer l\'expérience. Aucun cookie de traçage publicitaire n\'est utilisé.'),
          _Section('Contact', 'DPO Horem+ : Horemplus@gmail.com'),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section(this.title, this.body);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppTextStyles.h3
                    .copyWith(color: AppColors.primary)),
            const SizedBox(height: 6),
            Text(body,
                style: const TextStyle(fontSize: 14, height: 1.6)),
          ],
        ),
      );
}
