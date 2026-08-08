# CLAUDE.md — Horem+ / Horem+

> Fichier de référence pour Claude Code. Lis-le à chaque session avant toute modification.

---

## Identité du projet

**App :** horem_plus (titre affiché « Horem+ »)  
**Domaine :** Petites annonces immobilières + services au Cameroun  
**Stack :** Flutter + Firebase (Auth, Firestore, Storage, Messaging, Analytics) + Google Maps + Provider  
**Bundle ID (iOS + Android) :** `com.horemplus.app`

> ⚠️ L'ancien identifiant `com.example.*` a été abandonné : Google Play **refuse l'upload**
> de tout package commençant par `com.example`, et Apple rejette le bundle correspondant.
> Les deux plateformes utilisent désormais le même identifiant `com.horemplus.app`.
> Toute modification impose de réenregistrer les apps dans la console Firebase
> (`google-services.json` + `GoogleService-Info.plist`) — voir « Identité de l'app ».

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
`analytics_service`, `cache_service`, `tarification_service`,
`publicite_service`, `rating_service`

> AdMob a été entièrement retiré : plus de dépendance `google_mobile_ads`, plus de
> service `ads_service`, plus d'appel dans `main.dart`.
> `shared_widgets.dart` → `PubliciteBanner` affiche une publicité prestataire inline (remplace AdMob).

### Écrans existants
`splash`, `accueil`, `carte`, `favoris`, `messagerie`, `profil`, `detail_logement`,
`dashboard_prestataire`, `admin_panel`, `urgence`, `sponsorisation`,
`paiement_publication_screen`, `publier_publicite_screen`, `aide_faq_screen`,
`visitor_onboarding`, `auth/login_screen`, `auth/diag_otp_screen`,
`screens/legal/` (cgu_screen, politique_screen, consentement_screen)

### Widgets clés
- `stories_publicites_overlay` — overlay Instagram-style sur l'accueil visiteur, affiche les pubs actives
- `operateur_selector` — sélecteur Orange / MTN utilisé sur tous les écrans de paiement

---

## Champs Logement clés (Firestore `logements`)

```
estVerifie, estSponsorie, disponible, visibleAdmin, latitude, longitude,
typeBien, grade, photos, prix, ville, quartier, nbVues,
prestatireId, prestatireNom, prestatirePhone,   ← contact prestataire (rempli à la publication)
joursGarde: List<String>,                        ← pour pharmacies / services
heureOuverture, heureFermeture,                  ← pour pharmacies / services
visibiliteExpiry: Timestamp,                     ← date expiration visibilité annuelle
publicationExpiry: Timestamp,                    ← date expiration publication standard (30 jours)
visibleAdmin: bool,                               ← admin doit autoriser avant que prestataire puisse rendre visible
uid_prestataire                                  ← id Firebase Auth du prestataire
```

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

## Tarification des annonces

### ① Sponsoring immobilier — tarif FIXE par durée
Remplace l'ancienne commission variable. Sélectionné dans `sponsorisation_screen.dart`.

| Code | Durée | Prix |
|------|-------|------|
| `1s` | 1 semaine | **500 XAF** |
| `2s` | 2 semaines | **1 000 XAF** |
| `1m` | 1 mois | **2 000 XAF** |

Défini dans `TarificationService` (`lib/services/tarification_service.dart`) —
**source unique**, consommée par `sponsorisation_screen.dart` :

| Constante | Usage |
|---|---|
| `tarifsSponsoring` | montant facturé (`_montant`) |
| `dureeJoursSponsoring` | durée appliquée en compte gratuit |
| `optionsSponsoring` | liste affichée dans le sélecteur |

> Les badges « Recommandé » / « Meilleure valeur » restent dans l'écran
> (`_badgesSponsoring`, clés i18n) : c'est de la décoration, pas de la tarification.
> Ne jamais recopier la grille dans un écran — une copie locale se désynchronise
> sans erreur, et c'est l'ancien prix qui continue d'être facturé.

### ② Visibilité annuelle (services uniquement)
Payant UNE FOIS par an. Types éligibles :

| Type | Prix annuel |
|------|-------------|
| Entreprise | 3 000 XAF |
| Restaurant / Snack | 2 000 XAF |
| École | 1 000 XAF |

Pharmacie : **gratuite** (pas de prix). `_isPharmacieType` masque le champ prix et le paiement.

### ③ Publicités prestataires
500 XAF / 4 jours de diffusion (`PubliciteService.montantParPeriode` = 500, `dureeJours` = 4).

### ④ Ancienne grille commission (SUPPRIMÉE)
La commission variable par grade a été retirée du code : `enum GradeBien`,
`extension GradeBienLabel`, `pourcentageCommission()`, `montantSponsorisation()`
et `fraisUrgence()` n'avaient plus aucun appelant depuis le passage aux forfaits fixes.

Le champ Firestore `grade` reste un `String` libre sur `Logement`
(`'standards' | 'haut_standing' | 'meubles' | 'a_louer'`) — il n'a jamais été typé
par l'enum côté Dart, donc rien à migrer.

> `functions/index.js` conserve sa **propre** fonction `fraisUrgence(grade, typeBien)`,
> indépendante du Dart. La suppression côté app ne l'affecte pas.

---

## Publicités prestataires — flux complet

### Côté prestataire (`dashboard_prestataire_screen.dart` → onglet Mes Publicités)
1. Prestataire crée une pub (titre + description + photos/vidéo) via `PublierPubliciteScreen`.
2. `PubliciteService.creerBrouillon()` crée le document Firestore : `actif: false, paymentPending: true`.
3. L'écran de paiement est ouvert (500 XAF / 4 jours).
4. Le webhook GeniusPay (`appliquerTransactionReussie`) fixe :
   `actif: true, paymentPending: false, expiresAt: now + 4 jours`.
5. Le prestataire peut modifier le texte (gratuit) ou re-diffuser (nouveau paiement requis).

### Côté visiteur — 3 formats d'affichage

| Format | Widget | Emplacement | Déclenchement |
|--------|--------|-------------|---------------|
| **Stories plein écran** | `StoriesPublicitesOverlay` | Overlay modal | Auto (toutes les 3 nav / 4 reprises), tap sur bannière |
| **Carrousel horizontal** | `PublicitePrestataireBanner` | Accueil (sliver unique) | Toujours visible si pubs actives |
| **Cartes inline** | `PubliciteBanner` | Intercalées dans les listes (tous les 5-6 logements) | Automatique, rotation des pubs |

#### `StoriesPublicitesOverlay` (stories_publicites_overlay.dart)
- `ouvrirStoriesPublicites()` appelé automatiquement + au tap sur les autres formats.
- `PubliciteService.watchPublicitesDiffusables()` retourne les pubs `actif: true` et `expiresAt > now`.
- Affichage plein écran, style stories Instagram. Bouton "Contacter" ouvre le chat.

#### `PublicitePrestataireBanner` (shared_widgets.dart)
- Carrousel horizontal auto-scroll (5s) avec jusqu'à 6 previews photo/vidéo.
- Header "Services en vedette" + lien "Voir tout".

#### `PubliciteBanner` (shared_widgets.dart) — remplace AdMob
- Carte compacte avec photo (72px), titre, description (2 lignes), avatar prestataire, bouton "Voir".
- Label "SPONSORISE" en haut pour identifier clairement comme contenu payant.
- Cache global statique : un seul stream Firestore partagé entre toutes les instances.
- Rotation round-robin : chaque instance affiche une pub differente via `_nextIndex`.
- Tap ouvre `StoriesPublicitesOverlay`.
- Rend `SizedBox.shrink()` si aucune pub active (pas d'espace vide).

---

## Paiements iOS — flow email + page web (App Store 3.1.1)

> ⚠️ **CRITIQUE** : sur iOS, **aucun paiement dans l'app**. Aucun prix, aucune mention "XAF", aucun sélecteur opérateur. Sinon rejet App Store guideline 3.1.1 (external payment methods for digital goods).

### Séparation par plateforme

| Plateforme | Flux |
|------------|------|
| **Android** | Paiement intégré via WebView silencieux + GeniusPay (inchangé) |
| **iOS** | 1) L'app demande l'email · 2) Backend envoie un lien HTML · 3) L'utilisateur paie sur la page web `sgk-home.web.app/pay/<token>` · 4) Le webhook active le service |

### Détection dans le code Flutter
`isExternalActivationRequired` (dans `lib/screens/ios_activation_email_screen.dart`) → `Platform.isIOS`.
Chaque écran de paiement contient un branchement `if (isExternalActivationRequired) { push IosActivationEmailScreen }` :
- `SponsorisationScreen._payer()` : après choix durée
- `PaiementPublicationScreen.initState()` : avant tout affichage
- `PaiementPremiumScreen.initState()` : avant tout affichage
- `UrgenceScreen._FormulaireAlerteScreen._validerEtPayer()` : après validation formulaire
- `PublierPubliciteScreen` → délègue à `PaiementPublicationScreen` (intercepté)

### Sélecteur opérateur + prix affichés
Wrapper avec `if (!isExternalActivationRequired)` dans :
- `SponsorisationScreen` : sélecteur durée (prix XAF), sélecteur opérateur, bouton "Payer X XAF"
- `UrgenceScreen` : sélecteur opérateur, bouton "Payer 200 XAF"
- `dashboard_prestataire_screen.dart` : sélecteur durée hébergement, dialog réactivation

### Écran unique iOS
`lib/screens/ios_activation_email_screen.dart` — formulaire email + confirmation "Vérifiez votre boîte mail". Ne mentionne jamais prix, XAF, Mobile Money, MTN/Orange, GeniusPay.

### Service Flutter
`lib/services/activation_email_service.dart` :
```dart
ActivationEmailService.instance.envoyerLien(
  type: ActivationType.sponsorisation,
  email: 'user@example.com',
  targetId: logementId,
  params: {'duree': '1m', 'titre': 'Studio Bastos'},
);
```

### Cloud Functions Firebase

| Fonction | URL | Rôle |
|---|---|---|
| `envoyerLienPaiementEmail` | `https://envoyerlienpaiementemail-qhxw7o6nha-uc.a.run.app` | Génère token, crée doc Firestore, envoie email HTML |
| `initierPaiementDepuisWeb` | `https://initierpaiementdepuisweb-qhxw7o6nha-uc.a.run.app` | Appelée par la page web /pay/[token] pour lancer GeniusPay |

Le webhook `geniuspayWebhook` détecte la transaction par son `paymentToken` et met à jour `paiements_web/<token>.statut` = `reussi` / `echoue` en plus de l'activation métier normale.

### Collection Firestore `paiements_web`

```json
{
  "token": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",  // 128 bits hex
  "uid": "prestataire_uid",
  "type": "sponsorisation",   // premium | publication | sponsorisation | publicite | urgence | visibilite
  "targetId": "logement_id",
  "params": { "duree": "1m", "titre": "..." },
  "montant": 2000,
  "libelle": "Mise en avant (1 mois)",
  "description": "Mise en avant de « Studio Bastos » pendant 1 mois",
  "email": "user@example.com",
  "statut": "en_attente",     // en_attente | initie | reussi | echoue | expire
  "createdAt": "Timestamp",
  "expiresAt": "Timestamp",   // now + 24h
  "reference": "MTX-...",     // rempli quand initie
  "checkoutUrl": "https://...",
  "confirmedAt": "Timestamp"  // rempli quand reussi/echoue
}
```

### Page web `/pay/[token]` (Immoconnect_admin)
- Fichier : `Immoconnect_admin/app/pay/[token]/page.tsx`
- Route publique (pas dans `/dashboard/`, pas d'auth admin)
- Charge Firestore `paiements_web/<token>` en snapshot temps réel
- Formulaire : opérateur (Orange/MTN) + numéro +237
- Appelle `initierPaiementDepuisWeb` → GeniusPay → USSD PIN
- Détecte succès/échec via le snapshot Firestore (webhook backend)
- URL prod : `https://immoconnect-admin.up.railway.app/pay/<token>` (variable env `WEB_PAY_BASE_URL` côté functions)

### Template email Nodemailer
Fonction `buildPaymentLinkEmailHtml()` dans `functions/index.js` — HTML sobre : en-tête bleu Horem+, description du service, bouton d'action orange, footer légal, lien fallback.

### Comptes gratuits (compteGratuit)
Le flow iOS s'applique à tous les prestataires SAUF les comptes gratuits. `SponsorisationScreen` teste `widget.compteGratuit` avant redirect email (bypass total).

---

## Paiements — Architecture complète (Android)

### Acteurs de la chaîne de paiement

```
Utilisateur (téléphone Cameroun)
    │
    ▼
App Flutter  ──── HTTPS ────►  Cloud Function (Firebase)
                                    │
                                    ▼
                              GeniusPay API (geniuspay.ci)
                                    │  orchestrateur ivoirien
                                    ▼
                              PawaPay  (agrégateur africain)
                                    │
                          ┌─────────┴──────────┐
                          ▼                    ▼
                   MTN Mobile Money      Orange Money
                   Cameroun (XAF)        Cameroun (XAF)
```

### Pourquoi GeniusPay et pas un opérateur direct ?

GeniusPay est un agrégateur de paiement ivoirien (`geniuspay.ci`) qui expose une API unifiée vers PawaPay, lui-même agrégateur multi-pays. Cela permet d'atteindre MTN et Orange Cameroun via une seule intégration.

**⚠️ Règle absolue : ne jamais afficher « GeniusPay » dans l'UI.** Afficher uniquement « Paiement Mobile Money sécurisé ».

### Devise : XOF obligatoire (pas XAF)

GeniusPay est ivoirien → son API n'accepte que `XOF` (Franc CFA BCEAO, zone Afrique de l'Ouest).  
Le Cameroun utilise `XAF` (Franc CFA BEAC, zone Afrique Centrale).  
**Ces deux devises ont exactement le même taux de change** (1 XOF = 1 XAF = 1/655,957 EUR).  
PawaPay gère la conversion interne : on envoie 500 XOF, le client voit 500 XAF sur son téléphone.

```js
// functions/index.js
const DEVISE = "XOF";  // ← obligatoire pour l'API GeniusPay, pas XAF
```

```dart
// paiement_service.dart — mapping opérateurs vers codes PawaPay
'orange' → 'orange_money_cm'   // Orange Money Cameroun
'mtn'    → 'mtn_momo_cm'       // MTN Mobile Money Cameroun
```

### Mécanisme USSD push — WebView INVISIBLE (100% silencieux)

**Réalité technique vérifiée en production :** la création d'un paiement côté Cloud Function ne déclenche PAS l'USSD push toute seule. Une visite HTTP avec exécution du JavaScript de la page `paymentUrl` (= `checkoutUrl`) est nécessaire pour que GeniusPay pousse l'ordre à PawaPay.

**Stratégie utilisée dans l'app (invisible pour l'utilisateur) :**

```
1. App Flutter → Cloud Function → GeniusPay createPayment()
   ↳ GeniusPay réserve la transaction, renvoie { reference, paymentUrl }.

2. Un WebView invisible (SilentPaymentWebView) est monté dans le Stack
   du body dès que _etape passe à attente.
   ↳ Position : Positioned(top: 0, left: 0), 1×1 px, opacity 0.
   ↳ Le WebView charge paymentUrl et exécute le JavaScript comme
     un vrai navigateur Chrome mobile.
   ↳ Le JS de la page GeniusPay contacte PawaPay → USSD envoyé.
   ↳ Menu PIN Mobile Money s'ouvre sur le téléphone du client.
   ↳ L'utilisateur ne voit RIEN — il reste sur l'écran d'attente Flutter.

3. Écran d'attente Flutter s'affiche pendant que le client tape son PIN.

4. Client tape son PIN → PawaPay → GeniusPay → webhook Firebase.
   Firestore mis à jour → watchStatut() détecte → écran de succès ✅

5. Fallback : si après 15 secondes le statut est toujours en attente
   (le WebView n'a pas suffi — cas rarissime), l'app ouvre alors la page
   GeniusPay dans le navigateur externe (comportement classique visible).
```

**Widget :** `lib/widgets/silent_payment_webview.dart` — WebView monté mais invisible :
- `webview_flutter: ^4.10.0` (dépendance ajoutée dans pubspec)
- `JavaScriptMode.unrestricted` (obligatoire pour que la page GeniusPay tourne)
- User-Agent Chrome Android mobile
- Rendu : `IgnorePointer` + `Opacity(0)` + `SizedBox(1×1)` → invisible mais monté (le JS s'exécute)

**Pourquoi pas `Offstage(offstage: true)` ?** Flutter peut alors arrêter d'exécuter les frames du WebView, ce qui bloque l'exécution du JavaScript. Il faut que le WebView soit dans l'arbre visible mais transparent.

**Flags de l'écran de paiement :**
- `_checkoutUrl` : mémorisé après initiation, déclenche le montage du WebView
- `_fallbackLance` : garde-fou pour ne pas ouvrir le navigateur deux fois

**Fichiers concernés (4 écrans) :**
- `paiement_publication_screen.dart` (sponsoring + pub + visibilité)
- `urgence_screen.dart` (alerte prioritaire visiteur)
- `sponsorisation_screen.dart`
- `paiement_premium_screen.dart`

> ⚠️ **Ne jamais supprimer le WebView invisible ni le fallback `launchUrl` à T+15s.**  
> Le WebView est ce qui rend le paiement 100% silencieux. Le fallback est le filet de sécurité si jamais le WebView ne peut pas se charger (pas de connexion Chrome WebView installé, etc.).

### Flux de paiement étape par étape

```
Flutter                     Cloud Function              GeniusPay/PawaPay
  │                               │                           │
  │  POST /initierXxx             │                           │
  │  { telephone, operateur,      │                           │
  │    logementId, duree, ... }   │                           │
  │──────────────────────────────►│                           │
  │                               │  createPayment(XOF)       │
  │                               │──────────────────────────►│
  │                               │                           │ USSD push
  │                               │                           │────────► téléphone client
  │                               │  { reference, paymentUrl }│         (menu PIN s'ouvre)
  │                               │◄──────────────────────────│
  │                               │                           │
  │  { success, reference }       │                           │
  │◄──────────────────────────────│                           │
  │                               │                           │
  │  → _etape = attente           │          [client tape PIN] │
  │  → polling toutes les 5s      │                           │
  │                               │                           │
  │  POST /verifierPaiement       │                           │
  │──────────────────────────────►│                           │
  │  { statut: 'en_attente' }     │                           │
  │◄──────────────────────────────│           Webhook POST    │
  │                               │◄──────────────────────────│
  │                               │  appliquerTransactionReussie()
  │  Firestore update             │  met à jour Firestore     │
  │  (watchStatut stream)         │                           │
  │◄ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │                           │
  │                               │                           │
  │  → _etape = succes ✅         │                           │
```

### Fichiers Flutter impliqués

| Fichier | Rôle |
|---------|------|
| `lib/widgets/operateur_selector.dart` | Sélecteur Orange / MTN + numéro +237 |
| `lib/screens/paiement_publication_screen.dart` | Écran de paiement réutilisable (sponsoring, pub, visibilité) |
| `lib/screens/urgence_screen.dart` | Alerte prioritaire visiteur (formulaire + CRUD + paiement 200 XAF/48H) |
| `lib/screens/sponsorisation_screen.dart` | Ancien écran sponsoring (conservé) |
| `lib/screens/paiement_premium_screen.dart` | Paiement abonnement premium |
| `lib/services/paiement_service.dart` | Appels Cloud Functions + polling statut |
| `lib/services/paiement_debug_log.dart` | Panneau de logs diagnostic (visible si `kDebugPaiement = true`) |

### Règles de code anti-régression

```dart
// ✅ CORRECT — après initiation : juste mémoriser checkoutUrl, le WebView
// invisible du body Stack s'occupe du reste automatiquement.
_reference = result.reference;
_checkoutUrl = result.checkoutUrl;
setState(() { _etape = _Etape.attente; });
_demarrerAttente(); // watchStatut + poll 5s + fallback launchUrl à T+15s

// Dans build() du body — WebView invisible qui déclenche l'USSD :
Stack(children: [
  if (_checkoutUrl != null && _etape == _Etape.attente)
    Positioned(
      top: 0, left: 0,
      child: SilentPaymentWebView(url: _checkoutUrl!),
    ),
  // ... contenu normal
])

// ❌ INTERDIT :
// - Supprimer SilentPaymentWebView du Stack → USSD ne part pas.
// - Supprimer le fallback launchUrl → blocage total si WebView échoue.
// - Utiliser Offstage(offstage: true) → arrête l'exécution du JS.
```

### Mode simulation (tests sans vrai paiement)

```dart
// paiement_service.dart — ligne 9
const bool kSimulationPaiement = false;  // passer à true pour les tests

// En kDebugMode (flutter run), la simulation est automatique
bool get _simulation => kSimulationPaiement || kDebugMode;
```

En simulation : la Cloud Function n'est pas appelée, Firestore est mis à jour directement côté Flutter, et un statut `reussi` est émis après 4 secondes.

### Auth API GeniusPay

```
Headers → X-API-Key: <GENIUSPAY_API_KEY>
           X-API-Secret: <GENIUSPAY_SECRET_KEY>
// PAS de "Authorization: Bearer ..." — c'est différent de Firebase Auth
```

### Frais réels GeniusPay/PawaPay (ne pas afficher dans l'UI)

```
Net reçu = montant × 0,955 − 100 XOF
           └── PawaPay 3,5% ──┘ └── GeniusPay : 100 fixe + 1% ──┘
```

| Montant envoyé | Frais total | **Net reçu** |
|----------------|-------------|--------------|
| 200 XAF | 109 XAF | **91 XAF** |
| 500 XAF | 123 XAF | **377 XAF** |
| 1 000 XAF | 145 XAF | **855 XAF** |
| 2 000 XAF | 190 XAF | **1 810 XAF** |
| 3 000 XAF | 235 XAF | **2 765 XAF** |
| 45 000 XAF | 2 125 XAF | **42 875 XAF** |

> Le forfait fixe de 100 XAF est très pénalisant sur les petits montants. Ne pas descendre sous **500 XAF** par transaction.

---

## Cloud Functions Firebase (`functions/index.js`)

Déployées sur `us-central1`, projet `sgk-home`. URLs Cloud Run :

| Fonction | URL | Usage |
|---|---|---|
| `initierSponsorisation` | `https://initiersponsorisation-qhxw7o6nha-uc.a.run.app` | Lance paiement sponsoring |
| `initierPaiementPublicite` | `https://initierpaiementpublicite-qhxw7o6nha-uc.a.run.app` | Lance paiement pub |
| `initierVisibilite` | `https://initiervisibilite-qhxw7o6nha-uc.a.run.app` | Lance paiement visibilité annuelle |
| `initierUrgence` | `https://initierurgence-qhxw7o6nha-uc.a.run.app` | Lance paiement urgence visiteur |
| `geniuspayWebhook` | `https://geniuspaywebhook-qhxw7o6nha-uc.a.run.app` | Webhook GeniusPay (paiements reçus) |
| `verifierPaiement` | `https://verifierpaiement-qhxw7o6nha-uc.a.run.app` | Polling statut paiement |
| `envoyerNotifGlobale` | `https://envoyernotifglobale-qhxw7o6nha-uc.a.run.app` | Notif push tous les users |
| `envoyerLienPaiementEmail` | `https://envoyerlienpaiementemail-qhxw7o6nha-uc.a.run.app` | iOS : envoie email avec lien de paiement web |
| `initierPaiementDepuisWeb` | `https://initierpaiementdepuisweb-qhxw7o6nha-uc.a.run.app` | iOS : appelée par la page web /pay/[token] |

### Secrets Firebase (Secret Manager)
- `GENIUSPAY_API_KEY` / `GENIUSPAY_SECRET_KEY` / `GENIUSPAY_WEBHOOK_SECRET` — sur toutes les fonctions paiement
- `GMAIL_SENDER_EMAIL` / `GMAIL_APP_PASSWORD` — sur `geniuspayWebhook` (pour emails admin)

> ⚠️ Les secrets Gmail sont des **placeholders** à remplacer par un vrai compte Gmail + App Password Google.
> Commande : `echo "adresse@gmail.com" | firebase functions:secrets:set GMAIL_SENDER_EMAIL`

### Webhook `appliquerTransactionReussie`
Gère tous les types de paiement via le champ `tx.type` :
- `'sponsorisation'` → `disponible: true`, `estSponsorie: true`, expiry selon `tx.duree` (`1s`/`2s`/`1m`)
- `'publicite'` → `actif: true`, expiry + 4 jours
- `'visibilite'` → `visibiliteExpiry: now + 365 jours`
- `'urgence'` → active l'alerte prioritaire visiteur pendant 48h

**Admin notifications** : à chaque paiement réussi (sauf urgence), le webhook :
1. Envoie un email HTML à `Horem+49@gmail.com` (Nodemailer + Gmail SMTP)
2. Crée un document dans `admin_notifications` Firestore

---

## Notifications admin (`admin_notifications` Firestore)

Structure d'un document :
```json
{
  "type": "sponsorisation",
  "logementId": "...",
  "titre": "Chambre à louer Bastos",
  "typeBien": "Chambre",
  "ville": "Yaoundé",
  "quartier": "Bastos",
  "latitude": 3.87,
  "longitude": 11.52,
  "prestatireNom": "Jean Dupont",
  "prestatirePhone": "+237612345678",
  "uid_prestataire": "uid...",
  "createdAt": Timestamp,
  "lu": false
}
```

---

## Authentification

- Flux : Firebase Phone Auth (OTP SMS), 2 étapes (numéro → code à 6 chiffres).
- Pas d'email ni de mot de passe dans l'UI.
- Anti-brute-force via `SharedPreferences` (3 tentatives → 30 s, 5 → 5 min).

---

## Panneau Admin Flutter (`lib/screens/admin_panel_screen.dart`)

Accessible uniquement aux utilisateurs avec `role == 'admin'` dans Firestore.

---

## Dashboard Admin Web (Next.js)

**Repo :** `https://github.com/jasonemmanue/Horem-a-ADMIN.git`  
**Stack :** Next.js 14 + TypeScript + Tailwind + Firebase Firestore/Auth  
**Déploiement cible :** Railway (`railway.app`)

Pages disponibles :
- `/dashboard` — statistiques globales (inclut compteur alertes urgence actives)
- `/dashboard/annonces` — modération annonces (valider, rejeter, sponsoriser)
- `/dashboard/notifications` — nouvelles publications prestataires (depuis `admin_notifications`)
- `/dashboard/utilisateurs` — liste utilisateurs
- `/dashboard/transactions` — historique paiements (inclut type `urgence`)
- `/dashboard/conversations` — messagerie
- `/dashboard/urgences` — alertes prioritaires visiteurs (statut, budget, type, expiration)
- `/dashboard/signalements` — signalements
- `/dashboard/spots` — publicités actives

---

## Types de services (`_isServiceType`, `_isPharmacieType`, `_isVisibiliteType`)

Dans `dashboard_prestataire_screen.dart` :

| Flag | Types concernés | Comportement |
|------|----------------|--------------|
| `_isPharmacieType` | Pharmacie | Gratuit, pas de prix, jours de garde, horaires |
| `_isVisibiliteType` | Entreprise / Restaurant / École | Prix annuel fixe, horaires |
| `_isServiceType` | Pharmacie + Visibilité + Restaurant | Affiche jours + horaires |
| Immobilier | Tout le reste | Sponsoring durée fixe (500/1000/2000) |

Badge couleur (info banner) : Pharmacie=vert, Restaurant=orange, École=violet, Entreprise=bleu.

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
lib/services/paiement_service.dart    # Paiements GeniusPay, simulation, polling
lib/services/tarification_service.dart # Grilles de prix (sponsoring, visibilité, urgence)
lib/widgets/operateur_selector.dart   # Sélecteur Orange/MTN
functions/index.js                    # Toutes les Cloud Functions (déployer avec firebase deploy --only functions)
```

---

## Commandes utiles

```bash
# Analyser le code Flutter
flutter analyze lib

# Build APK release
flutter build apk --release

# Build iOS (sans signing, vérification locale)
flutter build ios --release --no-codesign

# Déployer les Cloud Functions
firebase deploy --only functions

# Mettre à jour un secret Firebase
echo "valeur" | firebase functions:secrets:set NOM_SECRET

# Déployer admin Next.js sur Railway
cd Immoconnect_admin && railway up
```

---

## Publication standard & dégradation de priorité

### Cycle de vie d'une annonce

```
Publication (paiement commission %)
    │
    ▼
  Visible 30 jours (priorité haute = 1)
    │  pharmacies = toujours actives, pas de paiement
    │
    ├── Si sponsorisée → priorité maximale (0) tant que sponsoring actif
    │
    ▼ après 30 jours
  Publication expirée → priorité basse (2)
  L'annonce reste visible mais descend dans les résultats
```

### Getters du modèle `Logement` (`models.dart`)

| Getter | Description |
|--------|-------------|
| `estPublicationActive` | `true` si pharmacie, ou si `publicationExpiry` est dans le futur (ou null) |
| `estPublicationExpiree` | `true` si `publicationExpiry` est dans le passé |
| `prioriteAffichage` | `0` = sponsorisé, `1` = publication active, `2` = expiré |
| `estVisiblePourVisiteur` | `disponible && !paymentPending` (ne masque plus les expirés) |

### Cloud Function `initierPublication`
- URL : `https://initierpublication-qhxw7o6nha-uc.a.run.app`
- Paramètres : `telephone`, `operateur`, `logementId`, `montant`
- Webhook type `'publication'` → fixe `disponible: true`, `publicationExpiry: now + 30j`, supprime `paymentPending`

### Sponsorisation (séparée de la publication)
Le sponsoring ne contrôle plus `disponible` ni `paymentPending`. Il fixe uniquement :
- `isSponsored: true`, `sponsoredAt`, `sponsoredUntil` (selon durée 1s/2s/1m)

---

## Comptes gratuits (`compteGratuit`)

Un admin peut créer un compte prestataire qui utilise TOUT sans payer.

### Champ Firestore (`users`)
```
compteGratuit: bool   ← true = accès gratuit total
```

### Bypass actifs
Quand `compteGratuit == true`, tous les paiements sont bypassés :
- **Nouvelle publication** : brouillon activé directement (`disponible: true`, `publicationExpiry: +30j` ou `visibiliteExpiry: +365j`)
- **Réactivation** : `disponible: true`, `publicationExpiry: +30j` sans paiement
- **Sponsoring** : `SponsorisationScreen` affiche un formulaire gratuit → `isSponsored: true`, `sponsoredUntil` selon durée choisie
- **Publicité (nouvelle)** : brouillon activé directement (`actif: true`, `expiresAt: +4j`)
- **Publicité (réactivation)** : même bypass

### Côté admin Flutter (`admin_panel_screen.dart`)
- Badge « 🆓 Compte offert » sur la carte utilisateur
- Bouton "Accès gratuit" / "Révoquer gratuit" (toggle `compteGratuit`)
- Bouton "Créer compte gratuit" → dialog (prénom, nom, tél) → Cloud Function `creerCompteGratuit`

### Côté admin Next.js (`/dashboard/utilisateurs`)
- Badge "🆓 Offert" dans le tableau et le panneau détail
- Icône cadeau (toggle) dans les actions tableau
- Bouton "Compte gratuit" en haut → dialog création
- Filtre "🆓 Gratuit" dans les filtres

### Cloud Function `creerCompteGratuit`
- URL : `https://creercomptegratuit-qhxw7o6nha-uc.a.run.app`
- Auth : Bearer token Firebase Auth (caller must have `role == 'admin'`)
- Body : `{ telephone, nom, prenom }` (tel sans + → préfixe +237 ajouté automatiquement)
- Crée l'Auth Firebase + doc Firestore avec `compteGratuit: true`, `role: 'prestataire'`
- Si le numéro existe déjà, met à jour le doc existant

---

## Visibilité admin (`visibleAdmin`)

L'admin a la priorité sur la visibilité des annonces. Le prestataire ne peut activer `disponible` que si `visibleAdmin == true`.

### Règles par type

| Type | `visibleAdmin` à la création | Comportement |
|------|------------------------------|--------------|
| Pharmacie (gratuit) | `false` | L'admin doit approuver manuellement |
| Immobilier / Entreprise / Restaurant / École (payant) | `true` | Visible par défaut, l'admin peut bloquer |

### Getter visiteur
`estVisiblePourVisiteur = disponible && visibleAdmin && !paymentPending`

### Côté prestataire
Si `visibleAdmin == false`, le toggle `disponible` est bloqué avec un message d'erreur.
Badge orange « En attente admin » sur la carte annonce.

### Côté admin (Next.js)
Bouton shield violet dans la page annonces pour toggler `visibleAdmin`.
Badge « ⛔ Bloqué admin » / « 🛡️ Admin OK » dans le détail.

---

## Recherche par budget (accueil visiteur)

Le visiteur peut rechercher par prix en tapant un montant dans la barre de recherche.
- Exemples : « chambre 10000 », « 25k », « studio 50 000 »
- Parsing : `_extraireBudget()` dans `accueil_screen.dart`
- Formats supportés : `10000`, `10 000`, `25k`, `25K`
- Tolérance : ±10 % du montant extrait
- Combinable avec le texte (filtre type + budget simultanément)

---

## Carte — marqueurs colorés avec noms

Les marqueurs sur la carte affichent le nom de l'annonce dans une bulle colorée.
- Couleurs par type : Chambre=bleu, Studio=violet, Appartement=orange, Villa=vert foncé, etc.
- Rendu via `ui.PictureRecorder` + `Canvas` → `BitmapDescriptor`
- Cache des icônes (`_iconCache`) pour éviter la re-génération
- Construction asynchrone (`_buildMarkersAsync`)

---

## Défilement automatique des photos (détail annonce)

Pour les annonces multi-photos, les images défilent automatiquement.
- Timer : démarre 2s après ouverture, cycle toutes les 4s
- Animation : 600ms `easeInOut`
- Reset : le timer redémarre si l'utilisateur swipe manuellement
- Fichier : `detail_logement_screen.dart`

---

## Fond skyline (arrière-plan pleine page)

Widget `SkylineBackground` dans `lib/widgets/shared_widgets.dart` — fond décoratif pleine page.
- Gradient vertical pleine page (bleu nuit → bleu clair) couvrant tout l'écran
- 3 cercles décoratifs en filigrane (haut-droite, milieu-gauche, bas-droite)
- Silhouette de ville (`SkylinePainter`) en bas de page en filigrane
- Support mode clair (bleu 4 couleurs) et mode sombre (bleu nuit 3 couleurs)

| Écran | Contenu | Adaptation |
|-------|---------|------------|
| Accueil visiteur | SliverAppBar transparent, chips et cards par-dessus | Titres de section en blanc |
| Dashboard prestataire | Onglets + cards annonces | Cards opaques, "aucune annonce" en blanc |
| Profil prestataire | Sections arrondies indépendantes (88% opacité) | Titres section en blanc, pas de champ email |
| Profil visiteur | Sections arrondies indépendantes (88% opacité) | En-tête carte arrondie, bouton prestataire blanc |
| Formulaire nouvelle annonce | Card semi-transparente (88% opacité) | Labels/champs lisibles sur fond blanc |
| Détail annonce visiteur | Carrousel photos + contenu arrondi 85% opacité | Coin arrondi en haut du contenu |

> **Règle** : les cards de contenu (`cardColor`) restent opaques pour la lisibilité. Le skyline est visible dans les marges et en haut/bas de page.

---

## Jours de garde pharmacies (détail annonce)

Les jours de garde saisis lors de la publication s'affichent sous le bandeau horaires.
- Badges bleus avec icône calendrier
- Visible uniquement si `joursGarde` non vide
- Clé i18n : `detail_guard_days`

---

## Alerte prioritaire visiteur (urgence)

Le visiteur peut créer des alertes pour être notifié en premier quand un bien correspondant est publié.

### Flux
1. Bouton FAB rouge animé (pulse) en bas à droite de l'accueil visiteur → ouvre `UrgenceScreen`
2. Page avec fond skyline, question introductive, liste des alertes existantes (CRUD)
3. Formulaire : type de bien, description, fourchette de prix (min/max)
4. Paiement : **200 XAF / 48H** via Mobile Money (flux WebView silencieux)
5. Quand un nouveau logement est publié et correspond (même type + dans la fourchette de prix), le visiteur avec alerte active est notifié **immédiatement** (les autres 30 min après)
6. L'alerte expire après 48H, le visiteur peut renouveler ou en créer d'autres

### Contact prestataire
Le contact du prestataire (nom, téléphone, photo) est **toujours visible** pour tous les visiteurs sur le détail d'une annonce. L'ancien système de masquage/déblocage via paiement urgence a été supprimé.

### Firestore collection `urgences`
```json
{
  "uid": "visiteur_uid",
  "typeBien": "Studio",
  "description": "Studio meublé proche université",
  "prixMin": 15000,
  "prixMax": 30000,
  "actif": true,
  "paymentPending": false,
  "expiresAt": "Timestamp",
  "createdAt": "Timestamp"
}
```

### Modèle Flutter
`AlerteUrgence` dans `lib/models/models.dart` — getters `estActive`, `estExpiree`.

### Cloud Function — notification prioritaire
`notifierAlertesUrgence()` dans `functions/index.js` — appelée après chaque publication réussie.
Cherche les alertes actives dont `typeBien` correspond et `prixMin <= prix <= prixMax`, puis envoie une notification push immédiate aux visiteurs matching.

---

## Build & déploiement iOS — Codemagic

**Plateforme CI/CD :** Codemagic (`codemagic.io`) — Mac mini M2, Xcode latest, Flutter stable.
**Configuration :** `codemagic.yaml` à la racine du projet (mode YAML, pas Workflow Editor GUI).

### Workflow actuel : `ios-build-check`
Build iOS sans signing (vérification que le projet compile). Déclenché sur push `main`.

```yaml
# codemagic.yaml — résumé
scripts:
  - flutter pub get
  - flutter analyze lib --no-fatal-infos --no-fatal-warnings
  - cd ios && pod install
  - flutter build ios --release --no-codesign
```

### Prochaine étape : TestFlight (quand compte Apple Developer disponible)
Ajouter un workflow `ios-testflight` avec :
- Code signing automatique Codemagic (certificat + provisioning profile via intégration App Store Connect)
- `flutter build ipa --release`
- Publication automatique sur TestFlight

### Permissions iOS — Info.plist

| Clé | Valeur | Pourquoi |
|-----|--------|----------|
| `NSCameraUsageDescription` | Photos annonces/pubs | Caméra pour les photos |
| `NSPhotoLibraryUsageDescription` | Illustrer annonces/pubs | Accès galerie photos |
| `NSMicrophoneUsageDescription` | Enregistrer vidéos | Micro pour les vidéos |
| `NSLocationWhenInUseUsageDescription` | Annonces proches | Géolocalisation foreground |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Notifier proximité | Géolocalisation background |
| `LSApplicationQueriesSchemes` | `tel, mailto, https, http, whatsapp, sms` | `canLaunchUrl()` vérifie ces schémas |
| `UIBackgroundModes` | `fetch, remote-notification` | FCM notifications push en arrière-plan |
| `FirebaseAppDelegateProxyEnabled` | `false` | Contrôle manuel FCM (évite conflit swizzling) |
| `ITSAppUsesNonExemptEncryption` | `false` | Évite le formulaire export compliance App Store |

### Macros Podfile (permission_handler)

```ruby
# ios/Podfile — post_install > GCC_PREPROCESSOR_DEFINITIONS
'PERMISSION_CAMERA=1',
'PERMISSION_PHOTOS=1',
'PERMISSION_MICROPHONE=1',
'PERMISSION_LOCATION=1',
'PERMISSION_LOCATION_ALWAYS=1',
'PERMISSION_NOTIFICATIONS=1',
```

> Chaque permission utilisée via `permission_handler` **doit** avoir sa macro activée dans le Podfile, sinon le code compile mais la permission retourne toujours `denied` sur iOS.

### Fichiers iOS
| Fichier | Rôle |
|---------|------|
| `ios/Runner/Info.plist` | Permissions iOS, schemes URL, background modes |
| `ios/Runner/AppDelegate.swift` | Clé Google Maps iOS, config Firebase, delegate notifications |
| `ios/Runner/GoogleService-Info.plist` | Config Firebase iOS (dans le repo) |
| `ios/Runner/Runner.entitlements` | APNs push notifications |
| `ios/Runner/PrivacyInfo.xcprivacy` | Privacy Manifest (Xcode 16+) |
| `ios/Podfile` | CocoaPods, platform 15.0, macros permissions |
| `codemagic.yaml` | Configuration CI/CD Codemagic |

### Identité de l'app (bundle ID) — `com.horemplus.app`

Un seul identifiant partagé par les deux plateformes. Les endroits où il apparaît :

| Fichier | Clé |
|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (Debug / Release / Profile) |
| `android/app/build.gradle.kts` | `namespace` + `applicationId` |
| `android/app/src/main/kotlin/com/horemplus/app/MainActivity.kt` | `package` |
| `lib/app_identity.dart` | `AppIdentity.bundleId` — **source de vérité côté Dart** |
| `lib/firebase_options.dart` | `iosBundleId` (ios + macos) |
| `ios/Runner/GoogleService-Info.plist` | `BUNDLE_ID` — **généré par Firebase** |
| `android/app/google-services.json` | `package_name` — **généré par Firebase** |

Les deux derniers ne se modifient **jamais à la main** : ils sont téléchargés depuis la
console Firebase. Changer le bundle ID sans les regénérer casse le build Android
(`No matching client found for package name`) et l'auth iOS.

```bash
# Réenregistre les apps dans le projet Firebase existant (sgk-home)
# et réécrit les 3 fichiers de config d'un coup.
flutterfire configure --project=sgk-home \
  --ios-bundle-id=com.horemplus.app \
  --android-package-name=com.horemplus.app
```

#### `AppIdentity.appStoreId` — à renseigner après création de la fiche

`openStoreListing` (plugin `in_app_review`) attend sur iOS l'identifiant
**numérique** attribué par App Store Connect (ex. `6742891234`), pas le bundle ID.
Tant que `AppIdentity.appStoreId` vaut `''`, `RatingService.ouvrirFicheStore()`
ne tente rien sur iOS plutôt que d'ouvrir une URL invalide. Renseigner la
constante dès que la fiche existe — c'est le seul endroit à modifier.

À refaire côté consoles après tout changement d'identifiant :
- **Firebase → Android** : réenregistrer les empreintes **SHA-1 et SHA-256** du keystore
  de release, sinon Phone Auth (OTP) échoue sur Android.
- **Firebase → Cloud Messaging** : réuploader la clé d'authentification **APNs (.p8)**
  pour la nouvelle app iOS, sinon push et Phone Auth échouent sur iOS.
- **Google Cloud → API Maps iOS** : la clé de `AppDelegate.swift` est restreinte par
  bundle ID ; ajouter `com.horemplus.app` sinon la carte reste grise.

### Phone Auth iOS — transmission manuelle des push

`Info.plist` fixe `FirebaseAppDelegateProxyEnabled = false`, donc le swizzling Firebase
est désactivé. `AppDelegate.swift` **doit** transmettre lui-même :

```swift
Auth.auth().setAPNSToken(deviceToken, type: .sandbox / .prod)  // didRegisterForRemoteNotifications
Auth.auth().canHandleNotification(userInfo)                     // didReceiveRemoteNotification
```

Sans ces deux appels, le push silencieux de vérification n'atteint jamais FirebaseAuth :
l'OTP SMS n'est **jamais envoyé** sur iOS et l'app est inutilisable → rejet App Store
guideline 2.1 (App Completeness). Ne pas retirer ces overrides.

### Entitlements APNs séparés par configuration

| Configuration | Fichier | `aps-environment` |
|---|---|---|
| Debug / Profile | `ios/Runner/Runner.entitlements` | `development` |
| Release | `ios/Runner/RunnerRelease.entitlements` | `production` |

Une seule entitlement `development` pour tout casse les push en TestFlight / App Store.
À l'inverse, forcer `production` en Debug fait échouer la signature avec un profil de dev.

### iOS deployment target : 15.0
Requis par Firebase iOS SDK 11+. Configuré dans `Podfile` (`platform :ios, '15.0'`) et `project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET = 15.0`).

### Cibles : iPhone + iPad
`TARGETED_DEVICE_FAMILY = "1,2"` dans `project.pbxproj` (1 = iPhone, 2 = iPad).

---

## Backlog des fonctionnalités

Voir `PROMPTS_RESTANTS.md` pour les prompts exacts des fonctionnalités à implémenter.
