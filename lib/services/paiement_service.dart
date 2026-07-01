import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'paiement_debug_log.dart';

/// Bascule simulation ↔ réel. Mettre à false pour le paiement réel.
const bool kSimulationPaiement = false;

enum PaiementStatut { enAttente, reussi, echoue, timeout, erreur }

class PaiementInitResult {
  final bool success;
  final String? reference;
  final String? checkoutUrl;
  final String message;

  const PaiementInitResult({
    required this.success,
    this.reference,
    this.checkoutUrl,
    required this.message,
  });
}

class PaiementService {
  PaiementService._();
  static final PaiementService instance = PaiementService._();

  // ⚠️ Région + projet Firebase (à vérifier après déploiement).
  // URLs Cloud Run (2nd gen) — suffixe unique généré par Firebase
  static const String _suffix = 'qhxw7o6nha-uc.a.run.app';
  static const String _initierPremiumUrl =
      'https://initierpaiementpremium-$_suffix';
  static const String _initierSponsorisationUrl =
      'https://initiersponsorisation-$_suffix';
  static const String _verifierPaiementUrl =
      'https://verifierpaiement-$_suffix';
  static const String _initierUrgenceUrl =
      'https://initierurgence-$_suffix';
  static const String _initierPubliciteUrl =
      'https://initierpaiementpublicite-$_suffix';
  static const String _initierVisibiliteUrl =
      'https://initiervisibilite-$_suffix';

  // Tarifs
  static const int premiumMontant = 200; // XAF/mois

  final _db = FirebaseFirestore.instance;

  // En debug, on force la simulation même si kSimulationPaiement = false,
  // car les secrets GeniusPay ne sont disponibles qu'en production déployée.
  bool get _simulation => kSimulationPaiement || kDebugMode;

  /// Convertit le code opérateur Flutter ('orange'|'mtn') vers le
  /// channel GeniusPay Cameroun attendu par l'API.
  static String? _toChannel(String? op) {
    switch (op) {
      case 'orange': return 'orange_money_cm';
      case 'mtn':    return 'mtn_momo_cm';
      default:       return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREMIUM – 100 XOF/mois via Wave CI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierPremium({
    required String telephone,
    String? channel, // 'orange' | 'mtn'  → mappé vers GeniusPay CM
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Vous devez être connecté en tant que prestataire.',
      );
    }

    // ── Mode simulation ──────────────────────────────────────────────────────
    if (_simulation) {
      try {
        final expiry = DateTime.now().add(const Duration(days: 30));
        await _db.collection('users').doc(user.uid).set(
          {'isPremium': true, 'premiumExpiry': Timestamp.fromDate(expiry)},
          SetOptions(merge: true),
        );
        return PaiementInitResult(
          success: true,
          reference: 'SIMU-premium-${DateTime.now().millisecondsSinceEpoch}',
          message: 'Paiement simulé (mode test).',
        );
      } catch (_) {
        return const PaiementInitResult(
          success: false,
          message: 'Erreur lors de la simulation.',
        );
      }
    }

    // ── Mode réel (GeniusPay via Cloud Function) ─────────────────────────────
    try {
      final token = await user.getIdToken();
      if (token == null) {
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      final res = await http
          .post(
            Uri.parse(_initierPremiumUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'telephone': telephone,
              if (_toChannel(channel) != null) 'channel': _toChannel(channel),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        return PaiementInitResult(
          success: true,
          reference: data['reference'] as String?,
          checkoutUrl: data['checkoutUrl'] as String?,
          message: data['message'] as String? ?? 'Demande Wave envoyée.',
        );
      }
      return PaiementInitResult(
        success: false,
        message:
            data['error'] as String? ?? 'Échec de l\'initiation du paiement.',
      );
    } catch (_) {
      return const PaiementInitResult(
          success: false,
          message: 'Erreur réseau. Vérifiez votre connexion et réessayez.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPONSORISATION
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierSponsorisation({
    required String logementId,
    required String telephone,
    String? channel,
    String? duree,  // '1s' | '2s' | '1m' — si null → '1m' par défaut
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Vous devez être connecté en tant que prestataire.',
      );
    }

    // ── Mode simulation ──────────────────────────────────────────────────────
    if (_simulation) {
      try {
        final jours = const {'1s': 7, '2s': 14, '1m': 30}[duree ?? '1m'] ?? 30;
        final until = DateTime.now().add(Duration(days: jours));
        await _db.collection('logements').doc(logementId).set(
          {
            'isSponsored': true,
            'sponsoredUntil': Timestamp.fromDate(until),
            'sponsoredAt': FieldValue.serverTimestamp(),
            'disponible': true,
            'paymentPending': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
        return PaiementInitResult(
          success: true,
          reference: 'SIMU-sponsor-${DateTime.now().millisecondsSinceEpoch}',
          message: 'Paiement simulé (mode test).',
        );
      } catch (_) {
        return const PaiementInitResult(
          success: false,
          message: 'Erreur lors de la simulation.',
        );
      }
    }

    // ── Mode réel (GeniusPay via Cloud Function) ─────────────────────────────
    final log = PaiementDebugLog.instance;
    log.info('initierSponsorisation → mode réel');
    log.info('URL: $_initierSponsorisationUrl');
    log.info('Params: logementId=$logementId tel=$telephone canal=${_toChannel(channel) ?? "auto"}');
    try {
      final token = await user.getIdToken();
      if (token == null) {
        log.err('Token Firebase NULL — session expirée');
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      log.ok('Token Firebase obtenu (${token.substring(0, 15)}...)');

      final body = jsonEncode({
        'logementId': logementId,
        'telephone': telephone,
        if (_toChannel(channel) != null) 'operateur': _toChannel(channel),
        if (duree != null) 'duree': duree,
      });
      log.info('Body: $body');

      final res = await http
          .post(
            Uri.parse(_initierSponsorisationUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      log.info('HTTP ${res.statusCode}');
      final rawBody = res.body.length > 400
          ? '${res.body.substring(0, 400)}…'
          : res.body;
      log.info('Réponse: $rawBody');

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        log.ok('Référence: ${data["reference"]}');
        return PaiementInitResult(
          success: true,
          reference: data['reference'] as String?,
          checkoutUrl: data['checkoutUrl'] as String?,
          message: data['message'] as String? ?? 'Paiement initié.',
        );
      }
      final errMsg = data['error'] as String? ?? 'Échec de l\'initiation du paiement.';
      log.err('API error: $errMsg');
      return PaiementInitResult(success: false, message: errMsg);
    } catch (e) {
      log.err('Exception ${e.runtimeType}: $e');
      return PaiementInitResult(
          success: false,
          message: 'Erreur réseau (${e.runtimeType}). Vérifiez votre connexion.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // URGENCE VISITEUR (accès prioritaire 48H)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Garantit une session Firebase (anonyme si le visiteur n'a pas de compte).
  /// Retourne l'utilisateur courant, ou null si la connexion échoue.
  Future<User?> _assurerAuth() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      return cred.user;
    } catch (_) {
      return null;
    }
  }

  Future<PaiementInitResult> initierUrgence({
    required String logementId,
    required String telephone,
    String? operateur,
  }) async {
    // Le visiteur n'a pas forcément de compte : on l'identifie via une
    // session Firebase anonyme (uid stable, persiste entre les sessions).
    final user = await _assurerAuth();
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Impossible de démarrer la session. Vérifiez votre connexion.',
      );
    }

    // ── Mode simulation ──────────────────────────────────────────────────────
    if (_simulation) {
      try {
        final until = DateTime.now().add(const Duration(hours: 48));
        await _db.collection('urgences').doc('${user.uid}_$logementId').set(
          {
            'uid': user.uid,
            'logementId': logementId,
            'expiresAt': Timestamp.fromDate(until),
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return PaiementInitResult(
          success: true,
          reference: 'SIMU-urgence-${DateTime.now().millisecondsSinceEpoch}',
          message: 'Paiement simulé (mode test).',
        );
      } catch (_) {
        return const PaiementInitResult(
            success: false, message: 'Erreur lors de la simulation.');
      }
    }

    // ── Mode réel ────────────────────────────────────────────────────────────
    final log = PaiementDebugLog.instance;
    log.info('initierUrgence → mode réel');
    log.info('URL: $_initierUrgenceUrl');
    log.info('Params: logementId=$logementId tel=$telephone op=${_toChannel(operateur) ?? "auto"}');
    try {
      final token = await user.getIdToken();
      if (token == null) {
        log.err('Token Firebase NULL — session expirée');
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      log.ok('Token Firebase obtenu (${token.substring(0, 15)}...)');

      final body = jsonEncode({
        'logementId': logementId,
        'telephone': telephone,
        if (_toChannel(operateur) != null) 'operateur': _toChannel(operateur),
      });
      log.info('Body: $body');

      final res = await http
          .post(
            Uri.parse(_initierUrgenceUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      log.info('HTTP ${res.statusCode}');
      final rawBody = res.body.length > 400
          ? '${res.body.substring(0, 400)}…'
          : res.body;
      log.info('Réponse: $rawBody');

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        log.ok('Référence: ${data["reference"]}');
        return PaiementInitResult(
          success: true,
          reference: data['reference'] as String?,
          checkoutUrl: data['checkoutUrl'] as String?,
          message: data['message'] as String? ?? 'Paiement initié.',
        );
      }
      final errMsg = data['error'] as String? ?? 'Échec de l\'initiation du paiement.';
      log.err('API error: $errMsg');
      return PaiementInitResult(success: false, message: errMsg);
    } catch (e) {
      log.err('Exception ${e.runtimeType}: $e');
      return PaiementInitResult(
          success: false,
          message: 'Erreur réseau (${e.runtimeType}). Vérifiez votre connexion.');
    }
  }

  /// Vrai si le visiteur a un accès urgence actif (non expiré) sur ce logement.
  Future<bool> aAccesUrgence(String logementId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await _db
          .collection('urgences')
          .doc('${user.uid}_$logementId')
          .get();
      final exp = doc.data()?['expiresAt'];
      if (exp is Timestamp) return exp.toDate().isAfter(DateTime.now());
      return false;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLICITÉ — 500 XAF pour 4 jours de diffusion
  // ═══════════════════════════════════════════════════════════════════════════

  static const int publiciteMontant = 500;
  static const int publiciteDureeJours = 4;

  Future<PaiementInitResult> initierPaiementPublicite({
    required String publiciteId,
    required String telephone,
    String? channel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Vous devez être connecté en tant que prestataire.',
      );
    }

    if (_simulation) {
      try {
        final expiry =
            DateTime.now().add(const Duration(days: publiciteDureeJours));
        await _db.collection('publicites').doc(publiciteId).set(
          {
            'actif': true,
            'paymentPending': false,
            'expiresAt': Timestamp.fromDate(expiry),
          },
          SetOptions(merge: true),
        );
        return PaiementInitResult(
          success: true,
          reference: 'SIMU-publicite-${DateTime.now().millisecondsSinceEpoch}',
          message: 'Paiement simulé (mode test).',
        );
      } catch (_) {
        return const PaiementInitResult(
            success: false, message: 'Erreur lors de la simulation.');
      }
    }

    final log = PaiementDebugLog.instance;
    log.info('initierPaiementPublicite → mode réel');
    log.info('URL: $_initierPubliciteUrl');
    log.info('Params: publiciteId=$publiciteId tel=$telephone canal=${_toChannel(channel) ?? "auto"}');
    try {
      final token = await user.getIdToken();
      if (token == null) {
        log.err('Token Firebase NULL — session expirée');
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      log.ok('Token Firebase obtenu (${token.substring(0, 15)}...)');

      final body = jsonEncode({
        'publiciteId': publiciteId,
        'telephone': telephone,
        if (_toChannel(channel) != null) 'operateur': _toChannel(channel),
      });
      log.info('Body: $body');

      final res = await http
          .post(
            Uri.parse(_initierPubliciteUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      log.info('HTTP ${res.statusCode}');
      final rawBody = res.body.length > 400
          ? '${res.body.substring(0, 400)}…'
          : res.body;
      log.info('Réponse: $rawBody');

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        log.ok('Référence: ${data["reference"]}');
        return PaiementInitResult(
          success: true,
          reference: data['reference'] as String?,
          checkoutUrl: data['checkoutUrl'] as String?,
          message: data['message'] as String? ?? 'Paiement initié.',
        );
      }
      final errMsg = data['error'] as String? ?? 'Échec de l\'initiation du paiement.';
      log.err('API error: $errMsg');
      return PaiementInitResult(success: false, message: errMsg);
    } catch (e) {
      log.err('Exception ${e.runtimeType}: $e');
      return PaiementInitResult(
          success: false,
          message: 'Erreur réseau (${e.runtimeType}). Vérifiez votre connexion.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISIBILITÉ ANNUELLE — Entreprise / Restaurant / École
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierVisibilite({
    required String logementId,
    required String telephone,
    String? channel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Vous devez être connecté en tant que prestataire.',
      );
    }

    if (_simulation) {
      try {
        final expiry = DateTime.now().add(const Duration(days: 365));
        await _db.collection('logements').doc(logementId).set(
          {
            'visibiliteExpiry': Timestamp.fromDate(expiry),
            'disponible': true,
            'paymentPending': false,
          },
          SetOptions(merge: true),
        );
        return PaiementInitResult(
          success: true,
          reference: 'SIMU-visib-${DateTime.now().millisecondsSinceEpoch}',
          message: 'Paiement simulé (mode test).',
        );
      } catch (_) {
        return const PaiementInitResult(
            success: false, message: 'Erreur lors de la simulation.');
      }
    }

    try {
      final token = await user.getIdToken();
      if (token == null) {
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      final res = await http
          .post(
            Uri.parse(_initierVisibiliteUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'logementId': logementId,
              'telephone': telephone,
              if (_toChannel(channel) != null) 'operateur': _toChannel(channel),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        return PaiementInitResult(
          success: true,
          reference: data['reference'] as String?,
          checkoutUrl: data['checkoutUrl'] as String?,
          message: data['message'] as String? ?? 'Paiement initié.',
        );
      }
      return PaiementInitResult(
        success: false,
        message: data['error'] as String? ?? 'Échec de l\'initiation du paiement.',
      );
    } catch (_) {
      return const PaiementInitResult(
          success: false,
          message: 'Erreur réseau. Vérifiez votre connexion et réessayez.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUIVI DU STATUT
  // ═══════════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════════
  // DÉCLENCHEUR USSD SILENCIEUX
  //
  // Sur PawaPay CM, l'USSD push n'est pas envoyé à la simple création du
  // paiement — il faut qu'un client HTTP visite la page checkoutUrl pour
  // que GeniusPay pousse l'ordre à PawaPay.
  //
  // On fait ce GET depuis Flutter avec un User-Agent de navigateur mobile.
  // Si le serveur GeniusPay déclenche l'USSD dès la première requête HTML,
  // l'utilisateur ne voit RIEN — le menu PIN s'ouvre directement sur son
  // téléphone pendant qu'il reste sur l'écran d'attente de l'app.
  //
  // Retourne true si le GET a répondu 2xx (ne garantit pas que l'USSD est
  // parti — voir _demarrerAttente + fallback launchUrl).
  // ═══════════════════════════════════════════════════════════════════════════
  Future<bool> declencherUssdSilencieux(String checkoutUrl) async {
    if (checkoutUrl.isEmpty) return false;
    final log = PaiementDebugLog.instance;
    try {
      log.info('Déclenchement USSD silencieux : GET $checkoutUrl');
      final res = await http.get(
        Uri.parse(checkoutUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));
      log.info('USSD trigger → HTTP ${res.statusCode}');
      return res.statusCode >= 200 && res.statusCode < 400;
    } catch (e) {
      log.warn('USSD trigger exception : $e');
      return false;
    }
  }

  Stream<PaiementStatut> watchStatut(String reference) {
    if (_simulation || reference.startsWith('SIMU')) {
      return _statutSimule();
    }
    return _db
        .collection('transactions')
        .doc(reference)
        .snapshots()
        .map((doc) => _mapStatut(doc.data()?['statut'] as String?));
  }

  Future<PaiementStatut> verifierStatut(String reference) async {
    if (_simulation || reference.startsWith('SIMU')) {
      return PaiementStatut.reussi;
    }
    try {
      final doc = await _db.collection('transactions').doc(reference).get();
      return _mapStatut(doc.data()?['statut'] as String?);
    } catch (_) {
      return PaiementStatut.erreur;
    }
  }

  /// Vérification ACTIVE auprès du serveur (interroge GeniusPay directement).
  /// Indépendant du webhook : à appeler en polling pendant l'attente.
  Future<PaiementStatut> verifierPaiementServeur(String reference) async {
    if (_simulation || reference.startsWith('SIMU')) {
      return PaiementStatut.reussi;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return PaiementStatut.erreur;
    final log = PaiementDebugLog.instance;
    try {
      final token = await user.getIdToken();
      if (token == null) return PaiementStatut.erreur;
      final res = await http
          .post(
            Uri.parse(_verifierPaiementUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'reference': reference}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final statut = data['statut'] as String? ?? '?';
      log.info('Polling → HTTP ${res.statusCode} statut=$statut');
      if (res.statusCode == 200 && data['success'] == true) {
        return _mapStatut(statut);
      }
      return PaiementStatut.enAttente;
    } catch (e) {
      log.warn('Polling exception: $e');
      return PaiementStatut.enAttente;
    }
  }

  Stream<PaiementStatut> _statutSimule() async* {
    yield PaiementStatut.enAttente;
    await Future.delayed(const Duration(seconds: 4));
    yield PaiementStatut.reussi;
  }

  PaiementStatut _mapStatut(String? statut) {
    switch (statut) {
      case 'reussi':
        return PaiementStatut.reussi;
      case 'echoue':
        return PaiementStatut.echoue;
      default:
        return PaiementStatut.enAttente;
    }
  }
}
