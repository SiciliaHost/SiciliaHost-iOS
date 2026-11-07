import Foundation

extension FinanceData {
    func withExpense(_ e: Expense) -> FinanceData { var d = self; d.expenses.removeAll { $0.id == e.id }; d.expenses.append(e); return d }
    func withoutExpenses(_ ids: Set<String>) -> FinanceData { var d = self; d.expenses.removeAll { ids.contains($0.id) }; return d }
    func withRecurring(_ r: RecurringExpense) -> FinanceData { var d = self; d.recurring.removeAll { $0.id == r.id }; d.recurring.append(r); return d }
    func withoutRecurring(_ id: String) -> FinanceData { var d = self; d.recurring.removeAll { $0.id == id }; return d }
    /// Sostituisce la riga della stessa prenotazione.
    func withMoney(_ m: ReservationMoney) -> FinanceData { var d = self; d.money.removeAll { $0.reservationId == m.reservationId }; d.money.append(m); return d }
    func withoutMoney(_ reservationIds: Set<String>) -> FinanceData { var d = self; d.money.removeAll { reservationIds.contains($0.reservationId) }; return d }
    /// Lo stesso telefono nella stessa casa viene sostituito; senza telefono si scarta.
    func withContacts(_ incoming: [Contact]) -> FinanceData {
        let valid = incoming.filter { !$0.phone.trimmingCharacters(in: .whitespaces).isEmpty }
        let keys = Set(valid.map { "\($0.propertyId)|\($0.phone)" })
        var d = self
        d.contacts.removeAll { keys.contains("\($0.propertyId)|\($0.phone)") }
        d.contacts.append(contentsOf: valid)
        return d
    }
}

/// Id di una spesa o spesa fissa creata sul telefono (non esiste più un id assegnato dal server).
func newLocalId() -> String { UUID().uuidString }
