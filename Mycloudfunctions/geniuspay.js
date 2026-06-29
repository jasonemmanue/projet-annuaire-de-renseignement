// ============================================================
// FICHIER : functions/geniuspay.js
// Adaptateur REST pour l'API GeniusPay (https://geniuspay.ci).
// Point d'entrée : https://geniuspay.ci/api/v1/merchant
// Méthodes supportées : wave, orange_money, mtn_money
//
// 📌 SECRETS FIREBASE REQUIS :
//   firebase functions:secrets:set GENIUSPAY_API_KEY      ← pk_sandbox_... / pk_live_...
//   firebase functions:secrets:set GENIUSPAY_SECRET_KEY   ← sk_sandbox_... / sk_live_...
//   firebase functions:secrets:set GENIUSPAY_WEBHOOK_SECRET ← secret webhook du portail
// ============================================================

const crypto = require("crypto");

const GENIUSPAY_BASE_URL = "https://geniuspay.ci/api/v1/merchant";

function _creds() {
  const apiKey = process.env.GENIUSPAY_API_KEY;
  const secretKey = process.env.GENIUSPAY_SECRET_KEY;
  const webhookSecret = process.env.GENIUSPAY_WEBHOOK_SECRET;
  if (!apiKey) {
    throw new Error("GENIUSPAY_API_KEY absent. Configurez-le via Firebase Secrets.");
  }
  return { apiKey, secretKey: secretKey || "", webhookSecret: webhookSecret || "" };
}

/**
 * Initie un paiement GeniusPay.
 *
 * Méthodes : 'wave' | 'orange_money' | 'mtn_money'
 * Retourne : { paymentUrl, reference, raw }
 */
async function createPayment({
  reference,
  amount,
  currency = "XOF",  // GeniusPay (geniuspay.ci) n'accepte pas XAF
  paymentMethod = "pawapay",
  mmoProvider,        // ex: 'ORANGE_CMR' | 'MTN_MOMO_CMR' (PawaPay)
  customerCountry,    // ex: 'CM'
  description,
  customerEmail,
  customerPhone,
  metadata = {},
  callbackUrl,
  returnUrl,
  errorUrl,
}) {
  const { apiKey, secretKey } = _creds();

  const body = {
    amount,
    currency,
    payment_method: paymentMethod,
    // Opérateur explicite (PawaPay) — sinon auto-détection depuis le numéro.
    ...(mmoProvider ? { mmo_provider: mmoProvider } : {}),
    description: description || "Paiement Horem+",
    customer: {
      email: customerEmail || "",
      ...(customerPhone ? { phone: customerPhone } : {}),
      ...(customerCountry ? { country: customerCountry } : {}),
    },
    metadata: { ...metadata, internal_reference: reference },
    callback_url: callbackUrl,
    success_url: returnUrl || "",
    error_url: errorUrl || returnUrl || "",
  };

  // Auth GeniusPay : X-API-Key (clé publique) + X-API-Secret (clé secrète).
  // Cf. doc officielle : https://geniuspay.ci/docs/api#authentication
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json", // ⚠️ sinon Laravel redirige (302) au lieu de renvoyer du JSON
    "X-API-Key": apiKey,
    "X-API-Secret": secretKey || apiKey,
  };

  // Retry automatique sur erreurs de passerelle (Cloudflare 5xx) :
  // la sandbox GeniusPay renvoie parfois un 522/503 transitoire.
  const GATEWAY_ERRORS = [502, 503, 504, 522, 524];
  const MAX_TENTATIVES = 3;
  let res, json = {};

  for (let tentative = 1; tentative <= MAX_TENTATIVES; tentative++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 25000); // 25 s max par appel
    try {
      res = await fetch(`${GENIUSPAY_BASE_URL}/payments`, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
    } catch (e) {
      clearTimeout(t);
      console.warn(`GeniusPay tentative ${tentative} : ${e.name} ${e.message}`);
      if (tentative === MAX_TENTATIVES) {
        throw new Error("GeniusPay injoignable (timeout réseau). Réessayez dans un instant.");
      }
      await new Promise((r) => setTimeout(r, 1500 * tentative));
      continue;
    }
    clearTimeout(t);

    json = {};
    try { json = await res.json(); } catch (_) {}

    // Erreur de passerelle transitoire → on retente
    if (GATEWAY_ERRORS.includes(res.status) && tentative < MAX_TENTATIVES) {
      console.warn(`GeniusPay HTTP ${res.status} (tentative ${tentative}/${MAX_TENTATIVES}), nouvel essai…`);
      await new Promise((r) => setTimeout(r, 1500 * tentative));
      continue;
    }
    break; // succès ou erreur définitive
  }

  if (!res.ok) {
    if (GATEWAY_ERRORS.includes(res.status)) {
      throw new Error(
        `Le service GeniusPay est temporairement indisponible (HTTP ${res.status}). Réessayez dans quelques instants.`
      );
    }
    throw new Error(
      `GeniusPay createPayment a échoué (HTTP ${res.status}) : ${JSON.stringify(json)}`
    );
  }

  const data = json.data || json;
  console.log("GeniusPay paiement créé:", data.reference, "→", data.payment_url);

  return {
    paymentUrl: data.payment_url || data.paymentUrl || data.url ||
                data.checkout_url || data.payment_link || data.link || "",
    reference:  data.reference   || reference,
    transactionId: data.transaction_id || data.id || data.transactionId || reference,
    raw: json,
  };
}

/**
 * Récupère le statut d'un paiement (source de vérité pour le webhook).
 * Statuts GeniusPay : 'completed' | 'failed' | 'cancelled' | 'pending'
 */
async function checkPayment(reference) {
  const { apiKey, secretKey } = _creds();
  const headers = {
    Accept: "application/json",
    "X-API-Key": apiKey,
    "X-API-Secret": secretKey || apiKey,
  };

  // Extrait un statut chaîne depuis un objet paiement (quelle que soit la forme).
  const lireStatut = (obj) => {
    if (!obj) return null;
    const v = obj.status ?? obj.state ?? obj.payment_status ?? obj.transaction_status;
    return v != null ? String(v).toLowerCase() : null;
  };

  // On essaie plusieurs endpoints de lecture (l'API GeniusPay varie).
  const urls = [
    `${GENIUSPAY_BASE_URL}/transactions/${reference}`,
    `${GENIUSPAY_BASE_URL}/payments/${reference}`,
    `${GENIUSPAY_BASE_URL}/payments?reference=${encodeURIComponent(reference)}`,
  ];

  let lastJson = {};
  for (const url of urls) {
    try {
      const res = await fetch(url, { method: "GET", headers });
      let json = {};
      try { json = await res.json(); } catch (_) {}
      lastJson = json;

      if (json && json.success === false) continue; // NOT_FOUND → endpoint suivant

      // Réponse liste (data = tableau) ou objet unique
      let obj = json.data;
      if (Array.isArray(obj)) obj = obj[0];
      if (!obj) obj = json;

      const status = lireStatut(obj);
      if (status) {
        console.log("GeniusPay checkPayment:", reference, "→", status, "(via", url, ")");
        return { status, raw: json };
      }
    } catch (e) {
      console.warn("checkPayment endpoint échoué:", url, e.message);
    }
  }

  console.log("GeniusPay checkPayment:", reference, "→ introuvable/pending");
  return { status: "pending", raw: lastJson };
}

/**
 * Vérifie la signature HMAC-SHA256 du webhook GeniusPay.
 * En-tête attendu : X-GeniusPay-Signature (ou similaire).
 */
function verifyWebhookSignature(rawBody, receivedSig) {
  const { webhookSecret } = _creds();
  if (!webhookSecret || !receivedSig) {
    console.warn("GeniusPay : vérification signature désactivée.");
    return true;
  }
  const expected = crypto
    .createHmac("sha256", webhookSecret)
    .update(rawBody)
    .digest("hex");
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected,                          "hex"),
      Buffer.from(receivedSig.replace(/^sha256=/, ""), "hex")
    );
  } catch (_) {
    return false;
  }
}

module.exports = { GENIUSPAY_BASE_URL, createPayment, checkPayment, verifyWebhookSignature };
