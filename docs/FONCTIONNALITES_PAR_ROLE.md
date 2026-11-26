# Horem+ : fonctionnalités de l'application mobile par rôle

Mis à jour le 26/11/2026 (version 1.0.6+8). Les règles (montants, visibilité,
modération) sont tenues par l'API `horem-api` : l'app ne fait qu'afficher.

## Rôles

| Rôle | Comment on l'obtient | Navigation (barre du bas) |
|---|---|---|
| Visiteur | Aucun compte (identifiant aléatoire `X-Visiteur-Id`, session Firebase anonyme pour payer) | Accueil, Carte, Favoris, Profil |
| Prestataire | Inscription e-mail + mot de passe + téléphone + CNI | Accueil, Carte, Favoris, Tableau de bord |
| Prestataire « compte offert » | Créé par un admin (`compteGratuit`) | Comme prestataire, sans aucun paiement |
| Admin | E-mail vérifié présent dans `ADMIN_EMAILS` (API) | Comme visiteur + entrée « Administration » dans le Profil |

## Visiteur

- Consentement CGU / confidentialité au 1er lancement, tutoriel visiteur.
- Accueil : annonces validées et actualisées depuis moins de 21 jours, triées
  (mises en avant, puis actives, puis expirées). Prix affiché = prix total
  d'entrée (loyer + charges x mois d'avance + caution + frais d'agence).
- Recherche au clavier ou à la voix (« studio Bastos 50000 », « 25k ») et filtres
  ville, type, location/vente, budget.
- Carte Google Maps : marqueurs colorés par type, rayon 500 m à plus de 10 km.
- Détail d'une annonce : photos qui défilent, bandeau de prudence, lecture vocale
  de la description, détail du prix total, horaires et jours de garde (pharmacies),
  appel, WhatsApp, messagerie, demande de visite, signalement, favori.
- Messagerie avec le prestataire (texte, photo caméra ou galerie), sans compte.
- Rendez-vous de visite : demande (30 min à 90 jours), suivi, annulation.
- Favoris (gardés sur le téléphone, fusionnés au compte à la connexion).
- Alerte prioritaire 48 h (200 XAF, Mobile Money Android ; lien e-mail sur iOS) :
  push immédiat dès qu'un bien du type et du budget voulus est validé.
- Stories publicitaires des prestataires.
- Profil : langue FR/EN, mode sombre, notifications par catégorie, aide/FAQ,
  CGU, confidentialité, noter l'app, devenir prestataire / se connecter.

## Prestataire

Tout ce que fait le visiteur, plus le Tableau de bord :
- Tutoriel en 4 pages à la 1re connexion (rejouable).
- Mes annonces : créer (immobilier, hébergement, pharmacie, entreprise,
  restaurant, école), modifier, supprimer, activer / désactiver.
  Refus si CNI absente (`cni_requise`), si doublon à moins de 10 m même type et
  même prix (`doublon_gps`), si e-mail non vérifié (sauf compte offert).
- Paiement de publication : 3 % du prix (minimum 200 XAF, 30 jours) ou forfait
  hébergement (1, 3, 6 ou 12 mois) ; visibilité annuelle (entreprise 3 000,
  restaurant 2 000, école 1 000 XAF) ; pharmacie gratuite.
- Toute annonce part « En attente de validation » puis est validée ou refusée
  (motif) par l'admin ; une annonce refusée et corrigée repart en file.
- Actualisation gratuite (bouton « Actualiser ») : sans elle l'annonce est masquée
  après 21 jours, rappel push 2 jours avant.
- Mise en avant : 1 semaine 500, 2 semaines 1 000, 1 mois 2 000 XAF.
- Publicités (stories) : 500 XAF pour 4 jours, texte modifiable gratuitement.
- Statistiques : vues, contacts, taux de conversion, évolution des vues.
- Messagerie avec les visiteurs (contacts numérotés « Contact1 »…).
- Rendez-vous : accepter / refuser avec réponse.
- Notifications : messages, validation, fin de mise en avant, paliers de vues.
- Profil : coordonnées, photo (copiée sur ses annonces), CNI, aide prestataire,
  vérification de l'e-mail, déconnexion, suppression du compte.
- iPhone/iPad : aucun prix ni paiement dans l'app ; un lien par e-mail ouvre la
  page web `/pay/<jeton>` de l'admin.

## Prestataire « compte offert »

Comme le prestataire, sans CNI ni e-mail à vérifier, annonces validées d'office,
publication, mise en avant et publicités activées sans paiement.

## Admin (dans l'app)

Profil, section « Administration » :
- Signalements : traiter, supprimer l'annonce visée.
- Annonces : file « À vérifier » (valider, refuser avec motif, badge vérifié),
  filtres, blocage.
- Utilisateurs : recherche, compte offert on/off, création de compte offert,
  suspension, vérification de CNI.
- Statistiques et transactions, notification à tous les utilisateurs.

Le back-office web (Horem-a-ADMIN) offre en plus : conversations, urgences,
publicités, notifications de publication, reprise des données Firestore.

## Notifications push (Android)

Icône de barre d'état : `res/drawable-*/ic_stat_notification.png` (silhouette
blanche du logo, 24 à 96 px), couleur `#0071C2`. Déclarée dans le manifeste
(`default_notification_icon`), dans `notification_service.dart` et envoyée par
l'API (`push.py`, `icon=ic_stat_notification`). Canaux : `sgkhome_messages`,
`sgkhome_annonces`.
