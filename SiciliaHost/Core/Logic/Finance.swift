import Foundation

// MARK: Calcolo dei netti

/// Commissioni e quote: 23,8% Booking, 17,5% Airbnb; casa in commissione = 21% di tasse e il 25% del netto + 50 €.
enum FinancialCalculator {
    struct Result: Equatable {
        let netAmountOwner: Double
        let netAmountAdmin: Double
    }

    static func calculate(grossAmount: Double, platform: String, isManagedOnCommission: Bool) -> Result {
        let platformCommRate: Double
        switch platform.uppercased() {
        case "BOOKING": platformCommRate = 0.238
        case "AIRBNB": platformCommRate = 0.175
        default: platformCommRate = 0.0
        }
        let platformComm = grossAmount * platformCommRate

        if isManagedOnCommission {
            let tax = grossAmount * 0.21
            let netOwner = grossAmount - tax - platformComm
            return Result(netAmountOwner: netOwner, netAmountAdmin: (netOwner * 0.25) + 50.0)
        }
        let netOwner = grossAmount - platformComm
        return Result(netAmountOwner: netOwner, netAmountAdmin: netOwner)
    }
}

// MARK: Categorie di spesa

/// Categorie delle spese. `key` è il valore salvato in `Expense.category` / `RecurringExpense.category`
/// (stabile: non cambiarlo), `label` quello mostrato.
enum ExpenseCategory: CaseIterable, Sendable {
    case pulizie, utenze, manutenzione, forniture, tasse, arredi, marketing, altro

    var key: String {
        switch self {
        case .pulizie: return "cleaning"
        case .utenze: return "utilities"
        case .manutenzione: return "maintenance"
        case .forniture: return "supplies"
        case .tasse: return "taxes"
        case .arredi: return "furniture"
        case .marketing: return "marketing"
        case .altro: return "other"
        }
    }

    var label: String {
        switch self {
        case .pulizie: return "Pulizie e biancheria"
        case .utenze: return "Utenze"
        case .manutenzione: return "Manutenzione e riparazioni"
        case .forniture: return "Forniture e consumabili"
        case .tasse: return "Tasse e commissioni"
        case .arredi: return "Arredi e attrezzature"
        case .marketing: return "Marketing"
        case .altro: return "Altro"
        }
    }

    static func fromKey(_ key: String?) -> ExpenseCategory? {
        allCases.first { $0.key == key }
    }

    /// La categoria di una spesa: quella salvata, oppure ricavata dalla descrizione (spese vecchie).
    static func of(_ expense: Expense) -> ExpenseCategory {
        fromKey(expense.category) ?? infer(expense.description)
    }

    // Radici di parola, confrontate con l'INIZIO di ogni parola della descrizione (così "tari" non scatta dentro
    // "sanitari"). L'ordine conta: vince la prima categoria che trova qualcosa.
    private static let keywords: [(ExpenseCategory, [String])] = [
        (.pulizie, ["biancheria", "pulizi", "lavanderia", "lenzuol", "asciugaman", "stiratur", "colf", "sanificaz"]),
        (.tasse, ["tass", "impost", "imu", "tari", "irpef", "f24", "commission", "cedolare", "iva", "commercialist", "soggiorno"]),
        (.manutenzione, ["riparaz", "manutenz", "idraulic", "elettricist", "guast", "caldaia", "condizionator", "climatizz", "imbianc", "ferrament", "tecnico"]),
        (.utenze, ["luce", "enel", "elettric", "gas", "acquedott", "idric", "internet", "wifi", "fibra", "telefon", "bollett", "condomin", "energia"]),
        (.arredi, ["arred", "mobil", "divano", "materass", "elettrodomest", "tv", "televisor", "lavatric", "frigo", "pentol", "stovigli", "lampad"]),
        (.marketing, ["fotograf", "foto", "pubblicit", "marketing", "sponsor", "social", "annunc"]),
        (.forniture, ["igienic", "sapon", "shampoo", "caff", "cialde", "detersiv", "cortesia", "kit", "consumabil", "carta", "acqua"]),
    ]

    static func infer(_ description: String) -> ExpenseCategory {
        let words = description.lowercased(with: Locale(identifier: "it"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for (category, stems) in keywords where words.contains(where: { word in stems.contains { word.hasPrefix($0) } }) {
            return category
        }
        return .altro
    }
}

// MARK: Periodi

/// Periodo delle Finanze. I mesi sono in UTC come in `FinanceStats` (le date delle prenotazioni sono mezzanotti UTC).
/// `range` = inizio incluso, fine esclusa; nil = tutto.
enum FinancePeriod: CaseIterable, Sendable {
    case thisMonth, lastMonth, last12Months, thisYear, lastYear, all

    var label: String {
        switch self {
        case .thisMonth: return "Questo mese"
        case .lastMonth: return "Mese scorso"
        case .last12Months: return "Ultimi 12 mesi"
        case .thisYear: return "Anno in corso"
        case .lastYear: return "Anno scorso"
        case .all: return "Tutto"
        }
    }

    func range(now: Int64) -> Range<Int64>? {
        let monthStart = startOfMonthUTC(now)
        func shifted(_ months: Int) -> Int64 { addMonthsUTC(monthStart, months) }
        let year = utcCalendar.component(.year, from: dateFromMillis(now))
        func yearStart(_ y: Int) -> Int64 { utcMillis(year: y, month: 1, day: 1) }
        switch self {
        case .thisMonth: return monthStart ..< shifted(1)
        case .lastMonth: return shifted(-1) ..< monthStart
        case .last12Months: return shifted(-11) ..< shifted(1)
        case .thisYear: return yearStart(year) ..< yearStart(year + 1)
        case .lastYear: return yearStart(year - 1) ..< yearStart(year)
        case .all: return nil
        }
    }
}

// MARK: Aggregazioni

/// Aggregazioni pure per la schermata Finanze. Gli importi sono ricalcolati con `FinancialCalculator` invece di
/// leggere i campi salvati sulla prenotazione: quelli diventano vecchi quando cambia il regime di commissione.
enum FinanceStats {
    struct Totals: Equatable {
        let gross: Double
        let netOwner: Double
        let adminRevenue: Double
        let expenses: Double
        var balance: Double { adminRevenue - expenses }
    }

    struct PropertyStats: Equatable {
        let property: Property
        let reservationCount: Int
        let gross: Double
        let adminRevenue: Double
        let expenses: Double
        var balance: Double { adminRevenue - expenses }
    }

    struct MonthStats: Equatable {
        let label: String
        let revenue: Double
        let expenses: Double
    }

    struct PlatformTotal: Equatable {
        let platform: String
        let gross: Double
    }

    static func totals(reservations: [Reservation], expenses: [Expense], properties: [Property]) -> Totals {
        var gross = 0.0, netOwner = 0.0, adminRevenue = 0.0
        for res in reservations {
            guard let amount = res.grossAmount else { continue }
            let calc = calculate(res, amount, properties)
            gross += amount
            netOwner += calc.netAmountOwner
            adminRevenue += calc.netAmountAdmin
        }
        return Totals(gross: gross, netOwner: netOwner, adminRevenue: adminRevenue, expenses: expenses.reduce(0) { $0 + $1.amount })
    }

    static func perProperty(reservations: [Reservation], expenses: [Expense], properties: [Property]) -> [PropertyStats] {
        let stats = properties.map { prop -> PropertyStats in
            let own = reservations.filter { $0.propertyId == prop.id }
            let gross = own.reduce(0) { $0 + ($1.grossAmount ?? 0) }
            let adminRevenue = own.reduce(0) { sum, res in
                sum + (res.grossAmount.map { calculate(res, $0, properties).netAmountAdmin } ?? 0)
            }
            let spent = expenses.filter { $0.propertyId == prop.id }.reduce(0) { $0 + $1.amount }
            return PropertyStats(property: prop, reservationCount: own.count, gross: gross, adminRevenue: adminRevenue, expenses: spent)
        }
        return stableSortedDescending(stats, by: \.balance)
    }

    /// Entrate (netto admin per mese di check-in) e uscite (per timestamp) negli ultimi `monthCount` mesi incluso
    /// quello corrente, dal più vecchio al corrente.
    static func monthly(reservations: [Reservation], expenses: [Expense], properties: [Property], monthCount: Int, now: Int64) -> [MonthStats] {
        var start = addMonthsUTC(startOfMonthUTC(now), -(monthCount - 1))
        return (0 ..< max(monthCount, 0)).map { _ in
            let label = shortMonthLabel(start)
            let end = addMonthsUTC(start, 1)
            let revenue = reservations
                .filter { $0.grossAmount != nil && $0.checkIn >= start && $0.checkIn < end }
                .reduce(0) { sum, res in sum + (res.grossAmount.map { calculate(res, $0, properties).netAmountAdmin } ?? 0) }
            let spent = expenses.filter { $0.timestamp >= start && $0.timestamp < end }.reduce(0) { $0 + $1.amount }
            let month = MonthStats(label: label, revenue: revenue, expenses: spent)
            start = end
            return month
        }
    }

    /// Lordo per piattaforma, solo prenotazioni con importo inserito, dal maggiore al minore.
    static func perPlatform(_ reservations: [Reservation]) -> [PlatformTotal] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        for res in reservations {
            guard let gross = res.grossAmount else { continue }
            if totals[res.platform] == nil { order.append(res.platform) }
            totals[res.platform, default: 0] += gross
        }
        return stableSortedDescending(order.map { PlatformTotal(platform: $0, gross: totals[$0]!) }, by: \.gross)
    }

    private static func calculate(_ reservation: Reservation, _ gross: Double, _ properties: [Property]) -> FinancialCalculator.Result {
        let commissioned = properties.first { $0.id == reservation.propertyId }?.isManagedOnCommission ?? false
        return FinancialCalculator.calculate(grossAmount: gross, platform: reservation.platform, isManagedOnCommission: commissioned)
    }
}

// MARK: Spese fisse e orfane

/// Trasforma le spese fisse mensili in spese vere. Le spese generate hanno un id deterministico
/// (`rec_<fissa>_<yyyy-MM>`): rigenerare è idempotente, anche se due dispositivi aprono Finanze insieme.
enum RecurringExpenses {
    static func expenseId(recurringId: String, month: String) -> String { "rec_\(recurringId)_\(month)" }

    static func monthKey(_ millis: Int64) -> String {
        let comps = utcCalendar.dateComponents([.year, .month], from: dateFromMillis(millis))
        return String(format: "%04d-%02d", comps.year!, comps.month!)
    }

    /// "yyyy-MM" valido (mese 01-12, anno 2000-2200), altrimenti nil.
    private static func parseMonth(_ text: String) -> (year: Int, month: Int)? {
        let parts = text.components(separatedBy: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (2000 ... 2200).contains(year), (1 ... 12).contains(month) else { return nil }
        return (year, month)
    }

    /// Mezzogiorno UTC del 1° del mese: dentro il mese in qualunque fuso, e coerente con i grafici di
    /// `FinanceStats`, che raggruppano i mesi in UTC.
    private static func monthTimestamp(year: Int, month: Int) -> Int64 {
        utcMillis(year: year, month: month, day: 1, hour: 12)
    }

    /// Le spese mancanti: una per ogni mese da `startMonth` al mese di `now` incluso, per le fisse valide,
    /// saltando gli id già presenti in `existingExpenseIds`.
    static func dueExpenses(recurring: [RecurringExpense], existingExpenseIds: Set<String>, now: Int64) -> [Expense] {
        guard let current = parseMonth(monthKey(now)) else { return [] }
        var result: [Expense] = []
        for rec in recurring {
            if rec.id.trimmed.isEmpty || rec.amount <= 0.0 { continue }
            guard var (year, month) = parseMonth(rec.startMonth) else { continue }
            while year < current.year || (year == current.year && month <= current.month) {
                let key = String(format: "%04d-%02d", year, month)
                let id = expenseId(recurringId: rec.id, month: key)
                if !existingExpenseIds.contains(id) {
                    result.append(Expense(
                        id: id, propertyId: rec.propertyId, description: "\(rec.description) (fissa)", amount: rec.amount,
                        authorId: "SYSTEM", timestamp: monthTimestamp(year: year, month: month), category: rec.category
                    ))
                }
                if month == 12 { year += 1; month = 1 } else { month += 1 }
            }
        }
        return result
    }
}

/// Id delle spese collegate a una prenotazione che non esiste più (es. cancellata da un collaboratore, che non può
/// toccare le spese). Le spese senza prenotazione (fisse mensili, manuali) non sono mai orfane. Va usata solo con
/// l'elenco COMPLETO delle prenotazioni delle stesse case delle spese, altrimenti si cancellerebbe per errore.
func orphanExpenseIds(_ expenses: [Expense], reservationIds: Set<String>) -> [String] {
    expenses
        .filter { ($0.reservationId ?? "").isEmpty == false && !reservationIds.contains($0.reservationId!) }
        .map(\.id)
}
