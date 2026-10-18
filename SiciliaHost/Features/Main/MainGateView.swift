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
                ProgressView().tint(Theme.primary)
            case .ready:
                MainTabView(scope: model.scope, onSignOut: onSignOut)
            case .noHouses:
                // TODO: onboarding (creazione guidata della prima casa / codice invito), vedi OnboardingScreen.kt.
                StateMessage(
                    systemImage: "building.2", title: "Nessuna casa",
                    message: "Crea la tua prima casa o usa un codice di invito."
                ) {
                    Button("Esci", action: onSignOut).buttonStyle(.appOutlined)
                }
            case .failed:
                StateMessage(systemImage: "wifi.exclamationmark", title: "Impossibile caricare i dati", message: nil) {
                    Button("Riprova") { Task { await model.load() } }.buttonStyle(.appPrimary)
                    Button("Esci", action: onSignOut).buttonStyle(.appText(color: Theme.error))
                }
            }
        }
        .task { await model.load() }
    }
}

/// Stato a tutto schermo (errore, nessuna casa): icona, occhiello, messaggio e azioni.
struct StateMessage<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(Theme.onSurfaceVariant)
            SectionLabel(title)
            if let message {
                Text(message).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).multilineTextAlignment(.center)
            }
            VStack(spacing: 6, content: actions)
                .padding(.top, 6)
        }
        .padding(Dimens.screenPadding * 2)
        .frame(maxWidth: 360)
    }
}
