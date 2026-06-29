# SGK HOME — Horem+

Application mobile immobilière et de services au Cameroun.

**Stack :** Flutter · Firebase · Google Maps · GeniusPay / PawaPay (Mobile Money)

---

## Présentation

SGK HOME connecte visiteurs et prestataires immobiliers au Cameroun. Les prestataires publient des annonces (logements, services, commerces) et les visiteurs les consultent, les sauvegardent en favoris et contactent directement les propriétaires via la messagerie intégrée.

---

## Rôles utilisateurs

| Rôle | Compte | Accès |
|------|--------|-------|
| Visiteur | Non requis | Consultation, recherche, chat, favoris, urgences |
| Prestataire | OTP SMS | + Publication, dashboard, sponsoring, publicités |
| Administrateur | OTP SMS + rôle Firestore | Modération, validation, admin panel web |

---

## Fonctionnalités principales

### Visiteur
- Recherche & filtres (ville, type, prix, surface)
- Carte interactive Google Maps avec géolocalisation
- Fiche détail avec galerie photos + mini-carte
- Messagerie en temps réel (texte, photos, vidéos)
- Favoris + mode hors connexion
- Stories publicités (overlay Instagram-style au démarrage)
- Urgence : accès prioritaire au contact (48h) via Mobile Money

### Prestataire
- Publication d'annonces : logements, services (pharmacie, restaurant, école, entreprise)
- Sponsoring annonce : 500 XAF/sem · 1 000 XAF/2 sem · 2 000 XAF/mois
- Visibilité annuelle service : 1 000–3 000 XAF/an (selon type)
- Pharmacie : publication gratuite avec jours de garde + horaires
- Publicités stories : 500 XAF / 4 jours de diffusion
- Dashboard : statistiques, gestion annonces, messagerie

### Administration
- Panneau Flutter intégré (`admin_panel_screen.dart`)
- Dashboard web Next.js : [github.com/jasonemmanue/Horem-a-ADMIN](https://github.com/jasonemmanue/Horem-a-ADMIN)

---

## Paiements

Paiement Mobile Money Cameroun via GeniusPay + PawaPay :
- **Opérateurs :** Orange Money Cameroun · MTN Mobile Money Cameroun
- **Flux :** USSD push (l'utilisateur reste dans l'app, pas de redirect)
- **Polling :** vérification automatique toutes les 5 s jusqu'à confirmation

---

## Stack technique

| Composant | Technologie |
|-----------|-------------|
| Mobile | Flutter (Android + iOS) |
| Auth | Firebase Phone Auth (OTP SMS) |
| Base de données | Cloud Firestore |
| Stockage médias | Firebase Storage |
| Notifications | Firebase Cloud Messaging |
| Analytics | Firebase Analytics |
| Carte | Google Maps Flutter |
| Paiement | GeniusPay (PawaPay) — Mobile Money XOF/XAF |
| Cloud Functions | Firebase Functions v2 (Node.js) |
| Admin web | Next.js 14 + Tailwind + Firebase |
| Déploiement admin | Railway |

---

## Installation

```bash
flutter pub get
flutter run
```

Fichiers de configuration Firebase requis :
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart` (généré par `flutterfire configure`)

---

## Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

Variables d'environnement (Firebase Secret Manager) :
- `GENIUSPAY_API_KEY` / `GENIUSPAY_SECRET_KEY` / `GENIUSPAY_WEBHOOK_SECRET`
- `GMAIL_SENDER_EMAIL` / `GMAIL_APP_PASSWORD`

---

## Build APK

```bash
flutter build apk --release
# Sortie : build/app/outputs/flutter-apk/app-release.apk
```
