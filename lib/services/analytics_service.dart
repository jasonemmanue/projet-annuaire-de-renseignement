// ============================================================
// FICHIER : lib/services/analytics_service.dart
// Service Analytics centralisé – ImmoConnect
// Dépendance : firebase_analytics: ^11.5.0 (déjà dans pubspec.yaml)
// ============================================================
//
// ┌─────────────────────────────────────────────────────────┐
// │         CONFIGURATION FIREBASE CONSOLE                  │
// ├─────────────────────────────────────────────────────────┤
// │                                                         │
// │  ÉTAPE 1 – Activer Google Analytics                     │
// │  → console.firebase.google.com > [votre projet]         │
// │  → Paramètres du projet > Intégrations > Google         │
// │    Analytics > Activer                                  │
// │  → Associer à une propriété GA4 (ou en créer une)       │
// │                                                         │
// │  ÉTAPE 2 – Vérifier l'initialisation dans main.dart     │
// │  Assurez-vous que main.dart contient :                  │
// │    await Firebase.initializeApp(                        │
// │      options: DefaultFirebaseOptions.currentPlatform,   │
// │    );                                                   │
// │  FirebaseAnalytics.instance est disponible dès lors.    │
// │  Aucune initialisation supplémentaire requise.          │
// │                                                         │
// │  ÉTAPE 3 – Vérifier les events dans la console          │
// │  → Analytics > Events (délai ~24h pour les custom)      │
// │  → En debug immédiat : activer DebugView                │
// │    Terminal : adb shell setprop debug.firebase.         │
// │    analytics.app.package_name true                      │
// │  → Analytics > DebugView : events en quasi-temps réel   │
// │                                                         │
// │  ÉTAPE 4 – Créer l'audience "Visiteurs actifs"          │
// │  → Analytics > Audiences > Nouvelle audience            │
// │  → Nom : "Visiteurs actifs"                             │
// │  → Condition : event "view_item" > 3 fois               │
// │    (dans la même session ou sur 30 jours, à choisir)    │
// │  → Enregistrer — disponible sous 24 à 48h               │
// │                                                         │
// │  ÉTAPE 5 – Entonnoir de conversion vue → contact        │
// │  → Analytics > Funnels > Créer un entonnoir             │
// │  → Étape 1 : view_item                                  │
// │  → Étape 2 : generate_lead                              │
// │  → Cela donne le taux de conversion métier clé          │
// │                                                         │
// │  ÉTAPE 6 – Tableau de bord personnalisé (optionnel)     │
// │  → Analytics > Tableaux de bord > Nouveau               │
// │  → Ajouter : view_item, generate_lead, add_to_wishlist  │
// │    share, login (prestataire), post_score (annonce)     │
// └─────────────────────────────────────────────────────────┘

import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  // ── Singleton ──────────────────────────────────────────────
  AnalyticsService._internal();
  static final AnalyticsService instance = AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // ──────────────────────────────────────────────────────────
  // a) Vue d'écran
  //    Appeler dans initState() de chaque screen.
  //    Alimente le rapport "Engagement > Vues d'écran" GA4.
  // ──────────────────────────────────────────────────────────
  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  // ──────────────────────────────────────────────────────────
  // b) Lancement d'une recherche
  //    Event GA4 standard : search
  //    Paramètres exploitables dans les rapports personnalisés.
  // ──────────────────────────────────────────────────────────
  Future<void> logRechercheLogement({
    String? ville,
    String? type,
    double? prixMax,
  }) async {
    await _analytics.logEvent(
      name: 'search',
      parameters: {
        if (ville != null && ville.isNotEmpty) 'search_term': ville,
        if (type != null && type.isNotEmpty) 'item_category': type,
        if (prixMax != null) 'price_max': prixMax,
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // c) Ouverture d'une fiche logement
  //    Event GA4 e-commerce standard : view_item
  //    Permet de mesurer les logements les plus consultés
  //    et constitue l'étape 1 de l'entonnoir de conversion.
  // ──────────────────────────────────────────────────────────
  Future<void> logVueLogement(
      String logementId,
      String titre,
      String ville,
      double prix,
      ) async {
    await _analytics.logEvent(
      name: 'view_item',
      parameters: {
        'item_id': logementId,
        'item_name': titre,
        'item_category': ville,
        'price': prix,
        'currency': 'XAF',
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // d) Contact prestataire (1er message)
  //    Event GA4 e-commerce standard : generate_lead
  //    Étape 2 de l'entonnoir — taux de conversion clé.
  //    N'appeler QUE si c'est bien le premier message
  //    de la conversation (vérification côté appelant).
  // ──────────────────────────────────────────────────────────
  Future<void> logContactPrestataire(
      String logementId,
      String prestataireId,
      ) async {
    await _analytics.logEvent(
      name: 'generate_lead',
      parameters: {
        'item_id': logementId,
        'prestataire_id': prestataireId,
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // e) Ajout en favori
  //    Event GA4 e-commerce standard : add_to_wishlist
  // ──────────────────────────────────────────────────────────
  Future<void> logAjoutFavori(String logementId) async {
    await _analytics.logEvent(
      name: 'add_to_wishlist',
      parameters: {'item_id': logementId},
    );
  }

  // ──────────────────────────────────────────────────────────
  // f) Partage d'une annonce
  //    Event GA4 standard : share
  // ──────────────────────────────────────────────────────────
  Future<void> logPartageAnnonce(String logementId) async {
    await _analytics.logEvent(
      name: 'share',
      parameters: {
        'content_type': 'logement',
        'item_id': logementId,
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // g) Connexion prestataire réussie
  //    Event GA4 standard : login
  // ──────────────────────────────────────────────────────────
  Future<void> logConnexionPrestataire() async {
    await _analytics.logLogin(loginMethod: 'email');
  }

  // ──────────────────────────────────────────────────────────
  // h) Publication d'une nouvelle annonce
  //    Event custom : post_item  (pas de standard GA4 exact)
  //    Permet de suivre la cadence de publication.
  // ──────────────────────────────────────────────────────────
  Future<void> logPublicationAnnonce(
      String logementId,
      String type,
      double prix,
      ) async {
    await _analytics.logEvent(
      name: 'post_item',
      parameters: {
        'item_id': logementId,
        'item_category': type,
        'price': prix,
        'currency': 'XAF',
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // i) Initiation d'un paiement
  //    Event GA4 e-commerce standard : begin_checkout
  // ──────────────────────────────────────────────────────────
  Future<void> logPaiementInitie(String type, double montant) async {
    await _analytics.logEvent(
      name: 'begin_checkout',
      parameters: {
        'payment_type': type,
        'value': montant,
        'currency': 'XAF',
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  // j) Définir le rôle de l'utilisateur comme user property
  //    Valeurs attendues : "prestataire" | "visiteur"
  //    Permet de segmenter tous les rapports GA4 par rôle.
  //    Note : les user properties peuvent prendre 24h à
  //    apparaître dans la console Firebase Analytics.
  // ──────────────────────────────────────────────────────────
  Future<void> setUserRole(String role) async {
    await _analytics.setUserProperty(name: 'role', value: role);
  }
}