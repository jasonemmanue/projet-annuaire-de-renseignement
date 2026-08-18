// ============================================================================
// FICHIER : functions/jwt.js
// JWT maison (HS256) + jetons de rafraîchissement opaques.
//
// Pourquoi pas `jsonwebtoken` ? La signature HS256 tient en trois appels au
// module `crypto` de Node. Une dépendance de plus, c'est une surface de mise à
// jour de plus sur un chemin critique (l'authentification) pour zéro gain.
//
// Secret à créer AVANT le premier déploiement :
//   firebase functions:secrets:set JWT_SECRET       ← ≥ 32 octets aléatoires
//   (générer : node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))")
//
// ⚠️ Changer JWT_SECRET invalide TOUS les access tokens en circulation.
//    Les refresh tokens survivent (ils sont stockés hachés en Firestore, pas
//    signés) : les sessions se rétablissent seules au prochain refresh.
// ============================================================================

const crypto = require("crypto");

/// Durées de vie — cahier des charges : access 1 h, refresh 30 j.
const ACCESS_TTL_S = 60 * 60;              // 1 heure
const REFRESH_TTL_S = 30 * 24 * 60 * 60;   // 30 jours
const ISSUER = "horemplus-auth";

function secret() {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) {
    throw new Error(
      "JWT_SECRET absent ou trop court (< 32 caractères). " +
        "Exécuter `firebase functions:secrets:set JWT_SECRET`."
    );
  }
  return s;
}

function b64url(input) {
  return Buffer.from(input).toString("base64url");
}

function signature(entete, charge, cle) {
  return crypto
    .createHmac("sha256", cle)
    .update(`${entete}.${charge}`)
    .digest("base64url");
}

// ════════════════════════════════════════════════════════════════════════════
// ACCESS TOKEN
// ════════════════════════════════════════════════════════════════════════════

/**
 * Signe un access token HS256.
 *
 * @param {object} args
 * @param {string} args.uid       Identifiant utilisateur (= uid Firestore).
 * @param {string} args.telephone Numéro E.164 vérifié.
 * @param {string} args.role      'client' | 'prestataire' | 'admin'.
 * @param {string} [args.deviceId]
 * @param {number} [args.ttlSecondes]
 * @returns {{token: string, expiresIn: number, expiresAt: number, jti: string}}
 */
function signerAccessToken({ uid, telephone, role, deviceId, ttlSecondes = ACCESS_TTL_S }) {
  const maintenant = Math.floor(Date.now() / 1000);
  const jti = crypto.randomBytes(12).toString("hex");

  const entete = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const charge = b64url(
    JSON.stringify({
      iss: ISSUER,
      sub: uid,
      phone: telephone,
      role: role || "prestataire",
      did: deviceId || null,
      typ: "access",
      jti,
      iat: maintenant,
      exp: maintenant + ttlSecondes,
    })
  );

  return {
    token: `${entete}.${charge}.${signature(entete, charge, secret())}`,
    expiresIn: ttlSecondes,
    expiresAt: (maintenant + ttlSecondes) * 1000,
    jti,
  };
}

/**
 * Vérifie un access token.
 * @returns {{valide: boolean, charge: object|null, raison: string|null}}
 */
function verifierAccessToken(token) {
  if (typeof token !== "string") return { valide: false, charge: null, raison: "absent" };

  const parties = token.split(".");
  if (parties.length !== 3) return { valide: false, charge: null, raison: "format" };

  const [entete, charge, sig] = parties;
  const attendue = signature(entete, charge, secret());

  // Comparaison à temps constant. Un `===` fuiterait, par son temps de retour,
  // le nombre d'octets corrects — de quoi forger une signature octet par octet.
  const a = Buffer.from(sig);
  const b = Buffer.from(attendue);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { valide: false, charge: null, raison: "signature" };
  }

  let donnees;
  try {
    donnees = JSON.parse(Buffer.from(charge, "base64url").toString("utf8"));
  } catch (_) {
    return { valide: false, charge: null, raison: "charge illisible" };
  }

  if (donnees.iss !== ISSUER) return { valide: false, charge: null, raison: "issuer" };
  if (donnees.typ !== "access") return { valide: false, charge: null, raison: "type" };
  if (typeof donnees.exp !== "number" || donnees.exp <= Math.floor(Date.now() / 1000)) {
    return { valide: false, charge: null, raison: "expire" };
  }

  return { valide: true, charge: donnees, raison: null };
}

// ════════════════════════════════════════════════════════════════════════════
// REFRESH TOKEN
// ════════════════════════════════════════════════════════════════════════════
//
// Un refresh token n'est PAS un JWT : c'est 32 octets aléatoires, dont seul le
// SHA-256 est stocké en base. Une fuite de la base ne permet donc pas de
// rejouer une session, alors qu'un JWT auto-porteur de 30 jours resterait
// valable jusqu'à son expiration sans moyen de le révoquer.

/**
 * Génère un refresh token opaque.
 * @returns {{token: string, hash: string, jti: string, expiresAt: number}}
 */
function genererRefreshToken() {
  const jti = crypto.randomBytes(12).toString("hex");
  const secretAleatoire = crypto.randomBytes(32).toString("base64url");
  // Le jti est préfixé dans le token remis au client : le serveur retrouve
  // ainsi le document Firestore en O(1) sans balayer la collection.
  const token = `${jti}.${secretAleatoire}`;
  return {
    token,
    hash: hacherRefreshToken(token),
    jti,
    expiresAt: Date.now() + REFRESH_TTL_S * 1000,
  };
}

function hacherRefreshToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

/// Extrait le jti d'un refresh token présenté par un client (null si malformé).
function jtiDeRefreshToken(token) {
  if (typeof token !== "string") return null;
  const point = token.indexOf(".");
  if (point <= 0) return null;
  const jti = token.substring(0, point);
  return /^[a-f0-9]{24}$/.test(jti) ? jti : null;
}

/// Comparaison à temps constant de deux hachages hexadécimaux.
function hashEgal(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

module.exports = {
  ACCESS_TTL_S,
  REFRESH_TTL_S,
  signerAccessToken,
  verifierAccessToken,
  genererRefreshToken,
  hacherRefreshToken,
  jtiDeRefreshToken,
  hashEgal,
};
