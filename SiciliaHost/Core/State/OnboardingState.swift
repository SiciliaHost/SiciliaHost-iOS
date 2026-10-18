import Foundation
import Observation

/// Stato in memoria di presentazione e tour, condiviso tra le schermate (come `PendingInvite`):
/// - `introRequested`: "Rivedi la presentazione" dal Profilo;
/// - `tourRequested`: avvia il tour (fine della prima casa, o "Rivedi il tour" dal Profilo);
/// - `tourForced`: il tour parte anche se l'account l'ha già visto ("Rivedi il tour");
/// - `introShownThisRun`: la presentazione è già comparsa da quando l'app è aperta.
@MainActor
@Observable
final class OnboardingController {
    static let shared = OnboardingController()
    var introRequested = false
    var tourRequested = false
    var tourForced = false
    var introShownThisRun = false
}

/// "Presentazione vista" su questo telefono: serve prima del login, quando l'account non si conosce.
enum IntroPrefs {
    private static let key = "introSeen"

    static func introSeen(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }

    static func markIntroSeen(_ defaults: UserDefaults = .standard) { defaults.set(true, forKey: key) }
}

/// Codice invito ricevuto (link o incolla) e non ancora gestito. Vive in memoria: sopravvive al login perché il
/// processo resta lo stesso. `accepted` cresce a ogni invito accettato: chi mostra le case dell'utente lo osserva per
/// ricaricarle senza riavviare l'app. (La schermata di accettazione è in F9.)
@MainActor
@Observable
final class PendingInvite {
    static let shared = PendingInvite()

    private(set) var code: String?
    private(set) var accepted = 0

    func set(_ code: String) { self.code = code }
    func clear() { code = nil }
    func notifyAccepted() { accepted += 1 }
}

/// Stato del tour guidato in corso: i passi, quello corrente. Le posizioni degli elementi indicati arrivano dalle
/// preferenze di layout (`.tourTarget`), non da qui.
@MainActor
@Observable
final class TourState {
    private(set) var steps: [TourStep] = []
    private(set) var index = 0

    var isActive: Bool { !steps.isEmpty }
    var current: TourStep? { steps.indices.contains(index) ? steps[index] : nil }
    var isLast: Bool { index == steps.count - 1 }

    func start(_ list: [TourStep]) { index = 0; steps = list }
    func next() { if isLast { stop() } else { index += 1 } }
    func stop() { steps = []; index = 0 }
}
