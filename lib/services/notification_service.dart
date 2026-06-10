import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================
// HANDLER BACKGROUND – fonction top-level obligatoire
// ============================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] ${message.notification?.title}');
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
  static final _db = FirebaseFirestore.instance;

  static const _chanMessages = 'sgkhome_messages';
  static const _chanAnnonces = 'sgkhome_annonces';

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
  // FOREGROUND FCM → notification locale heads-up
  // ============================================================
  static void _onForegroundMessage(RemoteMessage message) {
    final notif = message.notification;
    final type = message.data['type'] ?? 'message';
    if (notif == null) return;

    final isAnnonce =
        type == 'annonce' || type == 'nouvelle_annonce';

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
    await _db.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
    // Rafraîchissement automatique du token (rotation FCM)
    _fcm.onTokenRefresh.listen((t) async {
      await _db
          .collection('users')
          .doc(uid)
          .set({'fcmToken': t}, SetOptions(merge: true));
    });
  }

  static Future<void> clearToken(String uid) async {
    await _db.collection('users').doc(uid).set(
      {'fcmToken': null},
      SetOptions(merge: true),
    );
    await _fcm.deleteToken();
  }
}