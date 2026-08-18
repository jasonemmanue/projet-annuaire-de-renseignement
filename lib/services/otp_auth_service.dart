import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// ============================================================================
// FICHIER : lib/services/otp_auth_service.dart
// Client de l'authentification OTP maison — indépendant de Firebase Auth.
//
// Interlocuteur : les Cloud Functions de functions/otp.js.
//   authOtpDemander · authOtpRenvoyer · authOtpVerifier
//   authTokenRefresh · authRevoquer
//
// Ce service ne connaît PAS Firebase Auth. Il détient la session applicative
// (JWT maison : access 1 h + refresh 30 j) et se contente de transmettre à
// AuthService le `firebaseCustomToken` renvoyé par le backend, qui sert à
// conserver une identité Firebase pour les règles Firestore/Storage.
//
// Les jetons sont rangés dans flutter_secure_storage (Keystore Android /
// Keychain iOS) et non dans SharedPreferences : un refresh token de 30 jours en
// clair sur le disque serait rejouable par n'importe quelle app sur un appareil
// rooté.
// ============================================================================

/// Canaux de la cascade, dans l'ordre où le backend les essaie.
enum CanalOtp { push, sms, smsAlt, voice, inconnu }

CanalOtp _canalDepuis(String? brut) {
  switch (brut) {
    case 'push':
      return CanalOtp.push;
    case 'sms':
      return CanalOtp.sms;
    case 'sms_alt':
      return CanalOtp.smsAlt;
    case 'voice':
      return CanalOtp.voice;
    default:
      return CanalOtp.inconnu;
  }
}

String canalVersApi(CanalOtp canal) {
  switch (canal) {
    case CanalOtp.push:
      return 'push';
    case CanalOtp.sms:
      return 'sms';
    case CanalOtp.smsAlt:
      return 'sms_alt';
    case CanalOtp.voice:
      return 'voice';
    case CanalOtp.inconnu:
      return '';
  }
}

/// Clé i18n décrivant le canal en cours à l'utilisateur.
String canalI18nKey(CanalOtp canal) => 'otp_canal_${canal.name}';

/// Résultat d'une demande (ou d'un renvoi) de code.
class DemandeOtp {
  final String sessionId;
  final CanalOtp canal;
  final CanalOtp? prochainCanal;

  /// Durée de validité du code, en secondes.
  final int expiresIn;

  /// Délai après lequel l'app propose d'escalader vers le canal suivant.
  final int delaiFallbackSec;

  /// Vrai si l'appareil est reconnu — le code a pu partir en push silencieux.
  final bool appareilDeConfiance;

  const DemandeOtp({
    required this.sessionId,
    required this.canal,
    required this.prochainCanal,
    required this.expiresIn,
    required this.delaiFallbackSec,
    required this.appareilDeConfiance,
  });

  factory DemandeOtp.fromJson(Map<String, dynamic> j) => DemandeOtp(
        sessionId: j['sessionId'] as String,
        canal: _canalDepuis(j['canal'] as String?),
        prochainCanal:
            j['prochainCanal'] == null ? null : _canalDepuis(j['prochainCanal'] as String?),
        expiresIn: (j['expiresIn'] as num?)?.toInt() ?? 300,
        delaiFallbackSec: (j['delaiFallbackSec'] as num?)?.toInt() ?? 25,
        appareilDeConfiance: j['appareilDeConfiance'] == true,
      );
}

/// Session ouverte après vérification réussie.
class SessionOtp {
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  /// Jeton d'échange Firebase — `null` si le pont d'identité est coupé côté
  /// backend (PONT_FIREBASE = false).
  final String? firebaseCustomToken;

  final String uid;
  final String telephone;
  final String role;
  final String nom;
  final String prenom;
  final bool nouvelUtilisateur;

  const SessionOtp({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.firebaseCustomToken,
    required this.uid,
    required this.telephone,
    required this.role,
    required this.nom,
    required this.prenom,
    required this.nouvelUtilisateur,
  });

  factory SessionOtp.fromJson(Map<String, dynamic> j) {
    final u = (j['utilisateur'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SessionOtp(
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      accessExpiresAt:
          DateTime.fromMillisecondsSinceEpoch((j['accessExpiresAt'] as num).toInt()),
      refreshExpiresAt:
          DateTime.fromMillisecondsSinceEpoch((j['refreshExpiresAt'] as num).toInt()),
      firebaseCustomToken: j['firebaseCustomToken'] as String?,
      uid: (u['uid'] ?? '') as String,
      telephone: (u['telephone'] ?? '') as String,
      role: (u['role'] ?? 'prestataire') as String,
      nom: (u['nom'] ?? '') as String,
      prenom: (u['prenom'] ?? '') as String,
      nouvelUtilisateur: j['nouvelUtilisateur'] == true,
    );
  }
}

/// Échec renvoyé par le backend, avec le code machine exploitable par l'UI.
class ErreurOtp implements Exception {
  /// `telephone_invalide`, `code_invalide`, `session_expiree`, `cooldown`, …
  final String code;
  final String message;
  final int? statut;

  /// Renseigné sur `code_invalide`.
  final int? tentativesRestantes;

  /// Renseigné sur les erreurs de limitation de débit.
  final int? attendreS;

  const ErreurOtp({
    required this.code,
    required this.message,
    this.statut,
    this.tentativesRestantes,
    this.attendreS,
  });

  /// Clé i18n de l'erreur, avec repli sur un message générique.
  String get i18nKey => 'otp_err_$code';

  @override
  String toString() => 'ErreurOtp($code): $message';
}

// ════════════════════════════════════════════════════════════════════════════

class OtpAuthService {
  OtpAuthService._();
  static final OtpAuthService instance = OtpAuthService._();

  static const String _suffix = 'qhxw7o6nha-uc.a.run.app';
  static const String _urlDemander = 'https://authotpdemander-$_suffix';
  static const String _urlRenvoyer = 'https://authotprenvoyer-$_suffix';
  static const String _urlVerifier = 'https://authotpverifier-$_suffix';
  static const String _urlRefresh = 'https://authtokenrefresh-$_suffix';
  static const String _urlRevoquer = 'https://authrevoquer-$_suffix';

  static const _kAccess = 'otp_access_token';
  static const _kAccessExp = 'otp_access_expires_at';
  static const _kRefresh = 'otp_refresh_token';
  static const _kRefreshExp = 'otp_refresh_expires_at';
  static const _kUid = 'otp_uid';
  static const _kDeviceId = 'otp_device_id';

  static const _stockage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const Duration _timeout = Duration(seconds: 30);

  String? _accessToken;
  DateTime? _accessExpiresAt;
  String? _deviceId;

  /// Codes arrivés par push silencieux FCM, pour l'autofill sur appareil de
  /// confiance. Alimenté par NotificationService.
  final _codesPush = StreamController<String>.broadcast();
  Stream<String> get codesPush => _codesPush.stream;

  /// Dernier échec rencontré — alimente l'écran de diagnostic.
  static ErreurOtp? dernierEchec;

  /// Dernière demande aboutie — alimente l'écran de diagnostic.
  static DemandeOtp? derniereDemande;

  // ─── Identifiant d'appareil ───────────────────────────────────────────────

  /// Identifiant stable de l'installation.
  ///
  /// Il n'identifie pas le matériel (pas d'IMEI, pas d'ANDROID_ID) : c'est un
  /// UUID tiré une fois et conservé dans le stockage sécurisé. Il sert
  /// uniquement à marquer l'appareil comme « de confiance » pour ouvrir le
  /// canal push silencieux, et disparaît à la désinstallation.
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    var id = await _stockage.read(key: _kDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _stockage.write(key: _kDeviceId, value: id);
    }
    _deviceId = id;
    return id;
  }

  // ─── API OTP ──────────────────────────────────────────────────────────────

  /// Demande un code. Le backend choisit le premier canal disponible de la
  /// cascade (push si l'appareil est de confiance, sinon SMS).
  ///
  /// [appSignature] est le hash SMS Retriever : sans lui, le SMS part quand
  /// même mais Android ne le remettra pas à l'app pour l'autofill.
  /// [canal] force un canal précis (bouton « Recevoir un appel »).
  Future<DemandeOtp> demanderCode({
    required String telephone,
    String? appSignature,
    String langue = 'fr',
    CanalOtp? canal,
  }) async {
    final reponse = await _poster(_urlDemander, {
      'telephone': telephone,
      'deviceId': await deviceId(),
      if (appSignature != null) 'appSignature': appSignature,
      'langue': langue,
      if (canal != null) 'canal': canalVersApi(canal),
    });
    final demande = DemandeOtp.fromJson(reponse);
    derniereDemande = demande;
    debugPrint('[OTP] demande OK canal=${demande.canal.name} '
        'session=${demande.sessionId.substring(0, 8)}…');
    return demande;
  }

  /// Escalade vers le canal suivant (ou celui demandé). Génère un code neuf :
  /// l'ancien est invalidé côté serveur au même instant.
  Future<DemandeOtp> renvoyerCode({
    required String sessionId,
    CanalOtp? canal,
  }) async {
    final reponse = await _poster(_urlRenvoyer, {
      'sessionId': sessionId,
      if (canal != null) 'canal': canalVersApi(canal),
    });
    final demande = DemandeOtp.fromJson(reponse);
    derniereDemande = demande;
    debugPrint('[OTP] renvoi OK canal=${demande.canal.name}');
    return demande;
  }

  /// Vérifie le code et ouvre la session. Les jetons sont persistés ici même :
  /// l'appelant n'a rien à stocker.
  Future<SessionOtp> verifierCode({
    required String sessionId,
    required String code,
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      // Simulateur iOS, permission refusée : le canal push silencieux ne sera
      // simplement pas proposé aux prochaines connexions.
    }

    final reponse = await _poster(_urlVerifier, {
      'sessionId': sessionId,
      'code': code,
      'deviceId': await deviceId(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });

    final session = SessionOtp.fromJson(reponse);
    await _enregistrerSession(session);
    return session;
  }

  // ─── Session ──────────────────────────────────────────────────────────────

  Future<void> _enregistrerSession(SessionOtp s) async {
    _accessToken = s.accessToken;
    _accessExpiresAt = s.accessExpiresAt;
    await Future.wait([
      _stockage.write(key: _kAccess, value: s.accessToken),
      _stockage.write(
          key: _kAccessExp, value: s.accessExpiresAt.millisecondsSinceEpoch.toString()),
      _stockage.write(key: _kRefresh, value: s.refreshToken),
      _stockage.write(
          key: _kRefreshExp, value: s.refreshExpiresAt.millisecondsSinceEpoch.toString()),
      _stockage.write(key: _kUid, value: s.uid),
    ]);
  }

  /// Recharge la session depuis le stockage sécurisé. Appelé au démarrage.
  /// Retourne `true` s'il existe un refresh token encore valable.
  Future<bool> restaurer() async {
    _accessToken = await _stockage.read(key: _kAccess);
    final exp = await _stockage.read(key: _kAccessExp);
    _accessExpiresAt = exp == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(exp));

    final refreshExp = await _stockage.read(key: _kRefreshExp);
    if (refreshExp == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(refreshExp)).isAfter(DateTime.now());
  }

  Future<String?> uidStocke() => _stockage.read(key: _kUid);

  /// Access token utilisable immédiatement, rafraîchi si nécessaire.
  ///
  /// La marge de 2 minutes évite qu'un jeton expire pendant le vol de la
  /// requête qu'il accompagne — le serveur le refuserait alors qu'il était
  /// valide au moment de l'appel.
  Future<String?> accessTokenValide() async {
    _accessToken ??= await _stockage.read(key: _kAccess);
    if (_accessExpiresAt == null) {
      final exp = await _stockage.read(key: _kAccessExp);
      _accessExpiresAt = exp == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(exp));
    }

    final marge = DateTime.now().add(const Duration(minutes: 2));
    if (_accessToken != null && _accessExpiresAt != null && _accessExpiresAt!.isAfter(marge)) {
      return _accessToken;
    }
    return rafraichir();
  }

  /// Échange le refresh token contre une nouvelle paire.
  /// Retourne `null` si la session est morte : l'appelant doit reconnecter.
  Future<String?> rafraichir() async {
    final refresh = await _stockage.read(key: _kRefresh);
    if (refresh == null) return null;

    try {
      final reponse = await _poster(_urlRefresh, {
        'refreshToken': refresh,
        'deviceId': await deviceId(),
      });
      final session = SessionOtp.fromJson({
        ...reponse,
        'utilisateur': reponse['utilisateur'] ?? {'uid': await uidStocke() ?? ''},
      });
      await _enregistrerSession(session);
      return session.accessToken;
    } on ErreurOtp catch (e) {
      // `refresh_rejoue` signale une session compromise : le backend a déjà
      // tout révoqué, il ne reste qu'à effacer localement.
      debugPrint('[OTP] refresh refusé (${e.code}) — session effacée');
      await effacerSession();
      return null;
    } catch (e) {
      // Panne réseau : on garde la session, elle repartira au prochain essai.
      debugPrint('[OTP] refresh impossible (réseau) : $e');
      return null;
    }
  }

  /// Déconnexion : révoque le refresh token côté serveur puis efface en local.
  /// L'effacement local a lieu même si l'appel réseau échoue — sinon un
  /// utilisateur hors ligne resterait connecté sur l'appareil.
  Future<void> deconnecter({bool toutesLesSessions = false}) async {
    final refresh = await _stockage.read(key: _kRefresh);
    try {
      await _poster(
        _urlRevoquer,
        {
          if (refresh != null) 'refreshToken': refresh,
          if (toutesLesSessions) 'toutesLesSessions': true,
        },
        avecAuth: toutesLesSessions,
      );
    } catch (e) {
      debugPrint('[OTP] révocation serveur impossible : $e');
    }
    await effacerSession();
  }

  Future<void> effacerSession() async {
    _accessToken = null;
    _accessExpiresAt = null;
    await Future.wait([
      _stockage.delete(key: _kAccess),
      _stockage.delete(key: _kAccessExp),
      _stockage.delete(key: _kRefresh),
      _stockage.delete(key: _kRefreshExp),
      _stockage.delete(key: _kUid),
    ]);
    // _kDeviceId est volontairement conservé : l'appareil reste « de
    // confiance » d'une session à l'autre, ce qui garde le canal push
    // silencieux disponible à la reconnexion.
  }

  // ─── Push silencieux ──────────────────────────────────────────────────────

  /// Appelé par NotificationService à la réception d'un message FCM
  /// `type: 'otp_silent'`. Le code remonte à l'écran de saisie, qui le valide
  /// sans intervention de l'utilisateur.
  void injecterCodePush(String code) {
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      debugPrint('[OTP] code reçu par push silencieux');
      _codesPush.add(code);
    }
  }

  // ─── HTTP ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _poster(
    String url,
    Map<String, dynamic> corps, {
    bool avecAuth = false,
  }) async {
    final entetes = <String, String>{'Content-Type': 'application/json'};
    if (avecAuth) {
      final token = await accessTokenValide();
      if (token != null) entetes['Authorization'] = 'Bearer $token';
    }

    late final http.Response reponse;
    try {
      reponse = await http
          .post(Uri.parse(url), headers: entetes, body: jsonEncode(corps))
          .timeout(_timeout);
    } on TimeoutException {
      throw _memoriser(const ErreurOtp(
        code: 'reseau_timeout',
        message: 'Le serveur ne répond pas. Réessayez.',
      ));
    } on SocketException {
      throw _memoriser(const ErreurOtp(
        code: 'reseau',
        message: 'Pas de connexion Internet.',
      ));
    } catch (e) {
      throw _memoriser(ErreurOtp(code: 'reseau', message: e.toString()));
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(reponse.body) as Map<String, dynamic>;
    } catch (_) {
      throw _memoriser(ErreurOtp(
        code: 'reponse_illisible',
        message: 'Réponse serveur invalide (HTTP ${reponse.statusCode})',
        statut: reponse.statusCode,
      ));
    }

    if (reponse.statusCode >= 200 && reponse.statusCode < 300 && json['success'] == true) {
      return json;
    }

    throw _memoriser(ErreurOtp(
      code: (json['code'] ?? 'inconnu') as String,
      message: (json['error'] ?? 'Erreur inconnue') as String,
      statut: reponse.statusCode,
      tentativesRestantes: (json['tentativesRestantes'] as num?)?.toInt(),
      attendreS: (json['attendreS'] as num?)?.toInt(),
    ));
  }

  ErreurOtp _memoriser(ErreurOtp e) {
    dernierEchec = e;
    debugPrint('[OTP] échec ${e.code} — ${e.message}');
    return e;
  }
}
