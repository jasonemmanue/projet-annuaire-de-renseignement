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

## Option B : Sans Mac (alternatives)

### B1. Codemagic CI/CD (cloud)
- Créer un compte sur [codemagic.io](https://codemagic.io)
- Connecter ton repo GitHub/GitLab
- Codemagic compile sur des Mac cloud et génère l'IPA
- Tu peux installer l'IPA sur ton iPad via TestFlight

### B2. GitHub Actions avec macOS runner
```yaml
# .github/workflows/ios-build.yml
name: iOS Build
on: push
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: cd ios && pod install
      - run: flutter build ios --no-codesign
```

### B3. Location de Mac cloud
- MacStadium, MacInCloud, AWS Mac instances
- Accès distant à un Mac pour Xcode

---

## Permissions iOS spécifiques (Info.plist)

Le fichier `ios/Runner/Info.plist` doit déclarer les permissions utilisées :

```xml
<!-- Caméra -->
<key>NSCameraUsageDescription</key>
<string>Horem+ a besoin de la caméra pour prendre des photos de vos annonces</string>

<!-- Galerie photos -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Horem+ a besoin d'accéder à vos photos pour illustrer vos annonces</string>

<!-- Localisation -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Horem+ utilise votre position pour afficher les annonces proches</string>

<!-- Microphone (pour vidéos) -->
<key>NSMicrophoneUsageDescription</key>
<string>Horem+ a besoin du microphone pour enregistrer des vidéos</string>
```

---

## Différences iPad vs Android à surveiller

| Aspect | Android | iPad |
|--------|---------|------|
| Permissions galerie | `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` | `NSPhotoLibraryUsageDescription` |
| Permissions caméra | `CAMERA` | `NSCameraUsageDescription` |
| Paiement Mobile Money | WebView Android | WKWebView (iOS) — vérifier que `webview_flutter_wkwebview` est présent |
| Google Maps | API Key dans AndroidManifest | API Key dans AppDelegate.swift |
| Notifications push | FCM via `google-services.json` | FCM via `GoogleService-Info.plist` + APNs |
| Taille écran | Variable | iPad = grand écran, tester le layout responsive |

---

## Checklist avant premier lancement iPad

- [ ] Mac avec Xcode 15+ installé
- [ ] `flutter doctor` sans erreur iOS
- [ ] `ios/Runner.xcworkspace` ouvert et signing configuré
- [ ] `GoogleService-Info.plist` ajouté dans `ios/Runner/` (depuis Firebase Console)
- [ ] `Info.plist` avec toutes les descriptions de permissions
- [ ] `AppDelegate.swift` avec la clé Google Maps
- [ ] iPad en mode développeur, connecté par câble, confiance accordée
- [ ] `pod install` exécuté dans `ios/`
- [ ] `flutter run -d <ipad>` lance l'app sans erreur

---

## Commandes utiles

```bash
# Lister les appareils iOS connectés
flutter devices

# Nettoyer le build iOS
flutter clean
cd ios && pod deintegrate && pod install && cd ..

# Build iOS sans signing (pour CI)
flutter build ios --no-codesign

# Build IPA pour TestFlight
flutter build ipa

# Ouvrir le projet dans Xcode
open ios/Runner.xcworkspace
```
