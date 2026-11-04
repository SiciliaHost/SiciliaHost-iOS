import FirebaseCore
import SwiftUI

@main
struct SiciliaHostApp: App {
    /// Push e giro in sfondo (F10): il delegato configura Firebase già all'avvio (`FirebaseBootstrap`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Senza `GoogleService-Info.plist` Firebase va in crash: si mostra invece una schermata che spiega cosa fare.
    private static let firebaseConfigured = FirebaseBootstrap.configured

    var body: some Scene {
        WindowGroup {
            if Self.firebaseConfigured, let screen = UIPreview.requestedScreen {
                UIPreviewRoot(screen: screen) // solo build di debug, con `-UIPreview <schermata>`
            } else if Self.firebaseConfigured {
                RootView()
            } else {
                MissingConfigView()
            }
        }
    }
}

private struct MissingConfigView: View {
    var body: some View {
        ContentUnavailableView(
            "Configurazione Firebase mancante",
            systemImage: "exclamationmark.triangle",
            description: Text("Aggiungi GoogleService-Info.plist in SiciliaHost/Resources (vedi docs/SETUP_MAC.md).")
        )
    }
}
