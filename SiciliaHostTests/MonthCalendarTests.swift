import XCTest
@testable import SiciliaHost

// Specifica: MonthCalendarLogicTest dell'Android (calendario a mesi dell'Agenda).
final class MonthCalendarTests: XCTestCase {
    private func romeMs(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return millisFromDate(calendar.date(from: DateComponents(year: y, month: m, day: d))!)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Int { MonthCalendar.epochDay(year: y, month: m, day: d) }

    private func res(
        _ id: String, _ from: (Int, Int, Int), _ to: (Int, Int, Int), name: String? = "Ospite",
        adults: Int = 2, children: Int = 0, platform: String = "MANUAL"
    ) -> Reservation {
        Reservation(
            id: id, propertyId: "p", guestName: name,
            checkIn: romeMs(from.0, from.1, from.2), checkOut: romeMs(to.0, to.1, to.2),
            platform: platform, adults: adults, children: children
        )
    }

    private var nov: [[Int?]] { MonthCalendar.monthWeeks(year: 2026, month: 11) }

    func testWeeksStartOnMondayAndHaveSevenCells() {
        // Novembre 2026: il 1 è domenica, quindi la prima riga ha solo la domenica; il 30 è lunedì.
        XCTAssertEqual(nov.count, 6)
        XCTAssertTrue(nov.allSatisfy { $0.count == 7 })
        XCTAssertEqual(nov[0], [nil, nil, nil, nil, nil, nil, day(2026, 11, 1)])
        XCTAssertEqual(nov[1][0], day(2026, 11, 2))
        XCTAssertEqual(nov[5][0], day(2026, 11, 30))
        XCTAssertTrue(nov[5].dropFirst().allSatisfy { $0 == nil })
    }

    func testAMonthThatFitsFourWeeksHasNoEmptyTrailingRow() {
        // Febbraio 2027 comincia di lunedì e ha 28 giorni.
        XCTAssertEqual(MonthCalendar.monthWeeks(year: 2027, month: 2).count, 4)
    }

    func testIsoOfADay() {
        XCTAssertEqual(MonthCalendar.iso(day(2026, 11, 21)), "2026-11-21")
        XCTAssertEqual(MonthCalendar.iso(day(2027, 1, 5)), "2027-01-05")
    }

    func testAStayInsideOneWeekIsASingleRoundedBar() {
        let bars = MonthCalendar.weekBars(week: nov[2], reservations: [res("a", (2026, 11, 11), (2026, 11, 15))]) // 9..15
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(bars[0].x0, 2.5, accuracy: 0.001) // mercoledì 11 = colonna 2
        XCTAssertEqual(bars[0].x1, 6.5, accuracy: 0.001) // domenica 15 = colonna 6
        XCTAssertTrue(bars[0].roundStart && bars[0].roundEnd)
        XCTAssertEqual(bars[0].lane, 0)
    }

    func testAStayAcrossTwoWeeksIsCutFlatAtTheRowEdges() {
        let stay = [res("a", (2026, 11, 13), (2026, 11, 18))]
        let first = MonthCalendar.weekBars(week: nov[2], reservations: stay)[0] // 9..15
        XCTAssertEqual(first.x0, 4.5, accuracy: 0.001)
        XCTAssertEqual(first.x1, 7, accuracy: 0.001)
        XCTAssertTrue(first.roundStart)
        XCTAssertFalse(first.roundEnd)
        let second = MonthCalendar.weekBars(week: nov[3], reservations: stay)[0] // 16..22
        XCTAssertEqual(second.x0, 0, accuracy: 0.001)
        XCTAssertEqual(second.x1, 2.5, accuracy: 0.001)
        XCTAssertFalse(second.roundStart)
        XCTAssertTrue(second.roundEnd)
    }

    func testAStayAcrossTwoMonthsContinuesInTheNextMonthsRows() {
        // Dal 29 ottobre al 3 novembre: la prima riga di novembre ha solo la domenica 1 (barra dritta ai due lati).
        let stay = [res("a", (2026, 10, 29), (2026, 11, 3))]
        let bar = MonthCalendar.weekBars(week: nov[0], reservations: stay)[0]
        XCTAssertEqual(bar.x0, 6, accuracy: 0.001)
        XCTAssertEqual(bar.x1, 7, accuracy: 0.001)
        XCTAssertFalse(bar.roundStart)
        XCTAssertFalse(bar.roundEnd)
        let next = MonthCalendar.weekBars(week: nov[1], reservations: stay)[0] // 2..8
        XCTAssertEqual(next.x0, 0, accuracy: 0.001)
        XCTAssertEqual(next.x1, 1.5, accuracy: 0.001)
        XCTAssertTrue(next.roundEnd)
    }

    func testBackToBackStaysTouchOnTheSameLane() {
        let bars = MonthCalendar.weekBars(
            week: nov[2], reservations: [res("a", (2026, 11, 9), (2026, 11, 12)), res("b", (2026, 11, 12), (2026, 11, 15))]
        )
        XCTAssertEqual(bars.map(\.lane), [0, 0])
        XCTAssertEqual(bars[0].x1, bars[1].x0, accuracy: 0.001)
    }

    func testOverlappingStaysGoOnDifferentLanes() {
        let bars = MonthCalendar.weekBars(
            week: nov[2], reservations: [res("a", (2026, 11, 10), (2026, 11, 14)), res("b", (2026, 11, 12), (2026, 11, 15))]
        )
        XCTAssertEqual(bars.map(\.lane), [0, 1])
        XCTAssertEqual(MonthCalendar.laneCount(bars), 2)
        XCTAssertEqual(MonthCalendar.laneCount([]), 1)
    }

    func testICalDaysAtUTCMidnightAndRomeMidnightLandOnTheSameDay() {
        let ical = Reservation(
            id: "i", propertyId: "p", checkIn: utcMillis(year: 2026, month: 11, day: 11),
            checkOut: utcMillis(year: 2026, month: 11, day: 15), platform: "AIRBNB"
        )
        let manual = res("m", (2026, 11, 11), (2026, 11, 15))
        XCTAssertEqual(
            MonthCalendar.weekBars(week: nov[2], reservations: [ical])[0].x0,
            MonthCalendar.weekBars(week: nov[2], reservations: [manual])[0].x0, accuracy: 0.001
        )
    }

    func testEmptyOrReversedStaysAndAWeekWithoutTheStayGiveNoBars() {
        XCTAssertTrue(MonthCalendar.weekBars(
            week: nov[2], reservations: [res("a", (2026, 11, 12), (2026, 11, 12)), res("b", (2026, 11, 14), (2026, 11, 12))]
        ).isEmpty)
        XCTAssertTrue(MonthCalendar.weekBars(week: nov[2], reservations: [res("c", (2026, 12, 1), (2026, 12, 3))]).isEmpty)
    }

    func testDaysTouchedByABarHideTheirPrice() {
        let bars = MonthCalendar.weekBars(week: nov[2], reservations: [res("a", (2026, 11, 11), (2026, 11, 13))])
        XCTAssertEqual(
            MonthCalendar.daysTouched(week: nov[2], bars: bars),
            [day(2026, 11, 11), day(2026, 11, 12), day(2026, 11, 13)]
        )
    }

    func testLabelsShowNameAndTheOtherGuests() {
        XCTAssertEqual(MonthCalendar.stayLabel(res("a", (2026, 11, 1), (2026, 11, 2), name: "Elke", adults: 2, children: 1)), "Elke + 2")
        XCTAssertEqual(MonthCalendar.stayLabel(res("a", (2026, 11, 1), (2026, 11, 2), name: "Elke", adults: 1)), "Elke")
        XCTAssertEqual(MonthCalendar.stayLabel(res("a", (2026, 11, 1), (2026, 11, 2), name: "Elke", adults: 0)), "Elke")
        XCTAssertEqual(MonthCalendar.stayLabel(res("a", (2026, 11, 1), (2026, 11, 2), name: nil, adults: 0, platform: "BOOKING")), "Booking")
        XCTAssertEqual(MonthCalendar.stayLabel(res("a", (2026, 11, 1), (2026, 11, 2), name: "  ", adults: 0, platform: "AIRBNB")), "Airbnb")
        XCTAssertEqual(MonthCalendar.stayLabel(res("blocco-x", (2026, 11, 1), (2026, 11, 2), name: nil, adults: 0)), "Date bloccate")
        XCTAssertEqual(MonthCalendar.stayInitial(res("a", (2026, 11, 1), (2026, 11, 2), name: "elke")), "E")
        XCTAssertEqual(MonthCalendar.stayInitial(res("a", (2026, 11, 1), (2026, 11, 2), name: nil, platform: "BOOKING")), "B")
    }

    func testPriceIsTheSeasonalRateCoveringTheDayOrElseTheBasePrice() {
        let rates = [SeasonalRateEntry(startDate: "2026-11-21", endDate: "2026-11-25", pricePerNight: 166)]
        XCTAssertEqual(MonthCalendar.nightlyPrice(day: day(2026, 11, 21), base: 100, rates: rates), 166)
        XCTAssertEqual(MonthCalendar.nightlyPrice(day: day(2026, 11, 25), base: 100, rates: rates), 166)
        XCTAssertEqual(MonthCalendar.nightlyPrice(day: day(2026, 11, 26), base: 100, rates: rates), 100)
        XCTAssertNil(MonthCalendar.nightlyPrice(day: day(2026, 11, 26), base: nil, rates: rates))
    }

    func testDiscountLabelPrefersTheBiggestPercentageAndFallsBackToAFixedAmount() {
        let promos = [
            PromoEntry(id: "1", startDate: "2026-11-09", endDate: "2026-11-20", discountType: "percentage", discountValue: 20),
            PromoEntry(id: "2", startDate: "2026-11-10", endDate: "2026-11-16", discountType: "percentage", discountValue: 40),
            PromoEntry(id: "3", startDate: "2026-11-30", endDate: "2026-11-30", discountType: "fixed", discountValue: 10),
        ]
        XCTAssertEqual(MonthCalendar.discountLabel(day: day(2026, 11, 12), promotions: promos), "40% di sconto")
        XCTAssertEqual(MonthCalendar.discountLabel(day: day(2026, 11, 18), promotions: promos), "20% di sconto")
        XCTAssertEqual(MonthCalendar.discountLabel(day: day(2026, 11, 30), promotions: promos), "−10 € a notte")
        XCTAssertNil(MonthCalendar.discountLabel(day: day(2026, 11, 25), promotions: promos))
    }

    func testEuroFormatUsesTheCommaForCents() {
        XCTAssertEqual(MonthCalendar.formatEuro(100), "100 €")
        XCTAssertEqual(MonthCalendar.formatEuro(166.5), "166,50 €")
    }
}
