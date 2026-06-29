import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'cgu_screen.dart';
import 'politique_screen.dart';

// ============================================================
// ÉCRAN : ConsentementScreen
// Affiché au 1er lancement. Mémorise l'acceptation via prefs.
// ============================================================

const kLegalAcceptedKey = 'legal_accepted_v1';

class ConsentementScreen extends StatefulWidget {
  final Widget nextScreen;
  const ConsentementScreen({super.key, required this.nextScreen});

  @override
  State<ConsentementScreen> createState() => _ConsentementScreenState();
}

class _ConsentementScreenState extends State<ConsentementScreen> {
  bool _accepting = false;

  Future<void> _accepter() async {
    setState(() => _accepting = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLegalAcceptedKey, true);
    await prefs.setString(
        '${kLegalAcceptedKey}_date', DateTime.now().toIso8601String());
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => widget.nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Logo / icône
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.home_work_outlined,
                    color: Colors.white, size: 44),
              ),
              const SizedBox(height: 24),

              Text(
                l.t('consentement_title'),
                style: AppTextStyles.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l.t('consentement_subtitle'),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Résumé des points clés
              const _BulletPoint(
                icon: Icons.security_outlined,
                text: 'Vos données restent confidentielles et sécurisées.',
              ),
              const _BulletPoint(
                icon: Icons.location_off_outlined,
                text: 'La localisation n\'est utilisée que pour la carte.',
              ),
              const _BulletPoint(
                icon: Icons.notifications_outlined,
                text: 'Vous contrôlez vos notifications depuis le profil.',
              ),

              const SizedBox(height: 24),

              // Liens légaux
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CguScreen())),
                    child: Text(l.t('consentement_cgu_link'),
                        style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 13)),
                  ),
                  const Text('·',
                      style: TextStyle(color: AppColors.textHint)),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const PolitiqueScreen())),
                    child: Text(l.t('consentement_politique_link'),
                        style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 13)),
                  ),
                ],
              ),

              const Spacer(),

              // Bouton accepter
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _accepting ? null : _accepter,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _accepting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(l.t('consentement_accept'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );
}
