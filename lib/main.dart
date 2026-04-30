import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/accueil_screen.dart';
import 'screens/carte_screen.dart';
import 'screens/favoris_screen.dart';
import 'screens/messagerie_screen.dart';
import 'screens/profil_screen.dart';
import 'screens/dashboard_prestataire_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/auth_service.dart';
import 'widgets/shared_widgets.dart' as sw;

// ============================================================
// FICHIER : lib/main.dart
// Point d'entrée de l'application SGK HOME - Cameroun
// Navigation principale + gestion thème clair/sombre
// ============================================================

void main() {
  runApp(const ImmoConnectApp());
}

class ImmoConnectApp extends StatefulWidget {
  const ImmoConnectApp({super.key});

  @override
  State<ImmoConnectApp> createState() => _ImmoConnectAppState();
}

class _ImmoConnectAppState extends State<ImmoConnectApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SGK HOME',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: SplashScreen(nextScreen: const MainNavigationScreen()),
    );
  }
}

// ============================================================
// FICHIER : lib/screens/main_navigation_screen.dart
// Navigation principale Bottom Bar (§4.1.1)
// Accueil | Carte | Favoris | Messages | Profil/Dashboard
// ============================================================

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Indique si l'utilisateur est connecté comme prestataire
  bool get _isPrestataire =>
      AuthService.instance.isLoggedIn &&
          AuthService.instance.currentUser!.isPrestataire;

  // Reconstruit les onglets selon l'état d'auth
  List<Widget> get _screens => [
    const AccueilScreen(),      // Écran 1 - Accueil
    const CarteScreen(),        // Écran 2 - Carte
    const FavorisScreen(),      // Favoris
    const MessagerieScreen(),   // Messagerie
    _isPrestataire              // Dernier onglet : Dashboard ou Profil
        ? const DashboardPrestataireScreen()
        : _ProfilAvecLoginScreen(onLoginSuccess: _onLoginSuccess),
  ];

  // Appelé après un login réussi pour rafraîchir la nav
  void _onLoginSuccess() {
    setState(() {
      // Rester sur l'onglet Profil/Dashboard (index 4)
      _currentIndex = 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: sw.MainBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        isPrestataire: _isPrestataire,
      ),
    );
  }
}

// ============================================================
// Écran intermédiaire : affiche ProfilScreen si déconnecté,
// avec un bouton flottant pour accéder au login prestataire.
// ============================================================
class _ProfilAvecLoginScreen extends StatelessWidget {
  final VoidCallback onLoginSuccess;

  const _ProfilAvecLoginScreen({required this.onLoginSuccess});

  Future<void> _ouvrirLogin(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true) {
      onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Écran profil sans paramètre spécial
        const ProfilScreen(),
        // Bouton flottant "Espace Prestataire" en bas
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: ElevatedButton.icon(
            onPressed: () => _ouvrirLogin(context),
            icon: const Icon(Icons.business_center_outlined),
            label: const Text('Accéder à l\'Espace Prestataire'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: const Color(0xFF0071C2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}