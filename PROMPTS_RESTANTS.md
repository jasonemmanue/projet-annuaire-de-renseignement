# PROMPTS_RESTANTS.md — Horem+

Fonctionnalités à implémenter, dans l'ordre conseillé.
Coche chaque bloc une fois la fonctionnalité validée (critères ✅ satisfaits).

---

## ✅ FONCTIONNALITÉS LIVRÉES (sessions précédentes)

| # | Fonctionnalité | Notes |
|---|----------------|-------|
| — | Paiement Mobile Money (Orange/MTN via GeniusPay/PawaPay) | Devise XOF, USSD push, polling, pas de redirect |
| — | Sponsoring flat fee (500/1000/2000 XAF) | Remplace l'ancienne commission %, durée 1s/2s/1m |
| — | Visibilité annuelle services | Entreprise 3000 / Restaurant 2000 / École 1000 XAF/an |
| — | Pharmacie gratuite + jours garde + horaires | `_isPharmacieType`, champ prix masqué |
| — | Jours & horaires ouverture pour tous les services | `_isServiceType` |
| — | Badge École (violet) dans formulaire annonce | |
| — | Contact prestataire dans logement Firestore | `prestatireNom`, `prestatirePhone`, `prestatireId` |
| — | Email admin à `Horem+49@gmail.com` à chaque publication | Nodemailer + Gmail SMTP, secrets Firebase |
| — | `admin_notifications` Firestore | Collecte par le webhook après chaque paiement réussi |
| — | AdMob retiré côté visiteur | `PubliciteBanner` = `SizedBox.shrink()`, `AdsService` désactivé |
| — | Suppression redirect vers GeniusPay | `launchUrl(checkoutUrl)` retiré de urgence/sponsorisation/premium — USSD push, utilisateur reste dans l'app |
| — | Stories publicités overlay (Instagram-style) | `stories_publicites_overlay.dart` |
| — | Messagerie : envoi photos/vidéos, tag messages, réponse | |
| — | Dashboard admin web Next.js (pages + notifications) | Repo `Horem-a-ADMIN` sur GitHub |
| — | Dialog « annonce non vérifiée » texte sans overflow | `Flexible` sur le titre |

---

## PHASE D — Carte & Recherche

### [ ] #6 — Carte réelle : filtrage rayon, cercle, libellés km, >10 km

**Fichier :** `lib/screens/carte_screen.dart`

**Problèmes actuels :**
- `_distanceFiltreKm` est stocké dans l'état mais JAMAIS appliqué aux marqueurs Firestore.
- Le badge « Horem+ » (Positioned top-right) chevauche le sélecteur de distance (aussi top-left / top-right).
- Aucun cercle n'est dessiné sur la carte.
- L'option max est « 10 km » ; il faut un sentinelle « > 10 km ».

**Prompt :**
```
Améliore lib/screens/carte_screen.dart :

1) FILTRAGE PAR RAYON : à partir de la position utilisateur (_positionUtilisateur,
   sinon _yaoundeCenter), ne garde dans `markers` que les logements dont la
   distance ≤ _distanceFiltreKm (utilise geolocator Geolocator.distanceBetween).
   Quand le sentinelle 999.0 est actif, affiche tout (pas de filtre).

2) CERCLE : dessine un Circle (GoogleMap circles:) centré sur l'utilisateur,
   de rayon _distanceFiltreKm*1000 m, semi-transparent (couleur AppColors.primary).
   Ne dessine PAS de cercle si valeur sentinelle 999.0.

3) MARQUEURS NOMMÉS : garde InfoWindow(title: l.titre, snippet: l.prixLabel) et,
   au tap, montre la fiche résumé existante. Distingue visuellement les annonces
   sponsorisées (ex. BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)).

4) LIBELLÉS KM : dans _FiltreDistanceWidget et le bottom sheet _afficherFiltreDistance,
   ajoute l'option « > 10 km » (valeur sentinelle 999.0 → affiche tout, pas de cercle).
   La liste _distances passe à [0.5, 1.0, 5.0, 10.0, 999.0] et les labels à
   ['500m', '1km', '5km', '10km', '>10km'].

5) ANTI-CHEVAUCHEMENT : le badge « Horem+ » (Positioned top: 12, right: 12)
   chevauche les contrôles. Déplace-le en bas-centre (Positioned bottom: 16, left: 0, right: 0,
   child: Center(...)) avec un style discret (petit, semi-transparent).
   Le _FiltreDistanceWidget reste en haut-gauche, le bouton géoloc en bas-droite.

flutter analyze à la fin. Montre le build() complet modifié.
```

**Critères ✅ :**
- Changer le rayon filtre réellement les points et redessine le cercle.
- « > 10 km » montre toutes les annonces, sans cercle.
- « Horem+ » ne chevauche plus les contrôles km.
- Chaque marqueur affiche le nom de l'annonce en InfoWindow.

---

### [ ] #7 — Barre de recherche réelle + autocomplétion + filtres fonctionnels

**Fichiers :** `lib/screens/accueil_screen.dart`, `lib/widgets/shared_widgets.dart`,
`lib/screens/liste_logements_screen.dart`, `lib/models/models.dart`

**Problèmes actuels :**
- `_logementsFiltres` filtre uniquement par le chip de type, pas par le texte saisi.
- Le bouton filtre ouvre `_FiltresAvancesSheet` mais les valeurs ne sont pas appliquées à la liste.
- Aucune suggestion d'autocomplétion.

**Prompt :**
```
Rends la recherche réellement fonctionnelle dans accueil_screen.dart :

1) RECHERCHE TEXTE : dans la méthode qui calcule _logementsFiltres (ou son équivalent),
   ajoute un filtrage par le texte saisi qui matche (insensible à la casse/accents) sur :
   titre, typeBien, typeLocation, ville, quartier, description.
   Le filtre texte ET le chip de type se combinent (ET logique).

2) AUTOCOMPLÉTION : sous la barre AppSearchBar, affiche une liste de suggestions en temps
   réel à partir des logements chargés (titres, quartiers, types distincts qui matchent la
   saisie). Au tap d'une suggestion, applique-la comme texte de recherche et ferme la liste.
   Utilise un overlay ou une liste conditionnelle sous la barre.

3) FILTRE À DROITE : le bouton filtre (onFilterTap) ouvre _FiltresAvancesSheet.
   Ce sheet doit exposer : prix min/max, type de bien, location/vente, vérifié seulement,
   surface min. Construis un objet FiltreRecherche depuis ces valeurs et applique-le
   à la liste affichée. Montre un badge « filtres actifs (n) » sur le bouton quand au
   moins un filtre est posé, + un bouton « Réinitialiser » dans le sheet.

Ajoute les clés i18n FR/EN nécessaires. flutter analyze à la fin.
```

**Critères ✅ :**
- Taper « villa » filtre la liste et propose des suggestions.
- Un filtre de prix/type réduit réellement les résultats.
- Reset efface tous les filtres.

---

## PHASE E — Profil visiteur & informations

### [ ] #9 — Activation réelle des notifications par type

**Fichiers :** `lib/screens/profil_screen.dart`, `lib/services/notification_service.dart`

**Problème actuel :** les switches ne font qu'un `setState` local, non persisté, non appliqué.

**Prompt :**
```
Dans profil_screen.dart, les switches _notifNouvellesAnnonces, _notifMessages,
_notifAlertesPrix ne font qu'un setState. Rends-les réels :

1) PERSISTANCE : sauvegarde chaque préférence dans SharedPreferences
   (clés 'notif_annonces', 'notif_messages', 'notif_prix') ; charge au initState.

2) APPLICATION : dans NotificationService, ajoute des méthodes statiques
   isCategoryEnabled(String category) qui lisent ces clés. Avant d'afficher
   toute notification locale (showMessageNotification, etc.), vérifie que la
   catégorie est activée, sinon skip.

3) FCM TOPICS : pour 'notif_annonces' et 'notif_prix', appelle
   FirebaseMessaging.instance.subscribeToTopic/unsubscribeFromTopic('new_listings',
   'price_drops') selon l'état du switch.

flutter analyze à la fin.
```

**Critères ✅ :**
- Désactiver « Messages » → plus de notif message.
- La préférence survit au redémarrage.

---

### [ ] #10 — Aide & FAQ réelle + contact email / WhatsApp

**Fichiers :** `lib/screens/profil_screen.dart`, créer `lib/screens/aide_faq_screen.dart`

**Prompt :**
```
Crée lib/screens/aide_faq_screen.dart avec :
- une liste de questions/réponses repliables (ExpansionTile) : recherche d'annonce,
  contact prestataire, signification de « Vérifié par Horem+ », devenir prestataire,
  sponsorisation/paiement Mobile Money, notifications, mode visiteur ;
- section « Contacter le support » avec 2 boutons :
  • E-mail → url_launcher mailto: (constante SUPPORT_EMAIL = 'support@horemplus.cm') ;
  • WhatsApp → url_launcher https://wa.me/SUPPORT_WHATSAPP (constante SUPPORT_WHATSAPP = '237XXXXXXXXX').
Branche l'onTap de « Aide & FAQ » dans profil_screen.dart vers cet écran.
Textes FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- « Aide & FAQ » ouvre l'écran.
- Les boutons ouvrent Mail et WhatsApp pré-remplis.

---

### [ ] #11 — CGU + Confidentialité + écran d'acceptation 1er lancement

**Fichiers :** `lib/screens/profil_screen.dart`, `lib/main.dart`,
créer `lib/screens/legal/politique_screen.dart`, `lib/screens/legal/cgu_screen.dart`,
`lib/screens/legal/consentement_screen.dart`

**Prompt :**
```
1) Crée lib/screens/legal/politique_screen.dart et lib/screens/legal/cgu_screen.dart :
   deux écrans scrollables avec texte structuré (FR + EN — placeholder à remplacer par
   le texte juridique réel). Branche les onTap correspondants dans profil_screen.dart.

2) Crée lib/screens/legal/consentement_screen.dart : résumé CGU + Confidentialité,
   liens vers les deux écrans complets, bouton « J'accepte ».
   Mémorise l'acceptation dans SharedPreferences (clé 'legal_accepted_v1' + horodatage).

3) Dans main.dart, après SplashScreen et avant MainNavigationScreen, vérifie la clé
   'legal_accepted_v1'. Si absente → affiche ConsentementScreen ; sinon → app normale.

Tout en FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- 1ère installation → écran de consentement obligatoire.
- Après acceptation, plus jamais affiché.
- Les deux entrées du profil ouvrent les écrans complets.

---

### [ ] #12 — Widget « Noter l'application » périodique

**Fichiers :** `lib/screens/accueil_screen.dart`, créer `lib/services/rating_service.dart`

**Note :** Ajouter `in_app_review` au `pubspec.yaml` (confirmer la version avant).

**Prompt :**
```
1) Ajoute `in_app_review: ^2.0.9` au pubspec.yaml et crée lib/services/rating_service.dart :
   - compte les ouvertures (SharedPreferences clé 'app_open_count') ;
   - invite après ≥ 5 ouvertures, au plus 1 fois tous les 30 jours, plus jamais si
     l'utilisateur a choisi « Non merci » (clé 'rating_declined') ;
   - méthode Future<void> maybeAskForReview(BuildContext context).

2) Dans maybeAskForReview, affiche d'abord un bottom sheet maison
   « Vous aimez SGK HOME ? » avec :
   • « Oui, noter l'app » → InAppReview.instance.requestReview() ;
   • « Plus tard » → ferme, ne marque pas comme refusé ;
   • « Non merci » → ferme, marque rating_declined.

3) Appelle RatingService.instance.maybeAskForReview(context) dans
   accueil_screen.dart au retour sur l'onglet accueil (didChangeDependencies
   ou sur le focus de la tab), de façon non intrusive.

Textes FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- Forcer le compteur au seuil → invitation apparaît une fois.
- « Non merci » → plus jamais d'invitation.

---

### [ ] #13 — Accès à la page d'évaluation du store

**Fichier :** `lib/screens/profil_screen.dart`

**Prompt :**
```
Dans profil_screen.dart, branche l'onTap de « Évaluer l'application » :
- appelle InAppReview.instance.openStoreListing() (package in_app_review, cf. #12) ;
- fallback : url_launcher vers
  https://play.google.com/store/apps/details?id=com.horemplus.app
  (constante APP_STORE_ID à placer en haut du fichier — à confirmer).
flutter analyze à la fin.
```

**Critères ✅ :**
- « Évaluer l'application » ouvre la fiche Play Store.

---

### [ ] #15 — Retirer « Sans Compte » du badge Mode visiteur

**Fichier :** `lib/screens/profil_screen.dart`

**Prompt :**
```
Dans profil_screen.dart, trouve le badge qui affiche 'Mode visiteur · Sans compte'
(ou la clé i18n correspondante) et remplace-le par 'Mode visiteur' uniquement.
Mets à jour la clé i18n FR et EN. Aucune autre modification.
```

**Critères ✅ :**
- Le badge affiche « Mode visiteur » sans « Sans compte ».

---

## PHASE F — Mise en avant & inscription

### [ ] #14 — Version visible + bouton prestataire élargi + question

**Fichiers :** `lib/main.dart` (`_ProfilAvecLoginScreen`), `lib/screens/profil_screen.dart`

**Note :** Ajouter `package_info_plus` au pubspec (confirmer la version avant).

**Prompt :**
```
Dans lib/main.dart, _ProfilAvecLoginScreen utilise un Stack+Positioned qui superpose
le bouton « Accéder à l'Espace Prestataire » EN BAS, masquant la ligne « Version ».
Corrige :

1) Retire le Stack/Positioned de _ProfilAvecLoginScreen. À la place, ajoute au
   ProfilScreen un paramètre optionnel VoidCallback? onPrestataireAcces.
   Quand ce callback est non-null (cas visiteur), affiche en bas du ListView
   (après la section « Informations ») :
   - un texte : « Envie d'avoir plus de Visibilité en devenant prestataire ? »
     (clé i18n FR/EN) ;
   - le bouton « Accéder à l'Espace Prestataire » pleine largeur, padding confortable.

2) Ajoute package_info_plus: ^8.1.2 au pubspec.yaml. Dans profil_screen.dart,
   charge PackageInfo.fromPlatform() en initState (FutureBuilder ou setState)
   et affiche la vraie version « x.y.z (build n) » dans la ligne Version.

flutter analyze à la fin.
```

**Critères ✅ :**
- La version est visible et non masquée.
- La question apparaît au-dessus du bouton prestataire.
- Rien ne se chevauche.

---

### [ ] #17 — Case CGU cochable obligatoire à l'inscription

**Fichier :** `lib/screens/auth/login_screen.dart`

**Dépendance :** #11 doit être fait (écrans CGU/Confidentialité à lier).

**Prompt :**
```
Dans le formulaire d'inscription de login_screen.dart, ajoute juste avant le bouton
« S'inscrire » :
- un Row(Checkbox + RichText) : « J'accepte les Conditions d'utilisation et la
  Politique de confidentialité » avec les mots « Conditions d'utilisation » et
  « Politique de confidentialité » en TextSpan cliquables ouvrant respectivement
  CguScreen et PolitiqueScreen (#11).
- bool _cguAcceptees = false dans l'état.
- Le bouton « S'inscrire » est désactivé (onPressed: null) si _cguAcceptees == false.
- _inscription() vérifie aussi _cguAcceptees et affiche un SnackBar sinon.

Textes FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- Impossible de s'inscrire sans cocher la case.
- Les liens ouvrent les écrans CGU et Confidentialité.

---

## PHASE G — Onboarding & espace prestataire

### [ ] #18 — Onboarding post-connexion prestataire → espace direct

**Fichiers :** `lib/screens/auth/login_screen.dart`, `lib/main.dart`,
créer `lib/screens/prestataire_onboarding_screen.dart`

**Prompt :**
```
Crée lib/screens/prestataire_onboarding_screen.dart, un PageView de 4 pages
avec indicateur de progression en barres bleues (LinearProgressIndicator style
stepper) et bouton « Suivant » / « Commencer » :
- Page 1 : Bienvenue + publier des annonces.
- Page 2 : Être contacté via la messagerie ; photos/vidéos ; tag de messages.
- Page 3 : LA SPONSORISATION — payer (Orange Money/MTN) pour mettre une annonce
  en avant, durée, effet attendu (vues/contacts). Mentionner le statut
  « Vérifié par Horem+ ».
- Page 4 : bouton « Accéder à mon espace ».

Comportement :
- Affiché après connexion prestataire réussie, UNE SEULE FOIS
  (SharedPreferences clé 'presta_onboarding_seen').
- Re-jouable via un bouton « Revoir le tutoriel » dans le dashboard.
- À la fin : Navigator.pushAndRemoveUntil vers MainNavigationScreen positionné
  sur l'onglet Dashboard prestataire.

S'inspire du style de visitor_onboarding_screen.dart. FR + EN. flutter analyze.
```

**Critères ✅ :**
- 1ère connexion prestataire → onboarding → espace prestataire direct.
- 2ème connexion → pas d'onboarding.

---

### [ ] #20 — Prestataire : accès Notifications + Aide

**Fichiers :** `lib/screens/dashboard_prestataire_screen.dart`,
`lib/screens/aide_faq_screen.dart` (créé en #10)

**Dépendances :** #9 et #10 doivent être faits.

**Prompt :**
```
Dans dashboard_prestataire_screen.dart, ajoute dans le menu/paramètres :
1) NOTIFICATIONS : factorise la section notifications du profil visiteur dans un
   widget partagé lib/widgets/notifications_settings_widget.dart. Ajoute des
   catégories spécifiques au prestataire : « Nouveaux messages de visiteurs »,
   « Annonce vérifiée/refusée par l'admin », « Fin de sponsorisation ».
   Persiste via SharedPreferences (clés 'notif_presta_messages', etc.).

2) AIDE : bouton vers AideFaqScreen, avec une section supplémentaire prestataire
   expliquant : publier/modifier une annonce, messagerie (photos/vidéos/tag),
   sponsorisation Mobile Money, statut « Vérifié par Horem+ », statistiques.

FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- Depuis l'espace prestataire, on règle les notifications et on ouvre l'aide.

---

## PHASE H — Annonces & détail

### [ ] #24 — Retirer les étoiles dans le formulaire nouvelle annonce

**Fichier :** `lib/screens/dashboard_prestataire_screen.dart`

**Prompt :**
```
Dans le formulaire de création/édition d'annonce (dashboard_prestataire_screen.dart),
liste toutes les occurrences de Icons.star, Icons.star_border, Icons.star_rounded,
widgets de rating, et tout affichage du « standing » sous forme d'étoiles.
Retire-les du formulaire uniquement. Si le « standing/catégorie » utilisait
des étoiles, remplace par un DropdownButton texte (ex. 'Standard', 'Haut standing',
'Meublé'). Ne touche pas aux étoiles d'autres sections (stats du dashboard).
flutter analyze à la fin.
```

**Critères ✅ :**
- Formulaire « Nouvelle annonce » : aucune étoile.

---

### [ ] #25 — Type de bien « Autre (préciser) »

**Fichier :** `lib/screens/dashboard_prestataire_screen.dart`

**Prompt :**
```
Dans le formulaire d'annonce :
1) Ajoute « Autre » aux listes _typesImmo et _typesService.
2) Quand « Autre » est sélectionné, affiche un TextField « Précisez le type de bien »
   obligatoire (validator non-vide).
3) À la sauvegarde :
   - si typeBien == 'Autre', enregistre typeBien = valeur saisie (texte libre)
     et ajoute typeBienBase: 'autre' pour le filtrage ;
   - sinon, typeBienBase = typeBien (valeur normale).
4) Dans l'affichage (listes, détail), si typeBienBase == 'autre', affiche
   la valeur typeBien libre telle quelle.
flutter analyze à la fin.
```

**Critères ✅ :**
- Choisir « Autre » affiche le champ ; la précision est obligatoire et bien sauvegardée.

---

### [ ] #22 — Retirer badges « non vérifié » / « Premium » sur les prestataires

**Fichiers :** `lib/screens/profil_screen.dart`, `lib/screens/detail_logement_screen.dart`,
`lib/screens/dashboard_prestataire_screen.dart`

**Prompt :**
```
Recherche dans tout lib/ les badges/labels « Vérifié »/« Non vérifié » et « Premium »
qui s'affichent au niveau d'un PRESTATAIRE (utilisateur), et retire-les de l'UI.
Ne supprime PAS le champ isVerifie du modèle ni la logique côté ANNONCE.
Liste-moi les emplacements modifiés avant de modifier. flutter analyze à la fin.
```

**Critères ✅ :**
- Aucun badge « Non vérifié » ni « Premium » visible sur les profils prestataires.
- Le badge de vérification d'ANNONCE reste intact.

---

### [ ] #26 — Bannière d'avertissement si annonce non vérifiée

**Fichier :** `lib/screens/detail_logement_screen.dart`

**Prompt :**
```
Dans detail_logement_screen.dart, ajoute :
1) En haut du détail (sous l'AppBar) :
   - Si estVerifie == false : Container bannière couleur AppColors.warning/orange
     avec le texte « Cette annonce n'est pas encore vérifiée par Horem+.
     Par prudence, ne versez aucun acompte et ne finalisez une commande/
     réservation qu'avec une annonce vérifiée. »
   - Si estVerifie == true : petite note verte rassurante + conseil général
     de prudence.

2) Juste sous le bouton « Contacter le propriétaire » / « Réserver » :
   - Si estVerifie == false : rappel court en texte rouge/orange sous le bouton.

Clés i18n FR + EN. flutter analyze à la fin.
```

**Critères ✅ :**
- Annonce non vérifiée → bannière en haut + rappel près du bouton.
- Annonce vérifiée → note rassurante uniquement.

---

## PHASE I — Administration

### [ ] #21 — Admin : validation des annonces + statut « Vérifié par Horem+ »

**Fichiers :** `lib/models/models.dart`, `lib/services/logement_service.dart`,
`lib/screens/admin_panel_screen.dart`, `lib/screens/dashboard_prestataire_screen.dart`,
`lib/screens/accueil_screen.dart`, `lib/screens/carte_screen.dart`

**Prompt PARTIE A (app Flutter) :**
```
Mets en place un cycle de modération.

1) MODÈLE (models.dart) : ajoute à Logement :
   - statutModeration : String — 'en_attente' | 'valide' | 'rejete' (défaut 'en_attente') ;
   - verifieParHorem+ : bool (défaut false).
   Mets à jour fromMap/toMap. Migration douce : annonce sans champ = 'en_attente'.

2) PUBLICATION (dashboard_prestataire_screen.dart) : à la création, force
   statutModeration='en_attente' et verifieParHorem+=false. Informe le prestataire
   que l'annonce sera visible après validation.

3) VISIBILITÉ (logement_service.dart + accueil, liste, carte) : ne montre aux
   VISITEURS que les annonces statutModeration=='valide'. Le prestataire voit
   SES annonces quel que soit le statut, avec un libellé d'état.

4) PANNEAU ADMIN (admin_panel_screen.dart) : file « À vérifier » listant
   les annonces 'en_attente'. Par annonce : « Valider », « Rejeter » (+ motif),
   toggle « Vérifié par Horem+ ». Ces actions écrivent dans Firestore.

5) Rappelle de mettre à jour firestore.rules.

Procède en commits séparés (modèle → publication → visibilité → panneau admin).
flutter analyze après chacun.
```

**Critères ✅ :**
- Nouvelle annonce invisible aux visiteurs jusqu'à validation admin.
- Admin peut toggler « Vérifié par Horem+ ».
- Prestataire voit l'état de ses annonces.

---

## PHASES B (Paiements) — À faire quand la base est stable

### [ ] #1 — Choix opérateur Orange/MTN à la sponsorisation

**Fichier :** `lib/screens/sponsorisation_screen.dart`

**Prompt :**
```
Dans sponsorisation_screen.dart, intègre le widget OperateurSelector
(lib/widgets/operateur_selector.dart) à l'étape de paiement :
- affiche OperateurSelector(onChanged: (operateur, numero) { ... }) ;
- le bouton « Payer » reste désactivé si opérateur == null OU numéro invalide ;
- au paiement, passe channel: operateur (valeur 'orange' ou 'mtn') à
  PaiementService.instance.initierSponsorisation(...).
flutter analyze à la fin.
```

**Critères ✅ :**
- Impossible de payer sans choisir un opérateur + numéro valide.
- L'opérateur est bien transmis au service.

---

### [ ] #2 — Retirer « GeniusPay » UI → « Paiement Mobile Money sécurisé »

**Fichiers :** `lib/screens/sponsorisation_screen.dart`,
`lib/screens/paiement_premium_screen.dart`, `lib/screens/urgence_screen.dart`

**Prompt :**
```
Retire partout dans l'UI le texte/branding « GeniusPay » et remplace par
« Paiement Mobile Money sécurisé » (clé i18n 'payment_secure_label').
Sur paiement_premium_screen.dart et sponsorisation_screen.dart, ajoute
OperateurSelector si pas encore présent, et transmets channel au PaiementService.
Ne touche pas au backend (paiement_service.dart), uniquement à l'UI.
flutter analyze à la fin. Liste les emplacements nettoyés.
```

**Critères ✅ :**
- Aucune occurrence de « GeniusPay » visible à l'écran.
- Les 3 écrans de paiement montrent le choix Orange/MTN.

---

## Recette finale (à faire en DERNIER)

```
1) flutter analyze — corriger tous les warnings.
2) Vérifier : aucun « GeniusPay » visible (#2), aucun « Sans compte » (#15),
   aucune étoile dans le formulaire d'annonce (#24).
3) Parcours clés : 1er lancement → consentement (#11) → recherche (#7) → carte (#6)
   → détail annonce + avertissement (#26) → messagerie (#5) → inscription OTP (#3/#19)
   → photo (#16) + CGU (#17) → onboarding prestataire (#18) → publication (#21) →
   validation admin (#21).
4) Langue + thème persistent (#4/#8) ; notifications respectent les préférences (#9/#20).
```
