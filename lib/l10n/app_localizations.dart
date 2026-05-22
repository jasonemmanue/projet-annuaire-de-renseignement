// ============================================================
// FICHIER : lib/l10n/app_localizations.dart
// Système de traduction léger sans génération de code
// Langues supportées : fr (défaut), en
// ============================================================

import 'package:flutter/material.dart';
import 'app_fr.dart';
import 'app_en.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('fr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('fr'),
    Locale('en'),
  ];

  Map<String, String> get _strings {
    switch (locale.languageCode) {
      case 'en':
        return enStrings;
      case 'fr':
      default:
        return frStrings;
    }
  }

  String t(String key) => _strings[key] ?? key;

  // ── Raccourcis directs ─────────────────────────────────────
  String get navAccueil => t('nav_accueil');
  String get navCarte => t('nav_carte');
  String get navFavoris => t('nav_favoris');
  String get navProfil => t('nav_profil');
  String get navDashboard => t('nav_dashboard');

  String get messagesTitle => t('messages_title');
  String get messagesEmpty => t('messages_empty');
  String get messagesEmptyDesc => t('messages_empty_desc');
  String get messagesYesterday => t('messages_yesterday');
  String get messagesToday => t('messages_today');
  String get messagesWrite => t('messages_write');
  String get messagesPhotoComing => t('messages_photo_coming');
  String get messagesDocComing => t('messages_doc_coming');

  String get onboardingWelcome => t('onboarding_welcome');
  String get onboardingSubtitle => t('onboarding_intro');
  String get onboardingIntro => t('onboarding_intro');
  String get onboardingNameLabel => t('onboarding_name_label');
  String get onboardingNameHint => t('onboarding_firstname_hint');
  String get onboardingFirstnameHint => t('onboarding_firstname_hint');
  String get onboardingContinue => t('onboarding_continue');
  String get onboardingSkip => t('onboarding_skip');
  String get onboardingFeaturesTitle => t('onboarding_features_title');
  String get onboardingStart => t('onboarding_start');

  String get profilTitle => t('profil_title');
  String get profilDarkMode => t('profil_dark_mode');
  String get profilLanguage => t('profil_language');
  String get profilLogout => t('profil_logout');
  String get profilVisitor => t('profil_visitor');
  String get profilVisitorSub => t('profil_visitor_sub');

  String get commonLoading => t('common_loading');
  String get commonError => t('common_error');
  String get commonSend => t('common_send');
  String get commonCancel => t('common_cancel');
  String get commonSave => t('common_save');

  String get accueilGreeting => t('accueil_greeting');
  String get prestataireAccess => t('prestataire_access');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['fr', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
