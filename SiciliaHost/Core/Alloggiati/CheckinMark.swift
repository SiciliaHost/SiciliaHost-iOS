import Foundation

/// L'unica traccia del check-in sul server: campo `checkin` di `reservations/{id}`. Dice ai membri della casa che le schede
/// sono già state inviate (e quante), senza nomi né documenti. Non è un campo di `Reservation`: si legge a parte, così un
/// salvataggio della prenotazione non lo riscrive mai.
struct CheckinMark: Equatable, Sendable {
    let sentAt: Int64
    let guests: Int
    let by: String

    static func parse(_ value: Any?) -> CheckinMark? {
        guard let map = value as? [String: Any], let sentAt = (map["sentAt"] as? NSNumber)?.int64Value else { return nil }
        return CheckinMark(sentAt: sentAt, guests: (map["guests"] as? NSNumber)?.intValue ?? 0, by: map["by"] as? String ?? "")
    }
}
