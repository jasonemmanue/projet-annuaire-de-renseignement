// ============================================================
// FICHIER : functions/cinetpay.js
// Adaptateur ISOLÉ pour l'API CinetPay (https://cinetpay.com).
// Toute la spécificité du fournisseur de paiement vit ici.
//
// ⚠️ NON UTILISÉ tant que l'app tourne en MODE SIMULATION
//    (paiement_service.dart → kSimulationPaiement = true).
//
// Contrat d'API CinetPay (v2) :
//   Base URL       : https://api-checkout.cinetpay.com/v2
//   Init paiement  : POST /payment
//                    body { apikey, site_id, transaction_id, amount,
//                           currency, description, notify_url, return_url,
//                           channels, customer_* }
//                    → code "201" + data { payment_token, payment_url }
//   Vérif. statut  : POST /payment/check
//                    body { apikey, site_id, transaction_id }
//                    → data.status : "ACCEPTED" | "REFUSED" | "PENDING" ...
//   Webhook (notify_url) : CinetPay POST cpm_trans_id ; NE PAS faire
//                    confiance au corps → toujours RE-VÉRIFIER via /payment/check.
//
// Clés (variables d'environnement runtime) :
//   CINETPAY_APIKEY · CINETPAY_SITE_ID
//   (À fournir uniquement pour le mode réel.)
// ============================================================

const CINETPAY_BASE_URL = "https://api-checkout.cinetpay.com/v2";

function _creds() {
  const apikey = process.env.CINETPAY_APIKEY;
  const siteId = process.env.CINETPAY_SITE_ID;
  if (!apikey || !siteId) {
    throw new Error(
      "Clés CinetPay absentes : définissez CINETPAY_APIKEY et CINETPAY_SITE_ID."
    );
  }
  return { apikey, siteId };
}

/**
 * Initie un paiement CinetPay.
 * `transactionId` est généré par NOUS (sert de clé Firestore + suivi).
 * Retourne { paymentUrl, paymentToken, raw }.
 */
async function createPayment({
  transactionId,
  amount,
  currency = "XAF",
  description,
  customer, // { name, surname, email, phone }
  notifyUrl,
  returnUrl,
  channels = "ALL", // "ALL" | "MOBILE_MONEY" | "CREDIT_CARD"
}) {
  const { apikey, siteId } = _creds();

  const body = {
    apikey,
    site_id: siteId,
    transaction_id: transactionId,
    amount, // ⚠️ multiple de 5 exigé pour XAF/XOF
    currency,
    description: description || "Paiement ImmoConnect",
    notify_url: notifyUrl,
    return_url: returnUrl,
    channels,
    customer_name: customer?.name || "Client",
    customer_surname: customer?.surname || "ImmoConnect",
    customer_email: customer?.email || "",
    customer_phone_number: customer?.phone || "",
    customer_address: "Cameroun",
    customer_city: "Yaounde",
    customer_country: "CM",
    customer_state: "CM",
    customer_zip_code: "00000",
  };

  const res = await fetch(`${CINETPAY_BASE_URL}/payment`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  let json = {};
  try {
    json = await res.json();
  } catch (_) {
    /* corps non-JSON */
  }

  // CinetPay : code "201" = création réussie
  if (json.code !== "201" || !json.data) {
    throw new Error(`CinetPay createPayment a échoué : ${JSON.stringify(json)}`);
  }

  return {
    paymentUrl: json.data.payment_url,
    paymentToken: json.data.payment_token,
    raw: json.data,
  };
}

/**
 * Vérifie le statut réel d'une transaction (source de vérité).
 * Retourne { status, raw }. status === "ACCEPTED" → paiement abouti.
 */
async function checkPayment(transactionId) {
  const { apikey, siteId } = _creds();
  const res = await fetch(`${CINETPAY_BASE_URL}/payment/check`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      apikey,
      site_id: siteId,
      transaction_id: transactionId,
    }),
  });
  let json = {};
  try {
    json = await res.json();
  } catch (_) {
    /* ignore */
  }
  return { status: (json && json.data && json.data.status) || "UNKNOWN", raw: json };
}

module.exports = { CINETPAY_BASE_URL, createPayment, checkPayment };
