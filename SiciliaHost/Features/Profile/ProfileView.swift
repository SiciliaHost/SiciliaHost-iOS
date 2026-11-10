import FirebaseAuth
import SwiftUI
import UserNotifications

/// Impostazioni (ex «Profilo», `ProfileScreen.kt`): intestazione con nome modificabile, Collaboratori in evidenza (apre il
/// suo sottomenù), poi le voci per categoria: Le mie case, Notifiche, Guida, Privacy e sicurezza, Account, versione.
/// Non portati perché non esistono su iPhone: la riga diagnostica del Fold e il widget Cactus.
struct ProfileView: View {
    let roleLabel: String
    let scope: AccessScope?
    let onBack: () -> Void
    let onHouse: (String) -> Void
    let onPrivacy: () -> Void
    let onCollaborators: () -> Void
    let onReplayTour: () -> Void
    let onLogout: () -> Void
    /// Falso nell'anteprima con dati dimostrativi: lì non c'è un account da eliminare.
    var showsAccountActions = true

    @State private var model = ProfileModel()
    @State private var editingName = false
    @State private var notificationsDenied = false
    @State private var leaving = false
    @State private var confirmLogout = false
    @State private var confirmClearRecords = false
    @State private var clearFailed = false
    @Environment(\.openURL) private var openURL

    private var email: String { Auth.auth().currentUser?.email ?? "Account sconosciuto" }

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Impostazioni", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    header

                    // Collaboratori in primo piano, subito sotto l'intestazione.
                    CollaboratorsCard(summary: collaboratorsSummary(collaboratorsOverview(scope)), action: onCollaborators)

                    SettingsGroup(title: "Le mie case", items: houseItems, emptyText: "Nessuna casa.")

                    SettingsGroup(title: "Notifiche", items: notificationItems)

                    SettingsGroup(title: "Guida", items: [
                        SettingsItem(systemImage: "play.rectangle", title: "Rivedi la presentazione") {
                            OnboardingController.shared.introRequested = true
                        },
                        SettingsItem(systemImage: "safari", title: "Rivedi il tour", action: onReplayTour),
                    ])

                    SettingsGroup(title: "Privacy e sicurezza", items: [
                        SettingsItem(systemImage: "lock.shield", title: "Come proteggiamo i tuoi dati", action: onPrivacy),
                        SettingsItem(
                            systemImage: "trash", title: "Schede del check-in su questo telefono",
                            subtitle: "Le schede degli ospiti restano solo qui. Tocca per cancellarle tutte."
                        ) { confirmClearRecords = true },
                    ])

                    SettingsGroup(title: "Account", items: [
                        SettingsItem(systemImage: "rectangle.portrait.and.arrow.right", title: "Esci", enabled: !leaving) {
                            guard !leaving else { return }
                            // Nel dubbio (archivio illeggibile) si chiede conferma: uscendo le schede si cancellano.
                            if GuestRecordStore.shared.hasUnsent() {
                                confirmLogout = true
                            } else {
                                logout()
                            }
                        },
                    ])
                    if showsAccountActions {
                        AccountActionsSection(scope: scope, onDeleted: onLogout)
                    }

                    Text("SiciliaHost \(appVersion)")
                        .appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                        .padding(.top, Dimens.sectionSpacing)
                }
                .frame(maxWidth: 400, alignment: .leading)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await refreshNotificationState() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshNotificationState() }
        }
        .confirmationDialog("Schede non inviate", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Esci e cancella", role: .destructive) { logout() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Su questo telefono ci sono schede del check-in mai inviate. Uscendo verranno cancellate.")
        }
        .confirmationDialog("Cancellare le schede?", isPresented: $confirmClearRecords, titleVisibility: .visible) {
            Button("Cancella", role: .destructive) {
                ReceiptFiles.clear()
                do {
                    try GuestRecordStore.shared.clear()
                } catch {
                    clearFailed = true
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Cancelliamo da questo telefono tutte le schede del check-in, anche quelle mai inviate. Le credenziali restano.")
        }
        .alert("Non sono riuscito a cancellare le schede. Riprova.", isPresented: $clearFailed) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $editingName, onDismiss: { model.error = nil }) {
            EditNameSheet(model: model) { editingName = false }
        }
    }

    /// Uscita confermata (o senza schede da inviare): le schede del check-in si cancellano tutte, poi si esce
    /// (`signOutDiscardingAssistant(wipeUnsentCheckin = true)` dell'Android).
    private func logout() {
        guard !leaving else { return }
        leaving = true
        ReceiptFiles.clear()
        try? GuestRecordStore.shared.clear()
        onLogout()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(String((model.displayName.trimmed.isEmpty ? email : model.displayName).prefix(1)).uppercased())
                .appStyle(.titleLarge)
                .foregroundStyle(Theme.onPrimaryContainer)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.primaryContainer))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName.trimmed.isEmpty ? "Aggiungi il tuo nome" : model.displayName)
                    .appStyle(.titleMedium).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(email).appStyle(.bodySmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                if !roleLabel.isEmpty {
                    Text(roleLabel).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.error = nil
                editingName = true
            } label: {
                Image(systemName: "pencil").frame(width: Dimens.controlHeight, height: Dimens.controlHeight)
            }
            .buttonStyle(.appIcon)
            .accessibilityLabel("Modifica il nome")
        }
    }

    private var houseItems: [SettingsItem] {
        (scope.map(houseRows) ?? []).map { row in
            SettingsItem(
                systemImage: "building.2", title: row.name,
                subtitle: [row.roleLabel, row.permissionsText].compactMap { $0 }.joined(separator: " · ")
            ) { onHouse(row.propertyId) }
        }
    }

    private var notificationItems: [SettingsItem] {
        var items: [SettingsItem] = []
        if notificationsDenied {
            items.append(SettingsItem(
                systemImage: "bell.slash", title: "Le notifiche sono disattivate",
                subtitle: "Attivale dalle impostazioni del telefono per non perdere prenotazioni e avvisi."
            ) { openNotificationSettings() })
        }
        items.append(SettingsItem(
            systemImage: "bell", title: "Impostazioni notifiche",
            subtitle: "Nuove prenotazioni, importi da inserire, avvisi dal sito e promemoria Booking"
        ) { openNotificationSettings() })
        return items
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func refreshNotificationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}

/// Riga toccabile con titolo e sottotitolo (`NavRow` dell'Android).
struct NavRow: View {
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Dimens.cardPadding)
            .appCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditNameSheet: View {
    let model: ProfileModel
    let onClose: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il tuo nome").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
            Text("Lo vedono i collaboratori delle tue case al posto dell'email.")
                .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            AppTextField(
                label: "Nome", text: $text,
                supporting: "\(cleanDisplayName(text).count)/\(displayNameMax)",
                error: model.error, capitalization: .words
            )
            .disabled(model.isSaving)
            .onChange(of: text) { _, _ in model.error = nil }
            HStack {
                Button("Annulla", action: onClose).buttonStyle(.appText).disabled(model.isSaving)
                Spacer()
                Button(model.isSaving ? "Salvataggio…" : "Salva") {
                    Task { if await model.saveDisplayName(text) { onClose() } }
                }
                .buttonStyle(.appPrimary)
                .disabled(model.isSaving)
            }
            Spacer(minLength: 0)
        }
        .padding(Dimens.screenPadding + 4)
        .presentationDetents([.medium])
        .onAppear { text = model.displayName }
    }
}
