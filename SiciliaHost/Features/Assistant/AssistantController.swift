import Foundation
import SwiftUI

/// Lo stato condiviso tra la barra di navigazione, i moduli dell'app e l'overlay di Cactus.
@Observable
public final class AssistantController: @unchecked Sendable {
    public static let shared = AssistantController()

    /// L'assistente è abilitato per questo account (host registrato + interruttore attivo).
    public var available: Bool = false

    /// L'overlay dell'assistente è aperto a schermo.
    public var open: Bool = false

    /// La barra di navigazione principale è visibile (in tal caso il pulsante flottante si nasconde).
    public var navbarVisible: Bool = false

    /// `MainGate` è pronto (non in stato di caricamento, errore o onboarding iniziale).
    public var mainReady: Bool = false

    /// Scarta la conversazione prima del logout.
    public var discardHandler: (@Sendable () async -> Void)? = nil

    // MARK: - Messa in Scena dal Vivo (Live Staging)

    private var dirtySources: [String: Bool] = [:]

    /// Registra o rimuove lo stato «bozza non salvata» di una schermata dell'app (`case_…`, `services_…`, `page_…`).
    public func setDirty(key: String, dirty: Bool) {
        if dirty {
            dirtySources[key] = true
        } else {
            dirtySources.removeValue(forKey: key)
        }
    }

    /// Vero se almeno un modulo aperto ha modifiche non salvate: evita sovrascritture involontarie.
    public var hasDirtyForms: Bool {
        dirtySources.values.contains(true)
    }

    /// Contatore che sale dopo ogni scrittura confermata/annullata di Cactus: notifica le schermate di ricaricare i dati.
    public var liveRefreshTick: Int = 0

    public func notifyLiveDataChanged() {
        liveRefreshTick += 1
    }

    public func reset() {
        available = false
        open = false
        dirtySources.removeAll()
    }

    /// Da chiamare prima del logout: cancella la conversazione dal server con le credenziali attive.
    public func discardForLogout() async {
        guard let handler = discardHandler else { return }
        // Timeout di 2.5s per non bloccare il logout
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await handler()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}

/// Decide se mostrare il pulsante flottante in basso a destra sulle schermate secondarie.
public func showFloatingAssistant(
    available: Bool,
    open: Bool,
    navbarVisible: Bool,
    isKeyboardShowing: Bool,
    mainReady: Bool,
    route: Route?
) -> Bool {
    if !available || open || navbarVisible || isKeyboardShowing { return false }
    guard let route = route else {
        return mainReady
    }
    switch route {
    case .mrzScanner, .newCaseWizard, .checkin, .checkinSend, .guestForm, .editReservation:
        return false
    default:
        return true
    }
}
