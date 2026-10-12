// ============================================================
// FICHIER : lib/screens/prestataire_onboarding_screen.dart
//
// Tutoriel prestataire en 4 pages, affiché UNE SEULE FOIS après la
// première connexion prestataire (SharedPreferences
// 'presta_onboarding_seen'), puis re-jouable depuis le dashboard
// (« Revoir le tutoriel »). À la fin, l'écran se ferme : l'utilisateur
// est déjà positionné sur l'onglet Dashboard prestataire.
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class PrestataireOnboardingScreen extends StatefulWidget {
  const PrestataireOnboardingScreen({super.key});

  static const kVu = 'presta_onboarding_seen';

  /// Ouvre le tutoriel s'il n'a jamais été vu (1re connexion prestataire).
  static Future<void> afficherSiPremiereFois(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kVu) == true) return;
    if (!context.mounted) return;
    await afficher(context);
  }

  /// Ouvre le tutoriel (bouton « Revoir le tutoriel »).
  static Future<void> afficher(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PrestataireOnboardingScreen(),
      ));

  @override
  State<PrestataireOnboardingScreen> createState() =>
      _PrestataireOnboardingScreenState();
}

class _PageTuto {
  final IconData icone;
  final String titre;
  final String texte;
  final List<String> points;
  const _PageTuto(this.icone, this.titre, this.texte, this.points);
}

class _PrestataireOnboardingScreenState
    extends State<PrestataireOnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _terminer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrestataireOnboardingScreen.kVu, true);
    if (mounted) Navigator.of(context).pop();
  }

  List<_PageTuto> _pages(AppLocalizations l) => [
        _PageTuto(Icons.storefront_outlined, l.t('presta_onb_1_title'),
            l.t('presta_onb_1_body'), [
          l.t('presta_onb_1_p1'),
          l.t('presta_onb_1_p2'),
          l.t('presta_onb_1_p3'),
        ]),
        _PageTuto(Icons.chat_bubble_outline, l.t('presta_onb_2_title'),
            l.t('presta_onb_2_body'), [
          l.t('presta_onb_2_p1'),
          l.t('presta_onb_2_p2'),
          l.t('presta_onb_2_p3'),
        ]),
        _PageTuto(Icons.rocket_launch_outlined, l.t('presta_onb_3_title'),
            l.t('presta_onb_3_body'), [
          l.t('presta_onb_3_p1'),
          l.t('presta_onb_3_p2'),
          l.t('presta_onb_3_p3'),
          l.t('presta_onb_3_p4'),
        ]),
        _PageTuto(Icons.dashboard_customize_outlined, l.t('presta_onb_4_title'),
            l.t('presta_onb_4_body'), const []),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pages = _pages(l);
    final derniere = _page == pages.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // ── Progression en barres bleues (style stepper) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(children: [
              for (var i = 0; i < pages.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: i <= _page ? 1 : 0,
                        minHeight: 5,
                        color: AppColors.primary,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
              if (!derniere)
                TextButton(onPressed: _terminer, child: Text(l.t('presta_onb_skip')))
              else
                const SizedBox(width: 8),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _PageTutoVue(page: pages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: derniere
                    ? _terminer
                    : () => _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  derniere ? l.t('presta_onb_access') : l.t('presta_onb_next'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PageTutoVue extends StatelessWidget {
  final _PageTuto page;
  const _PageTutoVue({required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(page.icone, size: 54, color: AppColors.primary),
        ),
        const SizedBox(height: 28),
        Text(page.titre,
            textAlign: TextAlign.center,
            style: AppTextStyles.h2.copyWith(color: context.appTextPrimary)),
        const SizedBox(height: 12),
        Text(page.texte,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: context.appTextSecondary)),
        const SizedBox(height: 24),
        for (final p in page.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p,
                    style: TextStyle(fontSize: 14, height: 1.4, color: context.appTextPrimary)),
              ),
            ]),
          ),
      ]),
    );
  }
}
