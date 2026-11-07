import Foundation

/// Fonte degli importi del sito: separata per poterla finta nei test.
protocol SiteAmountsSource: Sendable {
    func amounts(propertyIds: [String]) async throws -> [SiteBookingAmount]
}

/// `getSiteBookingAmounts` accetta al massimo 20 case per chiamata (e rifiuta tutto se una non è del chiamante).
let siteAmountsChunkSize = 20

/// Importi del sito per `ids`, chiesti a gruppi da `chunkSize` case, un gruppo alla volta, risultati uniti.
/// Un gruppo che fallisce (il sito può non essere aggiornato) viene ignorato: gli altri restano validi.
/// Solo l'annullamento del task sale.
func siteAmountsInChunks(_ ids: [String], chunkSize: Int = siteAmountsChunkSize,
                         fetch: ([String]) async throws -> [SiteBookingAmount]) async throws -> [SiteBookingAmount] {
    var seen = Set<String>()
    let unique = ids.filter { seen.insert($0).inserted }
    let size = max(1, chunkSize)
    var out: [SiteBookingAmount] = []
    var start = 0
    while start < unique.count {
        let chunk = Array(unique[start..<min(start + size, unique.count)])
        start += size
        do {
            out += try await fetch(chunk)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            continue   // gruppo saltato
        }
    }
    return out
}

/// Tutto ciò che la schermata Finanze mostra in un dato istante.
struct FinanceSnapshot {
    var reservations: [FinReservation] = []
    var expenses: [Expense] = []
    var recurring: [RecurringExpense] = []
    var pending: [FinReservation] = []
    var contacts: [Contact] = []
}

let linenAmount = 20.0
let linenDescription = "Spesa fissa biancheria"

/// Unisce server (prenotazioni, importi del sito) e telefono (soldi, spese, contatti). Tutte le scritture sono locali.
struct FinanceRepository {
    let store: FinanceStore
    /// Prenotazioni delle case + `fromCache`: vero se la lettura di Firestore è venuta dalla cache locale (offline) e
    /// quindi potrebbe essere parziale. Con `fromCache` il riallineamento non cancella nulla.
    let loadReservations: @Sendable ([String]) async throws -> (reservations: [Reservation], fromCache: Bool)
    let site: SiteAmountsSource
    let now: @Sendable () -> Int64

    init(store: FinanceStore,
         loadReservations: @escaping @Sendable ([String]) async throws -> (reservations: [Reservation], fromCache: Bool),
         site: SiteAmountsSource,
         now: @escaping @Sendable () -> Int64 = { millisFromDate(Date()) }) {
        self.store = store; self.loadReservations = loadReservations; self.site = site; self.now = now
    }

    /// Carica prenotazioni (server) e soldi (telefono) delle case `properties` e riallinea. Gli errori del server salgono.
    func load(properties: [Property]) async throws -> FinanceSnapshot {
        let ids = properties.map(\.id)
        // Gli id che il telefono conosce PRIMA di leggere il server: solo questi possono risultare orfani (una riga
        // aggiunta durante il caricamento, ad esempio da un import Excel, non va mai cancellata).
        let before = await store.read()
        let candidates = orphanCandidates(before)
        let loaded = try await loadReservations(ids)
        let reservations = loaded.reservations
        let cleanOrphans = !loaded.fromCache
        let siteAmounts = (try? await siteAmountsInChunks(ids) { try await site.amounts(propertyIds: $0) }) ?? []   // a gruppi da 20; il sito può non essere ancora aggiornato
        let current = now()
        let idSet = Set(ids)
        let data = try await store.update {
            reconcile($0, loadedPropertyIds: idSet, reservations: reservations, siteAmounts: siteAmounts, now: current,
                      cleanOrphans: cleanOrphans, orphanCandidates: candidates)
        }
        let joined = joinMoney(reservations, data.moneyById())
        return FinanceSnapshot(
            reservations: joined,
            expenses: data.expenses.filter { idSet.contains($0.propertyId) },
            recurring: data.recurring.filter { idSet.contains($0.propertyId) },
            pending: pendingAmounts(joined, now: current),
            contacts: data.contacts.filter { idSet.contains($0.propertyId) }
        )
    }

    /// Importo lordo + spesa biancheria da 20 € (una sola volta per prenotazione).
    func saveGross(_ r: FinReservation, amount: Double) async throws {
        let t = now()
        try await store.update { d in
            var money = d.moneyById()[r.id] ?? ReservationMoney(reservationId: r.id, propertyId: r.propertyId)
            money.grossAmount = amount
            money.source = ReservationMoney.manual
            var next = d.withMoney(money)
            if !next.expenses.contains(where: { $0.reservationId == r.id }) {
                next = next.withExpense(FinanceRepository.linen(propertyId: r.propertyId, reservationId: r.id, guest: r.guestName, at: t))
            }
            return next
        }
    }

    /// Toglie l'importo di una prenotazione (campo svuotato nella modifica). Nessun effetto se non c'è una riga.
    func clearGross(_ reservationId: String) async throws {
        try await store.update { d in
            guard var m = d.moneyById()[reservationId] else { return d }
            m.grossAmount = nil
            return d.withMoney(m)
        }
    }

    func addExpense(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async throws {
        let t = now()
        try await store.update {
            $0.withExpense(Expense(id: newLocalId(), propertyId: propertyId, description: description, amount: amount,
                                   authorId: "OWNER", timestamp: t, category: category.key))
        }
    }

    func deleteExpense(_ id: String) async throws { try await store.update { $0.withoutExpenses([id]) } }

    func addRecurring(propertyId: String, description: String, amount: Double, category: ExpenseCategory) async throws {
        let month = RecurringExpenses.monthKey(now())
        try await store.update {
            $0.withRecurring(RecurringExpense(id: newLocalId(), propertyId: propertyId, description: description, amount: amount,
                                              startMonth: month, category: category.key))
        }
    }

    func deleteRecurring(_ id: String) async throws { try await store.update { $0.withoutRecurring(id) } }

    /// Alla cancellazione di una prenotazione dalla modifica: tolgo subito spese e importi collegati.
    func onReservationDeleted(_ id: String) async throws {
        try await store.update { d in
            d.withoutExpenses(Set(d.expenses.filter { $0.reservationId == id }.map(\.id))).withoutMoney([id])
        }
    }

    /// Import Excel: soldi/statistiche delle righe, contatti, biancheria per le prenotazioni nuove o completate.
    func applyExcelImport(_ rows: [ExcelMoneyRow], contacts: [Contact], linenFor: Set<String>) async throws {
        let t = now()
        try await store.update { d in
            var next = d
            for row in rows {
                let current = next.moneyById()[row.reservationId]
                // Un importo scritto a mano resta; commissione e statistiche si aggiornano sempre.
                let keepManual = current?.source == ReservationMoney.manual && current?.grossAmount != nil
                next = next.withMoney(ReservationMoney(
                    reservationId: row.reservationId, propertyId: row.propertyId,
                    grossAmount: keepManual ? current?.grossAmount : row.grossAmount,
                    commissionAmount: row.commissionAmount ?? current?.commissionAmount,
                    bookedAt: row.bookedAt ?? current?.bookedAt,
                    travelPurpose: row.travelPurpose ?? current?.travelPurpose,
                    bookingDevice: row.bookingDevice ?? current?.bookingDevice,
                    source: keepManual ? ReservationMoney.manual : ReservationMoney.excel
                ))
                if linenFor.contains(row.reservationId), !next.expenses.contains(where: { $0.reservationId == row.reservationId }) {
                    next = next.withExpense(FinanceRepository.linen(propertyId: row.propertyId, reservationId: row.reservationId, guest: nil, at: t))
                }
            }
            return next.withContacts(contacts)
        }
    }

    func wipe() async { await store.wipe() }

    /// Statica: le chiusure passate allo store non catturano `self`.
    private static func linen(propertyId: String, reservationId: String, guest: String?, at t: Int64) -> Expense {
        let g = (guest ?? "").trimmingCharacters(in: .whitespaces)
        return Expense(id: newLocalId(), propertyId: propertyId, reservationId: reservationId,
                       description: g.isEmpty ? linenDescription : "\(linenDescription) (\(g))",
                       amount: linenAmount, authorId: "SYSTEM", timestamp: t, category: ExpenseCategory.pulizie.key)
    }
}

/// Soldi di una riga dell'Excel Booking, associati all'id della prenotazione condivisa (nuova o completata).
struct ExcelMoneyRow: Equatable, Sendable {
    var reservationId = ""
    var propertyId: String
    var grossAmount: Double?
    var commissionAmount: Double?
    var bookedAt: Int64?
    var travelPurpose: String?
    var bookingDevice: String?
}
