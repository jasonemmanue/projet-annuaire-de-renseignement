const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const geniuspay = require("./geniuspay");
const nodemailer = require("nodemailer");

// ── Email admin ──
// Secrets à configurer AVANT le premier déploiement :
//   firebase functions:secrets:set GMAIL_SENDER_EMAIL    (ex: horemplus.notif@gmail.com)
//   firebase functions:secrets:set GMAIL_APP_PASSWORD    (mot de passe d'app Gmail)
const ADMIN_EMAIL = "Horem+49@gmail.com";

// ── GeniusPay – paiement Mobile Money Cameroun (MTN / Orange) ──
// Clés à configurer via Firebase Secrets :
//   firebase functions:secrets:set GENIUSPAY_API_KEY
//   firebase functions:secrets:set GENIUSPAY_SECRET_KEY
//
// URL webhook GeniusPay → remplacer [project-id] par votre projet Firebase.
// ⚠️ Vérifier l'URL exacte après déploiement (firebase deploy --only functions).
const GENIUSPAY_WEBHOOK_URL =
  "https://geniuspaywebhook-qhxw7o6nha-uc.a.run.app";

// ── Tarifs ──
const DEVISE = "XOF";          // GeniusPay (CI) accepte XOF — même cours que XAF (655,957/EUR)
const MIN_PAIEMENT = 200;      // plancher (100/150 → 200)
const PREMIUM_MONTANT = 200;   // XAF / mois
const PREMIUM_DUREE_JOURS = 30;

// Sponsoring à tarif fixe — Semaine / 2 semaines / Mois
const SPONSOR_TARIFS = { "1s": 500, "2s": 1000, "1m": 2000 };
const SPONSOR_DUREES = { "1s": 7, "2s": 14, "1m": 30 };   // jours
const SPONSOR_DUREE_JOURS = 30;        // durée d'une sponsorisation (legacy/default)
const URGENCE_DUREE_HEURES = 48;       // accès prioritaire visiteur
const PUBLICITE_DUREE_JOURS = 4;       // durée d'une diffusion publicitaire
const PUBLICITE_MONTANT = 500;         // XAF par période de 4 jours
const VISIBILITE_DUREE_JOURS = 365;    // visibilité annuelle (entreprise/restaurant/école)
const VISIBILITE_TARIFS = {            // tarifs visibilité annuelle par type (clé en minuscules)
  "entreprise": 3000,
  "restaurant / snack": 2000,
  "école": 1000,
};

// ── GRILLE DE PRIX (miroir de lib/services/tarification_service.dart) ──
function planche(montant) {
  const m = Math.round(montant);
  return m < MIN_PAIEMENT ? MIN_PAIEMENT : m;
}

// Commission sponsorisation = % du prix du bien selon grade + type.
// Fallback : 5% pour tout type non reconnu par la grille.
function pourcentageCommission(grade, typeBien) {
  const t = (typeBien || "").toLowerCase();
  switch (grade) {
    case "haut_standing": return 0.05;
    case "a_louer":
      if (t.includes("boutique") || t.includes("espace") || t.includes("terrain") ||
          t.includes("bureau") || t.includes("commerce") || t.includes("magasin")) {
        return 0.03;
      }
      return 0.05; // autres types → 5%
    case "meubles":
      if (t.includes("auberge")) return 0.03;
      if (t.includes("motel") || t.includes("meubl")) return 0.035;
      if (t.includes("45") || t.includes("4") || t.includes("5")) return 0.05;
      if (t.includes("23") || t.includes("2") || t.includes("3")) return 0.04;
      if (t.includes("1")) return 0.035;
      return 0.05; // fallback meublés → 5%
    case "standards":
    default:
      if (t.includes("chambre") || t.includes("studio") ||
          t.includes("appartement") || t.includes("villa")) {
        return 0.03;
      }
      return 0.05; // autres types → 5%
  }
}

function montantSponsorisation(grade, typeBien, prixBien) {
  return planche((prixBien || 0) * pourcentageCommission(grade, typeBien));
}

// Frais d'urgence visiteur (fixe) selon grade + type, planché à 200.
function fraisUrgence(grade, typeBien) {
  const t = (typeBien || "").toLowerCase();
  let brut;
  if (grade === "meubles") {
    if (t.includes("appartement")) brut = 500;
    else if (t.includes("studio")) brut = 300;
    else if (t.includes("chambre")) brut = 200;
    else if (t.includes("45") || t.includes("4") || t.includes("5")) brut = 500;
    else if (t.includes("23") || t.includes("2") || t.includes("3")) brut = 200;
    else brut = 100;
  } else if (grade === "haut_standing") {
    brut = t.includes("appartement") ? 200 : 150;
  } else {
    brut = t.includes("appartement") ? 150 : 100;
  }
  return planche(brut);
}

// Code opérateur Flutter → mmo_provider PawaPay (Cameroun).
//   'orange' → ORANGE_CMR · 'mtn' → MTN_MOMO_CMR
// (Si l'opérateur est inconnu, on renvoie undefined → auto-détection
//  PawaPay depuis le numéro +237.)
function mmoProviderCM(operateur) {
  const o = (operateur || "").toLowerCase();
  if (o.includes("mtn")) return "MTN_MOMO_CMR";
  if (o.includes("orange")) return "ORANGE_CMR";
  return undefined;
}

// URLs de redirection post-checkout (cosmétiques : la confirmation
// réelle passe par le webhook). Adaptez à votre hébergement.
const PAIEMENT_SUCCESS_URL = "https://sgk-home.web.app/paiement/succes";
const PAIEMENT_ERROR_URL  = "https://sgk-home.web.app/paiement/echec";

// ================================================================
// INITIALISATION FIREBASE ADMIN
// En production sur Firebase : admin.initializeApp() suffit.
// En local avec l'émulateur, décommente les 3 lignes ci-dessous :
// const serviceAccount = require("./serviceAccountKey.json");
// admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
// ================================================================
admin.initializeApp();
// Évite les crash si un champ vaut undefined (les champs absents sont ignorés).
admin.firestore().settings({ ignoreUndefinedProperties: true });

// ================================================================
// CLOUD FUNCTION 1 : sendChatNotification
// Déclenchée à chaque nouveau message dans une conversation.
// Envoie une notification push au destinataire via FCM.
// ================================================================
exports.sendChatNotification = onDocumentCreated(
  "conversations/{convId}/messages/{msgId}",
  async (event) => {
    const msg = event.data.data();
    const convId = event.params.convId;

    const senderId = msg.senderId;
    const text = msg.text ?? "";
    const type = msg.type ?? "text";

    // Corps de la notification selon le type de message
    let notifBody;
    if (type === "image") {
      notifBody = "📷 Vous a envoyé une photo";
    } else if (type === "file") {
      notifBody = `📎 ${msg.fileName ?? "Fichier"}`;
    } else {
      notifBody = text.length > 100 ? text.substring(0, 100) + "…" : text;
    }

    try {
      // 1. Récupère la conversation pour trouver le destinataire
      const convDoc = await admin.firestore()
        .collection("conversations")
        .doc(convId)
        .get();

      if (!convDoc.exists) {
        console.log("Conversation introuvable :", convId);
        return null;
      }

      const conv = convDoc.data();
      const participants = conv.participants ?? [];

      // Le destinataire = l'autre participant
      const recipientId = participants.find((p) => p !== senderId);

      if (!recipientId) {
        console.log("Pas de destinataire trouvé");
        return null;
      }

      // Les visiteurs anonymes n'ont pas de token FCM
      if (recipientId.startsWith("visiteur_")) {
        console.log("Destinataire visiteur anonyme, pas de push");
        return null;
      }

      // 2. Récupère le nom de l'expéditeur
      let senderName = "Nouveau message";
      if (senderId.startsWith("visiteur_")) {
        // Utilise le contact_label stocké dans la conversation si dispo
        senderName = conv.contact_label ?? "Visiteur";
      } else {
        const senderDoc = await admin.firestore()
          .collection("users")
          .doc(senderId)
          .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          senderName =
            `${senderData.prenom ?? ""} ${senderData.nom ?? ""}`.trim() ||
            "Nouveau message";
        }
      }

      // 3. Récupère le token FCM du destinataire
      const recipientDoc = await admin.firestore()
        .collection("users")
        .doc(recipientId)
        .get();

      if (!recipientDoc.exists) {
        console.log("Destinataire introuvable dans Firestore :", recipientId);
        return null;
      }

      const token = recipientDoc.data()?.fcmToken;
      if (!token) {
        console.log("Pas de token FCM pour :", recipientId);
        return null;
      }

      // 4. Envoie la notification via FCM HTTP v1
      const messagePayload = {
        token,
        notification: {
          title: `💬 ${senderName}`,
          body: notifBody,
        },
        data: {
          type: "message",
          conversationId: convId,
          logementTitre: conv.logement_titre ?? "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "sgkhome_messages",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
            sound: "default",
            priority: "max",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: `💬 ${senderName}`,
                body: notifBody,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      const response = await admin.messaging().send(messagePayload);
      console.log("Notification message envoyée :", response);
      return response;

    } catch (error) {
      console.error("Erreur sendChatNotification :", error);
      return null;
    }
  }
);

// ================================================================
// CLOUD FUNCTION 2 : sendNouvelleAnnonceNotification
// Déclenchée à chaque nouvelle annonce publiée par un prestataire.
// Envoie une notification push à tous les utilisateurs avec un token FCM.
//
// MISE À JOUR : le payload data inclut désormais :
//   • type: "nouvelle_annonce"    → détecté par NotificationService
//   • logementId                  → permet la navigation vers le détail
//   • click_action                → requis par Flutter sur Android
// ================================================================
exports.sendNouvelleAnnonceNotification = onDocumentCreated(
  "logements/{logementId}",
  async (event) => {
    const logement = event.data.data();
    const logementId = event.params.logementId;

    // Ne notifie pas un brouillon en attente de paiement.
    // La notification sera émise par appliquerTransactionReussie après paiement.
    if (logement.paymentPending === true || logement.disponible === false) {
      console.log("Skip notif (brouillon ou indisponible):", logementId);
      return null;
    }

    const titre = logement.titre ?? "Nouvelle annonce";
    const ville = logement.ville ?? "";
    const quartier = logement.quartier ?? "";

    const notifTitle = "🏠 Nouvelle annonce";
    const notifBody = `${titre} – ${quartier}, ${ville}`;

    try {
      // Récupère tous les tokens FCM — on exclut le prestataire auteur.
      // Le champ canonique du propriétaire est `uid_prestataire`
      // (fallback `prestataireId` pour les anciens documents).
      const prestataireId =
        logement.uid_prestataire ?? logement.prestataireId ?? "";

      const usersSnap = await admin.firestore()
        .collection("users")
        .get();

      const tokens = usersSnap.docs
        // Exclut le prestataire qui vient de publier l'annonce
        .filter((d) => d.id !== prestataireId)
        .map((d) => d.data().fcmToken)
        .filter((t) => !!t && typeof t === "string");

      if (tokens.length === 0) {
        console.log("Aucun token FCM disponible pour les nouvelles annonces");
        return null;
      }

      // Envoie en batch (max 500 par sendEachForMulticast)
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);

        const multicastMessage = {
          tokens: chunk,
          notification: {
            title: notifTitle,
            body: notifBody,
          },
          // ── Payload data mis à jour ──────────────────────────────
          data: {
            type: "nouvelle_annonce",          // ← type unifié côté Flutter
            logementId: logementId,            // ← navigation directe
            titre: titre,
            ville: ville,
            quartier: quartier,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          // ────────────────────────────────────────────────────────
          android: {
            priority: "high",
            notification: {
              channelId: "sgkhome_annonces",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: notifTitle,
                  body: notifBody,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        const result = await admin.messaging().sendEachForMulticast(multicastMessage);
        console.log(
          `Annonce notifiée : ${result.successCount} succès, ${result.failureCount} échecs`
        );

        // Nettoie les tokens invalides
        const failedTokens = [];
        result.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const code = resp.error?.code;
            if (
              code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered"
            ) {
              failedTokens.push(chunk[idx]);
            }
          }
        });

        // Supprime les tokens invalides de Firestore
        if (failedTokens.length > 0) {
          const badTokenUsers = await admin.firestore()
            .collection("users")
            .where("fcmToken", "in", failedTokens)
            .get();

          const cleanupBatch = admin.firestore().batch();
          badTokenUsers.docs.forEach((doc) => {
            cleanupBatch.update(doc.ref, { fcmToken: null });
          });
          await cleanupBatch.commit();
          console.log(`${failedTokens.length} tokens invalides supprimés`);
        }
      }

      return null;

    } catch (error) {
      console.error("Erreur sendNouvelleAnnonceNotification :", error);
      return null;
    }
  }
);

// ================================================================
// CLOUD FUNCTION 3 : cleanupOldMessages
// Supprime les messages de plus de 90 jours.
// Planifiée toutes les semaines (168 heures).
// ================================================================
exports.cleanupOldMessages = onSchedule("every 168 hours", async () => {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 90);

  const conversations = await admin.firestore()
    .collection("conversations")
    .get();

  const deletePromises = [];

  for (const conv of conversations.docs) {
    const oldMessages = await admin.firestore()
      .collection("conversations")
      .doc(conv.id)
      .collection("messages")
      .where("timestamp", "<", cutoff)
      .get();

    oldMessages.docs.forEach((doc) => {
      deletePromises.push(doc.reference.delete());
    });
  }

  await Promise.all(deletePromises);
  console.log(`Nettoyage : ${deletePromises.length} messages supprimés`);
  return null;
});

// ================================================================
// CLOUD FUNCTION 4 : sendVuesMilestoneNotification
// Déclenchée à chaque mise à jour d'un document logement.
// Si le champ "vues" franchit un seuil (10, 50, 100, 500),
// envoie une notification push au prestataire propriétaire.
//
// Anti-doublon : un sous-champ "vues_milestones_notified" stocke
// les seuils déjà notifiés pour éviter les envois multiples.
// ================================================================
exports.sendVuesMilestoneNotification = onDocumentUpdated(
  "logements/{logementId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const logementId = event.params.logementId;

    const vuesAvant = before.vues ?? 0;
    const vuesApres = after.vues ?? 0;

    // Pas de changement sur le compteur → rien à faire
    if (vuesAvant === vuesApres) return null;

    const SEUILS = [10, 50, 100, 500];

    // Seuils déjà notifiés (tableau stocké dans le document)
    const dejaNotifies = Array.isArray(after.vues_milestones_notified)
      ? after.vues_milestones_notified
      : [];

    // Trouve le(s) seuil(s) fraîchement franchis
    const nouveauxSeuils = SEUILS.filter(
      (s) => vuesApres >= s && vuesAvant < s && !dejaNotifies.includes(s)
    );

    if (nouveauxSeuils.length === 0) return null;

    const titre = after.titre ?? "Votre annonce";
    // Champ canonique du propriétaire : `uid_prestataire`
    // (fallback `prestataireId` pour les anciens documents).
    const prestataireId = after.uid_prestataire ?? after.prestataireId ?? "";

    if (!prestataireId) {
      console.log("Pas de prestataireId sur le logement :", logementId);
      return null;
    }

    try {
      // Récupère le token FCM du prestataire
      const prestDoc = await admin.firestore()
        .collection("users")
        .doc(prestataireId)
        .get();

      if (!prestDoc.exists) {
        console.log("Prestataire introuvable :", prestataireId);
        return null;
      }

      const token = prestDoc.data()?.fcmToken;
      if (!token) {
        console.log("Pas de token FCM pour le prestataire :", prestataireId);
        return null;
      }

      // Envoie une notification par seuil franchi
      // (cas rare : deux seuils franchis en un seul update)
      for (const seuil of nouveauxSeuils) {
        const notifTitle = "🎉 Milestone atteint !";
        const notifBody =
          `Votre annonce « ${titre} » vient d'atteindre ${seuil} vue${seuil > 1 ? "s" : ""} !`;

        const messagePayload = {
          token,
          notification: {
            title: notifTitle,
            body: notifBody,
          },
          data: {
            type: "logement_update",
            logementId: logementId,
            vues: String(vuesApres),
            seuil: String(seuil),
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: "high",
            notification: {
              // Réutilise le canal annonces (priorité haute, son)
              channelId: "sgkhome_annonces",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: notifTitle,
                  body: notifBody,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        const response = await admin.messaging().send(messagePayload);
        console.log(
          `Milestone ${seuil} vues notifié au prestataire ${prestataireId} :`,
          response
        );
      }

      // Marque les seuils comme notifiés pour éviter les doublons
      const seuilsMisAJour = [...dejaNotifies, ...nouveauxSeuils];
      await admin.firestore()
        .collection("logements")
        .doc(logementId)
        .update({ vues_milestones_notified: seuilsMisAJour });

      return null;

    } catch (error) {
      console.error("Erreur sendVuesMilestoneNotification :", error);
      return null;
    }
  }
);

// ================================================================
// CLOUD FUNCTION 5 : initierPaiementPremium (HTTP)
// Initie un paiement GeniusPay pour le Pack Premium.
// Sécurité : ID token Firebase obligatoire → uid dérivé du token.
//
// Body : { telephone: "+237XXXXXXXXX", channel?: "orange"|"mtn" }
// Réponse : { success, reference, checkoutUrl, message }
//
// Variables d'environnement requises :
//   GENIUSPAY_API_KEY    → firebase functions:secrets:set GENIUSPAY_API_KEY
//   GENIUSPAY_SECRET_KEY → firebase functions:secrets:set GENIUSPAY_SECRET_KEY
// ================================================================
exports.initierPaiementPremium = onRequest(
  {
    cors: true,
    secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }

    try {
      // 1. Authentification via ID token Firebase
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { telephone, channel } = req.body || {};
      if (!telephone) {
        res.status(400).json({ success: false, error: "Numéro de téléphone requis" });
        return;
      }

      // 2. Vérifier que l'appelant est bien un prestataire
      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      if (!userSnap.exists || userSnap.data().role !== "prestataire") {
        res.status(403).json({ success: false, error: "Compte prestataire requis" });
        return;
      }

      // 3. Anti-doublon : empêche de lancer un 2e paiement si un est déjà en attente
      const pending = await admin.firestore()
        .collection("transactions")
        .where("uid", "==", uid)
        .where("type", "==", "premium")
        .where("statut", "==", "en_attente")
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();
      if (!pending.empty) {
        const existing = pending.docs[0].data();
        const ageMs = Date.now() - (existing.createdAt?.toMillis() || 0);
        if (ageMs < 5 * 60 * 1000) { // transaction < 5 min → réutiliser
          res.status(200).json({
            success: true,
            reference: existing.reference,
            checkoutUrl: existing.checkoutUrl || "",
            message: "Paiement déjà en cours. Finalisez le via Mobile Money.",
          });
          return;
        }
      }

      // 4. Création du paiement GeniusPay
      const internalRef = `premium_${uid}_${Date.now()}`;
      const u = userSnap.data();
      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: PREMIUM_MONTANT,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(channel),
        customerCountry: "CM",
        description: "Pack Premium Horem+ — 1 mois",
        customerEmail: u.email || "",
        customerPhone: telephone,
        metadata: { uid, type: "premium" },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      // ⚠️ La référence GeniusPay (MTX-…) sert de clé : c'est elle que le
      // webhook nous renverra. Le doc Firestore est indexé dessus.
      const reference = paiement.reference;

      // 5. Transaction en attente dans Firestore (doc id = référence GeniusPay)
      await admin.firestore().collection("transactions").doc(reference).set({
        uid,
        type: "premium",
        montant: PREMIUM_MONTANT,
        devise: DEVISE,
        statut: "en_attente",
        reference,
        internalRef,
        telephone,
        channel: channel || "orange",
        checkoutUrl: paiement.paymentUrl || "",
        geniuspayTransactionId: paiement.transactionId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({
        success: true,
        reference,
        checkoutUrl: paiement.paymentUrl || "",
        message: "Paiement initié. Confirmez la demande sur votre téléphone (Mobile Money).",
      });
    } catch (error) {
      console.error("initierPaiementPremium :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION 7 : initierSponsorisation (HTTP)
// Initie un paiement GeniusPay pour sponsoriser une annonce.
// Body : { logementId, duree: "1s"|"2s"|"1m", telephone, operateur? }
// ================================================================
exports.initierSponsorisation = onRequest(
  { cors: true, secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }

    try {
      // 1. Auth par ID token
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ")
        ? authHeader.substring(7)
        : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { logementId, telephone, operateur, duree } = req.body || {};
      if (!logementId || !telephone) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }

      // 2. Vérifier que le logement appartient au prestataire
      const logSnap = await admin.firestore().collection("logements").doc(logementId).get();
      if (!logSnap.exists) {
        res.status(404).json({ success: false, error: "Annonce introuvable" });
        return;
      }
      const log = logSnap.data();
      const owner = log.uid_prestataire || log.prestatireId;
      if (owner !== uid) {
        res.status(403).json({ success: false, error: "Cette annonce ne vous appartient pas" });
        return;
      }

      // Montant = tarif fixe selon durée choisie (1s=500, 2s=1000, 1m=2000)
      const codeduree = duree || "1m";
      const montant = SPONSOR_TARIFS[codeduree] || SPONSOR_TARIFS["1m"];

      // 3. Récupère les infos du prestataire (pour le customer GeniusPay)
      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      const u = userSnap.exists ? userSnap.data() : {};

      const internalRef = `sponsor_${logementId}_${Date.now()}`;

      // 4. Paiement GeniusPay
      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: montant,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Publication Horem+ — ${log.titre || "annonce"}`,
        customerEmail: u.email || "",
        customerPhone: telephone,
        metadata: { uid, type: "sponsorisation", logementId, duree: codeduree },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      // Référence GeniusPay (MTX-…) = clé Firestore pour le webhook.
      const reference = paiement.reference;

      // 5. Transaction en attente (doc id = référence GeniusPay)
      await admin
        .firestore()
        .collection("transactions")
        .doc(reference)
        .set({
          uid,
          type: "sponsorisation",
          logementId,
          duree: codeduree,
          montant,
          devise: DEVISE,
          statut: "en_attente",
          reference,
          internalRef,
          telephone,
          checkoutUrl: paiement.paymentUrl,
          geniuspayTransactionId: paiement.transactionId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      res.status(200).json({
        success: true,
        reference,
        montant,
        checkoutUrl: paiement.paymentUrl,
        message: "Paiement initié. Finalisez sur la page Mobile Money.",
      });
    } catch (error) {
      console.error("initierSponsorisation :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION : initierPublication (HTTP)
// Prestataire : paie la commission % pour rendre visible 1 mois.
// Body : { logementId, telephone, montant, operateur? }
// ================================================================
const PUBLICATION_DUREE_JOURS = 30;

exports.initierPublication = onRequest(
  {
    cors: true,
    secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      const decoded = await admin.auth().verifyIdToken(idToken);
      const uid = decoded.uid;

      const { logementId, telephone, operateur, montant, dureeJours } = req.body || {};
      if (!logementId || !telephone || !montant) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }
      // Durée personnalisée (hébergement forfaitaire) — bornée à [7, 400] jours.
      let dureeJoursFinal = Number(dureeJours);
      if (!Number.isFinite(dureeJoursFinal) || dureeJoursFinal <= 0) {
        dureeJoursFinal = PUBLICATION_DUREE_JOURS;
      }
      dureeJoursFinal = Math.min(400, Math.max(7, Math.round(dureeJoursFinal)));

      const logSnap = await admin.firestore().collection("logements").doc(logementId).get();
      if (!logSnap.exists) {
        res.status(404).json({ success: false, error: "Annonce introuvable" });
        return;
      }
      const log = logSnap.data();
      const owner = log.uid_prestataire || log.prestatireId;
      if (owner !== uid) {
        res.status(403).json({ success: false, error: "Cette annonce ne vous appartient pas" });
        return;
      }

      const montantFinal = Math.max(montant, MIN_PAIEMENT);

      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      const u = userSnap.exists ? userSnap.data() : {};

      const internalRef = `pub_${logementId}_${Date.now()}`;

      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: montantFinal,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Publication Horem+ — ${log.titre || "annonce"}`,
        customerEmail: u.email || "",
        customerPhone: telephone,
        metadata: { uid, type: "publication", logementId },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      const reference = paiement.reference;

      await admin
        .firestore()
        .collection("transactions")
        .doc(reference)
        .set({
          uid,
          type: "publication",
          logementId,
          montant: montantFinal,
          devise: DEVISE,
          statut: "en_attente",
          reference,
          internalRef,
          telephone,
          dureeJours: dureeJoursFinal,
          checkoutUrl: paiement.paymentUrl,
          geniuspayTransactionId: paiement.transactionId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      res.status(200).json({
        success: true,
        reference,
        montant: montantFinal,
        checkoutUrl: paiement.paymentUrl,
        message: "Paiement initié. Finalisez sur la page Mobile Money.",
      });
    } catch (error) {
      console.error("initierPublication :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION : initierUrgence (HTTP)
// Visiteur : paie une alerte prioritaire 48 H — notifié en premier
// quand un bien correspondant est publié. Montant fixe 200 XAF.
// Body : { logementId (= alerteId dans urgences), telephone, operateur? }
// ================================================================
exports.initierUrgence = onRequest(
  {
    cors: true,
    secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { logementId, telephone, operateur } = req.body || {};
      if (!logementId || !telephone) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }

      const alerteId = logementId;
      const montant = 200;

      // Charger l'alerte pour la description
      let alerteDesc = "alerte prioritaire";
      try {
        const alerteSnap = await admin.firestore().collection("urgences").doc(alerteId).get();
        if (alerteSnap.exists) {
          const a = alerteSnap.data();
          alerteDesc = `${a.typeBien || "Bien"} — ${a.description || ""}`.substring(0, 80);
        }
      } catch (_) { /* pas bloquant */ }

      let email = "";
      try {
        const uDoc = await admin.firestore().collection("users").doc(uid).get();
        if (uDoc.exists) email = uDoc.data().email || "";
      } catch (_) { /* visiteur sans profil */ }

      const internalRef = `urgence_${uid}_${alerteId}_${Date.now()}`;

      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: montant,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Alerte prioritaire 48H — ${alerteDesc}`,
        customerEmail: email,
        customerPhone: telephone,
        metadata: { uid, type: "urgence", logementId: alerteId },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      const reference = paiement.reference;

      await admin.firestore().collection("transactions").doc(reference).set({
        uid,
        type: "urgence",
        logementId: alerteId,
        montant,
        devise: DEVISE,
        statut: "en_attente",
        reference,
        internalRef,
        telephone,
        checkoutUrl: paiement.paymentUrl || "",
        geniuspayTransactionId: paiement.transactionId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({
        success: true,
        reference,
        montant,
        checkoutUrl: paiement.paymentUrl || "",
        message: "Paiement initié. Finalisez sur la page Mobile Money.",
      });
    } catch (error) {
      console.error("initierUrgence :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION 8 : desactiverSponsorisationsExpirees (scheduler)
// Toutes les heures : désactive les sponsorisations dont la date
// d'expiration est dépassée.
// ================================================================
exports.desactiverSponsorisationsExpirees = onSchedule("every 1 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await admin.firestore()
    .collection("logements")
    .where("isSponsored", "==", true)
    .where("sponsoredUntil", "<", now)
    .get();

  if (snap.empty) {
    console.log("Sponsorisations : aucune expiration à traiter");
    return null;
  }

  const batch = admin.firestore().batch();
  snap.docs.forEach((doc) => {
    batch.update(doc.ref, { isSponsored: false, sponsoredUntil: null });
  });
  await batch.commit();
  console.log(`Sponsorisations désactivées : ${snap.size}`);
  return null;
});

// ================================================================
// CLOUD FUNCTION 6 : geniuspayWebhook (HTTP)
// Reçoit les notifications GeniusPay (callback_url).
// ① Vérifie la signature HMAC-SHA256 (en-tête X-GeniusPay-Signature).
// ② Re-vérifie le statut via l'API GeniusPay (source de vérité).
// ③ Applique l'effet métier. Idempotent.
//
// À configurer dans le portail GeniusPay :
//   Webhook URL : https://us-central1-sgk-home.cloudfunctions.net/geniuspayWebhook
// ================================================================
exports.geniuspayWebhook = onRequest(
  { cors: false, secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET", "GMAIL_SENDER_EMAIL", "GMAIL_APP_PASSWORD"] },
  async (req, res) => {
    try {
      // 1. Vérification signature HMAC
      const rawBody = JSON.stringify(req.body || {});
      const sig = req.headers["x-geniuspay-signature"] || "";
      if (!geniuspay.verifyWebhookSignature(rawBody, sig)) {
        console.warn("geniuspayWebhook : signature invalide");
        res.status(401).send("Signature invalide");
        return;
      }

      const body = req.body || {};
      // GeniusPay encapsule les détails dans body.data (référence MTX-…).
      const d = body.data || body;
      const reference =
        d.reference || d.transaction_reference || d.id ||
        body.reference || body.transaction_id;

      console.log("geniuspayWebhook reçu:", JSON.stringify(body).slice(0, 500));

      if (!reference) {
        res.status(200).send("OK (référence manquante)");
        return;
      }

      const db = admin.firestore();
      const txRef = db.collection("transactions").doc(String(reference));
      const txSnap = await txRef.get();
      if (!txSnap.exists) {
        console.warn("geniuspayWebhook : transaction inconnue", reference);
        res.status(200).send("OK (transaction inconnue)");
        return;
      }
      const tx = txSnap.data();

      // Idempotence
      if (tx.statut === "reussi" || tx.statut === "echoue") {
        res.status(200).send("OK (déjà traité)");
        return;
      }

      // 2. Statut : on combine le payload SIGNÉ (déjà vérifié HMAC) et une
      //    re-vérification API. Le payload signé est fiable ; on le privilégie
      //    si l'API de lecture ne confirme pas (endpoints parfois capricieux).
      const event = String(body.event || body.type || "").toLowerCase();
      const payloadStatus = String(
        d.status || d.state || d.payment_status || ""
      ).toLowerCase();

      let derive = "";
      if (event.includes("success") || payloadStatus === "success" ||
          payloadStatus === "completed" || payloadStatus === "paid") {
        derive = "COMPLETED";
      } else if (event.includes("fail") || event.includes("cancel") ||
          ["failed", "cancelled", "expired", "declined"].includes(payloadStatus)) {
        derive = "FAILED";
      }

      // Confirmation API (si un endpoint répond)
      const check = await geniuspay.checkPayment(String(reference));
      const apiStatus = check.status.toUpperCase();

      // Statut final : l'API si elle conclut, sinon le payload signé.
      const SUCCES0 = ["COMPLETED", "SUCCESS", "SUCCESSFUL", "PAID", "ACCEPTED"];
      const ECHEC0 = ["FAILED", "CANCELLED", "EXPIRED", "REFUSED", "DECLINED"];
      let status = apiStatus;
      if (!SUCCES0.includes(apiStatus) && !ECHEC0.includes(apiStatus)) {
        status = derive || apiStatus; // API non concluante → payload signé
      }

      // Statuts succès : completed/success/... · échec : failed/cancelled/...
      const SUCCES = ["COMPLETED", "SUCCESS", "SUCCESSFUL", "PAID", "ACCEPTED"];
      const ECHEC = ["FAILED", "CANCELLED", "EXPIRED", "REFUSED", "DECLINED"];

      if (SUCCES.includes(status)) {
        await txRef.update({
          statut: "reussi",
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          dernierStatutBrut: status,
        });
        await appliquerTransactionReussie(tx);
      } else if (ECHEC.includes(status)) {
        await txRef.update({
          statut: "echoue",
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          dernierStatutBrut: status,
        });
        // Flow iOS : signaler l'échec à la page web
        if (tx.paymentToken) {
          try {
            await db.collection("paiements_web").doc(String(tx.paymentToken)).set(
              {
                statut: "echoue",
                confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          } catch (_) {}
        }
        await notifierPrestataire(
          tx.uid,
          "Paiement échoué",
          "Votre paiement Wave n'a pas abouti. Vérifiez votre solde et réessayez.",
          { type: "transaction", reference: tx.reference }
        );
      } else {
        // PENDING / inconnu → conserve "en_attente"
        await txRef.update({ dernierStatutBrut: status });
      }

      res.status(200).send("OK");
    } catch (error) {
      console.error("geniuspayWebhook :", error);
      res.status(500).send("Erreur");
    }
  }
);

// ================================================================
// CLOUD FUNCTION : verifierPaiement (HTTP)
// Vérification ACTIVE du statut auprès de GeniusPay (pull), pour ne
// pas dépendre du webhook. Appelée par l'app pendant l'attente.
// Body : { reference: "MTX-…" | "SANDBOX_…" }
// Réponse : { statut: "en_attente" | "reussi" | "echoue" }
// ================================================================
exports.verifierPaiement = onRequest(
  { cors: true, secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      // 1. Auth par ID token
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { reference } = req.body || {};
      if (!reference) {
        res.status(400).json({ success: false, error: "Référence requise" });
        return;
      }

      const db = admin.firestore();
      const txRef = db.collection("transactions").doc(String(reference));
      const txSnap = await txRef.get();
      if (!txSnap.exists) {
        res.status(404).json({ success: false, error: "Transaction introuvable" });
        return;
      }
      const tx = txSnap.data();
      if (tx.uid !== uid) {
        res.status(403).json({ success: false, error: "Accès refusé" });
        return;
      }

      // Déjà finalisée → renvoie l'état connu (idempotent)
      if (tx.statut === "reussi" || tx.statut === "echoue") {
        res.status(200).json({ success: true, statut: tx.statut });
        return;
      }

      // 2. Vérification auprès de GeniusPay (source de vérité)
      const check = await geniuspay.checkPayment(String(reference));
      const status = (check.status || "").toUpperCase();
      const SUCCES = ["COMPLETED", "SUCCESS", "SUCCESSFUL", "PAID", "ACCEPTED"];
      const ECHEC = ["FAILED", "CANCELLED", "EXPIRED", "REFUSED", "DECLINED"];

      if (SUCCES.includes(status)) {
        await txRef.update({
          statut: "reussi",
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          dernierStatutBrut: status,
        });
        await appliquerTransactionReussie(tx);
        res.status(200).json({ success: true, statut: "reussi" });
        return;
      }
      if (ECHEC.includes(status)) {
        await txRef.update({
          statut: "echoue",
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
          dernierStatutBrut: status,
        });
        res.status(200).json({ success: true, statut: "echoue" });
        return;
      }

      // Toujours en attente
      await txRef.update({ dernierStatutBrut: status || "PENDING" });
      res.status(200).json({ success: true, statut: "en_attente" });
    } catch (error) {
      console.error("verifierPaiement :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de la vérification.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION : initierVisibilite (HTTP)
// Prestataire : paie la visibilité annuelle pour Entreprise / Restaurant / École.
// Montant fixe selon le type : Entreprise 3000 XAF · Restaurant 2000 XAF · École 1000 XAF.
// Body : { logementId, telephone, operateur? }
// ================================================================
exports.initierVisibilite = onRequest(
  { cors: true, secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }

    try {
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { logementId, telephone, operateur } = req.body || {};
      if (!logementId || !telephone) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }

      const logSnap = await admin.firestore().collection("logements").doc(logementId).get();
      if (!logSnap.exists) {
        res.status(404).json({ success: false, error: "Annonce introuvable" });
        return;
      }
      const log = logSnap.data();
      const owner = log.uid_prestataire || log.prestatireId;
      if (owner !== uid) {
        res.status(403).json({ success: false, error: "Cette annonce ne vous appartient pas" });
        return;
      }

      const typeBienKey = (log.typeBien || "").toLowerCase();
      const montant = VISIBILITE_TARIFS[typeBienKey] || 2000;

      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      const u = userSnap.exists ? userSnap.data() : {};

      const internalRef = `visib_${logementId}_${Date.now()}`;

      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: montant,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Visibilité 1 an — ${log.titre || log.typeBien || "fiche"}`,
        customerEmail: u.email || "",
        customerPhone: telephone,
        metadata: { uid, type: "visibilite", logementId },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      const reference = paiement.reference;

      await admin.firestore().collection("transactions").doc(reference).set({
        uid,
        type: "visibilite",
        logementId,
        montant,
        devise: DEVISE,
        statut: "en_attente",
        reference,
        internalRef,
        telephone,
        checkoutUrl: paiement.paymentUrl,
        geniuspayTransactionId: paiement.transactionId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({
        success: true,
        reference,
        montant,
        checkoutUrl: paiement.paymentUrl,
        message: "Paiement initié. Finalisez sur la page Mobile Money.",
      });
    } catch (error) {
      console.error("initierVisibilite :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ════════════════════════════════════════════════════════════════════════════
// EMAIL ADMIN — notification nouvelle publication
// Secrets requis : GMAIL_SENDER_EMAIL, GMAIL_APP_PASSWORD
// ════════════════════════════════════════════════════════════════════════════
async function sendAdminEmail({ logement, prestataire, logementId }) {
  const senderEmail = process.env.GMAIL_SENDER_EMAIL;
  const appPassword = process.env.GMAIL_APP_PASSWORD;
  if (!senderEmail || !appPassword) {
    console.warn("sendAdminEmail : secrets GMAIL_SENDER_EMAIL / GMAIL_APP_PASSWORD non configurés.");
    return;
  }

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: senderEmail, pass: appPassword },
  });

  const mapsLink = logement.latitude && logement.longitude
    ? `https://www.google.com/maps?q=${logement.latitude},${logement.longitude}`
    : "Non renseigné";

  const html = `
    <h2>🏠 Nouvelle publication sur Horem+</h2>
    <table style="border-collapse:collapse;width:100%;font-family:sans-serif;">
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Annonce</td>
          <td style="padding:8px;border:1px solid #ddd;">${logement.titre || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Type</td>
          <td style="padding:8px;border:1px solid #ddd;">${logement.typeBien || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Ville / Quartier</td>
          <td style="padding:8px;border:1px solid #ddd;">${logement.ville || "–"} · ${logement.quartier || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Prix</td>
          <td style="padding:8px;border:1px solid #ddd;">${logement.prix ? `${logement.prix.toLocaleString()} XAF` : "Gratuit"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Coordonnées GPS</td>
          <td style="padding:8px;border:1px solid #ddd;"><a href="${mapsLink}">${logement.latitude || "–"}, ${logement.longitude || "–"}</a></td></tr>
      <tr><td colspan="2" style="padding:8px;border:1px solid #ddd;background:#e8f4fd;"><strong>Prestataire</strong></td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Nom</td>
          <td style="padding:8px;border:1px solid #ddd;">${prestataire?.nom || logement.prestatireNom || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">Téléphone</td>
          <td style="padding:8px;border:1px solid #ddd;">${prestataire?.telephone || logement.prestatirePhone || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">UID</td>
          <td style="padding:8px;border:1px solid #ddd;">${logement.uid_prestataire || "–"}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f5f5f5;font-weight:bold;">ID Annonce</td>
          <td style="padding:8px;border:1px solid #ddd;">${logementId}</td></tr>
    </table>
    <p style="margin-top:16px;color:#666;font-size:12px;">
      Horem+ — Notification automatique. Ne pas répondre à ce mail.
    </p>
  `;

  try {
    await transporter.sendMail({
      from: `"Horem+" <${senderEmail}>`,
      to: ADMIN_EMAIL,
      subject: `[Horem+] Nouvelle annonce : ${logement.titre || logement.typeBien || "sans titre"}`,
      html,
    });
    console.log("Email admin envoyé à", ADMIN_EMAIL);
  } catch (e) {
    console.error("sendAdminEmail erreur:", e.message);
  }
}

// Sauvegarde une notification dans Firestore (visible dans le dashboard admin).
async function saveAdminNotification({ logement, logementId, type }) {
  await admin.firestore().collection("admin_notifications").add({
    type: type || "nouvelle_publication",
    logementId,
    titre: logement.titre || logement.typeBien || "",
    typeBien: logement.typeBien || "",
    ville: logement.ville || "",
    quartier: logement.quartier || "",
    latitude: logement.latitude || null,
    longitude: logement.longitude || null,
    prestatireNom: logement.prestatireNom || "",
    prestatirePhone: logement.prestatirePhone || "",
    uid_prestataire: logement.uid_prestataire || "",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lu: false,
  });
}

// Applique l'effet métier d'une transaction réussie.
async function appliquerTransactionReussie(tx) {
  const db = admin.firestore();

  if (tx.type === "premium") {
    const expiry = new Date(Date.now() + PREMIUM_DUREE_JOURS * 24 * 60 * 60 * 1000);
    await db.collection("users").doc(tx.uid).set(
      {
        isPremium: true,
        premiumExpiry: admin.firestore.Timestamp.fromDate(expiry),
      },
      { merge: true }
    );
    await notifierPrestataire(
      tx.uid,
      "🎉 Bienvenue dans le Pack Premium !",
      "Vos avantages Premium sont activés.",
      { type: "transaction", reference: tx.reference }
    );
  } else if (tx.type === "publication") {
    // Publication immobilier : durée variable (30 j par défaut, jusqu'à 365 j
    // pour les forfaits hébergement Meublé/Motel/Auberge/Hôtel).
    const dureeJ = Number(tx.dureeJours) > 0
        ? Number(tx.dureeJours)
        : PUBLICATION_DUREE_JOURS;
    const until = new Date(Date.now() + dureeJ * 24 * 60 * 60 * 1000);
    const untilTs = admin.firestore.Timestamp.fromDate(until);

    let logData = {};
    try {
      const logSnap = await db.collection("logements").doc(tx.logementId).get();
      if (logSnap.exists) logData = logSnap.data();
    } catch (_) {}

    await db.collection("logements").doc(tx.logementId).set(
      {
        disponible: true,
        paymentPending: admin.firestore.FieldValue.delete(),
        publicationExpiry: untilTs,
      },
      { merge: true }
    );

    // Email + notification admin pour nouvelle publication
    await sendAdminEmail({ logement: logData, logementId: tx.logementId });
    await saveAdminNotification({ logement: logData, logementId: tx.logementId, type: "nouvelle_publication" });

    const titre = logData.titre || "votre annonce";
    const dateFr = until.toLocaleDateString("fr-FR");
    const dureeLbl =
      dureeJ >= 360 ? "1 an" :
      dureeJ >= 175 ? "6 mois" :
      dureeJ >= 85  ? "3 mois" :
      "1 mois";
    await notifierPrestataire(
      tx.uid,
      "✅ Annonce publiée !",
      `Votre annonce « ${titre} » est visible pendant ${dureeLbl} (jusqu'au ${dateFr}).`,
      { type: "logement_update", logementId: tx.logementId, reference: tx.reference }
    );

    // ── Notification prioritaire : alertes urgences matching ──
    try {
      await notifierAlertesUrgence(db, logData, tx.logementId);
    } catch (e) {
      console.warn("notifierAlertesUrgence:", e.message);
    }
  } else if (tx.type === "sponsorisation") {
    // Sponsorisation = boost optionnel (annonce déjà publiée)
    const jours = SPONSOR_DUREES[tx.duree] || SPONSOR_DUREE_JOURS;
    const until = new Date(Date.now() + jours * 24 * 60 * 60 * 1000);
    const untilTs = admin.firestore.Timestamp.fromDate(until);

    let logData = {};
    try {
      const logSnap = await db.collection("logements").doc(tx.logementId).get();
      if (logSnap.exists) logData = logSnap.data();
    } catch (_) {}

    await db.collection("logements").doc(tx.logementId).set(
      {
        isSponsored: true,
        sponsoredUntil: untilTs,
        sponsoredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const titre = logData.titre || "votre annonce";
    const dateFr = until.toLocaleDateString("fr-FR");
    const labelDuree = { "1s": "1 semaine", "2s": "2 semaines", "1m": "1 mois" }[tx.duree] || `${jours} jours`;
    await notifierPrestataire(
      tx.uid,
      "🚀 Annonce mise en avant !",
      `Votre annonce « ${titre} » est mise en avant pendant ${labelDuree} (jusqu'au ${dateFr}).`,
      { type: "logement_update", logementId: tx.logementId, reference: tx.reference }
    );
  } else if (tx.type === "publicite") {
    // Diffusion publicitaire 4 jours : active la pub et fixe l'échéance.
    const until = new Date(Date.now() + PUBLICITE_DUREE_JOURS * 24 * 60 * 60 * 1000);
    const untilTs = admin.firestore.Timestamp.fromDate(until);

    await db.collection("publicites").doc(tx.publiciteId).set(
      {
        actif: true,
        paymentPending: false,
        expiresAt: untilTs,
        transactionRef: tx.reference,
        dernierPaiementAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const dateFr = until.toLocaleDateString("fr-FR");
    await notifierPrestataire(
      tx.uid,
      "📣 Publicité en ligne !",
      `Votre publicité est diffusée jusqu'au ${dateFr}.`,
      { type: "publicite", publiciteId: tx.publiciteId, reference: tx.reference }
    );
  } else if (tx.type === "visibilite") {
    // Visibilité annuelle : active l'annonce et pose la date d'expiration.
    const until = new Date(Date.now() + VISIBILITE_DUREE_JOURS * 24 * 60 * 60 * 1000);
    const untilTs = admin.firestore.Timestamp.fromDate(until);

    let logData = {};
    try {
      const logDoc = await admin.firestore().collection("logements").doc(tx.logementId).get();
      if (logDoc.exists) logData = logDoc.data();
    } catch (_) {}

    await admin.firestore().collection("logements").doc(tx.logementId).set(
      {
        visibiliteExpiry: untilTs,
        disponible: true,
        paymentPending: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    // Email + notification admin
    await sendAdminEmail({ logement: logData, logementId: tx.logementId });
    await saveAdminNotification({ logement: logData, logementId: tx.logementId, type: "nouvelle_publication" });

    const titre = logData.titre || "votre fiche";
    const dateFr = until.toLocaleDateString("fr-FR");
    await notifierPrestataire(
      tx.uid,
      "✅ Fiche activée !",
      `Votre fiche « ${titre} » est visible jusqu'au ${dateFr}.`,
      { type: "logement_update", logementId: tx.logementId, reference: tx.reference }
    );
  } else if (tx.type === "urgence") {
    // Alerte prioritaire visiteur : notifié en premier quand un bien
    // correspondant est publié. 200 XAF / 48 H.
    const until = new Date(Date.now() + URGENCE_DUREE_HEURES * 60 * 60 * 1000);
    const untilTs = admin.firestore.Timestamp.fromDate(until);

    // Active l'alerte dans la collection urgences.
    const alerteId = tx.logementId; // réutilise le champ pour l'id de l'alerte
    await db.collection("urgences").doc(alerteId).update({
      actif: true,
      paymentPending: false,
      expiresAt: untilTs,
      reference: tx.reference,
    });

    // Notifie le visiteur que son alerte est activée.
    await notifierPrestataire(
      tx.uid,
      "✅ Alerte prioritaire activée (48 H)",
      "Vous serez notifié en premier dès qu'un bien correspondant sera publié.",
      { type: "urgence", alerteId, reference: tx.reference }
    );
  }

  // ── Flow iOS : marquer paiements_web/<token> comme réussi pour que la page
  // web /pay/[token] affiche la confirmation à l'utilisateur.
  if (tx.paymentToken) {
    try {
      await db.collection("paiements_web").doc(String(tx.paymentToken)).set(
        {
          statut: "reussi",
          reference: tx.reference,
          confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (e) {
      console.warn("MAJ paiements_web échouée:", e.message);
    }
  }
}

// Notification push à un prestataire (silencieuse si pas de token).
async function notifierPrestataire(uid, titre, corps, data) {
  try {
    const doc = await admin.firestore().collection("users").doc(uid).get();
    const token = doc.exists ? doc.data().fcmToken : null;
    if (!token) return;

    const dataStr = {};
    for (const [k, v] of Object.entries(data || {})) dataStr[k] = String(v);
    dataStr.click_action = "FLUTTER_NOTIFICATION_CLICK";

    await admin.messaging().send({
      token,
      notification: { title: titre, body: corps },
      data: dataStr,
      android: {
        priority: "high",
        notification: {
          channelId: "sgkhome_annonces",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          sound: "default",
        },
      },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });
  } catch (e) {
    console.error("notifierPrestataire :", e);
  }
}

// ================================================================
// CLOUD FUNCTION 9 : envoyerNotifGlobale (HTTP, admin uniquement)
// Diffuse une notification push à tous les utilisateurs ayant un token FCM.
// Body : { titre, corps }
// Auth : ID token Firebase d'un utilisateur dont role == 'admin'.
// ================================================================
exports.envoyerNotifGlobale = onRequest({ cors: true }, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ success: false, error: "Méthode non autorisée" });
    return;
  }

  try {
    // 1. Authentification + contrôle du rôle admin
    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ")
      ? authHeader.substring(7)
      : null;
    if (!idToken) {
      res.status(401).json({ success: false, error: "Authentification requise" });
      return;
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (_) {
      res.status(401).json({ success: false, error: "Session invalide" });
      return;
    }
    const callerSnap = await admin.firestore().collection("users").doc(decoded.uid).get();
    if (!callerSnap.exists || callerSnap.data().role !== "admin") {
      res.status(403).json({ success: false, error: "Accès réservé aux administrateurs" });
      return;
    }

    const { titre, corps } = req.body || {};
    if (!titre || !corps) {
      res.status(400).json({ success: false, error: "Titre et corps requis" });
      return;
    }

    // 2. Collecte de tous les tokens FCM
    const usersSnap = await admin.firestore().collection("users").get();
    const tokens = usersSnap.docs
      .map((d) => d.data().fcmToken)
      .filter((t) => !!t && typeof t === "string");

    if (tokens.length === 0) {
      res.status(200).json({ success: true, sent: 0, message: "Aucun token FCM" });
      return;
    }

    // 3. Envoi multicast par lots de 500
    let sent = 0;
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const result = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: { title: titre, body: corps },
        data: { type: "annonce_globale", click_action: "FLUTTER_NOTIFICATION_CLICK" },
        android: {
          priority: "high",
          notification: { channelId: "sgkhome_annonces", sound: "default" },
        },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
      });
      sent += result.successCount;
    }

    res.status(200).json({ success: true, sent });
  } catch (error) {
    console.error("envoyerNotifGlobale :", error);
    res.status(500).json({ success: false, error: "Erreur lors de l'envoi." });
  }
});

// ================================================================
// CLOUD FUNCTION : initierPaiementPublicite (HTTP)
// Prestataire : paie 500 XAF pour 4 jours de diffusion publicitaire.
// Body : { publiciteId, telephone, operateur }
// La publicité doit déjà exister en brouillon (paymentPending: true).
// ================================================================
exports.initierPaiementPublicite = onRequest(
  {
    cors: true,
    secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { publiciteId, telephone, operateur } = req.body || {};
      if (!publiciteId || !telephone) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }

      // Vérifier que la pub appartient au prestataire connecté.
      const pubSnap = await admin.firestore().collection("publicites").doc(publiciteId).get();
      if (!pubSnap.exists) {
        res.status(404).json({ success: false, error: "Publicité introuvable" });
        return;
      }
      if (pubSnap.data().prestataireId !== uid) {
        res.status(403).json({ success: false, error: "Cette publicité ne vous appartient pas" });
        return;
      }

      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      const u = userSnap.exists ? userSnap.data() : {};

      const internalRef = `publicite_${publiciteId}_${Date.now()}`;
      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: PUBLICITE_MONTANT,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Publicité ${PUBLICITE_DUREE_JOURS} jours — ${pubSnap.data().titre || "Horem+"}`,
        customerEmail: u.email || "",
        customerPhone: telephone,
        metadata: { uid, type: "publicite", publiciteId },
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      const reference = paiement.reference;
      await admin.firestore().collection("transactions").doc(reference).set({
        uid,
        type: "publicite",
        publiciteId,
        montant: PUBLICITE_MONTANT,
        devise: DEVISE,
        statut: "en_attente",
        reference,
        internalRef,
        telephone,
        checkoutUrl: paiement.paymentUrl || "",
        geniuspayTransactionId: paiement.transactionId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Marquer la pub comme « paiement en cours » (paymentPending reste true).
      await admin.firestore().collection("publicites").doc(publiciteId).set(
        { paymentPending: true },
        { merge: true }
      );

      res.status(200).json({
        success: true,
        reference,
        montant: PUBLICITE_MONTANT,
        checkoutUrl: paiement.paymentUrl || "",
        message: "Paiement initié. Finalisez sur la page Mobile Money.",
      });
    } catch (error) {
      console.error("initierPaiementPublicite :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);

// ================================================================
// CLOUD FUNCTION : desactiverPublicitesExpirees (scheduler)
// Toutes les heures : désactive les pubs dont expiresAt est dépassé.
// La pub reste en base, le prestataire peut la réactiver en repayant.
// ================================================================
exports.desactiverPublicitesExpirees = onSchedule("every 1 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await admin.firestore()
    .collection("publicites")
    .where("actif", "==", true)
    .where("expiresAt", "<", now)
    .get();

  if (snap.empty) {
    console.log("Publicités : aucune expiration à traiter");
    return null;
  }

  const batch = admin.firestore().batch();
  snap.docs.forEach((doc) => {
    batch.update(doc.ref, { actif: false });
  });
  await batch.commit();
  console.log(`Publicités désactivées : ${snap.size}`);
  return null;
});

// ================================================================
// FONCTION UTILITAIRE : notifierAlertesUrgence
// Quand un nouveau logement est publié, cherche les alertes actives
// dont typeBien correspond et prixMin <= prix <= prixMax.
// Notifie immédiatement les visiteurs avec alerte matching.
// ================================================================
async function notifierAlertesUrgence(db, logData, logementId) {
  const typeBien = logData.typeBien || "";
  const prix = logData.prix || 0;
  const titre = logData.titre || "Nouveau bien";
  const ville = logData.ville || "";

  if (!typeBien) return;

  const now = admin.firestore.Timestamp.now();

  // Cherche les alertes actives pour ce type de bien.
  const snap = await db
    .collection("urgences")
    .where("actif", "==", true)
    .where("typeBien", "==", typeBien)
    .where("expiresAt", ">", now)
    .get();

  if (snap.empty) return;

  const promises = [];
  for (const doc of snap.docs) {
    const alerte = doc.data();
    const pMin = alerte.prixMin || 0;
    const pMax = alerte.prixMax || 0;

    // Vérifie la fourchette de prix (si pMax = 0, pas de limite haute).
    if (prix < pMin) continue;
    if (pMax > 0 && prix > pMax) continue;

    // Matching trouvé → notification immédiate au visiteur.
    promises.push(
      notifierPrestataire(
        alerte.uid,
        `🔴 ${titre} — ${ville}`,
        `Un ${typeBien} à ${prix} XAF correspond à votre alerte ! Consultez-le en priorité.`,
        { type: "alerte_urgence", logementId, alerteId: doc.id }
      )
    );
  }

  if (promises.length > 0) {
    await Promise.all(promises);
    console.log(`Alertes urgence notifiées : ${promises.length} pour logement ${logementId}`);
  }
}

// ================================================================
// FONCTION ADMIN : creerCompteGratuit
// Crée (ou met à jour) un compte prestataire avec accès 100% gratuit.
// Seul un utilisateur avec role == 'admin' peut appeler cette fonction.
// ================================================================
exports.creerCompteGratuit = onRequest({ cors: true }, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.status(204).send("");
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ success: false, error: "Méthode non autorisée" });
    return;
  }

  // Vérification du token Firebase Auth
  const authHeader = req.headers.authorization || "";
  const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
  if (!idToken) {
    res.status(401).json({ success: false, error: "Authentification requise" });
    return;
  }
  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch (_) {
    res.status(401).json({ success: false, error: "Session invalide" });
    return;
  }

  // Vérification du rôle admin
  const callerDoc = await admin.firestore()
    .collection("users").doc(decoded.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "admin") {
    res.status(403).json({ success: false, error: "Accès réservé aux administrateurs" });
    return;
  }

  const { telephone, nom, prenom } = req.body || {};
  if (!telephone || !nom || !prenom) {
    res.status(400).json({ success: false, error: "Paramètres manquants (telephone, nom, prenom)" });
    return;
  }

  // Normalisation du numéro de téléphone
  const phone = telephone.startsWith("+") ? telephone : `+237${telephone}`;

  try {
    let uid;
    try {
      // Recherche d'un compte existant avec ce numéro
      const existing = await admin.auth().getUserByPhoneNumber(phone);
      uid = existing.uid;
    } catch (_) {
      // Aucun compte → création
      const newUser = await admin.auth().createUser({
        phoneNumber: phone,
        displayName: `${prenom} ${nom}`.trim(),
      });
      uid = newUser.uid;
    }

    // Création / mise à jour du document Firestore
    await admin.firestore().collection("users").doc(uid).set(
      {
        uid,
        telephone: phone,
        nom: nom.trim(),
        prenom: prenom.trim(),
        role: "prestataire",
        compteGratuit: true,
        isVerifie: true,
        phoneVerified: true,
        isPremium: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log(`creerCompteGratuit: uid=${uid} phone=${phone} créé par admin=${decoded.uid}`);
    res.json({ success: true, uid, telephone: phone });
  } catch (e) {
    console.error("creerCompteGratuit error:", e);
    res.status(500).json({ success: false, error: e.message });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// FLOW iOS : activation par email + page web de paiement
// ────────────────────────────────────────────────────────────────────────────
// Objectif : conformité App Store 3.1.1 — aucun paiement dans l'app iOS.
//
// Étape 1 : l'app iOS appelle envoyerLienPaiementEmail avec { type, targetId,
//           params, email }. On crée un doc paiements_web/<token> et on envoie
//           un email HTML avec un lien vers la page web dashboard admin.
// Étape 2 : l'utilisateur ouvre l'email, clique le lien, arrive sur la page
//           web /pay/[token]. Il saisit opérateur + numéro et paie via
//           GeniusPay comme dans le flow Flutter Android.
// Étape 3 : le webhook GeniusPay existant marque la transaction "reussi",
//           appliquerTransactionReussie() active le service et met à jour
//           paiements_web/<token> pour que la page web affiche la confirmation.
//
// Le flow Android reste inchangé : il continue à utiliser les CF
// initierSponsorisation, initierPublication, initierPublicite, etc.
// ════════════════════════════════════════════════════════════════════════════

// URL publique du dashboard admin qui héberge /pay/[token].
// Remplacer par l'URL de production Railway une fois déployée.
const WEB_PAY_BASE_URL = process.env.WEB_PAY_BASE_URL
  || "https://immoconnect-admin.up.railway.app/pay";

// Durée de validité d'un lien de paiement (24 h).
const PAIEMENT_WEB_TOKEN_TTL_H = 24;

// Types acceptés par la CF envoyerLienPaiementEmail.
const TYPES_ACTIVATION = [
  "premium",
  "publication",
  "sponsorisation",
  "publicite",
  "urgence",
  "visibilite",
];

// Génère un token aléatoire (32 caractères hexa) pour le lien de paiement.
function genererTokenPaiement() {
  const bytes = require("crypto").randomBytes(16);
  return bytes.toString("hex");
}

// Calcule le montant et le libellé lisible pour un service à activer.
// Utilisé par le mail et par initierPaiementDepuisWeb.
function calculerMontantEtLibelle(type, params = {}) {
  const p = params || {};
  switch (type) {
    case "premium":
      return {
        montant: PREMIUM_MONTANT,
        libelle: "Pack Premium (30 jours)",
        description: "Accès aux avantages Premium pendant 30 jours",
      };
    case "sponsorisation": {
      const duree = p.duree || "1m";
      const montant = SPONSOR_TARIFS[duree] || SPONSOR_TARIFS["1m"];
      const label = { "1s": "1 semaine", "2s": "2 semaines", "1m": "1 mois" }[duree] || "1 mois";
      return {
        montant,
        libelle: `Mise en avant (${label})`,
        description: p.titre ? `Mise en avant de « ${p.titre} » pendant ${label}` : `Mise en avant pendant ${label}`,
        duree,
      };
    }
    case "publication": {
      const montant = Number(p.montant) > 0 ? Number(p.montant) : 500;
      const dureeJours = Number(p.dureeJours) > 0 ? Number(p.dureeJours) : PUBLICATION_DUREE_JOURS;
      return {
        montant: planche(montant),
        libelle: "Publication d'annonce",
        description: p.titre ? `Publication de « ${p.titre} » pendant ${dureeJours} jours` : `Publication d'annonce pendant ${dureeJours} jours`,
        dureeJours,
      };
    }
    case "publicite":
      return {
        montant: PUBLICITE_MONTANT,
        libelle: `Diffusion publicitaire (${PUBLICITE_DUREE_JOURS} jours)`,
        description: p.titre ? `Diffusion de « ${p.titre} » pendant ${PUBLICITE_DUREE_JOURS} jours` : `Diffusion publicitaire pendant ${PUBLICITE_DUREE_JOURS} jours`,
      };
    case "urgence":
      return {
        montant: MIN_PAIEMENT,
        libelle: `Alerte prioritaire (${URGENCE_DUREE_HEURES}h)`,
        description: `Alerte prioritaire pendant ${URGENCE_DUREE_HEURES} heures`,
      };
    case "visibilite": {
      const key = String(p.typeBien || "entreprise").toLowerCase();
      const montant = VISIBILITE_TARIFS[key] || 2000;
      return {
        montant,
        libelle: `Visibilité annuelle (${p.typeBien || "service"})`,
        description: p.titre ? `Visibilité annuelle pour « ${p.titre} »` : "Visibilité annuelle",
      };
    }
    default:
      throw new Error(`Type d'activation inconnu : ${type}`);
  }
}

// Template email HTML sobre pour le lien de paiement.
function buildPaymentLinkEmailHtml({ token, service, prenom }) {
  const url = `${WEB_PAY_BASE_URL}/${token}`;
  const bonjour = prenom ? `Bonjour ${prenom},` : "Bonjour,";
  return `
  <!DOCTYPE html>
  <html lang="fr">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Horem+ — Activation de votre service</title>
  </head>
  <body style="margin:0;padding:0;background:#f4f4f2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a18;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f2;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.04);">
            <tr>
              <td style="background:#1e3a8a;padding:32px 32px 24px;text-align:center;">
                <div style="color:#ffffff;font-size:24px;font-weight:700;letter-spacing:-0.5px;">Horem+</div>
                <div style="color:#c7d2fe;font-size:13px;margin-top:4px;">Activation de votre service</div>
              </td>
            </tr>
            <tr>
              <td style="padding:32px;">
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;">${bonjour}</p>
                <p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#4a4a45;">
                  Pour finaliser l'activation de votre service <strong>${service.libelle}</strong>,
                  merci de cliquer sur le bouton ci-dessous.
                </p>
                <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#4a4a45;">
                  ${service.description}
                </p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px auto;">
                  <tr>
                    <td align="center" style="background:#d4622b;border-radius:8px;">
                      <a href="${url}" style="display:inline-block;padding:14px 32px;color:#ffffff;font-size:15px;font-weight:600;text-decoration:none;">Finaliser l'activation →</a>
                    </td>
                  </tr>
                </table>
                <p style="margin:24px 0 0;font-size:13px;line-height:1.6;color:#8a877e;text-align:center;">
                  Ce lien est valable pendant ${PAIEMENT_WEB_TOKEN_TTL_H} heures.<br>
                  Si le bouton ne fonctionne pas, copiez ce lien dans votre navigateur :<br>
                  <a href="${url}" style="color:#d4622b;word-break:break-all;">${url}</a>
                </p>
              </td>
            </tr>
            <tr>
              <td style="background:#faf9f6;padding:20px 32px;border-top:1px solid #e2dfd8;text-align:center;">
                <p style="margin:0;font-size:12px;color:#8a877e;line-height:1.5;">
                  Horem+ — Petites annonces immobilières Cameroun<br>
                  Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
  </html>`;
}

// Envoi de l'email de lien de paiement via Gmail SMTP.
async function envoyerEmailLienPaiement({ email, token, service, prenom }) {
  const senderEmail = process.env.GMAIL_SENDER_EMAIL;
  const appPassword = process.env.GMAIL_APP_PASSWORD;
  if (!senderEmail || !appPassword) {
    console.warn("envoyerEmailLienPaiement : GMAIL_SENDER_EMAIL / GMAIL_APP_PASSWORD non configurés.");
    throw new Error("Service email indisponible");
  }
  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: senderEmail, pass: appPassword },
  });
  const html = buildPaymentLinkEmailHtml({ token, service, prenom });
  await transporter.sendMail({
    from: `"Horem+" <${senderEmail}>`,
    to: email,
    subject: `Horem+ — Finalisez l'activation de votre service`,
    html,
    text: `Bonjour,\n\nPour finaliser l'activation de votre service ${service.libelle}, ouvrez ce lien :\n${WEB_PAY_BASE_URL}/${token}\n\nCe lien est valable ${PAIEMENT_WEB_TOKEN_TTL_H} heures.\n\nHorem+`,
  });
}

// ─── CF envoyerLienPaiementEmail ─────────────────────────────────────────────
// Appelée par l'app iOS. Crée un token, un doc paiements_web/<token>, et
// envoie l'email avec le lien.
// Auth : Bearer ID token Firebase (l'utilisateur doit être connecté).
// Body : { type, email, targetId?, params? }
//   - type : "premium" | "publication" | "sponsorisation" | "publicite" | "urgence" | "visibilite"
//   - email : adresse où envoyer le lien
//   - targetId : id du logement / publicité / alerte (selon le type)
//   - params : données spécifiques (duree, dureeJours, titre, typeBien, montant…)
// Retour : { success, token, expiresAt }
// ────────────────────────────────────────────────────────────────────────────
exports.envoyerLienPaiementEmail = onRequest(
  { cors: true, secrets: ["GMAIL_SENDER_EMAIL", "GMAIL_APP_PASSWORD"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      // Auth
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
      if (!idToken) {
        res.status(401).json({ success: false, error: "Authentification requise" });
        return;
      }
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ success: false, error: "Session invalide" });
        return;
      }
      const uid = decoded.uid;

      const { type, email, targetId, params } = req.body || {};
      if (!type || !TYPES_ACTIVATION.includes(type)) {
        res.status(400).json({ success: false, error: "Type de service invalide" });
        return;
      }
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        res.status(400).json({ success: false, error: "Email invalide" });
        return;
      }

      // Calcul du montant + libellé lisible (ne sont pas montrés dans l'app iOS).
      let service;
      try {
        service = calculerMontantEtLibelle(type, params || {});
      } catch (e) {
        res.status(400).json({ success: false, error: e.message });
        return;
      }

      // Prénom (personnalisation du mail)
      let prenom = "";
      try {
        const uSnap = await admin.firestore().collection("users").doc(uid).get();
        if (uSnap.exists) {
          const u = uSnap.data();
          prenom = u.prenom || u.nom || "";
        }
      } catch (_) {}

      // Création du doc paiements_web/<token>
      const token = genererTokenPaiement();
      const expiresAt = new Date(Date.now() + PAIEMENT_WEB_TOKEN_TTL_H * 60 * 60 * 1000);
      await admin.firestore().collection("paiements_web").doc(token).set({
        token,
        uid,
        type,
        targetId: targetId || null,
        params: params || {},
        montant: service.montant,
        libelle: service.libelle,
        description: service.description,
        email,
        statut: "en_attente",   // en_attente | initie | reussi | echoue | expire
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      });

      // Envoi de l'email
      try {
        await envoyerEmailLienPaiement({ email, token, service, prenom });
      } catch (e) {
        console.error("Email envoyer erreur:", e.message);
        // On garde le doc — le lien reste valide via URL directe.
        res.status(500).json({ success: false, error: "Impossible d'envoyer l'email" });
        return;
      }

      res.status(200).json({
        success: true,
        token,
        expiresAt: expiresAt.toISOString(),
      });
    } catch (error) {
      console.error("envoyerLienPaiementEmail :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur serveur" });
    }
  }
);

// ─── CF initierPaiementDepuisWeb ─────────────────────────────────────────────
// Appelée par la page web /pay/[token] (Immoconnect_admin).
// Pas d'auth Firebase : le token dans paiements_web sert de "clé porteur" —
// il est aléatoire (128 bits) et lié à un doc précis.
// Body : { token, telephone, operateur }
// Retour : { success, reference, checkoutUrl }
// Effet : crée le doc transactions/<reference> comme les autres CF, appelle
// GeniusPay, met à jour paiements_web/<token>.statut = "initie".
// ────────────────────────────────────────────────────────────────────────────
exports.initierPaiementDepuisWeb = onRequest(
  { cors: true, secrets: ["GENIUSPAY_API_KEY", "GENIUSPAY_SECRET_KEY", "GENIUSPAY_WEBHOOK_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Méthode non autorisée" });
      return;
    }
    try {
      const { token, telephone, operateur } = req.body || {};
      if (!token || !telephone) {
        res.status(400).json({ success: false, error: "Paramètres manquants" });
        return;
      }
      if (!/^[a-f0-9]{32}$/.test(String(token))) {
        res.status(400).json({ success: false, error: "Token invalide" });
        return;
      }

      const db = admin.firestore();
      const tokenRef = db.collection("paiements_web").doc(token);
      const tokenSnap = await tokenRef.get();
      if (!tokenSnap.exists) {
        res.status(404).json({ success: false, error: "Lien introuvable" });
        return;
      }
      const t = tokenSnap.data();

      // Expiration
      const expMs = t.expiresAt && t.expiresAt.toDate ? t.expiresAt.toDate().getTime() : 0;
      if (expMs && expMs < Date.now()) {
        await tokenRef.update({ statut: "expire" });
        res.status(410).json({ success: false, error: "Lien expiré" });
        return;
      }

      // Idempotence : si déjà réussi, on renvoie l'info
      if (t.statut === "reussi") {
        res.status(200).json({ success: true, alreadyPaid: true });
        return;
      }

      const uid = t.uid;
      const type = t.type;
      const params = t.params || {};
      const montant = Number(t.montant) || 0;
      if (!montant) {
        res.status(500).json({ success: false, error: "Montant invalide" });
        return;
      }

      // Récupère les infos du prestataire (customer GeniusPay)
      let u = {};
      try {
        const uSnap = await db.collection("users").doc(uid).get();
        if (uSnap.exists) u = uSnap.data();
      } catch (_) {}

      const internalRef = `web_${type}_${token.substring(0, 8)}_${Date.now()}`;

      // Métadonnées à propager dans la transaction (utilisées par
      // appliquerTransactionReussie() selon le type).
      const meta = {
        uid,
        type,
        paymentToken: token,
      };
      if (params.duree) meta.duree = params.duree;
      if (params.dureeJours) meta.dureeJours = params.dureeJours;
      if (t.targetId) {
        if (type === "publicite") meta.publiciteId = t.targetId;
        else meta.logementId = t.targetId;
      }

      const paiement = await geniuspay.createPayment({
        reference: internalRef,
        amount: montant,
        currency: DEVISE,
        paymentMethod: "pawapay",
        mmoProvider: mmoProviderCM(operateur),
        customerCountry: "CM",
        description: `Horem+ — ${t.libelle || type}`,
        customerEmail: t.email || u.email || "",
        customerPhone: telephone,
        metadata: meta,
        callbackUrl: GENIUSPAY_WEBHOOK_URL,
        returnUrl: PAIEMENT_SUCCESS_URL,
        errorUrl: PAIEMENT_ERROR_URL,
      });

      const reference = paiement.reference;

      // Doc transaction (même schéma que les autres flows Android)
      const txDoc = {
        uid,
        type,
        montant,
        devise: DEVISE,
        statut: "en_attente",
        reference,
        internalRef,
        telephone,
        checkoutUrl: paiement.paymentUrl,
        geniuspayTransactionId: paiement.transactionId,
        source: "ios_web",
        paymentToken: token,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (meta.logementId) txDoc.logementId = meta.logementId;
      if (meta.publiciteId) txDoc.publiciteId = meta.publiciteId;
      if (meta.duree) txDoc.duree = meta.duree;
      if (meta.dureeJours) txDoc.dureeJours = meta.dureeJours;

      await db.collection("transactions").doc(reference).set(txDoc);

      await tokenRef.update({
        statut: "initie",
        reference,
        checkoutUrl: paiement.paymentUrl,
        initieAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({
        success: true,
        reference,
        checkoutUrl: paiement.paymentUrl,
      });
    } catch (error) {
      console.error("initierPaiementDepuisWeb :", error.message, error.stack);
      res.status(500).json({ success: false, error: "Erreur lors de l'initiation du paiement.", geniuspayError: error.message });
    }
  }
);