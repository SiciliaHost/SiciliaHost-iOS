import Foundation

// Le date delle prenotazioni sono mezzanotti UTC in millisecondi: tutti i calcoli per mese/settimana sono in UTC,
// come sull'Android, per non spostare una prenotazione di giorno a seconda del fuso del telefono.

let millisPerDay: Int64 = 24 * 60 * 60 * 1000

/// Calendario gregoriano in UTC, lunedì non è il primo giorno ma `weekday` segue la convenzione Java: domenica = 1.
let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func dateFromMillis(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

func millisFromDate(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

/// Mezzanotte UTC del primo giorno del mese che contiene `millis`.
func startOfMonthUTC(_ millis: Int64) -> Int64 {
    let comps = utcCalendar.dateComponents([.year, .month], from: dateFromMillis(millis))
    return millisFromDate(utcCalendar.date(from: comps)!)
}

/// `millis` spostato di `months` mesi (calendario UTC).
func addMonthsUTC(_ millis: Int64, _ months: Int) -> Int64 {
    millisFromDate(utcCalendar.date(byAdding: .month, value: months, to: dateFromMillis(millis))!)
}

/// Millisecondi UTC di una data civile (ora indicata).
func utcMillis(year: Int, month: Int, day: Int, hour: Int = 0) -> Int64 {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
    return millisFromDate(utcCalendar.date(from: comps)!)
}

/// Mesi abbreviati in italiano, fissi (senza dipendere dai dati del sistema): "gen", "feb", …
let italianShortMonths = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

/// "giu" per il mese di `millis` (UTC).
func shortMonthLabel(_ millis: Int64) -> String {
    italianShortMonths[utcCalendar.component(.month, from: dateFromMillis(millis)) - 1]
}

/// "giu 26" per il mese di `millis` (UTC).
func shortMonthYearLabel(_ millis: Int64) -> String {
    let year = utcCalendar.component(.year, from: dateFromMillis(millis)) % 100
    return "\(shortMonthLabel(millis)) \(String(format: "%02d", year))"
}

/// Intervalli semiaperti [start, end): un checkout lo stesso giorno di un altro checkin non si considera
/// sovrapposizione, coerente con come DTEND funziona in iCal.
func dateRangesOverlap(_ aStart: Int64, _ aEnd: Int64, _ bStart: Int64, _ bEnd: Int64) -> Bool {
    aStart < bEnd && bStart < aEnd
}

/// Ordinamento decrescente per chiave, STABILE (a parità resta l'ordine di partenza), come `sortedByDescending` di Kotlin.
func stableSortedDescending<T, K: Comparable>(_ items: [T], by key: (T) -> K) -> [T] {
    items.enumerated()
        .sorted { lhs, rhs in
            let a = key(lhs.element), b = key(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a > b
        }
        .map(\.element)
}

/// Conteggio dei valori ripetuti, dal più frequente; a parità vince chi è comparso prima.
func topCounts(_ values: [String]) -> [LabelCount] {
    var order: [String] = []
    var counts: [String: Int] = [:]
    for v in values {
        if counts[v] == nil { order.append(v) }
        counts[v, default: 0] += 1
    }
    return stableSortedDescending(order.map { LabelCount(label: $0, count: counts[$0]!) }, by: \.count)
}

struct LabelCount: Equatable, Sendable {
    let label: String
    let count: Int
}
