import BackgroundTasks
import FirebaseAuth
import FirebaseMessaging
import Foundation
import UserNotifications

// Notifiche e lavoro in sfondo (F10): permesso, token push, notifiche locali, promemoria Excel e giro periodico dei calendari.

/// Notifica locale (`LocalNotifier.kt`): usata per le push arrivate come solo dati e per i promemoria.
enum LocalNotifier {
    static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

enum NotificationPermission {
    /// Chiede il permesso una volta sola (stato non ancora deciso). Un rifiuto si cambia dalle impostazioni di iOS (Profilo).
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
}

/// Token FCM nel profilo dell'utente (`MyFirebaseMessagingService.onNewToken` + `updateFcmToken`).
enum PushToken {
    private static let key = "fcm.token"

    static func store(_ token: String) async {
        UserDefaults.standard.set(token, forKey: key)
        await saveForCurrentUser()
    }

    /// Salva il token noto (o lo chiede a Firebase) per l'utente connesso. Senza utente non fa nulla: si riprova all'accesso.
    static func saveForCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var token = UserDefaults.standard.string(forKey: key)
        if token == nil { token = try? await Messaging.messaging().token() }
        guard let token else { return }
        await FirestoreService().updateFcmToken(userId: uid, token: token)
    }
}

/// Promemoria mensile dell'export Excel Booking come notifiche locali pianificate (`ExcelReminder`).
enum ExcelReminderScheduler {
    /// Sostituisce i promemoria pianificati con quelli delle case date (quelle senza URL Booking non ne hanno).
    static func reschedule(for properties: [Property], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ExcelReminder.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let calendar = Calendar.current
        for property in properties where ExcelReminder.wantsReminder(property) {
            let fire = ExcelReminder.fireDate(lastImportAt: property.lastBookingExcelImportAt, now: now, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = ExcelReminder.title
            content.body = ExcelReminder.body(for: property)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false
            )
            try? await center.add(UNNotificationRequest(identifier: ExcelReminder.identifier(property.id), content: content, trigger: trigger))
        }
    }
}

/// Giro automatico dei calendari iCal. L'Android lo fa ogni ora con WorkManager; su iOS non esiste un'ora garantita:
/// si sincronizza all'apertura dell'app, al ritorno in primo piano (al massimo una volta ogni 55 minuti) e quando iOS
/// concede un giro in sfondo (`BGAppRefreshTask`, a discrezione del sistema: può essere molto più rado).
enum AutoSync {
    static let taskIdentifier = "com.siciliahost.cactushost.icalsync"
    static let minInterval: TimeInterval = 55 * 60

    private static func lastRunKey(_ uid: String) -> String { "ical.lastRunAt.\(uid)" }

    /// Ripianifica i promemoria Excel (dopo un import o una modifica degli URL).
    static func refreshReminders() async {
        // Riletto dal server: la data dell'ultimo import cambia fuori dalla sessione in cache.
        guard let scope = try? await AccessSession.shared.scope(forceRefresh: true) else { return }
        await ExcelReminderScheduler.reschedule(for: scope.managed)
    }

    /// Promemoria Excel sempre; calendari solo se è passato abbastanza dall'ultimo giro (o `force`). Solo le case che
    /// l'utente gestisce (chi può salvare gli URL nella sezione Gestione).
    static func runIfDue(force: Bool = false) async {
        guard let scope = try? await AccessSession.shared.scope() else { return }
        let houses = scope.managed
        await ExcelReminderScheduler.reschedule(for: houses)

        let key = lastRunKey(scope.uid)
        let now = Date().timeIntervalSince1970
        if !force, now - UserDefaults.standard.double(forKey: key) < minInterval { return }
        // Segnato prima del lavoro: due partenze ravvicinate (apertura + primo piano) non devono duplicare il giro.
        UserDefaults.standard.set(now, forKey: key)
        let service = ICalSyncService()
        for house in houses where !ICalSyncService.feeds(of: house).isEmpty {
            if Task.isCancelled { return }
            _ = await service.syncProperty(house)
        }
    }

    /// Da chiamare prima della fine dell'avvio dell'app (`didFinishLaunching`).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule() // il prossimo giro
            let work = Task {
                await runIfDue(force: true)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Chiede a iOS un giro tra almeno un'ora. Errori ignorati (simulatore, "Aggiorna app in background" spento).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
