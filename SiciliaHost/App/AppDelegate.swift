import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Configura Firebase una sola volta, qui o alla prima schermata. Senza `GoogleService-Info.plist` Firebase va in crash:
/// l'app mostra allora una schermata che spiega cosa fare.
enum FirebaseBootstrap {
    static let configured: Bool = {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        FirebaseApp.configure()
        return true
    }()
}

/// Push (APNs → FCM) e giro in sfondo (`MyFirebaseMessagingService.kt`). Con la lifecycle SwiftUI serve un delegato: il
/// token APNs arriva solo qui, e il compito in sfondo va registrato prima della fine dell'avvio.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AutoSync.register()
        guard FirebaseBootstrap.configured else { return true }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulatore, rete assente o Push non abilitato per l'app: nessun token, le notifiche push non arrivano.
    }

    /// Token FCM nuovo o rinnovato: si salva nel profilo se c'è un utente connesso (altrimenti all'accesso).
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { await PushToken.store(fcmToken) }
    }

    /// Messaggio con solo dati (senza `aps.alert`): lo mostriamo noi, come l'Android (`remoteMessage.data`).
    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let aps = userInfo["aps"] as? [String: Any]
        guard aps?["alert"] == nil else { return .noData }
        let title = userInfo["title"] as? String
        let body = userInfo["body"] as? String
        guard title != nil || body != nil else { return .noData }
        await LocalNotifier.post(title: title ?? "Nuova Prenotazione iCal", body: body ?? "Richiesto inserimento importo lordo")
        return .newData
    }

    /// Con l'app aperta la notifica si mostra comunque (l'Android la pubblica sempre).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
