import XCTest
@testable import SiciliaHost

// Specifica: BookingStatsTest, BookingImportPlanTest, BookingExcelParserTest (parti CSV e lettura del file reale).
final class BookingTests: XCTestCase {
    private let day = millisPerDay
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Int64 { utcMillis(year: y, month: m, day: d) }

    private func res(
        _ inDate: Int64, _ nights: Int, gross: Double? = nil, platform: String = "BOOKING", adults: Int = 2, children: Int = 0,
        bookedDaysBefore: Int? = nil, country: String? = nil, commission: Double? = nil, property: String = "p1", grossIsNil: Bool = false
    ) -> FinReservation {
        FinReservation(
            id: "r\(inDate)\(property)", propertyId: property, checkIn: inDate, checkOut: inDate + Int64(nights) * day,
            platform: platform, adults: adults, children: children, guestCountry: country,
            grossAmount: grossIsNil ? nil : (gross ?? 100.0 * Double(nights)), commissionAmount: commission,
            bookedAt: bookedDaysBefore.map { inDate - Int64($0) * day }
        )
    }

    // Aprile 2026: 30 notti disponibili per casa.
    private var april: Range<Int64> { date(2026, 4, 1) ..< date(2026, 5, 1) }

    // MARK: Statistiche

    func testOccupancyAdrAndAverages() throws {
        let list = [
            res(date(2026, 4, 2), 3, adults: 2, children: 2, bookedDaysBefore: 10),
            res(date(2026, 4, 10), 5, adults: 4, bookedDaysBefore: 30),
            res(date(2026, 4, 20), 2, platform: "AIRBNB", adults: 0, grossIsNil: true),
        ]
        let s = BookingStats.compute(reservations: list, range: april, houseCount: 1, now: date(2026, 4, 30))
        XCTAssertEqual(s.reservationCount, 3)
        XCTAssertEqual(s.nightsSold, 10)
        XCTAssertEqual(s.availableNights, 30)
        XCTAssertEqual(try XCTUnwrap(s.occupancy), 10.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.adr), 100, accuracy: 1e-9) // 800 € / 8 notti (solo con importo)
        XCTAssertEqual(try XCTUnwrap(s.avgNights), 10.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.avgGuests), 4, accuracy: 1e-9) // (4 + 4) / 2: solo dove ci sono i dati
        XCTAssertEqual(s.guestSample, 2)
        XCTAssertEqual(try XCTUnwrap(s.shareWithChildren), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.avgLeadDays), 20, accuracy: 1e-9)
    }

    func testNightsAreClippedToThePeriod() {
        // Arriva il 29 marzo, riparte il 3 aprile: 2 notti ad aprile, ma l'incasso è di marzo.
        let s = BookingStats.compute(reservations: [res(date(2026, 3, 29), 5)], range: april, houseCount: 1, now: date(2026, 4, 30))
        XCTAssertEqual(s.nightsSold, 2)
        XCTAssertEqual(s.reservationCount, 0)
        XCTAssertNil(s.adr)
    }

    func testChannelsUseRealCommissionWhenKnown() throws {
        let list = [
            res(date(2026, 4, 2), 2, gross: 200, commission: 36),
            res(date(2026, 4, 6), 2, gross: 200, platform: "AIRBNB"),
        ]
        let s = BookingStats.compute(reservations: list, range: april, houseCount: 1, now: date(2026, 4, 30))
        XCTAssertEqual(s.commissionsPaid, 36 + 200 * 0.175, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.bookingRealCommissionRate), 0.18, accuracy: 1e-9)
    }

    func testOrphanNightsBetweenFutureBookings() {
        let list = [
            res(date(2026, 4, 5), 3), // esce l'8
            res(date(2026, 4, 10), 2), // buco 8-10: 2 notti
            res(date(2026, 4, 20), 2), // buco di 8: non isolato
        ]
        XCTAssertEqual(BookingStats.orphanNights(list, now: date(2026, 4, 1)), 2)
    }

    func testCancellationRateFromImports() throws {
        let s = BookingStats.compute(
            reservations: [], range: april, houseCount: 1, now: date(2026, 4, 30),
            importCounts: [BookingImportCounts(confirmed: 8, cancelled: 2)]
        )
        XCTAssertEqual(try XCTUnwrap(s.cancellationRate), 0.2, accuracy: 1e-9)
    }

    func testStayLengthBucketsAndWeekdays() throws {
        // 6 aprile 2026 è un lunedì.
        let s = BookingStats.compute(
            reservations: [res(date(2026, 4, 6), 1), res(date(2026, 4, 11), 7)], range: april, houseCount: 1, now: date(2026, 4, 30)
        )
        XCTAssertEqual(try XCTUnwrap(s.stayLengths.first { $0.label == "1 notte" }).count, 1)
        XCTAssertEqual(try XCTUnwrap(s.stayLengths.first { $0.label == "7+ notti" }).count, 1)
        XCTAssertEqual(s.checkInWeekdays[0], 1) // lunedì
        XCTAssertEqual(s.checkInWeekdays[5], 1) // sabato
    }

    func testMonthlyOccupancyLabelsAndValues() throws {
        let s = BookingStats.compute(reservations: [res(date(2026, 4, 1), 15)], range: april, houseCount: 1, now: date(2026, 4, 30))
        XCTAssertEqual(s.monthlyOccupancy.map(\.label), ["apr 26"])
        XCTAssertEqual(s.monthlyOccupancy[0].occupancy, 0.5, accuracy: 1e-9)
    }

    // MARK: Piano di importazione

    private func row(_ uid: String, _ from: Int64, _ to: Int64, name: String? = "Rossi") -> ExcelRow {
        ExcelRow(
            reservation: Reservation(propertyId: "p1", guestName: name, checkIn: from * day, checkOut: to * day,
                                     platform: "BOOKING", icalUid: "booking-xls-\(uid)", adults: 2),
            money: ExcelMoneyRow(propertyId: "p1", grossAmount: 100)
        )
    }

    private func existing(_ id: String, _ from: Int64, _ to: Int64, name: String? = nil, uid: String? = nil) -> Reservation {
        Reservation(id: id, propertyId: "p1", guestName: name, checkIn: from * day, checkOut: to * day,
                    platform: "BOOKING", icalUid: uid ?? id)
    }

    func testOverlapWithNamelessIcalPlaceholderCompletesIt() {
        let plan = planBookingImport(rows: [row("1", 10, 12)], existingBooking: [existing("ical-1", 10, 12)])
        XCTAssertEqual(plan.complete.map { $0.existing.id }, ["ical-1"])
        XCTAssertTrue(plan.insert.isEmpty && plan.enrich.isEmpty)
    }

    func testOverlapWithNamedReservationOnlyEnriches() {
        let plan = planBookingImport(rows: [row("1", 10, 12)], existingBooking: [existing("ical-1", 10, 12, name: "Rossi")])
        XCTAssertEqual(plan.enrich.map { $0.existing.id }, ["ical-1"])
        XCTAssertTrue(plan.complete.isEmpty && plan.insert.isEmpty)
    }

    func testSameXlsDocumentIsEnrichNeverCompleted() {
        let plan = planBookingImport(
            rows: [row("1", 10, 12)], existingBooking: [existing("booking-xls-1", 10, 12, name: nil, uid: "booking-xls-1")]
        )
        XCTAssertEqual(plan.enrich.count, 1)
        XCTAssertEqual(plan.complete.count, 0)
    }

    func testNoOverlapInserts() {
        XCTAssertEqual(planBookingImport(rows: [row("1", 10, 12)], existingBooking: [existing("ical-1", 20, 22)]).insert.count, 1)
    }

    func testEachExistingReservationIsUsedOnce() {
        let plan = planBookingImport(rows: [row("1", 10, 12), row("2", 11, 13)], existingBooking: [existing("ical-1", 10, 13)])
        XCTAssertEqual(plan.complete.count, 1)
        XCTAssertEqual(plan.insert.count, 1)
        XCTAssertEqual(plan.insert.map { $0.reservation.icalUid }, ["booking-xls-2"])
    }

    func testPlaceholderDetection() {
        XCTAssertTrue(isNamelessIcalPlaceholder(existing("ical-1", 1, 2)))
        XCTAssertTrue(isNamelessIcalPlaceholder(existing("ical-1", 1, 2, name: "  ")))
        XCTAssertFalse(isNamelessIcalPlaceholder(existing("ical-1", 1, 2, name: "Rossi")))
        XCTAssertFalse(isNamelessIcalPlaceholder(existing("booking-xls-1", 1, 2)))
        XCTAssertFalse(isNamelessIcalPlaceholder(Reservation(id: "m1", propertyId: "p1", platform: "MANUAL")))
    }

    // MARK: CSV

    private func csv(_ text: String) -> Data { Data(text.utf8) }

    func testSemicolonCsvWithBomAndQuotedFields() throws {
        // BOM UTF-8, separatore ';' e campi quotati che contengono ',' e ';' — casi tipici dei CSV in locale europeo.
        let text = "\u{FEFF}"
            + "Stato;N° di prenotazione;Nome ospite(i);Arrivo;Partenza;Prezzo;Indirizzo;Numero di telefono;Booker country;Adulti;Bambini\n"
            + "ok;123;\"Rossi, Mario\";2026-01-16;2026-01-20;400 EUR;\"Via Roma 1; interno 2\";393331234567;it;4;2\n"
            + "cancelled;124;Skip Me;2026-03-01;2026-03-03;100 EUR;;;fr;1;0\n"
        let result = try BookingExcelParser.parse(data: csv(text), propertyId: "prop1")
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skippedRows, 1)
        let r = result.rows[0].reservation
        XCTAssertEqual(r.guestName, "Rossi, Mario")
        XCTAssertEqual(r.icalUid, "booking-xls-123")
        XCTAssertEqual(r.adults, 4)
        XCTAssertEqual(r.children, 2)
        XCTAssertEqual(r.guestCountry, "it")
        // I soldi stanno solo nella parte del telefono.
        XCTAssertEqual(try XCTUnwrap(result.rows[0].money.grossAmount), 400, accuracy: 0.001)
        XCTAssertEqual(result.rows[0].money.propertyId, "prop1")
        XCTAssertEqual(result.rows[0].money.reservationId, "")
        XCTAssertEqual(result.contacts[0].address, "Via Roma 1; interno 2")
        XCTAssertEqual(result.contacts[0].phone, "+393331234567")
        XCTAssertEqual(result.contacts[0].propertyId, "prop1")
    }

    func testCommaCsvWithEnglishHeadersAndEuropeanDates() throws {
        let text = "Status,Book number,Guest name(s),Check-in,Check-out,Price,Address,Phone number,Booker country,Adults,Children\n"
            + "ok,5100000001,Hans Muster,16/01/2026,25/01/2026,968 EUR,,491701234567,de,4,1\n"
        let result = try BookingExcelParser.parse(data: csv(text), propertyId: "prop2")
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.skippedRows, 0)
        let r = result.rows[0].reservation
        XCTAssertEqual(r.icalUid, "booking-xls-5100000001")
        XCTAssertEqual(r.guestName, "Hans Muster")
        XCTAssertEqual(r.checkIn, date(2026, 1, 16))
        XCTAssertEqual(r.checkOut, date(2026, 1, 25))
        XCTAssertEqual(try XCTUnwrap(result.rows[0].money.grossAmount), 968, accuracy: 0.001)
        XCTAssertEqual(result.contacts[0].phone, "+491701234567")
        XCTAssertEqual(result.contacts[0].country, "de")
    }

    func testEmptyChildrenCellBecomesZeroNotASkippedRow() throws {
        let text = "Stato;N° di prenotazione;Nome ospite(i);Arrivo;Partenza;Prezzo;Adulti;Bambini\n"
            + "ok;1;Jane Doe;2026-02-01;2026-02-03;250.5 EUR;2;\n"
        let result = try BookingExcelParser.parse(data: csv(text), propertyId: "p")
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].reservation.children, 0)
        XCTAssertEqual(try XCTUnwrap(result.rows[0].money.grossAmount), 250.5, accuracy: 0.001)
        XCTAssertTrue(result.contacts.isEmpty) // senza telefono nessun contatto
    }

    func testRejectsFileWithoutRecognizedHeaders() {
        XCTAssertThrowsError(try BookingExcelParser.parse(data: csv("Foo;Bar\n1;2\n"), propertyId: "p")) {
            XCTAssertTrue(($0 as? BookingImportError)?.message.hasPrefix("Nessuna colonna riconosciuta") == true)
        }
    }

    func testCountsCancelledRowsAndPeriod() throws {
        let text = "Stato;N° di prenotazione;Arrivo;Partenza;Prezzo\n"
            + "ok;1;2026-01-16;2026-01-20;400 EUR\n"
            + "cancelled_by_guest;2;2026-02-01;2026-02-03;250 EUR\n"
        let result = try BookingExcelParser.parse(data: csv(text), propertyId: "p1")
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.cancelledRows, 1)
        XCTAssertEqual(result.periodFrom, date(2026, 1, 16))
        XCTAssertEqual(result.periodTo, date(2026, 2, 1))
    }

    func testStatisticsColumnsAreRead() throws {
        let text = "Stato;N° di prenotazione;Arrivo;Partenza;Prezzo;Data di prenotazione;Booker country;Motivo del viaggio;Dispositivo;Importo commissione\n"
            + "ok;1;2026-01-16;2026-01-25;968 EUR;2025-12-14 20:01:12;DE;Svago;Computer;174.24 EUR\n"
        let row = try BookingExcelParser.parse(data: csv(text), propertyId: "p1").rows[0]
        XCTAssertEqual(row.reservation.guestCountry, "de")
        XCTAssertEqual(row.money.travelPurpose, "Svago")
        XCTAssertEqual(row.money.bookingDevice, "Computer")
        XCTAssertEqual(try XCTUnwrap(row.money.commissionAmount), 174.24, accuracy: 0.001)
        XCTAssertEqual((row.reservation.checkIn - (row.money.bookedAt ?? 0)) / day, 33) // 14/12/2025 → 16/01/2026
    }

    func testDateParsing() {
        XCTAssertEqual(BookingExcelParser.parseDate("2026-01-16"), date(2026, 1, 16))
        XCTAssertEqual(BookingExcelParser.parseDate("16/01/2026"), date(2026, 1, 16))
        XCTAssertNil(BookingExcelParser.parseDate("31/02/2026"))
        XCTAssertNil(BookingExcelParser.parseDate("boh"))
        XCTAssertNil(BookingExcelParser.parseDate(""))
    }

    func testCsvRecordsKeepNewlinesInsideQuotes() {
        let records = BookingExcelParser.parseCsvRecords("a;\"x\r\ny\";c\r\n1;2;3\r\n", delimiter: ";")
        XCTAssertEqual(records, [["a", "x\r\ny", "c"], ["1", "2", "3"]])
        XCTAssertEqual(BookingExcelParser.parseCsvRecords("a;\"he said \"\"hi\"\"\"\n", delimiter: ";"), [["a", "he said \"hi\""]])
    }

    func testDelimiterDetection() {
        XCTAssertEqual(BookingExcelParser.detectDelimiter("a;b;c\n1,2,3"), ";")
        XCTAssertEqual(BookingExcelParser.detectDelimiter("a,b,c;d"), ",")
        XCTAssertEqual(BookingExcelParser.detectDelimiter("a\tb\tc"), "\t")
        XCTAssertEqual(BookingExcelParser.detectDelimiter("\"a;b;c\",d"), ",")
        XCTAssertEqual(BookingExcelParser.detectDelimiter("solo"), ",")
    }

    // MARK: File reale (facoltativo)

    /// Se la variabile d'ambiente `BOOKING_XLS_FIXTURE` punta a un export reale (il file nella radice dell'Android) lo
    /// si legge davvero: stessi valori del test Android `parse_realExport_readsStatisticsColumns`.
    func testRealExportIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["BOOKING_XLS_FIXTURE"] else {
            throw XCTSkip("BOOKING_XLS_FIXTURE non impostata")
        }
        let result = try BookingExcelParser.parse(data: try Data(contentsOf: URL(fileURLWithPath: path)), propertyId: "p1")
        XCTAssertEqual(result.rows.count, 30)
        XCTAssertEqual(result.cancelledRows, 0)
        let first = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(first.reservation.guestCountry, "de")
        XCTAssertEqual(first.money.travelPurpose, "Svago")
        XCTAssertEqual(first.money.bookingDevice, "Computer")
        XCTAssertEqual(try XCTUnwrap(first.money.commissionAmount), 174.24, accuracy: 0.001)
        XCTAssertEqual((first.reservation.checkIn - (first.money.bookedAt ?? 0)) / day, 33)
    }
}
