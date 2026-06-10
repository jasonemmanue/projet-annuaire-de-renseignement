import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ============================================================
// FICHIER : lib/services/ads_service.dart
// Service centralisé Google AdMob : bannières + interstitiels.
//
// En DÉBOGAGE : utilise les IDs de TEST officiels Google.
// En RELEASE  : utilise vos vrais Ad Unit IDs (voir TODO ci-dessous).
// Les utilisateurs Premium ne doivent jamais voir de pub
// (filtrage fait côté widget / écran appelant).
// ============================================================

class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  // ── IDs de TEST Google (sûrs en développement) ──
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testBannerIOS =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';

  // ── VOS Ad Unit IDs de PRODUCTION ──
  // TODO: REMPLACER PAR VOTRE VRAI AD UNIT ID (Bannière Android)
  static const String _prodBannerAndroid =
      'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  // TODO: REMPLACER PAR VOTRE VRAI AD UNIT ID (Interstitiel Android)
  static const String _prodInterstitialAndroid =
      'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  // TODO: REMPLACER PAR VOS VRAIS AD UNIT IDS iOS si vous publiez sur iOS
  static const String _prodBannerIOS =
      'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const String _prodInterstitialIOS =
      'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  bool _initialized = false;
  InterstitialAd? _interstitialAd;

  String get bannerAdUnitId {
    if (kReleaseMode) {
      return Platform.isIOS ? _prodBannerIOS : _prodBannerAndroid;
    }
    return Platform.isIOS ? _testBannerIOS : _testBannerAndroid;
  }

  String get interstitialAdUnitId {
    if (kReleaseMode) {
      return Platform.isIOS ? _prodInterstitialIOS : _prodInterstitialAndroid;
    }
    return Platform.isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
  }

  /// À appeler une fois dans main().
  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  // ─── Bannière ───────────────────────────────────────────────────────────────
  /// Crée et charge une bannière. L'appelant gère son cycle de vie (dispose).
  BannerAd createBannerAd({
    void Function()? onLoaded,
    void Function()? onFailed,
  }) {
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailed?.call();
        },
      ),
    );
    ad.load();
    return ad;
  }

  // ─── Interstitiel ─────────────────────────────────────────────────────────
  /// Précharge un interstitiel (à appeler à l'avance, ex. dans initState).
  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  bool get isInterstitialReady => _interstitialAd != null;

  /// Affiche l'interstitiel s'il est prêt, puis en recharge un autre.
  /// Le Future se complète quand l'annonce est fermée (ou immédiatement
  /// si aucune n'était prête).
  Future<void> showInterstitialAd() async {
    final ad = _interstitialAd;
    if (ad == null) return;

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitialAd();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        if (!completer.isCompleted) completer.complete();
      },
    );
    await ad.show();
    return completer.future;
  }
}
