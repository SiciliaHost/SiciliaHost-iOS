import FirebaseAuth
import SwiftUI

/// Ingresso dopo il login: caricamento, errore, "crea la tua prima casa" o l'app (porting di `MainGate.kt` e della
/// navigazione di `Navigation.kt`). Finché l'utente non ha almeno una casa nessuna sezione viene composta, quindi nessuna
/// schermata interroga Firestore.
struct MainGateView: View {
    let onSignOut: () -> Void
    @State private var model: MainViewModel
    @State private var router = AppRouter()
    /// Stato del check-in condiviso dalle sue quattro schermate, per prenotazione.
    @State private var checkinModels = CheckinModels()

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
                NavigationStack(path: $router.path) {
                    MainTabView(scope: model.scope, router: router, onSignOut: onSignOut)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Route.self) { destination(for: $0) }
                }
            case .noHouses:
                NavigationStack(path: $router.path) {
                    OnboardingView(
                        isBusy: model.isBusy, error: model.actionError,
                        onCreateHouse: { router.push(.newCaseWizard(propertyId: nil, level: .app)) },
                        // Il codice resta in attesa: lo mostra `InviteOverlay` (accetta / rifiuta).
                        onInviteCode: { PendingInvite.shared.set($0) },
                        onDismissError: model.clearActionError,
                        onLogout: onSignOut
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Route.self) { destination(for: $0) }
                }
            case .failed:
                StateMessage(
                    systemImage: "lock.fill", title: "Caricamento non riuscito",
                    message: "Non riesco a caricare le tue case. Controlla la connessione e riprova."
                ) {
                    Button("Riprova") { Task { await model.load() } }.buttonStyle(.appPrimary)
                    Button("Esci", action: onSignOut).buttonStyle(.appOutlined)
                }
            }
        }
        .task { await model.load() }
        // Tornando dalla creazione guidata la prima casa esiste già: si ricarica per lasciare l'onboarding.
        .onChange(of: router.path) { old, new in
            if model.access == .noHouses && new.count < old.count { Task { await model.load() } }
            // Uscendo dal check-in il suo stato si libera (alla prossima apertura si ricarica da Firestore).
            checkinModels.retain(only: Set(new.compactMap(\.checkinKey)))
        }
        // Invito accettato: le case cambiano, si ricaricano senza riavviare l'app.
        .onChange(of: PendingInvite.shared.accepted) { _, _ in Task { await model.reloadAfterInvite() } }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .profile:
            ProfileView(
                roleLabel: model.scope?.profileLabel ?? "",
                showMembers: model.scope?.owned.isEmpty == false,
                onBack: router.pop,
                onMembers: { router.push(.members) },
                onReplayTour: {
                    OnboardingController.shared.tourForced = true
                    OnboardingController.shared.tourRequested = true
                    router.popToRoot()
                },
                onLogout: onSignOut
            )
        case .members:
            MembersView(onBack: router.pop)
        case let .checkin(reservationId, propertyId):
            CheckinView(
                model: checkinModels.model(reservationId: reservationId, propertyId: propertyId),
                onScan: { router.push(.mrzScan(reservationId: reservationId, propertyId: propertyId)) },
                onEditGuest: { router.push(.guestForm(reservationId: reservationId, propertyId: propertyId, guestRecordId: $0)) },
                onSend: { router.push(.checkinSend(reservationId: reservationId, propertyId: propertyId)) },
                onBack: router.pop
            )
        case let .mrzScan(reservationId, propertyId):
            MrzScannerView(
                onDetected: { mrz in
                    checkinModels.model(reservationId: reservationId, propertyId: propertyId).pendingMrz = mrz
                    router.replaceTop(with: .guestForm(reservationId: reservationId, propertyId: propertyId, guestRecordId: nil))
                },
                onManualEntry: {
                    router.replaceTop(with: .guestForm(reservationId: reservationId, propertyId: propertyId, guestRecordId: nil))
                },
                onBack: router.pop
            )
        case let .guestForm(reservationId, propertyId, guestRecordId):
            GuestFormView(
                model: checkinModels.model(reservationId: reservationId, propertyId: propertyId),
                guestRecordId: guestRecordId,
                onDone: router.pop
            )
        case let .checkinSend(reservationId, propertyId):
            CheckinSendView(model: checkinModels.model(reservationId: reservationId, propertyId: propertyId), onBack: router.pop)
        case .editReservation(let reservationId):
            ReservationEditView(reservationId: reservationId, onBack: router.pop)
        case .priceEditor:
            PriceEditorView(onBack: router.pop)
        case .newCaseWizard:
            PendingScreen(title: "Nuova casa", androidSource: "ui/wizard", onBack: {
                router.pop()
                // Prima casa fatta: parte il tour (solo se l'account non l'ha già visto). Qui si chiude senza completare.
            })
        }
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
            Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(Theme.secondary)
            SectionLabel(title)
            if let message {
                Text(message).appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant).multilineTextAlignment(.center)
            }
            VStack(spacing: 6, content: actions)
                .padding(.top, 6)
        }
        .padding(Dimens.screenPadding * 2)
        .frame(maxWidth: 400)
    }
}
