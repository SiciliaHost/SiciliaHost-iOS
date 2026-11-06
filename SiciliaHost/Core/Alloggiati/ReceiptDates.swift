import Foundation

/// Un giorno di calendario (senza ora né fuso), come `LocalDate`.
struct CalendarDay: Comparable, Hashable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// yyyy-MM-dd (la data della ricevuta).
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { iso }

    /// Il giorno di Roma dell'istante `epochMs`.
    static func rome(_ epochMs: Int64) -> CalendarDay { rome(RomeTime.date(epochMs)) }

    static func rome(_ date: Date) -> CalendarDay {
        let c = RomeTime.calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Mezzanotte di Roma di questo giorno (per il DatePicker, che lavora con il fuso di Roma).
    var romeMidnight: Date {
        RomeTime.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    func adding(days: Int) -> CalendarDay {
        let cal = RomeTime.calendar
        // A mezzogiorno: l'ora legale non sposta mai il giorno.
        let noon = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? romeMidnight
        return CalendarDay.rome(cal.date(byAdding: .day, value: days, to: noon) ?? noon)
    }
}

/// Giorni per cui Alloggiati Web dà la ricevuta: gli ultimi 30 escluso oggi, nel fuso italiano (porta di `ReceiptDates.kt`).
/// Il DatePicker di iOS si imposta con il calendario e il fuso di Roma, quindi non servono le conversioni UTC dell'Android.
enum ReceiptDates {
    static let windowDays = 30

    static func romeToday(now: Int64) -> CalendarDay { CalendarDay.rome(now) }

    static func range(today: CalendarDay) -> ClosedRange<CalendarDay> {
        today.adding(days: -windowDays)...today.adding(days: -1)
    }

    static func isSelectable(_ date: CalendarDay, today: CalendarDay) -> Bool { range(today: today).contains(date) }

    /// Il giorno dell'ultimo invio, se la ricevuta c'è già; altrimenti ieri.
    static func defaultDate(today: CalendarDay, lastSentAt: Int64?) -> CalendarDay {
        if let ms = lastSentAt, case let sent = CalendarDay.rome(ms), isSelectable(sent, today: today) { return sent }
        return today.adding(days: -1)
    }

    /// L'intervallo per il DatePicker: mezzanotti di Roma del primo e dell'ultimo giorno ammesso.
    static func pickerRange(today: CalendarDay) -> ClosedRange<Date> {
        let r = range(today: today)
        return r.lowerBound.romeMidnight...r.upperBound.romeMidnight
    }
}
