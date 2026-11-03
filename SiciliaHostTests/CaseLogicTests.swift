import XCTest
@testable import SiciliaHost

// Specifica: AppFieldsDraftTest, CaseLogicTest, CaseSaveLogicTest, CredentialsLogicTest, DeleteCaseTest, WizardLogicTest,
// PositionStateTest dell'app Android. (SiteDraftSaverTest: il salvataggio nel Bundle non esiste su iOS; c'è un test
// di andata e ritorno `Codable` al suo posto.)
final class CaseLogicTests: XCTestCase {
    private var property: Property {
        var p = Property(id: "p1", name: "Casa Mare")
        p.cin = "IT123"; p.maxGuests = 4; p.bedrooms = 2; p.beds = 3; p.bathrooms = 1.5
        p.description = "Bella"; p.amenities = ["Wifi", "Cucina"]; p.checkInTime = "15:00"; p.checkOutTime = "11:00"
        p.houseRules = "No fumo"; p.icalUrlAirbnb = "https://a"; p.icalUrlBooking = nil; p.isManagedOnCommission = true
        p.idAppartamento = 7
        return p
    }

    // MARK: AppFieldsDraftTest

    func testRoundTripKeepsEveryField() {
        XCTAssertEqual(AppFieldsDraft(property).apply(to: property), property)
    }

    func testBlankFieldsBecomeNilAndNumbersAreParsed() {
        var d = AppFieldsDraft(property)
        d.cin = "  "; d.maxGuests = "6"; d.bathrooms = "2,5"; d.amenitiesText = "Wifi\n\n TV "
        let out = d.apply(to: property)
        XCTAssertNil(out.cin)
        XCTAssertEqual(out.maxGuests, 6)
        XCTAssertEqual(out.bathrooms, 2.5)
        XCTAssertEqual(out.amenities, ["Wifi", "TV"])
    }

    func testValidationRequiresAName() {
        var d = AppFieldsDraft(property)
        XCTAssertNil(d.error())
        d.name = " "
        XCTAssertEqual(d.error(), "Il nome è obbligatorio")
        d.name = "x"; d.idAppartamento = "abc"
        XCTAssertEqual(d.error(), "ID Appartamento deve essere un numero")
    }

    func testAdminPatchContainsOnlyListingFieldsThatChanged() {
        let original = AppFieldsDraft(property)
        var changed = original
        changed.name = "Casa Nuova"; changed.maxGuests = "5"; changed.icalUrlAirbnb = "https://zzz"; changed.isManagedOnCommission = false
        let patch = changed.adminPatch(original: original)
        XCTAssertEqual(Set(patch.keys), ["name", "maxGuests"])
        XCTAssertEqual(patch["name"] as? String, "Casa Nuova")
        XCTAssertEqual(patch["maxGuests"] as? Int, 5)
        XCTAssertTrue(original.adminPatch(original: original).isEmpty)
    }

    func testDirectFieldsCarryOnlyTheSheetFields() {
        let f = AppFieldsDraft(property).directFields()
        XCTAssertEqual(Set(f.keys), [
            "name", "cin", "maxGuests", "bedrooms", "beds", "bathrooms", "description", "amenities", "houseRules",
            "checkInTime", "checkOutTime", "icalUrlAirbnb", "icalUrlBooking", "idAppartamento", "isManagedOnCommission",
        ])
        XCTAssertEqual(f["name"] as? String, "Casa Mare")
        XCTAssertEqual(f["amenities"] as? [String], ["Wifi", "Cucina"])
        XCTAssertEqual(f["isManagedOnCommission"] as? Bool, true)
        XCTAssertTrue(f["icalUrlBooking"] is NSNull)
    }

    // MARK: CaseLogicTest

    private func c(_ id: String, _ name: String, _ status: ListingStatus, owner: String = "h1", members: Set<String>? = nil) -> CaseSummary {
        CaseSummary(id: id, name: name, ownerUid: owner, memberUids: members ?? [owner], status: status, zone: nil,
                    coverUrl: nil, price: nil, missing: [])
    }

    private var all: [CaseSummary] {
        [c("a", "Zeta", .approved, owner: "me"), c("b", "Beta", .pending, owner: "h1"),
         c("c", "Alfa", .draft, owner: "h2", members: ["h2", "me"]), c("d", "Delta", .pending, owner: "h2")]
    }

    func testFilters() {
        XCTAssertEqual(CaseLogic.filter(all, .mine, myUid: "me").map(\.id), ["a", "c"])
        XCTAssertEqual(CaseLogic.filter(all, .all, myUid: "me").count, 4)
        XCTAssertEqual(CaseLogic.filter(all, .host(uid: "h1"), myUid: "me").map(\.id), ["b"])
    }

    func testPendingFirstThenByName() {
        XCTAssertEqual(CaseLogic.sort(all).map(\.id), ["b", "d", "c", "a"])
        XCTAssertEqual(CaseLogic.pendingCount(all), 2)
    }

    func testHostSearchMatchesEmailNameAndHouseNames() {
        let hosts = [
            HostRow(uid: "u1", email: "anna@x.it", displayName: "Anna Rossi", propertyCount: 2, pendingCount: 1,
                    propertyNames: ["Casa Mare", "Villa Sole"]),
            HostRow(uid: "u2", email: "bruno@x.it", displayName: "", propertyCount: 1, pendingCount: 0, propertyNames: ["Baglio"]),
        ]
        XCTAssertEqual(CaseLogic.searchHosts(hosts, query: "rossi").map(\.uid), ["u1"])
        XCTAssertEqual(CaseLogic.searchHosts(hosts, query: "BAGLIO").map(\.uid), ["u2"])
        XCTAssertEqual(CaseLogic.searchHosts(hosts, query: "villa").map(\.uid), ["u1"])
        XCTAssertEqual(CaseLogic.searchHosts(hosts, query: "  ").count, 2)
    }

    func testSections() {
        XCTAssertTrue(CaseLogic.visibleSections(canManage: true, onSiteTrack: true).contains(.gestione))
        XCTAssertFalse(CaseLogic.visibleSections(canManage: false, onSiteTrack: true).contains(.gestione))
        XCTAssertEqual(CaseLogic.visibleSections(canManage: false, onSiteTrack: true).count, CaseSection.allCases.count - 1)
        XCTAssertEqual(CaseLogic.visibleSections(canManage: true, onSiteTrack: false), [.informazioni, .orari, .gestione])
        XCTAssertEqual(CaseLogic.visibleSections(canManage: false, onSiteTrack: false), [.informazioni, .orari])
        XCTAssertEqual(CaseSection.allCases, [.stato, .informazioni, .prezzi, .foto, .contenuti, .posizione, .infoOspiti, .orari, .gestione])
    }

    func testRealignFollowsTheNewOriginalOnlyWhenTheDraftWasUntouched() {
        XCTAssertEqual(CaseLogic.realign(oldOriginal: "vecchio", newOriginal: "nuovo", draft: "vecchio"), "nuovo")
        XCTAssertEqual(CaseLogic.realign(oldOriginal: "vecchio", newOriginal: "nuovo", draft: "mio"), "mio")
        XCTAssertEqual(CaseLogic.realign(oldOriginal: "a", newOriginal: "a", draft: "mio"), "mio")
    }

    // MARK: CaseSaveLogicTest, CredentialsLogicTest

    func testSavePlan() {
        XCTAssertEqual(CaseSaveLogic.planSave(appChanged: false, siteChanged: false, access: .direct), SavePlan(app: .none, site: false))
        XCTAssertEqual(CaseSaveLogic.planSave(appChanged: true, siteChanged: true, access: .direct), SavePlan(app: .direct, site: true))
        XCTAssertEqual(CaseSaveLogic.planSave(appChanged: true, siteChanged: false, access: .viaAdmin).app, .adminCallable)
        XCTAssertEqual(CaseSaveLogic.planSave(appChanged: true, siteChanged: true, access: .readOnly), SavePlan(app: .none, site: true))
    }

    func testPartialFailureMessageNamesTheFailedPart() {
        XCTAssertEqual(CaseSaveLogic.partialFailureMessage(appFailed: "boom", siteFailed: nil),
                       "Salvate le informazioni del sito; non salvate quelle della scheda: boom")
        XCTAssertEqual(CaseSaveLogic.partialFailureMessage(appFailed: nil, siteFailed: "boom"),
                       "Salvata la scheda; non salvate le informazioni del sito: boom")
        XCTAssertEqual(CaseSaveLogic.partialFailureMessage(appFailed: "a", siteFailed: "b"), "Salvataggio non riuscito: a / b")
    }

    func testCredentialsToSave() {
        let creds = AlloggiatiCredentials(utente: "u", password: "p", wsKey: "k")
        XCTAssertEqual(CaseSaveLogic.credentialsToSave(loaded: creds, isOwner: true), creds)
        XCTAssertNil(CaseSaveLogic.credentialsToSave(loaded: creds, isOwner: false))
        XCTAssertNil(CaseSaveLogic.credentialsToSave(loaded: nil, isOwner: true))
        XCTAssertEqual(CaseSaveLogic.credentialsToSave(loaded: AlloggiatiCredentials(), isOwner: true), AlloggiatiCredentials())
    }

    // MARK: DeleteCaseTest

    func testDeleteConfirmation() {
        XCTAssertEqual(DeleteCaseLogic.confirmName(name: "  Casa Mare ", id: "p1"), "Casa Mare")
        XCTAssertEqual(DeleteCaseLogic.confirmName(name: "   ", id: "p1"), "p1")
        XCTAssertTrue(DeleteCaseLogic.nameMatches(typed: " Casa Mare ", name: "Casa Mare", id: "p1"))
        XCTAssertFalse(DeleteCaseLogic.nameMatches(typed: "casa mare", name: "Casa Mare", id: "p1"))
        XCTAssertFalse(DeleteCaseLogic.nameMatches(typed: "Casa", name: "Casa Mare", id: "p1"))
        XCTAssertTrue(DeleteCaseLogic.nameMatches(typed: "p1", name: "", id: "p1"))
    }

    func testDeleteErrorMessages() {
        XCTAssertEqual(DeleteCaseLogic.errorMessage(code: "FAILED_PRECONDITION", details: ["activeBookings": 1]),
                       "Un ospite del sito ha un soggiorno in corso o futuro: annulla prima la prenotazione.")
        XCTAssertEqual(DeleteCaseLogic.errorMessage(code: "FAILED_PRECONDITION", details: ["activeBookings": 3]),
                       "3 ospiti del sito hanno un soggiorno in corso o futuro: annulla prima la prenotazione.")
        XCTAssertTrue(DeleteCaseLogic.errorMessage(code: "FAILED_PRECONDITION", details: nil).hasPrefix("Un ospite"))
        XCTAssertEqual(DeleteCaseLogic.errorMessage(code: "PERMISSION_DENIED", details: nil), "Solo il proprietario può eliminare la casa.")
        XCTAssertTrue(DeleteCaseLogic.errorMessage(code: "INVALID_ARGUMENT", details: nil).hasPrefix("Il nome non corrisponde"))
        XCTAssertTrue(DeleteCaseLogic.errorMessage(code: "INTERNAL", details: nil).hasPrefix("Eliminazione non riuscita"))
        XCTAssertTrue(DeleteCaseLogic.errorMessage(code: nil, details: nil).hasPrefix("Eliminazione non riuscita"))
    }

    // MARK: WizardLogicTest

    private var complete: SiteDraft {
        var s = SiteDraft()
        s.zone = "Cefalù"; s.price = "90"; s.cleaningFee = "40"; s.depositPercentage = "30"; s.freeCancelDays = "7"
        return s
    }

    private var named: AppFieldsDraft {
        var a = AppFieldsDraft()
        a.name = "Casa Mare"; a.cin = "IT082053C2XXXX"
        return a
    }

    func testWizardSteps() {
        XCTAssertEqual(WizardLogic.steps(.app), [.struttura, .invito])
        XCTAssertEqual(WizardLogic.steps(.site), [.importa, .casa, .dove, .foto, .descrizione, .prezzi, .riepilogo])
        XCTAssertEqual(WizardStep.casa.level, .site)
        XCTAssertEqual(WizardStep.struttura.next, .invito)
        XCTAssertNil(WizardStep.invito.next)
        XCTAssertNil(WizardStep.struttura.previous)
        XCTAssertNil(WizardStep.importa.previous)
        XCTAssertEqual(WizardStep.importa.next, .casa)
        XCTAssertEqual(WizardStep.casa.previous, .importa)
        XCTAssertNil(WizardStep.riepilogo.next)
        XCTAssertEqual(WizardLogic.startStep(.app), .struttura)
        XCTAssertEqual(WizardLogic.startStep(.site), .importa)
    }

    func testWizardMissing() {
        let missing = WizardLogic.missing(app: AppFieldsDraft(), site: SiteDraft(), photoCount: 0)
        XCTAssertEqual(Array(missing.prefix(4)), [WizardLogic.missingName, WizardLogic.missingCin, "Zona", "Almeno una foto"])
        XCTAssertEqual(WizardLogic.firstIncomplete(app: AppFieldsDraft(), site: SiteDraft(), photoCount: 0), .struttura)
        var noCin = named; noCin.cin = " "
        XCTAssertEqual(WizardLogic.stepMissing(.casa, app: noCin, site: complete, photoCount: 1), [WizardLogic.missingCin])
        var noZone = complete; noZone.zone = ""
        XCTAssertEqual(WizardLogic.stepMissing(.dove, app: named, site: noZone, photoCount: 1), ["Zona"])
        XCTAssertEqual(WizardLogic.stepMissing(.foto, app: named, site: complete, photoCount: 0), ["Almeno una foto"])
        var noFee = complete; noFee.cleaningFee = ""
        XCTAssertEqual(WizardLogic.stepMissing(.prezzi, app: named, site: noFee, photoCount: 1), ["Costo pulizie"])
        XCTAssertTrue(WizardLogic.missing(app: named, site: complete, photoCount: 3).isEmpty)
        XCTAssertNil(WizardLogic.firstIncomplete(app: named, site: complete, photoCount: 3))
        XCTAssertEqual(WizardLogic.firstIncomplete(app: named, site: complete, photoCount: 0), .foto)
        var blank = AppFieldsDraft(); blank.name = "  "
        XCTAssertFalse(WizardLogic.canAdvance(.struttura, app: blank))
        XCTAssertTrue(WizardLogic.canAdvance(.struttura, app: named))
        XCTAssertTrue(WizardLogic.canAdvance(.casa, app: AppFieldsDraft()))
    }

    // MARK: PositionStateTest

    private let palermo = LatLng(lat: 38.1157, lng: 13.3615)
    private func bearing(_ v: Double) -> () -> Double { { v } }

    func testFirstPlacementCreatesTheAreaAtTheDefaultOffset() {
        XCTAssertNil(PositionState().problem())
        let s = PositionState().withExact(palermo, bearing: bearing(1))
        XCTAssertEqual(s.exact!.lat, palermo.lat, accuracy: 1e-6)
        XCTAssertEqual(distanceMeters(s.exact!, s.area!), defaultAreaOffsetM, accuracy: 0.5)
        XCTAssertNil(s.problem())
    }

    func testMovingThePinCarriesTheAreaAlong() {
        let placed = PositionState().withExact(palermo, bearing: bearing(2))
        let before = distanceMeters(placed.exact!, placed.area!)
        let moved = placed.withExact(offsetMeters(palermo, eastM: 80, northM: -40), bearing: bearing(3))
        XCTAssertEqual(distanceMeters(moved.exact!, moved.area!), before, accuracy: 0.5)
        XCTAssertNil(moved.problem())
        XCTAssertNil(placed.withExact(LatLng(lat: 37.9, lng: 14.0), bearing: bearing(3)).problem())
    }

    func testLegacyPinWithoutAreaGetsOne() {
        let legacy = PositionState(exact: palermo, area: nil)
        XCTAssertEqual(legacy.problem(), "Manca l'area pubblica")
        let fixed = legacy.withExact(palermo, bearing: bearing(4))
        XCTAssertNotNil(fixed.area)
        XCTAssertNil(fixed.problem())
    }

    func testHandleClampsTheOffset() {
        let placed = PositionState().withExact(palermo, bearing: bearing(5))
        let tooFar = placed.withAreaHandle(offsetMeters(palermo, eastM: 0, northM: 900))
        XCTAssertEqual(distanceMeters(tooFar.exact!, tooFar.area!), maxAreaOffsetM, accuracy: 0.5)
        XCTAssertEqual(tooFar.exact, placed.exact)
        let tooClose = placed.withAreaHandle(offsetMeters(palermo, eastM: 0, northM: 3))
        XCTAssertEqual(distanceMeters(tooClose.exact!, tooClose.area!), minAreaOffsetM, accuracy: 0.5)
        XCTAssertEqual(PositionState().withAreaHandle(palermo), PositionState())
    }

    func testProblems() {
        XCTAssertEqual(PositionState(exact: palermo, area: offsetMeters(palermo, eastM: 0, northM: 400)).problem(),
                       "Il pin esatto deve stare dentro l'area pubblica")
        XCTAssertEqual(PositionState(exact: palermo, area: offsetMeters(palermo, eastM: 0, northM: 5)).problem(),
                       "L'area pubblica è troppo vicina al pin: sposta la maniglia")
        XCTAssertEqual(PositionState(exact: nil, area: palermo).problem(), "Manca il pin esatto")
        XCTAssertEqual(PositionState(exact: LatLng(lat: .nan, lng: .nan), area: palermo).problem(), "Posizione non valida")
        XCTAssertEqual(PositionState(exact: palermo, area: LatLng(lat: 95, lng: 13)).problem(), "Posizione non valida")
    }

    func testInvalidPointsAreIgnoredOrReplaced() {
        let placed = PositionState().withExact(palermo, bearing: bearing(7))
        XCTAssertEqual(placed.withExact(LatLng(lat: .nan, lng: 13), bearing: bearing(8)), placed)
        XCTAssertEqual(placed.withExact(LatLng(lat: 95, lng: 13), bearing: bearing(8)), placed)
        XCTAssertEqual(placed.withAreaHandle(LatLng(lat: .nan, lng: 13)), placed)
        let broken = PositionState(exact: palermo, area: LatLng(lat: .nan, lng: .nan))
        let fixed = broken.withExact(offsetMeters(palermo, eastM: 20, northM: 20), bearing: bearing(10))
        XCTAssertNil(fixed.problem())
        XCTAssertEqual(distanceMeters(fixed.exact!, fixed.area!), defaultAreaOffsetM, accuracy: 0.5)
        let orphan = PositionState(exact: nil, area: LatLng(lat: 40, lng: 15)).withExact(palermo, bearing: bearing(15))
        XCTAssertEqual(distanceMeters(orphan.exact!, orphan.area!), defaultAreaOffsetM, accuracy: 0.5)
        // Pin non valido: la maniglia non fa nulla (area invariata).
        let badPin = PositionState(exact: LatLng(lat: 95, lng: 13), area: palermo)
        XCTAssertEqual(badPin.withAreaHandle(offsetMeters(palermo, eastM: 0, northM: 100)).area, palermo)
    }

    func testLargeLatitudeJumpsKeepTheOffsetInsideTheWindow() {
        let north = LatLng(lat: 46, lng: 11)
        let southMoved = PositionState(exact: north, area: offsetMeters(north, eastM: 250, northM: 0))
            .withExact(LatLng(lat: 36.7, lng: 11), bearing: bearing(12))
        XCTAssertNil(southMoved.problem())
        let south = LatLng(lat: 36.7, lng: 11)
        let northMoved = PositionState(exact: south, area: offsetMeters(south, eastM: 50, northM: 0))
            .withExact(LatLng(lat: 46, lng: 11), bearing: bearing(13))
        XCTAssertNil(northMoved.problem())
        let placed = PositionState(exact: palermo, area: offsetMeters(palermo, eastM: 120, northM: 30))
        let before = distanceMeters(placed.exact!, placed.area!)
        let moved = placed.withExact(LatLng(lat: palermo.lat, lng: palermo.lng + 0.002), bearing: bearing(14))
        XCTAssertEqual(distanceMeters(moved.exact!, moved.area!), before, accuracy: 0.5)
    }

    // Al posto di SiteDraftSaverTest: la bozza si salva e si rilegge identica.
    func testDraftsRoundTripThroughCodable() throws {
        var s = complete
        s.localTips = ["it": "Mare", "en": "Sea"]
        s.published = true
        let back = try JSONDecoder().decode(SiteDraft.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let a = AppFieldsDraft(property)
        XCTAssertEqual(try JSONDecoder().decode(AppFieldsDraft.self, from: JSONEncoder().encode(a)), a)
    }
}

/// `SiteTrackTest.kt` e `PropertyManagementViewModelTest.kt`.
final class SiteTrackTests: XCTestCase {
    func testANewHouseIsAppOnly() {
        XCTAssertFalse(isOnSiteTrack(siteTrack: nil, listingStatus: nil, publishedOnSite: nil))
        XCTAssertFalse(isOnSiteTrack(siteTrack: false, listingStatus: "draft", publishedOnSite: false))
    }

    func testAnyTraceOfTheSiteMakesItOnSiteTrack() {
        XCTAssertTrue(isOnSiteTrack(siteTrack: true, listingStatus: nil, publishedOnSite: nil))
        for s in ["pending", "approved", "rejected"] {
            XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: s, publishedOnSite: nil))
        }
        XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: nil, publishedOnSite: true))
    }

    func testExistingSiteContentCountsEvenWithoutAMarker() {
        XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: "draft", publishedOnSite: false, hasSiteContent: true))
        XCTAssertFalse(isOnSiteTrack(siteTrack: nil, listingStatus: "draft", publishedOnSite: false, hasSiteContent: false))
    }

    func testOnlyApprovedHousesCanEditCalendarPrices() {
        XCTAssertTrue(canEditCalendarPrices(.approved))
        for s in [ListingStatus.draft, .pending, .rejected] { XCTAssertFalse(canEditCalendarPrices(s)) }
    }

    func testApprovedIdsKeepsOnlyApproved() {
        XCTAssertEqual(approvedIds(["a": .approved, "b": .draft, "c": .approved]), ["a", "c"])
    }

    func testValidatePropertyForm() {
        XCTAssertEqual(validatePropertyForm(name: "", idAppartamentoText: ""), "Il nome è obbligatorio")
        XCTAssertEqual(validatePropertyForm(name: "Casa Mare", idAppartamentoText: "abc"), "ID Appartamento deve essere un numero")
        XCTAssertNil(validatePropertyForm(name: "Casa Mare", idAppartamentoText: ""))
        XCTAssertNil(validatePropertyForm(name: "Casa Mare", idAppartamentoText: "42"))
    }

    /// Le patch dei servizi (con `AnyHashable`) arrivano all'SDK come tipi Foundation semplici.
    func testPlainCallableValueUnwrapsHashables() {
        let services: [[String: AnyHashable]] = [["key": "wifi", "category": "work", "paid": true]]
        let plain = plainCallableValue(["services": services]) as? [String: Any]
        let first = (plain?["services"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual(first?["key"] as? String, "wifi")
        XCTAssertEqual(first?["paid"] as? Bool, true)
        XCTAssertTrue(plainCallableValue(NSNull()) is NSNull)
    }
}
