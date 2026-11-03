import Observation
import SwiftUI

/// Dati della modifica prenotazione (`ReservationEditViewModel`).
@MainActor
@Observable
final class ReservationEditModel {
    private(set) var reservation: Reservation?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isManagedOnCommission = false
    private(set) var canFinance = false
    var error: String?

    private let db = FirestoreService()

    func load(_ reservationId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            reservation = try await db.getReservation(reservationId)
            if let propertyId = reservation?.propertyId {
                let scope = try await AccessSession.shared.scope()
                let property = scope.properties.first { $0.id == propertyId }
                isManagedOnCommission = property?.isManagedOnCommission ?? false
                canFinance = property.map(scope.canFinance) ?? false
            }
        } catch {
            reservation = nil
        }
    }

    func save(_ updated: Reservation) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await db.updateReservation(updated)
            return true
        } catch {
            self.error = "Salvataggio non riuscito. Controlla la connessione e riprova."
            return false
        }
    }

    /// Le spese collegate (biancheria) si cancellano solo con il permesso sulle finanze: per un collaboratore le
    /// spese rimaste orfane le elimina la schermata Finanze.
    func delete() async -> Bool {
        guard let current = reservation else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await db.deleteReservationWithExpenses(
                reservationId: current.id, propertyId: current.propertyId, withExpenses: canFinance
            )
            return true
        } catch {
            self.error = "Eliminazione non riuscita. Controlla la connessione e riprova."
            return false
        }
    }
}

/// Modifica prenotazione (`ReservationEditScreen.kt`): nome, adulti/bambini, date, piattaforma, importo lordo (vuoto =
/// ancora da definire); "Salva" ricalcola i netti; "Elimina prenotazione" chiede conferma.
struct ReservationEditView: View {
    let reservationId: String
    let onBack: () -> Void
    @State private var model = ReservationEditModel()

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Modifica prenotazione", onBack: onBack)
            if let res = model.reservation {
                ReservationEditForm(reservation: res, model: model, onDone: onBack)
                    .id(res.id)
            } else if model.isLoading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Prenotazione non trovata")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reservationId) { await model.load(reservationId) }
    }
}

private struct ReservationEditForm: View {
    let reservation: Reservation
    let model: ReservationEditModel
    let onDone: () -> Void

    @State private var guestName: String
    @State private var adultsText: String
    @State private var childrenText: String
    @State private var checkIn: Int64
    @State private var checkOut: Int64
    @State private var platform: String
    @State private var amountText: String
    @State private var picking: DateTarget?
    @State private var showDeleteConfirm = false

    private enum DateTarget: Identifiable {
        case checkIn, checkOut
        var id: Self { self }
    }

    init(reservation: Reservation, model: ReservationEditModel, onDone: @escaping () -> Void) {
        self.reservation = reservation
        self.model = model
        self.onDone = onDone
        _guestName = State(initialValue: reservation.guestName ?? "")
        _adultsText = State(initialValue: reservation.adults > 0 ? String(reservation.adults) : "")
        _childrenText = State(initialValue: reservation.children > 0 ? String(reservation.children) : "")
        _checkIn = State(initialValue: reservation.checkIn)
        _checkOut = State(initialValue: reservation.checkOut)
        _platform = State(initialValue: reservation.platform)
        _amountText = State(initialValue: ReservationEditLogic.amountText(reservation.grossAmount))
    }

    var body: some View {
        // Scorre: con caratteri grandi o tastiera aperta i campi in fondo devono restare raggiungibili.
        ScrollView {
            VStack(spacing: 12) {
                AppTextField(label: "Nome ospite", text: $guestName, capitalization: .words)
                HStack(spacing: 12) {
                    AppTextField(label: "Adulti", text: digits($adultsText), keyboard: .numberPad)
                    AppTextField(label: "Bambini", text: digits($childrenText), keyboard: .numberPad)
                }
                AppDateField(label: "Check-in", text: dayMonthYear(checkIn)) { picking = .checkIn }
                AppDateField(label: "Check-out", text: dayMonthYear(checkOut)) { picking = .checkOut }
                SelectField(
                    label: "Piattaforma",
                    options: platformOptions,
                    selected: platform,
                    optionLabel: { $0 },
                    onSelect: { platform = $0 }
                )
                AppTextField(
                    label: "Importo lordo (€)", text: $amountText,
                    supporting: "Lascia vuoto se ancora da definire", keyboard: .decimalPad
                )

                Button("Salva", action: save)
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isSaving)
                Button("Elimina prenotazione") { showDeleteConfirm = true }
                    .buttonStyle(.appText(color: Theme.error))
                    .frame(maxWidth: .infinity)
                    .disabled(model.isSaving)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $picking) { target in
            DayPickerSheet(
                title: target == .checkIn ? "Check-in" : "Check-out",
                initial: target == .checkIn ? checkIn : checkOut,
                onPick: { millis in
                    if target == .checkIn { checkIn = millis } else { checkOut = millis }
                }
            )
        }
        .confirmationDialog("Eliminare questa prenotazione?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                Task { if await model.delete() { onDone() } }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'operazione è definitiva e cancella anche eventuali spese collegate (es. biancheria).")
        }
        .alert("Operazione non riuscita", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }

    /// Una piattaforma sconosciuta già salvata resta selezionabile (l'Android la mostra nel campo).
    private var platformOptions: [String] {
        ReservationEditLogic.platforms.contains(platform) ? ReservationEditLogic.platforms : ReservationEditLogic.platforms + [platform]
    }

    private func digits(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = ReservationEditLogic.digitsOnly($0) })
    }

    private func save() {
        let updated = ReservationEditLogic.applyEdit(
            to: reservation,
            guestName: guestName,
            checkIn: checkIn,
            checkOut: checkOut,
            platform: platform,
            grossAmount: ReservationEditLogic.parseAmount(amountText),
            adults: ReservationEditLogic.parseCount(adultsText),
            children: ReservationEditLogic.parseCount(childrenText),
            isManagedOnCommission: model.isManagedOnCommission
        )
        Task { if await model.save(updated) { onDone() } }
    }
}

/// Selettore di un giorno (calendario grafico) con "Annulla" / "OK".
struct DayPickerSheet: View {
    let title: String
    let initial: Int64
    let onPick: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(title: String, initial: Int64, onPick: @escaping (Int64) -> Void) {
        self.title = title
        self.initial = initial
        self.onPick = onPick
        _date = State(initialValue: dateFromMillis(initial))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
                Spacer()
                Text(title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                Spacer()
                Button("OK") {
                    // Giorno invariato = millisecondi invariati (una prenotazione manuale a mezzanotte locale non
                    // viene spostata alla mezzanotte UTC solo perché si è aperto il selettore).
                    if !Calendar.current.isDate(date, inSameDayAs: dateFromMillis(initial)) {
                        onPick(ReservationEditLogic.pickedDayMillis(date))
                    }
                    dismiss()
                }
                .buttonStyle(.appText)
            }
            DatePicker(title, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.primary)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .labelsHidden()
        }
        .padding(Dimens.screenPadding)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}
