import Foundation
import Observation

/// Chiave di `UserDefaults` dell'avviso «solo su questo telefono» già chiuso (globale: si usa anche nel valore iniziale).
private let financeNoticeSeenKey = "finance_local_notice_seen"

/// Dati e azioni delle Finanze (`FinanceViewModel` dell'Android). Soldi, spese e contatti stanno solo su questo telefono.
@MainActor
@Observable
final class FinanceModel {
    private(set) var properties: [Property] = []
    private(set) var reservations: [FinReservation] = []
    private(set) var expenses: [Expense] = []
    private(set) var recurring: [RecurringExpense] = []
    /// Importi da inserire (prenotazioni recenti o future senza lordo).
    private(set) var pending: [FinReservation] = []
    private(set) var importCounts: [String: BookingImportCounts] = [:]
    private(set) var isLoading = false
    private(set) var loadFailed = false
    /// Il file del telefono era illeggibile ed è stato messo da parte: lo si dice.
    private(set) var storeWasCorrupt = false
    /// «Questi dati restano solo su questo telefono»: si mostra finché non lo si chiude.
    private(set) var showLocalNotice = !UserDefaults.standard.bool(forKey: financeNoticeSeenKey)
    var message: String?

    // Filtri (restano cambiando sezione).
    var period: FinancePeriod = .last12Months
    var propertyFilter: String?

    private let db: FirestoreService?

    init(db: FirestoreService? = FirestoreService(),
         preview: (properties: [Property], reservations: [FinReservation], expenses: [Expense], recurring: [RecurringExpense])? = nil) {
        self.db = db
        if let preview {
            properties = preview.properties
            reservations = preview.reservations
            expenses = preview.expenses
            recurring = preview.recurring
            pending = pendingAmounts(preview.reservations, now: millisFromDate(Date()))
        }
    }

    /// Mai in cache: l'account può cambiare (logout/login) mentre il modello vive. Lo store è condiviso per uid
    /// (`FinanceStore.forUser`), quindi ricrearlo qui è a costo zero e sicuro.
    private func repository() async throws -> FinanceRepository? {
        guard let db else { return nil }
        let scope = try await AccessSession.shared.scope()
        return FinanceRepository(
            store: FinanceStore.forUser(scope.uid),
            loadReservations: { ids in try await db.getReservationsReportingCache(propertyIds: ids) },
            site: CloudSiteAmounts()
        )
    }

    func load() async {
        guard let db else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let scope = try await AccessSession.shared.scope()
            let houses = scope.financeProperties          // solo le case di cui sei OWNER
            properties = houses
            if let f = propertyFilter, !houses.contains(where: { $0.id == f }) { propertyFilter = nil }
            importCounts = (try? await db.getBookingImportCounts(houses.map(\.id))) ?? [:]
            guard let repo = try await repository() else { return }
            let snap = try await repo.load(properties: houses)
            reservations = snap.reservations
            expenses = snap.expenses
            recurring = snap.recurring
            pending = snap.pending
            storeWasCorrupt = await repo.store.wasCorrupt
        } catch {
            loadFailed = true
            message = "Caricamento delle finanze non riuscito. Controlla la connessione."
        }
    }

    func dismissLocalNotice() {
        UserDefaults.standard.set(true, forKey: financeNoticeSeenKey)
        showLocalNotice = false
    }

    func view(now: Int64 = millisFromDate(Date())) -> FinanceViewData {
        buildFinanceView(allReservations: reservations, allExpenses: expenses, properties: properties,
                         importCounts: importCounts, period: period, propertyId: propertyFilter, now: now)
    }

    func propertyName(_ id: String) -> String { properties.first { $0.id == id }?.name ?? id }

    func saveGross(_ r: FinReservation, amount: Double) async {
        await run("Salvataggio dell'importo non riuscito.") { try await $0.saveGross(r, amount: amount) }
    }

    func addExpense(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async {
        await run("Salvataggio della spesa non riuscito.") {
            try await $0.addExpense(propertyId: propertyId, description: description, amount: amount, category: category)
        }
    }

    func addRecurring(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async {
        await run("Salvataggio della spesa fissa non riuscito.") {
            try await $0.addRecurring(propertyId: propertyId, description: description, amount: amount, category: category)
        }
    }

    func deleteRecurring(_ id: String) async { await run("Eliminazione non riuscita.") { try await $0.deleteRecurring(id) } }

    func deleteExpense(_ e: Expense) async { await run("Eliminazione non riuscita.") { try await $0.deleteExpense(e.id) } }

    /// Scrittura locale, poi ricarica (spese fisse, importi da inserire e totali si ricalcolano).
    private func run(_ failure: String, _ block: (FinanceRepository) async throws -> Void) async {
        do {
            guard let repo = try await repository() else { return }
            try await block(repo)
            await load()
        } catch {
            message = failure
        }
    }
}

/// Importi del sito dalla callable `getSiteBookingAmounts` (risponde solo al proprietario).
struct CloudSiteAmounts: SiteAmountsSource {
    func amounts(propertyIds: [String]) async throws -> [SiteBookingAmount] {
        try await HostFunctionsService().getSiteBookingAmounts(propertyIds: propertyIds)
    }
}
