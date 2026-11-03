import XCTest
@testable import SiciliaHost

// Specifica: SiteDraftTest dell'app Android (numeri, bozza dal documento, cosa manca, errori, patch differenziale).
final class SiteDraftTests: XCTestCase {
    private func draft(_ edit: (inout SiteDraft) -> Void) -> SiteDraft {
        var d = SiteDraft()
        edit(&d)
        return d
    }

    private var complete: SiteDraft {
        draft { $0.published = true; $0.zone = "Mondello"; $0.price = "120"; $0.cleaningFee = "30"
            $0.depositPercentage = "30"; $0.freeCancelDays = "7" }
    }

    private typealias N = SiteNumbers

    func testParseAcceptsCommaAndRejectsGarbage() {
        XCTAssertEqual(N.parse("12,5"), 12.5)
        XCTAssertEqual(N.parse(" 7 "), 7)
        for bad in ["abc", "NaN", "", "1.000", "12.500", "-1.000", "1.234.567", "0.125", "1e3", "12f", "12d", "+5", "1.", ".5", "Infinity"] {
            XCTAssertNil(N.parse(bad), bad)
        }
    }

    func testParseAcceptsPlainDecimals() {
        XCTAssertEqual(N.parse("1.5"), 1.5)
        XCTAssertEqual(N.parse("1,5"), 1.5)
        XCTAssertEqual(N.parse("99,50"), 99.5)
        XCTAssertEqual(N.parse("1.25"), 1.25)
        XCTAssertEqual(N.parse("1.2345"), 1.2345)
        XCTAssertEqual(N.parse("1,000"), 1)
        XCTAssertEqual(N.parse("0,125"), 0.125)
        XCTAssertEqual(N.parse("-3"), -3)
        XCTAssertEqual(N.parse("120"), 120)
    }

    func testFormatRoundTripsAndIsNeverAmbiguous() {
        XCTAssertEqual(N.parse(N.format(89.5)), 89.5)
        XCTAssertEqual(N.parse(N.format(120)), 120)
        XCTAssertEqual(N.parse(N.format(38.2)), 38.2)
        XCTAssertEqual(N.format(38.123), "38,123")
        XCTAssertEqual(N.parse(N.format(38.123)), 38.123)
        XCTAssertEqual(N.parse(N.format(-0.125)), -0.125)
        XCTAssertEqual(N.format(1234.567), "1234.567")
        XCTAssertEqual(N.format(nil), "")
        XCTAssertEqual(N.format(90), "90")
        XCTAssertEqual(N.format(89.5), "89.5")
    }

    func testDraftFromDocumentMapsEveryField() {
        var c = PropertySiteContent()
        c.id = "p1"; c.name = "Casa"; c.publishedOnSite = true; c.zone = "Mondello"; c.basePricePerNight = 120
        c.cleaningFee = 30; c.depositPercentage = 30; c.cancellationPolicy = SiteCancellationPolicy(freeUntilDaysBefore: 7)
        c.requiresManualConfirmation = true; c.photos = ["a"]; c.coordinates = SiteCoordinates(lat: 38.2, lng: 13.3)
        c.address = "Via Roma 1, Palermo"; c.publicArea = SiteCoordinates(lat: 38.21, lng: 13.31)
        c.wifiInfo = SiteWifiInfo(ssid: "net", password: "pw"); c.managerContact = SiteManagerContact(name: "Ale", phone: "+39")
        c.localTips = ["it": "Consigli"]; c.departureChecklist = ["it": "Chiudi"]; c.titleTranslations = ["en": "House"]
        c.descriptionTranslations = ["en": "Desc"]; c.houseRulesTranslations = ["en": "Rules"]
        let expected = draft {
            $0.published = true; $0.zone = "Mondello"; $0.price = "120"; $0.cleaningFee = "30"; $0.depositPercentage = "30"
            $0.freeCancelDays = "7"; $0.manualConfirmation = true; $0.lat = "38.2"; $0.lng = "13.3"
            $0.address = "Via Roma 1, Palermo"; $0.areaLat = "38.21"; $0.areaLng = "13.31"; $0.wifiSsid = "net"
            $0.wifiPassword = "pw"; $0.managerName = "Ale"; $0.managerPhone = "+39"; $0.localTips = ["it": "Consigli"]
            $0.departureChecklist = ["it": "Chiudi"]; $0.titleTr = ["en": "House"]; $0.descriptionTr = ["en": "Desc"]
            $0.houseRulesTr = ["en": "Rules"]
        }
        XCTAssertEqual(SiteDraft(c), expected)
        var empty = PropertySiteContent()
        empty.id = "p1"; empty.name = "Casa"
        XCTAssertEqual(SiteDraft(empty), SiteDraft())
    }

    func testPublishBlockers() {
        XCTAssertEqual(SiteDraftLogic.publishBlockers(SiteDraft(), photoCount: 0), [
            "Zona", "Prezzo a notte (maggiore di 0)", "Costo pulizie", "Caparra %", "Giorni di cancellazione gratuita", "Almeno una foto",
        ])
        var zeroFee = complete; zeroFee.cleaningFee = "0"
        XCTAssertTrue(SiteDraftLogic.publishBlockers(zeroFee, photoCount: 1).isEmpty)
        var zeroPrice = complete; zeroPrice.price = "0"
        XCTAssertEqual(SiteDraftLogic.publishBlockers(zeroPrice, photoCount: 1), ["Prezzo a notte (maggiore di 0)"])
    }

    func testFieldErrors() {
        var emptied = complete; emptied.zone = ""; emptied.price = ""; emptied.freeCancelDays = ""
        let e1 = SiteDraftLogic.fieldErrors(original: complete, current: emptied)
        XCTAssertEqual(e1["zone"], "Non si può svuotare")
        XCTAssertEqual(e1["price"], "Non si può svuotare")
        XCTAssertEqual(e1["freeCancelDays"], "Non si può svuotare")
        XCTAssertTrue(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: SiteDraft()).isEmpty)
        let e2 = SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.depositPercentage = "101"; $0.price = "-5" })
        XCTAssertEqual(e2["deposit"], "Massimo 100")
        XCTAssertEqual(e2["price"], "Numero non valido (0 o più)")
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.lat = "38.1" })["lng"],
                       "Inserisci sia latitudine che longitudine")
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.lat = "95"; $0.lng = "13" })["lat"],
                       "Latitudine non valida (-90..90)")
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.localTips = ["en": "Tips"] })["localTips"],
                       "Scrivi prima la versione italiana")
        XCTAssertTrue(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.localTips = ["it": "Consigli"] }).isEmpty)
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(),
                                                  current: draft { $0.address = String(repeating: "a", count: 301) })["address"],
                       "Massimo 300 caratteri")
    }

    func testPatchBasics() {
        XCTAssertTrue(SiteDraftLogic.buildPatch(original: SiteDraft(), current: SiteDraft(), photos: []).isEmpty)
        let p1 = SiteDraftLogic.buildPatch(original: SiteDraft(), current: draft { $0.price = "99,5" }, photos: [])
        XCTAssertEqual(Set(p1.keys), ["basePricePerNight"])
        XCTAssertEqual(p1["basePricePerNight"] as? Double, 99.5)

        let p2 = SiteDraftLogic.buildPatch(original: complete, current: complete, photos: ["a"])
        XCTAssertEqual(Set(p2.keys), ["zone", "basePricePerNight", "cleaningFee", "depositPercentage", "cancellationPolicy",
                                      "requiresManualConfirmation", "photos"])
        XCTAssertEqual(p2["cancellationPolicy"] as? [String: Int], ["freeUntilDaysBefore": 7])
        XCTAssertEqual(p2["photos"] as? [String], ["a"])
        XCTAssertEqual(p2["requiresManualConfirmation"] as? Bool, false)

        var unpublished = complete; unpublished.published = false
        XCTAssertEqual(SiteDraftLogic.buildPatch(original: unpublished, current: complete, photos: ["a"])["publishedOnSite"] as? Bool, true)
    }

    func testPatchNullsAndObjects() {
        let cleared = SiteDraftLogic.buildPatch(original: draft { $0.lat = "38.1"; $0.lng = "13.3" }, current: SiteDraft(), photos: [])
        XCTAssertTrue(cleared["coordinates"] is NSNull)
        let coords = SiteDraftLogic.buildPatch(original: SiteDraft(), current: draft { $0.lat = "38,1"; $0.lng = "13.3" }, photos: [])
        XCTAssertEqual(coords["coordinates"] as? [String: Double], ["lat": 38.1, "lng": 13.3])
        let tr = SiteDraftLogic.buildPatch(original: SiteDraft(), current: draft { $0.titleTr = ["en": " House ", "fr": "  "] }, photos: [])
        XCTAssertEqual(tr["titleTranslations"] as? [String: String], ["en": "House"])
        let trCleared = SiteDraftLogic.buildPatch(original: draft { $0.titleTr = ["en": "House"] }, current: SiteDraft(), photos: [])
        XCTAssertTrue(trCleared["titleTranslations"] is NSNull)
        let wifi = SiteDraftLogic.buildPatch(original: draft { $0.managerName = "Ale"; $0.managerPhone = "+39" },
                                             current: draft { $0.wifiSsid = "net"; $0.wifiPassword = "pw" }, photos: [])
        XCTAssertEqual(wifi["wifiInfo"] as? [String: String], ["ssid": "net", "password": "pw"])
        XCTAssertTrue(wifi["managerContact"] is NSNull)
        XCTAssertNil(wifi["zone"])
    }

    // MARK: Posizione

    private func located(areaNorthMeters: Double? = 150) -> SiteDraft {
        let exact = LatLng(lat: 38.1157, lng: 13.3615)
        let area = areaNorthMeters.map { offsetMeters(exact, eastM: 0, northM: $0).rounded() }
        return draft {
            $0.address = "Via Roma 1, Palermo"; $0.lat = N.format(exact.lat); $0.lng = N.format(exact.lng)
            $0.areaLat = N.format(area?.lat); $0.areaLng = N.format(area?.lng)
        }
    }

    func testPositionRoundTrip() {
        let d = located()
        XCTAssertEqual(d.positionState.exact, LatLng(lat: 38.1157, lng: 13.3615))
        XCTAssertEqual(d.withPosition(d.positionState), d)
        let cleared = d.withPosition(PositionState())
        XCTAssertEqual(cleared.lat, "")
        XCTAssertEqual(cleared.areaLng, "")
    }

    func testPositionGroupTravelsTogether() {
        let original = located()
        var onlyAddress = original; onlyAddress.address = "Via Roma 2, Palermo"
        let patch = SiteDraftLogic.buildPatch(original: original, current: onlyAddress, photos: [])
        XCTAssertEqual(Set(patch.keys), ["address", "coordinates", "publicArea"])
        XCTAssertEqual(patch["address"] as? String, "Via Roma 2, Palermo")
        XCTAssertEqual(patch["coordinates"] as? [String: Double], ["lat": 38.1157, "lng": 13.3615])
        let moved = SiteDraftLogic.buildPatch(original: located(areaNorthMeters: 150), current: located(areaNorthMeters: 200), photos: [])
        XCTAssertNotNil(moved["coordinates"])
        XCTAssertNotNil(moved["publicArea"])
        let gone = SiteDraftLogic.buildPatch(original: located(), current: SiteDraft(), photos: [])
        XCTAssertTrue(gone["address"] is NSNull)
        XCTAssertTrue(gone["coordinates"] is NSNull)
        XCTAssertTrue(gone["publicArea"] is NSNull)
        var priceOnly = original; priceOnly.price = "99"
        XCTAssertEqual(Set(SiteDraftLogic.buildPatch(original: original, current: priceOnly, photos: []).keys), ["basePricePerNight"])
    }

    func testPositionErrors() {
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: located(areaNorthMeters: nil))["area"],
                       "Imposta l'area pubblica (Modifica posizione)")
        let legacy = located(areaNorthMeters: nil)
        var legacyPrice = legacy; legacyPrice.price = "99"
        XCTAssertNil(SiteDraftLogic.fieldErrors(original: legacy, current: legacyPrice)["area"])
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: draft { $0.areaLat = "38.1"; $0.areaLng = "13.3" })["area"],
                       "Manca il pin esatto")
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: located(areaNorthMeters: 400))["area"],
                       "Il pin esatto deve stare dentro l'area pubblica")
        XCTAssertEqual(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: located(areaNorthMeters: 5))["area"],
                       "L'area pubblica è troppo vicina al pin: sposta la maniglia")
        XCTAssertTrue(SiteDraftLogic.fieldErrors(original: SiteDraft(), current: located()).isEmpty)
    }
}
