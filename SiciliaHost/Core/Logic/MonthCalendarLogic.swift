import Foundation

/// Logica PURA del calendario a mesi dell'Agenda (`MonthCalendarLogic.kt`): celle con prezzo, prenotazioni come barre.
/// Niente SwiftUI né Firebase, così si prova nei test. Le barre vanno da metà della cella d'ingresso a metà di quella
/// d'uscita, come sul calendario di Airbnb: due soggiorni di fila si toccano nella cella del cambio.
/// I giorni sono «giorni dal 1970» a Roma (`romeDay`): i documenti iCal sono a mezzanotte UTC, quelli scritti a mano a
/// mezzanotte di Roma.
enum MonthCalendar {
    private static let rome: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let monthNames = [
        "Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno",
        "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre",
    ]
    static let weekdayHeaders = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]

    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        Int(utcMillis(year: year, month: month, day: day) / millisPerDay)
    }

    /// Giorno di calendario a Roma di un istante.
    static func romeDay(_ epochMs: Int64) -> Int {
        let c = rome.dateComponents([.year, .month, .day], from: dateFromMillis(epochMs))
        return epochDay(year: c.year!, month: c.month!, day: c.day!)
    }

    /// `aaaa-mm-gg` di un giorno dal 1970, come le date ISO di tariffe e promozioni.
    static func iso(_ epochDay: Int) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(epochDay) * 86_400))
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        let first = Date(timeIntervalSince1970: Double(epochDay(year: year, month: month, day: 1)) * 86_400)
        return utc.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// I blocchi di date del sito sono prenotazioni MANUAL con questo prefisso nell'id (vedi `reservationModel.ts`).
    static func isBlock(_ reservation: Reservation) -> Bool { reservation.id.hasPrefix("blocco-") }

    /// Settimane (lunedì-domenica) del mese: sempre 7 celle per riga, nil fuori dal mese; niente righe finali vuote.
    static func monthWeeks(year: Int, month: Int) -> [[Int?]] {
        let first = epochDay(year: year, month: month, day: 1)
        let count = daysInMonth(year: year, month: month)
        let lead = (first + 3) % 7 // il 1° gennaio 1970 era un giovedì; lunedì = 0
        let cells: [Int?] = (0..<42).map { i in
            let offset = i - lead
            return (0..<count).contains(offset) ? first + offset : nil
        }
        var rows = stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<($0 + 7)]) }
        while let last = rows.last, last.allSatisfy({ $0 == nil }) { rows.removeLast() }
        return rows
    }

    /// Un pezzo di barra in una riga-settimana. `x0`/`x1` sono in unità di colonna (0 = bordo sinistro del lunedì, 7 =
    /// bordo destro della domenica); `roundStart`/`roundEnd` dicono se il soggiorno comincia/finisce in questa riga
    /// (estremo tondo) o continua oltre (estremo dritto); `lane` è la corsia, 0 = la prima.
    struct BarSegment: Identifiable, Equatable {
        let reservation: Reservation
        let x0: Double
        let x1: Double
        let roundStart: Bool
        let roundEnd: Bool
        let lane: Int
        var id: String { "\(reservation.id)|\(x0)" }
    }

    /// Le barre di una riga-settimana. Si disegnano solo sulle colonne che cadono nel mese (le altre sono celle vuote): un
    /// soggiorno che attraversa due mesi continua nella riga del mese dopo. Le sovrapposizioni vere (doppie prenotazioni)
    /// vanno su corsie diverse, così restano visibili.
    static func weekBars(week: [Int?], reservations: [Reservation]) -> [BarSegment] {
        guard let first = week.firstIndex(where: { $0 != nil }),
              let last = week.lastIndex(where: { $0 != nil }),
              let firstDay = week[first] else { return [] }
        let columnZero = firstDay - first
        let rowStart = Double(first)
        let rowEnd = Double(last + 1)

        struct Raw {
            let reservation: Reservation
            let x0: Double
            let x1: Double
            let roundStart: Bool
            let roundEnd: Bool
        }

        let raw: [Raw] = reservations.compactMap { r in
            let inDay = romeDay(r.checkIn), outDay = romeDay(r.checkOut)
            guard outDay > inDay else { return nil }
            let start = Double(inDay - columnZero) + 0.5
            let end = Double(outDay - columnZero) + 0.5
            let x0 = max(start, rowStart), x1 = min(end, rowEnd)
            guard x1 > x0 else { return nil }
            return Raw(reservation: r, x0: x0, x1: x1, roundStart: start >= rowStart, roundEnd: end <= rowEnd)
        }
        .sorted { a, b in
            if a.x0 != b.x0 { return a.x0 < b.x0 }
            if a.reservation.checkIn != b.reservation.checkIn { return a.reservation.checkIn < b.reservation.checkIn }
            return a.reservation.id < b.reservation.id
        }

        var laneEnds: [Double] = []
        return raw.map { s in
            let lane: Int
            if let free = laneEnds.firstIndex(where: { $0 <= s.x0 }) {
                lane = free
                laneEnds[free] = s.x1
            } else {
                lane = laneEnds.count
                laneEnds.append(s.x1)
            }
            return BarSegment(reservation: s.reservation, x0: s.x0, x1: s.x1, roundStart: s.roundStart, roundEnd: s.roundEnd, lane: lane)
        }
    }

    /// Quante corsie servono alla riga (almeno una: l'altezza della riga cresce solo con le sovrapposizioni).
    static func laneCount(_ bars: [BarSegment]) -> Int { (bars.map(\.lane).max() ?? 0) + 1 }

    /// I giorni toccati da almeno una barra (ingresso, notti e uscita): lì il prezzo non si mostra, ci sta sopra la barra.
    static func daysTouched(week: [Int?], bars: [BarSegment]) -> Set<Int> {
        var touched = Set<Int>()
        for bar in bars {
            let from = min(max(Int(bar.x0.rounded(.down)), 0), 6)
            let to = min(max(Int(bar.x1.rounded(.up)) - 1, 0), 6)
            guard from <= to else { continue }
            for column in from...to { if let day = week[column] { touched.insert(day) } }
        }
        return touched
    }

    /// Il testo della barra: «Nome + N» con N = gli altri ospiti; senza nome, la piattaforma; per i blocchi «Date bloccate».
    static func stayLabel(_ reservation: Reservation) -> String {
        let block = isBlock(reservation)
        let typed = reservation.guestName?.trimmed ?? ""
        let name: String
        if !typed.isEmpty {
            name = typed
        } else if block {
            name = "Date bloccate"
        } else if reservation.platform == "AIRBNB" {
            name = "Airbnb"
        } else if reservation.platform == "BOOKING" {
            name = "Booking"
        } else {
            name = "Ospite"
        }
        let others = reservation.adults + reservation.children - 1
        return (!block && others > 0) ? "\(name) + \(others)" : name
    }

    /// La lettera nel cerchietto della barra.
    static func stayInitial(_ reservation: Reservation) -> String {
        let typed = reservation.guestName?.trimmed ?? ""
        let source = typed.isEmpty ? (reservation.platform.isEmpty ? "?" : reservation.platform) : typed
        return String(source.prefix(1)).uppercased()
    }

    /// Il prezzo della notte: la tariffa per date che la copre, altrimenti il prezzo base; nil se non si conosce.
    static func nightlyPrice(day: Int, base: Double?, rates: [SeasonalRateEntry]) -> Double? {
        let key = iso(day)
        return rates.first { key >= $0.startDate && key <= $0.endDate }?.pricePerNight ?? base
    }

    /// «40% di sconto» (la promozione in percentuale più alta) o «−10 € a notte»; nil senza promozioni quel giorno.
    static func discountLabel(day: Int, promotions: [PromoEntry]) -> String? {
        let key = iso(day)
        let active = promotions.filter { key >= $0.startDate && key <= $0.endDate }
        guard !active.isEmpty else { return nil }
        if let percent = active.filter({ $0.discountType == discountPercentage }).max(by: { $0.discountValue < $1.discountValue }) {
            return "\(number(percent.discountValue))% di sconto"
        }
        guard let fixed = active.max(by: { $0.discountValue < $1.discountValue }) else { return nil }
        return "−\(number(fixed.discountValue)) € a notte"
    }

    /// «100 €», «166,50 €».
    static func formatEuro(_ amount: Double) -> String { "\(number(amount)) €" }

    private static func number(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int64(value))
            : String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
