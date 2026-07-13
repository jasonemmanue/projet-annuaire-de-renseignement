# Guide de débogage Flutter sur iPad

## Prérequis matériel et logiciel

| Élément | Requis |
|---------|--------|
| iPad | iPadOS 16+ recommandé |
| Mac | macOS Ventura 13+ (Xcode ne tourne que sur Mac) |
| Xcode | Version 15+ (App Store gratuit) |
| Apple ID | Gratuit pour le développement, payant (99$/an) pour App Store |
| Câble | USB-C ou Lightning vers Mac |
| Flutter SDK | Installé sur le Mac |
| CocoaPods | `sudo gem install cocoapods` ou `brew install cocoapods` |

> **Windows seul ne suffit pas** pour compiler du code iOS/iPadOS. Un Mac est obligatoire pour Xcode et le toolchain Apple. Si tu n'as pas de Mac physique, voir la section "Alternatives sans Mac".

---

## Option A : Avec un Mac

### 1. Installer les outils

```bash
# Vérifier Flutter
flutter doctor

# Installer Xcode CLI tools
xcode-select --install

# Installer CocoaPods
sudo gem install cocoapods

# Accepter les licences Xcode
sudo xcodebuild -license accept
```

### 2. Préparer le projet iOS

```bash
cd /chemin/vers/app_renseignement

# Installer les dépendances iOS
cd ios
pod install
cd ..

# Vérifier que iOS est prêt
flutter doctor -v
```

### 3. Configurer le signing (Apple ID gratuit)

1. Ouvrir `ios/Runner.xcworkspace` dans Xcode
2. Sélectionner **Runner** dans le navigateur de projet
3. Onglet **Signing & Capabilities**
4. Cocher **Automatically manage signing**
5. Team → **Add Account** → connecter ton Apple ID
6. Le Bundle Identifier doit être unique (ex: `com.horemplus.app`)

### 4. Connecter l'iPad

1. Brancher l'iPad au Mac via câble USB
2. Sur l'iPad : **Réglages → Confidentialité → Mode développeur** → Activer
3. Sur l'iPad : faire confiance à l'ordinateur quand demandé
4. Vérifier la connexion :
```bash
flutter devices
# Doit afficher ton iPad dans la liste
```

### 5. Lancer l'app en mode debug

```bash
# Lancer sur l'iPad connecté
flutter run -d <device_id>

# Ou lancer avec sélection interactive
flutter run

# Hot reload : taper 'r' dans le terminal
# Hot restart : taper 'R'
# Quitter : taper 'q'
```

### 6. Déboguer avec les DevTools

```bash
# Lancer Flutter DevTools (inspecteur, profiler, réseau)
flutter run -d <device_id>
# Puis ouvrir l'URL DevTools affichée dans le terminal

# Ou directement
dart devtools
```

### 7. Logs et débogage

```bash
# Voir les logs en temps réel
flutter logs -d <device_id>

# Lancer avec logs détaillés
flutter run -d <device_id> --verbose
```

---

## Option B : Sans Mac — CI/CD cloud (ta situation)

Tu n'as pas de Mac, donc tu utilises des Mac cloud pour compiler. Deux pipelines sont configurés.

---

### B1. Codemagic (recommandé — 500 min gratuites/mois)

**Fichier de config :** `codemagic.yaml` (racine du projet)

#### Étape 1 : Créer un compte Codemagic
1. Va sur https://codemagic.io et connecte-toi avec ton compte GitHub
2. Ajoute le repo `app_renseignement`
3. Codemagic détecte automatiquement `codemagic.yaml`

#### Étape 2 : Configurer les credentials Apple
1. Dans Codemagic → Settings → ton app → **Code signing (iOS)**
2. Connecter ton Apple ID (ou App Store Connect API Key)
3. Codemagic gère automatiquement les certificats et provisioning profiles

#### Étape 3 : Ajouter le GoogleService-Info.plist
1. Télécharge `GoogleService-Info.plist` depuis la Firebase Console (projet sgk-home, app iOS)
2. Encode-le en base64 : `base64 -i GoogleService-Info.plist`
3. Dans Codemagic → Environment variables → ajoute `GOOGLE_SERVICE_INFO` avec la valeur base64
4. Groupe : `apple_credentials`

#### Étape 4 : Lancer un build
- **Build de vérification** : push sur `main` → workflow `ios-build-check` se lance automatiquement
- **Deploy TestFlight** : push sur une branche `release/*` ou crée un tag `v1.0.0` → workflow `ios-testflight`
- L'IPA est uploadée sur TestFlight automatiquement
- Tu recevras un email à sakamemmanuel@gmail.com

#### Étape 5 : Installer sur iPad
1. Installe l'app **TestFlight** sur ton iPad (App Store, gratuit)
2. Connecte-toi avec ton Apple ID
3. L'app Horem+ apparaît → Installer

---

### B2. GitHub Actions (~200 min macOS gratuites/mois)

**Fichiers de config :** `.github/workflows/ios-build.yml` et `.github/workflows/ios-testflight.yml`

#### Workflow 1 : `ios-build.yml` (vérification automatique)
- Se lance à chaque push sur `main`
- Compile l'app iOS sans signing (vérifie que ça compile)
- Aucune configuration nécessaire, marche tout de suite

#### Workflow 2 : `ios-testflight.yml` (deploy manuel sur TestFlight)
Nécessite des secrets GitHub. Va dans Settings → Secrets → Actions :

| Secret | Description | Comment l'obtenir |
|--------|-------------|-------------------|
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | Firebase iOS config (base64) | Firebase Console → Projet → iOS → télécharger → `base64 -i fichier` |
| `APPLE_P12_CERTIFICATE_BASE64` | Certificat distribution (base64) | Xcode (via Codemagic ou un Mac emprunté) |
| `APPLE_P12_PASSWORD` | Mot de passe du .p12 | Choisi lors de l'export |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Provisioning profile (base64) | Apple Developer Portal ou Codemagic |
| `KEYCHAIN_PASSWORD` | Mot de passe temporaire | N'importe quelle chaîne aléatoire |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID | App Store Connect → Users → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | App Store Connect → Users → Keys |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Fichier .p8 (base64) | App Store Connect → Users → Keys → Download |

Pour lancer : GitHub → Actions → "iOS TestFlight Deploy" → Run workflow

---

### Comparaison Codemagic vs GitHub Actions

| | Codemagic | GitHub Actions |
|---|---|---|
| Minutes macOS gratuites | 500/mois | ~200/mois (2000 × 0.1) |
| Config signing iOS | Automatique (UI) | Manuelle (secrets) |
| Détection Flutter | Native | Via action tierce |
| Upload TestFlight | Intégré | Manuelle (xcrun) |
| Complexité setup | Facile | Moyen |
| **Recommandation** | **Pour les deploys iPad** | **Pour les checks CI** |

**Stratégie recommandée :** GitHub Actions pour vérifier la compilation (gratuit, automatique), Codemagic pour les vraies releases TestFlight.

---

## Prérequis Apple (obligatoire pour TestFlight)

Avant de pouvoir installer sur ton iPad via TestFlight, il te faut :

1. **Apple ID** — gratuit, tu en as probablement un
2. **Apple Developer Program** — **99 $/an** obligatoire pour TestFlight et App Store
   - Inscription : https://developer.apple.com/programs/enroll/
   - Sans ça, tu peux uniquement faire des builds `--no-codesign` (vérification compilation)
3. **Bundle ID enregistré** — `com.horemplus.app` dans le Developer Portal
4. **App créée dans App Store Connect** — nécessaire pour TestFlight

---

## Permissions iOS (déjà configurées)

Les permissions sont déclarées dans `ios/Runner/Info.plist` :

| Permission | Clé | Description |
|------------|-----|-------------|
| Caméra | `NSCameraUsageDescription` | Photos annonces/publicités |
| Galerie | `NSPhotoLibraryUsageDescription` | Illustrations annonces |
| Micro | `NSMicrophoneUsageDescription` | Enregistrement vidéos |
| Position | `NSLocationWhenInUseUsageDescription` | Annonces à proximité |

---

## Différences iPad vs Android

| Aspect | Android | iPad |
|--------|---------|------|
| Permissions galerie | `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` | `NSPhotoLibraryUsageDescription` |
| Permissions caméra | `CAMERA` | `NSCameraUsageDescription` |
| Paiement Mobile Money | WebView Android | WKWebView (iOS) |
| Google Maps | API Key dans AndroidManifest | API Key dans AppDelegate.swift |
| Notifications push | FCM via `google-services.json` | FCM via `GoogleService-Info.plist` + APNs |
| Taille écran | Variable | iPad = grand écran, tester le layout responsive |

---

## Checklist pour installer Horem+ sur iPad (sans Mac)

- [ ] Apple Developer Program souscrit (99 $/an)
- [ ] Compte Codemagic créé et repo connecté
- [ ] `GoogleService-Info.plist` généré depuis Firebase Console (app iOS)
- [ ] Signing iOS configuré dans Codemagic
- [ ] `GOOGLE_SERVICE_INFO` ajouté dans les variables Codemagic
- [ ] Push sur branche `release/v1.0` ou tag `v1.0.0`
- [ ] Build réussi dans Codemagic
- [ ] TestFlight installé sur iPad
- [ ] App Horem+ visible dans TestFlight → Installer
