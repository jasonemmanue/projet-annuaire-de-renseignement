import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app_controller.dart';
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
import 'services/notification_service.dart';
import 'widgets/shared_widgets.dart' as sw;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AuthService.instance.init();
  await NotificationService.init();

  if (AuthService.instance.isLoggedIn) {
    await NotificationService.saveToken(AuthService.instance.currentUser!.id);
  }

  runApp(const ImmoConnectApp());
}

// ─────────────────────────────────────────────────────────────
// App root — écoute AppController pour thème et langue
// ─────────────────────────────────────────────────────────────
class ImmoConnectApp extends StatefulWidget {
  const ImmoConnectApp({super.key});

  @override
  State<ImmoConnectApp> createState() => _ImmoConnectAppState();
}

class _ImmoConnectAppState extends State<ImmoConnectApp> {
  @override
  void initState() {
    super.initState();
    AppController.instance.addListener(_onAppControllerChanged);
  }

  @override
  void dispose() {
    AppController.instance.removeListener(_onAppControllerChanged);
    super.dispose();
  }

  void _onAppControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SGK HOME',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: AppController.instance.themeMode,
      locale: AppController.instance.locale,
      navigatorKey: navigatorKey,
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>?;
          final conversationId = args?['conversationId'] as String?;
          if (conversationId != null) {
            return MaterialPageRoute(
              builder: (_) =>
                  _ChatFromNotification(conversationId: conversationId),
            );
          }
        }
        return null;
      },
      home: SplashScreen(nextScreen: const MainNavigationScreen()),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Chat ouvert depuis une notification
// ─────────────────────────────────────────────────────────────
class _ChatFromNotification extends StatelessWidget {
  final String conversationId;
  const _ChatFromNotification({required this.conversationId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadConvData(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!;
        return ChatScreen(
          conversationId: conversationId,
          logementTitre: data['logement_titre'] ?? '',
          logementPhoto: data['logement_photo'],
          otherId: data['otherId'] ?? '',
          currentUid: data['currentUid'] ?? '',
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadConvData() async {
    final auth = AuthService.instance;
    final currentUid = auth.isLoggedIn
        ? auth.currentUser!.id
        : await getOrCreateVisitorId();

    final doc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .get();
    final data = doc.data() ?? {};
    final participants = List<String>.from(data['participants'] ?? []);
    final otherId =
        participants.firstWhere((p) => p != currentUid, orElse: () => '');

    return {...data, 'otherId': otherId, 'currentUid': currentUid};
  }
}

// ─────────────────────────────────────────────────────────────
// Navigation principale
// ─────────────────────────────────────────────────────────────
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  bool get _isPrestataire =>
      AuthService.instance.isLoggedIn &&
      AuthService.instance.currentUser!.isPrestataire;

  /// Visiteur : Accueil | Carte | Favoris | Profil  (4 onglets)
  /// Prestataire : Accueil | Carte | Favoris | Dashboard (4 onglets — Messages dans le Dashboard)
  List<Widget> get _screens => _isPrestataire
      ? [
          const AccueilScreen(),
          const CarteScreen(),
          const FavorisScreen(),
          const DashboardPrestataireScreen(),
        ]
      : [
          const AccueilScreen(),
          const CarteScreen(),
          const FavorisScreen(),
          _ProfilAvecLoginScreen(onLoginSuccess: _onLoginSuccess),
        ];

  void _onLoginSuccess() {
    setState(() => _currentIndex = 0);
    if (AuthService.instance.isLoggedIn) {
      NotificationService.saveToken(AuthService.instance.currentUser!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxIndex = _screens.length - 1;
    if (_currentIndex > maxIndex) _currentIndex = 0;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: sw.MainBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        isPrestataire: _isPrestataire,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Profil visiteur avec bouton accès espace prestataire
// ─────────────────────────────────────────────────────────────
class _ProfilAvecLoginScreen extends StatelessWidget {
  final VoidCallback onLoginSuccess;
  const _ProfilAvecLoginScreen({required this.onLoginSuccess});

  Future<void> _ouvrirLogin(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true) onLoginSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ProfilScreen(key: ValueKey('profil_visiteur')),
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
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
