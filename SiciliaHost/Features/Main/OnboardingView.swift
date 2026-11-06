import SwiftUI

/// Primo accesso, o utente senza case: due grandi card di vetro, "Crea la tua prima casa" (consigliata, apre la
/// creazione guidata) e "Ho un codice invito" (per collaborare alla casa di un altro).
struct OnboardingView: View {
    let isBusy: Bool
    let error: String?
    let onCreateHouse: () -> Void
    let onInviteCode: (String) -> Void
    let onDismissError: () -> Void
    let onLogout: () -> Void
    /// Anche chi non ha ancora case deve poter eliminare l'account (App Store 5.1.1(v)); falso nell'anteprima demo.
    var showsAccountActions = true

    @State private var showInvite = false
    @State private var text = ""
    @State private var inviteError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BrandLogo(height: 70)
                Text("Iniziamo")
                    .appStyle(.headlineMedium)
                    .foregroundStyle(Theme.onSurface)
                Text("Non hai ancora nessuna casa. Crea la tua in pochi passi, oppure entra con il codice che ti ha dato il proprietario di una casa.")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                if let error {
                    Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error).multilineTextAlignment(.center)
                }
                if isBusy {
                    ProgressView().tint(Theme.primary)
                } else {
                    ActionCard(
                        systemImage: "house.and.flag.fill", title: "Crea la tua prima casa",
                        text: "Nome, posizione, foto e prezzi: ti guidiamo fase per fase.", highlighted: true
                    ) {
                        onDismissError()
                        onCreateHouse()
                    }
                    ActionCard(
                        systemImage: "person.badge.plus", title: "Ho un codice invito",
                        text: "Collabori alla gestione della casa di un altro host.", highlighted: false
                    ) {
                        text = ""
                        inviteError = nil
                        onDismissError()
                        showInvite = true
                    }
                    Button("Esci", action: onLogout).buttonStyle(.appText)
                    if showsAccountActions {
                        AccountActionsSection(scope: nil, onDeleted: onLogout)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showInvite) { inviteSheet }
    }

    private var inviteSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codice o link d'invito").appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Codice o link incollato", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .appStyle(.bodyLarge)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Dimens.controlHeight + 4)
                    .background(roundedShape(Radius.button).fill(Theme.surfaceContainerLowest.opacity(0.8)))
                    .overlay(roundedShape(Radius.button).strokeBorder(inviteError == nil ? Theme.outline : Theme.error, lineWidth: 1))
                    .onChange(of: text) { _, _ in inviteError = nil }
                if let inviteError {
                    Text(inviteError).appStyle(.bodySmall).foregroundStyle(Theme.error)
                }
            }
            HStack {
                Spacer()
                Button("Annulla") { showInvite = false }.buttonStyle(.appText)
                Button("Continua") {
                    // Il riscatto vero lo fa la schermata invito (anteprima + Accetta/Rifiuta).
                    if let code = InviteLink.extractCode(text) {
                        showInvite = false
                        onInviteCode(code)
                    } else {
                        inviteError = "Non è un codice o un link d'invito valido"
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(text.trimmed.isEmpty)
            }
        }
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationBackground(Theme.surfaceContainerHigh)
        .presentationCornerRadius(Radius.dialog)
    }
}

/// Card-azione di vetro; quella `highlighted` ha l'icona su un disco a gradiente.
private struct ActionCard: View {
    let systemImage: String
    let title: String
    let text: String
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    if highlighted {
                        Circle()
                            .fill(Theme.primary)
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)))
                            .softShadow(10, color: Theme.primary)
                    } else {
                        Circle().fill(Theme.primaryContainer)
                    }
                    Image(systemName: systemImage)
                        .font(.system(size: 22))
                        .foregroundStyle(highlighted ? Theme.onPrimary : Theme.onPrimaryContainer)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                    Text(text).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(roundedShape(Radius.extraLarge), elevation: highlighted ? 16 : 8)
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Pressione delle card-azione: rientrano a 0,97 con la molla e danno una vibrazione leggera.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.pressSpring, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
