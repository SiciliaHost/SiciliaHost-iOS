import Observation
import SwiftUI

/// Dati della Home (`DashboardViewModel`): arrivi di oggi e prenotazioni da completare delle case su cui si opera.
/// Il caricamento è iniettabile per le anteprime della CI (dati inventati, nessun accesso a Firestore).
@MainActor
@Observable
final class HomeModel {
    private(set) var arrivalsToday: [Reservation] = []
    private(set) var pendingReview: [Reservation] = []
    private(set) var properties: [Property] = []
    private(set) var isLoading = false
    var isCreatingGuest = false
    var actionError: String?

    private let fetch: ([String]) async throws -> [Reservation]
    private let create: (Reservation) async throws -> Reservation

    init(
        fetch: @escaping ([String]) async throws -> [Reservation] = { try await FirestoreService().getReservations(propertyIds: $0) },
        create: @escaping (Reservation) async throws -> Reservation = { try await FirestoreService().addReservation($0) }
    ) {
        self.fetch = fetch
        self.create = create
    }

    /// Una sola lettura per casa serve sia agli arrivi sia alle "da completare" (l'Android ne faceva due uguali).
    func load(scope: AccessScope?) async {
        let operable = scope?.operable ?? []
        properties = operable
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await fetch(operable.map(\.id))
            arrivalsToday = AgendaLogic.arrivalsToday(all, now: millisFromDate(Date()))
            pendingReview = AgendaLogic.pendingReview(all)
        } catch {
            arrivalsToday = []
            pendingReview = []
        }
    }

    /// "Aggiungi ospite": crea una prenotazione manuale oggi → domani e ne restituisce l'id per aprire il check-in.
    func createManualReservation(propertyId: String) async -> Reservation? {
        isCreatingGuest = true
        defer { isCreatingGuest = false }
        do {
            return try await create(AgendaLogic.newManualReservation(propertyId: propertyId, now: millisFromDate(Date())))
        } catch {
            actionError = "Non riesco a creare la prenotazione. Controlla la connessione e riprova."
            return nil
        }
    }
}

/// Home (`DashboardScreen.kt`): data e numero di arrivi, prenotazioni da completare (tocco → modifica), arrivi di oggi
/// (tocco → check-in) e il pulsante "Aggiungi ospite" che crea una prenotazione manuale e apre il check-in.
struct HomeView: View {
    let scope: AccessScope?
    let onProfile: () -> Void
    let onCheckin: (_ reservationId: String, _ propertyId: String) -> Void
    let onEditReservation: (_ reservationId: String) -> Void
    @State var model: HomeModel

    @State private var showPropertyPicker = false
    @State private var chosenPropertyId: String?

    init(
        scope: AccessScope?,
        onProfile: @escaping () -> Void,
        onCheckin: @escaping (String, String) -> Void = { _, _ in },
        onEditReservation: @escaping (String) -> Void = { _ in },
        model: HomeModel = HomeModel()
    ) {
        self.scope = scope
        self.onProfile = onProfile
        self.onCheckin = onCheckin
        self.onEditReservation = onEditReservation
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
                    header
                    if !model.pendingReview.isEmpty { pendingSection }
                    arrivals
                }
                .padding(Dimens.screenPadding)
                // Spazio per il pulsante "Aggiungi ospite", che non deve coprire l'ultima riga.
                .padding(.bottom, 56)
            }
            .refreshable { await model.load(scope: scope) }

            addGuestButton
        }
        .overlay {
            if model.isCreatingGuest { ProgressView().tint(Theme.primary) }
        }
        // Si ricarica a ogni ritorno sulla Home (anche dopo aver salvato una prenotazione): come il `LaunchedEffect`.
        .onAppear { Task { await model.load(scope: scope) } }
        .onChange(of: scope) { _, newScope in Task { await model.load(scope: newScope) } }
        .sheet(isPresented: $showPropertyPicker) { propertyPicker }
        .alert("Operazione non riuscita", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    // Niente barra in alto: una riga sola che è già informazione (quanti arrivi + data).
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OGGI · \(model.arrivalsToday.count) ARRIVI")
                    .appStyle(.labelSmall)
                    .foregroundStyle(Theme.primary)
                Text(dayMonthYear(millisFromDate(Date())))
                    .appStyle(.titleMedium)
                    .foregroundStyle(Theme.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Senza prenotazioni da completare il tour indica l'intestazione della Home.
            .modifier(TourTargetIf(target: .homeReview, active: model.pendingReview.isEmpty))
            Button(action: onProfile) {
                Image(systemName: "person.crop.circle").font(.system(size: 26))
            }
            .buttonStyle(.appIcon)
            .tourTarget(.profile)
            .accessibilityLabel("Profilo")
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NUOVE PRENOTAZIONI DA COMPLETARE · \(model.pendingReview.count)")
                .appStyle(.labelSmall)
                .foregroundStyle(Theme.secondary)
                .tourTarget(.homeReview)
            // Altezza limitata con scorrimento interno: con molte prenotazioni o caratteri grandi il blocco non deve
            // mangiarsi la lista degli arrivi, che è il contenuto della Home.
            if model.pendingReview.count <= 3 {
                pendingRows
            } else {
                ScrollView { pendingRows }.frame(height: 200)
            }
        }
    }

    private var pendingRows: some View {
        VStack(spacing: 6) {
            ForEach(model.pendingReview) { res in
                Button { onEditReservation(res.id) } label: { PendingReviewRow(reservation: res) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var arrivals: some View {
        if model.isLoading && model.arrivalsToday.isEmpty {
            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(32)
        } else if model.properties.isEmpty {
            emptyMessage("Configura prima una struttura in Immobili per poter aggiungere ospiti.")
        } else if model.arrivalsToday.isEmpty {
            emptyMessage("Nessun arrivo previsto oggi")
        } else {
            VStack(spacing: Dimens.itemSpacing) {
                ForEach(model.arrivalsToday) { res in
                    Button { onCheckin(res.id, res.propertyId) } label: { ArrivalRow(reservation: res) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .appStyle(.bodyMedium)
            .foregroundStyle(Theme.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(32)
    }

    // Pulsante piccolo (sull'Android un FAB piccolo: quello esteso copriva l'ultima riga della lista).
    private var addGuestButton: some View {
        Button(action: onAddGuest) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: Dimens.iconSmall, weight: .semibold))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 44, height: 44)
                .background(roundedShape(Radius.medium).fill(Theme.primary))
                .softShadow(6, color: Theme.primary)
        }
        .buttonStyle(.appIcon)
        .accessibilityLabel("Aggiungi ospite")
        .padding(Dimens.screenPadding)
        .disabled(model.isCreatingGuest)
    }

    private func onAddGuest() {
        switch model.properties.count {
        case 0: return
        case 1: startNewGuest(model.properties[0].id)
        default:
            chosenPropertyId = model.properties.first?.id
            showPropertyPicker = true
        }
    }

    private func startNewGuest(_ propertyId: String) {
        Task {
            if let created = await model.createManualReservation(propertyId: propertyId) {
                onCheckin(created.id, propertyId)
            }
        }
    }

    private var propertyPicker: some View {
        VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
            Text("Per quale casa?").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            SelectField(
                label: "Casa",
                options: model.properties,
                selected: model.properties.first { $0.id == chosenPropertyId },
                optionLabel: \.name,
                onSelect: { chosenPropertyId = $0.id }
            )
            HStack {
                Spacer()
                Button("Annulla") { showPropertyPicker = false }.buttonStyle(.appText)
                Button("Continua") {
                    showPropertyPicker = false
                    if let id = chosenPropertyId { startNewGuest(id) }
                }
                .buttonStyle(.appPrimary)
                .disabled(chosenPropertyId == nil)
            }
        }
        .padding(Dimens.screenPadding * 2)
        .presentationDetents([.height(240)])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// Registra il bersaglio del tour solo se `active` (l'Android usa `Modifier.then(if …)`).
private struct TourTargetIf: ViewModifier {
    let target: TourTarget
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.tourTarget(target) } else { content }
    }
}

/// Riga di un arrivo: barretta verde (= arrivo), nome, "PIATTAFORMA · esce gg/mm".
struct ArrivalRow: View {
    let reservation: Reservation

    var body: some View {
        HStack(spacing: Dimens.cardPadding) {
            roundedShape(2).fill(Theme.primary).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName ?? "Ospite")
                    .appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text("\(reservation.platform) · esce \(dayMonth(reservation.checkOut))")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(Dimens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .contentShape(Rectangle())
        .accessibilityHint("Apri check-in")
    }
}

/// Riga di una prenotazione da completare: fondo giallo (= da rivedere), nome, "PIATTAFORMA · arriva gg/mm".
struct PendingReviewRow: View {
    let reservation: Reservation

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName ?? "Ospite da confermare")
                    .appStyle(.titleSmall).foregroundStyle(Theme.onSecondaryContainer).lineLimit(2)
                Text("\(reservation.platform) · arriva \(dayMonth(reservation.checkIn))")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(container: Theme.secondaryContainer)
        .contentShape(Rectangle())
        .accessibilityHint("Completa prenotazione")
    }
}

/// "gg/mm" nel fuso del telefono, come `SimpleDateFormat("dd/MM")`.
func dayMonth(_ millis: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "dd/MM"
    return f.string(from: dateFromMillis(millis))
}

/// "gg/mm/aaaa" nel fuso del telefono, come `SimpleDateFormat("dd/MM/yyyy")`.
func dayMonthYear(_ millis: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "dd/MM/yyyy"
    return f.string(from: dateFromMillis(millis))
}
