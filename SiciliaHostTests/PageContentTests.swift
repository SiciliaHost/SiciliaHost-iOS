import XCTest
@testable import SiciliaHost

// Specifica: ServicesDraftTest e PageContentDraftTest dell'app Android (casi principali).
final class PageContentTests: XCTestCase {
    private let empty = ServicesDraft()

    // MARK: ServicesDraftTest

    func testToggleAddsAndRemovesACatalogueService() {
        let on = empty.toggle("wifi")
        XCTAssertEqual(on.entries, [ServiceEntry(key: "wifi", category: "work")])
        XCTAssertTrue(on.has("wifi"))
        XCTAssertEqual(on.toggle("wifi"), empty)
        XCTAssertEqual(empty.toggle("nope"), empty)
    }

    func testCustomServicesAreIdentifiedByName() {
        let d = empty.withCustom("Telescopio", category: .entertainment).withCustom("telescopio", category: .outdoor)
        XCTAssertEqual(d.entries.count, 1)
        XCTAssertEqual(d.entries[0].name, "Telescopio")
        XCTAssertEqual(d.entries[0].category, "entertainment")
    }

    func testReplaceAndRenameRules() {
        let d = empty.toggle("oven")
        var e = d.entries[0]; e.note = "A gas"; e.paid = true
        let updated = d.replace(d.entries[0], with: e)
        XCTAssertEqual(updated.entries[0].note, "A gas")
        XCTAssertTrue(updated.entries[0].paid)

        let two = empty.withCustom("Telescopio", category: .entertainment).withCustom("Barca", category: .outdoor)
        let barca = two.entries[1]
        var clash = barca; clash.name = " telescopio "
        XCTAssertEqual(two.replace(barca, with: clash), two)
        XCTAssertTrue(two.nameTaken(" TELESCOPIO ", except: barca))
        XCTAssertFalse(two.nameTaken("Barca", except: barca))
    }

    func testMergeImportAddsOnlyNewServicesAndTheAcceptedCustomOnes() {
        let result = ServiceImportResult(
            matched: [ImportedService(key: "wifi", paid: false), ImportedService(key: "parking", paid: true)],
            unmatched: [ImportedCustom(name: "Pannolini", category: .family), ImportedCustom(name: "Altro", category: .work)]
        )
        let merged = empty.toggle("wifi").mergeImport(result, acceptedCustom: ["Pannolini"])
        XCTAssertEqual(merged.entries.map(\.key), ["wifi", "parking", "custom"])
        XCTAssertTrue(merged.entries[1].paid)
        XCTAssertEqual(merged.entries[2].name, "Pannolini")
    }

    func testDraftFromServicesReadsFirestoreAndDropsInvalidEntries() {
        let content = PropertySiteContent(services: [
            SiteService(key: "oven", category: "kitchen", paid: true, note: "A gas"),
            SiteService(key: "custom", name: "Telescopio", category: "entertainment"),
            SiteService(key: "zzz", category: "kitchen"),
            SiteService(key: "custom", name: " ", category: "kitchen"),
            SiteService(key: "wifi", category: "bogus"),
        ])
        XCTAssertEqual(ServicesDraftLogic.fromServices(content).entries, [
            ServiceEntry(key: "oven", category: "kitchen", paid: true, note: "A gas"),
            ServiceEntry(key: "custom", name: "Telescopio", category: "entertainment"),
            ServiceEntry(key: "zzz", category: "kitchen"),
            ServiceEntry(key: "wifi", category: "work"),
        ])
    }

    func testLegacyAmenities() {
        let legacy = PropertySiteContent(amenities: ["Wifi", "Cucina", "Telescopio"], services: nil)
        XCTAssertEqual(ServicesDraftLogic.from(legacy).entries.map(\.key), ["wifi", "kitchen", "custom"])
        XCTAssertTrue(ServicesDraftLogic.fromServices(legacy).entries.isEmpty)
        XCTAssertEqual(ServicesDraftLogic.from(PropertySiteContent(amenities: ["Wifi"], services: [SiteService(key: "pool", category: "outdoor")]))
            .entries.map(\.key), ["pool"])
        XCTAssertTrue(ServicesDraftLogic.from(PropertySiteContent(amenities: ["Wifi"], services: [])).entries.isEmpty)
        let migrate = PropertySiteContent(amenities: ["Wifi"], services: nil)
        XCTAssertEqual(ServicesDraftLogic.patch(original: ServicesDraftLogic.fromServices(migrate), current: ServicesDraftLogic.from(migrate)),
                       [["key": "wifi", "category": "work"]])
    }

    func testServicesPatch() {
        let d = empty.toggle("wifi")
        XCTAssertNil(ServicesDraftLogic.patch(original: d, current: d))
        let oven = empty.toggle("oven")
        var e = oven.entries[0]; e.note = " A gas "; e.paid = true
        let withNote = oven.replace(oven.entries[0], with: e).withCustom("Telescopio", category: .entertainment)
        XCTAssertEqual(ServicesDraftLogic.patch(original: empty, current: withNote), [
            ["key": "oven", "category": "kitchen", "paid": true, "note": "A gas"],
            ["key": "custom", "category": "entertainment", "name": "Telescopio"],
        ])
        XCTAssertEqual(ServicesDraftLogic.patch(original: d, current: empty), [])
    }

    func testOpaqueKeysAreKeptAndSentBackUnchanged() {
        let original = ServicesDraftLogic.fromServices(PropertySiteContent(services: [
            SiteService(key: "wifi", category: "work"),
            SiteService(key: "future_thing", category: "kitchen", paid: true, note: "Nuovo"),
            SiteService(key: "bad", category: "bogus"),
        ]))
        XCTAssertEqual(original.entries.map(\.key), ["wifi", "future_thing"])
        XCTAssertEqual(original.entries.filter { !$0.isOpaque }.count, 1)
        XCTAssertEqual(ServicesDraftLogic.patch(original: original, current: original.toggle("wifi")),
                       [["key": "future_thing", "category": "kitchen", "paid": true, "note": "Nuovo"]])
    }

    func testServicesErrors() {
        let tooMany = ServicesDraft(entries: (1 ... 81).map { ServiceEntry(key: "custom", name: "S\($0)", category: "work") })
        XCTAssertNotNil(ServicesDraftLogic.errors(tooMany)["total"])
        let d = empty.toggle("oven")
        var long = d.entries[0]; long.note = String(repeating: "x", count: 301)
        XCTAssertNotNil(ServicesDraftLogic.errors(d.replace(d.entries[0], with: long))["oven"])
        XCTAssertNil(ServicesDraftLogic.errors(d)["oven"])
    }

    // MARK: PageContentDraftTest

    func testEmptyContentGivesAnEmptyDraftAndPatch() {
        let d = PageContentLogic.draft(from: PropertySiteContent())
        XCTAssertEqual(d, PageContentDraft())
        XCTAssertTrue(PageContentLogic.patch(original: d, current: d).isEmpty)
    }

    func testDraftIsReadFromContent() {
        var c = PropertySiteContent()
        var rules = SiteRules(); rules.pets = "allowed"; rules.quietHours = "22:00-08:00"; rules.minAge = 18; rules.note = "No scarpe"
        var access = SiteAccess(); access.floor = 0; access.elevator = false; access.stepFree = true; access.parking = "private"
        var tax = SiteTouristTax(); tax.perPersonPerNight = 2.5; tax.maxNights = 5; tax.exemptUnderAge = 12
        var fees = SiteFees(); fees.touristTax = tax
        var near = SiteNearby(); near.type = "sea"; near.name = "Mondello"; near.minutes = 5; near.mode = "walk"
        var host = SiteHost(); host.name = "Maria"; host.languages = ["it", "en"]; host.showPhone = true
        c.rulesStructured = rules; c.access = access; c.fees = fees; c.nearby = [near]; c.host = host
        let d = PageContentLogic.draft(from: c)
        XCTAssertEqual(d.pets, "allowed")
        XCTAssertEqual(d.quietFrom, "22:00")
        XCTAssertEqual(d.quietTo, "08:00")
        XCTAssertEqual(d.minAge, "18")
        XCTAssertEqual(d.floor, "0")
        XCTAssertEqual(d.elevator, "no")
        XCTAssertEqual(d.stepFree, "yes")
        XCTAssertEqual(d.taxAmount, "2.5")
        XCTAssertEqual(d.nearby, [NearbyRow(type: "sea", name: "Mondello", minutes: "5", mode: "walk")])
        XCTAssertEqual(d.hostLanguages, ["it", "en"])
        XCTAssertTrue(d.showPhone)
    }

    func testHostPrefillFromGuestHubContact() {
        var c = PropertySiteContent(); c.managerContact = SiteManagerContact(name: "Maria", phone: "+39 333 1234567")
        XCTAssertEqual(PageContentLogic.draft(from: c).hostName, "Maria")
        XCTAssertEqual(PageContentLogic.draft(from: c).hostPhone, "+393331234567")
        var h = SiteHost(); h.name = "Luca"
        c.host = h
        XCTAssertEqual(PageContentLogic.draft(from: c).hostName, "Luca")
        XCTAssertEqual(PageContentLogic.draft(from: c).hostPhone, "")
        XCTAssertEqual(PageContentLogic.prefillPhone("333 1234567"), "+393331234567")
        XCTAssertEqual(PageContentLogic.prefillPhone("0049 170 1234567"), "+491701234567")
        XCTAssertEqual(PageContentLogic.prefillPhone("abc"), "")
    }

    func testPatchSendsOnlyChangedBlocks() {
        var changed = PageContentDraft()
        changed.pets = "allowed"; changed.smoking = "not_allowed"; changed.quietFrom = "22:00"; changed.quietTo = "08:00"
        changed.minAge = "18"; changed.rulesNote = " No scarpe "
        let patch = PageContentLogic.patch(original: PageContentDraft(), current: changed)
        XCTAssertEqual(Set(patch.keys), ["rulesStructured"])
        XCTAssertEqual(patch["rulesStructured"] as? [String: AnyHashable],
                       ["pets": "allowed", "smoking": "not_allowed", "quietHours": "22:00-08:00", "minAge": 18, "note": "No scarpe"])
        var before = PageContentDraft(); before.pets = "allowed"
        XCTAssertTrue(PageContentLogic.patch(original: before, current: PageContentDraft())["rulesStructured"] is NSNull)
    }

    func testAccessFeesNearbyAndHost() {
        var d = PageContentDraft()
        d.floor = "2"; d.elevator = "yes"; d.stepFree = "no"; d.parking = "private"
        d.taxAmount = "2,5"; d.taxMaxNights = "5"; d.taxExemptAge = "12"
        d.nearby = [NearbyRow(type: "sea", name: "", minutes: "5", mode: "walk"), NearbyRow(type: "center", name: "Piazza", minutes: "", mode: "car")]
        d.transportNote = " Bus 806 "
        d.hostName = " Maria "; d.hostPhone = "+39 333 123-4567"; d.hostWhatsapp = true; d.hostLanguages = ["en", "it"]
        let p = PageContentLogic.patch(original: PageContentDraft(), current: d)
        XCTAssertEqual(p["access"] as? [String: AnyHashable], ["floor": 2, "elevator": true, "stepFree": false, "parking": "private"])
        XCTAssertEqual(p["fees"] as? [String: AnyHashable],
                       ["touristTax": ["perPersonPerNight": 2.5, "maxNights": 5, "exemptUnderAge": 12] as [String: AnyHashable]])
        XCTAssertEqual(p["nearby"] as? [AnyHashable], [["type": "sea", "minutes": 5, "mode": "walk"] as [String: AnyHashable]])
        XCTAssertEqual(p["transportNote"] as? String, "Bus 806")
        XCTAssertEqual(p["host"] as? [String: AnyHashable],
                       ["name": "Maria", "phone": "+393331234567", "languages": ["en", "it"], "whatsapp": true])
    }

    func testSleepingArrangementsAndCrib() {
        var d = PageContentDraft()
        d.rooms = [RoomRow(kind: "bedroom", beds: ["double": 1, "single": 0])]
        d.crib = true
        let p = PageContentLogic.patch(original: PageContentDraft(), current: d)
        XCTAssertEqual(p["sleepingArrangements"] as? [AnyHashable], [
            ["kind": "bedroom", "beds": [["type": "double", "count": 1] as [String: AnyHashable],
                                         ["type": "crib", "count": 1] as [String: AnyHashable]] as [AnyHashable]] as [String: AnyHashable],
        ])
        var room = SiteSleepingRoom(); room.kind = "bedroom"
        var crib = SiteBed(); crib.type = "crib"; crib.count = 1
        var dbl = SiteBed(); dbl.type = "double"; dbl.count = 1
        room.beds = [dbl, crib]
        var onlyCrib = SiteSleepingRoom(); onlyCrib.kind = "other"; onlyCrib.beds = [crib]
        let read = PageContentLogic.sleepingRows([room, onlyCrib])
        XCTAssertEqual(read.rooms, [RoomRow(kind: "bedroom", beds: ["double": 1])])
        XCTAssertTrue(read.crib)
    }

    func testPageContentErrors() {
        var d = PageContentDraft()
        d.quietFrom = "22"; d.minAge = "0"; d.floor = "-3"; d.taxMaxNights = "3"
        d.rooms = [RoomRow(kind: "bedroom", beds: [:])]
        d.nearby = [NearbyRow(type: "sea", name: "", minutes: "0", mode: "walk")]
        d.hostEmail = "x@"; d.hostPhone = "333"; d.showEmail = true
        let e = PageContentLogic.errors(d)
        XCTAssertEqual(e["quietHours"], "Indica inizio e fine nel formato 22:00")
        XCTAssertEqual(e["minAge"], "Età da 1 a 99")
        XCTAssertEqual(e["floor"], "Piano intero da -2 a 100")
        XCTAssertEqual(e["taxAmount"], "Indica l'importo della tassa")
        XCTAssertEqual(e["rooms.0"], "Aggiungi almeno un letto o rimuovi la stanza")
        XCTAssertEqual(e["nearby.0"], "Minuti da 1 a 600")
        XCTAssertEqual(e["hostEmail"], "Email non valida")
        XCTAssertEqual(e["hostPhone"], "Usa il formato internazionale, es. +39 333 1234567")
        XCTAssertTrue(PageContentLogic.errors(PageContentDraft()).isEmpty)
    }
}
