// ============================================================
// Identifiants de l'application sur les stores.
// Source de vérité unique : ne jamais réécrire un de ces
// identifiants en dur ailleurs dans le code.
// ============================================================

class AppIdentity {
  AppIdentity._();

  /// Package Android et bundle iOS — identique sur les deux plateformes.
  /// Doit rester aligné avec `applicationId` (build.gradle.kts) et
  /// `PRODUCT_BUNDLE_IDENTIFIER` (project.pbxproj).
  static const String bundleId = 'com.horemplus.app';

  /// Identifiant **numérique** attribué par App Store Connect à la création
  /// de la fiche (ex. `6742891234`). Ce n'est PAS le bundle ID.
  ///
  /// Tant que cette valeur est vide, l'app n'essaie pas d'ouvrir la fiche
  /// App Store : `openStoreListing` construirait `apps.apple.com/app/id`
  /// sans identifiant, donc une page d'erreur. À renseigner dès que la
  /// fiche existe dans App Store Connect.
  static const String appStoreId = '';

  static bool get hasAppStoreId => appStoreId.isNotEmpty;

  static Uri get playStoreUri =>
      Uri.parse('https://play.google.com/store/apps/details?id=$bundleId');

  /// `null` tant que [appStoreId] n'est pas renseigné.
  static Uri? get appStoreUri =>
      hasAppStoreId ? Uri.parse('https://apps.apple.com/app/id$appStoreId') : null;
}
