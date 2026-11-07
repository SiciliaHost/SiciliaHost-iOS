import XCTest
@testable import SiciliaHost

// Specifica: PropertyTest, ListingStatusTest, ServiceCatalogTest, FanOutTest, AccessScopeListingTest (Android).
final class ModelsTests: XCTestCase {
    // MARK: Property

    func testRoleOfReadsKnownRolesOnly() {
        let p = Property(id: "p1", members: ["a": "OWNER", "b": "COLLABORATOR", "c": "ADMIN"])
        XCTAssertEqual(p.roleOf("a"), .owner)
        XCTAssertEqual(p.roleOf("b"), .collaborator)
        XCTAssertNil(p.roleOf("c"))
        XCTAssertNil(p.roleOf("z"))
    }

    func testAppFieldsNeverIncludeMembershipOrCredentials() {
        let fields = Property(id: "p1", name: "Casa", members: ["a": "OWNER"], memberUids: ["a"], createdBy: "a").appFields
        for key in ["members", "memberUids", "createdBy", "alloggiatiConfigured", "wsUtente", "wsPassword", "wsKey", "permissions"] {
            XCTAssertNil(fields[key], "\(key) non deve essere scritto dai salvataggi della scheda")
        }
    }

    func testPermissionsOfReadsKnownPermissionsOfCollaboratorsOnly() {
        let p = Property(
            id: "p1", members: ["c": "COLLABORATOR", "o": "OWNER"],
            permissions: ["c": ["FINANCE", "BOH", "SITE"], "o": ["PRICES"], "x": ["SITE"]]
        )
        XCTAssertEqual(p.permissionsOf("c"), [.site])   // FINANCE (non più un permesso) e BOH ignorati
        XCTAssertTrue(p.permissionsOf("o").isEmpty)
        XCTAssertTrue(p.permissionsOf("x").isEmpty)
        XCTAssertTrue(Property(id: "p2", members: ["c": "COLLABORATOR"]).permissionsOf("c").isEmpty)
    }

    func testAppFieldsKeepTheCommissionFlagUnderItsRealName() {
        let fields = Property(isManagedOnCommission: true).appFields
        XCTAssertEqual(fields["isManagedOnCommission"] as? Bool, true)
        XCTAssertNil(fields["managedOnCommission"])
    }

    func testAppFieldsWriteNullsSoClearedFieldsAreCleared() {
        let fields = Property(id: "p1", cin: nil).appFields
        XCTAssertTrue(fields["cin"] is NSNull)
        XCTAssertEqual(fields["id"] as? String, "p1")
    }

    // MARK: Contratto dei campi Firestore

    func testReservationUsesTheRealFirestoreFieldNameForIcal() {
        let data = Reservation(id: "r", icalUid: "x@airbnb.com").firestoreData
        XCTAssertEqual(data["icalUid"] as? String, "x@airbnb.com")
        XCTAssertNil(data["iCalUid"])
        XCTAssertTrue(Reservation().firestoreData["guestName"] is NSNull)
    }

    func testReservationNeverWritesMoneyFields() {
        let r = Reservation(id: "r1", propertyId: "p1", guestName: "Rossi", checkIn: 1, checkOut: 2, platform: "BOOKING", icalUid: "u", adults: 2, children: 0, guestCountry: "de")
        let keys = Set(r.firestoreData.keys)
        for money in ["grossAmount", "netAmountOwner", "netAmountAdmin", "needsReview", "bookedAt", "travelPurpose", "bookingDevice", "commissionAmount"] {
            XCTAssertFalse(keys.contains(money), money)
        }
    }

    func testOldReservationDocumentWithMoneyFieldsStillDecodes() throws {
        let json = #"{"id":"r1","propertyId":"p1","checkIn":1,"checkOut":2,"platform":"BOOKING","grossAmount":300,"netAmountOwner":228.6,"netAmountAdmin":228.6,"needsReview":true,"bookedAt":0,"commissionAmount":50,"adults":2}"#
        let r = try JSONDecoder().decode(Reservation.self, from: Data(json.utf8))
        XCTAssertEqual(r, Reservation(id: "r1", propertyId: "p1", checkIn: 1, checkOut: 2, platform: "BOOKING", adults: 2))
    }

    func testInventoryKeepsTheDepletedFlagUnderItsRealName() {
        XCTAssertEqual(InventoryItem(isDepleted: true).firestoreData["isDepleted"] as? Bool, true)
    }

    func testUserProfileWritesOnlyTheFieldsAllowedByTheRules() {
        XCTAssertEqual(Set(UserProfile(id: "u", email: "a@b.c").firestoreData.keys), ["id", "email", "fcmToken"])
    }

    func testAlloggiatiCredentialsConfiguredOnlyWhenAllThreeAreFilled() {
        XCTAssertFalse(AlloggiatiCredentials().isConfigured)
        XCTAssertFalse(AlloggiatiCredentials(utente: "u", password: " ", wsKey: "k").isConfigured)
        XCTAssertTrue(AlloggiatiCredentials(utente: "u", password: "p", wsKey: "k").isConfigured)
    }

    // MARK: ListingStatus

    func testStoredStatusWins() {
        XCTAssertEqual(effectiveListingStatus(stored: "pending", publishedOnSite: false), .pending)
        XCTAssertEqual(effectiveListingStatus(stored: "rejected", publishedOnSite: true), .rejected)
    }

    func testMissingOrUnknownStatusIsDerivedFromPublished() {
        XCTAssertEqual(effectiveListingStatus(stored: nil, publishedOnSite: true), .approved)
        XCTAssertEqual(effectiveListingStatus(stored: nil, publishedOnSite: false), .draft)
        XCTAssertEqual(effectiveListingStatus(stored: nil, publishedOnSite: nil), .draft)
        XCTAssertEqual(effectiveListingStatus(stored: "weird", publishedOnSite: true), .approved)
    }

    func testSiteTrack() {
        XCTAssertTrue(isOnSiteTrack(siteTrack: true, listingStatus: nil, publishedOnSite: nil))
        XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: "pending", publishedOnSite: nil))
        XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: nil, publishedOnSite: true))
        XCTAssertTrue(isOnSiteTrack(siteTrack: nil, listingStatus: nil, publishedOnSite: nil, hasSiteContent: true))
        XCTAssertFalse(isOnSiteTrack(siteTrack: nil, listingStatus: "draft", publishedOnSite: nil))
        XCTAssertFalse(isOnSiteTrack(siteTrack: false, listingStatus: nil, publishedOnSite: false))
    }

    func testCalendarPricesNeedAnApprovedListing() {
        XCTAssertTrue(canEditCalendarPrices(.approved))
        XCTAssertFalse(canEditCalendarPrices(.pending))
        XCTAssertEqual(approvedIds(["a": .approved, "b": .draft, "c": .approved]), ["a", "c"])
    }

    func testSiteContentStatusAndTrack() {
        var content = PropertySiteContent(id: "p", publishedOnSite: true)
        XCTAssertEqual(content.status, .approved)
        content = PropertySiteContent(id: "p", zone: "Centro")
        XCTAssertTrue(content.onSiteTrack)
        XCTAssertFalse(PropertySiteContent(id: "p").onSiteTrack)
    }

    // MARK: ServiceCatalog

    private let contract: Set<String> = [
        "kitchen", "refrigerator", "freezer", "oven", "stove", "microwave", "dishwasher", "coffee_machine",
        "moka", "kettle", "toaster", "cookware", "dishes_cutlery", "wine_glasses", "dining_table",
        "hair_dryer", "shower", "bathtub", "bidet", "towels", "toiletries", "washing_machine", "dryer",
        "bed_linen", "iron", "clothes_rack", "wardrobe", "extra_blankets", "blackout_curtains", "mosquito_nets",
        "air_conditioning", "heating", "fan", "fireplace",
        "tv", "streaming", "sound_system", "books", "board_games",
        "terrace_balcony", "garden", "pool", "bbq", "outdoor_furniture", "sea_view", "mountain_view",
        "beach_gear", "outdoor_shower", "parking",
        "wifi", "workspace", "printer",
        "crib", "high_chair", "baby_bath", "safety_gates", "toys",
        "smoke_detector", "co_detector", "fire_extinguisher", "first_aid_kit", "safe",
    ]

    func testCatalogMatchesTheSharedContract() {
        XCTAssertEqual(contract.count, 62)
        XCTAssertEqual(Set(ServiceCatalog.all.map(\.key)), contract)
        XCTAssertEqual(ServiceCatalog.all.count, ServiceCatalog.byKey.count, "nessuna chiave duplicata")
    }

    func testEveryServiceHasALabelAndKeywordsInNormalisedForm() {
        for s in ServiceCatalog.all {
            XCTAssertFalse(s.label.trimmed.isEmpty, "\(s.key) label")
            XCTAssertFalse(s.keywords.isEmpty, "\(s.key) keywords")
            for k in s.keywords { XCTAssertEqual(k, k.lowercased().trimmed, "\(s.key): '\(k)' deve essere già normalizzata") }
        }
    }

    func testCategoriesRoundTripThroughTheirKey() {
        for c in ServiceCategory.allCases { XCTAssertEqual(ServiceCategory.fromKey(c.key), c) }
        XCTAssertNil(ServiceCategory.fromKey("nope"))
        XCTAssertNotNil(ServiceCatalog.byKey["wifi"])
        XCTAssertEqual(ServiceCatalog.label(for: "wifi"), "Wi-Fi")
        XCTAssertEqual(ServiceCatalog.label(for: "zzz"), "zzz")
    }

    // MARK: FanOut

    func testFanOutEmptyIdsReturnsEmptyWithoutCallingFetch() async throws {
        let result: [Int] = try await fanOut([]) { _ in XCTFail("fetch non deve essere chiamato"); return [1] }
        XCTAssertTrue(result.isEmpty)
    }

    func testFanOutFlattensResultsInTheOrderOfTheIds() async throws {
        let result: [String] = try await fanOut(["a", "b", "c"]) { id in
            // "a" finisce per ultima ma l'ordine del risultato segue quello degli id.
            if id == "a" { try await Task.sleep(nanoseconds: 30_000_000) }
            return ["\(id)-1", "\(id)-2"]
        }
        XCTAssertEqual(result, ["a-1", "a-2", "b-1", "b-2", "c-1", "c-2"])
    }

    func testFanOutAFailingQueryFailsTheWholeCall() async {
        struct Denied: Error {}
        do {
            let _: [Int] = try await fanOut(["a", "b"]) { id in
                if id == "b" { throw Denied() }
                return [1]
            }
            XCTFail("doveva fallire")
        } catch {
            XCTAssertTrue(error is Denied)
        }
    }

    // MARK: Lookup Alloggiati

    func testLookupCsvSkipsHeaderAndBrokenRows() {
        let csv = "Codice;Descrizione\n100;Roma\n\n200;Milano;extra\nsolo-una-colonna\n"
        XCTAssertEqual(LookupService.parseCsv(csv), [
            LookupEntry(code: "100", description: "Roma"), LookupEntry(code: "200", description: "Milano"),
        ])
    }

    func testLookupFilterNeedsTwoCharactersAndIsCaseInsensitive() {
        let list = [LookupEntry(code: "1", description: "ROMA"), LookupEntry(code: "2", description: "Palermo")]
        XCTAssertTrue(LookupService.filterLuoghi(list, query: "r").isEmpty)
        XCTAssertEqual(LookupService.filterLuoghi(list, query: "ro").map(\.code), ["1"])
        XCTAssertEqual(LookupService.filterLuoghi(list, query: "ERM").map(\.code), ["2"])
        let many = (0 ..< 50).map { LookupEntry(code: "\($0)", description: "Paese \($0)") }
        XCTAssertEqual(LookupService.filterLuoghi(many, query: "Paese").count, 30)
    }

    // MARK: AccessScope (annunci)

    private let mine = Property(id: "m", members: ["me": "OWNER"], memberUids: ["me"])
    private let theirs = Property(id: "t", members: ["host": "OWNER"], memberUids: ["host"])
    private let commission = Property(id: "c", isManagedOnCommission: true, members: ["host": "OWNER"], memberUids: ["host"])

    func testSuperAdminEditsEveryListingButOperatesOnlyOwnAndCommission() {
        let scope = AccessScope(uid: "me", isSuperAdmin: true, properties: [mine, theirs, commission])
        XCTAssertEqual(scope.listingProperties.map(\.id), ["m", "t", "c"])
        XCTAssertTrue(scope.canEditListing(theirs))
        XCTAssertFalse(scope.canOperate(theirs))
        XCTAssertFalse(scope.canManage(theirs))
        XCTAssertEqual(scope.appFieldsAccess(theirs), .viaAdmin)
        XCTAssertEqual(scope.appFieldsAccess(mine), .direct)
        XCTAssertEqual(scope.appFieldsAccess(commission), .direct)
    }

    func testCollaboratorWithSitePermissionEditsListingButNotAppFields() {
        let shared = Property(id: "s", members: ["host": "OWNER", "me": "COLLABORATOR"],
                              memberUids: ["host", "me"], permissions: ["me": ["SITE"]])
        let scope = AccessScope(uid: "me", isSuperAdmin: false, properties: [shared])
        XCTAssertTrue(scope.canEditListing(shared))
        XCTAssertEqual(scope.appFieldsAccess(shared), .readOnly)
    }

    func testCollaboratorWithoutSitePermissionHasNoListing() {
        let shared = Property(id: "s", members: ["host": "OWNER", "me": "COLLABORATOR"], memberUids: ["host", "me"])
        XCTAssertTrue(AccessScope(uid: "me", isSuperAdmin: false, properties: [shared]).listingProperties.isEmpty)
    }
}
