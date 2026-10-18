import FirebaseAuth
import SwiftUI

/// Profilo: account, ruolo, e le azioni "Membri e inviti" (solo proprietari), "Rivedi la presentazione", "Rivedi il
/// tour" ed "Esci". Su Android mostra anche una riga diagnostica dello schermo per il Fold: su iPhone non serve.
struct ProfileView: View {
    let roleLabel: String
    let showMembers: Bool
    let onBack: () -> Void
    let onMembers: () -> Void
    let onReplayTour: () -> Void
    let onLogout: () -> Void

    private var email: String { Auth.auth().currentUser?.email ?? "Account sconosciuto" }

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Profilo", onBack: onBack)
            ScrollView {
                VStack(spacing: Dimens.itemSpacing) {
                    Spacer().frame(height: Dimens.sectionSpacing)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.primary)
                    Text(email).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                    Text(roleLabel).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                    Spacer().frame(height: Dimens.sectionSpacing)

                    if showMembers {
                        Button("Membri e inviti", action: onMembers).buttonStyle(.appOutlined)
                    }
                    // La guida: presentazione dell'app e tour delle funzioni, da rivedere quando si vuole.
                    Button("Rivedi la presentazione") { OnboardingController.shared.introRequested = true }
                        .buttonStyle(.appOutlined)
                    Button("Rivedi il tour", action: onReplayTour).buttonStyle(.appOutlined)
                    Button("Esci", action: onLogout).buttonStyle(.appOutlined)
                }
                .frame(maxWidth: 400)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
