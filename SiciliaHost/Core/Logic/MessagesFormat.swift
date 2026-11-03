import Foundation

/// Testi e formati della scheda Messaggi (`MessagesFormat.kt`). Le date dei soggiorni sono giorni civili `yyyy-MM-dd`
/// (UTC, senza fuso); gli istanti dei messaggi si mostrano nell'ora di Roma.
enum MessagesFormat {
    private static let rome: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    static let italianMonths = [
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
        "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
    ]

    /// (anno, mese, giorno) di un `yyyy-MM-dd` valido, altrimenti nil.
    private static func civil(_ iso: String) -> (year: Int, month: Int, day: Int)? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        // Non indulgente come `isLenient = false` dell'Android: 2026-02-30 non esiste.
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        guard let date = utcCalendar.date(from: comps) else { return nil }
        let back = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return (y, m, d)
    }

    static func shortDate(_ iso: String) -> String {
        guard let c = civil(iso) else { return iso }
        return "\(c.day) \(italianShortMonths[c.month - 1])"
    }

    static func longDate(_ iso: String) -> String {
        guard let c = civil(iso) else { return iso }
        return "\(c.day) \(italianShortMonths[c.month - 1]) \(c.year)"
    }

    static func nights(_ checkIn: String, _ checkOut: String) -> Int? {
        guard let a = civil(checkIn), let b = civil(checkOut) else { return nil }
        let start = utcMillis(year: a.year, month: a.month, day: a.day)
        let end = utcMillis(year: b.year, month: b.month, day: b.day)
        return Int((end - start) / millisPerDay)
    }

    static func guests(_ count: Int) -> String { count == 1 ? "1 ospite" : "\(count) ospiti" }

    /// «1 dic 2026 → 4 dic 2026 · 3 notti · 2 ospiti», o solo gli ospiti, o «Date non indicate».
    static func stayLine(_ stay: StayRequest, long: Bool = true) -> String {
        var parts: [String] = []
        if let checkIn = stay.checkIn, let checkOut = stay.checkOut {
            let format = long ? longDate : shortDate
            parts.append("\(format(checkIn)) → \(format(checkOut))")
            if let n = nights(checkIn, checkOut) { parts.append(n == 1 ? "1 notte" : "\(n) notti") }
        }
        if let guests = stay.guests { parts.append(Self.guests(guests)) }
        return parts.isEmpty ? "Date non indicate" : parts.joined(separator: " · ")
    }

    static func statusLabel(_ status: String?) -> String {
        switch status {
        case nil: return "Richiesta"
        case "awaiting_confirmation": return "Da confermare"
        case "pending_payment": return "Caparra in attesa"
        case "confirmed": return "Confermata"
        case "cancelled": return "Annullata"
        default: return "In verifica"
        }
    }

    private static func romeParts(_ ms: Int64) -> DateComponents {
        rome.dateComponents([.year, .month, .day, .hour, .minute], from: dateFromMillis(ms))
    }

    /// Il giorno di Roma come `yyyy-MM-dd`.
    static func romeDay(_ ms: Int64) -> String {
        let c = romeParts(ms)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func time(_ ms: Int64) -> String {
        let c = romeParts(ms)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func shortRomeDate(_ ms: Int64) -> String {
        let c = romeParts(ms)
        return "\(c.day ?? 0) \(italianShortMonths[(c.month ?? 1) - 1])"
    }

    /// «Oggi», «Ieri» o la data, per separare i messaggi per giorno (ora di Roma).
    static func dayLabel(_ ms: Int64, now: Int64 = millisFromDate(Date())) -> String {
        let day = romeDay(ms)
        if day == romeDay(now) { return "Oggi" }
        if day == romeDay(now - millisPerDay) { return "Ieri" }
        let c = romeParts(ms)
        return "\(c.day ?? 0) \(italianMonths[(c.month ?? 1) - 1]) \(c.year ?? 0)"
    }

    /// Data breve nell'elenco: l'ora se è di oggi, altrimenti il giorno.
    static func listTime(_ ms: Int64, now: Int64 = millisFromDate(Date())) -> String {
        romeDay(ms) == romeDay(now) ? time(ms) : shortRomeDate(ms)
    }

    /// I messaggi raggruppati per giorno di Roma, in ordine.
    static func groupByDay(_ messages: [ChatMessage]) -> [(day: String, messages: [ChatMessage])] {
        var groups: [(day: String, messages: [ChatMessage])] = []
        for message in messages {
            let day = romeDay(message.at)
            if groups.last?.day == day {
                groups[groups.count - 1].messages.append(message)
            } else {
                groups.append((day, [message]))
            }
        }
        return groups
    }

    /// «400,00 €» (formato italiano).
    static func euro(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)) + " €"
    }
}

/// I messaggi del polling si aggiungono senza doppioni, in ordine di tempo (a parità, per id).
func mergeMessages(_ current: [ChatMessage], _ incoming: [ChatMessage]) -> [ChatMessage] {
    var byId: [String: ChatMessage] = [:]
    for m in current { byId[m.id] = m }
    for m in incoming { byId[m.id] = m }
    return byId.values.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
}

/// Stessa regola del server (`contactDetails.ts`): cifre col prefisso; senza «+» o «00» si assume +39.
func isValidPhone(_ value: String) -> Bool {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return true }
    if text.count > 30 || text.range(of: #"^\+?[0-9\s().\-/]+$"#, options: .regularExpression) == nil { return false }
    let compact = text.replacingOccurrences(of: #"[\s().\-/]"#, with: "", options: .regularExpression)
    let digits: String
    if compact.hasPrefix("+") { digits = String(compact.dropFirst()) }
    else if compact.hasPrefix("00") { digits = String(compact.dropFirst(2)) }
    else { digits = "39" + compact }
    return digits.range(of: "^[1-9][0-9]{6,14}$", options: .regularExpression) != nil
}
