// ============================================================================
// FICHIER : functions/otp.js
// Moteur d'authentification OTP — indépendant de Firebase Auth.
//
// Firebase Phone Auth n'est plus utilisé nulle part ici : ni SMS, ni reCAPTCHA,
// ni empreinte SHA, ni App Check sur le chemin d'authentification. Les codes
// sont générés, stockés et vérifiés par ce module ; la session est un JWT
// maison (voir jwt.js).
//
// Le SDK Admin reste utilisé pour deux choses, qui ne sont PAS de
// l'authentification par téléphone :
//   • FCM (envoi du push silencieux) ;
//   • `createCustomToken`, qui traduit une session déjà validée ici en
//     identité Firebase — sans lui, les règles Firestore/Storage (qui reposent
//     toutes sur `request.auth.uid`) et toutes les Cloud Functions existantes
//     qui appellent `verifyIdToken` cesseraient de fonctionner.
//   Ce pont se coupe avec PONT_FIREBASE = false (voir plus bas).
//
// ──────────────────────────────────────────────────────────────────────────
// CASCADE DE CANAUX — objectif 99 %+ de délivrabilité
//
//   1. push    — FCM data-only vers un appareil de confiance (instantané,
//                gratuit, aucun SMS consommé). Seulement si l'appareil a déjà
//                réussi une vérification et que son token FCM est frais.
//   2. sms     — Africa's Talking, message formaté SMS Retriever (autofill
//                Android sans permission SMS).
//   3. sms_alt — 2ᵉ tentative SMS sur la route par défaut de l'opérateur
//                (sender ID retiré). Rattrape les rejets de sender ID et les
//                incidents transitoires d'une seule route.
//   4. voice   — appel vocal Africa's Talking qui dicte le code. Passe là où
//                le SMS ne passe pas (SIM en itinérance, filtrage A2P,
//                boîte SMS pleine).
//
// L'escalade est déclenchée par trois signaux distincts :
//   • échec immédiat de l'API AT (statut ≠ Success) → canal suivant, sur-le-champ ;
//   • rapport de livraison AT (`authOtpDeliveryReport`) Failed/Rejected →
//     canal suivant sans que l'utilisateur n'ait rien à faire ;
//   • expiration du délai côté app → l'app appelle `authOtpRenvoyer`.
// ============================================================================

const crypto = require("crypto");
const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const at = require("./africastalking");
const jwt = require("./jwt");

// ─── Réglages ───────────────────────────────────────────────────────────────

/// Longueur du code. 6 chiffres = 10⁶ combinaisons ; avec 5 essais max et une
/// fenêtre de 5 minutes, la probabilité de tomber juste au hasard est de 5·10⁻⁶.
const LONGUEUR_CODE = 6;

/// Durée de validité d'un code.
const TTL_CODE_S = 5 * 60;

/// Essais de saisie autorisés avant destruction de la session.
const MAX_TENTATIVES = 5;

/// Délai après lequel l'app doit escalader si le canal courant n'a rien donné.
const DELAI_FALLBACK_S = { push: 8, sms: 25, sms_alt: 25, voice: 45 };

/// Garde-fous anti-abus (fenêtre glissante par numéro et par IP).
const LIMITES = {
  cooldownNumeroS: 30,        // délai minimal entre deux demandes sur un numéro
  parNumeroParHeure: 5,
  parNumeroParJour: 15,
  parIpParHeure: 30,
};

/// Un appareil devient « de confiance » après cette 1ʳᵉ vérification réussie.
/// Le token FCM doit avoir été vu il y a moins de 30 jours, sinon le push
/// silencieux part dans le vide et fait perdre 8 secondes à l'utilisateur.
const FRAICHEUR_APPAREIL_JOURS = 30;

/// Pont d'identité Firebase. Passer à `false` coupe complètement
/// `createCustomToken` : le JWT maison devient l'unique session. À ne faire
/// qu'après avoir migré les règles Firestore et les autres Cloud Functions
/// vers la vérification du JWT maison (voir OTP_AUTH.md § « Couper le pont »).
const PONT_FIREBASE = true;

/// Collections Firestore.
const C_SESSIONS = "otp_sessions";
const C_LIMITES = "otp_rate_limits";
const C_REFRESH = "refresh_tokens";
const C_APPAREILS = "trusted_devices";
const C_LIVRAISONS = "otp_deliveries";

/// Index inversé numéro → session, pour le callback vocal d'Africa's Talking.
///
/// Ce détour évite une requête `telephone == X && consomme == false
/// ORDER BY creeA DESC`, qui exigerait un index composite. Le projet n'a pas de
/// `firestore.indexes.json` : l'index manquant ne se verrait qu'en production,
/// au moment où un utilisateur décroche — et l'appel serait muet. Ici, le
/// callback fait un `get()` par identifiant, sans index ni ambiguïté.
const C_VOIX = "otp_voice_pending";

/// Secrets requis par les fonctions de ce module.
const SECRETS_OTP = ["AT_USERNAME", "AT_API_KEY", "AT_SENDER_ID", "AT_VOICE_NUMBER", "JWT_SECRET", "OTP_PEPPER"];

const db = () => admin.firestore();
const horodatage = () => admin.firestore.FieldValue.serverTimestamp();

// ════════════════════════════════════════════════════════════════════════════
// OUTILS
// ════════════════════════════════════════════════════════════════════════════

/**
 * Normalise un numéro camerounais vers E.164.
 * Accepte « 612345678 », « 237612345678 », « +237 6 12 34 56 78 ».
 * @returns {string|null} `+237XXXXXXXXX` ou null si non conforme.
 */
function normaliserTelephone(brut) {
  if (typeof brut !== "string") return null;
  let n = brut.replace(/[\s\-().]/g, "");
  if (n.startsWith("00")) n = `+${n.substring(2)}`;
  if (!n.startsWith("+")) {
    n = n.startsWith("237") ? `+${n}` : `+237${n}`;
  }
  // Mobiles camerounais : +237 puis 6 puis 8 chiffres (MTN, Orange, Camtel).
  return /^\+237[62]\d{8}$/.test(n) ? n : null;
}

/// Code à 6 chiffres tiré d'une source cryptographique.
/// `Math.random()` serait prédictible depuis quelques codes observés.
function genererCode() {
  const max = 10 ** LONGUEUR_CODE;
  // Rejet des tirages qui dépasseraient le dernier multiple complet de `max`,
  // sinon les petits codes sortiraient légèrement plus souvent (biais modulo).
  const plafond = Math.floor(4294967296 / max) * max;
  let tirage;
  do {
    tirage = crypto.randomBytes(4).readUInt32BE(0);
  } while (tirage >= plafond);
  return String(tirage % max).padStart(LONGUEUR_CODE, "0");
}

/// Hache le code avec un sel propre à la session et un poivre global.
/// Le sel isole les sessions entre elles ; le poivre (Secret Manager, jamais en
/// base) rend une fuite de Firestore inexploitable pour retrouver les codes.
function hacherCode(code, sel) {
  const poivre = process.env.OTP_PEPPER || "";
  return crypto.createHash("sha256").update(`${code}:${sel}:${poivre}`).digest("hex");
}

function codeEgal(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

/// IP de l'appelant derrière le proxy Cloud Run.
function ipAppelant(req) {
  const transmise = req.headers["x-forwarded-for"];
  if (typeof transmise === "string" && transmise.length) return transmise.split(",")[0].trim();
  return req.ip || "inconnue";
}

function repondreErreur(res, statut, code, message, extra = {}) {
  res.status(statut).json({ success: false, code, error: message, ...extra });
}

// ════════════════════════════════════════════════════════════════════════════
// LIMITATION DE DÉBIT
// ════════════════════════════════════════════════════════════════════════════

/**
 * Fenêtre glissante en transaction Firestore.
 * Retourne `{ autorise, raison, attendreS }`.
 *
 * La transaction est indispensable : deux demandes simultanées sur le même
 * numéro liraient sinon le même compteur et passeraient toutes les deux.
 */
async function verifierLimites(telephone, ip) {
  const refNumero = db().collection(C_LIMITES).doc(`tel_${telephone.replace(/\+/g, "")}`);
  const refIp = db().collection(C_LIMITES).doc(`ip_${crypto.createHash("sha1").update(ip).digest("hex")}`);
  const maintenant = Date.now();
  const uneHeure = 60 * 60 * 1000;
  const unJour = 24 * uneHeure;

  return db().runTransaction(async (tx) => {
    const [snapNumero, snapIp] = await Promise.all([tx.get(refNumero), tx.get(refIp)]);

    const numero = snapNumero.exists ? snapNumero.data() : { horodatages: [], dernier: 0 };
    const parIp = snapIp.exists ? snapIp.data() : { horodatages: [] };

    const recentsNumero = (numero.horodatages || []).filter((t) => maintenant - t < unJour);
    const derniereHeureNumero = recentsNumero.filter((t) => maintenant - t < uneHeure);
    const recentsIp = (parIp.horodatages || []).filter((t) => maintenant - t < uneHeure);

    const depuisDernier = maintenant - (numero.dernier || 0);
    if (depuisDernier < LIMITES.cooldownNumeroS * 1000) {
      return {
        autorise: false,
        raison: "cooldown",
        attendreS: Math.ceil((LIMITES.cooldownNumeroS * 1000 - depuisDernier) / 1000),
      };
    }
    if (derniereHeureNumero.length >= LIMITES.parNumeroParHeure) {
      return { autorise: false, raison: "limite_horaire", attendreS: 3600 };
    }
    if (recentsNumero.length >= LIMITES.parNumeroParJour) {
      return { autorise: false, raison: "limite_journaliere", attendreS: 86400 };
    }
    if (recentsIp.length >= LIMITES.parIpParHeure) {
      return { autorise: false, raison: "limite_ip", attendreS: 3600 };
    }

    tx.set(refNumero, { horodatages: [...recentsNumero, maintenant], dernier: maintenant, majA: horodatage() });
    tx.set(refIp, { horodatages: [...recentsIp, maintenant], majA: horodatage() });
    return { autorise: true, raison: null, attendreS: 0 };
  });
}

// ════════════════════════════════════════════════════════════════════════════
// CASCADE DE CANAUX
// ════════════════════════════════════════════════════════════════════════════

/**
 * Ordre des canaux pour cette session.
 * `push` n'est proposé que si l'appareil est de confiance ET que son token FCM
 * est encore frais — un token périmé consommerait le premier échelon de la
 * cascade sans jamais rien livrer.
 */
async function ordreCanaux(telephone, deviceId) {
  const canaux = [];
  const appareil = await chargerAppareilDeConfiance(telephone, deviceId);
  if (appareil?.fcmToken) canaux.push("push");
  canaux.push("sms", "sms_alt", "voice");
  return { canaux, appareil };
}

async function chargerAppareilDeConfiance(telephone, deviceId) {
  if (!deviceId) return null;
  const id = `${cleTelephone(telephone)}_${deviceId}`;
  const snap = await db().collection(C_APPAREILS).doc(id).get();
  if (!snap.exists) return null;

  const donnees = snap.data();
  if (!donnees.fcmToken) return null;

  const vuLe = donnees.fcmTokenVuA?.toMillis?.() ?? 0;
  const age = Date.now() - vuLe;
  if (age > FRAICHEUR_APPAREIL_JOURS * 24 * 3600 * 1000) return null;

  return donnees;
}

/**
 * Envoie le code sur un canal donné.
 * @returns {Promise<{succes: boolean, detail: object}>}
 */
async function envoyerParCanal({ canal, telephone, code, sessionId, appSignature, appareil, langue }) {
  switch (canal) {
    case "push":
      return envoyerPushSilencieux({ appareil, code, sessionId, telephone });
    case "sms":
      return envoyerSmsOtp({ telephone, code, appSignature, langue, senderId: undefined });
    case "sms_alt":
      // Sender ID explicitement vidé : si le rejet venait d'un sender ID non
      // approuvé pour cet opérateur, la route par défaut le contourne.
      return envoyerSmsOtp({ telephone, code, appSignature, langue, senderId: "" });
    case "voice":
      return declencherAppelVocal({ telephone, sessionId, langue });
    default:
      return { succes: false, detail: { erreur: `Canal inconnu : ${canal}` } };
  }
}

/// Identifiant de document dans C_VOIX / C_APPAREILS — le « + » de E.164 est
/// interdit dans un chemin Firestore.
function cleTelephone(telephone) {
  return telephone.replace(/\+/g, "");
}

/// Canal 1 — FCM data-only. Aucune notification affichée : l'app remplit le
/// champ toute seule. `contentAvailable` réveille iOS, `priority: high` évite
/// la mise en file d'attente Doze sur Android.
async function envoyerPushSilencieux({ appareil, code, sessionId, telephone }) {
  if (!appareil?.fcmToken) return { succes: false, detail: { erreur: "aucun token FCM" } };
  try {
    const messageId = await admin.messaging().send({
      token: appareil.fcmToken,
      data: {
        type: "otp_silent",
        sessionId,
        code,
        telephone,
        expiresIn: String(TTL_CODE_S),
      },
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "5", "apns-push-type": "background" },
        payload: { aps: { "content-available": 1 } },
      },
    });
    return { succes: true, detail: { messageId } };
  } catch (e) {
    // Token révoqué / appareil désinstallé : on le retire pour que la prochaine
    // demande n'attende pas 8 secondes sur un canal mort.
    if (e.code === "messaging/registration-token-not-registered") {
      await db()
        .collection(C_APPAREILS)
        .doc(`${telephone.replace(/\+/g, "")}_${appareil.deviceId}`)
        .set({ fcmToken: null }, { merge: true })
        .catch(() => {});
    }
    return { succes: false, detail: { erreur: e.message, code: e.code || null } };
  }
}

/// Canal 2/3 — SMS Africa's Talking au format SMS Retriever.
async function envoyerSmsOtp({ telephone, code, appSignature, langue, senderId }) {
  if (!at.estConfigure()) {
    return { succes: false, detail: { erreur: "Africa's Talking non configuré" } };
  }
  const message = composerSmsRetriever({ code, appSignature, langue });
  const envoi = await at.envoyerSms({ telephone, message, senderId });
  return {
    succes: envoi.succes,
    detail: {
      messageId: envoi.messageId,
      statut: envoi.statut,
      statusCode: envoi.statusCode,
      cout: envoi.cout,
      erreur: envoi.erreur,
    },
  };
}

/**
 * Compose le SMS au format exigé par la SMS Retriever API de Google :
 *   • commence par `<#>` ;
 *   • contient le code ;
 *   • se termine par le hash à 11 caractères de la signature de l'app ;
 *   • fait au plus 140 octets.
 *
 * Sans ces quatre conditions, le SMS arrive bien mais Android ne le transmet
 * pas à l'app : l'utilisateur doit recopier le code à la main. Si l'app n'a
 * pas envoyé sa signature (iOS, ou hash indisponible), on émet un SMS normal.
 */
function composerSmsRetriever({ code, appSignature, langue }) {
  const corps =
    langue === "en"
      ? `Your Horem+ code: ${code}. Valid 5 min. Never share it.`
      : `Votre code Horem+ : ${code}. Valable 5 min. Ne le partagez jamais.`;

  const signatureValide = typeof appSignature === "string" && /^[A-Za-z0-9+/=_-]{11}$/.test(appSignature);
  const message = signatureValide ? `<#> ${corps}\n${appSignature}` : corps;

  // Garde-fou : au-delà de 140 octets, la SMS Retriever API ignore le message.
  if (Buffer.byteLength(message, "utf8") > 140) {
    const court = langue === "en" ? `Horem+ code: ${code}` : `Code Horem+ : ${code}`;
    return signatureValide ? `<#> ${court}\n${appSignature}` : court;
  }
  return message;
}

/// Canal 4 — appel vocal. Le code n'est pas transmis à AT ici : il est dicté
/// par `authOtpVoiceCallback` au décrochage.
///
/// L'index inversé numéro → session est écrit AVANT de déclencher l'appel :
/// sur un numéro qui décroche vite, le callback d'Africa's Talking peut arriver
/// avant que cette fonction n'ait fini, et il ne trouverait rien à dicter.
async function declencherAppelVocal({ telephone, sessionId, langue }) {
  if (!at.estConfigure()) {
    return { succes: false, detail: { erreur: "Africa's Talking non configuré" } };
  }

  await db().collection(C_VOIX).doc(cleTelephone(telephone)).set({
    sessionId,
    telephone,
    langue: langue || "fr",
    creeA: horodatage(),
    expireA: admin.firestore.Timestamp.fromMillis(Date.now() + TTL_CODE_S * 1000),
  });

  const appel = await at.appelVocal({ telephone });
  return {
    succes: appel.succes,
    detail: { sessionIdVocal: appel.sessionId, statut: appel.statut, erreur: appel.erreur },
  };
}

/**
 * Tente les canaux dans l'ordre à partir de `depuis`, et s'arrête au premier
 * qui accepte l'envoi. C'est le cœur de la fiabilité : un canal en panne ne
 * bloque jamais l'utilisateur, la bascule est faite dans la même requête.
 */
async function envoyerAvecCascade({ session, sessionId, canaux, depuis, appareil }) {
  const restants = canaux.slice(depuis);
  const journal = [];

  for (const canal of restants) {
    const resultat = await envoyerParCanal({
      canal,
      telephone: session.telephone,
      code: session.code,
      sessionId,
      appSignature: session.appSignature,
      appareil,
      langue: session.langue,
    });

    journal.push({ canal, succes: resultat.succes, ...resultat.detail, a: Date.now() });

    await tracerLivraison({ sessionId, telephone: session.telephone, canal, resultat });

    if (resultat.succes) {
      return {
        canal,
        index: canaux.indexOf(canal),
        prochainCanal: canaux[canaux.indexOf(canal) + 1] || null,
        journal,
      };
    }
    console.warn(`[OTP] canal ${canal} en échec pour ${masquer(session.telephone)} :`, resultat.detail?.erreur);
  }

  return { canal: null, index: canaux.length, prochainCanal: null, journal };
}

/// Journal de livraison — sert au suivi du taux de délivrabilité réel.
async function tracerLivraison({ sessionId, telephone, canal, resultat }) {
  try {
    await db().collection(C_LIVRAISONS).add({
      sessionId,
      telephone: masquer(telephone),
      canal,
      succes: resultat.succes,
      detail: resultat.detail || {},
      // Corrélation avec le rapport de livraison AT, qui ne connaît que ce champ.
      messageId: resultat.detail?.messageId || null,
      creeA: horodatage(),
    });
  } catch (e) {
    console.warn("[OTP] trace livraison impossible :", e.message);
  }
}

/// Masque un numéro pour les logs (RGPD / loi camerounaise sur les données).
function masquer(telephone) {
  return typeof telephone === "string" && telephone.length > 6
    ? `${telephone.substring(0, 7)}***${telephone.slice(-2)}`
    : "***";
}

// ════════════════════════════════════════════════════════════════════════════
// SESSION UTILISATEUR (après vérification réussie)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Retrouve ou crée le document `users` correspondant au numéro vérifié.
 * L'uid réutilise celui de Firebase Auth quand un compte existe déjà pour ce
 * numéro : sans cela, tous les logements, conversations et paiements des
 * comptes historiques seraient orphelins.
 */
async function trouverOuCreerUtilisateur(telephone) {
  const requete = await db().collection("users").where("telephone", "==", telephone).limit(1).get();
  if (!requete.empty) {
    const doc = requete.docs[0];
    return { uid: doc.id, donnees: doc.data(), nouveau: false };
  }

  // Compte Firebase Auth historique (créé du temps de Phone Auth ou par
  // `creerCompteGratuit`) sans document Firestore aligné sur `telephone`.
  let uid = null;
  try {
    const existant = await admin.auth().getUserByPhoneNumber(telephone);
    uid = existant.uid;
  } catch (_) {
    /* aucun compte Auth — cas nominal d'une première inscription */
  }

  if (uid) {
    const snap = await db().collection("users").doc(uid).get();
    if (snap.exists) {
      // Le document existe mais son champ `telephone` était vide ou différent :
      // on le réaligne pour que la prochaine connexion le retrouve du premier coup.
      await snap.ref.set({ telephone }, { merge: true });
      return { uid, donnees: { ...snap.data(), telephone }, nouveau: false };
    }
  }

  if (!uid) {
    uid = db().collection("users").doc().id;
    if (PONT_FIREBASE) {
      // Le compte Auth doit exister pour que `createCustomToken` produise une
      // identité utilisable par les règles Firestore.
      try {
        const cree = await admin.auth().createUser({ uid, phoneNumber: telephone });
        uid = cree.uid;
      } catch (e) {
        console.warn("[OTP] createUser impossible, uid Firestore conservé :", e.message);
      }
    }
  }

  const donnees = {
    uid,
    telephone,
    nom: "",
    prenom: "",
    email: "",
    role: "prestataire",
    isPremium: false,
    isVerifie: false,
    compteGratuit: false,
    phoneVerified: true,
    phoneVerifiedAt: horodatage(),
    createdAt: horodatage(),
  };
  await db().collection("users").doc(uid).set(donnees, { merge: true });
  return { uid, donnees, nouveau: true };
}

/// Émet le couple access + refresh, et le custom token Firebase si le pont est actif.
async function emettreSession({ uid, telephone, role, deviceId }) {
  const acces = jwt.signerAccessToken({ uid, telephone, role, deviceId });
  const rafraichissement = jwt.genererRefreshToken();

  await db().collection(C_REFRESH).doc(rafraichissement.jti).set({
    uid,
    telephone,
    deviceId: deviceId || null,
    tokenHash: rafraichissement.hash,
    creeA: horodatage(),
    expireA: admin.firestore.Timestamp.fromMillis(rafraichissement.expiresAt),
    revoqueA: null,
    remplacePar: null,
  });

  let jetonFirebase = null;
  if (PONT_FIREBASE) {
    try {
      jetonFirebase = await admin.auth().createCustomToken(uid, { role: role || "prestataire", otp: true });
    } catch (e) {
      // Non bloquant : la session JWT reste valide. Seules les écritures
      // Firestore directes depuis l'app échoueront, ce que l'app signale.
      console.error("[OTP] createCustomToken en échec :", e.message);
    }
  }

  return {
    accessToken: acces.token,
    accessExpiresIn: acces.expiresIn,
    accessExpiresAt: acces.expiresAt,
    refreshToken: rafraichissement.token,
    refreshExpiresAt: rafraichissement.expiresAt,
    firebaseCustomToken: jetonFirebase,
  };
}

/// Mémorise l'appareil pour que la prochaine connexion démarre sur `push`.
async function enregistrerAppareilDeConfiance({ telephone, deviceId, fcmToken, uid }) {
  if (!deviceId) return;
  const id = `${cleTelephone(telephone)}_${deviceId}`;
  await db()
    .collection(C_APPAREILS)
    .doc(id)
    .set(
      {
        uid,
        telephone,
        deviceId,
        ...(fcmToken ? { fcmToken, fcmTokenVuA: horodatage() } : {}),
        derniereConnexion: horodatage(),
        verificationsReussies: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );
}

// ════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE — vérification du JWT maison
// ════════════════════════════════════════════════════════════════════════════

/**
 * Extrait et vérifie l'access token maison d'une requête.
 * Exporté pour que les futures Cloud Functions puissent se passer de
 * `verifyIdToken` (voir OTP_AUTH.md § « Couper le pont »).
 */
function authentifierRequete(req) {
  const entete = req.headers.authorization || "";
  const token = entete.startsWith("Bearer ") ? entete.substring(7) : null;
  if (!token) return { valide: false, charge: null, raison: "absent" };
  return jwt.verifierAccessToken(token);
}

// ════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTIONS
// ════════════════════════════════════════════════════════════════════════════

const OPTIONS = { cors: true, secrets: SECRETS_OTP };

// ─── 1. Demander un code ────────────────────────────────────────────────────
//
// POST { telephone, deviceId?, appSignature?, langue?, canal? }
// → { sessionId, canal, prochainCanal, expiresIn, delaiFallbackSec, appareilDeConfiance }
//
// Le code n'est JAMAIS renvoyé dans la réponse HTTP, même en développement :
// une capture réseau suffirait sinon à prendre la main sur n'importe quel compte.
const authOtpDemander = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { repondreErreur(res, 405, "methode", "Méthode non autorisée"); return; }

  try {
    const { telephone: brut, deviceId, appSignature, langue, canal: canalForce } = req.body || {};

    const telephone = normaliserTelephone(brut);
    if (!telephone) { repondreErreur(res, 400, "telephone_invalide", "Numéro de téléphone invalide"); return; }

    const limites = await verifierLimites(telephone, ipAppelant(req));
    if (!limites.autorise) {
      repondreErreur(res, 429, limites.raison, "Trop de demandes pour ce numéro", { attendreS: limites.attendreS });
      return;
    }

    const { canaux, appareil } = await ordreCanaux(telephone, deviceId);

    // Un canal explicitement demandé (bouton « Recevoir un appel ») passe
    // devant la cascade, mais reste une valeur de la liste connue.
    let depuis = 0;
    if (canalForce && canaux.includes(canalForce)) depuis = canaux.indexOf(canalForce);

    const code = genererCode();
    const sel = crypto.randomBytes(16).toString("hex");
    const sessionId = crypto.randomBytes(16).toString("hex");
    const expireA = Date.now() + TTL_CODE_S * 1000;

    const session = {
      telephone,
      code,                       // en mémoire seulement — jamais persisté
      appSignature: appSignature || null,
      langue: langue === "en" ? "en" : "fr",
    };

    // Le document de session est écrit AVANT l'envoi, pas après. Sinon, quand la
    // cascade atteint le canal vocal, Africa's Talking peut rappeler
    // `authOtpVoiceCallback` (qui a besoin de ce document) avant que la réponse
    // HTTP n'ait fini de l'écrire : l'appel serait muet. On pose donc la session
    // d'abord, puis on met à jour le canal réellement utilisé.
    await db().collection(C_SESSIONS).doc(sessionId).set({
      telephone,
      codeHash: hacherCode(code, sel),
      sel,
      canal: null,
      canauxOrdre: canaux,
      canalIndex: -1,
      journalEnvois: [],
      deviceId: deviceId || null,
      appSignature: appSignature || null,
      langue: session.langue,
      tentatives: 0,
      maxTentatives: MAX_TENTATIVES,
      consomme: false,
      ip: ipAppelant(req),
      creeA: horodatage(),
      expireA: admin.firestore.Timestamp.fromMillis(expireA),
    });

    const envoi = await envoyerAvecCascade({ session, sessionId, canaux, depuis, appareil });

    if (!envoi.canal) {
      // Aucun canal n'a abouti : la session ne mènera nulle part, on la retire
      // pour ne pas laisser un document mort (et un pointeur vocal orphelin).
      console.error(`[OTP] tous les canaux ont échoué pour ${masquer(telephone)}`, envoi.journal);
      await db().collection(C_SESSIONS).doc(sessionId).delete().catch(() => {});
      await db().collection(C_VOIX).doc(cleTelephone(telephone)).delete().catch(() => {});
      repondreErreur(res, 502, "aucun_canal", "Impossible d'envoyer le code pour le moment", {
        journal: envoi.journal.map((j) => ({ canal: j.canal, erreur: j.erreur || null })),
      });
      return;
    }

    await db().collection(C_SESSIONS).doc(sessionId).set({
      canal: envoi.canal,
      canalIndex: envoi.index,
      journalEnvois: envoi.journal,
    }, { merge: true });

    console.log(`[OTP] session ${sessionId.substring(0, 8)}… canal=${envoi.canal} tel=${masquer(telephone)}`);

    res.json({
      success: true,
      sessionId,
      canal: envoi.canal,
      prochainCanal: envoi.prochainCanal,
      expiresIn: TTL_CODE_S,
      delaiFallbackSec: DELAI_FALLBACK_S[envoi.canal] ?? 25,
      appareilDeConfiance: Boolean(appareil),
      // Utile à l'écran de diagnostic ; ne contient jamais le code.
      tentativesCanaux: envoi.journal.map((j) => ({ canal: j.canal, succes: j.succes })),
    });
  } catch (e) {
    console.error("[OTP] authOtpDemander :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

// ─── 2. Escalader vers le canal suivant ─────────────────────────────────────
//
// POST { sessionId, canal? }
// Réutilise la MÊME session (donc le même compteur de tentatives) mais génère
// un nouveau code : rediffuser l'ancien sur un second canal doublerait sa
// fenêtre d'interception.
const authOtpRenvoyer = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { repondreErreur(res, 405, "methode", "Méthode non autorisée"); return; }

  try {
    const { sessionId, canal: canalDemande } = req.body || {};
    if (!sessionId) { repondreErreur(res, 400, "session_absente", "sessionId requis"); return; }

    const ref = db().collection(C_SESSIONS).doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) { repondreErreur(res, 404, "session_inconnue", "Session introuvable ou expirée"); return; }

    const donnees = snap.data();
    if (donnees.consomme) { repondreErreur(res, 409, "session_consommee", "Session déjà utilisée"); return; }
    if (donnees.expireA.toMillis() < Date.now()) {
      repondreErreur(res, 410, "session_expiree", "Session expirée, redemandez un code");
      return;
    }

    const canaux = donnees.canauxOrdre || ["sms", "sms_alt", "voice"];
    let depuis = (donnees.canalIndex ?? 0) + 1;
    if (canalDemande && canaux.includes(canalDemande)) depuis = canaux.indexOf(canalDemande);
    if (depuis >= canaux.length) {
      repondreErreur(res, 409, "canaux_epuises", "Tous les canaux ont été essayés", { canauxEssayes: canaux });
      return;
    }

    const appareil = await chargerAppareilDeConfiance(donnees.telephone, donnees.deviceId);
    const code = genererCode();
    const sel = crypto.randomBytes(16).toString("hex");

    const envoi = await envoyerAvecCascade({
      session: {
        telephone: donnees.telephone,
        code,
        appSignature: donnees.appSignature,
        langue: donnees.langue,
      },
      sessionId,
      canaux,
      depuis,
      appareil,
    });

    if (!envoi.canal) {
      repondreErreur(res, 502, "aucun_canal", "Impossible d'envoyer le code sur les canaux restants");
      return;
    }

    // La fenêtre de validité repart : sinon un renvoi à T+4min laisserait
    // 60 secondes pour saisir un code reçu par appel vocal.
    await ref.set(
      {
        codeHash: hacherCode(code, sel),
        sel,
        canal: envoi.canal,
        canalIndex: envoi.index,
        journalEnvois: [...(donnees.journalEnvois || []), ...envoi.journal],
        expireA: admin.firestore.Timestamp.fromMillis(Date.now() + TTL_CODE_S * 1000),
        renvoyeA: horodatage(),
      },
      { merge: true }
    );

    console.log(`[OTP] renvoi session ${sessionId.substring(0, 8)}… canal=${envoi.canal}`);

    res.json({
      success: true,
      sessionId,
      canal: envoi.canal,
      prochainCanal: envoi.prochainCanal,
      expiresIn: TTL_CODE_S,
      delaiFallbackSec: DELAI_FALLBACK_S[envoi.canal] ?? 25,
    });
  } catch (e) {
    console.error("[OTP] authOtpRenvoyer :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

// ─── 3. Vérifier le code ────────────────────────────────────────────────────
//
// POST { sessionId, code, deviceId?, fcmToken? }
// → { accessToken, refreshToken, firebaseCustomToken, utilisateur }
const authOtpVerifier = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { repondreErreur(res, 405, "methode", "Méthode non autorisée"); return; }

  try {
    const { sessionId, code, deviceId, fcmToken } = req.body || {};
    if (!sessionId || !code) { repondreErreur(res, 400, "parametres", "sessionId et code requis"); return; }

    const ref = db().collection(C_SESSIONS).doc(sessionId);

    // Toute la vérification tient dans une transaction : sans elle, N requêtes
    // parallèles liraient le même compteur `tentatives` et disposeraient chacune
    // des 5 essais, ce qui annulerait la protection anti-force-brute.
    const verdict = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { etat: "inconnue" };

      const s = snap.data();
      if (s.consomme) return { etat: "consommee" };
      if (s.expireA.toMillis() < Date.now()) return { etat: "expiree" };
      if ((s.tentatives || 0) >= (s.maxTentatives || MAX_TENTATIVES)) return { etat: "bloquee" };

      const saisi = String(code).trim();
      if (!codeEgal(hacherCode(saisi, s.sel), s.codeHash)) {
        const tentatives = (s.tentatives || 0) + 1;
        tx.set(ref, { tentatives, derniereTentativeA: horodatage() }, { merge: true });
        return {
          etat: "invalide",
          restantes: Math.max(0, (s.maxTentatives || MAX_TENTATIVES) - tentatives),
        };
      }

      tx.set(ref, { consomme: true, consommeA: horodatage() }, { merge: true });
      return { etat: "ok", telephone: s.telephone, deviceId: s.deviceId, canal: s.canal };
    });

    switch (verdict.etat) {
      case "inconnue":
        repondreErreur(res, 404, "session_inconnue", "Session introuvable"); return;
      case "consommee":
        repondreErreur(res, 409, "session_consommee", "Ce code a déjà été utilisé"); return;
      case "expiree":
        repondreErreur(res, 410, "session_expiree", "Code expiré, demandez-en un nouveau"); return;
      case "bloquee":
        repondreErreur(res, 429, "trop_de_tentatives", "Trop de codes erronés, demandez un nouveau code"); return;
      case "invalide":
        repondreErreur(res, 401, "code_invalide", "Code incorrect", { tentativesRestantes: verdict.restantes }); return;
    }

    const telephone = verdict.telephone;
    const appareilId = deviceId || verdict.deviceId || null;

    const utilisateur = await trouverOuCreerUtilisateur(telephone);
    const role = utilisateur.donnees.role || "prestataire";

    const session = await emettreSession({ uid: utilisateur.uid, telephone, role, deviceId: appareilId });

    await Promise.all([
      enregistrerAppareilDeConfiance({ telephone, deviceId: appareilId, fcmToken, uid: utilisateur.uid }),
      db().collection("users").doc(utilisateur.uid).set(
        {
          phoneVerified: true,
          phoneVerifiedAt: horodatage(),
          derniereConnexion: horodatage(),
          ...(fcmToken ? { fcmToken } : {}),
        },
        { merge: true }
      ),
    ]);

    console.log(
      `[OTP] vérification OK uid=${utilisateur.uid} canal=${verdict.canal} ` +
      `nouveau=${utilisateur.nouveau} tel=${masquer(telephone)}`
    );

    res.json({
      success: true,
      ...session,
      nouvelUtilisateur: utilisateur.nouveau,
      utilisateur: {
        uid: utilisateur.uid,
        telephone,
        role,
        nom: utilisateur.donnees.nom || "",
        prenom: utilisateur.donnees.prenom || "",
        photoUrl: utilisateur.donnees.photoUrl || null,
      },
    });
  } catch (e) {
    console.error("[OTP] authOtpVerifier :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

// ─── 4. Rafraîchir la session ───────────────────────────────────────────────
//
// POST { refreshToken, deviceId? }
// Rotation systématique : le refresh présenté est révoqué et remplacé. Rejouer
// un refresh déjà consommé révoque toute la chaîne — c'est la détection de vol
// de jeton recommandée par l'OAuth 2.1 (« refresh token reuse detection »).
const authTokenRefresh = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { repondreErreur(res, 405, "methode", "Méthode non autorisée"); return; }

  try {
    const { refreshToken, deviceId } = req.body || {};
    const jti = jwt.jtiDeRefreshToken(refreshToken);
    if (!jti) { repondreErreur(res, 400, "refresh_invalide", "Jeton de rafraîchissement invalide"); return; }

    const ref = db().collection(C_REFRESH).doc(jti);
    const snap = await ref.get();
    if (!snap.exists) { repondreErreur(res, 401, "refresh_inconnu", "Session expirée, reconnectez-vous"); return; }

    const donnees = snap.data();

    if (donnees.revoqueA) {
      // Rejeu d'un jeton déjà tourné → jeton volé. On coupe toutes les sessions
      // de cet utilisateur, y compris celle du voleur.
      console.warn(`[OTP] rejeu de refresh détecté uid=${donnees.uid} — révocation globale`);
      await revoquerToutesLesSessions(donnees.uid);
      repondreErreur(res, 401, "refresh_rejoue", "Session compromise, reconnectez-vous");
      return;
    }
    if (donnees.expireA.toMillis() < Date.now()) {
      repondreErreur(res, 401, "refresh_expire", "Session expirée, reconnectez-vous");
      return;
    }
    if (!jwt.hashEgal(jwt.hacherRefreshToken(refreshToken), donnees.tokenHash)) {
      repondreErreur(res, 401, "refresh_invalide", "Jeton de rafraîchissement invalide");
      return;
    }

    const utilisateurSnap = await db().collection("users").doc(donnees.uid).get();
    if (!utilisateurSnap.exists) {
      repondreErreur(res, 401, "compte_absent", "Compte introuvable");
      return;
    }
    const role = utilisateurSnap.data().role || "prestataire";

    const session = await emettreSession({
      uid: donnees.uid,
      telephone: donnees.telephone,
      role,
      deviceId: deviceId || donnees.deviceId,
    });

    await ref.set(
      { revoqueA: horodatage(), remplacePar: jwt.jtiDeRefreshToken(session.refreshToken) },
      { merge: true }
    );

    res.json({ success: true, ...session, utilisateur: { uid: donnees.uid, telephone: donnees.telephone, role } });
  } catch (e) {
    console.error("[OTP] authTokenRefresh :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

// ─── 5. Déconnexion / révocation ────────────────────────────────────────────
//
// POST { refreshToken?, toutesLesSessions? }  · Authorization: Bearer <access>
const authRevoquer = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { repondreErreur(res, 405, "methode", "Méthode non autorisée"); return; }

  try {
    const { refreshToken, toutesLesSessions } = req.body || {};
    const auth = authentifierRequete(req);

    if (toutesLesSessions) {
      if (!auth.valide) { repondreErreur(res, 401, "non_authentifie", "Access token requis"); return; }
      await revoquerToutesLesSessions(auth.charge.sub);
      res.json({ success: true, revoque: "toutes" });
      return;
    }

    const jti = jwt.jtiDeRefreshToken(refreshToken);
    if (jti) {
      await db().collection(C_REFRESH).doc(jti).set({ revoqueA: horodatage() }, { merge: true });
    }
    // Réponse volontairement identique en cas de jeton inconnu : distinguer les
    // deux cas transformerait cet endpoint en oracle d'existence de session.
    res.json({ success: true, revoque: "session" });
  } catch (e) {
    console.error("[OTP] authRevoquer :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

async function revoquerToutesLesSessions(uid) {
  // Filtre `revoqueA == null` appliqué en mémoire, pas dans la requête : deux
  // égalités sur des champs distincts imposeraient un index composite, et ce
  // projet n'a pas de firestore.indexes.json. Le volume est borné — au plus un
  // jeton par rafraîchissement sur 30 jours.
  const jetons = await db().collection(C_REFRESH).where("uid", "==", uid).limit(450).get();
  const actifs = jetons.docs.filter((d) => !d.data().revoqueA);
  if (actifs.length) {
    const lot = db().batch();
    actifs.forEach((doc) => lot.set(doc.ref, { revoqueA: horodatage() }, { merge: true }));
    await lot.commit();
  }
  if (PONT_FIREBASE) {
    // Invalide aussi les ID tokens Firebase déjà émis pour cet utilisateur.
    await admin.auth().revokeRefreshTokens(uid).catch(() => {});
  }
}

// ─── 6. Rapport de livraison Africa's Talking ───────────────────────────────
//
// AT appelle cette URL après chaque SMS. Un « Failed » / « Rejected » déclenche
// l'escalade tout de suite : l'utilisateur reçoit l'appel vocal avant même
// d'avoir compris que le SMS n'arriverait pas.
//
// URL à coller dans le dashboard AT → SMS → Delivery Reports.
const authOtpDeliveryReport = onRequest({ cors: false, secrets: SECRETS_OTP }, async (req, res) => {
  // AT n'attend rien du corps de la réponse et retente en cas de non-200 : on
  // acquitte immédiatement, le traitement suit.
  res.status(200).send("");

  try {
    const { id, status, phoneNumber, failureReason } = req.body || {};
    if (!id) return;

    console.log(`[OTP] rapport AT id=${id} statut=${status} raison=${failureReason || "-"}`);

    await db().collection(C_LIVRAISONS).add({
      type: "rapport",
      messageId: id,
      statut: status || null,
      telephone: masquer(phoneNumber || ""),
      raisonEchec: failureReason || null,
      creeA: horodatage(),
    });

    const echec = ["failed", "rejected"].includes(String(status || "").toLowerCase());
    if (!echec) return;

    // Retrouver la session concernée par ce messageId.
    const trace = await db().collection(C_LIVRAISONS).where("messageId", "==", id).limit(5).get();
    const sessionId = trace.docs.map((d) => d.data().sessionId).find(Boolean);
    if (!sessionId) return;

    const ref = db().collection(C_SESSIONS).doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) return;

    const s = snap.data();
    if (s.consomme || s.expireA.toMillis() < Date.now()) return;

    const canaux = s.canauxOrdre || [];
    const suivant = (s.canalIndex ?? 0) + 1;
    if (suivant >= canaux.length) return;

    const code = genererCode();
    const sel = crypto.randomBytes(16).toString("hex");
    const envoi = await envoyerAvecCascade({
      session: { telephone: s.telephone, code, appSignature: s.appSignature, langue: s.langue },
      sessionId,
      canaux,
      depuis: suivant,
      appareil: await chargerAppareilDeConfiance(s.telephone, s.deviceId),
    });

    if (!envoi.canal) return;

    await ref.set(
      {
        codeHash: hacherCode(code, sel),
        sel,
        canal: envoi.canal,
        canalIndex: envoi.index,
        journalEnvois: [...(s.journalEnvois || []), ...envoi.journal],
        expireA: admin.firestore.Timestamp.fromMillis(Date.now() + TTL_CODE_S * 1000),
        escaladeAutomatiqueA: horodatage(),
      },
      { merge: true }
    );

    console.log(`[OTP] escalade automatique ${sessionId.substring(0, 8)}… → ${envoi.canal}`);
  } catch (e) {
    console.error("[OTP] authOtpDeliveryReport :", e);
  }
});

// ─── 7. Callback vocal Africa's Talking ─────────────────────────────────────
//
// Appelé par AT quand le destinataire décroche. La réponse DOIT être du XML.
// URL à coller dans le dashboard AT → Voice → Callback URL du numéro.
const authOtpVoiceCallback = onRequest({ cors: false, secrets: SECRETS_OTP }, async (req, res) => {
  res.set("Content-Type", "application/xml");

  try {
    const corps = { ...(req.body || {}), ...(req.query || {}) };
    // `destinationNumber` sur un appel sortant = la personne appelée.
    const telephone = normaliserTelephone(corps.destinationNumber || corps.callerNumber || "");
    if (!telephone) { res.status(200).send(at.xmlAucunCode("fr")); return; }

    // Index inversé posé par `declencherAppelVocal` — un simple get() par id.
    const pointeur = await db().collection(C_VOIX).doc(cleTelephone(telephone)).get();
    if (!pointeur.exists) { res.status(200).send(at.xmlAucunCode("fr")); return; }

    const attente = pointeur.data();
    const langueAppel = attente.langue || "fr";
    if (attente.expireA.toMillis() < Date.now()) {
      res.status(200).send(at.xmlAucunCode(langueAppel));
      return;
    }

    const doc = await db().collection(C_SESSIONS).doc(attente.sessionId).get();
    if (!doc.exists) { res.status(200).send(at.xmlAucunCode(langueAppel)); return; }

    const s = doc.data();
    if (s.consomme || s.expireA.toMillis() < Date.now()) {
      res.status(200).send(at.xmlAucunCode(s.langue || langueAppel));
      return;
    }

    // Le code n'est stocké que haché : impossible de le relire. On le remplace
    // donc par un code neuf, dicté immédiatement — la fenêtre d'écoute d'un
    // appel vocal se confond avec celle de la saisie, il n'y a rien à perdre.
    const code = genererCode();
    const sel = crypto.randomBytes(16).toString("hex");
    await doc.ref.set(
      {
        codeHash: hacherCode(code, sel),
        sel,
        canal: "voice",
        canalIndex: (s.canauxOrdre || []).indexOf("voice"),
        expireA: admin.firestore.Timestamp.fromMillis(Date.now() + TTL_CODE_S * 1000),
        dicteA: horodatage(),
      },
      { merge: true }
    );

    console.log(`[OTP] dictée vocale session ${doc.id.substring(0, 8)}… tel=${masquer(telephone)}`);
    res.status(200).send(at.xmlDicterCode(code, s.langue || "fr"));
  } catch (e) {
    console.error("[OTP] authOtpVoiceCallback :", e);
    res.status(200).send(at.xmlAucunCode("fr"));
  }
});

// ─── 8. Purge des documents périmés ─────────────────────────────────────────
//
// Sans ça, `otp_sessions` grossit indéfiniment et le coût de stockage suit.
// Les sessions consommées sont supprimées aussi : leur seul contenu utile
// (le hash du code) est mort une fois la vérification passée.
const purgerOtpExpires = onSchedule("every 6 hours", async () => {
  const maintenant = admin.firestore.Timestamp.now();
  const ilYaTrenteJours = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 3600 * 1000);
  let total = 0;

  const supprimerLot = async (requete) => {
    const snap = await requete.limit(400).get();
    if (snap.empty) return 0;
    const lot = db().batch();
    snap.forEach((d) => lot.delete(d.ref));
    await lot.commit();
    return snap.size;
  };

  total += await supprimerLot(db().collection(C_SESSIONS).where("expireA", "<", maintenant));
  total += await supprimerLot(db().collection(C_VOIX).where("expireA", "<", maintenant));
  total += await supprimerLot(db().collection(C_REFRESH).where("expireA", "<", maintenant));
  total += await supprimerLot(db().collection(C_LIVRAISONS).where("creeA", "<", ilYaTrenteJours));
  total += await supprimerLot(db().collection(C_LIMITES).where("majA", "<", ilYaTrenteJours));

  console.log(`[OTP] purge : ${total} documents supprimés`);
});

// ─── 9. Statistiques de délivrabilité (admin) ───────────────────────────────
//
// Sert à vérifier concrètement l'objectif « 99 %+ » plutôt qu'à le supposer.
// GET · Authorization: Bearer <access token d'un compte role == 'admin'>
const authOtpStatistiques = onRequest(OPTIONS, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  try {
    const auth = authentifierRequete(req);
    if (!auth.valide) { repondreErreur(res, 401, "non_authentifie", "Access token requis"); return; }
    if (auth.charge.role !== "admin") { repondreErreur(res, 403, "interdit", "Réservé aux administrateurs"); return; }

    const heures = Math.min(Number(req.query.heures) || 24, 720);
    const depuis = admin.firestore.Timestamp.fromMillis(Date.now() - heures * 3600 * 1000);

    const [livraisons, sessions] = await Promise.all([
      db().collection(C_LIVRAISONS).where("creeA", ">=", depuis).get(),
      db().collection(C_SESSIONS).where("creeA", ">=", depuis).get(),
    ]);

    const parCanal = {};
    livraisons.forEach((d) => {
      const v = d.data();
      if (v.type === "rapport" || !v.canal) return;
      parCanal[v.canal] ??= { tentatives: 0, succes: 0 };
      parCanal[v.canal].tentatives++;
      if (v.succes) parCanal[v.canal].succes++;
    });
    Object.values(parCanal).forEach((c) => {
      c.taux = c.tentatives ? Number(((c.succes / c.tentatives) * 100).toFixed(2)) : 0;
    });

    let livrees = 0;
    let verifiees = 0;
    sessions.forEach((d) => {
      const v = d.data();
      if (v.canal) livrees++;
      if (v.consomme) verifiees++;
    });

    res.json({
      success: true,
      fenetreHeures: heures,
      sessions: sessions.size,
      // Part des demandes pour lesquelles au moins un canal a accepté l'envoi —
      // c'est la métrique visée par l'objectif 99 %+.
      tauxLivraison: sessions.size ? Number(((livrees / sessions.size) * 100).toFixed(2)) : 0,
      // Part des sessions effectivement validées (inclut les abandons utilisateur).
      tauxVerification: sessions.size ? Number(((verifiees / sessions.size) * 100).toFixed(2)) : 0,
      parCanal,
    });
  } catch (e) {
    console.error("[OTP] authOtpStatistiques :", e);
    repondreErreur(res, 500, "interne", e.message);
  }
});

module.exports = {
  // Cloud Functions
  authOtpDemander,
  authOtpRenvoyer,
  authOtpVerifier,
  authTokenRefresh,
  authRevoquer,
  authOtpDeliveryReport,
  authOtpVoiceCallback,
  authOtpStatistiques,
  purgerOtpExpires,
  // Utilitaires réutilisables par index.js
  authentifierRequete,
  normaliserTelephone,
  SECRETS_OTP,
  PONT_FIREBASE,
};
