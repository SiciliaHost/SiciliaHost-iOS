import XCTest
@testable import SiciliaHost

// Specifica: FinanceListKeysTest dell'app Android, più `buildFinanceView` e le azioni pure delle Finanze.
final class FinanceViewTests: XCTestCase {
    // MARK: FinanceListKeysTest

    func testTheSamePropertyHasADifferentKeyInEachSection() {
        let keys = [FinanceListKeys.propertyDetail("p1"), FinanceListKeys.recurring("p1")]
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testSectionsNeverCollideEvenWhenIdsAreEqual() {
        let id = "abc123"
        let keys = [FinanceListKeys.propertyDetail(id), FinanceListKeys.recurring(id),
                    FinanceListKeys.pendingReservation(id), FinanceListKeys.expense(id, index: 0)]
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testExpensesWithoutAnIdGetADistinctKeyEach() {
        XCTAssertNotEqual(FinanceListKeys.expense("", index: 0), FinanceListKeys.expense("", index: 1))
        XCTAssertEqual(FinanceListKeys.expense("e1", index: 5), "exp-e1")
    }

    func testARealisticListHasNoDuplicateKeys() {
        let ids = ["p1", "p2"]
        let keys = ids.map(FinanceListKeys.propertyDetail) + ids.map(FinanceListKeys.recurring)
            + ["r1", "r2"].map(FinanceListKeys.pendingReservation)
            + ["e1", "", ""].enumerated().map { FinanceListKeys.expense($0.element, index: $0.offset) }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: buildFinanceView

    func testViewFiltersByHouseAndPeriodAndGroupsExpenses() {
        let now = utcMillis(year: 2026, month: 8, day: 15)
        let houses = [Property(id: "p1", name: "A"), Property(id: "p2", name: "B")]
        let reservations = [
            FinReservation(id: "r1", propertyId: "p1", checkIn: utcMillis(year: 2026, month: 8, day: 1),
                           checkOut: utcMillis(year: 2026, month: 8, day: 4), platform: "MANUAL", grossAmount: 300),
            FinReservation(id: "r2", propertyId: "p2", checkIn: utcMillis(year: 2026, month: 8, day: 2),
                           checkOut: utcMillis(year: 2026, month: 8, day: 3), platform: "MANUAL", grossAmount: 100),
            FinReservation(id: "r3", propertyId: "p1", checkIn: utcMillis(year: 2026, month: 6, day: 1),
                           checkOut: utcMillis(year: 2026, month: 6, day: 2), platform: "MANUAL", grossAmount: 50),
        ]
        let expenses = [
            Expense(id: "e1", propertyId: "p1", description: "Biancheria", amount: 20, timestamp: utcMillis(year: 2026, month: 8, day: 2)),
            Expense(id: "e2", propertyId: "p1", description: "Bolletta luce", amount: 80, timestamp: utcMillis(year: 2026, month: 8, day: 5)),
            Expense(id: "e3", propertyId: "p2", description: "Caffè", amount: 5, timestamp: utcMillis(year: 2026, month: 8, day: 6)),
        ]
        let view = buildFinanceView(allReservations: reservations, allExpenses: expenses, properties: houses, importCounts: [:],
                                    period: .thisMonth, propertyId: "p1", now: now)
        XCTAssertEqual(view.houses.map(\.id), ["p1"])
        XCTAssertEqual(view.reservations.map(\.id), ["r1"])
        XCTAssertEqual(view.expenses.map(\.id), ["e2", "e1"]) // dalla più recente
        XCTAssertEqual(view.totals.gross, 300, accuracy: 0.001)
        XCTAssertEqual(view.totals.expenses, 100, accuracy: 0.001)
        XCTAssertEqual(view.byCategory.map(\.category), [.utenze, .pulizie])
        XCTAssertEqual(statsKpis(view, all: false).count, 4)
        XCTAssertGreaterThan(statsKpis(view, all: true).count, 4)

        let all = buildFinanceView(allReservations: reservations, allExpenses: expenses, properties: houses, importCounts: [:],
                                   period: .all, propertyId: nil, now: now)
        XCTAssertEqual(all.reservations.count, 3)
        XCTAssertEqual(all.expenses.count, 3)
    }

    func testAReservationWithoutGrossIsCountedButAddsNothingToTotals() {
        let now: Int64 = 1_800_000_000_000
        let day: Int64 = 86_400_000
        let withGross = FinReservation(id: "r1", propertyId: "p1", guestName: "Ospite r1", checkIn: now - 10 * day,
                                       checkOut: now - 8 * day, platform: "BOOKING", grossAmount: 100)
        let withoutGross = FinReservation(id: "r2", propertyId: "p1", guestName: "Ospite r2", checkIn: now - 10 * day,
                                          checkOut: now - 8 * day, platform: "BOOKING")
        let view = buildFinanceView(allReservations: [withGross, withoutGross], allExpenses: [], properties: [Property(id: "p1", name: "Casa")],
                                    importCounts: [:], period: .all, propertyId: nil, now: now)
        XCTAssertEqual(view.reservations.count, 2)
        XCTAssertEqual(view.totals, FinanceStats.totals(reservations: [withGross], expenses: []))
        XCTAssertEqual(view.totals.gross, 100, accuracy: 0.001)
        // Le statistiche reggono una prenotazione senza importo (il lordo conta solo quelle con importo).
        XCTAssertEqual(view.stats.gross, 100, accuracy: 0.001)
        XCTAssertEqual(view.stats.reservationCount, 2)
        XCTAssertFalse(statsKpis(view, all: true).isEmpty)
    }

    func testLinenExpenseAndAmountParsing() {
        let linen = FinanceActions.linenExpense(propertyId: "p1", reservationId: "r1", guest: nil)
        XCTAssertFalse(linen.id.isEmpty) // id locale: due biancherie non si sostituiscono
        XCTAssertNotEqual(linen.id, FinanceActions.linenExpense(propertyId: "p1", reservationId: "r2", guest: nil).id)
        XCTAssertEqual(linen.propertyId, "p1")
        XCTAssertEqual(linen.amount, 20)
        XCTAssertEqual(linen.reservationId, "r1")
        XCTAssertEqual(linen.authorId, "SYSTEM")
        XCTAssertEqual(linen.category, "cleaning")
        XCTAssertEqual(linen.description, "Spesa fissa biancheria (Ospite)")
        XCTAssertEqual(FinanceActions.parseAmount("12,50"), 12.5)
        XCTAssertNil(FinanceActions.parseAmount("abc"))
    }

    func testFormats() {
        XCTAssertEqual(FinanceFormat.euro0(1234.4), "€1.234")
        XCTAssertEqual(FinanceFormat.euro2(1234.5), "€1.234,50")
        XCTAssertEqual(FinanceFormat.euroPlain(-12.5), "€-12.50")
        XCTAssertEqual(FinanceFormat.pct(0.456), "46%")
        XCTAssertEqual(FinanceFormat.dec1(2.5), "2,5")
        XCTAssertEqual(FinanceFormat.number(1234567.891, decimals: 2), "1.234.567,89")
        XCTAssertEqual(FinanceFormat.number(-1234, decimals: 0), "-1.234")
        XCTAssertEqual(FinanceFormat.number(999, decimals: 0), "999")
        XCTAssertEqual(FinanceFormat.countryName("de"), "Germania")
        XCTAssertEqual(FinanceFormat.platformName("MANUAL"), "Dirette / manuali")
    }
}
