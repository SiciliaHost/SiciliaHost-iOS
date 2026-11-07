import XCTest
@testable import SiciliaHost

// Specifica: i casi «echo_*» di ICalSyncWorkerTest (stessi di reservationSyncPlan.test.ts del sito) e la logica del
// promemoria Excel (BookingExcelReminderWorker).
final class BackgroundSyncTests: XCTestCase {
    private func day(_ d: Int) -> Int64 { utcMillis(year: 2026, month: 8, day: d) }

    private var rome: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private func romeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        return rome.date(from: c)!
    }

    private func romeMidnight(_ d: Int) -> Int64 { millisFromDate(romeDate(2026, 8, d)) }

    private func ev(_ uid: String, _ from: Int, _ to: Int) -> ICalSync.ParsedEvent {
        ICalSync.ParsedEvent(uid: uid, summary: "CLOSED - Not available", checkIn: day(from), checkOut: day(to))
    }

    private func booking(_ id: String, _ from: Int, _ to: Int, name: String? = nil) -> Reservation {
        Reservation(id: id, propertyId: "p1", guestName: name, checkIn: day(from), checkOut: day(to), platform: "BOOKING",
                    icalUid: id)
    }

    private var airbnb: Reservation {
        Reservation(id: "a1@airbnb.com", propertyId: "p1", guestName: "Reserved", checkIn: day(1), checkOut: day(5),
                    platform: "AIRBNB", icalUid: "a1@airbnb.com")
    }

    private func manual(_ id: String, _ from: Int, _ to: Int) -> Reservation {
        Reservation(id: id, propertyId: "p1", guestName: "Rossi", checkIn: romeMidnight(from), checkOut: romeMidnight(to),
                    platform: "MANUAL")
    }

    private func plan(_ events: [ICalSync.ParsedEvent], _ existing: [Reservation], _ others: [Reservation], now: Int64 = 0) -> ICalSync.Plan {
        ICalSync.buildSyncPlan(events: events, propertyId: "p1", platform: "BOOKING", existingFutureReservations: existing,
                               otherFutureReservations: others, now: now)
    }

    func testBookingClosureWithTheExactNightsOfAnAirbnbReservationIsNotImported() {
        let p = plan([ev("echo@booking.com", 1, 5), ev("real@booking.com", 10, 12)], [], [airbnb])
        XCTAssertEqual(p.toUpsert.map(\.icalUid), ["real@booking.com"])
        XCTAssertEqual(p.echoes, 1)
    }

    func testEchoRecognisedAgainstAReservationWrittenAtRomeMidnight() {
        let p = plan([ev("echo@booking.com", 3, 6)], [], [manual("blocco-1", 3, 6)])
        XCTAssertTrue(p.toUpsert.isEmpty)
        XCTAssertEqual(p.echoes, 1)
    }

    func testClosureSpanningTwoBackToBackForeignReservations() {
        XCTAssertTrue(plan([ev("echo@booking.com", 1, 9)], [], [airbnb, manual("m1", 5, 9)]).toUpsert.isEmpty)
    }

    func testPartialOverlapAndTurnoverDayAreStillImported() {
        let partial = plan([ev("real@booking.com", 4, 7)], [], [airbnb])
        XCTAssertEqual(partial.toUpsert.map(\.icalUid), ["real@booking.com"])
        XCTAssertEqual(partial.echoes, 0)
        XCTAssertEqual(plan([ev("real@booking.com", 5, 8)], [], [airbnb]).toUpsert.count, 1)
    }

    func testUntouchedPlaceholderTurnedEchoIsDeleted() {
        let placeholder = booking("echo@booking.com", 1, 5)
        let p = plan([ev("echo@booking.com", 1, 5)], [placeholder], [airbnb])
        XCTAssertEqual(p.toDelete, [placeholder])
        XCTAssertTrue(p.toUpsert.isEmpty)
    }

    func testCompletedPlaceholderAndExcelReservationAreKept() {
        let withName = booking("n@booking.com", 1, 5, name: "Bianchi")
        let excel = booking("booking-xls-7", 1, 5)
        XCTAssertTrue(plan([ev("echo@booking.com", 1, 5)], [withName, excel], [airbnb]).toDelete.isEmpty)
    }

    func testUntouchedPlaceholderIsAnIcalBookingWithoutName() {
        // L'importo non è più sul server: il segnaposto mai toccato è quello iCal senza nome.
        XCTAssertTrue(ICalSync.isUntouchedPlaceholder(booking("x@booking.com", 1, 5)))
        XCTAssertTrue(ICalSync.isUntouchedPlaceholder(booking("x@booking.com", 1, 5, name: "   ")))
        XCTAssertFalse(ICalSync.isUntouchedPlaceholder(booking("x@booking.com", 1, 5, name: "Bianchi")))
        XCTAssertFalse(ICalSync.isUntouchedPlaceholder(booking("booking-xls-7", 1, 5)))
        var noUid = booking("m1", 1, 5)
        noUid.icalUid = nil
        XCTAssertFalse(ICalSync.isUntouchedPlaceholder(noUid))
    }

    func testCreatedReservationsCarryNoReviewFlagOrMoney() {
        let bookingPlan = plan([ev("real@booking.com", 10, 12)], [], [])
        let airbnbPlan = ICalSync.buildSyncPlan(
            events: [ICalSync.ParsedEvent(uid: "r@airbnb.com", summary: "Reserved", checkIn: day(1), checkOut: day(5))],
            propertyId: "p1", platform: "AIRBNB", existingFutureReservations: []
        )
        let created = bookingPlan.toUpsert + airbnbPlan.toUpsert
        XCTAssertEqual(created.count, 2)
        for r in created {
            for key in ["needsReview", "grossAmount", "netAmountOwner", "netAmountAdmin"] {
                XCTAssertNil(r.firestoreData[key], key)
            }
        }
    }

    func testEventStrictlyInsideALongerForeignStayIsImportedAndItsPlaceholderKept() {
        var long = airbnb
        long.id = "long@airbnb.com"
        long.icalUid = "long@airbnb.com"
        long.checkOut = day(10)
        let p = plan([ev("inside@booking.com", 3, 5)], [], [long])
        XCTAssertEqual(p.toUpsert.map(\.icalUid), ["inside@booking.com"])
        XCTAssertEqual(p.echoes, 0)
        let placeholder = booking("inside@booking.com", 3, 5)
        XCTAssertTrue(plan([ev("inside@booking.com", 3, 5)], [placeholder], [long]).toDelete.isEmpty)
    }

    func testNothingIsCreatedFromAPastEvent() {
        let p = plan([ev("echo@booking.com", 1, 5), ev("real@booking.com", 10, 12)], [], [], now: day(6))
        XCTAssertEqual(p.toUpsert.map(\.icalUid), ["real@booking.com"])
    }

    func testIdenticalDatesInTheSameFeedAreImportedOnce() {
        let p = plan([ev("a@booking.com", 10, 12), ev("b@booking.com", 10, 12)], [], [])
        XCTAssertEqual(p.toUpsert.map(\.icalUid), ["a@booking.com"])
    }

    func testNeverCreatesAndDeletesTheSameIdTogether() {
        let placeholder = booking("x@booking.com", 1, 5)
        let p = plan([ev("x@booking.com", 2, 7)], [placeholder], [airbnb])
        let deleted = Set(p.toDelete.map(\.icalUid))
        XCTAssertTrue(p.toUpsert.allSatisfy { !deleted.contains($0.icalUid) })
    }

    func testAirbnbIgnoresTheOtherPlatforms() {
        let events = [
            ICalSync.ParsedEvent(uid: "real-booking-1@airbnb.com", summary: "Reserved", checkIn: day(1), checkOut: day(5)),
            ICalSync.ParsedEvent(uid: "blocked-1@airbnb.com", summary: "Airbnb (Not available)", checkIn: day(10), checkOut: day(12)),
        ]
        let p = ICalSync.buildSyncPlan(events: events, propertyId: "p1", platform: "AIRBNB", existingFutureReservations: [],
                                       otherFutureReservations: [manual("m", 1, 5)])
        XCTAssertEqual(p.toUpsert.map(\.icalUid), ["real-booking-1@airbnb.com"])
        XCTAssertEqual(p.echoes, 0)
    }

    func testRomeDayTreatsUtcAndRomeMidnightAsTheSameDay() {
        XCTAssertEqual(ICalSync.romeDay(day(3)), ICalSync.romeDay(romeMidnight(3)))
    }

    // MARK: Promemoria Excel

    func testReminderWithoutAnImportFiresAtTenTheNextOccasion() {
        let fire = ExcelReminder.fireDate(lastImportAt: nil, now: romeDate(2026, 11, 4, 12), calendar: rome)
        XCTAssertEqual(fire, romeDate(2026, 11, 5, 10))
        // Prima delle 10 vale lo stesso giorno.
        XCTAssertEqual(ExcelReminder.fireDate(lastImportAt: nil, now: romeDate(2026, 11, 4, 8), calendar: rome), romeDate(2026, 11, 4, 10))
    }

    func testReminderWaitsThirtyDaysFromTheLastImport() {
        let last = millisFromDate(romeDate(2026, 11, 1, 9))
        let fire = ExcelReminder.fireDate(lastImportAt: last, now: romeDate(2026, 11, 4, 12), calendar: rome)
        XCTAssertEqual(fire, romeDate(2026, 12, 1, 10))
    }

    func testReminderIsOverdueWhenTheLastImportIsOld() {
        let last = millisFromDate(romeDate(2026, 8, 1))
        let fire = ExcelReminder.fireDate(lastImportAt: last, now: romeDate(2026, 11, 4, 12), calendar: rome)
        XCTAssertEqual(fire, romeDate(2026, 11, 5, 10))
    }

    func testReminderOnlyForHousesWithABookingFeed() {
        var house = Property(id: "a", name: "Casa Mare")
        XCTAssertFalse(ExcelReminder.wantsReminder(house))
        house.icalUrlBooking = "  "
        XCTAssertFalse(ExcelReminder.wantsReminder(house))
        house.icalUrlBooking = "https://example.com/booking.ics"
        XCTAssertTrue(ExcelReminder.wantsReminder(house))
        XCTAssertTrue(ExcelReminder.body(for: house).hasPrefix("Casa Mare:"))
        XCTAssertEqual(ExcelReminder.identifier("p1"), "excel-reminder-p1")
    }

    func testFeedsOfAHouseAreTheConfiguredOnes() {
        var house = Property(id: "a", name: "A")
        house.icalUrlAirbnb = " https://example.com/a.ics "
        house.icalUrlBooking = ""
        let feeds = ICalSyncService.feeds(of: house)
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].platform, "AIRBNB")
        XCTAssertEqual(feeds[0].url, "https://example.com/a.ics")
    }
}
