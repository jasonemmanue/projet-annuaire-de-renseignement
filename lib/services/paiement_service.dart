import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// ============================================================
// FICHIER : lib/services/paiement_service.dart
// Paiements via GeniusPay (Wave CI, Orange Money CI, MTN CI…).
//
// ⚙️  MODE SIMULATION (« à blanc »)
// --------------------------------------------------------------
// Tant que [kSimulationPaiement] vaut true :
//   • AUCUN appel réseau / backend n'est effectué ;
//   • le paiement est SIMULÉ (succès au bout de quelques secondes) ;
//   • l'effet est appliqué directement (Premium / Sponsorisation).
// → On peut parcourir et tester tout le parcours sans clé GeniusPay.
//
// POUR PASSER EN RÉEL (GeniusPay) :
//   1. Mettre [kSimulationPaiement] = false.
//   2. Déployer les Cloud Functions avec vos clés GeniusPay :
//        firebase functions:secrets:set GENIUSPAY_API_KEY
//        firebase functions:secrets:set GENIUSPAY_SECRET_KEY
//   3. Vérifier [_region] et [_projectId] ci-dessous.
// ============================================================

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

  // Tarifs
  static const int premiumMontant = 200; // XAF/mois

  final _db = FirebaseFirestore.instance;

  bool get _simulation => kSimulationPaiement;

  // ═══════════════════════════════════════════════════════════════════════════
  // PREMIUM – 100 XOF/mois via Wave CI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierPremium({
    required String telephone,
    String? channel, // 'wave_ci' | 'orange_money_ci' | 'mtn_ci' | 'moov_ci'
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
              if (channel != null) 'channel': channel,
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
        final until = DateTime.now().add(const Duration(days: 30));
        await _db.collection('logements').doc(logementId).set(
          {
            'isSponsored': true,
            'sponsoredUntil': Timestamp.fromDate(until),
            'sponsoredAt': FieldValue.serverTimestamp(),
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
    try {
      final token = await user.getIdToken();
      if (token == null) {
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      final res = await http
          .post(
            Uri.parse(_initierSponsorisationUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'logementId': logementId,
              'telephone': telephone,
              if (channel != null) 'operateur': channel,
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
    try {
      final token = await user.getIdToken();
      if (token == null) {
        return const PaiementInitResult(
            success: false, message: 'Session expirée. Reconnectez-vous.');
      }
      final res = await http
          .post(
            Uri.parse(_initierUrgenceUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'logementId': logementId,
              'telephone': telephone,
              if (operateur != null) 'operateur': operateur,
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
        message:
            data['error'] as String? ?? 'Échec de l\'initiation du paiement.',
      );
    } catch (_) {
      return const PaiementInitResult(
          success: false,
          message: 'Erreur réseau. Vérifiez votre connexion et réessayez.');
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
  // SUIVI DU STATUT
  // ═══════════════════════════════════════════════════════════════════════════
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
      if (res.statusCode == 200 && data['success'] == true) {
        return _mapStatut(data['statut'] as String?);
      }
      return PaiementStatut.enAttente;
    } catch (_) {
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
