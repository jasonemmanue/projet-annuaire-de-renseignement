# CLAUDE.md — ImmoConnect / SGK HOME

> Fichier de référence pour Claude Code. Lis-le à chaque session avant toute modification.

---

## Identité du projet

**App :** immoconnect (titre affiché « SGK HOME »)  
**Domaine :** Petites annonces immobilières au Cameroun  
**Stack :** Flutter + Firebase (Auth, Firestore, Storage, Messaging, Analytics) + Google Maps + Provider

---

## Architecture (ne jamais casser l'existant)

| Couche | Chemin | Notes |
|---|---|---|
| Point d'entrée | `lib/main.dart` | MaterialApp → SplashScreen → MainNavigationScreen |
| Navigation | `MainNavigationScreen` (IndexedStack) + `MainBottomNav` | 4 onglets selon le rôle |
| Rôles | `lib/models/user_model.dart` | `UserRole { client, prestataire, admin }` |
| Thème & langue | `lib/app_controller.dart` | Singleton, `loadPrefs()` appelé dans `main()` |
| Thème | `lib/theme/app_theme.dart` | `AppTheme.lightTheme/darkTheme`, `AppColors`, `AppTextStyles` |
| i18n | `lib/l10n/app_localizations.dart` | `AppLocalizations.of(context).t('cle')` |
| Strings FR | `lib/l10n/app_fr.dart` | `frStrings` |
| Strings EN | `lib/l10n/app_en.dart` | `enStrings` |
| Services | `lib/services/` | Voir liste ci-dessous |
| Écrans | `lib/screens/` | Voir liste ci-dessous |
| Modèles | `lib/models/models.dart` | `Logement`, `Message`, `Conversation`, `FiltreRecherche` |
| Widgets partagés | `lib/widgets/shared_widgets.dart` | `MainBottomNav`, `AppSearchBar`, etc. |
| Sélecteur opérateur | `lib/widgets/operateur_selector.dart` | Orange / MTN, préfixe +237 |

### Services existants
`auth_service`, `messagerie_service`, `paiement_service`, `notification_service`,
`logement_service`, `favoris_service`, `storage_service`, `geolocation_service`,
`analytics_service`, `cache_service`, `tarification_service`, `ads_service`

### Écrans existants
`splash`, `accueil`, `carte`, `favoris`, `messagerie`, `profil`, `detail_logement`,
`dashboard_prestataire`, `admin_panel`, `urgence`, `sponsorisation`, `paiement_premium`,
`visitor_onboarding`, `auth/login_screen`, `auth/diag_otp_screen`

---

## Champs Logement clés
`estVerifie`, `estSponsorie`, `latitude`, `longitude`, `typeBien`, `grade`,
`photos`, `prix`, `ville`, `quartier`, `nbVues`

---

## Règles de travail OBLIGATOIRES

1. **Plan avant code** : lire les fichiers concernés, expliquer le plan en 3-5 lignes.
   Attendre « go » pour les changements lourds (auth, migration, suppression).
   Pour les changements simples, appliquer directement puis résumer.

2. **AppColors / AppTextStyles / AppLocalizations** : aucune couleur ni texte « en dur ».
   Toujours passer par les tokens de thème et les clés i18n.

3. **Null-safety** : ne pas introduire de nouvelle dépendance sans le signaler
   et l'ajouter proprement dans `pubspec.yaml`.

4. **`flutter analyze`** après chaque tâche — corriger tout warning introduit.
   Ne jamais supprimer un fichier sans demander.

5. **i18n bilingue** : toujours ajouter la traduction anglaise dans `enStrings`
   en même temps que la clé dans `frStrings`.

---

## Paiements

- Flag global `kSimulationPaiement` dans `paiement_service.dart`.
- Widget de sélection : `lib/widgets/operateur_selector.dart` (Orange / MTN, +237).
- Les méthodes de paiement acceptent un paramètre `channel` (`'orange'` | `'mtn'`).
- GeniusPay = nom du backend de paiement, ne pas l'afficher dans l'UI (remplacer par « Paiement Mobile Money sécurisé »).

---

## Authentification

- Flux : Firebase Phone Auth (OTP SMS), 2 étapes (numéro → code à 6 chiffres).
- Pas d'email ni de mot de passe dans l'UI.
- Anti-brute-force via `SharedPreferences` (3 tentatives → 30 s, 5 → 5 min).

---

## Fichiers à consulter en priorité

```
lib/main.dart                         # Flux démarrage, routes, navigation
lib/app_controller.dart               # Thème + langue + persistance
lib/theme/app_theme.dart              # AppColors, AppTextStyles, extensions
lib/l10n/app_fr.dart                  # frStrings (source de vérité i18n)
lib/l10n/app_en.dart                  # enStrings (traductions anglaises)
lib/models/models.dart                # Logement + autres modèles
lib/models/user_model.dart            # Utilisateur, UserRole
lib/services/auth_service.dart        # Authentification OTP
lib/services/logement_service.dart    # Requêtes Firestore logements
lib/widgets/operateur_selector.dart   # Sélecteur Orange/MTN
```

---

## Backlog des fonctionnalités

Voir `PROMPTS_RESTANTS.md` pour les prompts exacts des fonctionnalités à implémenter.
