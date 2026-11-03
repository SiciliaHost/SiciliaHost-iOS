import Foundation

// Logica pura di Home (`DashboardScreen.kt`), Agenda (`CalendarScreen.kt`) e modifica prenotazione
// (`ReservationEditScreen.kt`). Il "giorno" è sempre quello del calendario del telefono, come `Calendar.getInstance()`
// dell'Android: le prenotazioni iCal sono a mezzanotte UTC e quelle manuali a mezzanotte locale, ed entrambe cadono
// nello stesso giorno di calendario in Italia.

/// Righe della griglia del mese: sempre 7 celle per riga, `nil` dove non cade un giorno del mese. Le settimane finali
/// completamente vuote vengono scartate. `firstDayOfWeek` è 0 = domenica … 6 = sabato (`Calendar.DAY_OF_WEEK - 1`).
func monthGridRows(daysInMonth: Int, firstDayOfWeek: Int) -> [[Int?]] {
    let cells: [Int?] = (0 ..< 42).map { index in
        let day = index - firstDayOfWeek + 1
        return (1 ... daysInMonth).contains(day) ? day : nil
    }
    var rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    while let last = rows.last, last.allSatisfy({ $0 == nil }) { rows.removeLast() }
    return rows
}

enum AgendaLogic {
    /// Intestazioni della griglia: la settimana parte da domenica, come l'Android.
    static let weekdayHeaders = ["Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"]

    static func isSameDay(_ a: Int64, _ b: Int64, calendar: Calendar = .current) -> Bool {
        calendar.isDate(dateFromMillis(a), inSameDayAs: dateFromMillis(b))
    }

    /// Mezzanotte locale del giorno di `millis`.
    static func startOfDay(_ millis: Int64, calendar: Calendar = .current) -> Int64 {
        millisFromDate(calendar.startOfDay(for: dateFromMillis(millis)))
    }

    /// Arrivi di oggi: check-in nel giorno locale di `now` (`[mezzanotte, mezzanotte + 24 h)`, come l'Android).
    static func arrivalsToday(_ reservations: [Reservation], now: Int64, calendar: Calendar = .current) -> [Reservation] {
        let today = startOfDay(now, calendar: calendar)
        let tomorrow = today + 86_400_000
        return reservations.filter { $0.checkIn >= today && $0.checkIn < tomorrow }
    }

    static func pendingReview(_ reservations: [Reservation]) -> [Reservation] {
        reservations.filter(\.needsReview)
    }

    /// Prenotazione manuale vuota (oggi → domani, mezzanotte locale) creata da "Aggiungi ospite" per aprire il check-in.
    static func newManualReservation(propertyId: String, now: Int64, calendar: Calendar = .current) -> Reservation {
        let today = startOfDay(now, calendar: calendar)
        return Reservation(propertyId: propertyId, checkIn: today, checkOut: today + 86_400_000, platform: "MANUAL")
    }

    /// Check-in e check-out che cadono nel giorno `day`.
    static func events(on day: Int64, in reservations: [Reservation], calendar: Calendar = .current) -> [Reservation] {
        reservations.filter { isSameDay($0.checkIn, day, calendar: calendar) || isSameDay($0.checkOut, day, calendar: calendar) }
    }

    /// Giorni del mese con almeno un arrivo / una partenza.
    struct DayMarks: Equatable {
        var checkIns = false
        var checkOuts = false
        var hasEvent: Bool { checkIns || checkOuts }
    }

    static func marks(on day: Int64, in reservations: [Reservation], calendar: Calendar = .current) -> DayMarks {
        DayMarks(
            checkIns: reservations.contains { isSameDay($0.checkIn, day, calendar: calendar) },
            checkOuts: reservations.contains { isSameDay($0.checkOut, day, calendar: calendar) }
        )
    }

    /// Sottotitolo di una riga dell'Agenda: "Casa · PIATTAFORMA · N pers." (persone solo se note).
    static func rowSubtitle(_ reservation: Reservation, propertyName: String) -> String {
        let guests = reservation.adults + reservation.children
        return guests > 0
            ? "\(propertyName) · \(reservation.platform) · \(guests) pers."
            : "\(propertyName) · \(reservation.platform)"
    }
}

// MARK: Modifica prenotazione

enum ReservationEditLogic {
    static let platforms = ["AIRBNB", "BOOKING", "MANUAL"]

    /// Importo scritto a mano: la virgola vale come punto; testo vuoto o non numerico = importo da definire (`nil`).
    static func parseAmount(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// Campo numerico di adulti/bambini: solo cifre; vuoto = 0.
    static func digitsOnly(_ text: String) -> String { text.filter(\.isASCII).filter(\.isNumber) }

    static func parseCount(_ text: String) -> Int { Int(digitsOnly(text)) ?? 0 }

    /// Testo iniziale di un importo: `toString()` di Kotlin mostra sempre i decimali ("120.0"); qui si toglie lo zero
    /// inutile ("120") ma si tiene il punto, come l'Android, per i decimali veri.
    static func amountText(_ amount: Double?) -> String {
        guard let amount else { return "" }
        if amount == amount.rounded() && abs(amount) < 1e15 { return String(Int64(amount)) }
        return String(amount)
    }

    /// La prenotazione salvata da "Salva" (`ReservationEditViewModel.save`): nome vuoto = nessun nome, netti ricalcolati
    /// dal lordo con il regime della casa, `needsReview` finché manca il lordo.
    static func applyEdit(
        to current: Reservation,
        guestName: String,
        checkIn: Int64,
        checkOut: Int64,
        platform: String,
        grossAmount: Double?,
        adults: Int,
        children: Int,
        isManagedOnCommission: Bool
    ) -> Reservation {
        let calc = grossAmount.map {
            FinancialCalculator.calculate(grossAmount: $0, platform: platform, isManagedOnCommission: isManagedOnCommission)
        }
        var updated = current
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.guestName = trimmed.isEmpty ? nil : trimmed
        updated.checkIn = checkIn
        updated.checkOut = checkOut
        updated.platform = platform
        updated.grossAmount = grossAmount
        updated.netAmountOwner = calc?.netAmountOwner
        updated.netAmountAdmin = calc?.netAmountAdmin
        updated.adults = adults
        updated.children = children
        updated.needsReview = grossAmount == nil
        return updated
    }

    /// Data scelta nel selettore → millisecondi da salvare. Il selettore dell'Android restituisce la mezzanotte UTC del
    /// giorno scelto (come l'import iCal): qui si fa lo stesso, a partire dal giorno di calendario locale scelto.
    static func pickedDayMillis(_ date: Date, calendar: Calendar = .current) -> Int64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return utcMillis(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}
