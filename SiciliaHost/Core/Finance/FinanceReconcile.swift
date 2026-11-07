import Foundation

/// Importo pagato per una prenotazione diretta del sito; `reservationId` = id della prenotazione condivisa.
struct SiteBookingAmount: Equatable, Sendable {
    let reservationId: String
    let propertyId: String
    let totalPrice: Double
}

/// Le prenotazioni senza importo compaiono in «Importi da inserire» solo se finite da meno di 45 giorni (o future).
let pendingWindowDays: Int64 = 45
private let dayMs: Int64 = 86_400_000

/// Riallinea i dati locali con il server (puro): 1) importi delle prenotazioni del sito (mai sopra uno scritto a mano);
/// 2) spese fisse mancanti (id deterministici); 3) orfani, SOLO per le case caricate, con l'elenco completo e
/// SOLO tra le righe che c'erano PRIMA della lettura del server (`orphanCandidates`): una riga scritta nel frattempo
/// (es. un import Excel) non si tocca. Con `cleanOrphans == false` (lettura venuta dalla cache di Firestore, quindi
/// forse parziale o vuota) non si cancella nulla.
func reconcile(_ data: FinanceData, loadedPropertyIds: Set<String>, reservations: [Reservation],
               siteAmounts: [SiteBookingAmount], now: Int64,
               cleanOrphans: Bool = true, orphanCandidates: Set<String> = []) -> FinanceData {
    let reservationIds = Set(reservations.map(\.id))
    var next = data

    let known = next.moneyById()
    for amount in siteAmounts {
        guard reservationIds.contains(amount.reservationId), loadedPropertyIds.contains(amount.propertyId) else { continue }
        let current = known[amount.reservationId]
        if let current, current.source != ReservationMoney.site { continue }
        var money = current ?? ReservationMoney(reservationId: amount.reservationId, propertyId: amount.propertyId)
        money.grossAmount = amount.totalPrice
        money.source = ReservationMoney.site
        next = next.withMoney(money)
    }

    let due = RecurringExpenses.dueExpenses(recurring: next.recurring, existingExpenseIds: Set(next.expenses.map(\.id)), now: now)
    for e in due { next = next.withExpense(e) }

    guard cleanOrphans else { return next }
    let candidateExpenses = next.expenses.filter { e in
        guard loadedPropertyIds.contains(e.propertyId), let rid = e.reservationId else { return false }
        return orphanCandidates.contains(rid)
    }
    next = next.withoutExpenses(Set(orphanExpenseIds(candidateExpenses, reservationIds: reservationIds)))
    let orphanMoney = Set(next.money
        .filter { loadedPropertyIds.contains($0.propertyId) && !reservationIds.contains($0.reservationId) && orphanCandidates.contains($0.reservationId) }
        .map(\.reservationId))
    return next.withoutMoney(orphanMoney)
}

/// Id di prenotazione a cui sono legate righe locali (soldi o spese): da prendere PRIMA di leggere il server.
func orphanCandidates(_ data: FinanceData) -> Set<String> {
    Set(data.money.map(\.reservationId))
        .union(data.expenses.compactMap { e in e.reservationId.flatMap { $0.isEmpty ? nil : $0 } })
}

/// Prenotazioni senza lordo da completare: niente blocchi di date, niente stagioni vecchie.
func pendingAmounts(_ reservations: [FinReservation], now: Int64) -> [FinReservation] {
    reservations
        .filter { $0.grossAmount == nil && !$0.id.hasPrefix("blocco-") && $0.checkOut >= now - pendingWindowDays * dayMs }
        .sorted { $0.checkIn < $1.checkIn }
}
