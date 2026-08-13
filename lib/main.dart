import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'app_controller.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/accueil_screen.dart';
import 'screens/carte_screen.dart';
import 'screens/favoris_screen.dart';
import 'screens/messagerie_screen.dart';
import 'screens/profil_screen.dart';
import 'screens/dashboard_prestataire_screen.dart';
import 'screens/detail_logement_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/legal/consentement_screen.dart';
import 'services/auth_service.dart';
import 'widgets/stories_publicites_overlay.dart';
import 'services/notification_service.dart';
import 'widgets/shared_widgets.dart' as sw;
import 'models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
    // Firebase déjà initialisé par FirebaseInitProvider Android — on continue.
  }

  // App Check — Debug provider pour les tests internes (avant publication Play Store).
  // ⚠️ Avant publication Play Store :
  //   1. Remplacer AndroidProvider.debug par AndroidProvider.playIntegrity
  //   2. Enregistrer les SHA-1/SHA-256 release dans Firebase Console
  //
  // `appleProvider` vaut DeviceCheck par défaut, qui exige du vrai matériel et
  // n'existe pas sur le simulateur iOS : activate() y lève une exception. Rien
  // ici n'étant rattrapé, cette seule exception fermait l'app avant runApp().
  // On prend donc le provider de debug hors release, et on n'autorise plus
  // App Check à empêcher le démarrage : sans attestation, l'app tourne, ce
  // sont les requêtes protégées qui seront refusées — pas l'app entière.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
  } catch (e) {
    debugPrint('⚠️ App Check indisponible, démarrage sans : $e');
  }

  // Émulateurs désactivés — mode production (vrais SMS Firebase)
  // Pour réactiver les émulateurs en local :
  // await FirebaseAuth.instance.useAuthEmulator('192.168.1.20', 9099);
  // FirebaseFirestore.instance.useFirestoreEmulator('192.168.1.20', 8080);

  await AppController.instance.loadPrefs();
  await AuthService.instance.init();

  // Les notifications sont un service optionnel : l'enregistrement APNs échoue
  // sur simulateur (pas d'APNs) et sur un appareil dont l'utilisateur refuse la
  // permission. Ni l'un ni l'autre ne doit empêcher l'app de démarrer — sans ce
  // filet, un refus de permission suffisait à la rendre inutilisable.
  try {
    await NotificationService.init();

    if (AuthService.instance.isLoggedIn) {
      await NotificationService.saveToken(AuthService.instance.currentUser!.id);
    }
  } catch (e) {
    debugPrint('⚠️ Notifications indisponibles, démarrage sans : $e');
  }

  runApp(const HoremPlusApp());
}

// ─────────────────────────────────────────────────────────────
// App root — écoute AppController pour thème et langue
// ─────────────────────────────────────────────────────────────
class HoremPlusApp extends StatefulWidget {
  const HoremPlusApp({super.key});

  @override
  State<HoremPlusApp> createState() => _HoremPlusAppState();
}

class _HoremPlusAppState extends State<HoremPlusApp> {
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
      title: 'Horem+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: AppController.instance.themeMode,
      locale: AppController.instance.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorKey: navigatorKey,
      onGenerateRoute: (settings) {
        // ── Route /chat : ouverture depuis notification message ──
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

        // ── Route /logement : ouverture depuis notification annonce ou vues ──
        if (settings.name == '/logement') {
          final args = settings.arguments as Map<String, dynamic>?;
          final logementId = args?['logementId'] as String?;
          if (logementId != null) {
            return MaterialPageRoute(
              builder: (_) =>
                  _LogementFromNotification(logementId: logementId),
            );
          }
        }

        return null;
      },
      home: SplashScreen(nextScreen: const _ConsentGateway()),
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
// Logement ouvert depuis une notification (annonce ou vues)
// Charge le document Firestore par son ID puis affiche
// DetailLogementScreen.
// ─────────────────────────────────────────────────────────────
class _LogementFromNotification extends StatelessWidget {
  final String logementId;
  const _LogementFromNotification({required this.logementId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('logements')
          .doc(logementId)
          .get(),
      builder: (context, snap) {
        // ── Chargement ──
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ── Logement introuvable ou supprimé ──
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Annonce')),
            body: const Center(
              child: Text('Cette annonce n\'est plus disponible.'),
            ),
          );
        }

        // ── Affiche le détail ──
        final docData = snap.data!;
        final logement = Logement.fromMap(logementId, docData.data()!);
        return DetailLogementScreen(
          logement: logement,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Porte consentement légal (1er lancement)
// ─────────────────────────────────────────────────────────────
class _ConsentGateway extends StatelessWidget {
  const _ConsentGateway();

  Future<bool> _isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kLegalAcceptedKey) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAccepted(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == true) return const MainNavigationScreen();
        return const ConsentementScreen(nextScreen: MainNavigationScreen());
      },
    );
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

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stories : tous les 4 retours d'arrière-plan (visiteurs ET prestataires hors dashboard).
    if (state == AppLifecycleState.resumed && _currentIndex != 3) {
      if (StoriesTrigger.instance.registerForegroundReturn()) {
        _maybeShowStories();
      }
    }
  }

  Future<void> _maybeShowStories() async {
    if (!mounted) return;
    await ouvrirStoriesPublicites(context);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {
      // Recalibrer l'index si on passe de visiteur → prestataire ou inversement
      final isPresta = _isPrestataire;
      if (isPresta && _currentIndex == 3) return; // déjà sur dashboard
      if (!isPresta && _currentIndex == 3) _currentIndex = 0;
    });
  }

  bool get _isPrestataire =>
      AuthService.instance.isLoggedIn &&
          AuthService.instance.currentUser!.isPrestataire;

  /// Prestataire : Accueil | Carte | Favoris | Dashboard
  /// Visiteur    : Accueil | Carte | Favoris | Profil
  List<Widget> get _screens {
    if (_isPrestataire) {
      return const [
        AccueilScreen(),
        CarteScreen(),
        FavorisScreen(),
        DashboardPrestataireScreen(),
      ];
    }
    return [
      const AccueilScreen(),
      const CarteScreen(),
      const FavorisScreen(),
      _ProfilAvecLoginScreen(onLoginSuccess: _onLoginSuccess),
    ];
  }

  void _onLoginSuccess() {
    // Prestataire → aller directement au dashboard (onglet 3)
    final isPresta = AuthService.instance.isLoggedIn &&
        AuthService.instance.currentUser!.isPrestataire;
    setState(() => _currentIndex = isPresta ? 3 : 0);
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
        onTap: _onTabTap,
        isPrestataire: _isPrestataire,
      ),
    );
  }

  void _onTabTap(int i) {
    final wasIndex = _currentIndex;
    setState(() => _currentIndex = i);
    // Stories : tous les 3 changements de tab (visiteurs ET prestataires hors dashboard).
    if (wasIndex != i && i != 3) {
      if (StoriesTrigger.instance.registerNavigation()) {
        _maybeShowStories();
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Profil visiteur — passe le callback prestataire à ProfilScreen
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
    return ProfilScreen(
      key: const ValueKey('profil_visiteur'),
      onPrestataireAcces: () => _ouvrirLogin(context),
    );
  }
}