import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FirebaseApp.configure() reads GoogleService-Info.plist from the app
    // bundle and raises a fatal exception when it is absent. It was absent:
    // the file is committed under ios/Runner/ but is not referenced by
    // Runner.xcodeproj, so it never gets copied into the .app. The app died
    // here, on every iOS launch, before drawing a single frame — invisible
    // until now because building never needed the file, only running does.
    //
    // It is not needed anyway: Dart calls Firebase.initializeApp with
    // DefaultFirebaseOptions.ios (lib/firebase_options.dart), which configures
    // the native default app just the same. Configuring here stays conditional
    // so that adding the plist to the Xcode project later changes nothing.
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    }
    // Clé restreinte au bundle com.horemplus.app + Maps SDK for iOS.
    // Android utilise une clé distincte (AndroidManifest.xml) : une clé Google
    // ne peut porter qu'un seul type de restriction applicative à la fois.
    GMSServices.provideAPIKey("AIzaSyAO78D6gFAunMlI-Fj18m5_G83-Q4j2_4c")
    GeneratedPluginRegistrant.register(with: self)

    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Info.plist fixe FirebaseAppDelegateProxyEnabled = false : le swizzling est
  // desactive, donc le jeton APNs et les notifications silencieuses doivent etre
  // transmis a la main. Sans ces deux methodes, la verification Phone Auth
  // (push silencieux) n'aboutit jamais et l'OTP SMS n'est pas envoye sur iOS.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    #if DEBUG
      Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
    #else
      Auth.auth().setAPNSToken(deviceToken, type: .prod)
    #endif
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Les push de verification Phone Auth ne doivent pas remonter jusqu'a Flutter.
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(
      application,
      didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler
    )
  }
}
