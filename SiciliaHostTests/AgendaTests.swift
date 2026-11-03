import XCTest
@testable import SiciliaHost

// Specifica: CalendarGridTest, PriceSelectionTest, GuestPricingTest dell'app Android, più la logica di Home e della
// modifica prenotazione (che sull'Android sta nei ViewModel, senza test).
final class AgendaTests: XCTestCase {
    private func d(_ s: String) -> LocalDay { LocalDay(iso: s)! }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var rome: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }

    // MARK: CalendarGridTest

    func testJuly2026HasFiveRowsWithThreeLeadingBlanks() {
        let rows = monthGridRows(daysInMonth: 31, firstDayOfWeek: 3)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0], [nil, nil, nil, 1, 2, 3, 4])
        XCTAssertEqual(rows[4], [26, 27, 28, 29, 30, 31, nil])
    }

    func testFebruary2026HasExactlyFourFullRows() {
        let rows = monthGridRows(daysInMonth: 28, firstDayOfWeek: 0)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0], [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(rows[3], [22, 23, 24, 25, 26, 27, 28])
    }

    func testEveryRowAlwaysHasSevenCells() {
        monthGridRows(daysInMonth: 30, firstDayOfWeek: 6).forEach { XCTAssertEqual($0.count, 7) }
    }

    func testYearMonthWeekdayMatchesAndroidConvention() {
        // 1 luglio 2026 = mercoledì (3), 1 febbraio 2026 = domenica (0).
        XCTAssertEqual(YearMonth(year: 2026, month: 7).atDay(1).weekdayFromSunday, 3)
        XCTAssertEqual(YearMonth(year: 2026, month: 2).atDay(1).weekdayFromSunday, 0)
        XCTAssertEqual(YearMonth(year: 2026, month: 13), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).plusMonths(-1), YearMonth(year: 2025, month: 12))
    }

    // MARK: Home

    func testArrivalsTodayIncludeUtcAndLocalMidnights() {
        let now = millisFromDate(rome.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 15))!)
        let iCal = Reservation(id: "a", checkIn: utcMillis(year: 2026, month: 8, day: 10)) // 02:00 a Roma
        let manual = Reservation(id: "b", checkIn: millisFromDate(rome.date(from: DateComponents(year: 2026, month: 8, day: 10))!))
        let tomorrow = Reservation(id: "c", checkIn: utcMillis(year: 2026, month: 8, day: 11))
        let yesterday = Reservation(id: "d", checkIn: utcMillis(year: 2026, month: 8, day: 9))
        let ids = AgendaLogic.arrivalsToday([iCal, manual, tomorrow, yesterday], now: now, calendar: rome).map(\.id)
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testPendingReviewAndNewManualReservation() {
        let list = [Reservation(id: "a", needsReview: true), Reservation(id: "b")]
        XCTAssertEqual(AgendaLogic.pendingReview(list).map(\.id), ["a"])

        let now = millisFromDate(rome.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 15))!)
        let created = AgendaLogic.newManualReservation(propertyId: "p1", now: now, calendar: rome)
        let midnight = millisFromDate(rome.date(from: DateComponents(year: 2026, month: 8, day: 10))!)
        XCTAssertEqual(created.propertyId, "p1")
        XCTAssertEqual(created.platform, "MANUAL")
        XCTAssertEqual(created.checkIn, midnight)
        XCTAssertEqual(created.checkOut, midnight + 86_400_000)
        XCTAssertFalse(created.needsReview)
        XCTAssertNil(created.grossAmount)
    }

    func testDayEventsAndMarks() {
        let res = Reservation(id: "a", checkIn: utcMillis(year: 2026, month: 8, day: 10), checkOut: utcMillis(year: 2026, month: 8, day: 13))
        let day10 = utcMillis(year: 2026, month: 8, day: 10, hour: 12)
        let day11 = utcMillis(year: 2026, month: 8, day: 11, hour: 12)
        let day13 = utcMillis(year: 2026, month: 8, day: 13, hour: 12)
        XCTAssertEqual(AgendaLogic.events(on: day10, in: [res], calendar: rome).count, 1)
        XCTAssertTrue(AgendaLogic.events(on: day11, in: [res], calendar: rome).isEmpty)
        XCTAssertEqual(AgendaLogic.marks(on: day10, in: [res], calendar: rome), .init(checkIns: true, checkOuts: false))
        XCTAssertEqual(AgendaLogic.marks(on: day13, in: [res], calendar: rome), .init(checkIns: false, checkOuts: true))
    }

    func testRowSubtitleShowsGuestsOnlyWhenKnown() {
        XCTAssertEqual(AgendaLogic.rowSubtitle(Reservation(platform: "AIRBNB"), propertyName: "Casa Mare"), "Casa Mare · AIRBNB")
        XCTAssertEqual(
            AgendaLogic.rowSubtitle(Reservation(platform: "BOOKING", adults: 2, children: 1), propertyName: "Casa Mare"),
            "Casa Mare · BOOKING · 3 pers."
        )
    }

    // MARK: Modifica prenotazione

    func testParseAmountAcceptsCommaAndBlank() {
        XCTAssertEqual(ReservationEditLogic.parseAmount("120"), 120)
        XCTAssertEqual(ReservationEditLogic.parseAmount("99,5"), 99.5)
        XCTAssertEqual(ReservationEditLogic.parseAmount(" 80.25 "), 80.25)
        XCTAssertNil(ReservationEditLogic.parseAmount(""))
        XCTAssertNil(ReservationEditLogic.parseAmount("abc"))
        XCTAssertEqual(ReservationEditLogic.parseCount("2a"), 2)
        XCTAssertEqual(ReservationEditLogic.parseCount(""), 0)
        XCTAssertEqual(ReservationEditLogic.amountText(nil), "")
        XCTAssertEqual(ReservationEditLogic.amountText(120), "120")
        XCTAssertEqual(ReservationEditLogic.amountText(99.5), "99.5")
    }

    func testApplyEditRecomputesNetsAndReviewFlag() {
        let current = Reservation(id: "r", propertyId: "p", guestName: "Old", checkIn: 1, checkOut: 2, platform: "MANUAL",
                                  icalUid: "uid-1", needsReview: true, guestCountry: "de")
        let edited = ReservationEditLogic.applyEdit(
            to: current, guestName: "  Anna  ", checkIn: 10, checkOut: 20, platform: "BOOKING",
            grossAmount: 100, adults: 2, children: 1, isManagedOnCommission: false
        )
        XCTAssertEqual(edited.guestName, "Anna")
        XCTAssertEqual(edited.checkIn, 10)
        XCTAssertEqual(edited.platform, "BOOKING")
        XCTAssertEqual(edited.netAmountOwner!, 76.2, accuracy: 0.0001)
        XCTAssertEqual(edited.netAmountAdmin!, 76.2, accuracy: 0.0001)
        XCTAssertFalse(edited.needsReview)
        // Campi non toccati dal modulo restano.
        XCTAssertEqual(edited.icalUid, "uid-1")
        XCTAssertEqual(edited.guestCountry, "de")

        let blank = ReservationEditLogic.applyEdit(
            to: edited, guestName: "   ", checkIn: 10, checkOut: 20, platform: "BOOKING",
            grossAmount: nil, adults: 0, children: 0, isManagedOnCommission: true
        )
        XCTAssertNil(blank.guestName)
        XCTAssertNil(blank.netAmountOwner)
        XCTAssertNil(blank.netAmountAdmin)
        XCTAssertTrue(blank.needsReview)
    }

    func testPickedDayIsUtcMidnightOfTheLocalDay() {
        let lateEvening = rome.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 23, minute: 30))!
        XCTAssertEqual(ReservationEditLogic.pickedDayMillis(lateEvening, calendar: rome), utcMillis(year: 2026, month: 8, day: 10))
    }

    // MARK: PriceSelectionTest

    func testDragRangeIsContinuousAndOrderInsensitive() {
        let forward = PriceLogic.dragRange(d("2026-08-30"), d("2026-09-02"))
        XCTAssertEqual(forward, [d("2026-08-30"), d("2026-08-31"), d("2026-09-01"), d("2026-09-02")])
        XCTAssertEqual(forward, PriceLogic.dragRange(d("2026-09-02"), d("2026-08-30")))
        XCTAssertEqual(PriceLogic.dragRange(d("2026-08-30"), d("2026-08-30")), [d("2026-08-30")])
    }

    func testToggleMonthAddsWholeMonthKeepingOtherSelections() {
        let other = d("2026-07-15")
        let august = YearMonth(year: 2026, month: 8)
        let result = PriceLogic.toggleMonth([other, d("2026-08-03")], august)
        XCTAssertEqual(result.count, 31 + 1)
        XCTAssertTrue(result.contains(other))
        XCTAssertTrue(PriceLogic.monthDates(august).isSubset(of: result))
    }

    func testToggleMonthRemovesTheMonthWhenFullySelected() {
        let other = d("2026-07-15")
        let august = YearMonth(year: 2026, month: 8)
        XCTAssertEqual(PriceLogic.toggleMonth(PriceLogic.monthDates(august).union([other]), august), [other])
    }

    func testMonthDatesHandlesFebruaryInLeapYear() {
        XCTAssertEqual(PriceLogic.monthDates(YearMonth(year: 2028, month: 2)).count, 29)
        XCTAssertEqual(PriceLogic.monthDates(YearMonth(year: 2026, month: 2)).count, 28)
    }

    func testGroupIntoRangesSplitsOnGapsAndCrossesMonths() {
        let dates = Set(["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-05", "2026-01-31", "2026-02-01"].map(d))
        XCTAssertEqual(PriceLogic.groupIntoRanges(dates), [
            IsoRange(startDate: "2026-01-01", endDate: "2026-01-03"),
            IsoRange(startDate: "2026-01-05", endDate: "2026-01-05"),
            IsoRange(startDate: "2026-01-31", endDate: "2026-02-01"),
        ])
        XCTAssertEqual(PriceLogic.groupIntoRanges([]), [])
    }

    func testPriceForDayUsesSeasonalRateInclusiveOfBothEndsElseBase() {
        let rates = [SeasonalRateEntry(startDate: "2026-08-04", endDate: "2026-08-06", pricePerNight: 150)]
        XCTAssertEqual(PriceLogic.priceForDay(d("2026-08-04"), rates: rates, basePrice: 100), DayPrice(amount: 150, isSeasonal: true))
        XCTAssertEqual(PriceLogic.priceForDay(d("2026-08-06"), rates: rates, basePrice: 100), DayPrice(amount: 150, isSeasonal: true))
        XCTAssertEqual(PriceLogic.priceForDay(d("2026-08-07"), rates: rates, basePrice: 100), DayPrice(amount: 100, isSeasonal: false))
        XCTAssertEqual(PriceLogic.priceForDay(d("2026-08-07"), rates: rates, basePrice: nil), DayPrice(amount: nil, isSeasonal: false))
    }

    func testFormatPriceDropsZeroDecimalsAndUsesComma() {
        XCTAssertEqual(PriceLogic.formatPrice(120), "120")
        XCTAssertEqual(PriceLogic.formatPrice(99.5), "99,5")
        XCTAssertEqual(PriceLogic.formatPrice(99.99), "99,99")
        XCTAssertEqual(PriceLogic.formatPrice(99.999), "100")
        XCTAssertEqual(PriceLogic.formatPrice(120.001), "120")
        XCTAssertEqual(PriceLogic.formatPrice(nil), "—")
    }

    func testParsePriceAcceptsPositiveAmountsWithTwoDecimalsAtMost() {
        XCTAssertEqual(PriceLogic.parsePrice("120"), 120)
        XCTAssertEqual(PriceLogic.parsePrice("99,5"), 99.5)
        XCTAssertEqual(PriceLogic.parsePrice(" 80 "), 80)
        XCTAssertNil(PriceLogic.parsePrice(""))
        XCTAssertNil(PriceLogic.parsePrice("0"))
        XCTAssertNil(PriceLogic.parsePrice("-5"))
        XCTAssertNil(PriceLogic.parsePrice("abc"))
        XCTAssertNil(PriceLogic.parsePrice("1e3"))
        XCTAssertNil(PriceLogic.parsePrice("1.234"))
        XCTAssertNil(PriceLogic.parsePrice("100000"))
    }

    // 7 colonne da 40 con 6 spazi da 4 → larghezza 304, passo 44.
    func testGridCellAtMapsPointsToRowAndColumn() {
        func cell(_ x: Double, _ y: Double, aspect: Double = 1) -> [Int]? {
            PriceLogic.gridCellAt(x: x, y: y, gridWidth: 304, gap: 4, rowCount: 5, cellAspect: aspect).map { [$0.row, $0.col] }
        }
        XCTAssertEqual(cell(10, 10), [0, 0])
        XCTAssertEqual(cell(50, 10), [0, 1])
        XCTAssertEqual(cell(300, 100), [2, 6])
        XCTAssertNil(cell(-1, 10))
        XCTAssertNil(cell(304, 10))
        XCTAssertNil(cell(10, 5 * 44 + 1))
        // Celle 40 × 32 (rapporto 1,25) con spazio 4: passo colonna 44, passo riga 36.
        XCTAssertEqual(cell(10, 37, aspect: 1.25), [1, 0])
        XCTAssertEqual(cell(300, 30, aspect: 1.25), [0, 6])
        XCTAssertNil(cell(10, 5 * 36 + 1, aspect: 1.25))
    }

    func testIsNightBookedCoversCheckInUpToButNotIncludingCheckOut() {
        let res = Reservation(propertyId: "p1", checkIn: utcMillis(year: 2026, month: 8, day: 10), checkOut: utcMillis(year: 2026, month: 8, day: 13))
        XCTAssertFalse(PriceLogic.isNightBooked(d("2026-08-09"), propertyId: "p1", reservations: [res], calendar: utc))
        XCTAssertTrue(PriceLogic.isNightBooked(d("2026-08-10"), propertyId: "p1", reservations: [res], calendar: utc))
        XCTAssertTrue(PriceLogic.isNightBooked(d("2026-08-12"), propertyId: "p1", reservations: [res], calendar: utc))
        XCTAssertFalse(PriceLogic.isNightBooked(d("2026-08-13"), propertyId: "p1", reservations: [res], calendar: utc))
        XCTAssertFalse(PriceLogic.isNightBooked(d("2026-08-11"), propertyId: "other", reservations: [res], calendar: utc))
    }

    func testLocalDayParsesOnlyValidIsoDates() {
        XCTAssertEqual(LocalDay(iso: "2026-08-04")?.iso, "2026-08-04")
        XCTAssertNil(LocalDay(iso: "2026-02-31"))
        XCTAssertNil(LocalDay(iso: "agosto"))
        XCTAssertEqual(d("2026-12-31").plusDays(1), d("2027-01-01"))
    }

    // MARK: GuestPricingTest

    private func promo(_ type: String, _ value: Double, _ start: String = "2026-08-01", _ end: String = "2026-08-31") -> PromoEntry {
        PromoEntry(id: "x", startDate: start, endDate: end, discountType: type, discountValue: value)
    }

    func testParseExtraAcceptsZeroAndTwoDecimalsRejectsTheRest() {
        XCTAssertEqual(PriceLogic.parseExtra("10"), 10)
        XCTAssertEqual(PriceLogic.parseExtra("10,5"), 10.5)
        XCTAssertEqual(PriceLogic.parseExtra("0"), 0)
        XCTAssertNil(PriceLogic.parseExtra(""))
        XCTAssertNil(PriceLogic.parseExtra("abc"))
        XCTAssertNil(PriceLogic.parseExtra("1,234"))
        XCTAssertNil(PriceLogic.parseExtra("-3"))
        XCTAssertNil(PriceLogic.parseExtra("10001"))
    }

    func testParsePromoValuePercentageIsInOneToHundredFixedIsPositive() {
        XCTAssertEqual(PriceLogic.parsePromoValue(discountType: "percentage", "20"), 20)
        XCTAssertNil(PriceLogic.parsePromoValue(discountType: "percentage", "0"))
        XCTAssertNil(PriceLogic.parsePromoValue(discountType: "percentage", "101"))
        XCTAssertEqual(PriceLogic.parsePromoValue(discountType: "fixed", "15,5"), 15.5)
        XCTAssertNil(PriceLogic.parsePromoValue(discountType: "fixed", "0"))
        XCTAssertNil(PriceLogic.parsePromoValue(discountType: "fixed", "x"))
    }

    func testDiscountedPricePercentageAndFixedNeverBelowZero() {
        XCTAssertEqual(PriceLogic.discountedPrice(100, promo("percentage", 20)), 80, accuracy: 0.001)
        XCTAssertEqual(PriceLogic.discountedPrice(100, promo("fixed", 30)), 70, accuracy: 0.001)
        XCTAssertEqual(PriceLogic.discountedPrice(20, promo("fixed", 30)), 0, accuracy: 0.001)
        XCTAssertEqual(PriceLogic.discountedPrice(99.99, promo("percentage", 15)), 84.99, accuracy: 0.001)
    }

    func testPromoPriceForDayPicksTheCheapestInsideTheWindow() {
        let promos = [promo("percentage", 10), promo("fixed", 35, "2026-08-10", "2026-08-20")]
        XCTAssertEqual(PriceLogic.promoPriceForDay(d("2026-08-05"), price: 100, promos: promos)!, 90, accuracy: 0.001)
        XCTAssertEqual(PriceLogic.promoPriceForDay(d("2026-08-15"), price: 100, promos: promos)!, 65, accuracy: 0.001)
        XCTAssertNil(PriceLogic.promoPriceForDay(d("2026-09-01"), price: 100, promos: promos))
        XCTAssertNil(PriceLogic.promoPriceForDay(d("2026-08-05"), price: nil, promos: promos))
    }

    func testToSurchargeMapKeepsOnlyValidPositiveEntries() {
        XCTAssertEqual(PriceLogic.toSurchargeMap(["3": 10, "4": 0, "x": 5, "1": 7]), [3: 10])
        XCTAssertEqual(PriceLogic.toSurchargeMap(nil), [:])
    }

    func testFormatPromoRangeAndDiscount() {
        XCTAssertEqual(PriceLogic.formatPromoRange(promo("percentage", 20)), "01/08/2026 – 31/08/2026")
        XCTAssertEqual(PriceLogic.formatPromoRange(promo("percentage", 20, "2026-08-05", "2026-08-05")), "05/08/2026")
        XCTAssertEqual(PriceLogic.formatDiscount(promo("percentage", 20)), "−20%")
        XCTAssertEqual(PriceLogic.formatDiscount(promo("fixed", 15.5)), "−€15,5")
    }

    func testMergeSurchargesAddsReplacesAndRemoves() {
        let base: [Int: Double] = [3: 10]
        XCTAssertEqual(PriceLogic.mergeSurcharges(base, guests: 4, value: 15), [3: 10, 4: 15])
        XCTAssertEqual(PriceLogic.mergeSurcharges(base, guests: 3, value: 12), [3: 12])
        XCTAssertEqual(PriceLogic.mergeSurcharges(base, guests: 3, value: 0), [:])
        XCTAssertEqual(PriceLogic.mergeSurcharges(base, guests: 5, value: 0), base)
        XCTAssertEqual(base, [3: 10])
    }

    func testSurchargesToRawRoundTripsWithToSurchargeMap() {
        let m: [Int: Double] = [2: 5, 4: 7.5]
        XCTAssertEqual(PriceLogic.surchargesToRaw(m), ["2": 5, "4": 7.5])
        XCTAssertEqual(PriceLogic.toSurchargeMap(PriceLogic.surchargesToRaw(m)), m)
    }
}
