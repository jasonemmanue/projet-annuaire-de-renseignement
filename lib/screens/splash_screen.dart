import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Contrôleurs d'animation
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;

  // Animations
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
    // 1. Animation de mise à l'échelle (zoom in du logo)
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // 2. Animation de fondu (fade in global)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // 3. Animation de pulsation (respiration du logo)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 4. Fondu du texte (apparaît après le logo)
    _fadeTextAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  Future<void> _startSequence() async {
    // Démarrer le fade-in
    _fadeController.forward();

    // Démarrer le zoom du logo après 200ms
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) _scaleController.forward();

    // Attendre 4 secondes au total, puis naviguer
    await Future.delayed(const Duration(milliseconds: 3800));
    if (mounted) _navigateToNext();
  }

  void _navigateToNext() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
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
    return Scaffold(
      backgroundColor: const Color(0xFF0071C2), // Bleu ImmoConnect
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Cercles décoratifs en arrière-plan
            _buildBackgroundDecor(),

            // Contenu central
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo animé
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

                  // Nom de l'application
                  FadeTransition(
                    opacity: _fadeTextAnimation,
                    child: const Text(
                      'ImmoConnect',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Sous-titre
                  FadeTransition(
                    opacity: _fadeTextAnimation,
                    child: const Text(
                      'Votre Immobilier au Cameroun',
                      style: TextStyle(
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

            // Indicateur de chargement en bas
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeTextAnimation,
                child: const Column(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Chargement...',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logo dans un conteneur blanc arrondi avec ombre
  Widget _buildLogo() {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            spreadRadius: 4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  /// Cercles décoratifs en arrière-plan
  Widget _buildBackgroundDecor() {
    return Stack(
      children: [
        // Grand cercle haut-droite
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
        ),
        // Cercle moyen haut-gauche
        Positioned(
          top: 40,
          left: -60,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
        // Cercle bas-gauche
        Positioned(
          bottom: -100,
          left: -60,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
        ),
        // Petit cercle bas-droite
        Positioned(
          bottom: 80,
          right: -30,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
      ],
    );
  }
}
