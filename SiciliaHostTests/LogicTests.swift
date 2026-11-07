import XCTest
@testable import SiciliaHost

// Specifica: ICalSyncWorkerTest, GeoMathTest, NominatimClientTest, OsmUserAgentTest, ServiceImportTest,
// AirbnbListingScraperTest, PhotoLogicTest, InviteLinkTest, MrzParserTest dell'app Android.
final class LogicTests: XCTestCase {
    // MARK: iCal

    private let sampleIcal = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:real-booking-1@airbnb.com
    SUMMARY:Reserved
    DTSTART;VALUE=DATE:20260801
    DTEND;VALUE=DATE:20260805
    END:VEVENT
    BEGIN:VEVENT
    UID:blocked-1@airbnb.com
    SUMMARY:Airbnb (Not available)
    DTSTART;VALUE=DATE:20260810
    DTEND;VALUE=DATE:20260812
    END:VEVENT
    BEGIN:VEVENT
    UID:blocked-2@booking.com
    SUMMARY:CLOSED - Not available
    DTSTART;VALUE=DATE:20260815
    DTEND;VALUE=DATE:20260817
    END:VEVENT
    END:VCALENDAR
    """

    func testParseEventsExtractsEveryEventRegardlessOfSummary() {
        let events = ICalSync.parseEvents(sampleIcal)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].uid, "real-booking-1@airbnb.com")
        XCTAssertEqual(events[0].checkIn, utcMillis(year: 2026, month: 8, day: 1))
        XCTAssertEqual(events[0].checkOut, utcMillis(year: 2026, month: 8, day: 5))
        XCTAssertEqual(events[2].uid, "blocked-2@booking.com")
        XCTAssertEqual(events[2].summary, "CLOSED - Not available")
    }

    func testAirbnbImportsOnlyNonBlockedEvents() {
        let plan = ICalSync.buildSyncPlan(events: ICalSync.parseEvents(sampleIcal), propertyId: "prop1", platform: "AIRBNB", existingFutureReservations: [])
        XCTAssertEqual(plan.toUpsert.count, 1)
        XCTAssertEqual(plan.toUpsert[0].icalUid, "real-booking-1@airbnb.com")
        XCTAssertTrue(plan.toDelete.isEmpty)
    }

    func testAirbnbDeletesReservationWhoseUidLeftTheFeed() {
        let vanished = Reservation(id: "r1", propertyId: "prop1", checkIn: 1, checkOut: 2, platform: "AIRBNB", icalUid: "cancelled@airbnb.com")
        let plan = ICalSync.buildSyncPlan(events: ICalSync.parseEvents(sampleIcal), propertyId: "prop1", platform: "AIRBNB", existingFutureReservations: [vanished])
        XCTAssertEqual(plan.toDelete.map(\.id), ["r1"])
    }

    func testBookingImportsEveryEventAsPlaceholderWithNilGuestName() {
        let plan = ICalSync.buildSyncPlan(events: ICalSync.parseEvents(sampleIcal), propertyId: "prop1", platform: "BOOKING", existingFutureReservations: [])
        XCTAssertEqual(plan.toUpsert.count, 3)
        XCTAssertTrue(plan.toUpsert.allSatisfy { $0.guestName == nil && $0.firestoreData["needsReview"] == nil })
    }

    func testBookingSkipsEventOverlappingAnExistingReservation() {
        // Copre già le date dell'evento real-booking-1 (1-5 agosto 2026): dev'essere l'unico scartato.
        let already = Reservation(id: "excel-1", propertyId: "prop1", checkIn: 1_785_542_400_000, checkOut: 1_785_888_000_000,
                                  platform: "BOOKING", icalUid: "booking-xls-42")
        let plan = ICalSync.buildSyncPlan(events: ICalSync.parseEvents(sampleIcal), propertyId: "prop1", platform: "BOOKING", existingFutureReservations: [already])
        XCTAssertEqual(plan.toUpsert.count, 2)
        XCTAssertTrue(plan.toUpsert.allSatisfy { $0.checkIn != 1_785_542_400_000 })
    }

    func testBookingDeletesReservationWhoseDatesAreNoLongerBlocked() {
        let cancelled = Reservation(id: "r2", propertyId: "prop1", checkIn: 2_000_000_000_000, checkOut: 2_000_100_000_000,
                                    platform: "BOOKING", icalUid: "booking-xls-99")
        let plan = ICalSync.buildSyncPlan(events: ICalSync.parseEvents(sampleIcal), propertyId: "prop1", platform: "BOOKING", existingFutureReservations: [cancelled])
        XCTAssertEqual(plan.toDelete.map(\.id), ["r2"])
    }

    func testEmptyFeedDeletesNothingForEitherPlatform() {
        let empty = ICalSync.parseEvents("BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertTrue(empty.isEmpty)
        let airbnb = Reservation(id: "r1", propertyId: "prop1", checkIn: 1, checkOut: 2, platform: "AIRBNB", icalUid: "would-be-deleted@airbnb.com")
        let booking = Reservation(id: "excel-1", propertyId: "prop1", checkIn: 1_785_542_400_000, checkOut: 1_785_888_000_000,
                                  platform: "BOOKING", icalUid: "booking-xls-42")
        for (platform, existing) in [("AIRBNB", airbnb), ("BOOKING", booking)] {
            let plan = ICalSync.buildSyncPlan(events: empty, propertyId: "prop1", platform: platform, existingFutureReservations: [existing])
            XCTAssertTrue(plan.toUpsert.isEmpty)
            XCTAssertTrue(plan.toDelete.isEmpty)
        }
    }

    func testFeedValidityAndErrorReasonNeverLeakTheSecretUrl() {
        XCTAssertTrue(ICalSync.isValidFeed(sampleIcal))
        XCTAssertFalse(ICalSync.isValidFeed("<html>404</html>"))
        XCTAssertEqual(
            ICalSync.safeErrorReason(typeName: "FileNotFoundException", message: "https://www.airbnb.it/calendar/ical/12345.ics?s=SEGRETO123ABC"),
            "FileNotFoundException: <url iCal>"
        )
        let mixed = ICalSync.safeErrorReason(typeName: "IOException", message: "Cleartext HTTP traffic to http://booking.com/ical?token=SEGRETO not permitted")
        XCTAssertFalse(mixed.contains("SEGRETO"))
        XCTAssertTrue(mixed.hasPrefix("IOException: "))
        XCTAssertEqual(ICalSync.safeErrorReason(typeName: "SocketTimeoutException", message: nil), "SocketTimeoutException")
    }

    // MARK: GeoMath

    private let palermo = LatLng(lat: 38.1157, lng: 13.3615)

    func testDistance() {
        XCTAssertEqual(distanceMeters(palermo, palermo), 0, accuracy: 0)
        XCTAssertEqual(distanceMeters(LatLng(lat: 0, lng: 0), LatLng(lat: 1, lng: 0)), 111_195, accuracy: 1)
        XCTAssertEqual(distanceMeters(LatLng(lat: 60, lng: 0), LatLng(lat: 60, lng: 1)), 55_597.9, accuracy: 5)
    }

    func testOffsetMetersRoundTripsThroughDistance() {
        XCTAssertEqual(distanceMeters(palermo, offsetMeters(palermo, eastM: 100, northM: 0)), 100, accuracy: 0.1)
        XCTAssertEqual(distanceMeters(palermo, offsetMeters(palermo, eastM: 90, northM: 120)), 150, accuracy: 0.2)
        let south = LatLng(lat: -33.9, lng: -70.6)
        XCTAssertEqual(distanceMeters(south, offsetMeters(south, eastM: 100, northM: 100)), 141.42, accuracy: 0.3)
    }

    func testDefaultAreaCenterIsFixedDistanceAwayInTheGivenDirection() {
        let north = defaultAreaCenter(exact: palermo, bearingRad: 0)
        XCTAssertEqual(distanceMeters(palermo, north), defaultAreaOffsetM, accuracy: 0.2)
        XCTAssertGreaterThan(north.lat, palermo.lat)
        let east = defaultAreaCenter(exact: palermo, bearingRad: .pi / 2)
        XCTAssertEqual(distanceMeters(palermo, east), defaultAreaOffsetM, accuracy: 0.2)
        XCTAssertGreaterThan(east.lng, palermo.lng)
    }

    func testClamp() {
        let valid = offsetMeters(palermo, eastM: 0, northM: 120)
        XCTAssertEqual(clampAreaCenter(exact: palermo, candidate: valid), valid)

        let near = clampAreaCenter(exact: palermo, candidate: offsetMeters(palermo, eastM: 0, northM: 10))
        XCTAssertEqual(distanceMeters(palermo, near), minAreaOffsetM, accuracy: 0.2)
        XCTAssertGreaterThan(near.lat, palermo.lat)

        let far = clampAreaCenter(exact: palermo, candidate: offsetMeters(palermo, eastM: 500, northM: 0))
        XCTAssertEqual(distanceMeters(palermo, far), maxAreaOffsetM, accuracy: 0.3)
        XCTAssertGreaterThan(far.lng, palermo.lng)

        XCTAssertEqual(distanceMeters(palermo, clampAreaCenter(exact: palermo, candidate: palermo)), minAreaOffsetM, accuracy: 0.2)

        let diagonal = offsetMeters(palermo, eastM: 90, northM: 90)
        XCTAssertEqual(clampAreaCenter(exact: palermo, candidate: diagonal), diagonal)
    }

    func testClampKeepsTheDirectionOfADiagonalCandidate() {
        let clamped = clampAreaCenter(exact: palermo, candidate: offsetMeters(palermo, eastM: 400, northM: 300))
        XCTAssertEqual(distanceMeters(palermo, clamped), maxAreaOffsetM, accuracy: 0.3)
        let northM = (clamped.lat - palermo.lat) * 111_195
        let eastM = (clamped.lng - palermo.lng) * 111_195 * cos(palermo.lat * .pi / 180)
        XCTAssertEqual(eastM / northM, 4.0 / 3.0, accuracy: 0.005)
    }

    func testClampReturnsTheCandidateUnchangedWhenAnInputIsNotValid() {
        let nan = LatLng(lat: .nan, lng: 13.3)
        XCTAssertTrue(clampAreaCenter(exact: palermo, candidate: nan).lat.isNaN)
        let valid = offsetMeters(palermo, eastM: 0, northM: 10)
        XCTAssertEqual(clampAreaCenter(exact: LatLng(lat: .nan, lng: .nan), candidate: valid), valid)
        XCTAssertEqual(clampAreaCenter(exact: LatLng(lat: .infinity, lng: 13.3), candidate: valid), valid)
    }

    func testRoundedShiftedAndValid() {
        XCTAssertEqual(LatLng(lat: 38.1157123456, lng: 13.3615349999).rounded(), LatLng(lat: 38.115712, lng: 13.361535))
        XCTAssertEqual(LatLng(lat: -33.9123456, lng: -70.6123454).rounded(), LatLng(lat: -33.912346, lng: -70.612345))
        XCTAssertTrue(LatLng(lat: .nan, lng: .nan).rounded().lat.isNaN)
        let shifted = LatLng(lat: 38.0005, lng: 13.0005).shifted(from: LatLng(lat: 38, lng: 13), to: LatLng(lat: 38.001, lng: 13.002))
        XCTAssertEqual(shifted.lat, 38.0015, accuracy: 1e-9)
        XCTAssertEqual(shifted.lng, 13.0025, accuracy: 1e-9)
        XCTAssertTrue(LatLng(lat: -90, lng: 180).isValid)
        XCTAssertFalse(LatLng(lat: 91, lng: 13.3).isValid)
        XCTAssertFalse(LatLng(lat: 38.1, lng: -181).isValid)
        XCTAssertFalse(LatLng(lat: .infinity, lng: 13.3).isValid)
    }

    // MARK: Nominatim e User-Agent OSM

    func testNominatimReadsLabelAndCoordinates() throws {
        let json = """
        [
          {"lat":"38.1157","lon":"13.3615","display_name":"Via Roma, Palermo, Sicilia, Italia"},
          {"lat":"38.2","lon":"13.4","display_name":"Via Roma, Bagheria"}
        ]
        """
        let results = try parseNominatimResults(json)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].label, "Via Roma, Palermo, Sicilia, Italia")
        XCTAssertEqual(results[0].point, LatLng(lat: 38.1157, lng: 13.3615))
        XCTAssertEqual(results[1].point, LatLng(lat: 38.2, lng: 13.4))
        XCTAssertTrue(try parseNominatimResults("[]").isEmpty)
    }

    func testNominatimSkipsBadEntriesAndFallsBackToCoordinates() throws {
        let json = """
        [{"display_name":"senza coordinate"},{"lat":"abc","lon":"13","display_name":"x"},
         {"lat":"95","lon":"13","display_name":"fuori range"},{"lat":"38.1","lon":"13.3","display_name":"valido"}]
        """
        XCTAssertEqual(try parseNominatimResults(json).map(\.label), ["valido"])
        XCTAssertEqual(try parseNominatimResults(#"[{"lat":"38.1","lon":"13.3","display_name":""}]"#)[0].label, "38.10000, 13.30000")
    }

    func testNominatimRejectsNonArrays() {
        for body in [#"{"error":"rate limited"}"#, "<html>502</html>"] {
            XCTAssertThrowsError(try parseNominatimResults(body)) {
                XCTAssertEqual($0.localizedDescription, "Risposta non valida")
            }
        }
    }

    func testOsmUserAgentIdentifiesTheAppAndTheOperator() {
        XCTAssertTrue(osmUserAgent.hasPrefix("SiciliaHostManager/"))
        XCTAssertTrue(osmUserAgent.contains("info@siciliahost.com"))
        XCTAssertTrue(osmUserAgent.contains("https://siciliahost.com"))
        XCTAssertFalse(osmUserAgent.contains("com.example"))
        XCTAssertTrue(osmUserAgent.unicodeScalars.allSatisfy { (32 ... 126).contains($0.value) })
        XCTAssertEqual(NominatimClient().userAgent, osmUserAgent)
    }

    // MARK: ServiceImport

    private func keys(_ r: ServiceImportResult) -> Set<String> { Set(r.matched.map(\.key)) }

    func testRecognisesCommonItalianNames() {
        let r = parsePastedServices("Wi-Fi\nLavatrice\nAria condizionata\nPiscina\nTV con Netflix")
        XCTAssertEqual(keys(r), ["wifi", "washing_machine", "air_conditioning", "pool", "tv", "streaming"])
        XCTAssertTrue(r.unmatched.isEmpty)
    }

    func testExclusionsAvoidFalseMatches() {
        XCTAssertEqual(keys(parsePastedServices("Forno a microonde")), ["microwave"])
        XCTAssertEqual(keys(parsePastedServices("Forno")), ["oven"])
        XCTAssertEqual(keys(parsePastedServices("Doccia esterna")), ["outdoor_shower"])
        XCTAssertEqual(keys(parsePastedServices("Doccia")), ["shower"])
        XCTAssertFalse(keys(parsePastedServices("Asciugamani da spiaggia")).contains("towels"))
        XCTAssertFalse(keys(parsePastedServices("Vasca da bagno per bambini")).contains("bathtub"))
    }

    func testSkipsUnavailableAndStopsAtTheNotIncludedSection() {
        let text = "Lavatrice\nNon disponibile: Lavastoviglie\nPiscina\nNon incluso\nAsciugatrice"
        XCTAssertEqual(keys(parsePastedServices(text)), ["washing_machine", "pool"])
    }

    func testIgnoresHeadersAndTheShowAllLine() {
        let r = parsePastedServices("Cosa troverai in questo alloggio\nRiscaldamento e aria condizionata\nMostra tutti i 45 servizi\nVentilatore")
        XCTAssertEqual(keys(r), ["fan"])
        XCTAssertTrue(r.unmatched.isEmpty)
    }

    func testPaidIsDetectedFromTheLine() {
        XCTAssertEqual(parsePastedServices("Parcheggio a pagamento in strada").matched, [ImportedService(key: "parking", paid: true)])
    }

    func testUnknownLinesBecomeCustomWithTheCategoryOfTheirSection() {
        let r = parsePastedServices("Famiglia\nPannolini\nBagno\nTappetino antiscivolo")
        XCTAssertEqual(r.unmatched, [
            ImportedCustom(name: "Pannolini", category: .family), ImportedCustom(name: "Tappetino antiscivolo", category: .bathroom),
        ])
    }

    func testStripsBulletsAndIgnoresEmptyOrSingleCharacterLines() {
        let r = parsePastedServices("• Wifi\n-  Barbecue\n\n*\nx")
        XCTAssertEqual(keys(r), ["wifi", "bbq"])
        XCTAssertTrue(r.unmatched.isEmpty)
    }

    func testLegacyAmenitiesAndDuplicates() {
        let r = servicesFromLegacyAmenities(["Wifi", "Cucina", "Telescopio"])
        XCTAssertEqual(keys(r), ["wifi", "kitchen"])
        XCTAssertEqual(r.unmatched.map(\.name), ["Telescopio"])
        XCTAssertEqual(parsePastedServices("Wifi\nWi-Fi veloce\nWifi").matched.count, 1)
    }

    func testNormalizeForMatch() {
        XCTAssertEqual(normalizeForMatch("Wi-Fi"), "wi fi")
        XCTAssertEqual(normalizeForMatch("  Caffè  Macchina!  "), "caffe macchina")
        XCTAssertEqual(normalizeForMatch("Doccia all'aperto"), "doccia all aperto")
    }

    // MARK: Annuncio Airbnb

    private let airbnbFixture = """
    <html><head>
    <meta property="og:title" content="Casa · Trappeto · ★4,81 · 4 camere da letto · 6 letti · 2 bagni"/>
    <script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Nome da ignorare"}</script>
    <script type="application/ld+json">{"@context":"https://schema.org","@type":"VacationRental","name":"Villetta dei Tramonti","description":"La casa e' in un'ottima posizione.","containsPlace":{"@type":"Accommodation","occupancy":{"@type":"QuantitativeValue","value":6}}}</script>
    </head><body></body></html>
    """

    func testParseAirbnbHtmlExtractsAllFields() {
        let r = parseAirbnbHtml(airbnbFixture)
        XCTAssertEqual(r.name, "Villetta dei Tramonti")
        XCTAssertEqual(r.description, "La casa e' in un'ottima posizione.")
        XCTAssertEqual(r.maxGuests, 6)
        XCTAssertEqual(r.bedrooms, 4)
        XCTAssertEqual(r.beds, 6)
        XCTAssertEqual(r.bathrooms, 2.0)
    }

    func testParseAirbnbHtmlHandlesDecimalCommaAndMissingData() {
        XCTAssertEqual(parseAirbnbHtml(#"<meta property="og:title" content="Casa · X · 1,5 bagni"/>"#).bathrooms, 1.5)
        XCTAssertEqual(parseAirbnbHtml("<html><body>pagina senza dati</body></html>"), AirbnbListingData())
    }

    // MARK: Foto

    func testMovePhoto() {
        XCTAssertEqual(movePhoto(["a", "b", "c"], from: 0, to: 2), ["b", "c", "a"])
        XCTAssertEqual(movePhoto(["a", "b", "c"], from: 2, to: 0), ["c", "a", "b"])
        let list = ["a", "b"]
        XCTAssertEqual(movePhoto(list, from: 0, to: 5), list)
        XCTAssertEqual(movePhoto(list, from: -1, to: 0), list)
        XCTAssertEqual(movePhoto(list, from: 1, to: 1), list)
    }

    func testRemovePhoto() {
        XCTAssertEqual(removePhoto(["a", "b", "c"], at: 1), ["a", "c"])
        XCTAssertEqual(removePhoto(["a"], at: 3), ["a"])
    }

    func testScaledSizeAndSampleSize() {
        XCTAssertTrue(scaledSize(width: 800, height: 600) == (800, 600))
        XCTAssertTrue(scaledSize(width: 4000, height: 2250) == (1600, 900))
        XCTAssertTrue(scaledSize(width: 2250, height: 4000) == (900, 1600))
        XCTAssertTrue(scaledSize(width: 100_000, height: 1) == (1600, 1))
        XCTAssertEqual(sampleSizeFor(width: 1200, height: 800), 1)
        XCTAssertEqual(sampleSizeFor(width: 4000, height: 3000), 2)
        XCTAssertEqual(sampleSizeFor(width: 8000, height: 6000), 4)
    }

    func testExifRotationDegrees() {
        XCTAssertEqual([1, 3, 6, 8, 0, 2, 99].map(exifRotationDegrees), [0, 180, 90, 270, 0, 0, 0])
    }

    // MARK: Link di invito

    func testInviteLinkBuildAndExtract() {
        XCTAssertEqual(InviteLink.build("ABCD2345"), "https://siciliahost.com/invito/ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("https://siciliahost.com/invito/ABCD2345"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("https://www.siciliahost.com/invito/abcd2345"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("Apri: https://siciliahost.com/invito/ABCD2345\nCodice: ABCD2345"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("siciliahost://invito/ABCD2345"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("  siciliahost://invito/ABCD2345\n"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("Ti invito a collaborare!\nApri: siciliahost://invito/ABCD2345\nCodice: ABCD2345"), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode(" abcd 2345 "), "ABCD2345")
        XCTAssertEqual(InviteLink.extractCode("abcd-2345"), "ABCD2345")
    }

    func testInviteLinkRejectsAnythingElse() {
        for text in ["", "   ", "ciao a tutti, come va?", "https://example.com/invito/ABCD2345",
                     "https://siciliahost.com.evil.example/invito/ABCD2345", "siciliahost://altro/ABCD2345", "siciliahost://invito/"] {
            XCTAssertNil(InviteLink.extractCode(text), text)
        }
    }

    // MARK: MRZ

    /// Riga MRZ della lunghezza richiesta: il testo significativo + riempimento con '<'.
    private func mrz(_ text: String, _ length: Int) -> String {
        precondition(text.count <= length)
        return text + String(repeating: "<", count: length - text.count)
    }

    func testTD3ItalianPassport() throws {
        let line1 = mrz("P<ITAROSSI<<MARIO<LUIGI", 44)
        let line2 = mrz("AA12345678ITA8001014M300101", 44) // controllo documento '8' in pos. 9, data di nascita '4' in pos. 19
        let r = try XCTUnwrap(MrzParser.parse("\(line1)\n\(line2)"))
        XCTAssertEqual(r.cognome, "ROSSI")
        XCTAssertEqual(r.nome, "MARIO LUIGI")
        XCTAssertEqual(r.sesso, "1")
        XCTAssertEqual(r.dataNascita, "01/01/1980")
        XCTAssertEqual(r.numeroDocumento, "AA1234567")
        XCTAssertEqual(r.tipoDocumento, "P")
        XCTAssertEqual(r.issuingCountryIso, "ITA")
        XCTAssertEqual(r.statoNascitaIso, "ITA")
        XCTAssertEqual(r.cittadinanzaIso, "ITA")
        XCTAssertTrue(r.checkDigitsValid)
    }

    func testTD3WithWrongCheckDigitsAndForeignPassport() throws {
        let bad = try XCTUnwrap(MrzParser.parse(mrz("P<ITAROSSI<<MARIO<LUIGI", 44) + "\n" + mrz("AA12345678ITA8001010M300101", 44)))
        XCTAssertFalse(bad.checkDigitsValid) // controllo della data di nascita cambiato da 4 a 0
        let de = try XCTUnwrap(MrzParser.parse(mrz("P<DEUSCHMIDT<<HANS", 44) + "\n" + mrz("C01234560<DEU7506089M2812319", 44)))
        XCTAssertEqual(de.cognome, "SCHMIDT")
        XCTAssertEqual(de.nome, "HANS")
        XCTAssertEqual(de.cittadinanzaIso, "DEU")
    }

    func testTD1ItalianIdentityCard() throws {
        let raw = [mrz("I<ITACA12345AA7", 30), mrz("8001014F300101<ITA", 30), mrz("ROSSI<<MARIA", 30)].joined(separator: "\n")
        let r = try XCTUnwrap(MrzParser.parse(raw))
        XCTAssertEqual(r.cognome, "ROSSI")
        XCTAssertEqual(r.nome, "MARIA")
        XCTAssertEqual(r.sesso, "2")
        XCTAssertEqual(r.dataNascita, "01/01/1980")
        XCTAssertEqual(r.numeroDocumento, "CA12345AA")
        XCTAssertEqual(r.tipoDocumento, "I")
        XCTAssertEqual(r.cittadinanzaIso, "ITA")
        XCTAssertTrue(r.checkDigitsValid)
    }

    func testMrzHelpers() {
        XCTAssertNil(MrzParser.parse("testo normale non MRZ"))
        XCTAssertEqual(MrzParser.checkDigit("520727"), 3)
        XCTAssertEqual(MrzParser.checkDigit("AA1234567"), 8)
        XCTAssertEqual(MrzParser.checkDigit("800101"), 4)
        let name = MrzParser.parseName("ROSSI<<MARIO<LUIGI<<<<<<<<<")
        XCTAssertEqual(name.cognome, "ROSSI")
        XCTAssertEqual(name.nome, "MARIO LUIGI")
        XCTAssertEqual(MrzParser.parseMrzDate("800101", currentYear: 2026), "01/01/1980")
        XCTAssertEqual(MrzParser.parseMrzDate("050615", currentYear: 2026), "15/06/2005")
    }
}
