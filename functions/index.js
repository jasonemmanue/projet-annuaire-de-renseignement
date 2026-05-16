const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

// ================================================================
// INITIALISATION FIREBASE ADMIN
// En production sur Firebase : admin.initializeApp() suffit.
// En local avec l'émulateur, décommente les 3 lignes ci-dessous :
// const serviceAccount = require("./serviceAccountKey.json");
// admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
// ================================================================
admin.initializeApp();

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
          conversationId: convId,
          type: "message",
          logementTitre: conv.logement_titre ?? "",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "sgkhome_messages", // ✅ Canal messages haute priorité
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
// Envoie une notification push à tous les visiteurs/clients.
// ================================================================
exports.sendNouvelleAnnonceNotification = onDocumentCreated(
  "logements/{logementId}",
  async (event) => {
    const logement = event.data.data();
    const logementId = event.params.logementId;

    const titre = logement.titre ?? "Nouvelle annonce";
    const ville = logement.ville ?? "";
    const quartier = logement.quartier ?? "";
    const prix = logement.prix ?? "";
    const typeLocation = logement.typeLocation ?? "location";

    const notifTitle = "🏠 Nouvelle annonce";
    const notifBody = `${titre} – ${quartier}, ${ville}`;

    try {
      // Récupère tous les tokens FCM des utilisateurs clients
      // (les prestataires ne reçoivent pas cette notif)
      const usersSnap = await admin.firestore()
        .collection("users")
        .get();

      const tokens = usersSnap.docs
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
          data: {
            type: "annonce",
            logementId: logementId,
            titre: titre,
            ville: ville,
            quartier: quartier,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "sgkhome_annonces", // ✅ Canal annonces
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