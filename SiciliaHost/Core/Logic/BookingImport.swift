import Foundation

// MARK: Piano di importazione

/// Una riga dell'Excel: la parte condivisa (server) e quella dei soldi (telefono).
struct ExcelRow: Equatable {
    var reservation: Reservation
    var money: ExcelMoneyRow
}

/// Cosa fare di ogni riga dell'Excel Booking rispetto alle prenotazioni Booking già salvate della casa.
///
/// Una riga che a suo tempo ha completato un segnaposto iCal vive nel documento del segnaposto (id e `icalUid`
/// dell'iCal), non in `booking-xls-N`: confrontare solo per id la farebbe reinserire a ogni nuovo import. Per questo il
/// confronto è per date sovrapposte su TUTTE le prenotazioni Booking:
/// - `complete`: si sovrappone a un segnaposto iCal senza nome → lo completa (nome, adulti, bambini, paese);
/// - `enrich`: si sovrappone a una prenotazione già con nome → il server non cambia, i soldi vanno comunque sul telefono;
/// - `insert`: nessuna sovrapposizione → prenotazione nuova (passa da `syncIcalReservationsBatch`).
struct BookingImportPlan {
    /// segnaposto esistente → riga
    let complete: [(existing: Reservation, row: ExcelRow)]
    /// prenotazione esistente → riga
    let enrich: [(existing: Reservation, row: ExcelRow)]
    let insert: [ExcelRow]
}

/// Segnaposto = Booking creato dall'iCal e mai completato: senza nome e non da Excel.
func isNamelessIcalPlaceholder(_ r: Reservation) -> Bool {
    guard let uid = r.icalUid else { return false }
    return !uid.hasPrefix("booking-xls-") && (r.guestName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
}

func planBookingImport(rows: [ExcelRow], existingBooking: [Reservation]) -> BookingImportPlan {
    var complete: [(existing: Reservation, row: ExcelRow)] = []
    var enrich: [(existing: Reservation, row: ExcelRow)] = []
    var insert: [ExcelRow] = []
    var used = Set<String>()
    for row in rows {
        let r = row.reservation
        // Prima lo stesso documento di un import precedente, poi un segnaposto, poi qualunque sovrapposizione.
        let sameDoc = existingBooking.first { $0.id == r.icalUid && !used.contains($0.id) }
        let overlapping = existingBooking.filter {
            !used.contains($0.id) && dateRangesOverlap($0.checkIn, $0.checkOut, r.checkIn, r.checkOut)
        }
        let match = sameDoc ?? overlapping.first(where: isNamelessIcalPlaceholder) ?? overlapping.first
        guard let match else {
            insert.append(row)
            continue
        }
        if sameDoc == nil && isNamelessIcalPlaceholder(match) {
            complete.append((existing: match, row: row))
        } else {
            enrich.append((existing: match, row: row))
        }
        used.insert(match.id)
    }
    return BookingImportPlan(complete: complete, enrich: enrich, insert: insert)
}

// MARK: Lettura dell'export "Arrivi con recapiti"

struct BookingImportError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Legge l'export "Arrivi con recapiti" di Booking.com (.xls legacy oppure CSV con le stesse colonne) e produce
/// righe in due parti: quella condivisa (nome, date, ospiti, paese: va sul server) e quella dei soldi (lordo,
/// commissione, statistiche: resta sul telefono del proprietario), più i contatti dei clienti (anche loro solo sul
/// telefono).
///
/// Booking genera lo stesso report con intestazioni italiane o inglesi a seconda della lingua dell'account: ogni
/// colonna è quindi cercata con entrambi i nomi.
enum BookingExcelParser {
    struct ImportResult {
        let rows: [ExcelRow]
        let contacts: [Contact]
        let skippedRows: Int
        /// Righe cancellate nel periodo del file: non diventano prenotazioni (bloccherebbero il calendario del
        /// sito), servono solo al tasso di cancellazione delle Finanze.
        var cancelledRows = 0
        /// Primo e ultimo arrivo del file (millis UTC), per sapere a che periodo si riferisce.
        var periodFrom: Int64?
        var periodTo: Int64?
    }

    // Ogni colonna è cercata con il nome italiano e quello inglese dell'export Booking.
    private static let knownHeaders: Set<String> = [
        "Stato", "Status",
        "N° di prenotazione", "Book number",
        "Nome ospite(i)", "Guest name(s)",
        "Arrivo", "Check-in",
        "Partenza", "Check-out",
        "Prezzo", "Price",
        "Adulti", "Adults",
        "Bambini", "Children",
        "Numero di telefono", "Phone number",
        "Indirizzo", "Address",
        "Booker country",
        "Data di prenotazione", "Booked on",
        "Motivo del viaggio", "Travel purpose",
        "Dispositivo", "Device",
        "Importo commissione", "Commission amount",
    ]

    private static let ole2Magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0]

    /// Legge il file (xls binario oppure CSV) e ne ricava prenotazioni e contatti.
    static func parse(data: Data, propertyId: String) throws -> ImportResult {
        let rows: [[String]]
        if data.count >= ole2Magic.count && Array(data.prefix(ole2Magic.count)) == ole2Magic {
            rows = try XlsReader.readRows(data)
        } else {
            rows = readCsvRows(data)
        }
        return try parseRows(rows, propertyId: propertyId)
    }

    // MARK: CSV

    static func readCsvRows(_ data: Data) -> [[String]] {
        var bytes = data
        if bytes.count >= 3 && bytes[bytes.startIndex] == 0xEF && bytes[bytes.startIndex + 1] == 0xBB && bytes[bytes.startIndex + 2] == 0xBF {
            bytes = bytes.dropFirst(3)
        }
        let text = String(decoding: bytes, as: UTF8.self)
        let delimiter = detectDelimiter(text)
        return parseCsvRecords(text, delimiter: delimiter).filter { row in row.contains { !$0.trimmed.isEmpty } }
    }

    /// Conta i candidati nella prima riga (fuori dalle virgolette) e sceglie il più frequente; a parità vince ';'.
    static func detectDelimiter(_ text: String) -> Character {
        let candidates: [Character] = [";", ",", "\t"]
        var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false
        scan: for ch in text {
            switch ch {
            case "\"": inQuotes.toggle()
            case _ where inQuotes: break
            case "\n", "\r\n", "\r": break scan // "\r\n" è un solo Character in Swift
            default:
                if counts[ch] != nil { counts[ch]! += 1 }
            }
        }
        var best: Character = ","
        var bestCount = 0
        for c in candidates where counts[c]! > bestCount {
            best = c
            bestCount = counts[c]!
        }
        return bestCount > 0 ? best : ","
    }

    /// Split RFC 4180: campi tra virgolette (con "" per il literal), separatori e a capo ammessi dentro i campi quotati.
    static func parseCsvRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        // Si lavora sugli scalari Unicode: in Swift "\r\n" è un unico Character e confonderebbe il ciclo.
        let scalars = Array(text.unicodeScalars)
        let delim = delimiter.unicodeScalars.first!
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            if inQuotes && ch == "\"" {
                if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                    field.unicodeScalars.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if inQuotes {
                field.unicodeScalars.append(ch)
            } else if ch == delim {
                record.append(field.trimmed)
                field = ""
            } else if ch == "\r" {
                // \n chiude il record; dentro i campi quotati \r\n è preservato
            } else if ch == "\n" {
                record.append(field.trimmed)
                records.append(record)
                record = []
                field = ""
            } else {
                field.unicodeScalars.append(ch)
            }
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field.trimmed)
            records.append(record)
        }
        return records
    }

    // MARK: Righe → prenotazioni

    /// "yyyy-MM-dd" oppure "dd/MM/yyyy" (prefisso: dopo la data può esserci un'ora), in UTC.
    static func parseDate(_ text: String) -> Int64? {
        let t = text.trimmed
        if let m = firstMatch(#"^(\d{4})-(\d{1,2})-(\d{1,2})"#, in: t), let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]) {
            return validDate(y, mo, d)
        }
        if let m = firstMatch(#"^(\d{1,2})/(\d{1,2})/(\d{4})"#, in: t), let d = Int(m[1]), let mo = Int(m[2]), let y = Int(m[3]) {
            return validDate(y, mo, d)
        }
        return nil
    }

    private static func validDate(_ y: Int, _ m: Int, _ d: Int) -> Int64? {
        guard (1 ... 12).contains(m), (1 ... 31).contains(d) else { return nil }
        let millis = utcMillis(year: y, month: m, day: d)
        // Scarta i giorni inesistenti (es. 31/02), che il calendario riporterebbe al mese dopo.
        let comps = utcCalendar.dateComponents([.month, .day], from: dateFromMillis(millis))
        return comps.month == m && comps.day == d ? millis : nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0 ..< match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// "400 EUR" / "250,5 EUR" / "400" → 400 / 250.5 / 400.
    private static func amount(_ text: String) -> Double? {
        Double(text.components(separatedBy: " ")[0].replacingOccurrences(of: ",", with: "."))
    }

    static func parseRows(_ rows: [[String]], propertyId: String) throws -> ImportResult {
        guard let headerRow = rows.first else { return ImportResult(rows: [], contacts: [], skippedRows: 0) }
        var columnIndex: [String: Int] = [:]
        for (i, name) in headerRow.enumerated() { columnIndex[name.trimmed] = i }
        if !columnIndex.keys.contains(where: knownHeaders.contains) {
            throw BookingImportError(message: "Nessuna colonna riconosciuta: il file non sembra l'export \"Arrivi con recapiti\" di Booking")
        }

        func cell(_ row: [String], _ names: String...) -> String {
            guard let index = names.compactMap({ columnIndex[$0] }).first, index < row.count else { return "" }
            return row[index].trimmed
        }

        var parsed: [ExcelRow] = []
        var contacts: [Contact] = []
        var skipped = 0
        var cancelled = 0
        var periodFrom: Int64?
        var periodTo: Int64?

        for row in rows.dropFirst() {
            let stato = cell(row, "Stato", "Status").lowercased()
            let bookingId = cell(row, "N° di prenotazione", "Book number")
            let guestName = cell(row, "Nome ospite(i)", "Guest name(s)")
            let arrivo = cell(row, "Arrivo", "Check-in")
            let partenza = cell(row, "Partenza", "Check-out")
            let prezzoText = cell(row, "Prezzo", "Price")
            let adults = Int(cell(row, "Adulti", "Adults")) ?? 0
            let children = Int(cell(row, "Bambini", "Children")) ?? 0

            if let d = parseDate(arrivo) {
                periodFrom = min(periodFrom ?? d, d)
                periodTo = max(periodTo ?? d, d)
            }
            if stato.contains("cancel") { cancelled += 1 }

            if stato != "ok" || bookingId.isEmpty || arrivo.isEmpty || partenza.isEmpty || prezzoText.isEmpty {
                skipped += 1
                continue
            }
            guard let checkIn = parseDate(arrivo), let checkOut = parseDate(partenza), let gross = amount(prezzoText) else {
                skipped += 1
                continue
            }

            let country = cell(row, "Booker country")
            let purpose = cell(row, "Motivo del viaggio", "Travel purpose")
            let device = cell(row, "Dispositivo", "Device")

            parsed.append(ExcelRow(
                reservation: Reservation(
                    propertyId: propertyId,
                    guestName: guestName.isEmpty ? nil : guestName,
                    checkIn: checkIn,
                    checkOut: checkOut,
                    platform: "BOOKING",
                    // Il prefisso "booking-xls-" resta anche per i CSV: è l'ID documento usato per la deduplicazione,
                    // cambiarlo duplicherebbe le prenotazioni.
                    icalUid: "booking-xls-\(bookingId)",
                    adults: adults,
                    children: children,
                    guestCountry: country.isEmpty ? nil : country.lowercased()
                ),
                money: ExcelMoneyRow(
                    propertyId: propertyId,
                    grossAmount: gross,
                    commissionAmount: amount(cell(row, "Importo commissione", "Commission amount")),
                    // "2025-12-14 20:01:12": basta la data.
                    bookedAt: parseDate(cell(row, "Data di prenotazione", "Booked on").components(separatedBy: " ")[0]),
                    travelPurpose: purpose.isEmpty ? nil : purpose,
                    bookingDevice: device.isEmpty ? nil : device
                )
            ))

            let phoneDigits = cell(row, "Numero di telefono", "Phone number")
            if !phoneDigits.isEmpty {
                contacts.append(Contact(
                    phone: "+\(phoneDigits)", name: guestName, address: cell(row, "Indirizzo", "Address"),
                    country: country, propertyId: propertyId
                ))
            }
        }

        return ImportResult(
            rows: parsed, contacts: contacts, skippedRows: skipped,
            cancelledRows: cancelled, periodFrom: periodFrom, periodTo: periodTo
        )
    }
}
