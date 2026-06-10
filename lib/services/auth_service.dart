import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'analytics_service.dart';

// ============================================================
// FICHIER : lib/services/auth_service.dart
// ✅ Anti-brute-force avec SharedPreferences (résistant aux redémarrages)
// ✅ Seuils : 3 tentatives → 30s | 5 tentatives → 5min
// ✅ Reset mot de passe via Firebase
// ============================================================

/// Clés SharedPreferences pour la persistance du verrouillage
const _kLoginAttempts    = 'login_attempts';
const _kLoginBlockedUntil = 'login_blocked_until';

class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // ─── ÉTAT BRUTE-FORCE (cache mémoire, source de vérité = SharedPrefs) ──
  int      _failedAttempts = 0;
  DateTime? _blockedUntil;

  int      get failedAttempts => _failedAttempts;
  DateTime? get blockedUntil  => _blockedUntil;

  /// Durée de blocage selon le nombre de tentatives échouées.
  Duration _lockDuration(int attempts) {
    if (attempts >= 5) return const Duration(minutes: 5);
    if (attempts >= 3) return const Duration(seconds: 30);
    return Duration.zero;
  }

  /// Retourne true si le compte est actuellement verrouillé.
  bool get isBlocked {
    if (_blockedUntil == null) return false;
    return DateTime.now().isBefore(_blockedUntil!);
  }

  /// Temps restant avant déblocage (Duration.zero si non bloqué).
  Duration get remainingLockDuration {
    if (!isBlocked) return Duration.zero;
    return _blockedUntil!.difference(DateTime.now());
  }

  // ─── INITIALISATION ────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadBruteForceState();
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _loadUserFromFirestore(firebaseUser.uid);
    }
  }

  /// Recharge le profil de l'utilisateur connecté depuis Firestore.
  /// À appeler après une opération qui modifie le profil côté serveur
  /// (ex. activation Premium via webhook GeniusPay) pour rafraîchir l'UI.
  Future<void> refreshCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _loadUserFromFirestore(firebaseUser.uid);
    }
  }

  /// Recharge l'état de verrouillage depuis SharedPreferences.
  Future<void> _loadBruteForceState() async {
    final prefs = await SharedPreferences.getInstance();
    _failedAttempts = prefs.getInt(_kLoginAttempts) ?? 0;

    final blockedUntilMs = prefs.getInt(_kLoginBlockedUntil);
    if (blockedUntilMs != null) {
      _blockedUntil = DateTime.fromMillisecondsSinceEpoch(blockedUntilMs);
      // Si le blocage a expiré on nettoie
      if (!isBlocked) {
        _blockedUntil = null;
        await prefs.remove(_kLoginBlockedUntil);
      }
    }
  }

  /// Persiste l'état de verrouillage dans SharedPreferences.
  Future<void> _saveBruteForceState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLoginAttempts, _failedAttempts);
    if (_blockedUntil != null) {
      await prefs.setInt(
          _kLoginBlockedUntil, _blockedUntil!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kLoginBlockedUntil);
    }
  }

  /// Enregistre une tentative échouée et calcule le prochain blocage.
  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    final duration = _lockDuration(_failedAttempts);
    if (duration > Duration.zero) {
      _blockedUntil = DateTime.now().add(duration);
    }
    await _saveBruteForceState();
  }

  /// Remet à zéro le compteur après une connexion réussie.
  Future<void> _resetBruteForce() async {
    _failedAttempts = 0;
    _blockedUntil   = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLoginAttempts);
    await prefs.remove(_kLoginBlockedUntil);
  }

  // ─── CHARGEMENT UTILISATEUR ────────────────────────────────────────────

  Future<void> _loadUserFromFirestore(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      _currentUser = UserModel.fromMap(doc.data()!);
    } else {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        final minimal = UserModel(
          id: uid,
          email: firebaseUser.email ?? '',
          nom: '',
          prenom: '',
          role: UserRole.prestataire,
        );
        await _db.collection('users').doc(uid).set({
          ...minimal.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        _currentUser = minimal;
      }
    }

    // [ANALYTICS] Définir le rôle utilisateur comme user property GA4
    // "prestataire" pour les comptes connectés, "visiteur" par défaut.
    final role = _currentUser?.role == UserRole.prestataire
        ? 'prestataire'
        : 'visiteur';
    await AnalyticsService.instance.setUserRole(role);
  }

  // ─── CONNEXION ─────────────────────────────────────────────────────────

  Future<AuthResult> login(String email, String password) async {
    // Recharger l'état persisté (cas redémarrage entre tentatives)
    await _loadBruteForceState();

    // Vérification du verrouillage AVANT tout appel réseau
    if (isBlocked) return AuthResult.tooManyAttempts;

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _loadUserFromFirestore(cred.user!.uid);

      // FCM token
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('users').doc(cred.user!.uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }

      // Vérification du rôle — prestataires ET admins peuvent se connecter
      if (_currentUser?.role != UserRole.prestataire &&
          _currentUser?.role != UserRole.admin) {
        await _auth.signOut();
        _currentUser = null;
        // On comptabilise comme échec pour éviter l'énumération de rôles
        await _recordFailedAttempt();
        return AuthResult.wrongCredentials;
      }

      // ✅ Connexion réussie : réinitialisation du compteur
      await _resetBruteForce();

      // [ANALYTICS] Connexion prestataire réussie
      await AnalyticsService.instance.logConnexionPrestataire();

      return AuthResult.success;

    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found'   ||
          e.code == 'wrong-password'   ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        await _recordFailedAttempt();
        return AuthResult.wrongCredentials;
      }
      return AuthResult.networkError;
    }
  }

  // ─── RÉINITIALISATION MOT DE PASSE ─────────────────────────────────────

  /// Envoie un email de réinitialisation de mot de passe.
  ///
  /// Retourne :
  ///   [AuthResult.success]          → email envoyé avec succès
  ///   [AuthResult.wrongCredentials] → adresse email introuvable
  ///   [AuthResult.networkError]     → problème réseau ou autre erreur
  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim());
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        return AuthResult.wrongCredentials;
      }
      return AuthResult.networkError;
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  // ─── INSCRIPTION ───────────────────────────────────────────────────────

  /// Inscription prestataire avec photo de profil optionnelle.
  Future<AuthResult> register({
    required String email,
    required String password,
    required String nom,
    required String prenom,
    required String telephone,
    String? photoUrl,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final token = await FirebaseMessaging.instance.getToken();

      final user = UserModel(
        id: cred.user!.uid,
        email: email.trim(),
        nom: nom,
        prenom: prenom,
        telephone: telephone,
        role: UserRole.prestataire,
        fcmToken: token,
        photoUrl: photoUrl,
        isVerifie: false,
      );

      await _db.collection('users').doc(cred.user!.uid).set({
        ...user.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _currentUser = user;
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return AuthResult.emailAlreadyUsed;
      }
      return AuthResult.networkError;
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  // ─── MISE À JOUR PHOTO ────────────────────────────────────────────────

  /// Met à jour la photo de profil dans Firestore et en mémoire.
  Future<void> updatePhotoUrl(String photoUrl) async {
    if (_currentUser == null) return;
    await _db.collection('users').doc(_currentUser!.id).set(
      {'photoUrl': photoUrl},
      SetOptions(merge: true),
    );
    _currentUser = UserModel(
      id:            _currentUser!.id,
      email:         _currentUser!.email,
      nom:           _currentUser!.nom,
      prenom:        _currentUser!.prenom,
      telephone:     _currentUser!.telephone,
      role:          _currentUser!.role,
      isPremium:     _currentUser!.isPremium,
      photoUrl:      photoUrl,
      fcmToken:      _currentUser!.fcmToken,
      isVerifie:     _currentUser!.isVerifie,
      premiumExpiry: _currentUser!.premiumExpiry,
    );
  }

  // ─── DÉCONNEXION ──────────────────────────────────────────────────────

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
  }
}

enum AuthResult {
  success,
  wrongCredentials,
  emailAlreadyUsed,
  networkError,
  /// Compte temporairement verrouillé (anti-brute-force)
  tooManyAttempts,
}