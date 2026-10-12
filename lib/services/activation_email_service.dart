import 'package:firebase_auth/firebase_auth.dart';
import 'api_client.dart';

/// Types de services activables via le flow email/web (iOS uniquement).
/// Doit rester en phase avec `TYPES_ACTIVATION` de l'API (app/services/tarifs.py).
enum ActivationType {
  premium,
  publication,
  sponsorisation,
  publicite,
  urgence,
  visibilite,
}

extension ActivationTypeCode on ActivationType {
  String get code {
    switch (this) {
      case ActivationType.premium: return 'premium';
      case ActivationType.publication: return 'publication';
      case ActivationType.sponsorisation: return 'sponsorisation';
      case ActivationType.publicite: return 'publicite';
      case ActivationType.urgence: return 'urgence';
      case ActivationType.visibilite: return 'visibilite';
    }
  }
}

class ActivationEmailResult {
  final bool success;
  final String? token;
  final String? expiresAt;
  final String message;
  const ActivationEmailResult({
    required this.success,
    this.token,
    this.expiresAt,
    required this.message,
  });
}

/// Service iOS : demande au backend d'envoyer un email avec un lien vers la
/// page web de paiement. Aucune trace de montant/paiement dans l'app iOS.
class ActivationEmailService {
  ActivationEmailService._();
  static final ActivationEmailService instance = ActivationEmailService._();


  /// Envoie un email à [email] avec un lien pour activer le service.
  ///
  /// [type] : type de service (voir [ActivationType]).
  /// [targetId] : id du logement / publicité / alerte selon le type.
  /// [params] : données spécifiques au type — le backend calcule le montant
  ///           à partir de là. Exemples :
  ///   - sponsorisation : { duree: '1s'|'2s'|'1m', titre?: String }
  ///   - publication    : { montant: int, dureeJours: int, titre?: String }
  ///   - publicite      : { titre?: String }
  ///   - urgence        : {}
  ///   - visibilite     : { typeBien: String, titre?: String }
  ///   - premium        : {}
  Future<ActivationEmailResult> envoyerLien({
    required ActivationType type,
    required String email,
    String? targetId,
    Map<String, dynamic>? params,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ActivationEmailResult(
        success: false,
        message: 'Vous devez être connecté.',
      );
    }

    try {
      final data = await ApiClient.instance.post('/paiements/lien-email', {
        'type': type.code,
        'email': email.trim(),
        if (targetId != null) 'targetId': targetId,
        if (params != null) 'params': params,
      }) as Map<String, dynamic>;
      return ActivationEmailResult(
        success: data['success'] == true,
        token: data['token']?.toString(),
        expiresAt: data['expiresAt']?.toString(),
        message: 'Email envoyé.',
      );
    } on ApiException catch (e) {
      return ActivationEmailResult(success: false, message: e.message);
    } catch (e) {
      return ActivationEmailResult(
        success: false,
        message: 'Erreur réseau : $e',
      );
    }
  }
}
