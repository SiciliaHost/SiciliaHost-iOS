import Foundation
import Observation

/// Dati e azioni delle Finanze (`FinanceViewModel` in `FinanceScreen.kt`).
@MainActor
@Observable
final class FinanceModel {
    private(set) var properties: [Property] = []
    private(set) var reservations: [Reservation] = []
    private(set) var expenses: [Expense] = []
    private(set) var recurring: [RecurringExpense] = []
    private(set) var importCounts: [String: BookingImportCounts] = [:]
    private(set) var isLoading = false
    /// Solo il super-admin cambia il regime a commissione: quel flag gli dà accesso a finanze e prenotazioni della casa.
    private(set) var isSuperAdmin = false
    var message: String?

    // Filtri (restano cambiando sezione).
    var period: FinancePeriod = .last12Months
    var propertyFilter: String?

    private let db: FirestoreService?

    init(db: FirestoreService? = FirestoreService(),
         preview: (properties: [Property], reservations: [Reservation], expenses: [Expense], recurring: [RecurringExpense])? = nil) {
        self.db = db
        if let preview {
            properties = preview.properties
            reservations = preview.reservations
            expenses = preview.expenses
            recurring = preview.recurring
        }
    }

    func load() async {
        guard let db else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let scope = try await AccessSession.shared.scope()
            isSuperAdmin = scope.isSuperAdmin
            // Case con Finanze accessibili: proprietario/super-admin o collaboratore con FINANCE.
            let houses = scope.financeProperties
            let ids = houses.map(\.id)
            properties = houses
            if let f = propertyFilter, !houses.contains(where: { $0.id == f }) { propertyFilter = nil }
            importCounts = (try? await db.getBookingImportCounts(ids)) ?? [:]
            recurring = try await db.getRecurringExpenses(propertyIds: ids)
            var loaded = try await db.getExpenses(propertyIds: ids)
            // Spese fisse dei mesi mancanti (id deterministici: nessun doppione).
            let due = RecurringExpenses.dueExpenses(
                recurring: recurring, existingExpenseIds: Set(loaded.map(\.id)), now: millisFromDate(Date())
            )
            if !due.isEmpty {
                for e in due { try await db.setExpense(e) }
                loaded = try await db.getExpenses(propertyIds: ids)
            }
            expenses = loaded
            // Le prenotazioni si leggono DOPO le spese: una prenotazione (e la sua spesa) nata tra le due letture non
            // deve far sembrare orfana una spesa valida.
            reservations = try await db.getReservations(propertyIds: ids)
            // Spese rimaste senza prenotazione (cancellata da un collaboratore): le elimina chi ha le finanze.
            let orphans = orphanExpenseIds(loaded, reservationIds: Set(reservations.map(\.id)))
            if !orphans.isEmpty, (try? await db.deleteExpenses(orphans)) != nil {
                let removed = Set(orphans)
                expenses = loaded.filter { !removed.contains($0.id) }
            }
        } catch {
            message = "Caricamento delle finanze non riuscito. Controlla la connessione."
        }
    }

    func view(now: Int64 = millisFromDate(Date())) -> FinanceViewData {
        buildFinanceView(allReservations: reservations, allExpenses: expenses, properties: properties,
                         importCounts: importCounts, period: period, propertyId: propertyFilter, now: now)
    }

    func propertyName(_ id: String) -> String { properties.first { $0.id == id }?.name ?? id }

    func setCommissionMode(_ property: Property, _ value: Bool) async {
        guard let db else { return }
        var updated = property
        updated.isManagedOnCommission = value
        do {
            try await db.updateProperty(updated)
            // Le altre schermate leggono il regime dalla cache di sessione: va riletta.
            await AccessSession.shared.invalidate()
            properties = properties.map { $0.id == updated.id ? updated : $0 }
        } catch {
            message = "Modifica del regime non riuscita."
        }
    }

    func saveGross(_ reservation: Reservation, amount: Double) async {
        guard let db else { return }
        let commission = properties.first { $0.id == reservation.propertyId }?.isManagedOnCommission ?? false
        do {
            try await db.updateReservation(FinanceActions.withGross(reservation, amount: amount, isManagedOnCommission: commission))
            try await db.addExpense(FinanceActions.linenExpense(for: reservation))
            await load()
        } catch {
            message = "Salvataggio dell'importo non riuscito."
        }
    }

    func addExpense(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async {
        guard let db else { return }
        do {
            try await db.addExpense(Expense(propertyId: propertyId, description: description, amount: amount, category: category.key))
            await load()
        } catch {
            message = "Salvataggio della spesa non riuscito."
        }
    }

    func addRecurring(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async {
        guard let db else { return }
        do {
            try await db.addRecurringExpense(RecurringExpense(
                propertyId: propertyId, description: description, amount: amount,
                startMonth: RecurringExpenses.monthKey(millisFromDate(Date())), category: category.key
            ))
            await load()
        } catch {
            message = "Salvataggio della spesa fissa non riuscito."
        }
    }

    func deleteRecurring(_ id: String) async {
        guard let db else { return }
        do {
            try await db.deleteRecurringExpense(id)
            await load()
        } catch {
            message = "Eliminazione non riuscita."
        }
    }

    func deleteExpense(_ expense: Expense) async {
        guard let db else { return }
        do {
            try await db.deleteExpenses([expense.id])
            expenses.removeAll { $0.id == expense.id }
        } catch {
            message = "Eliminazione non riuscita."
        }
    }
}
