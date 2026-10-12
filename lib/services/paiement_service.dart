import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'paiement_debug_log.dart';

/// Les paiements de test se règlent désormais CÔTÉ SERVEUR (variable
/// PAIEMENTS_SIMULES de l'API sur Railway) : l'app passe toujours par l'API.
/// Conservé pour compatibilité ; n'a plus d'effet.
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

// ============================================================
// FICHIER : lib/services/paiement_service.dart
// Paiements Mobile Money via l'API Horem+ (remplace les Cloud
// Functions initierXxx / verifierPaiement). Les montants sont
// calculés par le serveur. Le WebView invisible (USSD) et le
// fallback navigateur des écrans de paiement sont inchangés.
// ============================================================
class PaiementService {
  PaiementService._();
  static final PaiementService instance = PaiementService._();

  final _api = ApiClient.instance;

  // Tarifs (affichage uniquement : le serveur fait foi)
  static const int premiumMontant = 200; // XAF/mois

  /// Code opérateur Flutter → channel GeniusPay attendu par l'API.
  ///   Cameroun       → 'orange' | 'mtn' | 'orange_cm' | 'mtn_cm'
  ///   Côte d'Ivoire  → 'orange_ci' | 'mtn_ci' | 'moov_ci' | 'wave_ci'
  static String? _toChannel(String? op) {
    switch (op) {
      case 'orange':
      case 'orange_cm':
        return 'orange_money_cm';
      case 'mtn':
      case 'mtn_cm':
        return 'mtn_momo_cm';
      case 'orange_ci':
        return 'orange_money_ci';
      case 'mtn_ci':
        return 'mtn_momo_ci';
      case 'moov_ci':
        return 'moov_ci';
      case 'wave_ci':
        return 'wave_ci';
      default:
        return null;
    }
  }

  /// Pays ISO à partir du code opérateur (défaut 'CM').
  static String _paysDepuisOperateur(String? op) {
    if (op == null) return 'CM';
    return op.endsWith('_ci') ? 'CI' : 'CM';
  }

  Map<String, dynamic> _corps(String telephone, String? operateur,
          [Map<String, dynamic>? extra]) =>
      {
        'telephone': telephone,
        'pays': _paysDepuisOperateur(operateur),
        if (_toChannel(operateur) != null) 'operateur': _toChannel(operateur),
        ...?extra,
      };

  /// Appel d'initiation commun (journalisé dans le panneau de diagnostic).
  Future<PaiementInitResult> _initier(
      String chemin, Map<String, dynamic> corps) async {
    final log = PaiementDebugLog.instance;
    log.info('POST $chemin');
    log.info('Body: $corps');
    try {
      final data = await _api.post(chemin, corps) as Map<String, dynamic>;
      log.ok('Référence: ${data["reference"]}');
      return PaiementInitResult(
        success: data['success'] == true,
        reference: data['reference'] as String?,
        checkoutUrl: data['checkoutUrl'] as String?,
        message: data['message'] as String? ?? 'Paiement initié.',
      );
    } on ApiException catch (e) {
      log.err('API ${e.statusCode}: ${e.message}');
      return PaiementInitResult(success: false, message: e.message);
    } catch (e) {
      log.err('Exception ${e.runtimeType}: $e');
      return PaiementInitResult(
          success: false,
          message: 'Erreur réseau (${e.runtimeType}). Vérifiez votre connexion.');
    }
  }

  bool get _connecte => FirebaseAuth.instance.currentUser != null;

  static const _nonConnecte = PaiementInitResult(
    success: false,
    message: 'Vous devez être connecté en tant que prestataire.',
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // PREMIUM
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierPremium({
    required String telephone,
    String? channel,
  }) async {
    if (!_connecte) return _nonConnecte;
    return _initier('/paiements/premium', _corps(telephone, channel));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPONSORISATION
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierSponsorisation({
    required String logementId,
    required String telephone,
    String? channel,
    String? duree, // '1s' | '2s' | '1m' — si null → '1m'
  }) async {
    if (!_connecte) return _nonConnecte;
    return _initier('/paiements/sponsorisation', _corps(telephone, channel, {
      'logementId': logementId,
      if (duree != null) 'duree': duree,
    }));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLICATION IMMOBILIER (montant recalculé par le serveur)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierPublication({
    required String logementId,
    required String telephone,
    required int montant,
    String? channel,
    int? dureeJours,
  }) async {
    if (!_connecte) return _nonConnecte;
    return _initier('/paiements/publication', _corps(telephone, channel, {
      'logementId': logementId,
      if (dureeJours != null) 'dureeJours': dureeJours,
    }));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // URGENCE VISITEUR (alerte prioritaire 48H)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Garantit une session Firebase (anonyme si le visiteur n'a pas de compte).
  Future<User?> assurerAuth() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      return cred.user;
    } catch (_) {
      return null;
    }
  }

  /// [logementId] = identifiant de l'alerte (nom historique conservé).
  Future<PaiementInitResult> initierUrgence({
    required String logementId,
    required String telephone,
    String? operateur,
  }) async {
    final user = await assurerAuth();
    if (user == null) {
      return const PaiementInitResult(
        success: false,
        message: 'Impossible de démarrer la session. Vérifiez votre connexion.',
      );
    }
    return _initier('/paiements/urgence',
        _corps(telephone, operateur, {'alerteId': logementId}));
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
    if (!_connecte) return _nonConnecte;
    return _initier('/paiements/publicite',
        _corps(telephone, channel, {'publiciteId': publiciteId}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISIBILITÉ ANNUELLE — Entreprise / Restaurant / École
  // ═══════════════════════════════════════════════════════════════════════════
  Future<PaiementInitResult> initierVisibilite({
    required String logementId,
    required String telephone,
    String? channel,
  }) async {
    if (!_connecte) return _nonConnecte;
    return _initier('/paiements/visibilite',
        _corps(telephone, channel, {'logementId': logementId}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DÉCLENCHEUR USSD SILENCIEUX
  //
  // Sur PawaPay CM, l'USSD push n'est pas envoyé à la simple création du
  // paiement — il faut qu'un client HTTP visite la page checkoutUrl pour
  // que GeniusPay pousse l'ordre à PawaPay.
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SUIVI DU STATUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Statut connu par l'API, mis à jour dès le webhook (interrogation
  /// versionnée toutes les 3 s).
  Stream<PaiementStatut> watchStatut(String reference) => _api.sonder(
        '/paiements/statut/$reference',
        (rep) => _mapStatut(rep['statut'] as String?),
        intervalle: const Duration(seconds: 3),
      );

  Future<PaiementStatut> verifierStatut(String reference) async {
    try {
      final rep = await _api.get('/paiements/statut/$reference')
          as Map<String, dynamic>;
      return _mapStatut(rep['statut'] as String?);
    } catch (_) {
      return PaiementStatut.erreur;
    }
  }

  /// Vérification ACTIVE (l'API interroge GeniusPay). Indépendante du
  /// webhook : à appeler en polling pendant l'attente.
  Future<PaiementStatut> verifierPaiementServeur(String reference) async {
    final log = PaiementDebugLog.instance;
    try {
      final data = await _api.post('/paiements/verifier', {'reference': reference})
          as Map<String, dynamic>;
      final statut = data['statut'] as String? ?? '?';
      log.info('Polling → statut=$statut');
      return _mapStatut(statut);
    } catch (e) {
      log.warn('Polling exception: $e');
      return PaiementStatut.enAttente;
    }
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
