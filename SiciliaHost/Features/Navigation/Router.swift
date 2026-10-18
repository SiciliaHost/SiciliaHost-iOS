import Observation
import SwiftUI

/// Livello di una creazione guidata di casa: `app` = dati dell'app, `site` = dati per il sito.
enum WizardLevel: String, Hashable, Codable { case app = "APP", site = "SITE" }

/// Le destinazioni dell'app (`NavigationKeys.kt`), spinte sullo stack sopra la schermata principale.
/// Il login e la schermata principale non sono destinazioni: li sceglie `RootView` in base alla sessione.
enum Route: Hashable {
    case profile
    case members
    case checkin(reservationId: String, propertyId: String)
    case mrzScan(reservationId: String, propertyId: String)
    case guestForm(reservationId: String, propertyId: String, guestRecordId: String?)
    case checkinSend(reservationId: String, propertyId: String)
    case editReservation(reservationId: String)
    /// Creazione guidata di una casa: `propertyId` per riprendere una bozza.
    case newCaseWizard(propertyId: String?, level: WizardLevel)
}

/// Stack di navigazione condiviso. Mai svuotarlo del tutto con `pop` oltre la radice (la radice è la schermata principale).
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }

    func pop() { if !path.isEmpty { path.removeLast() } }

    func popToRoot() { path.removeAll() }

    /// Sostituisce la schermata in cima (es. la scansione MRZ → il modulo ospite) senza lasciarla nello stack.
    func replaceTop(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
}

/// Schermata di secondo livello non ancora portata: intestazione con "indietro" e un segnaposto.
struct PendingScreen: View {
    let title: String
    let androidSource: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: title, onBack: onBack)
            PlaceholderView(feature: title, androidSource: androidSource)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
