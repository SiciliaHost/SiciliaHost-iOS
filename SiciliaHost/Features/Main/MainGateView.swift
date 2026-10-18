import FirebaseAuth
import SwiftUI

/// Ingresso dopo il login: caricamento, errore, "crea la tua prima casa" o l'app (porting di `MainGate.kt`).
struct MainGateView: View {
    let onSignOut: () -> Void
    @State private var model: MainViewModel

    init(user: User, onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
        _model = State(initialValue: MainViewModel(user: user))
    }

    var body: some View {
        Group {
            switch model.access {
            case .loading:
                ProgressView()
            case .ready:
                MainTabView(scope: model.scope, onSignOut: onSignOut)
            case .noHouses:
                // TODO: onboarding (creazione guidata della prima casa / codice invito), vedi OnboardingScreen.kt.
                ContentUnavailableView {
                    Label("Nessuna casa", systemImage: "building.2")
                } description: {
                    Text("Crea la tua prima casa o usa un codice di invito.")
                } actions: {
                    Button("Esci", action: onSignOut)
                }
            case .failed:
                ContentUnavailableView {
                    Label("Impossibile caricare i dati", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Riprova") { Task { await model.load() } }
                    Button("Esci", role: .destructive, action: onSignOut)
                }
            }
        }
        .task { await model.load() }
    }
}
