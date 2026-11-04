import Foundation

/// Promemoria mensile per re-importare l'export Excel di Booking (`BookingExcelReminderWorker.kt`). Sull'Android è un lavoro
/// periodico di 30 giorni; iOS non garantisce nessun orario in sfondo, quindi la notifica è LOCALE e pianificata a ogni
/// apertura dell'app (e a ogni giro in sfondo): scatta alle 10:00 del primo giorno utile dopo 30 giorni dall'ultimo import
/// (subito il prossimo giorno se è già scaduto o se non c'è mai stato un import) e si ripianifica se l'host importa nel frattempo.
enum ExcelReminder {
    static let intervalDays = 30
    static let hour = 10
    static let identifierPrefix = "excel-reminder-"

    static func identifier(_ propertyId: String) -> String { identifierPrefix + propertyId }

    /// Solo le case con un URL iCal Booking configurato (segnale che usano Booking).
    static func wantsReminder(_ property: Property) -> Bool {
        !(property.icalUrlBooking ?? "").trimmed.isEmpty
    }

    /// Quando far scattare la notifica. `lastImportAt` = `lastBookingExcelImportAt` della casa (epoch ms), nil se mai importato.
    static func fireDate(lastImportAt: Int64?, now: Date, calendar: Calendar = .current) -> Date {
        let due = lastImportAt.map { dateFromMillis($0).addingTimeInterval(Double(intervalDays) * 86_400) } ?? now
        let base = max(due, now)
        return calendar.nextDate(
            after: base, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime
        ) ?? base.addingTimeInterval(86_400)
    }

    static func body(for property: Property) -> String {
        let name = property.name.trimmed.isEmpty ? "La tua casa" : property.name
        return "\(name): importa il nuovo export Excel per avere i resoconti aggiornati."
    }

    static let title = "Aggiorna le prenotazioni Booking"
}
