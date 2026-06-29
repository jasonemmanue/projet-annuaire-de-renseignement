// ============================================================
// FICHIER : lib/services/paiement_debug_log.dart
// Logs de diagnostic paiement — terminal Flutter + écran.
// Mettre kDebugPaiement = false avant de publier sur le Play Store.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Active les logs de diagnostic paiement.
/// false = production, true = debug.
const bool kDebugPaiement = true;

enum PayLogLevel { info, success, warning, error }

class PayLogEntry {
  final DateTime time;
  final String message;
  final PayLogLevel level;

  PayLogEntry(this.message, this.level) : time = DateTime.now();

  Color get color {
    switch (level) {
      case PayLogLevel.info:    return const Color(0xFF90CAF9);
      case PayLogLevel.success: return const Color(0xFFA5D6A7);
      case PayLogLevel.warning: return const Color(0xFFFFCC80);
      case PayLogLevel.error:   return const Color(0xFFEF9A9A);
    }
  }

  String get icon {
    switch (level) {
      case PayLogLevel.info:    return 'i';
      case PayLogLevel.success: return 'OK';
      case PayLogLevel.warning: return '!';
      case PayLogLevel.error:   return 'ERR';
    }
  }

  String get timestamp {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String toPlainText() => '[$timestamp] [$icon] $message';
}

/// Singleton de logs diagnostics paiement.
/// Imprime dans le terminal Flutter ET stocke pour l'affichage à l'écran.
class PaiementDebugLog extends ChangeNotifier {
  PaiementDebugLog._();
  static final instance = PaiementDebugLog._();

  final List<PayLogEntry> entries = [];

  void _add(String message, PayLogLevel level) {
    if (!kDebugPaiement) return;
    final entry = PayLogEntry(message, level);
    entries.add(entry);
    // Affichage dans le terminal Flutter (flutter run)
    debugPrint('[PAY][${level.name.toUpperCase().padRight(7)}] $message');
    notifyListeners();
  }

  void info(String msg)  => _add(msg, PayLogLevel.info);
  void ok(String msg)    => _add(msg, PayLogLevel.success);
  void warn(String msg)  => _add(msg, PayLogLevel.warning);
  void err(String msg)   => _add(msg, PayLogLevel.error);

  void clear() {
    if (!kDebugPaiement) return;
    entries.clear();
    debugPrint('[PAY] ========== NOUVELLE TENTATIVE ==========');
    notifyListeners();
  }

  String toText() => entries.map((e) => e.toPlainText()).join('\n');
}
