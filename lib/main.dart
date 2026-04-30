import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/accueil_screen.dart';
import 'screens/carte_screen.dart';
import 'screens/favoris_screen.dart';
import 'screens/messagerie_screen.dart';
import 'screens/profil_screen.dart';
import 'screens/dashboard_prestataire_screen.dart';
import 'widgets/shared_widgets.dart' as sw;

// ============================================================
// FICHIER : lib/main.dart
// Point d'entrée de l'application ImmoConnect Cameroun
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
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImmoConnect Cameroun',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const MainNavigationScreen(),
    );
  }
}

// ============================================================
// FICHIER : lib/screens/main_navigation_screen.dart
// Navigation principale Bottom Bar (§4.1.1)
// Accueil | Carte | Favoris | Messages | Profil/Dashboard
// ============================================================

class MainNavigationScreen extends StatefulWidget {
  /// Si l'utilisateur est prestataire connecté, le 5e onglet
  /// devient son Dashboard (§4.1.6) au lieu du profil
  final bool isPrestataire;

  const MainNavigationScreen({super.key, this.isPrestataire = false});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Onglets MVP - §4.1 "7 écrans principaux"
  // Écrans 1 à 7 mappés sur la bottom nav
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const AccueilScreen(),                          // Écran 1 - Accueil
      const CarteScreen(),                            // Écran 2 - Carte
      const FavorisScreen(),                          // Favoris
      const MessagerieScreen(),                       // Écran 5 - Messagerie
      widget.isPrestataire                            // Écran 6 ou 7
          ? const DashboardPrestataireScreen()
          : const ProfilScreen(),
    ];
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
        isPrestataire: widget.isPrestataire,
      ),
    );
  }
}