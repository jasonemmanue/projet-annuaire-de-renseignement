# CLAUDE.md — horem-api

API Horem+ : FastAPI + PostgreSQL + Redis, déployée sur Railway (projet
**Admin Horem+**, service `horem-api`, URL
`https://horem-api-production.up.railway.app`). Structure calquée sur l'API
Prepaxia.

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

## Commandes

```bash
railway up -s horem-api --detach          # déployer
railway logs -s horem-api                 # journaux
TEST_FAKEREDIS=1 .venv/Scripts/python -m pytest -q   # tests (Postgres embarqué pgserver)
```

## Reprise des données Firestore

`POST /api/v1/admin/migration-firestore` (admin connecté, `FIREBASE_CREDENTIALS`
posé), suivi par `GET` sur la même route. Idempotente : à relancer juste avant
la diffusion de la nouvelle app pour récupérer ce que l'ancienne a écrit.
