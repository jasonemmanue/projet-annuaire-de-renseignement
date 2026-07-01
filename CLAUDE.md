# CLAUDE.md — Horem+ / Horem+

> Fichier de référence pour Claude Code. Lis-le à chaque session avant toute modification.

---

## Identité du projet

**App :** horem_plus (titre affiché « Horem+ »)  
**Domaine :** Petites annonces immobilières + services au Cameroun  
**Stack :** Flutter + Firebase (Auth, Firestore, Storage, Messaging, Analytics) + Google Maps + Provider  
**Package ID Android :** `com.example.horemplus`

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

> ⚠️ `ads_service` existe encore dans le code mais est **désactivé côté visiteur** (AdMob retiré).
> `shared_widgets.dart` → `PubliciteBanner` retourne `SizedBox.shrink()`.
> `main.dart` → `AdsService.instance.initialize()` commenté.

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
estVerifie, estSponsorie, disponible, latitude, longitude,
typeBien, grade, photos, prix, ville, quartier, nbVues,
prestatireId, prestatireNom, prestatirePhone,   ← contact prestataire (rempli à la publication)
joursGarde: List<String>,                        ← pour pharmacies / services
heureOuverture, heureFermeture,                  ← pour pharmacies / services
visibiliteExpiry: Timestamp,                     ← date expiration visibilité annuelle
publicationExpiry: Timestamp,                    ← date expiration publication standard (30 jours)
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
Remplace l'ancienne commission variable. Sélectionné via `_DureeSponsoringSheet` dans `dashboard_prestataire_screen.dart`.

| Code | Durée | Prix |
|------|-------|------|
| `1s` | 1 semaine | **500 XAF** |
| `2s` | 2 semaines | **1 000 XAF** |
| `1m` | 1 mois | **2 000 XAF** |

Défini dans `TarificationService.optionsSponsoring` (`lib/services/tarification_service.dart`).

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

### ④ Ancienne grille commission (OBSOLÈTE, conservée dans le code pour référence)
`TarificationService.montantSponsorisation()` existe encore mais n'est plus utilisé pour les nouvelles publications.

---

## Publicités prestataires — flux complet

### Côté prestataire (`dashboard_prestataire_screen.dart` → onglet Mes Publicités)
1. Prestataire crée une pub (titre + description + photos/vidéo) via `PublierPubliciteScreen`.
2. `PubliciteService.creerBrouillon()` crée le document Firestore : `actif: false, paymentPending: true`.
3. L'écran de paiement est ouvert (500 XAF / 4 jours).
4. Le webhook GeniusPay (`appliquerTransactionReussie`) fixe :
   `actif: true, paymentPending: false, expiresAt: now + 4 jours`.
5. Le prestataire peut modifier le texte (gratuit) ou re-diffuser (nouveau paiement requis).

### Côté visiteur (`main.dart` + `stories_publicites_overlay.dart`)
- Au démarrage de l'app (après auth), `ouvrirStoriesPublicites()` est appelé automatiquement.
- `PubliciteService.watchPublicitesDiffusables()` retourne les pubs où `actif: true` et `expiresAt > now`.
- `StoriesPublicitesOverlay` les affiche en plein écran, style stories Instagram.
- Le visiteur peut appuyer pour contacter le prestataire directement depuis l'overlay.

---

## Paiements — Architecture complète

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
**Chemin local :** `C:\Users\hp\StudioProjects\Immoconnect_admin`  
**Stack :** Next.js 14 + TypeScript + Tailwind + Firebase Firestore/Auth  
**Déploiement cible :** Railway (`railway.app`)

Pages disponibles :
- `/dashboard` — statistiques globales
- `/dashboard/annonces` — modération annonces (valider, rejeter, sponsoriser)
- `/dashboard/notifications` — nouvelles publications prestataires (depuis `admin_notifications`)
- `/dashboard/utilisateurs` — liste utilisateurs
- `/dashboard/transactions` — historique paiements
- `/dashboard/conversations` — messagerie
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
# Déployer les Cloud Functions (depuis le dossier racine)
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"   # si proxy corporate
firebase deploy --only functions

# Mettre à jour un secret
echo "valeur" | firebase functions:secrets:set NOM_SECRET

# Analyser le code Flutter
flutter analyze lib

# Build APK release
flutter build apk --release
# APK : build/app/outputs/flutter-apk/app-release.apk

# Push admin vers GitHub
cd C:\Users\hp\StudioProjects\Immoconnect_admin
git add -A && git commit -m "..." && git push
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
| Dashboard prestataire | Profil + onglets + cards annonces | Cards opaques, "aucune annonce" en blanc |
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

## Backlog des fonctionnalités

Voir `PROMPTS_RESTANTS.md` pour les prompts exacts des fonctionnalités à implémenter.
