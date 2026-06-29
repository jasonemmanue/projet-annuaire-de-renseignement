import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

// ============================================================
// ÉCRAN : CGU — Conditions Générales d'Utilisation
// ============================================================

class CguScreen extends StatelessWidget {
  const CguScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('cgu_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Section('1. Objet',
              'Horem+ (ci-après « l\'Application ») est une plateforme de petites annonces immobilières au Cameroun, éditée par Horem+. Les présentes Conditions Générales d\'Utilisation (CGU) définissent les règles d\'utilisation de l\'Application.'),
          _Section('2. Accès',
              'L\'Application est accessible gratuitement à toute personne disposant d\'un smartphone Android. Certaines fonctionnalités (publication d\'annonces, messagerie avancée) nécessitent la création d\'un compte Prestataire via numéro de téléphone.'),
          _Section('3. Responsabilité des prestataires',
              'Les prestataires s\'engagent à publier des annonces exactes, légales et conformes à la réalité. Horem+ n\'est pas responsable des informations inexactes publiées par les prestataires.'),
          _Section('4. Contenu interdit',
              'Il est interdit de publier des annonces frauduleuses, discriminatoires, illégales ou portant atteinte à des droits de tiers. Horem+ se réserve le droit de supprimer tout contenu non conforme.'),
          _Section('5. Propriété intellectuelle',
              'L\'ensemble des éléments de l\'Application (logo, design, code) est la propriété d\'Horem+ et ne peut être reproduit sans autorisation écrite préalable.'),
          _Section('6. Paiements',
              'Les transactions de sponsorisation sont traitées via Mobile Money (Orange Money / MTN). Horem+ n\'est pas responsable des dysfonctionnements des opérateurs de paiement.'),
          _Section('7. Modification des CGU',
              'Horem+ se réserve le droit de modifier les présentes CGU à tout moment. L\'utilisateur sera informé des modifications substantielles.'),
          _Section('8. Droit applicable',
              'Les présentes CGU sont soumises au droit camerounais. Tout litige sera porté devant les juridictions compétentes de Yaoundé, Cameroun.'),
          _Section('Contact', 'Pour toute question : Horem+49@gmail.com'),
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
