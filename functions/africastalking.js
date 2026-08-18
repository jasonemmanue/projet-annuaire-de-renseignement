// ============================================================================
// FICHIER : functions/africastalking.js
// Client HTTP Africa's Talking — SMS + Voice.
//
// Aucune dépendance externe : Node 24 expose `fetch` globalement, l'API AT
// accepte du `application/x-www-form-urlencoded`. Ajouter le SDK officiel
// ferait entrer une chaîne de dépendances entière pour deux appels POST.
//
// Secrets à créer AVANT le premier déploiement :
//   firebase functions:secrets:set AT_USERNAME        ← 'sandbox' ou le username live
//   firebase functions:secrets:set AT_API_KEY         ← clé API du dashboard AT
//   firebase functions:secrets:set AT_SENDER_ID       ← sender ID alphanumérique (optionnel)
//   firebase functions:secrets:set AT_VOICE_NUMBER    ← numéro vocal AT au format +237...
//
// ⚠️ Le username « sandbox » bascule automatiquement sur les endpoints
//    api.sandbox.africastalking.com : aucun SMS réel n'est facturé, mais
//    aucun SMS réel n'arrive non plus. En production, le username est celui
//    du compte live.
// ============================================================================

// ─── Endpoints ──────────────────────────────────────────────────────────────
const AT_SMS_LIVE = "https://api.africastalking.com/version1/messaging";
const AT_SMS_SANDBOX = "https://api.sandbox.africastalking.com/version1/messaging";
const AT_VOICE_LIVE = "https://voice.africastalking.com/call";
const AT_VOICE_SANDBOX = "https://voice.sandbox.africastalking.com/call";

/// Statuts de livraison AT considérés comme « le SMS est parti ».
/// 100 = Processed · 101 = Sent · 102 = Queued
const CODES_ENVOI_OK = [100, 101, 102];

/// Configuration lue depuis les variables d'environnement (Secret Manager).
/// Lève si un secret obligatoire manque : mieux vaut échouer au premier appel
/// avec un message clair qu'envoyer une requête anonyme qui renverra un 401
/// illisible.
function config() {
  const username = process.env.AT_USERNAME;
  const apiKey = process.env.AT_API_KEY;
  if (!username || !apiKey) {
    throw new Error(
      "Africa's Talking non configuré : secrets AT_USERNAME / AT_API_KEY absents. " +
        "Exécuter `firebase functions:secrets:set AT_USERNAME` puis AT_API_KEY."
    );
  }
  const sandbox = username.toLowerCase() === "sandbox";
  return {
    username,
    apiKey,
    sandbox,
    senderId: process.env.AT_SENDER_ID || "",
    voiceNumber: process.env.AT_VOICE_NUMBER || "",
    smsUrl: sandbox ? AT_SMS_SANDBOX : AT_SMS_LIVE,
    voiceUrl: sandbox ? AT_VOICE_SANDBOX : AT_VOICE_LIVE,
  };
}

/// True si les secrets AT sont présents — permet aux appelants de dégrader
/// proprement (cascade → canal suivant) au lieu de planter.
function estConfigure() {
  return Boolean(process.env.AT_USERNAME && process.env.AT_API_KEY);
}

/// POST form-urlencoded avec les en-têtes AT et un timeout dur.
/// Sans timeout, un incident réseau chez AT bloquerait la Cloud Function
/// jusqu'à son propre timeout (60 s) — l'utilisateur attendrait devant un
/// spinner alors que la cascade pourrait déjà être passée au canal suivant.
async function postForm(url, params, apiKey, timeoutMs = 12000) {
  const controller = new AbortController();
  const minuteur = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const reponse = await fetch(url, {
      method: "POST",
      headers: {
        apiKey,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: new URLSearchParams(params).toString(),
      signal: controller.signal,
    });

    const brut = await reponse.text();
    let corps;
    try {
      corps = JSON.parse(brut);
    } catch (_) {
      corps = { raw: brut };
    }
    return { ok: reponse.ok, statut: reponse.status, corps };
  } finally {
    clearTimeout(minuteur);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SMS
// ════════════════════════════════════════════════════════════════════════════

/**
 * Envoie un SMS.
 *
 * @param {object} args
 * @param {string} args.telephone  Destinataire au format E.164 (+237...).
 * @param {string} args.message    Corps du SMS (≤ 140 octets pour SMS Retriever).
 * @param {string} [args.senderId] Écrase le sender ID par défaut — utilisé par
 *                                 la cascade pour retenter sur une autre route.
 * @returns {Promise<{succes: boolean, messageId: string|null, statut: string,
 *                    statusCode: number|null, cout: string|null, erreur: string|null}>}
 */
async function envoyerSms({ telephone, message, senderId }) {
  const cfg = config();

  const params = {
    username: cfg.username,
    to: telephone,
    message,
  };

  // `from` n'est accepté que si le sender ID est enregistré côté AT. Envoyer
  // un sender ID inconnu fait rejeter TOUT le message (InvalidSenderId), donc
  // on ne le pose que s'il est explicitement configuré.
  const expediteur = senderId !== undefined ? senderId : cfg.senderId;
  if (expediteur) params.from = expediteur;

  let reponse;
  try {
    reponse = await postForm(cfg.smsUrl, params, cfg.apiKey);
  } catch (e) {
    const cause = e.name === "AbortError" ? "Timeout Africa's Talking" : e.message;
    return { succes: false, messageId: null, statut: "NetworkError", statusCode: null, cout: null, erreur: cause };
  }

  const destinataires = reponse.corps?.SMSMessageData?.Recipients || [];
  const premier = destinataires[0];

  if (!premier) {
    // AT répond 201 avec une liste vide quand le numéro est rejeté en amont
    // (format invalide, pays non couvert, compte non approvisionné).
    const message = reponse.corps?.SMSMessageData?.Message || `HTTP ${reponse.statut}`;
    return { succes: false, messageId: null, statut: "NoRecipient", statusCode: null, cout: null, erreur: message };
  }

  const code = Number(premier.statusCode);
  return {
    succes: CODES_ENVOI_OK.includes(code),
    messageId: premier.messageId || null,
    statut: premier.status || "Unknown",
    statusCode: Number.isNaN(code) ? null : code,
    cout: premier.cost || null,
    erreur: CODES_ENVOI_OK.includes(code) ? null : `${premier.status} (${premier.statusCode})`,
  };
}

// ════════════════════════════════════════════════════════════════════════════
// VOICE
// ════════════════════════════════════════════════════════════════════════════

/**
 * Déclenche un appel vocal sortant. Le code n'est PAS transmis ici : quand le
 * destinataire décroche, Africa's Talking appelle le callback vocal configuré
 * sur le dashboard, qui répond avec le XML `<Say>` produit par `xmlDicterCode`.
 *
 * @param {object} args
 * @param {string} args.telephone Destinataire au format E.164.
 * @returns {Promise<{succes: boolean, sessionId: string|null, statut: string, erreur: string|null}>}
 */
async function appelVocal({ telephone }) {
  const cfg = config();
  if (!cfg.voiceNumber) {
    return {
      succes: false,
      sessionId: null,
      statut: "NotConfigured",
      erreur: "AT_VOICE_NUMBER absent — aucun numéro vocal Africa's Talking configuré.",
    };
  }

  let reponse;
  try {
    reponse = await postForm(cfg.voiceUrl, {
      username: cfg.username,
      from: cfg.voiceNumber,
      to: telephone,
    }, cfg.apiKey);
  } catch (e) {
    const cause = e.name === "AbortError" ? "Timeout Africa's Talking (voice)" : e.message;
    return { succes: false, sessionId: null, statut: "NetworkError", erreur: cause };
  }

  const entree = (reponse.corps?.entries || [])[0];
  if (!entree) {
    const message = reponse.corps?.errorMessage || `HTTP ${reponse.statut}`;
    return { succes: false, sessionId: null, statut: "NoEntry", erreur: message };
  }

  // AT renvoie « Queued » quand l'appel est accepté ; tout le reste est un refus
  // (Invalid Phone Number, Insufficient Credit, ...).
  const succes = String(entree.status || "").toLowerCase() === "queued";
  return {
    succes,
    sessionId: entree.sessionId || null,
    statut: entree.status || "Unknown",
    erreur: succes ? null : entree.status || "Appel refusé",
  };
}

/**
 * Construit la réponse XML lue par Africa's Talking quand l'utilisateur décroche.
 *
 * Le code est épelé chiffre par chiffre, séparé par des points : la synthèse
 * vocale marque une pause à chaque point, sinon « 123456 » est prononcé
 * « cent vingt-trois mille quatre cent cinquante-six » — inutilisable.
 * La séquence est répétée deux fois, l'utilisateur n'ayant pas de bouton rejouer.
 *
 * @param {string} code   Code à dicter (6 chiffres).
 * @param {string} langue 'fr' ou 'en'.
 */
function xmlDicterCode(code, langue = "fr") {
  const chiffres = String(code).split("").join(" . ");
  const texte =
    langue === "en"
      ? `Hello. Your Horem Plus verification code is. ${chiffres}. I repeat. ${chiffres}. Goodbye.`
      : `Bonjour. Votre code de vérification Horem Plus est. ${chiffres}. Je répète. ${chiffres}. Au revoir.`;

  // `escapeXml` est indispensable : le texte est interpolé dans du XML et un
  // caractère « & » suffirait à rendre la réponse invalide, donc l'appel muet.
  return (
    '<?xml version="1.0" encoding="UTF-8"?>' +
    "<Response>" +
    `<Say voice="woman" playBeep="false">${escapeXml(texte)}</Say>` +
    "</Response>"
  );
}

/// Réponse XML de secours : aucune session OTP trouvée pour ce numéro.
function xmlAucunCode(langue = "fr") {
  const texte =
    langue === "en"
      ? "Sorry, no active verification code was found. Please request a new code in the app. Goodbye."
      : "Désolé, aucun code de vérification actif n'a été trouvé. Veuillez demander un nouveau code dans l'application. Au revoir.";
  return (
    '<?xml version="1.0" encoding="UTF-8"?>' +
    `<Response><Say voice="woman">${escapeXml(texte)}</Say></Response>`
  );
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

module.exports = {
  estConfigure,
  envoyerSms,
  appelVocal,
  xmlDicterCode,
  xmlAucunCode,
  CODES_ENVOI_OK,
};
