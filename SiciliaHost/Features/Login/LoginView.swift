import SwiftUI

struct LoginView: View {
    let auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("SiciliaHost").font(.largeTitle.bold())
            Text("Gestione delle tue case vacanza").foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(isRegistering ? .newPassword : .password)
            }
            .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center)
            }

            Button(action: submit) {
                if isBusy {
                    ProgressView()
                } else {
                    Text(isRegistering ? "Crea account" : "Accedi").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || email.isEmpty || password.isEmpty)

            Button(isRegistering ? "Hai già un account? Accedi" : "Non hai un account? Registrati") {
                isRegistering.toggle()
                errorMessage = nil
            }
            .font(.footnote)

            // TODO: pulsanti "Accedi con Apple" e "Accedi con Google".
            Spacer()
        }
        .padding(24)
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
