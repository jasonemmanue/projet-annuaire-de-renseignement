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
    FirebaseApp.configure()
    GMSServices.provideAPIKey("AIzaSyCiaCA-3EazbF-Ekh3D3GcdtHDZVMko9_Q")
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
