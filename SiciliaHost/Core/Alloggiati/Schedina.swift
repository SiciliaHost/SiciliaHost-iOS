import Foundation

/// Fuso e calendario italiani per il check-in: le date si dichiarano con il giorno di Roma. Calendario gregoriano esplicito
/// (un telefono impostato sul calendario buddista scriverebbe l'anno 2569).
enum RomeTime {
    static let zone = TimeZone(identifier: "Europe/Rome")!

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = Locale(identifier: "it_IT")
        return cal
    }

    static func date(_ epochMs: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000) }

    static func format(_ pattern: String, _ epochMs: Int64) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = zone
        f.dateFormat = pattern
        return f.string(from: date(epochMs))
    }
}

/// La riga a larghezza fissa (168 caratteri) di una schedina Alloggiati (porta di `Schedina.kt`).
enum Schedina {
    private static let maxNights = 30

    /// dd/MM/yyyy nel fuso italiano: l'arrivo si dichiara con la data locale.
    static func italianDate(_ epochMs: Int64) -> String { RomeTime.format("dd/MM/yyyy", epochMs) }

    /// yyyy-MM-dd nel fuso italiano (data della ricevuta).
    static func romeIsoDate(_ epochMs: Int64) -> String { RomeTime.format("yyyy-MM-dd", epochMs) }

    /// I caratteri di controllo (CR, LF, tab...) romperebbero il tracciato: diventano spazi. Si lavora sugli scalari
    /// Unicode (in Swift "\r\n" è un solo `Character`: uno spazio solo invece dei due dell'Android).
    static func clean(_ value: String?) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in (value ?? "").unicodeScalars {
            scalars.append(CharacterSet.controlCharacters.contains(scalar) ? " " : scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    private static func fit(_ value: String?, _ length: Int) -> String {
        String(clean(value).prefix(length)).padding(toLength: length, withPad: " ", startingAt: 0)
    }

    /// Notti = giorni di calendario di Roma: le prenotazioni stanno a mezzanotte UTC (iCal) o di Roma (manuali) e l'ora
    /// legale rende i soggiorni di 23 o 25 ore. Meno di una notte = date non valide.
    static func nights(checkIn: Int64, checkOut: Int64) throws -> Int {
        let cal = RomeTime.calendar
        let from = cal.startOfDay(for: RomeTime.date(checkIn))
        let to = cal.startOfDay(for: RomeTime.date(checkOut))
        let raw = cal.dateComponents([.day], from: from, to: to).day ?? 0
        guard raw >= 1 else { throw AlloggiatiError.refused("Date del soggiorno non valide: controlla arrivo e partenza") }
        return min(raw, maxNights)
    }

    static func row(_ r: GuestRecord, checkIn: Int64, checkOut: Int64) throws -> String {
        let n = try nights(checkIn: checkIn, checkOut: checkOut)
        let nightsText = n < 10 ? "0\(n)" : "\(n)"
        return fit(r.tipoAlloggiato, 2)           //   0-1    (2)
            + italianDate(checkIn)                //   2-11   (10)
            + nightsText                          //  12-13   (2)
            + fit(r.cognome, 50)                  //  14-63   (50)
            + fit(r.nome, 30)                     //  64-93   (30)
            + fit(r.sesso, 1)                     //  94      (1)
            + fit(r.dataNascita, 10)              //  95-104  (10)
            + fit(r.comuneNascitaCode, 9)         // 105-113  (9)
            + fit(r.provinciaNascita, 2)          // 114-115  (2)
            + fit(r.statoNascitaCode, 9)          // 116-124  (9)
            + fit(r.cittadinanzaCode, 9)          // 125-133  (9)
            + fit(r.tipoDocumentoCode, 5)         // 134-138  (5)
            + fit(r.numeroDocumento, 20)          // 139-158  (20)
            + fit(r.luogoRilascioCode, 9)         // 159-167  (9)
    }

    /// Ogni riga tranne l'ultima termina con \r\n.
    static func rows(_ records: [GuestRecord], checkIn: Int64, checkOut: Int64) throws -> [String] {
        try records.enumerated().map { index, record in
            let line = try row(record, checkIn: checkIn, checkOut: checkOut)
            return index < records.count - 1 ? line + "\r\n" : line
        }
    }
}
