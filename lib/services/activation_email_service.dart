import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Types de services activables via le flow email/web (iOS uniquement).
/// Doit rester en phase avec `TYPES_ACTIVATION` dans functions/index.js.
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

  static const String _suffix = 'qhxw7o6nha-uc.a.run.app';
  static const String _envoyerLienUrl =
      'https://envoyerlienpaiementemail-$_suffix';

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
      final idToken = await user.getIdToken();
      final body = <String, dynamic>{
        'type': type.code,
        'email': email.trim(),
        if (targetId != null) 'targetId': targetId,
        if (params != null) 'params': params,
      };

      final resp = await http
          .post(
            Uri.parse(_envoyerLienUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final data = resp.body.isNotEmpty
          ? jsonDecode(resp.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (resp.statusCode == 200 && data['success'] == true) {
        return ActivationEmailResult(
          success: true,
          token: data['token']?.toString(),
          expiresAt: data['expiresAt']?.toString(),
          message: 'Email envoyé.',
        );
      }

      return ActivationEmailResult(
        success: false,
        message: data['error']?.toString() ?? 'Erreur inconnue',
      );
    } catch (e) {
      return ActivationEmailResult(
        success: false,
        message: 'Erreur réseau : $e',
      );
    }
  }
}
