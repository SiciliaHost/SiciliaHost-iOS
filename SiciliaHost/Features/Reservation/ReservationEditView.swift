import Observation
import SwiftUI

/// Dati della modifica prenotazione (`ReservationEditViewModel`). La prenotazione è sul server; l'importo lordo sta solo
/// sul telefono del proprietario (`FinanceStore`): un collaboratore non lo vede e non lo tocca mai.
@MainActor
@Observable
final class ReservationEditModel {
    private(set) var reservation: Reservation?
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// Solo il proprietario vede e modifica l'importo (sta sul suo telefono).
    private(set) var canEditMoney = false
    /// Importo letto dal telefono al caricamento: al salvataggio si scrive solo se è cambiato.
    private(set) var grossAmount: Double?
    var error: String?

    private let db = FirestoreService()

    /// Serve solo per le scritture locali (nessuna lettura dal server).
    private func finance(_ uid: String) -> FinanceRepository {
        FinanceRepository(store: FinanceStore.forUser(uid), loadReservations: { _ in ([], false) }, site: CloudSiteAmounts())
    }

    func load(_ reservationId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await db.getReservation(reservationId)
            var money = false
            var gross: Double?
            if let res {
                let scope = try await AccessSession.shared.scope()
                if let property = scope.properties.first(where: { $0.id == res.propertyId }), scope.canFinance(property) {
                    money = true
                    gross = await FinanceStore.forUser(scope.uid).read().moneyById()[res.id]?.grossAmount
                }
            }
            // Importo prima della prenotazione: il modulo nasce con la prenotazione e legge l'importo una volta sola.
            canEditMoney = money
            grossAmount = gross
            reservation = res
        } catch {
            reservation = nil
        }
    }

    /// `editedGross`: il valore del campo importo (ignorato se non si è il proprietario).
    func save(_ updated: Reservation, editedGross: Double?) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await db.updateReservation(updated)
            // Il campo è precompilato: si scrive solo se l'importo è cambiato, altrimenti ogni salvataggio lo
            // bloccherebbe come manuale e aggiungerebbe la biancheria.
            if canEditMoney {
                switch ReservationEditLogic.grossChange(initial: grossAmount, edited: editedGross) {
                case .unchanged:
                    break
                case let .set(amount):
                    let uid = try await AccessSession.shared.scope().uid
                    try await finance(uid).saveGross(joinMoney([updated], [:])[0], amount: amount)
                case .clear:
                    let uid = try await AccessSession.shared.scope().uid
                    try await finance(uid).clearGross(updated.id)
                }
            }
            return true
        } catch {
            self.error = "Salvataggio non riuscito. Controlla la connessione e riprova."
            return false
        }
    }

    /// Sul server si cancella solo la prenotazione; spese e importo collegati stanno sul telefono del proprietario e
    /// li toglie lui (qui, o il riallineamento delle Finanze se l'ha cancellata un collaboratore).
    func delete() async -> Bool {
        guard let current = reservation else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await db.deleteReservation(current.id)
            if canEditMoney {
                let uid = try await AccessSession.shared.scope().uid
                try await finance(uid).onReservationDeleted(current.id)
            }
            return true
        } catch {
            self.error = "Eliminazione non riuscita. Controlla la connessione e riprova."
            return false
        }
    }
}

/// Modifica prenotazione (`ReservationEditScreen.kt`): nome, adulti/bambini, date, piattaforma e, solo per il
/// proprietario, importo lordo (vuoto = ancora da definire); "Elimina prenotazione" chiede conferma.
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

    /// `@MainActor`: legge l'importo dal modello (isolato sul main actor).
    @MainActor
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
        _amountText = State(initialValue: ReservationEditLogic.amountText(model.grossAmount))
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
                if model.canEditMoney {
                    AppTextField(
                        label: "Importo lordo (€)", text: $amountText,
                        supporting: "Lascia vuoto se ancora da definire", keyboard: .decimalPad
                    )
                }

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
            // Le spese collegate stanno solo sul telefono del proprietario: il collaboratore non ne tocca (Android `60a8f98`).
            Text(model.canEditMoney
                 ? "Cancella la prenotazione. Le eventuali spese collegate sul tuo telefono vengono tolte dalle Finanze. L'operazione non si può annullare."
                 : "Elimina la prenotazione. L'operazione non si può annullare.")
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
            adults: ReservationEditLogic.parseCount(adultsText),
            children: ReservationEditLogic.parseCount(childrenText)
        )
        let gross = ReservationEditLogic.parseAmount(amountText)
        Task { if await model.save(updated, editedGross: gross) { onDone() } }
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
