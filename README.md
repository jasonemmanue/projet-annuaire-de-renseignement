# SGK HOME — ImmoConnect

Application Flutter de petites annonces immobilières au Cameroun.

**Version :** 1.0.0+1  
**Stack :** Flutter · Firebase (Auth, Firestore, Storage, Messaging, Analytics) · Google Maps · Provider

---

## Lancer le projet

```bash
flutter pub get
flutter run
```

Prérequis : `google-services.json` présent dans `android/app/` (téléchargeable depuis la console Firebase).

---

## Architecture

```
lib/
├── main.dart                        # Point d'entrée, navigation principale
├── app_controller.dart              # Singleton thème + langue (SharedPreferences)
├── firebase_options.dart            # Config Firebase générée
├── l10n/
│   ├── app_localizations.dart       # Résolveur i18n maison
│   ├── app_fr.dart                  # Strings français
│   └── app_en.dart                  # Strings anglais
├── theme/
│   └── app_theme.dart               # AppColors, AppTextStyles, light/dark themes
├── models/
│   ├── models.dart                  # Logement, Message, Conversation, FiltreRecherche
│   └── user_model.dart              # Utilisateur, UserRole
├── services/                        # Firebase, géolocalisation, paiements…
├── screens/                         # Tous les écrans
└── widgets/                         # Widgets partagés (SearchBar, BottomNav, OperateurSelector)
```

---

## État des 26 fonctionnalités

### ✅ Implémentées

| # | Fonctionnalité | Notes |
|---|---|---|
| #3 | Authentification par OTP Firebase (téléphone) | `login_screen.dart` — flux 2 étapes, anti-brute-force |
| #19 | Connexion OTP uniquement (plus d'email/mdp) | Intégré dans `login_screen.dart` |
| #4 | Persistance paramètres profil + langue + mode sombre | `app_controller.dart` + `main.dart` |
| #8 | Traduction & mode sombre réels | `localizationsDelegates` dans `MaterialApp`, dark theme branché |
| #5 | Messagerie accessible depuis l'accueil | Icône chat dans AppBar de `accueil_screen.dart` |
| #23 | Tag des messages + photos/vidéos (prestataire) | Permissions différenciées, `replyTo`, vidéo dans `messagerie_screen.dart` |
| #16 | Photo de profil à l'inscription prestataire | Sélecteur avatar dans `login_screen.dart` |

### ❌ En attente (voir `PROMPTS_RESTANTS.md`)

| # | Fonctionnalité | Fichiers principaux |
|---|---|---|
| #6 | **Carte réelle** : filtrage rayon, cercle, >10 km, anti-chevauchement badge | `carte_screen.dart` |
| #7 | Barre de recherche réelle + autocomplétion + filtres fonctionnels | `accueil_screen.dart` |
| #9 | Notifications persistées par type + FCM topics | `profil_screen.dart`, `notification_service.dart` |
| #10 | Écran Aide & FAQ + contact email / WhatsApp | Créer `aide_faq_screen.dart` |
| #11 | CGU + Confidentialité + écran d'acceptation 1er lancement | Créer `lib/screens/legal/` |
| #12 | Widget « Noter l'application » périodique | Créer `rating_service.dart` |
| #13 | Bouton « Évaluer » → Play Store | `profil_screen.dart` |
| #14 | Version visible + bouton prestataire non-chevauchant + question | `main.dart`, `profil_screen.dart` |
| #15 | Retirer « Sans Compte » du badge Mode visiteur | `profil_screen.dart` |
| #17 | Case CGU cochable obligatoire à l'inscription | `auth/login_screen.dart` |
| #18 | Onboarding post-connexion prestataire → espace direct | Créer `prestataire_onboarding_screen.dart` |
| #20 | Prestataire : accès Notifications + Aide | `dashboard_prestataire_screen.dart` |
| #21 | Admin : validation annonces + statut « Vérifié par ImmoConnect » | `admin_panel_screen.dart`, `models.dart` |
| #22 | Retirer badges « non vérifié » / « Premium » prestataires | `profil_screen.dart`, `detail_logement_screen.dart` |
| #24 | Retirer étoiles dans le formulaire nouvelle annonce | `dashboard_prestataire_screen.dart` |
| #25 | Type de bien « Autre (préciser) » | `dashboard_prestataire_screen.dart` |
| #26 | Bannière d'avertissement si annonce non vérifiée | `detail_logement_screen.dart` |
| #1 | Choix opérateur Orange/MTN à la sponsorisation | `sponsorisation_screen.dart` |
| #2 | Retirer « GeniusPay » UI → « Paiement Mobile Money sécurisé » | `sponsorisation_screen`, `paiement_premium_screen`, `urgence_screen` |

---

## Actions manuelles requises (console)

- [ ] Firebase Auth → activer « Phone », SHA-1 + SHA-256, re-télécharger `google-services.json`, numéros de test.
- [ ] Google Cloud → activer « Maps SDK for Android » + clé dans `AndroidManifest.xml`.
- [ ] Remplacer `SUPPORT_EMAIL` et `SUPPORT_WHATSAPP` dans `aide_faq_screen.dart` (#10).
- [ ] Remplacer le texte juridique dans `politique_screen.dart` / `cgu_screen.dart` (#11).
- [ ] Confirmer `applicationId` pour Play Store (#12/#13).
- [ ] Déployer `firestore.rules` + `storage.rules` après #21 et #23.

---

## Conventions

- **Couleurs** : toujours via `AppColors` — jamais `Colors.white/black` en dur pour fond/texte.
- **Textes** : toujours via `AppLocalizations.of(context).t('cle')`.
- **Paiements** : flag `kSimulationPaiement`; widget `OperateurSelector` pour Orange/MTN.
- **Rôles** : visiteur = non connecté (`visiteur_uid` local) ; prestataire/admin = Firebase Auth.
