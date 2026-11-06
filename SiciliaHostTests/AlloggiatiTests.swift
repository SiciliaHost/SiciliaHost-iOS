import XCTest
@testable import SiciliaHost

/// Porta dei test Android di `data/alloggiati` (AlloggiatiSoapTest, SchedinaTest, SendPlanTest, ReceiptDatesTest,
/// CheckinMarkTest, e più sotto AlloggiatiClientTest e GuestRecordStoreTest).
final class AlloggiatiTests: XCTestCase {
    private func block(_ esito: Bool, _ extra: String = "") -> String {
        "<EsitoOperazioneServizio><esito>\(esito)</esito>\(extra)</EsitoOperazioneServizio>"
    }

    private func assertAlloggiatiError(
        _ kind: AlloggiatiError.Kind, _ message: String? = nil, file: StaticString = #filePath, line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let e = error as? AlloggiatiError else { return XCTFail("errore inatteso \(error)", file: file, line: line) }
            XCTAssertEqual(e.kind, kind, file: file, line: line)
            if let message { XCTAssertEqual(e.message, message, file: file, line: line) }
        }
    }

    // MARK: SOAP

    func testEscapeAndEnvelope() {
        XCTAssertEqual(AlloggiatiSoap.esc("a&b<c>\"d\""), "a&amp;b&lt;c&gt;&quot;d&quot;")
        let xml = AlloggiatiSoap.envelope("Tabella", "<all:tipo>Luoghi</all:tipo>")
        XCTAssertTrue(xml.contains("xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\""))
        XCTAssertTrue(xml.contains("<all:Tabella><all:tipo>Luoghi</all:tipo></all:Tabella>"))
    }

    func testExtract() {
        XCTAssertEqual(AlloggiatiSoap.extractText("<a><token>T1</token></a>", "token"), "T1")
        XCTAssertEqual(AlloggiatiSoap.extractText("<a><Token>T1</Token></a>", "token"), "")
        XCTAssertEqual(AlloggiatiSoap.extractText("<a></a>", "token"), "")
        XCTAssertTrue(AlloggiatiSoap.extractBool("<ESITO>TRUE</ESITO>", "esito"))
        XCTAssertFalse(AlloggiatiSoap.extractBool("<esito>false</esito>", "esito"))
        XCTAssertFalse(AlloggiatiSoap.extractBool("<x/>", "esito"))
    }

    func testParseEsitoReadsCountAndRowsInOrder() throws {
        let xml = "<R><esito>true</esito><SchedineValide>1</SchedineValide><Dettaglio>" + block(true)
            + block(false, "<ErroreCod>12</ErroreCod><ErroreDes>Documento non valido</ErroreDes><ErroreDettaglio>numero</ErroreDettaglio>")
            + "</Dettaglio></R>"
        XCTAssertEqual(try AlloggiatiSoap.parseEsito(xml), ElencoSchedineEsito(schedineValide: 1, dettaglio: [
            EsitoSingolo(esito: true, errorCod: "", errorDes: "", erroreDettaglio: ""),
            EsitoSingolo(esito: false, errorCod: "12", errorDes: "Documento non valido", erroreDettaglio: "numero"),
        ]))
        let other = "<R><esito>true</esito>" + block(false, "<errorCod>7</errorCod><errorDes>Boh</errorDes><erroreDettaglio>d</erroreDettaglio>") + "</R>"
        XCTAssertEqual(try AlloggiatiSoap.parseEsito(other).dettaglio[0],
                       EsitoSingolo(esito: false, errorCod: "7", errorDes: "Boh", erroreDettaglio: "d"))
        XCTAssertEqual(try AlloggiatiSoap.parseEsito("<R><esito>true</esito></R>"), ElencoSchedineEsito(schedineValide: 0, dettaglio: []))
    }

    func testCallLevelRefusalIsRejected() {
        assertAlloggiatiError(.rejected, "Token scaduto: rifare il login") {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreDes>Token scaduto</ErroreDes><ErroreDettaglio>rifare il login</ErroreDettaglio></R>")
        }
        assertAlloggiatiError(.rejected, "Il servizio ha rifiutato la richiesta") {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreCod>3</ErroreCod></R>")
        }
        assertAlloggiatiError(.rejected, "Rifiutata") {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreDes>Rifiutata</ErroreDes><SchedineValide>0</SchedineValide></R>")
        }
    }

    func testUnclearRefusalsAreUncertain() {
        assertAlloggiatiError(.uncertain, alloggiatiUncertainTransportMessage) {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreDes>Rifiutata</ErroreDes>\(self.block(true))</R>")
        }
        assertAlloggiatiError(.uncertain) {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreDes>Rifiutata</ErroreDes><SchedineValide>2</SchedineValide></R>")
        }
        assertAlloggiatiError(.uncertain) { _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito></R>") }
    }

    func testErrorTextsAreXmlDecoded() throws {
        assertAlloggiatiError(.rejected, "Dati d'ingresso & altro") {
            _ = try AlloggiatiSoap.parseEsito("<R><esito>false</esito><ErroreDes>Dati d&apos;ingresso &amp; altro</ErroreDes></R>")
        }
        let row = try AlloggiatiSoap.parseEsito(
            "<R><esito>true</esito>\(block(false, "<ErroreDes>&lt;x&gt; &quot;y&quot; &amp;lt;</ErroreDes>"))</R>"
        ).dettaglio[0]
        XCTAssertEqual(row.errorDes, "<x> \"y\" &lt;")
    }

    func testResponseWithoutEnvelopeIsUncertain() throws {
        XCTAssertEqual(try AlloggiatiSoap.requireSoapBody("<soap:Envelope/>"), "<soap:Envelope/>")
        assertAlloggiatiError(.uncertain) { _ = try AlloggiatiSoap.requireSoapBody("<html>502</html>") }
    }

    // MARK: Schedina

    private func romeMidnight(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
        Int64(RomeTime.calendar.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970 * 1000)
    }

    private func utcMidnight(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return Int64(cal.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970 * 1000)
    }

    private let mario = GuestRecord(
        tipoAlloggiato: "16", cognome: "ROSSI", nome: "MARIO", sesso: "1", dataNascita: "01/02/1980",
        comuneNascitaCode: "403015146", provinciaNascita: "PA", statoNascitaCode: "100000100",
        cittadinanzaCode: "100000216", tipoDocumentoCode: "IDENT", numeroDocumento: "AB1234567", luogoRilascioCode: "403015146"
    )

    private func sub(_ s: String, _ from: Int, _ to: Int) -> String {
        String(s[s.index(s.startIndex, offsetBy: from)..<s.index(s.startIndex, offsetBy: to)])
    }

    private func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }

    func testRowIs168CharactersWithFieldsInPlace() throws {
        let row = try Schedina.row(mario, checkIn: romeMidnight(2026, 8, 14), checkOut: romeMidnight(2026, 8, 18))
        XCTAssertEqual(row.count, 168)
        XCTAssertEqual(sub(row, 0, 2), "16")
        XCTAssertEqual(sub(row, 2, 12), "14/08/2026")
        XCTAssertEqual(sub(row, 12, 14), "04")
        XCTAssertEqual(sub(row, 14, 64), pad("ROSSI", 50))
        XCTAssertEqual(sub(row, 64, 94), pad("MARIO", 30))
        XCTAssertEqual(sub(row, 94, 95), "1")
        XCTAssertEqual(sub(row, 95, 105), "01/02/1980")
        XCTAssertEqual(sub(row, 105, 114), "403015146")
        XCTAssertEqual(sub(row, 114, 116), "PA")
        XCTAssertEqual(sub(row, 116, 125), "100000100")
        XCTAssertEqual(sub(row, 125, 134), "100000216")
        XCTAssertEqual(sub(row, 134, 139), "IDENT")
        XCTAssertEqual(sub(row, 139, 159), pad("AB1234567", 20))
        XCTAssertEqual(sub(row, 159, 168), "403015146")
    }

    func testLongValuesAreCutAndMissingOnesBlank() throws {
        var long = mario
        long.cognome = String(repeating: "X", count: 80)
        long.comuneNascitaCode = nil
        long.provinciaNascita = nil
        let row = try Schedina.row(long, checkIn: romeMidnight(2026, 8, 14), checkOut: romeMidnight(2026, 8, 15))
        XCTAssertEqual(row.count, 168)
        XCTAssertEqual(sub(row, 14, 64), String(repeating: "X", count: 50))
        XCTAssertEqual(sub(row, 105, 116), String(repeating: " ", count: 11))
    }

    func testNightsAreCappedAt30AndAreRomeCalendarDays() throws {
        XCTAssertEqual(sub(try Schedina.row(mario, checkIn: romeMidnight(2026, 1, 1), checkOut: romeMidnight(2026, 3, 1)), 12, 14), "30")
        // Il 29 marzo 2026 inizia l'ora legale: 47 ore ma 2 notti.
        XCTAssertEqual(sub(try Schedina.row(mario, checkIn: romeMidnight(2026, 3, 28), checkOut: romeMidnight(2026, 3, 30)), 12, 14), "02")
        let mixed = try Schedina.row(mario, checkIn: utcMidnight(2026, 8, 14), checkOut: romeMidnight(2026, 8, 18))
        XCTAssertEqual(sub(mixed, 2, 12), "14/08/2026")
        XCTAssertEqual(sub(mixed, 12, 14), "04")
    }

    func testArrivalDateIsTheItalianOne() {
        // 23:30 UTC del 13 agosto = 01:30 del 14 a Roma.
        XCTAssertEqual(Schedina.italianDate(utcMidnight(2026, 8, 13) + (23 * 60 + 30) * 60_000), "14/08/2026")
        XCTAssertEqual(Schedina.romeIsoDate(romeMidnight(2026, 8, 14) + 60_000), "2026-08-14")
    }

    func testInvalidStayDatesAreRefused() {
        let day = romeMidnight(2026, 8, 14)
        for out in [day, day - 86_400_000, 0] {
            assertAlloggiatiError(.refused, "Date del soggiorno non valide: controlla arrivo e partenza") {
                _ = try Schedina.row(self.mario, checkIn: day, checkOut: out)
            }
        }
    }

    func testControlCharactersBecomeSpaces() throws {
        var r = mario
        r.cognome = "ROSSI\nX"
        r.nome = "A\r\nB\t"
        let row = try Schedina.row(r, checkIn: romeMidnight(2026, 8, 14), checkOut: romeMidnight(2026, 8, 15))
        XCTAssertEqual(row.count, 168)
        XCTAssertEqual(sub(row, 14, 64), pad("ROSSI X", 50))
        XCTAssertEqual(sub(row, 64, 94), pad("A  B", 30))
    }

    func testEveryRowButTheLastEndsWithCrLf() throws {
        let rows = try Schedina.rows([mario, mario], checkIn: romeMidnight(2026, 8, 14), checkOut: romeMidnight(2026, 8, 18))
        XCTAssertTrue(rows[0].hasSuffix("\r\n"))
        // In Swift "\r\n" è un solo Character: si contano le unità UTF-16, come la lunghezza Kotlin.
        XCTAssertEqual(rows[0].utf16.count, 170)
        XCTAssertEqual(rows[1].utf16.count, 168)
    }

    // MARK: Regole d'invio

    private let now: Int64 = 1_800_000_000_000
    private let day: Int64 = 24 * 60 * 60 * 1000

    private func r(_ id: String, sent: Bool = false, sendingAt: Int64? = nil, sentTs: Int64? = nil) -> GuestRecord {
        GuestRecord(id: id, schedInaSent: sent, sendTimestamp: sentTs, sendingAt: sendingAt)
    }

    func testPendingSkipsSentAndLockedRecords() {
        let records = [r("a"), r("b", sent: true), r("c", sendingAt: now - 10_000), r("d", sendingAt: now - SendPlan.lockMs - 1)]
        XCTAssertEqual(SendPlan.pending(records, now: now, respectLock: true).map(\.id), ["a", "d"])
        XCTAssertEqual(SendPlan.pending(records, now: now, respectLock: false).map(\.id), ["a", "c", "d"])
    }

    func testOutcomesNeedOneResultPerRecord() {
        XCTAssertNil(SendPlan.outcomes(count: 2, [EsitoSingolo(esito: true, errorCod: "", errorDes: "", erroreDettaglio: "")]))
        XCTAssertEqual(SendPlan.outcomes(count: 3, [
            EsitoSingolo(esito: true, errorCod: "", errorDes: "", erroreDettaglio: ""),
            EsitoSingolo(esito: false, errorCod: "1", errorDes: "Documento non valido", erroreDettaglio: ""),
            EsitoSingolo(esito: false, errorCod: "", errorDes: "", erroreDettaglio: ""),
        ]), [SendOutcome(sent: true, error: nil), SendOutcome(sent: false, error: "Documento non valido"),
             SendOutcome(sent: false, error: "Scheda rifiutata")])
    }

    func testApplyOutcomesMarksOnlyTheSentRecordsAndReleasesTheLock() {
        let records = [r("a", sendingAt: now), r("b", sendingAt: now), r("x", sent: true)]
        let out = SendPlan.apply(records, ids: ["a", "b"],
                                 outcomes: [SendOutcome(sent: true, error: nil), SendOutcome(sent: false, error: "No")], now: now + 5)
        XCTAssertEqual(out[0], GuestRecord(id: "a", schedInaSent: true, sendTimestamp: now + 5))
        XCTAssertEqual(out[1], GuestRecord(id: "b", schedInaSent: false, sendTimestamp: now + 5, sendError: "No"))
        XCTAssertEqual(out[2], records[2])
    }

    func testUncertainAndLocks() {
        let out = SendPlan.markUncertain([r("a", sendingAt: now), r("b")], ids: ["a"])
        XCTAssertEqual(out[0].sendError, SendPlan.uncertainMessage)
        XCTAssertNil(out[0].sendingAt)
        XCTAssertTrue(SendPlan.hasUncertain(out))
        XCTAssertFalse(SendPlan.hasUncertain([r("b")]))
        let released = SendPlan.releaseLocks([r("a", sendingAt: now), r("b", sendingAt: now)], ids: ["a"])
        XCTAssertNil(released[0].sendingAt)
        XCTAssertEqual(released[1].sendingAt, now)
        XCTAssertEqual(SendPlan.lock([r("a"), r("b")], ids: ["b"], now: now).map(\.sendingAt), [nil, now])
    }

    func testStaleLocksBecomeUncertain() {
        let out = SendPlan.normalizeStaleLocks([r("a", sendingAt: now - SendPlan.lockMs), r("b", sendingAt: now - 1_000), r("c")], now: now)
        XCTAssertEqual(out[0].sendError, SendPlan.uncertainMessage)
        XCTAssertNil(out[0].sendingAt)
        XCTAssertEqual(out[1], r("b", sendingAt: now - 1_000))
        XCTAssertEqual(out[2], r("c"))
    }

    func testDescriptionsHideSecretsAndPersonalData() {
        let c = AlloggiatiCredentials(utente: "mario", password: "SEGRETO", wsKey: "CHIAVE")
        XCTAssertEqual(c.description, "AlloggiatiCredentials(utente=mario, password=***, wsKey=***)")
        XCTAssertFalse(String(describing: c).contains("SEGRETO"))
        let g = GuestRecord(id: "i", cognome: "ROSSI", nome: "MARIO", dataNascita: "01/02/1980", numeroDocumento: "AB1234567")
        let s = String(describing: g)
        for secret in ["ROSSI", "MARIO", "01/02/1980", "AB1234567"] { XCTAssertFalse(s.contains(secret)) }
        XCTAssertTrue(s.contains("id=i"))
    }

    func testCredentialsRoundTripAsJson() throws {
        let c = AlloggiatiCredentials(utente: "u", password: "p\"<", wsKey: "k")
        XCTAssertEqual(try JSONDecoder().decode(AlloggiatiCredentials.self, from: JSONEncoder().encode(c)), c)
    }

    func testRetention() {
        let sent = StoredCheckin(propertyId: "p", reservationId: "r", checkOut: now, records: [r("a", sent: true, sentTs: now - 31 * day)])
        XCTAssertTrue(SendPlan.isExpired(sent, now: now))
        var recent = sent
        recent.records = [r("a", sent: true, sentTs: now - 29 * day)]
        XCTAssertFalse(SendPlan.isExpired(recent, now: now))
        var mixed = sent
        mixed.records.append(r("b"))
        XCTAssertFalse(SendPlan.isExpired(mixed, now: now))
        var empty = sent
        empty.records = []
        XCTAssertFalse(SendPlan.isExpired(empty, now: now))

        let stale = StoredCheckin(propertyId: "p", reservationId: "r", checkOut: now - 31 * day, records: [r("a")])
        XCTAssertTrue(SendPlan.isStaleUnsent(stale, now: now))
        var recentStay = stale
        recentStay.checkOut = now - 10 * day
        XCTAssertFalse(SendPlan.isStaleUnsent(recentStay, now: now))
        var noCheckout = stale
        noCheckout.checkOut = 0
        XCTAssertFalse(SendPlan.isStaleUnsent(noCheckout, now: now))
        var allSent = stale
        allSent.records = [r("a", sent: true)]
        XCTAssertFalse(SendPlan.isStaleUnsent(allSent, now: now))
    }

    // MARK: Segno «check-in inviato»

    func testCheckinMark() {
        XCTAssertEqual(CheckinMark.parse(["sentAt": NSNumber(value: 1000), "guests": NSNumber(value: 3), "by": "u1"]),
                       CheckinMark(sentAt: 1000, guests: 3, by: "u1"))
        XCTAssertNil(CheckinMark.parse(nil))
        XCTAssertNil(CheckinMark.parse(["guests": NSNumber(value: 3)]))
        XCTAssertNil(CheckinMark.parse("x"))
    }

    // MARK: Giorni della ricevuta

    private func ms(_ iso: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
    }

    private func d(_ y: Int, _ m: Int, _ dd: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: dd) }

    func testReceiptTodayIsTheRomeDate() {
        // 23:30 UTC del 5 novembre è già il 6 a Roma.
        XCTAssertEqual(ReceiptDates.romeToday(now: ms("2026-11-05T23:30:00Z")), d(2026, 11, 6))
    }

    func testReceiptRangeIsTheLast30DaysExcludingToday() {
        let today = d(2026, 11, 6)
        XCTAssertTrue(ReceiptDates.isSelectable(d(2026, 11, 5), today: today))
        XCTAssertTrue(ReceiptDates.isSelectable(d(2026, 10, 7), today: today))
        XCTAssertFalse(ReceiptDates.isSelectable(today, today: today))
        XCTAssertFalse(ReceiptDates.isSelectable(d(2026, 10, 6), today: today))
        XCTAssertFalse(ReceiptDates.isSelectable(d(2026, 11, 7), today: today))
        XCTAssertEqual(d(2026, 10, 25).iso, "2026-10-25")
    }

    func testReceiptDefaultDate() {
        let today = d(2026, 11, 6)
        let yesterday = d(2026, 11, 5)
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: ms("2026-11-02T10:00:00Z")), d(2026, 11, 2))
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: nil), yesterday)
        // Inviato oggi in ora italiana (23:30 UTC del 5 = 00:30 del 6): la ricevuta non c'è ancora.
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: ms("2026-11-05T23:30:00Z")), yesterday)
        // Troppo vecchio per il servizio.
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: ms("2026-09-27T10:00:00Z")), yesterday)
    }

    func testReceiptDatesAroundTheDstSwitch() {
        // 25 ottobre 2026: fine dell'ora legale. 22:30 UTC del 24 = 00:30 del 25 a Roma (CEST, +2).
        let today = d(2026, 10, 26)
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: ms("2026-10-24T22:30:00Z")), d(2026, 10, 25))
        // 23:30 UTC del 25 = 00:30 del 26 (CET, +1): è oggi.
        XCTAssertEqual(ReceiptDates.defaultDate(today: today, lastSentAt: ms("2026-10-25T23:30:00Z")), d(2026, 10, 25))
        XCTAssertEqual(ReceiptDates.romeToday(now: ms("2026-10-25T23:30:00Z")), today)
        XCTAssertEqual(d(2026, 3, 29).adding(days: -1), d(2026, 3, 28))
        XCTAssertEqual(d(2026, 3, 1).adding(days: -1), d(2026, 2, 28))
    }

    // MARK: Client

    private final class FakeTransport: SoapTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String]
        private var sent: [String] = []

        init(_ responses: [String]) { self.responses = responses }

        var bodies: [String] {
            lock.lock()
            defer { lock.unlock() }
            return sent
        }

        func post(_ body: String) async throws -> String {
            lock.lock()
            defer { lock.unlock() }
            sent.append(body)
            return responses.removeFirst()
        }
    }

    /// Orologio finto: una closure `@Sendable` non può catturare una `var` locale.
    private final class FakeClock: @unchecked Sendable {
        var now: Int64 = 0
    }

    private let creds = AlloggiatiCredentials(utente: "utente", password: "pa<ss", wsKey: "key")
    private let tokenOk = "<R><esito>true</esito><token>TK</token></R>"

    func testTokenIsCachedForTenMinutesAndEscaped() async throws {
        let clock = FakeClock()
        let t = FakeTransport([tokenOk, tokenOk])
        let client = AlloggiatiClient(transport: t, clock: { clock.now })
        let first = try await client.token(creds)
        let second = try await client.token(creds)
        XCTAssertEqual(first, "TK")
        XCTAssertEqual(second, "TK")
        XCTAssertEqual(t.bodies.count, 1)
        XCTAssertTrue(t.bodies[0].contains("<all:Password>pa&lt;ss</all:Password>"))
        clock.now += 10 * 60 * 1000 + 1
        _ = try await client.token(creds)
        XCTAssertEqual(t.bodies.count, 2)
    }

    func testChangedCredentialsDoNotReuseTheToken() async throws {
        let t = FakeTransport([tokenOk, tokenOk])
        let client = AlloggiatiClient(transport: t, clock: { 0 })
        _ = try await client.token(creds)
        var other = creds
        other.password = "altra"
        _ = try await client.token(other)
        XCTAssertEqual(t.bodies.count, 2)
    }

    func testRefusedTokenIsARefusal() async {
        let client = AlloggiatiClient(
            transport: FakeTransport(["<R><esito>false</esito><ErroreDes>Credenziali errate</ErroreDes></R>"]), clock: { 0 }
        )
        do {
            _ = try await client.token(creds)
            XCTFail("doveva fallire")
        } catch let e as AlloggiatiError {
            XCTAssertEqual(e.kind, .refused)
            XCTAssertEqual(e.message, "Credenziali errate")
        } catch {
            XCTFail("errore inatteso \(error)")
        }
    }

    func testTestAndSendUseTheApartmentMethods() async throws {
        let ok = "<R><esito>true</esito><SchedineValide>1</SchedineValide><EsitoOperazioneServizio><esito>true</esito></EsitoOperazioneServizio></R>"
        let t = FakeTransport([ok, ok])
        let client = AlloggiatiClient(transport: t, clock: { 0 })
        let tested = try await client.test(utente: "u", token: "TK", idAppartamento: 42, rows: ["RIGA"])
        XCTAssertEqual(tested.schedineValide, 1)
        _ = try await client.send(utente: "u", token: "TK", idAppartamento: 42, rows: ["RIGA"])
        XCTAssertTrue(t.bodies[0].contains("<all:GestioneAppartamenti_Test>"))
        XCTAssertTrue(t.bodies[0].contains(
            "<all:ElencoSchedine><all:string>RIGA</all:string></all:ElencoSchedine><all:IdAppartamento>42</all:IdAppartamento>"
        ))
        XCTAssertTrue(t.bodies[1].contains("<all:GestioneAppartamenti_Send>"))
    }

    func testTableAndReceipt() async throws {
        let t = FakeTransport([
            "<R><esito>true</esito><CSV>a;b\n1;2</CSV></R>",
            "<R><esito>true</esito><PDF>JVBERg==</PDF></R>",
            "<R><esito>false</esito></R>",
            "<R><esito>true</esito><PDF>A</PDF></R>",
        ])
        let client = AlloggiatiClient(transport: t, clock: { 0 })
        let csv = try await client.table(utente: "u", token: "TK", tipo: "Luoghi")
        XCTAssertEqual(csv, "a;b\n1;2")
        let pdf = try await client.receipt(utente: "u", token: "TK", dateIso: "2026-08-14")
        XCTAssertEqual(Array(pdf), [0x25, 0x50, 0x44, 0x46])
        XCTAssertTrue(t.bodies[1].contains("<all:Data>2026-08-14T00:00:00</all:Data>"))
        do {
            _ = try await client.receipt(utente: "u", token: "TK", dateIso: "2026-08-15")
            XCTFail("doveva fallire")
        } catch let e as AlloggiatiError {
            XCTAssertEqual(e.message, "Ricevuta non disponibile")
        }
        do {
            _ = try await client.receipt(utente: "u", token: "TK", dateIso: "2026-08-16")
            XCTFail("doveva fallire")
        } catch let e as AlloggiatiError {
            XCTAssertEqual(e.message, "Ricevuta non leggibile")
        }
    }

    func testInvalidateAndClearForceANewToken() async throws {
        let t = FakeTransport([tokenOk, tokenOk, tokenOk])
        let client = AlloggiatiClient(transport: t, clock: { 0 })
        _ = try await client.token(creds)
        await client.invalidate(creds)
        _ = try await client.token(creds)
        XCTAssertEqual(t.bodies.count, 2)
        await client.clearTokens()
        _ = try await client.token(creds)
        XCTAssertEqual(t.bodies.count, 3)
    }

    func testTransportErrorsBeforeSendingAreNotUncertain() {
        XCTAssertTrue(URLSessionSoapTransport.requestNeverSent(URLError(.notConnectedToInternet)))
        XCTAssertTrue(URLSessionSoapTransport.requestNeverSent(URLError(.cannotFindHost)))
        XCTAssertFalse(URLSessionSoapTransport.requestNeverSent(URLError(.timedOut)))
        XCTAssertFalse(URLSessionSoapTransport.requestNeverSent(URLError(.networkConnectionLost)))
    }

    // MARK: Schede su file

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("guest_records")
    }

    private func store(_ dir: URL) -> GuestRecordStore {
        var n = 0
        return GuestRecordStore(directory: dir, newId: {
            n += 1
            return "id\(n)"
        })
    }

    func testSaveAssignsAnIdAndKeepsOrder() throws {
        let s = store(tempDir())
        let a = try s.save(GuestRecord(reservationId: "r", propertyId: "p", nome: "A"), checkOut: 10)
        try s.save(GuestRecord(reservationId: "r", propertyId: "p", nome: "B"), checkOut: 10)
        XCTAssertEqual(a.id, "id1")
        XCTAssertEqual(try s.list(propertyId: "p", reservationId: "r").map(\.nome), ["A", "B"])
        var edited = a
        edited.nome = "A2"
        try s.save(edited, checkOut: 10)
        XCTAssertEqual(try s.list(propertyId: "p", reservationId: "r").map(\.nome), ["A2", "B"])
        XCTAssertEqual(s.all().map(\.checkOut), [10])
    }

    func testReservationsAreSeparateEvenWithStrangeIds() throws {
        let s = store(tempDir())
        try s.save(GuestRecord(reservationId: "abc@airbnb.com/1", propertyId: "p"), checkOut: 0)
        try s.save(GuestRecord(reservationId: "r2", propertyId: "p"), checkOut: 0)
        XCTAssertEqual(try s.list(propertyId: "p", reservationId: "abc@airbnb.com/1").count, 1)
        XCTAssertEqual(try s.list(propertyId: "p", reservationId: "r2").count, 1)
        XCTAssertEqual(try s.list(propertyId: "q", reservationId: "r2").count, 0)
    }

    func testDeleteAndReplaceAll() throws {
        let s = store(tempDir())
        let a = try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 0)
        try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 0)
        try s.delete(propertyId: "p", reservationId: "r", id: a.id)
        XCTAssertEqual(try s.list(propertyId: "p", reservationId: "r").count, 1)
        try s.replaceAll(propertyId: "p", reservationId: "r", checkOut: 0, records: [])
        XCTAssertTrue(s.all().isEmpty)
    }

    func testUnsentAndClear() throws {
        let s = store(tempDir())
        XCTAssertFalse(s.hasUnsent())
        try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 0)
        XCTAssertTrue(s.hasUnsent())
        try s.clear()
        XCTAssertTrue(s.all().isEmpty)
        XCTAssertFalse(s.hasUnsent())
    }

    func testPurgeRemovesOnlyExpiredReservations() throws {
        let s = store(tempDir())
        let now = 100 * day
        try s.save(GuestRecord(reservationId: "old", propertyId: "p", schedInaSent: true, sendTimestamp: now - 31 * day), checkOut: 0)
        try s.save(GuestRecord(reservationId: "new", propertyId: "p", schedInaSent: true, sendTimestamp: now - day), checkOut: 0)
        XCTAssertEqual(s.purgeExpired(now: now), 1)
        XCTAssertEqual(s.all().map(\.reservationId), ["new"])
    }

    func testTwoInstancesOnTheSameDirDoNotLoseRecords() throws {
        let dir = tempDir()
        let a = GuestRecordStore(directory: dir)
        let b = GuestRecordStore(directory: dir)
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            _ = try? (i % 2 == 0 ? a : b).save(GuestRecord(reservationId: "r", propertyId: "p", nome: "\(i)"), checkOut: 5)
        }
        XCTAssertEqual(try a.list(propertyId: "p", reservationId: "r").count, 50)
    }

    func testCorruptFileIsKeptAsideAndSaveThrows() throws {
        let dir = tempDir()
        let s = GuestRecordStore(directory: dir, newId: { "x" })
        let first = try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 0)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let json = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        try Data("{non json".utf8).write(to: json)
        var edited = first
        edited.nome = "N"
        XCTAssertThrowsError(try s.save(edited, checkOut: 0)) { error in
            XCTAssertEqual(error as? GuestRecordStoreError, .corrupt)
            XCTAssertEqual(error.localizedDescription, "Archivio delle schede danneggiato")
        }
        let aside = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".corrupt") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try String(contentsOf: aside[0], encoding: .utf8), "{non json")
        XCTAssertTrue(s.hasUnsent())
        XCTAssertTrue(s.all().isEmpty)
        try s.clear()
        XCTAssertFalse(s.hasUnsent())
    }

    func testSaveWithZeroKeepsTheKnownCheckOut() throws {
        let s = store(tempDir())
        try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 777)
        try s.save(GuestRecord(reservationId: "r", propertyId: "p"), checkOut: 0)
        XCTAssertEqual(try s.get(propertyId: "p", reservationId: "r")?.checkOut, 777)
    }

    func testStoredCheckinWithoutOptionalFieldsDecodes() throws {
        let json = #"{"propertyId":"p","reservationId":"r","records":[{"id":"a","schedInaSent":true}]}"#
        let c = try JSONDecoder().decode(StoredCheckin.self, from: Data(json.utf8))
        XCTAssertEqual(c.checkOut, 0)
        XCTAssertEqual(c.records.map(\.id), ["a"])
        XCTAssertNil(c.records[0].sendingAt)
    }

    // MARK: Ricevute

    func testReceiptFilesAreOverwrittenAndPurged() throws {
        let dir = tempDir()
        let url = try ReceiptFiles.write(Data([1]), directory: dir)
        _ = try ReceiptFiles.write(Data([2, 3]), directory: dir)
        XCTAssertEqual(try Data(contentsOf: url), Data([2, 3]))
        ReceiptFiles.purgeOlderThan(60, now: Date(), directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        ReceiptFiles.purgeOlderThan(60, now: Date().addingTimeInterval(120), directory: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        ReceiptFiles.clear(directory: dir)
    }
}
