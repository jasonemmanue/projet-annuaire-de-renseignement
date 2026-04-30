# ImmoConnect Cameroun 🏠
### Application mobile immobilière — MVP Flutter

> Plateforme collaborative de services immobiliers dédiée au Cameroun  
> Version : 1.0 MVP · Date : Avril 2026

---

## 📁 Structure des fichiers

```
lib/
├── main.dart                          ← Point d'entrée + Navigation principale
│
├── theme/
│   └── app_theme.dart                 ← Charte graphique (couleurs, typo, thèmes)
│                                        Bleu #0071C2, inspiré Booking.com
│
├── models/
│   └── models.dart                    ← Tous les modèles de données
│                                        Logement, Utilisateur, Message,
│                                        Conversation, FiltreRecherche
│
├── widgets/
│   └── shared_widgets.dart            ← Composants réutilisables
│                                        LogementCard, SearchBar, FilterChip,
│                                        PubliciteBanner, MainBottomNav...
│
└── screens/
    ├── accueil_screen.dart            ← ÉCRAN 1 : Page d'accueil / Menu principal
    │                                    Recherche, filtres rapides, sponsorisés,
    │                                    recommandés près de vous
    │
    ├── carte_screen.dart              ← ÉCRAN 2 : Navigateur / Carte interactive
    │                                    Google Maps, marqueurs, géolocalisation,
    │                                    filtre distance (500m/1km/5km/10km)
    │
    ├── liste_logements_screen.dart    ← ÉCRAN 3 : Liste des logements
    │                                    Grille/liste, tri, pagination infinie,
    │                                    lazy loading, pub toutes les 5 annonces
    │
    ├── detail_logement_screen.dart    ← ÉCRAN 4 : Fiche détail logement
    │                                    Galerie photos + zoom, description,
    │                                    caractéristiques, mini-carte, contact
    │
    ├── messagerie_screen.dart         ← ÉCRAN 5 : Messagerie / Chat
    │                                    Liste conversations + Chat WhatsApp-style
    │                                    Texte, photos, documents, indicateur lu
    │
    ├── dashboard_prestataire_screen.dart ← ÉCRAN 6 : Espace Prestataire
    │                                    CRUD annonces, stats, paiements,
    │                                    sponsorisation, formulaire annonce
    │
    ├── profil_screen.dart             ← ÉCRAN 7 : Profil / Paramètres
    │                                    Langue FR/EN, mode sombre/clair,
    │                                    notifications par catégorie,
    │                                    déconnexion, suppression compte
    │
    ├── favoris_screen.dart            ← Favoris + Mode hors connexion
    │
    └── auth/
        └── login_screen.dart          ← Authentification prestataires
                                         Connexion + Inscription + Social auth
```

---

## 🚀 Démarrage rapide

### Prérequis
```bash
flutter --version  # ≥ 3.10.0
dart --version     # ≥ 3.0.0
```

### Installation
```bash
# 1. Cloner / décompresser le projet
cd immo_connect

# 2. Installer les dépendances
flutter pub get

# 3. Télécharger les polices Poppins
# https://fonts.google.com/specimen/Poppins
# → Placer dans assets/fonts/

# 4. Lancer l'app
flutter run
```

### Configuration Firebase (obligatoire)
```bash
# Installer FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurer Firebase (créer un projet sur console.firebase.google.com)
flutterfire configure

# Cela génère lib/firebase_options.dart automatiquement
```

Puis dans `main.dart` :
```dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ImmoConnectApp());
}
```

---

## 🗺️ Configuration Google Maps

Dans `android/app/src/main/AndroidManifest.xml` :
```xml

```

Dans `ios/Runner/AppDelegate.swift` :
```swift
GMSServices.provideAPIKey("VOTRE_CLE_API_GOOGLE_MAPS")
```

> 💡 Crédit Google Maps : $200/mois offert (§7.2 du cahier des charges)

---

## 💰 Modèle économique (MVP)

| Source | Tarif | Implémenté |
|--------|-------|-----------|
| Annonce gratuite | 1/mois par prestataire | ✅ |
| Annonce sponsorisée | 5 000–15 000 XAF/sem | ✅ UI |
| Pack Premium | 20 000 XAF/mois | ✅ UI |
| Commission transaction | 3–5% | Phase 2 |
| Publicité display | CPM/CPC | ✅ Banner UI |

---

## 📱 Fonctionnalités MVP

### Incluses ✅
- [x] Recherche & filtres logements (ville, type, prix, surface)
- [x] Carte interactive avec marqueurs (placeholder → Google Maps)
- [x] Liste grille/liste avec lazy loading
- [x] Fiche détail avec galerie photos zoom
- [x] Chat client-prestataire (style WhatsApp)
- [x] Espace prestataire avec CRUD annonces
- [x] Statistiques de base (vues, contacts)
- [x] Dashboard paiements
- [x] Profil & Paramètres complets
- [x] Langue FR/EN
- [x] Mode clair/sombre
- [x] Notifications par catégorie
- [x] Favoris + Mode hors connexion (UI)
- [x] Authentification prestataires (UI)
- [x] Publicités intégrées (1 pub / 5 annonces)

### Phase 2 🔜
- [ ] Paiement Orange Money / MTN via CinetPay
- [ ] Statistiques avancées Premium
- [ ] Sponsorisation self-service
- [ ] Extension géographique Afrique centrale

### Phase 3–5 🔮
- [ ] Estimation automatique de prix (IA)
- [ ] Recommandations personnalisées
- [ ] Services notariaux intégrés

---

## 🔐 Sécurité (§5.2)

- HTTPS/TLS via Firebase (Critique)
- JWT via Firebase Auth
- Anti-injection : Firestore NoSQL (pas de SQL)
- Anti-brute force : Firebase Auth (max tentatives)
- Modération contenu : Firebase App Check

---

## 💻 Stack technique recommandée

| Composant | Technologie | Coût |
|-----------|-------------|------|
| Frontend | Flutter (Android + iOS) | Gratuit |
| Auth | Firebase Auth | Gratuit |
| Base de données | Cloud Firestore | Gratuit (Spark) |
| Chat | Firebase Realtime Database | Gratuit |
| Stockage médias | Firebase Storage | Gratuit ≤5GB |
| Notifications | Firebase Cloud Messaging | Gratuit |
| Analytics | Firebase Analytics | Gratuit |
| Carte | Google Maps Flutter | Gratuit ≤$200/mois |
| Crash reporting | Firebase Crashlytics | Gratuit |
| Paiement (Phase 2) | CinetPay | % transaction |

---

## 👥 Rôles utilisateurs (§1.2)

| Rôle | Compte | Accès |
|------|--------|-------|
| **Client/Visiteur** | ❌ Non requis | Consultation, recherche, chat, favoris |
| **Prestataire** | ✅ Obligatoire | + Publication annonces, dashboard, paiements |
| **Administrateur** | ✅ Back-office | Modération, analytics, gestion publicités |

---

