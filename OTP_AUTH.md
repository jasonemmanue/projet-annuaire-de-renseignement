# OTP_AUTH.md — Authentification OTP Horem+

Système d'authentification par code à usage unique, **indépendant de Firebase
Auth** : Africa's Talking (SMS + voix), FCM en push silencieux, session JWT
maison.

---

## 1. Ce qui a remplacé quoi

| Avant | Après |
|---|---|
| Firebase Phone Auth (`verifyPhoneNumber`) | `authOtpDemander` → Africa's Talking |
| `PhoneAuthProvider.credential` + `signInWithCredential` | `authOtpVerifier` → JWT maison |
| Session = ID token Firebase (1 h, non révocable finement) | Access token 1 h + refresh token 30 j, rotatif et révocable |
| reCAPTCHA / App Check sur le chemin d'auth | Rien — plus de captcha à l'écran |
| Empreintes SHA-1/SHA-256 obligatoires dans Firebase | Plus nécessaires **pour l'auth** (le hash SMS Retriever les remplace) |
| Quota SMS Firebase | Crédit Africa's Talking |
| Auto-retrieval Play Services | SMS Retriever API + push silencieux FCM |

### Ce que Firebase fait encore

Deux usages, aucun n'étant de l'authentification par téléphone :

1. **FCM** — transport du push silencieux (canal 1 de la cascade).
2. **`createCustomToken`** — pont d'identité. Après vérification du code par
   *notre* backend, celui-ci signe un jeton Firebase que l'app échange contre une
   session Firebase.

Le pont existe parce que tout le reste de l'app en dépend : `firestore.rules`,
les règles Storage et une dizaine de Cloud Functions reposent sur
`request.auth.uid` / `verifyIdToken`. Le couper sans les migrer rendrait
impossible la publication d'annonces et l'envoi de messages.

Pour le couper (voir § 8) : `PONT_FIREBASE = false` dans `functions/otp.js`.

---

## 2. La cascade — comment on vise 99 %+

```
                    ┌─────────────────────────────────┐
  authOtpDemander → │ 1. push  (appareil de confiance)│ ~0,3 s · gratuit
                    └──────────────┬──────────────────┘
                       échec / 8 s │
                    ┌──────────────▼──────────────────┐
                    │ 2. sms   (Africa's Talking)     │ ~3 s · SMS Retriever
                    └──────────────┬──────────────────┘
                       échec / 25 s│
                    ┌──────────────▼──────────────────┐
                    │ 3. sms_alt (sans sender ID)     │ contourne un rejet
                    └──────────────┬──────────────────┘   de sender ID
                       échec / 25 s│
                    ┌──────────────▼──────────────────┐
                    │ 4. voice (appel qui dicte)      │ passe où le SMS
                    └─────────────────────────────────┘ ne passe pas
```

**Trois déclencheurs d'escalade, indépendants :**

| Déclencheur | Latence | Mécanisme |
|---|---|---|
| L'API AT refuse l'envoi | immédiate, dans la même requête HTTP | `envoyerAvecCascade` boucle sur les canaux restants |
| Rapport de livraison AT `Failed`/`Rejected` | 5–30 s | `authOtpDeliveryReport` réémet sur le canal suivant, sans action de l'utilisateur |
| Délai côté app écoulé | `delaiFallbackSec` | l'app appelle `authOtpRenvoyer` |

Chaque escalade **génère un code neuf** : rediffuser le même code sur un second
canal doublerait sa fenêtre d'interception.

**Mesurer le résultat** — `authOtpStatistiques` (rôle admin requis) renvoie le
taux de livraison réel sur une fenêtre glissante :

```bash
curl -H "Authorization: Bearer <access token admin>" \
  "https://authotpstatistiques-qhxw7o6nha-uc.a.run.app?heures=168"
```

`tauxLivraison` est la métrique de l'objectif 99 %+ : part des demandes pour
lesquelles au moins un canal a accepté l'envoi. `tauxVerification` est plus bas
par nature — il inclut les utilisateurs qui abandonnent en cours de route.

---

## 3. Secrets à créer AVANT le premier déploiement

```bash
cd functions

# ── Africa's Talking ────────────────────────────────────────────
# 'sandbox' pour tester (aucun SMS réel), sinon le username du compte live
echo "sandbox"              | firebase functions:secrets:set AT_USERNAME
echo "atsk_xxxxxxxxxxxxx"   | firebase functions:secrets:set AT_API_KEY
# Sender ID alphanumérique enregistré chez AT. Laisser VIDE tant qu'il n'est
# pas approuvé : un sender ID inconnu fait rejeter tout le message.
echo ""                     | firebase functions:secrets:set AT_SENDER_ID
# Numéro vocal AT au format E.164 — sans lui, le canal `voice` est inactif.
echo "+237XXXXXXXXX"        | firebase functions:secrets:set AT_VOICE_NUMBER

# ── Session ─────────────────────────────────────────────────────
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))" \
  | firebase functions:secrets:set JWT_SECRET
node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))" \
  | firebase functions:secrets:set OTP_PEPPER
```

> ⚠️ **`OTP_PEPPER` ne se change jamais à chaud.** Il entre dans le hash des
> codes : le modifier invalide instantanément toutes les sessions OTP en cours
> (au pire, quelques utilisateurs redemandent un code).
>
> ⚠️ **`JWT_SECRET` invalide tous les access tokens en circulation.** Les
> refresh tokens survivent — les sessions se rétablissent seules dans l'heure.

Puis :

```bash
firebase deploy --only functions
```

---

## 4. Configuration du dashboard Africa's Talking

Deux URL à coller après le déploiement (les URL Cloud Run sont affichées par
`firebase deploy`) :

| Réglage AT | URL |
|---|---|
| **SMS → Delivery Reports** | `https://authotpdeliveryreport-qhxw7o6nha-uc.a.run.app` |
| **Voice → Callback URL** du numéro | `https://authotpvoicecallback-qhxw7o6nha-uc.a.run.app` |

Sans le callback vocal, l'appel aboutit mais reste **muet** : c'est lui qui
renvoie le XML `<Say>` dictant le code.

Sans le delivery report, la cascade fonctionne toujours, mais l'escalade
automatique sur SMS non délivré disparaît — l'utilisateur doit appuyer sur
« Recevoir un appel » lui-même.

---

## 5. SMS Retriever (autofill Android)

Le SMS doit respecter quatre conditions, sinon il arrive mais Android ne le
transmet pas à l'app :

1. commencer par `<#>` ;
2. contenir le code ;
3. se terminer par le hash à 11 caractères de la signature de l'app ;
4. faire ≤ 140 octets.

`composerSmsRetriever()` (functions/otp.js) s'en charge, à partir du hash que
l'app envoie à chaque demande.

**Le hash dépend de la clé de signature** — il diffère entre :

- le build de debug ;
- un build signé avec `android/key.properties` ;
- un build **re-signé par Google Play** (Play App Signing).

C'est pourquoi il est calculé à l'exécution (`AppSignatureHelper.kt`) et
transmis au serveur, jamais codé en dur. Rien à configurer côté Play Console.

Pour le lire : écran de diagnostic (long-press sur le titre de l'écran de
connexion en debug) → section « Cascade OTP » → « Hash SMS Retriever ».

Si le hash est absent (ROM sans Play Services), le backend envoie un SMS
classique et l'utilisateur saisit le code — la saisie manuelle n'est jamais
désactivée.

---

## 6. Modèle de données Firestore

Cinq collections, **toutes verrouillées côté client** dans `firestore.rules`
(`allow read, write: if false`) — seul l'Admin SDK y écrit.

| Collection | Contenu | Durée de vie |
|---|---|---|
| `otp_sessions/{sessionId}` | hash du code + sel, canal courant, compteur de tentatives | 5 min, purgée toutes les 6 h |
| `refresh_tokens/{jti}` | hash du refresh token, `revoqueA`, `remplacePar` | 30 j |
| `trusted_devices/{tel}_{deviceId}` | token FCM de l'appareil, date de dernière vue | permanent |
| `otp_rate_limits/{clé}` | fenêtres glissantes par numéro et par IP | 30 j |
| `otp_deliveries/{id}` | journal d'envoi et rapports AT (numéros masqués) | 30 j |

**Le code en clair n'est jamais persisté** : seul `sha256(code:sel:poivre)` est
stocké. Le poivre vit dans Secret Manager, hors de la base — une fuite de
Firestore ne permet donc pas de retrouver les codes.

---

## 7. Sécurité

| Menace | Parade |
|---|---|
| Force brute sur le code | 5 essais max, en **transaction** Firestore (sinon N requêtes parallèles disposeraient chacune de 5 essais) |
| Bombardement SMS d'un numéro | 30 s entre deux demandes · 5/h · 15/jour |
| Bombardement depuis un script | 30 demandes/h par IP |
| Fuite de la base | codes hachés + salés + poivrés ; refresh tokens hachés |
| Vol d'un refresh token | rotation à chaque usage ; **rejeu détecté → révocation de toutes les sessions** de l'utilisateur |
| Forge de signature JWT | comparaison HMAC à temps constant (`timingSafeEqual`) |
| Interception du code par une autre app | SMS Retriever ne livre qu'à l'app dont la signature correspond ; le push silencieux n'affiche rien |
| Fuite du code dans les logs | les numéros sont masqués (`masquer()`), le code n'apparaît jamais |
| Le code renvoyé dans la réponse HTTP | jamais, y compris en développement |

Note sur le canal vocal : le code n'étant stocké que haché, `authOtpVoiceCallback`
ne peut pas le relire — il en génère un neuf et le dicte. La fenêtre d'écoute et
celle de saisie se confondent, il n'y a rien à perdre.

---

## 8. Couper le pont Firebase

Pour que le JWT maison devienne l'unique session :

1. Migrer `firestore.rules` : les règles reposent sur `request.auth.uid`, il
   faudrait passer par un backend intermédiaire ou des custom claims — c'est le
   plus gros morceau, à ne pas sous-estimer.
2. Remplacer `verifyIdToken` par `otp.authentifierRequete(req)` dans les Cloud
   Functions concernées (`initierUrgence`, `creerCompteGratuit`,
   `envoyerLienPaiementEmail`, …). La fonction est déjà exportée pour ça.
3. Passer `PONT_FIREBASE = false` dans `functions/otp.js`.
4. Retirer `signInWithCustomToken` de `AuthService._ouvrirSession`.

Tant que l'étape 1 n'est pas faite, `PONT_FIREBASE = false` casse la
publication d'annonces et la messagerie.

---

## 9. Tester

### En sandbox (aucun SMS réel)

`AT_USERNAME = "sandbox"` bascule automatiquement sur les endpoints sandbox
d'Africa's Talking. Les envois sont acceptés et visibles dans le simulateur AT,
mais **aucun SMS n'arrive sur un vrai téléphone** — lire le code dans les logs
de la fonction :

```bash
firebase functions:log --only authOtpDemander
```

### Forcer un canal

Le bouton « Recevoir un appel » de l'écran de saisie passe `canal: 'voice'`.
En direct :

```bash
curl -X POST https://authotpdemander-qhxw7o6nha-uc.a.run.app \
  -H "Content-Type: application/json" \
  -d '{"telephone":"+237612345678","canal":"voice"}'
```

### Vérifier la cascade

Mettre `AT_SENDER_ID` à une valeur invalide : le canal `sms` échoue, `sms_alt`
prend le relais dans la même requête. La réponse contient `tentativesCanaux`,
qui montre l'enchaînement.

---

## 10. Dépannage

| Symptôme | Cause probable |
|---|---|
| `aucun_canal` sur toutes les demandes | Secrets AT absents, ou crédit Africa's Talking épuisé |
| SMS reçu mais pas d'autofill Android | Hash de signature absent ou faux — voir écran de diagnostic |
| L'appel sonne mais reste muet | Callback vocal non configuré sur le dashboard AT |
| `pontFirebase` au moment de la connexion | Horloge de l'appareil déréglée, ou compte de service sans le rôle « Créateur de jetons du compte de service » |
| Le push silencieux n'arrive jamais | Token FCM périmé (> 30 j) — la cascade descend d'elle-même sur le SMS |
| `cooldown` en boucle pendant les tests | 30 s entre deux `authOtpDemander` sur le même numéro ; utiliser `authOtpRenvoyer` |
| SMS rejeté `InvalidSenderId` | Sender ID non approuvé chez AT — vider `AT_SENDER_ID` |
