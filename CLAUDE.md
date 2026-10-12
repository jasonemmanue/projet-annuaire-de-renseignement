# CLAUDE.md — horem-api

API Horem+ : FastAPI + PostgreSQL + Redis, déployée sur Railway (projet
**Admin Horem+**, service `horem-api`, URL
`https://horem-api-production.up.railway.app`). Structure calquée sur l'API
Prepaxia. Code versionné sur la branche **`horem-api`** du dépôt de l'app
(`jasonemmanue/projet-annuaire-de-renseignement`).

Elle remplace **Firestore** et les **Cloud Functions**. Firebase ne sert plus
qu'à : l'authentification (jeton d'identité vérifié par l'API), le stockage
des fichiers (Firebase Storage, l'app envoie directement) et les push (FCM).

## Arborescence

| Chemin | Rôle |
|---|---|
| `app/main.py` | App, CORS, limite 600 req/min/IP, format d'erreur `{success:false, error}` |
| `app/core/config.py` | Variables d'environnement |
| `app/core/dependencies.py` | `utilisateur_courant`, `compte_requis`, `admin_requis`, `appelant` (compte ou visiteur `X-Visiteur-Id`) |
| `app/core/serial.py` | Lignes SQL ↔ JSON aux **mêmes clés que les anciens documents Firestore**, dates ISO |
| `app/core/cache.py` | Redis : cache court, versions (polling `?v=`), limitation, verrous |
| `app/db/session.py` | Session par requête ; `marquer()` (versions) et `apres_commit()` (push, e-mails…) après commit |
| `app/db/migrations.py` | `create_all` + liste `MIGRATIONS` (ALTER … IF NOT EXISTS) au démarrage |
| `app/models/models.py` | Tables (ids Firestore conservés ; id utilisateur = uid Firebase) |
| `app/services/` | `paiements` (cycle GeniusPay, application unique sous verrou), `geniuspay`, `push`, `email` (Gmail API / Resend), `annonces` (diffusion, alertes urgence, notif admin), `tarifs`, `taches` (planifiées), `migration_firestore` |
| `app/api/v1/routes/` | `users`, `logements`, `conversations`, `divers` (favoris, signalements, notifications, urgences), `publicites`, `paiements`, `admin` |

## Règles

- Les **montants sont calculés par le serveur** (`services/tarifs.py`, miroir de `tarification_service.dart`).
- L'état d'une annonce (disponible, visibleAdmin, paymentPending, expirations,
  sponsoring) ne se règle que par création, paiement, `activer-gratuit`
  (compte offert) ou l'admin.
- « Temps réel » = polling versionné : une route lue en boucle passe par
  `versionne()` et toute écriture qui la concerne appelle `marquer(db, clé)`.
- Effets de bord (push, e-mails, cache) via `apres_commit`, jamais avant le commit.
- **Modération** : `logements.statut_moderation` (`en_attente` | `valide` |
  `rejete`, NULL = antérieure = validée). Création → `en_attente` (sauf admin
  et compte offert). Les listes visiteurs filtrent `valide`/NULL ; la
  diffusion « nouvelle annonce » et les alertes urgence attendent la
  validation. `POST /admin/logements/{id}/moderation` `{decision: valider|rejeter,
  motif?, verifie?}` → push `type: moderation` au prestataire. Filtres admin
  `a_verifier` / `rejete`, compteur `annoncesAVerifier` dans `/admin/stats`.
- **Préférences push** : `notif_messages`, `notif_moderation`,
  `notif_fin_sponsor` (modifiables par `PUT /users/me`) ;
  `push.notifier_utilisateur(..., pref="notif_xxx")` les respecte.
  Fin de sponsorisation (tâche horaire) → push `type: fin_sponsorisation`.

## Commandes

```bash
railway up -s horem-api --detach          # déployer
railway logs -s horem-api                 # journaux
TEST_FAKEREDIS=1 .venv/Scripts/python -m pytest -q   # tests (Postgres embarqué pgserver)
```

## Secrets (variables Railway du service API)

Ils étaient dans le Secret Manager Firebase (Cloud Functions) ; à recopier :
`GENIUSPAY_API_KEY`, `GENIUSPAY_SECRET_KEY`, `GENIUSPAY_WEBHOOK_SECRET`
(`firebase functions:secrets:access NOM`), `FIREBASE_CREDENTIALS` (JSON du
compte de service en base64 sur une ligne), `ADMIN_EMAILS`, `ADMIN_NOTIF_EMAIL`.
E-mails : Railway bloque le SMTP, donc l'ancien couple Gmail
`GMAIL_SENDER_EMAIL` / `GMAIL_APP_PASSWORD` ne sert plus ; poser soit
`GMAIL_API_*` (OAuth, comme Prepaxia) soit `RESEND_API_KEY`.

## Reprise des données Firestore

`POST /api/v1/admin/migration-firestore` (admin connecté, `FIREBASE_CREDENTIALS`
posé), suivi par `GET` sur la même route. Idempotente : à relancer juste avant
la diffusion de la nouvelle app pour récupérer ce que l'ancienne a écrit.
