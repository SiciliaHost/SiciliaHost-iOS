import Foundation

// Logica pura dell'editor prezzi (`PriceSelection.kt` e `GuestPricing.kt`): niente SwiftUI né Firebase.

/// Un giorno di calendario senza ora né fuso (equivalente di `java.time.LocalDate`). Le date ISO "aaaa-mm-gg" delle
/// tariffe e delle promozioni si confrontano come testo: l'ordine lessicografico è quello cronologico.
struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "2026-08-04" → giorno; nil se il testo non è una data valida.
    init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        guard let date = LocalDay.utc.date(from: comps) else { return nil }
        self.init(utcDate: date)
        guard year == parts[0], month == parts[1], day == parts[2] else { return nil }
    }

    /// Il giorno di calendario di `date` nel calendario `calendar` (di solito quello del telefono).
    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    private init(utcDate: Date) {
        let c = LocalDay.utc.dateComponents([.year, .month, .day], from: utcDate)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { iso }

    /// Mezzanotte UTC del giorno.
    var utcDate: Date { dateFromMillis(utcMillis(year: year, month: month, day: day)) }

    func plusDays(_ n: Int) -> LocalDay {
        LocalDay(utcDate: LocalDay.utc.date(byAdding: .day, value: n, to: utcDate) ?? utcDate)
    }

    /// 0 = domenica … 6 = sabato.
    var weekdayFromSunday: Int { LocalDay.utc.component(.weekday, from: utcDate) - 1 }

    static func < (a: LocalDay, b: LocalDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

/// Un mese di calendario (`java.time.YearMonth`).
struct YearMonth: Hashable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        // Normalizza mesi fuori intervallo (13 → gennaio dell'anno dopo).
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1)
    }

    func plusMonths(_ n: Int) -> YearMonth { YearMonth(year: year, month: month + n) }

    func atDay(_ day: Int) -> LocalDay { LocalDay(year: year, month: month, day: day) }

    var lengthOfMonth: Int {
        let first = atDay(1)
        let next = plusMonths(1).atDay(1)
        return Int((next.utcDate.timeIntervalSince(first.utcDate) / 86_400).rounded())
    }

    /// "AGOSTO 2026".
    var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: atDay(1).utcDate).uppercased()
    }
}

/// Prezzo mostrato in una cella: `isSeasonal` distingue una tariffa impostata dal prezzo base.
struct DayPrice: Equatable {
    let amount: Double?
    let isSeasonal: Bool
}

enum PriceLogic {
    static let maxPrice = 10_000.0
    static let maxExtra = 10_000.0

    /// Tutti i giorni tra `anchor` e `current` inclusi, in qualsiasi ordine vengano passati.
    static func dragRange(_ anchor: LocalDay, _ current: LocalDay) -> Set<LocalDay> {
        let from = min(anchor, current), to = max(anchor, current)
        var days = Set<LocalDay>()
        var day = from
        while day <= to {
            days.insert(day)
            day = day.plusDays(1)
        }
        return days
    }

    static func monthDates(_ month: YearMonth) -> Set<LocalDay> {
        Set((1 ... month.lengthOfMonth).map(month.atDay))
    }

    /// "Tutto il mese": se il mese è già tutto selezionato lo toglie, altrimenti lo completa.
    static func toggleMonth(_ selection: Set<LocalDay>, _ month: YearMonth) -> Set<LocalDay> {
        let all = monthDates(month)
        return all.isSubset(of: selection) ? selection.subtracting(all) : selection.union(all)
    }

    /// Raggruppa le date in intervalli di giorni consecutivi, già nel formato della callable.
    static func groupIntoRanges(_ dates: Set<LocalDay>) -> [IsoRange] {
        var ranges: [IsoRange] = []
        var start: LocalDay?
        var prev: LocalDay?
        for day in dates.sorted() {
            if let s = start, let p = prev {
                if day != p.plusDays(1) {
                    ranges.append(IsoRange(startDate: s.iso, endDate: p.iso))
                    start = day
                }
            } else {
                start = day
            }
            prev = day
        }
        if let s = start, let p = prev { ranges.append(IsoRange(startDate: s.iso, endDate: p.iso)) }
        return ranges
    }

    /// Come il server: il primo intervallo che contiene il giorno vince, altrimenti il prezzo base.
    static func priceForDay(_ day: LocalDay, rates: [SeasonalRateEntry], basePrice: Double?) -> DayPrice {
        let iso = day.iso
        if let match = rates.first(where: { iso >= $0.startDate && iso <= $0.endDate }) {
            return DayPrice(amount: match.pricePerNight, isSeasonal: true)
        }
        return DayPrice(amount: basePrice, isSeasonal: false)
    }

    /// "120", "99,5", "99,99"; "—" se manca. Indipendente dalla lingua del telefono.
    static func formatPrice(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        var fixed = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount) // arrotonda a 2 decimali
        while fixed.hasSuffix("0") { fixed.removeLast() }
        if fixed.hasSuffix(".") { fixed.removeLast() }
        return fixed.replacingOccurrences(of: ".", with: ",")
    }

    private static func isMoney(_ text: String) -> Bool {
        text.wholeMatch(of: #/[0-9]+([.,][0-9]{1,2})?/#) != nil
    }

    private static func money(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Legge il campo prezzo: numero positivo, al massimo 2 decimali (punto o virgola), ≤ 10000.
    static func parsePrice(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMoney(t), let value = money(t), value > 0, value <= maxPrice else { return nil }
        return value
    }

    /// Cella (riga, colonna) sotto il punto (`x`, `y`) di una griglia a 7 colonne larga `gridWidth` con `gap` tra le
    /// celle, o nil fuori dalla griglia. Le celle sono larghe `cellAspect` volte la loro altezza (1 = quadrate).
    static func gridCellAt(
        x: Double, y: Double, gridWidth: Double, gap: Double, rowCount: Int, cellAspect: Double = 1
    ) -> (row: Int, col: Int)? {
        if x < 0 || y < 0 || x >= gridWidth { return nil }
        let colStride = (gridWidth - 6 * gap) / 7 + gap
        let rowStride = (colStride - gap) / cellAspect + gap
        let row = Int(y / rowStride)
        let col = min(Int(x / colStride), 6)
        return row < rowCount ? (row, col) : nil
    }

    /// La notte che inizia in `day` è occupata se check-in ≤ giorno < check-out (giorni nel calendario `calendar`).
    static func isNightBooked(
        _ day: LocalDay, propertyId: String, reservations: [Reservation], calendar: Calendar = .current
    ) -> Bool {
        reservations.contains { r in
            r.propertyId == propertyId
                && day >= LocalDay(dateFromMillis(r.checkIn), calendar: calendar)
                && day < LocalDay(dateFromMillis(r.checkOut), calendar: calendar)
        }
    }

    // MARK: Extra per ospiti e promozioni (`GuestPricing.kt`)

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Legge l'extra a notte: numero >= 0 con al massimo 2 decimali (punto o virgola), <= 10000.
    static func parseExtra(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMoney(t), let value = money(t), value <= maxExtra else { return nil }
        return value
    }

    /// Valore dello sconto: % in (0, 100], euro in (0, 10000], al massimo 2 decimali.
    static func parsePromoValue(discountType: String, _ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMoney(t), let value = money(t), value > 0 else { return nil }
        let max = discountType == discountPercentage ? 100.0 : maxExtra
        return value <= max ? value : nil
    }

    /// Prezzo di una notte dopo una promozione, come il server (arrotonda a 2 decimali, mai sotto 0).
    static func discountedPrice(_ price: Double, _ promo: PromoEntry) -> Double {
        promo.discountType == discountPercentage
            ? round2(price * (1 - promo.discountValue / 100))
            : max(0, round2(price - promo.discountValue))
    }

    /// Prezzo scontato di `day` se una promozione lo copre (vince la più conveniente), altrimenti nil.
    static func promoPriceForDay(_ day: LocalDay, price: Double?, promos: [PromoEntry]) -> Double? {
        guard let price else { return nil }
        let iso = day.iso
        guard let best = promos.filter({ iso >= $0.startDate && iso <= $0.endDate }).map({ discountedPrice(price, $0) }).min()
        else { return nil }
        return best < price ? best : nil
    }

    /// {"3": 10} dal documento della casa → {3: 10}; scarta chiavi non numeriche, ospiti < 2 e valori <= 0.
    static func toSurchargeMap(_ raw: [String: Double]?) -> [Int: Double] {
        var map: [Int: Double] = [:]
        for (k, v) in raw ?? [:] {
            if let n = Int(k), n >= 2, v > 0 { map[n] = v }
        }
        return map
    }

    /// Aggiunge/sostituisce l'extra per `guests` ospiti; `value` 0 (o meno) lo rimuove.
    static func mergeSurcharges(_ current: [Int: Double], guests: Int, value: Double) -> [Int: Double] {
        var next = current
        if value <= 0 { next.removeValue(forKey: guests) } else { next[guests] = value }
        return next
    }

    /// Mappa con chiavi testuali, come nel documento della casa.
    static func surchargesToRaw(_ map: [Int: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
    }

    static func formatPromoRange(_ p: PromoEntry) -> String {
        func f(_ iso: String) -> String {
            guard let d = LocalDay(iso: iso) else { return iso }
            return String(format: "%02d/%02d/%d", d.day, d.month, d.year)
        }
        return p.startDate == p.endDate ? f(p.startDate) : "\(f(p.startDate)) – \(f(p.endDate))"
    }

    static func formatDiscount(_ p: PromoEntry) -> String {
        p.discountType == discountPercentage ? "−\(formatPrice(p.discountValue))%" : "−€\(formatPrice(p.discountValue))"
    }
}
