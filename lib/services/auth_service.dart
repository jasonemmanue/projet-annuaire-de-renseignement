import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'analytics_service.dart';

// ============================================================
// FICHIER : lib/services/auth_service.dart
//
// AUTHENTIFICATION : email + mot de passe (Firebase Auth).
//
// Le numéro de téléphone est demandé à l'inscription mais N'EST PAS vérifié :
// il sert de numéro Mobile Money par défaut pour les paiements (pré-rempli dans
// OperateurSelector). Aucun SMS/OTP n'est envoyé — le module OTP maison
// (functions/otp.js, lib/services/otp_auth_service.dart) reste sur le disque
// mais n'est plus branché sur ce chemin d'authentification.
//
// Firebase Auth email/password fournit directement une identité Firebase :
// `request.auth.uid` est renseigné nativement, sans pont ni custom token — les
// règles Firestore/Storage et les Cloud Functions (`verifyIdToken`) fonctionnent
// telles quelles.
//
// ✅ Anti-brute-force local (SharedPreferences, résistant aux redémarrages) :
//    3 tentatives → 30s | 5 tentatives → 5min
// ============================================================

/// Clés SharedPreferences pour la persistance du verrouillage
const _kLoginAttempts    = 'login_attempts';
const _kLoginBlockedUntil = 'login_blocked_until';

class AuthService extends ChangeNotifier {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Dernière erreur d'authentification (code Firebase brut), pour l'écran de
  /// diagnostic debug. `null` tant qu'aucune erreur n'est survenue.
  static String? lastAuthError;

  void _setCurrentUser(UserModel? value) {
    _currentUser = value;
    notifyListeners();
  }

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
      // `uid` réinjecté : certains vieux documents ne stockent pas le champ,
      // et sans lui UserModel.id serait vide.
      _setCurrentUser(UserModel.fromMap({'uid': uid, ...doc.data()!}));
    } else {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        final minimal = UserModel(
          id: uid,
          email: firebaseUser.email,
          nom: '',
          prenom: '',
          telephone: firebaseUser.phoneNumber ?? '',
          role: UserRole.prestataire,
        );
        await _db.collection('users').doc(uid).set({
          ...minimal.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        _setCurrentUser(minimal);
      }
    }

    // [ANALYTICS] Définir le rôle utilisateur comme user property GA4
    // "prestataire" pour les comptes connectés, "visiteur" par défaut.
    final role = _currentUser?.role == UserRole.prestataire
        ? 'prestataire'
        : 'visiteur';
    await AnalyticsService.instance.setUserRole(role);
  }

  /// Enregistre / rafraîchit le token FCM du compte connecté.
  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('users').doc(uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // FCM indisponible (simulateur iOS, permission refusée) : non bloquant.
    }
  }

  // ─── CONNEXION (EMAIL / MOT DE PASSE) ─────────────────────────────────

  /// Connexion par email + mot de passe.
  /// Applique l'anti-brute-force local et n'autorise que les rôles
  /// `prestataire` et `admin` (les visiteurs n'ont pas de compte).
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
      await _saveFcmToken(cred.user!.uid);

      // Vérification du rôle — prestataires ET admins peuvent se connecter
      if (_currentUser?.role != UserRole.prestataire &&
          _currentUser?.role != UserRole.admin) {
        await _auth.signOut();
        _setCurrentUser(null);
        // On comptabilise comme échec pour éviter l'énumération de rôles
        await _recordFailedAttempt();
        return AuthResult.wrongCredentials;
      }

      // ✅ Connexion réussie : réinitialisation du compteur
      await _resetBruteForce();
      lastAuthError = null;

      // [ANALYTICS] Connexion prestataire réussie
      await AnalyticsService.instance.logConnexionPrestataire();

      return AuthResult.success;

    } on FirebaseAuthException catch (e) {
      lastAuthError = e.code;
      if (e.code == 'user-not-found'      ||
          e.code == 'wrong-password'      ||
          e.code == 'invalid-credential'  ||
          e.code == 'invalid-email') {
        await _recordFailedAttempt();
        return e.code == 'invalid-email'
            ? AuthResult.invalidEmail
            : AuthResult.wrongCredentials;
      }
      if (e.code == 'too-many-requests') {
        await _recordFailedAttempt();
        return AuthResult.tooManyAttempts;
      }
      if (e.code == 'user-disabled') return AuthResult.userDisabled;
      return AuthResult.networkError;
    } catch (e) {
      lastAuthError = e.toString();
      return AuthResult.networkError;
    }
  }

  // ─── RÉINITIALISATION MOT DE PASSE ────────────────────────────────────

  /// Envoie un email de réinitialisation du mot de passe.
  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      lastAuthError = null;
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      lastAuthError = e.code;
      if (e.code == 'invalid-email') return AuthResult.invalidEmail;
      // `user-not-found` : réponse volontairement identique au succès pour ne
      // pas révéler quels emails ont un compte (énumération de comptes).
      if (e.code == 'user-not-found') return AuthResult.success;
      return AuthResult.networkError;
    } catch (e) {
      lastAuthError = e.toString();
      return AuthResult.networkError;
    }
  }

  // ─── INSCRIPTION (EMAIL / MOT DE PASSE) ───────────────────────────────

  /// Crée un compte prestataire.
  ///
  /// [telephone] est le numéro Mobile Money par défaut (format E.164, ex.
  /// « +237612345678 »). Il n'est PAS vérifié : aucun SMS n'est envoyé, il sert
  /// uniquement à pré-remplir l'opérateur au moment des paiements.
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

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        // FCM indisponible : non bloquant.
      }

      final user = UserModel(
        id: cred.user!.uid,
        email: email.trim(),
        nom: nom.trim(),
        prenom: prenom.trim(),
        telephone: telephone.trim(),   // numéro de paiement par défaut
        role: UserRole.prestataire,
        fcmToken: fcmToken,
        photoUrl: photoUrl,
        isVerifie: false,
        phoneVerified: false,          // téléphone non vérifié — sert au paiement
      );

      await _db.collection('users').doc(cred.user!.uid).set({
        ...user.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _setCurrentUser(user);
      await _resetBruteForce();
      lastAuthError = null;
      await AnalyticsService.instance.logConnexionPrestataire();
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      lastAuthError = e.code;
      switch (e.code) {
        case 'email-already-in-use':
          return AuthResult.emailAlreadyUsed;
        case 'invalid-email':
          return AuthResult.invalidEmail;
        case 'weak-password':
          return AuthResult.weakPassword;
        default:
          return AuthResult.networkError;
      }
    } catch (e) {
      lastAuthError = e.toString();
      return AuthResult.networkError;
    }
  }

  // ─── MISE À JOUR PROFIL ───────────────────────────────────────────────

  /// Met à jour les champs de profil passés (merge Firestore + cache mémoire).
  /// [telephone] met à jour le numéro Mobile Money par défaut.
  Future<void> updateProfile({
    String? nom,
    String? prenom,
    String? email,
    String? telephone,
    String? photoUrl,
  }) async {
    if (_currentUser == null) return;
    final updates = <String, dynamic>{};
    if (nom != null)       updates['nom']       = nom;
    if (prenom != null)    updates['prenom']    = prenom;
    if (email != null)     updates['email']     = email;
    if (telephone != null) updates['telephone'] = telephone;
    if (photoUrl != null)  updates['photoUrl']  = photoUrl;
    if (updates.isEmpty)   return;

    await _db.collection('users').doc(_currentUser!.id).set(
      updates,
      SetOptions(merge: true),
    );
    _setCurrentUser(UserModel(
      id:              _currentUser!.id,
      email:           email     ?? _currentUser!.email,
      nom:             nom       ?? _currentUser!.nom,
      prenom:          prenom    ?? _currentUser!.prenom,
      telephone:       telephone ?? _currentUser!.telephone,
      role:            _currentUser!.role,
      isPremium:       _currentUser!.isPremium,
      photoUrl:        photoUrl  ?? _currentUser!.photoUrl,
      fcmToken:        _currentUser!.fcmToken,
      isVerifie:       _currentUser!.isVerifie,
      compteGratuit:   _currentUser!.compteGratuit,
      premiumExpiry:   _currentUser!.premiumExpiry,
      phoneVerified:   _currentUser!.phoneVerified,
      phoneVerifiedAt: _currentUser!.phoneVerifiedAt,
    ));
  }

  // ─── MISE À JOUR PHOTO ────────────────────────────────────────────────

  /// Met à jour la photo de profil dans Firestore et en mémoire.
  Future<void> updatePhotoUrl(String photoUrl) async {
    if (_currentUser == null) return;
    await _db.collection('users').doc(_currentUser!.id).set(
      {'photoUrl': photoUrl},
      SetOptions(merge: true),
    );
    _setCurrentUser(UserModel(
      id:              _currentUser!.id,
      email:           _currentUser!.email,
      nom:             _currentUser!.nom,
      prenom:          _currentUser!.prenom,
      telephone:       _currentUser!.telephone,
      role:            _currentUser!.role,
      isPremium:       _currentUser!.isPremium,
      photoUrl:        photoUrl,
      fcmToken:        _currentUser!.fcmToken,
      isVerifie:       _currentUser!.isVerifie,
      compteGratuit:   _currentUser!.compteGratuit,
      premiumExpiry:   _currentUser!.premiumExpiry,
      phoneVerified:   _currentUser!.phoneVerified,
      phoneVerifiedAt: _currentUser!.phoneVerifiedAt,
    ));
  }

  // ─── DÉCONNEXION ──────────────────────────────────────────────────────

  Future<void> logout() async {
    await _auth.signOut();
    _setCurrentUser(null);
  }
}

enum AuthResult {
  success,
  /// Identifiants incorrects (email inconnu ou mot de passe faux).
  wrongCredentials,
  /// Email déjà associé à un compte (inscription).
  emailAlreadyUsed,
  /// Format d'email invalide.
  invalidEmail,
  /// Mot de passe trop faible (< 6 caractères côté Firebase).
  weakPassword,
  /// Compte désactivé par un administrateur Firebase.
  userDisabled,
  /// Erreur réseau / serveur.
  networkError,
  /// Compte temporairement verrouillé (anti-brute-force).
  tooManyAttempts,
}
