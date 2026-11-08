import AuthenticationServices
import SwiftUI

/// Accesso (`LoginScreen.kt`): Cactus al centro (si muove da solo e «pensa» mentre l'accesso è in corso), il nome dell'app,
/// i pulsanti e, in fondo, «powered by SiciliaHost» con il logo: il marchio dell'azienda resta sullo sfondo. Il fondo è il
/// palcoscenico verde del marchio (`BrandBackdrop`), uguale in chiaro e in scuro.
/// «Accedi con Google» e «Accedi con Apple» (obbligatorio da App Store) sono gli accessi veri. «Accesso revisori»
/// (email e password, chiuso di default) serve solo all'account dimostrativo per i revisori degli store: le regole di
/// Firestore e Storage lo ammettono per quell'unico uid (vedi `AuthService`).
struct LoginView: View {
    let auth: AuthService
    @State private var isBusy = false
    @State private var errorMessage: String?
    /// Stringa casuale il cui hash è stato mandato ad Apple nella richiesta in corso.
    @State private var appleNonce: String?
    @State private var isDemoActive = false
    @State private var reviewerOpen = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: ReviewerField?

    private enum ReviewerField { case email, password }

    private let ink = Color(hex: Brand.ink)
    private let yellow = Color(hex: Brand.yellow)

    var body: some View {
        BrandBackdrop {
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 4)

                    VStack(spacing: 0) {
                        CactusHero(state: isBusy ? .thinking : .idle)
                            .frame(width: 240, height: 260)
                        Text("CactusHost")
                            .appStyle(.displaySmall)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Le tue case vacanza, sotto controllo.")
                            .appStyle(.bodyLarge)
                            .foregroundStyle(Color.white.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }

                    VStack(spacing: 0) {
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
                            .buttonStyle(AppPrimaryButtonStyle(container: .white, content: ink, cornerRadius: 14))

                            SignInWithAppleButton(.signIn) { request in
                                let nonce = AppleNonce.random()
                                appleNonce = nonce
                                request.requestedScopes = [.fullName, .email]
                                request.nonce = AppleNonce.sha256(nonce)
                            } onCompletion: { result in
                                signInWithApple(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: Dimens.controlHeight + 4)
                            .clipShape(roundedShape(14))
                            .padding(.top, 10)

                            Button(action: { isDemoActive = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill")
                                    Text("Esplora con dati dimostrativi (Demo)")
                                }
                                .font(.subheadline.bold())
                                .foregroundStyle(yellow)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)

                            // Accesso con email e password: solo per i revisori degli store (account dimostrativo).
                            Button {
                                withAnimation(.emphasized) { reviewerOpen.toggle() }
                            } label: {
                                Text("Accesso revisori")
                                    .appStyle(.labelMedium)
                                    .foregroundStyle(Color.white.opacity(0.8))
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 36)
                            }
                            .buttonStyle(.plain)

                            if reviewerOpen { reviewerForm }
                        }
                    }
                    .frame(maxWidth: 380)
                    .padding(.top, 20)

                    PoweredBySiciliaHost()
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            }
        }
        .fullScreenCover(isPresented: $isDemoActive) {
            UIPreviewRoot(screen: "home", onDismiss: { isDemoActive = false })
        }
    }

    /// Campi email e password dell'accesso revisori. Niente viene salvato: restano solo in memoria finché la vista è aperta.
    private var reviewerForm: some View {
        VStack(spacing: 8) {
            TextField("", text: $email, prompt: Text("Email").foregroundStyle(Color.white.opacity(0.6)))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
                .reviewerFieldStyle()
            SecureField("", text: $password, prompt: Text("Password").foregroundStyle(Color.white.opacity(0.6)))
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit(signInWithEmail)
                .reviewerFieldStyle()
            Button(action: signInWithEmail) {
                Text("Accedi").appStyle(.titleMedium).frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(container: yellow, content: ink, cornerRadius: 12))
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
        }
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

    private func signInWithApple(_ result: Result<ASAuthorization, Error>) {
        isBusy = true
        errorMessage = nil
        let nonce = appleNonce
        Task {
            do {
                try await auth.signInWithApple(result: result, rawNonce: nonce) // annullato dall'utente: nessun messaggio
            } catch {
                errorMessage = "Errore: \(AuthService.describe(error))"
            }
            isBusy = false
        }
    }

    private func signInWithEmail() {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty, !isBusy else { return }
        focus = nil
        isBusy = true
        errorMessage = nil
        let mail = email
        let pass = password
        Task {
            do {
                try await auth.signInWithEmail(email: mail, password: pass)
                password = "" // entrato: la password non resta in memoria nella vista
            } catch {
                errorMessage = "Errore: \(AuthService.describe(error))"
            }
            isBusy = false
        }
    }
}

private extension View {
    /// Campo di testo chiaro su fondo verde (come gli `OutlinedTextField` bianchi dell'Android).
    func reviewerFieldStyle() -> some View {
        self
            .appStyle(.bodyLarge)
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: Dimens.controlHeight)
            .background(roundedShape(12).fill(Color.white.opacity(0.12)))
            .overlay(roundedShape(12).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
    }
}
