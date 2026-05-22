// ============================================================
// FICHIER : lib/screens/visitor_onboarding_screen.dart
//
// Affiché automatiquement à la PREMIÈRE ouverture de l'app
// (splash_screen.dart vérifie SharedPreferences 'onboarding_done').
//
// Structure en 2 pages :
//   Page 1 — Saisie du prénom/pseudo (optionnel)
//   Page 2 — Présentation des fonctionnalités + bouton "Commencer"
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../screens/messagerie_screen.dart' show getOrCreateVisitorId;

class VisitorOnboardingScreen extends StatefulWidget {
  final Widget nextScreen;

  const VisitorOnboardingScreen({super.key, required this.nextScreen});

  @override
  State<VisitorOnboardingScreen> createState() =>
      _VisitorOnboardingScreenState();
}

class _VisitorOnboardingScreenState extends State<VisitorOnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  bool _saving = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    // Crée l'UID visiteur dès l'onboarding
    getOrCreateVisitorId();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (name.isNotEmpty) {
      await prefs.setString('visitor_firstname', name);
      await prefs.setString('visitor_display_name', name);
    }
    await prefs.setBool('onboarding_done', true);

    if (mounted) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _saving = false);
    }
  }

  void _goToApp() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) _goToApp();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // ── Page 1 : Saisie du prénom ──────────────────
              _NamePage(
                controller: _nameController,
                focusNode: _nameFocus,
                l10n: l10n,
                isDark: isDark,
                saving: _saving,
                onContinue: _saveAndContinue,
                onSkip: _skip,
              ),
              // ── Page 2 : Fonctionnalités + Commencer ───────
              _FeaturesPage(
                l10n: l10n,
                isDark: isDark,
                visitorName: _nameController.text.trim(),
                onStart: _goToApp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PAGE 1 — Saisie du prénom
// ============================================================
class _NamePage extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AppLocalizations l10n;
  final bool isDark;
  final bool saving;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _NamePage({
    required this.controller,
    required this.focusNode,
    required this.l10n,
    required this.isDark,
    required this.saving,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          28, 16, 28, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bouton passer
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                l10n.onboardingSkip,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Icône
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.waving_hand_rounded,
                color: AppColors.primary, size: 38),
          ),

          const SizedBox(height: 28),

          Text(
            l10n.onboardingWelcome,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            l10n.onboardingSubtitle,
            style: TextStyle(
              fontSize: 15,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 40),

          Text(
            l10n.onboardingNameLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: l10n.onboardingNameHint,
              prefixIcon: const Icon(Icons.person_outline_rounded,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark ? AppColors.darkCard : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color:
                      isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
            onSubmitted: (_) => onContinue(),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: saving ? null : onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      l10n.onboardingContinue,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PAGE 2 — Présentation des fonctionnalités
// ============================================================
class _FeaturesPage extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDark;
  final String visitorName;
  final VoidCallback onStart;

  const _FeaturesPage({
    required this.l10n,
    required this.isDark,
    required this.visitorName,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = visitorName.isNotEmpty
        ? '${l10n.accueilGreeting}, $visitorName !'
        : l10n.onboardingWelcome;

    final features = [
      _FeatureItem(
        icon: Icons.search_rounded,
        color: const Color(0xFF0071C2),
        title: l10n.t('onboarding_feature_search'),
        desc: l10n.t('onboarding_feature_search_desc'),
      ),
      _FeatureItem(
        icon: Icons.map_outlined,
        color: const Color(0xFF28A745),
        title: l10n.t('onboarding_feature_map'),
        desc: l10n.t('onboarding_feature_map_desc'),
      ),
      _FeatureItem(
        icon: Icons.favorite_rounded,
        color: const Color(0xFFDC3545),
        title: l10n.t('onboarding_feature_favorites'),
        desc: l10n.t('onboarding_feature_favorites_desc'),
      ),
      _FeatureItem(
        icon: Icons.chat_bubble_outline_rounded,
        color: const Color(0xFFFEBA02),
        title: l10n.t('onboarding_feature_chat'),
        desc: l10n.t('onboarding_feature_chat_desc'),
      ),
      // ── Devenir prestataire par abonnement ───────────────
      _FeatureItem(
        icon: Icons.workspace_premium_rounded,
        color: const Color(0xFF7B2FBE),
        title: l10n.t('onboarding_feature_subscription'),
        desc: l10n.t('onboarding_feature_subscription_desc'),
        isHighlighted: true,
      ),
    ];

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          Text(
            greeting,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            l10n.onboardingFeaturesTitle,
            style: TextStyle(
              fontSize: 15,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.separated(
              itemCount: features.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 14),
              itemBuilder: (_, i) =>
                  _FeatureCard(item: features[i], isDark: isDark),
            ),
          ),

          const SizedBox(height: 20),

          // ── Bouton Commencer ────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.rocket_launch_rounded, size: 20),
              label: Text(
                l10n.onboardingStart,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============================================================
// MODÈLE
// ============================================================
class _FeatureItem {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final bool isHighlighted;

  const _FeatureItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    this.isHighlighted = false,
  });
}

// ============================================================
// CARTE de fonctionnalité
// ============================================================
class _FeatureCard extends StatelessWidget {
  final _FeatureItem item;
  final bool isDark;

  const _FeatureCard({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.isHighlighted
            ? item.color.withValues(alpha: isDark ? 0.18 : 0.07)
            : (isDark ? AppColors.darkCard : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: item.isHighlighted
            ? Border.all(
                color: item.color.withValues(alpha: 0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icône
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.color, size: 26),
          ),
          const SizedBox(width: 16),
          // Texte
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (item.isHighlighted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'NOUVEAU',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
