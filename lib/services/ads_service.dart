import 'dart:async';

// ============================================================
// FICHIER : lib/services/ads_service.dart
// Service AdMob — DÉSACTIVÉ (dépendance google_mobile_ads retirée).
// Conservé comme stub pour éviter les erreurs de référence.
// ============================================================

class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }
}
