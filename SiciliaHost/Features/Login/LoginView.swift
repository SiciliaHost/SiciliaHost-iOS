import SwiftUI

/// Accesso (`LoginScreen.kt`). Il marchio è il pezzo forte: sta da solo su fondo verde, senza card intorno. Il fondo è il
/// gradiente fisso del marchio, non una superficie del tema: resta lo stesso in chiaro e in scuro.
/// Solo "Accedi con Google": è l'unico accesso che le regole del backend ammettono (vedi `AuthService`).
struct LoginView: View {
    let auth: AuthService
    @State private var isBusy = false
    @State private var errorMessage: String?

    private let ink = Color(hex: Brand.ink)
    private let yellow = Color(hex: Brand.yellow)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: Brand.green900), Color(hex: Brand.green700), Color(hex: Brand.green)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                BrandLogo(height: 130)
                Text("RENTAL HOMES")
                    .appStyle(.labelSmall)
                    .foregroundStyle(yellow)
                    .padding(.top, 4)
                    .padding(.bottom, 28)

                if let errorMessage {
                    Text(errorMessage)
                        .appStyle(.bodyMedium)
                        .foregroundStyle(yellow)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }

                if isBusy {
                    ProgressView().tint(yellow).frame(height: Dimens.controlHeight)
                } else {
                    Button(action: signIn) {
                        Text("Accedi con Google")
                            .appStyle(.titleMedium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(container: .white, content: ink, cornerRadius: 10))
                }
            }
            .frame(maxWidth: 360)
            .padding(Dimens.screenPadding)
        }
        .preferredColorScheme(.dark) // fondo scuro fisso: controlli di sistema coerenti
    }

    private func signIn() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await auth.signInWithGoogle() // annullato dall'utente: nessun messaggio
            } catch {
                errorMessage = "Errore: \(AuthService.describe(error))"
            }
            isBusy = false
        }
    }
}
