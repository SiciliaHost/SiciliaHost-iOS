import SwiftUI

/// Accesso. Il marchio è il pezzo forte: sta da solo su fondo verde, senza card intorno (come l'app Android). Il fondo è
/// il gradiente fisso del marchio, non una superficie del tema: resta lo stesso in chiaro e in scuro.
/// TODO F3: pulsanti "Accedi con Apple" (obbligatorio da App Store) e "Accedi con Google".
struct LoginView: View {
    let auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
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

            ScrollView {
                VStack(spacing: 0) {
                    BrandLogo(height: 130)
                    Text("RENTAL HOMES")
                        .appStyle(.labelSmall)
                        .foregroundStyle(yellow)
                        .padding(.top, 4)
                        .padding(.bottom, 28)

                    VStack(spacing: 10) {
                        TextField("", text: $email, prompt: Text("Email").foregroundStyle(.white.opacity(0.6)))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .modifier(LoginField())
                        SecureField("", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.6)))
                            .textContentType(isRegistering ? .newPassword : .password)
                            .modifier(LoginField())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .appStyle(.bodyMedium)
                            .foregroundStyle(yellow)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    }

                    Group {
                        if isBusy {
                            ProgressView().tint(yellow).frame(height: Dimens.controlHeight)
                        } else {
                            Button(action: submit) {
                                Text(isRegistering ? "Crea account" : "Accedi")
                                    .appStyle(.titleMedium)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AppPrimaryButtonStyle(container: .white, content: ink, cornerRadius: 10))
                            .disabled(email.isEmpty || password.isEmpty)
                        }
                    }
                    .padding(.top, 16)

                    Button(isRegistering ? "Hai già un account? Accedi" : "Non hai un account? Registrati") {
                        isRegistering.toggle()
                        errorMessage = nil
                    }
                    .buttonStyle(AppTextButtonStyle(color: .white))
                    .padding(.top, 6)
                }
                .frame(maxWidth: 360)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark) // fondo scuro fisso: tastiera e controlli di sistema coerenti
    }

    private func submit() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                if isRegistering {
                    try await auth.register(email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = AuthService.describe(error)
            }
            isBusy = false
        }
    }
}

/// Campo di testo traslucido bianco sul fondo verde.
private struct LoginField: ViewModifier {
    func body(content: Content) -> some View {
        let shape = roundedShape(10)
        content
            .appStyle(.bodyLarge)
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: Dimens.controlHeight + 4)
            .background(shape.fill(.white.opacity(0.14)))
            .overlay(shape.strokeBorder(.white.opacity(0.30), lineWidth: 1))
    }
}
