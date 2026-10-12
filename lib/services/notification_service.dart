import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

// ============================================================
// HANDLER BACKGROUND – fonction top-level obligatoire
// S'exécute dans un isolate séparé : pas d'accès au widget tree.
// ============================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Vérifie la préférence dans SharedPreferences (accessible hors isolate).
  final prefs = await SharedPreferences.getInstance();
  final type  = message.data['type'] ?? 'message';

  final isAnnonce = type == 'annonce' || type == 'nouvelle_annonce';
  final catKey = NotificationService.categoriePourType(type);

  final defaultEnabled = catKey == NotificationService.kNotifPrix ? false : true;
  final enabled = prefs.getBool(catKey) ?? defaultEnabled;
  if (!enabled) return;

  // Si le message contient déjà un champ notification, Android l'affiche
  // automatiquement — on ne double pas. On n'intervient que pour les data-only.
  if (message.notification != null) return;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(const InitializationSettings(android: androidInit));

  final chanId   = isAnnonce ? 'sgkhome_annonces' : 'sgkhome_messages';
  final chanName = isAnnonce ? 'Nouvelles annonces' : 'Messages';
  final title    = message.data['title']    as String? ?? chanName;
  final body     = message.data['body']     as String? ?? '';
  final convId   = message.data['conversationId'] as String?;
  final logId    = message.data['logementId']     as String?
      ?? message.data['logementid']               as String?;

  final payload = convId != null
      ? 'chat:$convId'
      : logId != null
          ? 'logement:$logId'
          : '';

  await local.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        chanId, chanName,
        importance: isAnnonce ? Importance.high : Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF0071C2),
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
    payload: payload,
  );
}

// NavigatorKey global – partagé avec main.dart
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// NOTIFICATION SERVICE
// 2 canaux Android distincts :
//   • sgkhome_messages   → nouveaux messages chat (max priorité)
//   • sgkhome_annonces   → nouvelles annonces prestataires
// ============================================================
class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const _chanMessages = 'sgkhome_messages';
  static const _chanAnnonces = 'sgkhome_annonces';

  // ── Clés SharedPreferences pour les préférences de notification ──
  static const kNotifAnnonces = 'notif_annonces';
  static const kNotifMessages = 'notif_messages';
  static const kNotifPrix     = 'notif_prix';
  // Catégories propres au prestataire (#20).
  static const kNotifPrestaModeration = 'notif_presta_moderation';
  static const kNotifPrestaSponsor    = 'notif_presta_sponsor';

  /// Catégorie de préférence d'un message push selon son champ `type`.
  static String categoriePourType(String type) {
    switch (type) {
      case 'annonce':
      case 'nouvelle_annonce':
        return kNotifAnnonces;
      case 'price_drop':
      case 'alerte_prix':
        return kNotifPrix;
      case 'moderation':
        return kNotifPrestaModeration;
      case 'fin_sponsorisation':
        return kNotifPrestaSponsor;
      default:
        return kNotifMessages;
    }
  }

  // ── FCM topics correspondants ──
  static const _topicAnnonces = 'new_listings';
  static const _topicPrix     = 'price_drops';

  static const _channelMessages = AndroidNotificationChannel(
    _chanMessages,
    'Messages',
    description: 'Nouveaux messages reçus dans vos conversations',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const _channelAnnonces = AndroidNotificationChannel(
    _chanAnnonces,
    'Nouvelles annonces',
    description: 'Nouvelles publications de prestataires',
    importance: Importance.high,
    playSound: true,
  );

  // ============================================================
  // INIT – appelé dans main()
  // ============================================================
  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalTap,
      onDidReceiveBackgroundNotificationResponse: _onLocalTapBackground,
    );

    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channelMessages);
    await androidPlugin?.createNotificationChannel(_channelAnnonces);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // ── App au premier plan puis tappée (background → foreground) ──
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // ── App complètement fermée (cold start depuis notification) ──
    // On attend que le widget tree soit prêt avant de naviguer.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Délai suffisant pour que NavigatorState soit monté.
      await Future.delayed(const Duration(milliseconds: 1000));
      _routeFromData(initial.data);
    }
  }

  // ============================================================
  // PRÉFÉRENCES NOTIFICATIONS
  // ============================================================

  /// Retourne true si la catégorie est activée (default : true sauf prix).
  static Future<bool> isCategoryEnabled(String category) async {
    final prefs = await SharedPreferences.getInstance();
    if (category == kNotifPrix) {
      return prefs.getBool(kNotifPrix) ?? false;
    }
    return prefs.getBool(category) ?? true;
  }

  /// Persiste le choix, gère les topics FCM et synchronise l'API.
  static Future<void> setCategory(String category, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(category, enabled);

    if (category == kNotifAnnonces) {
      if (enabled) {
        await _fcm.subscribeToTopic(_topicAnnonces);
      } else {
        await _fcm.unsubscribeFromTopic(_topicAnnonces);
      }
    } else if (category == kNotifPrix) {
      if (enabled) {
        await _fcm.subscribeToTopic(_topicPrix);
      } else {
        await _fcm.unsubscribeFromTopic(_topicPrix);
      }
    } else {
      // Synchronise dans l'API : le serveur n'envoie pas les push d'une
      // catégorie désactivée (messages, modération, fin de sponsorisation).
      const champsApi = {
        kNotifMessages: 'notifMessages',
        kNotifPrestaModeration: 'notifModeration',
        kNotifPrestaSponsor: 'notifFinSponsor',
      };
      final champ = champsApi[category];
      final user = FirebaseAuth.instance.currentUser;
      if (champ != null && user != null && !user.isAnonymous) {
        try {
          await ApiClient.instance.put('/users/me', {champ: enabled});
        } catch (_) {}
      }
    }
  }

  /// Charge toutes les préférences sous forme de Map (pour l'UI).
  static Future<Map<String, bool>> loadAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      kNotifAnnonces: prefs.getBool(kNotifAnnonces) ?? true,
      kNotifMessages: prefs.getBool(kNotifMessages) ?? true,
      kNotifPrix:     prefs.getBool(kNotifPrix)     ?? false,
      kNotifPrestaModeration: prefs.getBool(kNotifPrestaModeration) ?? true,
      kNotifPrestaSponsor:    prefs.getBool(kNotifPrestaSponsor)    ?? true,
    };
  }

  // ============================================================
  // FOREGROUND FCM → notification locale heads-up
  // ============================================================
  static void _onForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    final type = message.data['type'] ?? 'message';
    if (notif == null) return;

    final isAnnonce = type == 'annonce' || type == 'nouvelle_annonce';
    final category = categoriePourType(type);

    if (!await isCategoryEnabled(category)) return;

    _local.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isAnnonce ? _chanAnnonces : _chanMessages,
          isAnnonce ? 'Nouvelles annonces' : 'Messages',
          importance: isAnnonce ? Importance.high : Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF0071C2),
          styleInformation: BigTextStyleInformation(notif.body ?? ''),
          ticker: notif.title,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: _buildPayload(message.data),
    );
  }

  // ============================================================
  // NOTIFICATION MANUELLE – nouveau message (foreground local)
  // ============================================================
  static Future<void> showMessageNotification({
    required String senderName,
    required String messageText,
    required String conversationId,
    required String logementTitre,
  }) async {
    if (!await isCategoryEnabled(kNotifMessages)) return;
    await _local.show(
      conversationId.hashCode,
      '💬 $senderName',
      messageText,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chanMessages, 'Messages',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF0071C2),
          subText: logementTitre,
          styleInformation: BigTextStyleInformation(messageText),
          ticker: 'Nouveau message',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: 'chat:$conversationId',
    );
  }

  // ============================================================
  // NOTIFICATION MANUELLE – nouvelle annonce
  // ============================================================
  static Future<void> showNouvelleAnnonceNotification({
    required String titre,
    required String ville,
    required String quartier,
    required String logementId,
  }) async {
    if (!await isCategoryEnabled(kNotifAnnonces)) return;
    await _local.show(
      logementId.hashCode,
      '🏠 Nouvelle annonce',
      '$titre – $quartier, $ville',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chanAnnonces, 'Nouvelles annonces',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF0071C2),
          styleInformation:
          BigTextStyleInformation('$titre\n📍 $quartier, $ville'),
          ticker: 'Nouvelle annonce disponible',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      // ── Payload mis à jour pour inclure logementId ──
      payload: 'logement:$logementId',
    );
  }

  // ============================================================
  // ROUTING
  // ============================================================

  /// Appelé quand l'app était en background et que l'utilisateur tappe
  /// sur la notification (système ou FCM).
  static void _onMessageOpenedApp(RemoteMessage message) =>
      _routeFromData(message.data);

  static void _onLocalTap(NotificationResponse r) {
    if (r.payload != null) _routeFromPayload(r.payload!);
  }

  @pragma('vm:entry-point')
  static void _onLocalTapBackground(NotificationResponse r) {
    if (r.payload != null) _routeFromPayload(r.payload!);
  }

  /// Résout le type de message FCM et pousse la bonne route.
  static void _routeFromData(Map<String, dynamic> data) {
    final type = data['type'] ?? '';

    // ── Messages chat ──
    if (type == 'message' || data['conversationId'] != null) {
      final convId = data['conversationId'] as String?;
      if (convId != null) {
        _navigateTo('/chat', {'conversationId': convId});
      }
      return;
    }

    // ── Nouvelle annonce (type mis à jour dans la Cloud Function) ──
    if (type == 'nouvelle_annonce' || type == 'annonce') {
      final logementId = data['logementId'] as String?;
      if (logementId != null) {
        _navigateTo('/logement', {'logementId': logementId});
      }
      return;
    }

    // ── Mise à jour logement (vues milestone) ──
    if (type == 'logement_update') {
      final logementId = data['logementId'] as String?;
      if (logementId != null) {
        _navigateTo('/logement', {'logementId': logementId});
      }
      return;
    }
  }

  /// Résout un payload local (chaîne préfixée) vers la bonne route.
  static void _routeFromPayload(String payload) {
    if (payload.startsWith('chat:')) {
      _navigateTo('/chat', {'conversationId': payload.substring(5)});
    } else if (payload.startsWith('logement:')) {
      _navigateTo('/logement', {'logementId': payload.substring(9)});
    }
  }

  static void _navigateTo(String route, Map<String, dynamic> args) {
    navigatorKey.currentState?.pushNamed(route, arguments: args);
  }

  /// Construit la chaîne payload pour flutter_local_notifications.
  static String _buildPayload(Map<String, dynamic> data) {
    if (data['conversationId'] != null) {
      return 'chat:${data['conversationId']}';
    }
    if (data['logementId'] != null) {
      return 'logement:${data['logementId']}';
    }
    return '';
  }

  // ============================================================
  // TOKEN FCM
  // ============================================================
  static Future<void> saveToken(String uid) async {
    final token = await _fcm.getToken();
    if (token == null) return;
    try {
      await ApiClient.instance.put('/users/me/fcm', {'token': token});
    } catch (_) {}
    // Rafraîchissement automatique du token (rotation FCM)
    _fcm.onTokenRefresh.listen((t) async {
      try {
        await ApiClient.instance.put('/users/me/fcm', {'token': t});
      } catch (_) {}
    });
  }

  static Future<void> clearToken(String uid) async {
    try {
      await ApiClient.instance.put('/users/me/fcm', {'token': null});
    } catch (_) {}
    await _fcm.deleteToken();
  }
}