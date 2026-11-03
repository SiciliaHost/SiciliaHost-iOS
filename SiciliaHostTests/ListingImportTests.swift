import XCTest
@testable import SiciliaHost

// `ui/wizard/importing/*Test.kt`: ImportApply, ImportRepository (errori), ImportReview, ImportUrls, ListingFetcher (parte
// pura), ListingImport, OwnershipDeclaration, PhotoProgress.

final class ListingImportTests: XCTestCase {
    private let draft = ListingDraft(
        portals: ["airbnb", "booking"],
        name: "Ciuririvù",
        description: "Una casa luminosa",
        maxGuests: 4, bedrooms: 2, beds: 2, bathrooms: 1.5,
        services: ["wifi", "air_conditioning", "non_esiste"],
        rules: ImportedRules(pets: "not_allowed", smoking: "boh", quietHours: "22:00-08:00", minAge: 18),
        checkInType: "keybox",
        address: "25 Via della Loggia, 90133 Palermo, Italia",
        cin: "IT082053C2HUI2C8GU",
        checkInFrom: "15:00", checkOutUntil: "11:00",
        location: ImportedLocation(lat: 38.1157, lng: 13.3615, area: "Palermo, Sicilia, Italia", exact: false),
        photos: ["https://a0.muscache.com/1.jpg"],
        found: ["name"]
    )

    // MARK: ImportApply

    func testFillsTheAppFieldsAndMarksThemToCheck() {
        let r = applyImport(draft, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 0)
        XCTAssertEqual(r.app.name, "Ciuririvù")
        XCTAssertEqual(r.app.maxGuests, "4")
        XCTAssertEqual(r.app.bedrooms, "2")
        XCTAssertEqual(r.app.beds, "2")
        XCTAssertEqual(r.app.bathrooms, "1.5")
        XCTAssertEqual(r.app.cin, "IT082053C2HUI2C8GU")
        XCTAssertEqual(r.app.checkInTime, "15:00")
        XCTAssertEqual(r.app.checkOutTime, "11:00")
        XCTAssertEqual(r.app.description, "Una casa luminosa")
        XCTAssertTrue(r.review.isSuperset(of: [ReviewKey.name, ReviewKey.cin, ReviewKey.bathrooms]))
    }

    func testNeverOverwritesWhatTheHostAlreadyWrote() {
        var app = AppFieldsDraft()
        app.name = "Mia casa"
        app.cin = "MIO"
        var site = SiteDraft()
        site.zone = "Mondello"
        let r = applyImport(draft, app: app, site: site, bearingRad: 0)
        XCTAssertEqual(r.app.name, "Mia casa")
        XCTAssertEqual(r.app.cin, "MIO")
        XCTAssertEqual(r.site.zone, "Mondello")
        XCTAssertFalse(r.review.contains(ReviewKey.name))
        XCTAssertFalse(r.review.contains(ReviewKey.zone))
    }

    func testLocationGetsAPinAndAnAreaInsideTheAllowedRing() throws {
        let r = applyImport(draft, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 1)
        XCTAssertEqual(r.site.zone, "Palermo")
        XCTAssertEqual(r.site.address, "25 Via della Loggia, 90133 Palermo, Italia")
        let pin = LatLng(lat: try XCTUnwrap(Double(r.site.lat)), lng: try XCTUnwrap(Double(r.site.lng)))
        let area = LatLng(lat: try XCTUnwrap(Double(r.site.areaLat)), lng: try XCTUnwrap(Double(r.site.areaLng)))
        XCTAssertEqual(pin.lat, 38.1157, accuracy: 1e-6)
        let d = distanceMeters(pin, area)
        XCTAssertTrue((minAreaOffsetM ... maxAreaOffsetM).contains(d), "area a \(d) m")
        XCTAssertTrue(r.review.isSuperset(of: [ReviewKey.location, ReviewKey.address, ReviewKey.zone]))
    }

    func testNoLocationLeavesThePositionAlone() {
        var noLocation = draft
        noLocation.location = nil
        let r = applyImport(noLocation, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 0)
        XCTAssertEqual(r.site.lat, "")
        XCTAssertEqual(r.site.areaLat, "")
        XCTAssertFalse(r.review.contains(ReviewKey.location))
    }

    func testSitePatchHasKnownServicesValidRulesAndCheckIn() {
        let r = applyImport(draft, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 0)
        let services = r.sitePatch["services"] as? [[String: Any]] ?? []
        XCTAssertEqual(services.compactMap { $0["key"] as? String }, ["wifi", "air_conditioning"])
        XCTAssertTrue(services.allSatisfy { $0["category"] is String })
        let rules = r.sitePatch["rulesStructured"] as? [String: Any] ?? [:]
        XCTAssertEqual(Set(rules.keys), ["pets", "quietHours", "minAge"])
        XCTAssertEqual(rules["pets"] as? String, "not_allowed")
        XCTAssertEqual(rules["quietHours"] as? String, "22:00-08:00")
        XCTAssertEqual(rules["minAge"] as? Int, 18)
        XCTAssertEqual(r.sitePatch["access"] as? [String: String], ["checkInType": "keybox"])
        XCTAssertTrue(r.review.contains(ReviewKey.services))
    }

    func testInvalidQuietHoursNeverEnterThePatch() {
        var bad = draft
        bad.rules = ImportedRules(pets: "not_allowed", quietHours: "99:99-08:00")
        let rules = applyImport(bad, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 0).sitePatch["rulesStructured"] as? [String: Any]
        XCTAssertEqual(rules?.count, 1)
        XCTAssertEqual(rules?["pets"] as? String, "not_allowed")
    }

    func testLocationChipIsFoundWithOnlyAnAddress() {
        var d = draft
        d.location = nil
        d.address = "25 Via della Loggia, Palermo"
        XCTAssertEqual(foundChips(d).first { $0.key == "location" }?.found, true)
    }

    func testEmptyImportGivesAnEmptyPatchAndNothingToCheck() {
        let r = applyImport(ListingDraft(), app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 0)
        XCTAssertTrue(r.sitePatch.isEmpty)
        XCTAssertTrue(r.review.isEmpty)
        XCTAssertEqual(r.app, AppFieldsDraft())
    }

    func testChipsShowWhatWasFoundAndWhatIsMissing() {
        var d = draft
        d.services = ["wifi", "air_conditioning"]
        d.location = nil
        d.address = nil
        let chips = foundChips(d)
        func chip(_ key: String) -> FoundChip? { chips.first { $0.key == key } }
        XCTAssertEqual(chip("name")?.found, true)
        XCTAssertEqual(chip("rooms")?.found, true)
        XCTAssertEqual(chip("services")?.count, 2)
        XCTAssertEqual(chip("photos")?.count, 1)
        XCTAssertEqual(chip("location")?.found, false)
        XCTAssertEqual(chip("cin")?.found, true)
        XCTAssertNil(chip("name")?.count)
    }

    func testAppliedSiteDraftPassesSiteValidation() {
        let r = applyImport(draft, app: AppFieldsDraft(), site: SiteDraft(), bearingRad: 1)
        XCTAssertTrue(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: r.site).isEmpty)
    }

    // MARK: ImportRepository (errori)

    func testExplainsTheErrorsTheHostCanActOn() {
        XCTAssertTrue(describeImportError(code: "RESOURCE_EXHAUSTED", message: "Troppe importazioni oggi").contains("domani"))
        XCTAssertTrue(describeImportError(code: "FAILED_PRECONDITION", message: "noData").contains("compila"))
        XCTAssertEqual(describeImportError(code: "UNAUTHENTICATED", message: nil), "Accedi di nuovo per continuare")
        XCTAssertTrue(describeImportError(code: "UNAVAILABLE", message: nil).contains("riprova"))
        XCTAssertTrue(describeImportError(code: "INTERNAL", message: "boom").contains("compila a mano"))
        XCTAssertFalse(describeImportError(code: "DEADLINE_EXCEEDED", message: nil).trimmed.isEmpty)
    }

    func testServerMessagesWithDataAreNeverShown() {
        XCTAssertFalse(describeImportError(code: "INVALID_ARGUMENT", message: "https://www.airbnb.it/rooms/1 non ammesso").contains("airbnb"))
    }

    // MARK: ImportReview

    func testEachStepOwnsItsKeys() {
        XCTAssertEqual(reviewKeysFor(.struttura), [ReviewKey.name])
        XCTAssertTrue(reviewKeysFor(.casa).contains(ReviewKey.cin))
        XCTAssertTrue(reviewKeysFor(.dove).contains(ReviewKey.zone))
        XCTAssertTrue(reviewKeysFor(.descrizione).contains(ReviewKey.services))
        XCTAssertTrue(reviewKeysFor(.invito).isEmpty)
    }

    func testTouchedKeysAreTheFieldsThatChanged() {
        var a = AppFieldsDraft()
        a.name = "Casa"
        a.cin = "X"
        var renamed = a
        renamed.name = "Casa 2"
        XCTAssertEqual(touchedKeys(a, renamed), [ReviewKey.name])
        var beds = a
        beds.bathrooms = "2"
        beds.beds = "3"
        XCTAssertEqual(touchedKeys(a, beds), [ReviewKey.bathrooms, ReviewKey.beds])
        XCTAssertTrue(touchedKeys(a, a).isEmpty)
        var s = SiteDraft()
        s.zone = "Palermo"
        var zone = s
        zone.zone = "Cefalù"
        XCTAssertEqual(touchedKeys(s, zone), [ReviewKey.zone])
        var moved = s
        moved.lat = "38.1"
        XCTAssertEqual(touchedKeys(s, moved), [ReviewKey.location])
    }

    // MARK: ImportUrls

    func testAcceptsPortalLinksAndForcesHttps() {
        XCTAssertEqual(cleanListingUrl(.airbnb, "airbnb.it/rooms/1"), "https://airbnb.it/rooms/1")
        XCTAssertEqual(cleanListingUrl(.airbnb, " http://www.airbnb.it/rooms/1?x=1 "), "https://www.airbnb.it/rooms/1?x=1")
        XCTAssertEqual(cleanListingUrl(.airbnb, "https://www.airbnb.co.uk/rooms/1"), "https://www.airbnb.co.uk/rooms/1")
        XCTAssertNotNil(cleanListingUrl(.booking, "https://www.booking.com/Share-ySu2iJ"))
        XCTAssertNotNil(cleanListingUrl(.booking, "https://booking.com/hotel/it/x.it.html"))
    }

    func testRejectsOtherHostsAndOddInputs() {
        XCTAssertNil(cleanListingUrl(.airbnb, "https://airbnb.evil.com/rooms/1"))
        XCTAssertNil(cleanListingUrl(.booking, "https://booking.com.evil.net/x"))
        XCTAssertNil(cleanListingUrl(.airbnb, "https://user@airbnb.it/rooms/1"))
        XCTAssertNil(cleanListingUrl(.airbnb, "javascript://airbnb.it/rooms/1"))
        XCTAssertNil(cleanListingUrl(.airbnb, "non è un link"))
        XCTAssertNil(cleanListingUrl(.airbnb, ""))
        XCTAssertNil(cleanListingUrl(.booking, "https://www.airbnb.it/rooms/1"))
    }

    func testProblemTextOnlyForNonBlankWrongLinks() {
        XCTAssertNil(urlProblem(.airbnb, ""))
        XCTAssertNil(urlProblem(.airbnb, "https://www.airbnb.it/rooms/1"))
        XCTAssertEqual(urlProblem(.booking, "https://www.airbnb.it/rooms/1"), "Questo non sembra un link di Booking")
    }

    // MARK: ListingFetcher (parte pura)

    func testDecodesAJavaScriptString() {
        XCTAssertEqual(decodeJsString("\"<html>\""), "<html>")
        XCTAssertEqual(decodeJsString("\"riga1\\nriga2\""), "riga1\nriga2")
        XCTAssertEqual(decodeJsString("\"a\\\"b\""), "a\"b")
        XCTAssertNil(decodeJsString("null"))
        XCTAssertNil(decodeJsString(nil))
        XCTAssertNil(decodeJsString("123"))
    }

    func testRecognisesTheRealBookingPageAndNotTheChallenge() {
        XCTAssertTrue(looksLikeBookingData(#"<html><script data-capla-store-data="apollo" type="application/json">{}</script></html>"#))
        XCTAssertFalse(looksLikeBookingData("<html><script src=\"https://x.awswaf.com/challenge.js\"></script></html>"))
        XCTAssertFalse(looksLikeBookingData(""))
    }

    func testPortalHostsAreStrict() {
        XCTAssertTrue(isAirbnbHost("www.airbnb.it"))
        XCTAssertTrue(isAirbnbHost("airbnb.co.uk"))
        XCTAssertTrue(isAirbnbHost("AIRBNB.com"))
        XCTAssertFalse(isAirbnbHost("airbnb.evil.com"))
        XCTAssertFalse(isAirbnbHost("www.airbnb.attacker.org"))
        XCTAssertFalse(isAirbnbHost("evilairbnb.com"))
        XCTAssertFalse(isAirbnbHost("booking.com"))
        XCTAssertTrue(isBookingHost("www.booking.com"))
        XCTAssertFalse(isBookingHost("booking.com.evil.io"))
    }

    func testOnlyHttpsAirbnbUrlsAreFollowed() {
        XCTAssertTrue(isSafeAirbnbUrl(URL(string: "https://www.airbnb.it/rooms/1")!))
        XCTAssertFalse(isSafeAirbnbUrl(URL(string: "http://www.airbnb.it/rooms/1")!))
        XCTAssertFalse(isSafeAirbnbUrl(URL(string: "https://airbnb.evil.com/rooms/1")!))
        XCTAssertFalse(isSafeAirbnbUrl(URL(string: "file:///etc/passwd")!))
    }

    func testResolvesRelativeRedirects() {
        let base = URL(string: "https://www.airbnb.it/rooms/1")!
        XCTAssertEqual(resolveRedirect(base, "/rooms/2")?.absoluteString, "https://www.airbnb.it/rooms/2")
        XCTAssertEqual(resolveRedirect(base, "https://x.com/a")?.absoluteString, "https://x.com/a")
    }

    func testRequiresHttpsScheme() {
        XCTAssertTrue(isHttpsUrl("https://www.airbnb.it/rooms/1"))
        XCTAssertFalse(isHttpsUrl("http://www.airbnb.it/rooms/1"))
        XCTAssertFalse(isHttpsUrl("file:///x"))
        XCTAssertFalse(isHttpsUrl("javascript:alert(1)"))
    }

    func testCappedBufferStopsPastTheLimit() {
        var small = CappedBuffer(maxBytes: 10)
        XCTAssertTrue(small.append(Data("1234567890".utf8)))
        XCTAssertFalse(small.overflowed)
        var big = CappedBuffer(maxBytes: 100)
        var chunks = 0
        while big.append(Data(repeating: 97, count: 64)) { chunks += 1 }
        XCTAssertTrue(big.overflowed)
        XCTAssertLessThan(chunks, 3)
    }

    // MARK: ListingImport

    private let response: [String: Any] = [
        "importId": "imp1",
        "listings": [Any](),
        "failures": [["portal": "booking", "code": "noData"]],
        "merged": [
            "portals": ["airbnb", "booking"],
            "name": "Ciuririvù",
            "description": "Una casa luminosa",
            "descriptionLanguage": "en-gb",
            "maxGuests": 4,
            "bedrooms": Int64(2),
            "beds": 2.0,
            "bathrooms": 1.5,
            "services": ["wifi", "air_conditioning"],
            "otherServices": ["Culla"],
            "rules": ["pets": "not_allowed", "quietHours": "22:00-08:00", "minAge": 18] as [String: Any],
            "checkInType": "keybox",
            "address": "25 Via della Loggia, 90133 Palermo, Italia",
            "cin": "IT082053C2HUI2C8GU",
            "checkInFrom": "15:00",
            "checkOutUntil": "11:00",
            "location": ["lat": 38.1157, "lng": 13.3615, "area": "Palermo, Sicilia, Italia", "exact": true] as [String: Any],
            "photos": ["https://a0.muscache.com/1.jpg", "https://cf.bstatic.com/2.jpg"],
            "found": ["name", "maxGuests", "services"],
            "conflicts": [
                ["field": "bathrooms", "values": ["airbnb": 1.5, "booking": 1] as [String: Any], "chosen": 1.5] as [String: Any],
            ],
        ] as [String: Any],
    ]

    func testReadsTheMergedListing() throws {
        let r = try XCTUnwrap(parseListingImport(response))
        XCTAssertEqual(r.importId, "imp1")
        XCTAssertEqual(r.failedPortals, ["booking"])
        let d = r.draft
        XCTAssertEqual(d.name, "Ciuririvù")
        XCTAssertEqual(d.descriptionLanguage, "en-gb")
        XCTAssertEqual(d.maxGuests, 4)
        XCTAssertEqual(d.bedrooms, 2)
        XCTAssertEqual(d.beds, 2)
        XCTAssertEqual(d.bathrooms, 1.5)
        XCTAssertEqual(d.services, ["wifi", "air_conditioning"])
        XCTAssertEqual(d.rules.pets, "not_allowed")
        XCTAssertNil(d.rules.smoking)
        XCTAssertEqual(d.rules.quietHours, "22:00-08:00")
        XCTAssertEqual(d.rules.minAge, 18)
        XCTAssertEqual(d.checkInType, "keybox")
        XCTAssertEqual(d.cin, "IT082053C2HUI2C8GU")
        XCTAssertEqual(d.checkOutUntil, "11:00")
        XCTAssertEqual(d.location?.lat, 38.1157)
        XCTAssertEqual(d.location?.exact, true)
        XCTAssertEqual(d.photos.count, 2)
        XCTAssertEqual(d.portals, ["airbnb", "booking"])
    }

    func testReadsConflictsWithBothValuesAsText() throws {
        let c = try XCTUnwrap(parseListingImport(response)?.draft.conflicts.first)
        XCTAssertEqual(c.field, "bathrooms")
        XCTAssertEqual(c.values, ["airbnb": "1.5", "booking": "1"])
        XCTAssertEqual(c.chosen, "1.5")
    }

    func testABadResponseIsNil() {
        XCTAssertNil(parseListingImport(nil))
        XCTAssertNil(parseListingImport(["merged": [String: Any]()]))
        XCTAssertNil(parseListingImport(["importId": "x"]))
    }

    func testAnEmptyMergedListingStillParses() {
        let r = parseListingImport(["importId": "x", "merged": ["portals": ["airbnb"]] as [String: Any]])
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.draft.services, [])
        XCTAssertNil(r?.draft.name)
    }

    func testReadsAPhotoBatch() throws {
        let b = try XCTUnwrap(parsePhotoBatch([
            "stored": [["sourceUrl": "s1", "url": "u1"], ["sourceUrl": "s2", "url": "u2"]],
            "failed": ["s3"],
            "nextOffset": 6,
            "total": 29,
        ] as [String: Any]))
        XCTAssertEqual(b.stored, ["u1", "u2"])
        XCTAssertEqual(b.failedCount, 1)
        XCTAssertEqual(b.nextOffset, 6)
        XCTAssertEqual(b.total, 29)
        let last = parsePhotoBatch(["stored": [Any](), "failed": [Any](), "nextOffset": NSNull(), "total": 0] as [String: Any])
        XCTAssertNotNil(last)
        XCTAssertNil(last?.nextOffset)
        XCTAssertNil(parsePhotoBatch("boh"))
    }

    // MARK: OwnershipDeclaration

    func testOwnershipVersionMatchesTheServer() {
        XCTAssertEqual(ownershipTextVersion, "v1-2026-10-28")
        XCTAssertFalse(ownershipText.trimmed.isEmpty)
        XCTAssertLessThan(ownershipText.count, 300)
    }

    // MARK: PhotoProgress

    func testAccumulatesBatchesAfterTheBase() {
        var p = PhotoProgress(base: ["old"]).afterBatch(["a", "b"], next: 2)
        XCTAssertEqual(p.photos(), ["old", "a", "b"])
        XCTAssertEqual(p.offset, 2)
        XCTAssertFalse(p.finished)
        p = p.afterBatch(["c"], next: nil)
        XCTAssertEqual(p.photos(), ["old", "a", "b", "c"])
        XCTAssertTrue(p.finished)
    }

    func testRetryDoesNotDuplicateAlreadySavedPhotos() {
        var p = PhotoProgress(base: []).afterBatch(["a", "b"], next: 2)
        XCTAssertTrue(p.unwritten)
        XCTAssertEqual(p.offset, 2)
        p = p.afterBatch(["c"], next: nil).written()
        XCTAssertEqual(p.photos(), ["a", "b", "c"])
        XCTAssertFalse(p.unwritten)
    }

    func testEmptyBatchKeepsOffsetWhenNoNext() {
        let p = PhotoProgress(base: ["x"]).afterBatch([], next: nil)
        XCTAssertEqual(p.photos(), ["x"])
        XCTAssertFalse(p.unwritten)
        XCTAssertTrue(p.finished)
    }

    func testSameUrlTwiceIsKeptOnce() {
        XCTAssertEqual(PhotoProgress(base: ["a"]).afterBatch(["a", "b"], next: nil).photos(), ["a", "b"])
    }
}
