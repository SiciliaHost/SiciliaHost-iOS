import Foundation

// Logica pura delle Finanze (`ui/finance/FinanceView.kt`, `FinanceListKeys.kt`, formati di `FinanceParts.kt`,
// `statsKpis` di `FinanceDetailScreens.kt`).

/// Tutto ciò che le Finanze mostrano per un periodo e una casa (o tutte): calcolato una volta sola.
struct FinanceViewData {
    let houses: [Property]
    /// Prenotazioni delle case scelte con arrivo nel periodo.
    let reservations: [FinReservation]
    /// Spese delle case scelte registrate nel periodo, dalla più recente.
    let expenses: [Expense]
    let totals: FinanceStats.Totals
    let stats: BookingStats.Summary
    /// Spese per categoria nel periodo, dalla più alta.
    let byCategory: [(category: ExpenseCategory, amount: Double)]
    let insights: [FinanceInsights.Insight]
}

func buildFinanceView(
    allReservations: [FinReservation],
    allExpenses: [Expense],
    properties: [Property],
    importCounts: [String: BookingImportCounts],
    period: FinancePeriod,
    propertyId: String?,
    now: Int64
) -> FinanceViewData {
    let houses = propertyId == nil ? properties : properties.filter { $0.id == propertyId }
    let ids = Set(houses.map(\.id))
    let range = period.range(now: now)
    let houseReservations = allReservations.filter { ids.contains($0.propertyId) }
    let reservations = houseReservations.filter { range == nil || range!.contains($0.checkIn) }
    let expenses = stableSortedDescending(
        allExpenses.filter { ids.contains($0.propertyId) && (range == nil || range!.contains($0.timestamp)) }
    ) { $0.timestamp }

    let totals = FinanceStats.totals(reservations: reservations, expenses: expenses)
    let stats = BookingStats.compute(
        reservations: houseReservations, range: range, houseCount: houses.count, now: now,
        importCounts: houses.compactMap { importCounts[$0.id] }
    )
    var sums: [ExpenseCategory: Double] = [:]
    var order: [ExpenseCategory] = []
    for e in expenses {
        let c = ExpenseCategory.of(e)
        if sums[c] == nil { order.append(c) }
        sums[c, default: 0] += e.amount
    }
    let byCategory = stableSortedDescending(order.map { (category: $0, amount: sums[$0]!) }) { $0.amount }

    // Prossimi 3 mesi: solo se ci sono già prenotazioni future (altrimenti sembrerebbe tutto vuoto solo perché il
    // calendario non è sincronizzato).
    var upcoming: [BookingStats.MonthOccupancy] = []
    if houseReservations.contains(where: { $0.checkIn >= now }) {
        let day: Int64 = 86_400_000
        let from = (now / day) * day
        let to = addMonthsUTC(startOfMonthUTC(now), 3)
        upcoming = BookingStats.compute(reservations: houseReservations, range: from ..< to, houseCount: houses.count, now: now)
            .monthlyOccupancy
    }
    let insights = FinanceInsights.compute(
        stats: stats, expensesByCategory: sums, netRevenue: totals.netOwner, upcomingMonths: upcoming
    )
    return FinanceViewData(houses: houses, reservations: reservations, expenses: expenses, totals: totals, stats: stats,
                           byCategory: byCategory, insights: insights)
}

/// Chiavi degli elenchi delle Finanze: uniche in tutta la schermata (la stessa casa compare in due sezioni). Su Android
/// una chiave doppia faceva andare in crash la lista; in SwiftUI rende ambigui gli aggiornamenti.
enum FinanceListKeys {
    static func propertyDetail(_ propertyId: String) -> String { "detail-\(propertyId)" }
    static func recurring(_ recurringId: String) -> String { "recurring-\(recurringId)" }
    static func pendingReservation(_ reservationId: String) -> String { "pending-\(reservationId)" }
    /// Una spesa senza id usa la posizione (due spese uguali avrebbero lo stesso contenuto).
    static func expense(_ expenseId: String, index: Int) -> String {
        expenseId.isEmpty ? "exp-noid-\(index)" : "exp-\(expenseId)"
    }
}

/// Formati dei numeri delle Finanze, in italiano e indipendenti dalla lingua del telefono.
enum FinanceFormat {
    /// Come `String.format(Locale.ITALY, "%,.Nf")` dell'Android: punto per le migliaia (anche a 4 cifre: il formattatore
    /// di sistema in italiano non le separa), virgola per i decimali. Fatto a mano per non dipendere dai dati CLDR.
    static func number(_ value: Double, decimals: Int) -> String {
        let fixed = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
        var integer = fixed
        var fraction = ""
        if let dot = fixed.firstIndex(of: ".") {
            integer = String(fixed[..<dot])
            fraction = String(fixed[fixed.index(after: dot)...])
        }
        // "-0" / "-0,00" (un negativo che arrotonda a zero) si scrive senza segno.
        let negative = integer.hasPrefix("-") && !fixed.allSatisfy { "-0.".contains($0) }
        if integer.hasPrefix("-") { integer.removeFirst() }
        var grouped = ""
        for (i, ch) in integer.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        return (negative ? "-" : "") + String(grouped.reversed()) + (fraction.isEmpty ? "" : "," + fraction)
    }

    /// "€1.234".
    static func euro0(_ value: Double) -> String { "€" + number(value, decimals: 0) }
    /// "€1.234,50".
    static func euro2(_ value: Double) -> String { "€" + number(value, decimals: 2) }
    /// "€1234.50" (saldo e tessere del bilancio: come `String.format(Locale.US, "%.2f")` dell'Android).
    static func euroPlain(_ value: Double) -> String { "€" + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
    static func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func dec1(_ value: Double) -> String { number(value, decimals: 1) }

    /// Nome italiano di un paese dal codice ISO ("de" → "Germania").
    static func countryName(_ code: String) -> String {
        Locale(identifier: "it_IT").localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    static func platformName(_ platform: String) -> String {
        switch platform {
        case "AIRBNB": return "Airbnb"
        case "BOOKING": return "Booking"
        case "MANUAL": return "Dirette / manuali"
        default: return platform
        }
    }
}

/// Un numero con la sua etichetta (e una nota sotto, es. "su 12 prenotazioni").
struct Kpi: Equatable, Identifiable {
    let label: String
    let value: String
    var note: String?
    var id: String { label }
}

/// Le tessere delle statistiche (le prime 4 sono anche nella card "Prenotazioni" delle Finanze).
func statsKpis(_ view: FinanceViewData, all: Bool) -> [Kpi] {
    let s = view.stats
    typealias F = FinanceFormat
    let base = [
        Kpi(label: "Occupazione", value: s.occupancy.map(F.pct) ?? "—", note: "\(s.nightsSold) notti su \(s.availableNights)"),
        Kpi(label: "Prezzo medio a notte", value: s.adr.map(F.euro0) ?? "—"),
        Kpi(label: "Notti medie", value: s.avgNights.map(F.dec1) ?? "—", note: "\(s.reservationCount) prenotazioni"),
        Kpi(label: "Ospiti medi", value: s.avgGuests.map(F.dec1) ?? "—",
            note: s.guestSample > 0 ? "su \(s.guestSample) prenotazioni" : "dato dall'Excel Booking"),
    ]
    guard all else { return base }
    var more = [
        Kpi(label: "Ricavo per notte disponibile", value: s.revPar.map(F.euro0) ?? "—", note: "RevPAR"),
        Kpi(label: "Incasso lordo", value: F.euro0(s.gross)),
        Kpi(label: "Adulti / bambini",
            value: s.avgAdults.map { "\(F.dec1($0)) / \(F.dec1(s.avgChildren ?? 0))" } ?? "—"),
        Kpi(label: "Con bambini", value: s.shareWithChildren.map(F.pct) ?? "—", note: "delle prenotazioni"),
        Kpi(label: "Anticipo medio", value: s.avgLeadDays.map { "\(Int($0)) giorni" } ?? "—",
            note: s.leadSample > 0 ? "su \(s.leadSample) prenotazioni Booking" : "dato dall'Excel Booking"),
        Kpi(label: "Cancellazioni", value: s.cancellationRate.map(F.pct) ?? "—", note: "ultimo import Booking"),
        Kpi(label: "Commissioni pagate", value: F.euro0(s.commissionsPaid), note: "Airbnb e Booking"),
    ]
    if let real = s.bookingRealCommissionRate {
        more.append(Kpi(label: "Commissione Booking reale", value: F.pct(real), note: "dall'Excel; l'app calcola il 23,8%"))
    }
    more.append(Kpi(label: "Notti isolate", value: "\(s.orphanNights)", note: "buchi di 1–2 notti in futuro"))
    return base + more
}

enum FinanceActions {
    /// Spesa biancheria creata quando si inserisce il lordo di una prenotazione (stessa forma dell'Android). L'id è
    /// locale: la spesa sta solo sul telefono, e un id vuoto farebbe sostituire una biancheria con l'altra.
    static func linenExpense(propertyId: String, reservationId: String, guest: String?) -> Expense {
        Expense(
            id: newLocalId(),
            propertyId: propertyId,
            reservationId: reservationId,
            description: "Spesa fissa biancheria (\(guest ?? "Ospite"))",
            amount: 20,
            authorId: "SYSTEM",
            category: ExpenseCategory.pulizie.key
        )
    }

    /// Importo scritto a mano ("12,50"): nil se non è un numero.
    static func parseAmount(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
