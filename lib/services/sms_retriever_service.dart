import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
// FICHIER : lib/services/sms_retriever_service.dart
// Pont Dart ↔ SMS Retriever API (Android).
//
// Le code natif vit dans android/app/src/main/kotlin/com/horemplus/app/
// SmsRetrieverPlugin.kt. Aucune permission SMS n'est demandée : Google Play
// Services ne remet à l'app que le message qui se termine par le hash de sa
// propre signature.
//
// Sur iOS il n'y a rien à faire : l'autofill du code est natif dès qu'un champ
// porte `autofillHints: [AutofillHints.oneTimeCode]`. Les méthodes de ce
// service y répondent donc en no-op.
// ============================================================================

class SmsRetrieverService {
  SmsRetrieverService._();
  static final SmsRetrieverService instance = SmsRetrieverService._();

  static const _methodes = MethodChannel('horemplus/sms_retriever');
  static const _evenements = EventChannel('horemplus/sms_retriever/events');

  StreamSubscription? _abonnement;

  /// Le hash à 11 caractères identifiant l'app auprès de Google Play Services.
  ///
  /// Il est transmis au backend à chaque demande de code pour qu'il termine le
  /// SMS par cette chaîne. Sans lui, le SMS arrive quand même mais Android ne
  /// le donne pas à l'app : l'utilisateur recopie le code à la main.
  ///
  /// Mis en cache : le calcul ouvre le PackageManager et hache la signature de
  /// l'APK, inutile de le refaire à chaque saisie de numéro.
  String? _signature;
  bool _signatureChargee = false;

  bool get estDisponible => !kIsWeb && Platform.isAndroid;

  /// Retourne le hash de signature, ou `null` sur iOS / si Play Services manque.
  Future<String?> signatureApp() async {
    if (!estDisponible) return null;
    if (_signatureChargee) return _signature;
    try {
      _signature = await _methodes.invokeMethod<String>('signatureApp');
    } on PlatformException catch (e) {
      debugPrint('[SMS-R] signature indisponible : ${e.message}');
      _signature = null;
    } catch (e) {
      debugPrint('[SMS-R] signature indisponible : $e');
      _signature = null;
    }
    _signatureChargee = true;
    return _signature;
  }

  /// Arme l'écoute et appelle [onCode] dès qu'un code à 6 chiffres arrive.
  ///
  /// La fenêtre Play Services dure 5 minutes puis se referme d'elle-même —
  /// exactement la durée de validité d'un code côté backend.
  ///
  /// Retourne `false` si l'écoute n'a pas pu démarrer (iOS, ROM sans Play
  /// Services) : l'appelant garde alors la saisie manuelle, qui reste le
  /// chemin nominal et n'est jamais désactivée.
  Future<bool> ecouter(void Function(String code) onCode) async {
    if (!estDisponible) return false;

    await arreter();

    _abonnement = _evenements.receiveBroadcastStream().listen(
      (evenement) {
        final code = evenement?.toString();
        if (code != null && RegExp(r'^\d{6}$').hasMatch(code)) {
          debugPrint('[SMS-R] code reçu par autofill');
          onCode(code);
        }
      },
      onError: (e) {
        // `timeout` après 5 minutes : cas nominal, pas une anomalie.
        debugPrint('[SMS-R] flux interrompu : $e');
      },
      cancelOnError: false,
    );

    try {
      final arme = await _methodes.invokeMethod<bool>('demarrer') ?? false;
      if (!arme) await arreter();
      return arme;
    } on PlatformException catch (e) {
      debugPrint('[SMS-R] démarrage impossible : ${e.message}');
      await arreter();
      return false;
    }
  }

  /// Coupe l'écoute. À appeler dans `dispose()` de l'écran d'authentification.
  Future<void> arreter() async {
    await _abonnement?.cancel();
    _abonnement = null;
    if (!estDisponible) return;
    try {
      await _methodes.invokeMethod('arreter');
    } catch (_) {
      // Rien à rattraper : le récepteur natif se retire aussi tout seul.
    }
  }
}
