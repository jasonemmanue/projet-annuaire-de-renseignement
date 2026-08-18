import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'analytics_service.dart';

// ============================================================
// FICHIER : lib/services/auth_service.dart
// ✅ Authentification par EMAIL + MOT DE PASSE (méthode principale)
// ✅ Vérification d'email obligatoire (lien de confirmation)
// ✅ Anti-brute-force avec SharedPreferences (résistant aux redémarrages)
// ✅ Seuils : 3 tentatives → 30s | 5 tentatives → 5min
// ✅ Reset mot de passe via Firebase
// ℹ️  Les méthodes OTP SMS restent disponibles (écran diag) mais ne sont
//     plus utilisées par l'UI de connexion/inscription.
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
      _setCurrentUser(UserModel.fromMap(doc.data()!));
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

  // ─── CONNEXION (EMAIL / MOT DE PASSE) ─────────────────────────────────

  /// Connexion par email + mot de passe.
  /// Applique l'anti-brute-force et vérifie le rôle (prestataire ou admin).
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
        _setCurrentUser(null);
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

  // ─── RÉINITIALISATION MOT DE PASSE ────────────────────────────────────

  /// Envoie un email de réinitialisation du mot de passe.
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

  // ─── INSCRIPTION (EMAIL / MOT DE PASSE) ───────────────────────────────

  /// Crée un compte prestataire par email + mot de passe.
  /// Le numéro de téléphone est conservé comme coordonnée de contact
  /// (affichée aux visiteurs sur les annonces) mais ne sert PAS à
  /// l'authentification.
  /// Envoie automatiquement un email de vérification après la création.
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

      // Envoi du lien de vérification d'email (non bloquant).
      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {
        // L'échec d'envoi ne doit pas bloquer l'inscription :
        // l'utilisateur pourra renvoyer le lien depuis l'app.
      }

      _setCurrentUser(user);
      await AnalyticsService.instance.setUserRole('prestataire');
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return AuthResult.emailAlreadyUsed;
        case 'invalid-email':
          return AuthResult.invalidEmail;
        case 'weak-password':
          return AuthResult.weakPassword;
        case 'operation-not-allowed':
          // Le provider Email/Password n'est pas activé côté Firebase Console.
          return AuthResult.networkError;
        default:
          return AuthResult.networkError;
      }
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  // ─── VÉRIFICATION D'EMAIL ─────────────────────────────────────────────

  /// `true` si l'utilisateur Firebase courant a un email vérifié.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Email de l'utilisateur Firebase courant (source de vérité Auth).
  String? get currentEmail => _auth.currentUser?.email;

  /// Renvoie un nouveau lien de vérification d'email à l'utilisateur courant.
  Future<AuthResult> renvoyerEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.wrongCredentials;
    try {
      await user.sendEmailVerification();
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') return AuthResult.tooManyAttempts;
      return AuthResult.networkError;
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  /// Recharge l'utilisateur Firebase pour rafraîchir l'état `emailVerified`
  /// (à appeler quand l'utilisateur revient dans l'app après avoir cliqué
  /// le lien reçu par email). Retourne `true` si l'email est vérifié.
  Future<bool> reloadEmailVerifie() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── OTP PHONE AUTH ───────────────────────────────────────────────────

  /// Dernier diagnostic OTP capturé (utile pour la bannière debug + écran diag).
  /// Reste `null` tant qu'aucune erreur n'a été remontée par Firebase Phone Auth.
  static OtpDiag? lastOtpDiag;

  /// Envoie un SMS OTP via Firebase Phone Auth.
  /// [telephone] doit être au format E.164, ex. « +237612345678 ».
  Future<void> envoyerOtp({
    required String telephone,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException) onError,
    void Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    debugPrint('[OTP] sendVerification phone=$telephone');
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: telephone,
        timeout: const Duration(seconds: 30),
        verificationCompleted: (PhoneAuthCredential credential) {
          debugPrint('[OTP] auto-verified by Play Services');
          onAutoVerified?.call(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _captureOtpDiag(e);
          onError(e);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('[OTP] codeSent id=${verificationId.substring(0, 6)}…');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      _captureOtpDiag(e);
      onError(e);
    } catch (e) {
      final wrapped = FirebaseAuthException(
        code: 'network-request-failed',
        message: 'Impossible de joindre le serveur : $e',
      );
      _captureOtpDiag(wrapped);
      onError(wrapped);
    }
  }

  /// Convertit une FirebaseAuthException en diagnostic structuré et le journalise.
  void _captureOtpDiag(FirebaseAuthException e) {
    final diag = OtpDiag.fromException(e);
    lastOtpDiag = diag;
    debugPrint(
      '[OTP] FAILED reason=${diag.reason.name} '
      'code=${e.code} message=${e.message}',
    );
  }

  /// Vérifie le code OTP saisi manuellement.
  /// Applique l'anti-brute-force sur les codes invalides.
  Future<AuthResult> verifierOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    await _loadBruteForceState();
    if (isBlocked) return AuthResult.tooManyAttempts;

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _doPhoneSignIn(credential, countFailure: true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code' ||
          e.code == 'invalid-verification-id') {
        await _recordFailedAttempt();
        return AuthResult.wrongCredentials;
      }
      if (e.code == 'session-expired') return AuthResult.otpExpired;
      return AuthResult.networkError;
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  /// Connexion avec un credential pré-construit (cas auto-vérification Android).
  /// Pas d'anti-brute-force : la vérification est faite par le système.
  Future<AuthResult> signInWithPhoneCredential(
      PhoneAuthCredential credential) async {
    try {
      return await _doPhoneSignIn(credential, countFailure: false);
    } on FirebaseAuthException catch (_) {
      return AuthResult.networkError;
    } catch (_) {
      return AuthResult.networkError;
    }
  }

  Future<AuthResult> _doPhoneSignIn(
    PhoneAuthCredential credential, {
    required bool countFailure,
  }) async {
    final cred = await _auth.signInWithCredential(credential);
    await _loadUserFromFirestore(cred.user!.uid);

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _db.collection('users').doc(cred.user!.uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    }

    if (_currentUser?.role != UserRole.prestataire &&
        _currentUser?.role != UserRole.admin) {
      await _auth.signOut();
      _setCurrentUser(null);
      if (countFailure) await _recordFailedAttempt();
      return AuthResult.wrongCredentials;
    }

    // Marque le téléphone vérifié la première fois seulement
    if (_currentUser?.phoneVerified != true) {
      await _db.collection('users').doc(cred.user!.uid).set(
        {
          'phoneVerified':   true,
          'phoneVerifiedAt': FieldValue.serverTimestamp(),
        },
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
        photoUrl:        _currentUser!.photoUrl,
        fcmToken:        _currentUser!.fcmToken,
        isVerifie:       _currentUser!.isVerifie,
        compteGratuit:   _currentUser!.compteGratuit,
        premiumExpiry:   _currentUser!.premiumExpiry,
        phoneVerified:   true,
        phoneVerifiedAt: DateTime.now(),
      ));
    }

    await _resetBruteForce();
    await AnalyticsService.instance.logConnexionPrestataire();
    return AuthResult.success;
  }

  // ─── MISE À JOUR PROFIL ───────────────────────────────────────────────

  /// Met à jour les champs de profil passés (merge Firestore + cache mémoire).
  Future<void> updateProfile({
    String? nom,
    String? prenom,
    String? email,
    String? photoUrl,
  }) async {
    if (_currentUser == null) return;
    final updates = <String, dynamic>{};
    if (nom != null)      updates['nom']      = nom;
    if (prenom != null)   updates['prenom']   = prenom;
    if (email != null)    updates['email']    = email;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (updates.isEmpty)  return;

    await _db.collection('users').doc(_currentUser!.id).set(
      updates,
      SetOptions(merge: true),
    );
    _setCurrentUser(UserModel(
      id:              _currentUser!.id,
      email:           email    ?? _currentUser!.email,
      nom:             nom      ?? _currentUser!.nom,
      prenom:          prenom   ?? _currentUser!.prenom,
      telephone:       _currentUser!.telephone,
      role:            _currentUser!.role,
      isPremium:       _currentUser!.isPremium,
      photoUrl:        photoUrl ?? _currentUser!.photoUrl,
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
  wrongCredentials,
  emailAlreadyUsed,
  /// Email au format invalide.
  invalidEmail,
  /// Mot de passe trop faible (< 6 caractères côté Firebase).
  weakPassword,
  networkError,
  /// Compte temporairement verrouillé (anti-brute-force)
  tooManyAttempts,
  /// Session OTP expirée (Firebase session-expired)
  otpExpired,
}

// ============================================================
// DIAGNOSTIC OTP — mapping FirebaseAuthException → cause probable
// Aide à savoir EXACTEMENT pourquoi l'envoi SMS échoue :
// fingerprint SHA absente, App Check KO, quota épuisé, etc.
// ============================================================

enum OtpDiagReason {
  /// SHA-1 / SHA-256 absente côté Firebase Console.
  shaMissing,
  /// App Check n'a pas pu fournir de token valide (Play Integrity KO ou
  /// debug token non enregistré).
  appCheckFailed,
  /// Quota Firebase Phone Auth dépassé (mensuel ou journalier).
  quotaExceeded,
  /// Facturation Firebase non activée — Phone Auth bascule sur Spark limité.
  billingDisabled,
  /// Trop de tentatives sur ce numéro côté Firebase.
  tooManyRequests,
  /// reCAPTCHA est apparu et a échoué/été fermé.
  recaptchaFailed,
  /// Numéro invalide ou manquant.
  invalidPhone,
  /// Code OTP invalide ou expiré.
  invalidCode,
  /// Connectivité réseau.
  network,
  /// Autre / inconnu.
  unknown,
}

class OtpDiag {
  final OtpDiagReason reason;
  final String code;
  final String? message;
  final DateTime at;

  OtpDiag({
    required this.reason,
    required this.code,
    this.message,
  }) : at = DateTime.now();

  factory OtpDiag.fromException(FirebaseAuthException e) {
    return OtpDiag(
      reason: _mapCode(e.code),
      code: e.code,
      message: e.message,
    );
  }

  static OtpDiagReason _mapCode(String code) {
    switch (code) {
      case 'app-not-authorized':
      case 'missing-client-identifier':
      case 'app-not-installed':
        return OtpDiagReason.shaMissing;
      case 'app-check-token-invalid':
      case 'firebase-app-check-token-is-invalid':
        return OtpDiagReason.appCheckFailed;
      case 'quota-exceeded':
        return OtpDiagReason.quotaExceeded;
      case 'billing-not-enabled':
        return OtpDiagReason.billingDisabled;
      case 'too-many-requests':
        return OtpDiagReason.tooManyRequests;
      case 'web-context-cancelled':
      case 'web-context-already-presented':
      case 'captcha-check-failed':
      case 'recaptcha-not-enabled':
        return OtpDiagReason.recaptchaFailed;
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return OtpDiagReason.invalidPhone;
      case 'invalid-verification-code':
      case 'invalid-verification-id':
      case 'session-expired':
        return OtpDiagReason.invalidCode;
      case 'network-request-failed':
        return OtpDiagReason.network;
      default:
        return OtpDiagReason.unknown;
    }
  }

  /// Clé i18n pour la cause probable affichée à l'utilisateur (debug only).
  String get i18nReasonKey => 'otp_diag_reason_${reason.name}';

  /// Clé i18n pour l'action conseillée à mener.
  String get i18nHintKey => 'otp_diag_hint_${reason.name}';
}