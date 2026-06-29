import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'visitor_onboarding_screen.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/splash_screen.dart
// Splash animé → si première ouverture, affiche l'onboarding
//               sinon, va directement vers nextScreen
// ============================================================

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeTextAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startSequence();
  }

  void _initAnimations() {
    _scaleController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scaleAnimation = CurvedAnimation(
        parent: _scaleController, curve: Curves.elasticOut);

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _fadeTextAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0.4, 1.0, curve: Curves.easeIn)),
    );
  }

  Future<void> _startSequence() async {
    _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) _scaleController.forward();
    await Future.delayed(const Duration(milliseconds: 3800));
    if (mounted) _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;

    if (!mounted) return;

    final destination = onboardingDone
        ? widget.nextScreen
        : VisitorOnboardingScreen(nextScreen: widget.nextScreen);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0071C2),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            _buildBackgroundDecor(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (_, child) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      ),
                      child: _buildLogo(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _fadeTextAnimation,
                    child: const Text(
                      'Horem+',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _fadeTextAnimation,
                    child: Text(
                      l.t('splash_subtitle'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeTextAnimation,
                child: Column(
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 16),
                    Text(l.t('splash_loading'),
                        style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: Image.asset(
        'assets/images/logo.png',
        width: 180,
        height: 180,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  Widget _buildBackgroundDecor() {
    return Stack(children: [
      Positioned(
          top: -80, right: -80,
          child: _circle(280, 0.07)),
      Positioned(
          top: 40, left: -60,
          child: _circle(180, 0.05)),
      Positioned(
          bottom: -100, left: -60,
          child: _circle(300, 0.07)),
      Positioned(
          bottom: 80, right: -30,
          child: _circle(140, 0.05)),
    ]);
  }

  Widget _circle(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity)),
  );
}