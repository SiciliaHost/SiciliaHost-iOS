import XCTest
@testable import SiciliaHost

// Specifica: FinancialCalculatorTest, FinanceStatsTest, DateRangeUtilsTest, OrphanExpensesTest, RecurringExpensesTest,
// BookingStatsTest (insight, categorie, periodi) dell'app Android.
final class FinanceTests: XCTestCase {
    // MARK: FinancialCalculator

    func testNetOwner() {
        XCTAssertEqual(FinancialCalculator.netOwner(gross: 1000, platform: "BOOKING"), 762, accuracy: 0.001)
        XCTAssertEqual(FinancialCalculator.netOwner(gross: 1000, platform: "airbnb"), 825, accuracy: 0.001)
        XCTAssertEqual(FinancialCalculator.netOwner(gross: 1000, platform: "MANUAL"), 1000, accuracy: 0.001)
        XCTAssertEqual(FinancialCalculator.netOwner(gross: 1000, platform: "BOOKING", realCommission: 180), 820, accuracy: 0.001)
        XCTAssertEqual(FinancialCalculator.netOwner(gross: 1000, platform: "BOOKING", realCommission: 0), 1000, accuracy: 0.001)
    }

    // MARK: FinanceStats

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Int64 { utcMillis(year: y, month: m, day: d, hour: h) }

    private func r(_ id: String, _ platform: String, _ gross: Double?, checkIn: Int64 = 0, pid: String = "p1") -> FinReservation {
        FinReservation(id: id, propertyId: pid, guestName: nil, checkIn: checkIn, checkOut: checkIn + 1, platform: platform, grossAmount: gross)
    }

    func testTotalsUseNetOfPlatform() {
        let t = FinanceStats.totals(reservations: [r("1", "BOOKING", 1000), r("2", "AIRBNB", 1000), r("3", "MANUAL", nil)],
                                    expenses: [Expense(amount: 100)])
        XCTAssertEqual(t.gross, 2000, accuracy: 0.001)
        XCTAssertEqual(t.netOwner, 762 + 825, accuracy: 0.001)
        XCTAssertEqual(t.expenses, 100, accuracy: 0.001)
        XCTAssertEqual(t.balance, 1487, accuracy: 0.001)
    }

    func testReservationsWithoutAmountCountZero() {
        XCTAssertEqual(FinanceStats.totals(reservations: [r("1", "BOOKING", nil)], expenses: []).netOwner, 0)
    }

    func testTotalsUseTheRealCommissionWhenKnown() {
        var booking = r("1", "BOOKING", 1000)
        booking.commissionAmount = 180
        XCTAssertEqual(FinanceStats.totals(reservations: [booking], expenses: []).netOwner, 820, accuracy: 0.001)
    }

    func testPerPropertySortedByBalance() {
        let a = Property(id: "p1", name: "A"), b = Property(id: "p2", name: "B")
        let out = FinanceStats.perProperty(reservations: [r("1", "MANUAL", 100, pid: "p1"), r("2", "MANUAL", 500, pid: "p2")],
                                           expenses: [], properties: [a, b])
        XCTAssertEqual(out.map(\.property.id), ["p2", "p1"])
        XCTAssertEqual(out[0].netOwner, 500, accuracy: 0.001)
        XCTAssertEqual(out[0].reservationCount, 1)
    }

    func testPerPlatformSortedByGross() {
        let out = FinanceStats.perPlatform([r("1", "AIRBNB", 100), r("2", "BOOKING", 300), r("3", "BOOKING", nil)])
        XCTAssertEqual(out, [
            FinanceStats.PlatformTotal(platform: "BOOKING", gross: 300), FinanceStats.PlatformTotal(platform: "AIRBNB", gross: 100),
        ])
    }

    func testMonthlyBucketsRevenueByCheckInAndExpensesByTimestamp() {
        let now = utc(2026, 8, 6)
        let out = FinanceStats.monthly(reservations: [r("1", "MANUAL", 100, checkIn: now)],
                                       expenses: [Expense(amount: 7, timestamp: now)], monthCount: 3, now: now)
        XCTAssertEqual(out.map(\.label), ["giu", "lug", "ago"])
        XCTAssertEqual(out.last?.revenue ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(out.last?.expenses ?? -1, 7, accuracy: 0.001)
        XCTAssertEqual(out.first?.revenue, 0)
    }

    // MARK: Periodi

    func testPeriodRanges() {
        let now = utc(2026, 10, 17, 0)
        XCTAssertEqual(FinancePeriod.thisMonth.range(now: now), utc(2026, 10, 1, 0) ..< utc(2026, 11, 1, 0))
        XCTAssertEqual(FinancePeriod.lastMonth.range(now: now), utc(2026, 9, 1, 0) ..< utc(2026, 10, 1, 0))
        XCTAssertEqual(FinancePeriod.last12Months.range(now: now), utc(2025, 11, 1, 0) ..< utc(2026, 11, 1, 0))
        XCTAssertEqual(FinancePeriod.thisYear.range(now: now), utc(2026, 1, 1, 0) ..< utc(2027, 1, 1, 0))
        XCTAssertEqual(FinancePeriod.lastYear.range(now: now), utc(2025, 1, 1, 0) ..< utc(2026, 1, 1, 0))
        XCTAssertNil(FinancePeriod.all.range(now: now))
    }

    // MARK: Categorie di spesa

    func testExpenseCategoryInference() {
        XCTAssertEqual(ExpenseCategory.infer("Spesa fissa biancheria (Mario)"), .pulizie)
        XCTAssertEqual(ExpenseCategory.infer("Bolletta Enel luce"), .utenze)
        XCTAssertEqual(ExpenseCategory.infer("Elettricista per presa"), .manutenzione)
        XCTAssertEqual(ExpenseCategory.infer("Carta igienica e sapone"), .forniture)
        XCTAssertEqual(ExpenseCategory.infer("Tassa di soggiorno"), .tasse)
        XCTAssertEqual(ExpenseCategory.infer("Sanitari nuovi"), .altro) // "tari" non scatta dentro "sanitari"
        XCTAssertEqual(ExpenseCategory.of(Expense(description: "qualcosa", category: "marketing")), .marketing)
    }

    func testExpenseCategoryKeysAreStable() {
        XCTAssertEqual(ExpenseCategory.allCases.map(\.key), ["cleaning", "utilities", "maintenance", "supplies", "taxes", "furniture", "marketing", "other"])
        XCTAssertNil(ExpenseCategory.fromKey("boh"))
    }

    // MARK: Suggerimenti

    func testInsightsFireOnlyWhenJustified() {
        let day = millisPerDay
        let many = (1 ... 6).map { i in
            FinReservation(id: "r\(i)", propertyId: "p1", checkIn: utc(2026, 4, i * 4, 0), checkOut: utc(2026, 4, i * 4, 0) + day,
                           platform: "BOOKING", adults: 2, guestCountry: "de", grossAmount: 100)
        }
        let april = utc(2026, 4, 1, 0) ..< utc(2026, 5, 1, 0)
        let s = BookingStats.compute(reservations: many, range: april, houseCount: 1, now: utc(2026, 4, 30, 0))
        let insights = FinanceInsights.compute(stats: s, expensesByCategory: [.utenze: 400, .pulizie: 100], netRevenue: 600)
        let titles = insights.map(\.title)
        XCTAssertTrue(titles.contains { $0.hasPrefix("Commissioni") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("Molti soggiorni di una notte") })
        XCTAssertTrue(titles.contains { $0.contains("tedesco") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("Utenze") })
        // Nessun dato di cancellazioni o anticipo: niente suggerimenti su quelli.
        XCTAssertFalse(titles.contains { $0.hasPrefix("Cancellazioni") || $0.hasPrefix("Prenotano") })
        XCTAssertEqual(insights.map(\.priority), insights.map(\.priority).sorted(by: >))
    }

    func testEuroAndPercentFormatting() {
        XCTAssertEqual(FinanceInsights.euro(1234.4), "€1.234")
        XCTAssertEqual(FinanceInsights.euro(999.5), "€1.000")
        XCTAssertEqual(FinanceInsights.euro(1_234_567), "€1.234.567")
        XCTAssertEqual(FinanceInsights.euro(0), "€0")
        XCTAssertEqual(FinanceInsights.pct(0.256), "26%")
        XCTAssertEqual(FinanceInsights.pct(0.5), "50%")
    }

    // MARK: Intervalli, spese orfane, spese fisse

    func testDateRangesOverlap() {
        XCTAssertTrue(dateRangesOverlap(10, 15, 12, 20))
        XCTAssertFalse(dateRangesOverlap(10, 15, 15, 20)) // intervalli semiaperti, come DTEND in iCal
        XCTAssertFalse(dateRangesOverlap(10, 15, 20, 25))
        XCTAssertTrue(dateRangesOverlap(10, 20, 12, 15))
    }

    private func expense(_ id: String, _ reservationId: String? = nil) -> Expense {
        Expense(id: id, propertyId: "p1", reservationId: reservationId, description: "x", amount: 20)
    }

    func testOrphanExpenses() {
        XCTAssertEqual(orphanExpenseIds([expense("e1", "r-gone"), expense("e2", "r1")], reservationIds: ["r1"]), ["e1"])
        XCTAssertTrue(orphanExpenseIds([expense("e1", nil), expense("e2", "")], reservationIds: ["r1"]).isEmpty)
        XCTAssertEqual(orphanExpenseIds([expense("e1", "r1"), expense("e2", nil)], reservationIds: []), ["e1"])
    }

    private let rent = RecurringExpense(id: "r1", propertyId: "p1", description: "Affitto", amount: 500, startMonth: "2026-08")

    func testRecurringGeneratesOneExpensePerMonthUpToCurrent() {
        let due = RecurringExpenses.dueExpenses(recurring: [rent], existingExpenseIds: [], now: utc(2026, 10, 13, 10))
        XCTAssertEqual(due.map(\.id), ["rec_r1_2026-08", "rec_r1_2026-09", "rec_r1_2026-10"])
        XCTAssertTrue(due.allSatisfy { $0.amount == 500 && $0.propertyId == "p1" && $0.authorId == "SYSTEM" })
        XCTAssertEqual(due[0].description, "Affitto (fissa)")
    }

    func testRecurringSkipsMonthsAlreadyGenerated() {
        let due = RecurringExpenses.dueExpenses(recurring: [rent], existingExpenseIds: ["rec_r1_2026-08", "rec_r1_2026-09"], now: utc(2026, 10, 13, 10))
        XCTAssertEqual(due.map(\.id), ["rec_r1_2026-10"])
    }

    func testRecurringNothingBeforeStartMonthAndAcrossYears() {
        XCTAssertTrue(RecurringExpenses.dueExpenses(recurring: [rent], existingExpenseIds: [], now: utc(2026, 7, 31, 10)).isEmpty)
        var nov = rent
        nov.startMonth = "2026-11"
        let due = RecurringExpenses.dueExpenses(recurring: [nov], existingExpenseIds: [], now: utc(2027, 1, 2, 10))
        XCTAssertEqual(due.map(\.id), ["rec_r1_2026-11", "rec_r1_2026-12", "rec_r1_2027-01"])
    }

    func testRecurringIgnoresInvalidDefinitions() {
        var a = rent; a.id = "a"; a.startMonth = "boh"
        var b = rent; b.id = "b"; b.startMonth = "2026-13"
        var c = rent; c.id = "c"; c.amount = 0
        var d = rent; d.id = ""
        XCTAssertTrue(RecurringExpenses.dueExpenses(recurring: [a, b, c, d], existingExpenseIds: [], now: utc(2026, 10, 1, 10)).isEmpty)
    }

    func testRecurringTimestampFallsInsideItsMonth() throws {
        let due = try XCTUnwrap(RecurringExpenses.dueExpenses(recurring: [rent], existingExpenseIds: [], now: utc(2026, 8, 20, 10)).first)
        XCTAssertEqual(RecurringExpenses.monthKey(due.timestamp), "2026-08")
    }
}
