import XCTest
@testable import SiciliaHost

// Specifica: FinanceStoreTest e FinanceOpsTest dell'app Android.
final class FinanceLocalTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fin-\(UUID().uuidString)/u1/finance.json")
    }

    func testEmptyWhenNoFile() async {
        let data = await FinanceStore(fileURL: tempFile()).read()
        XCTAssertEqual(data, FinanceData())
    }

    func testUpdateIsPersistedAndReadBackByANewInstance() async throws {
        let url = tempFile()
        _ = try await FinanceStore(fileURL: url).update {
            $0.withExpense(Expense(id: "e1", propertyId: "p1", description: "", amount: 12.5))
                .withMoney(ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 300))
        }
        let back = await FinanceStore(fileURL: url).read()
        XCTAssertEqual(back.expenses.first?.amount, 12.5)
        XCTAssertEqual(back.moneyById()["r1"]?.grossAmount, 300)
    }

    func testCorruptFileIsSetAsideAndStoreStartsEmpty() async throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{non json".write(to: url, atomically: true, encoding: .utf8)
        let store = FinanceStore(fileURL: url)
        let data = await store.read()
        XCTAssertEqual(data, FinanceData())
        let corrupt = await store.wasCorrupt
        XCTAssertTrue(corrupt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".bad"))
    }

    func testUnknownKeysAreIgnored() async throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"version":9,"extra":1,"expenses":[]}"#.write(to: url, atomically: true, encoding: .utf8)
        let data = await FinanceStore(fileURL: url).read()
        XCTAssertEqual(data.version, 9)
    }

    func testWipeRemovesTheFile() async throws {
        let url = tempFile()
        let store = FinanceStore(fileURL: url)
        _ = try await store.update { $0.withExpense(Expense(id: "e1")) }
        await store.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStoreFolderIsIncludedInBackups() async throws {
        let url = tempFile()
        _ = try await FinanceStore(fileURL: url).update { $0.withExpense(Expense(id: "e1")) }
        let values = try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotEqual(values.isExcludedFromBackup, true)
    }

    func testMoneyIsReplacedPerReservationAndContactsDedupByPhoneAndHouse() {
        var d = FinanceData()
            .withMoney(ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 100))
            .withMoney(ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 120))
        XCTAssertEqual(d.money.count, 1)
        XCTAssertEqual(d.moneyById()["r1"]?.grossAmount, 120)
        d = d.withContacts([Contact(phone: "+39333", name: "Vecchio", propertyId: "p1"), Contact(phone: "+39333", name: "Altra", propertyId: "p2")])
            .withContacts([Contact(phone: "+39333", name: "Nuovo", propertyId: "p1"), Contact(phone: " ", name: "Senza", propertyId: "p1")])
        XCTAssertEqual(Set(d.contacts.map(\.name)), ["Nuovo", "Altra"])
    }

    func testForUserReturnsTheSameInstanceAndWritesAreVisibleThroughIt() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("fin-\(UUID().uuidString)")
        let a = FinanceStore.forUser("u1", base: base)
        let b = FinanceStore.forUser("u1", base: base)
        XCTAssertTrue(a === b)
        _ = try await a.update { $0.withExpense(Expense(id: "e1", propertyId: "p1", description: "", amount: 3)) }
        let read = await b.read()
        XCTAssertEqual(read.expenses.first?.amount, 3)
        XCTAssertFalse(FinanceStore.forUser("u2", base: base) === a)   // un altro account ha un altro archivio
    }

    func testMoneyWithoutSourceIsReadWithTheDefaultAndTheFileIsNotCorrupt() async throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"money":[{"reservationId":"r1","propertyId":"p1","grossAmount":100,"extra":true}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let store = FinanceStore(fileURL: url)
        let data = await store.read()
        let corrupt = await store.wasCorrupt
        XCTAssertFalse(corrupt)
        XCTAssertEqual(data.moneyById()["r1"]?.grossAmount, 100)
        XCTAssertEqual(data.moneyById()["r1"]?.source, ReservationMoney.manual)
        XCTAssertNil(data.moneyById()["r1"]?.commissionAmount)
    }
}

// Specifica: FinanceReconcileTest dell'app Android.
final class FinanceReconcileTests: XCTestCase {
    private let now: Int64 = 1_760_000_000_000
    private let day: Int64 = 86_400_000
    private let rec = RecurringExpense(id: "rc1", propertyId: "p1", description: "Affitto", amount: 400, startMonth: "2025-10")

    private func res(_ id: String, _ pid: String = "p1", checkOut: Int64? = nil) -> Reservation {
        let out = checkOut ?? now + day
        return Reservation(id: id, propertyId: pid, checkIn: out - day, checkOut: out)
    }

    func testOrphanExpensesAndMoneyOfLoadedHousesAreRemoved() {
        var data = FinanceData()
        data.expenses = [Expense(id: "e1", propertyId: "p1", reservationId: "gone"), Expense(id: "e2", propertyId: "p1", reservationId: "r1"),
                         Expense(id: "e3", propertyId: "p1")]
        data.money = [ReservationMoney(reservationId: "gone", propertyId: "p1", grossAmount: 10), ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 20),
                      ReservationMoney(reservationId: "altrui", propertyId: "p9", grossAmount: 30)]
        let out = reconcile(data, loadedPropertyIds: ["p1"], reservations: [res("r1")], siteAmounts: [], now: now,
                            orphanCandidates: orphanCandidates(data))
        XCTAssertEqual(Set(out.expenses.map(\.id)), ["e2", "e3"])
        // I soldi di una casa non caricata (p9) non si toccano.
        XCTAssertEqual(Set(out.money.map(\.reservationId)), ["r1", "altrui"])
    }

    func testOrphanCandidatesAreTheLinkedIdsOfMoneyAndExpenses() {
        var data = FinanceData()
        data.expenses = [Expense(id: "e1", propertyId: "p1", reservationId: "a"), Expense(id: "e2", propertyId: "p1"),
                         Expense(id: "e3", propertyId: "p1", reservationId: "")]
        data.money = [ReservationMoney(reservationId: "b", propertyId: "p1", grossAmount: 1)]
        XCTAssertEqual(orphanCandidates(data), ["a", "b"])
    }

    func testOnlyRowsKnownBeforeTheServerReadCanBeOrphans() {
        // "nuova" è stata scritta (es. import Excel) dopo la lettura del server: non è tra i candidati.
        var data = FinanceData()
        data.expenses = [Expense(id: "e1", propertyId: "p1", reservationId: "vecchia"), Expense(id: "e2", propertyId: "p1", reservationId: "nuova")]
        data.money = [ReservationMoney(reservationId: "vecchia", propertyId: "p1", grossAmount: 10),
                      ReservationMoney(reservationId: "nuova", propertyId: "p1", grossAmount: 50)]
        let out = reconcile(data, loadedPropertyIds: ["p1"], reservations: [], siteAmounts: [], now: now,
                            cleanOrphans: true, orphanCandidates: ["vecchia"])
        XCTAssertEqual(Set(out.money.map(\.reservationId)), ["nuova"])
        XCTAssertEqual(Set(out.expenses.map(\.id)), ["e2"])
    }

    func testACachedListNeverRemovesOrphansButStillMergesSiteAndRecurring() {
        var data = FinanceData()
        data.expenses = [Expense(id: "e1", propertyId: "p1", reservationId: "r1")]
        data.money = [ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 10)]
        data.recurring = [rec]
        // Offline: la cache può essere vuota o parziale, quindi nessun orfano si cancella.
        let out = reconcile(data, loadedPropertyIds: ["p1"], reservations: [], siteAmounts: [], now: now,
                            cleanOrphans: false, orphanCandidates: orphanCandidates(data))
        XCTAssertEqual(out.moneyById()["r1"]?.grossAmount, 10)
        XCTAssertTrue(out.expenses.contains { $0.id == "e1" })
        XCTAssertTrue(out.expenses.contains { $0.id == "rec_rc1_2025-10" })

        let cachedWithSite = reconcile(FinanceData(), loadedPropertyIds: ["p1"], reservations: [res("r2")],
                                       siteAmounts: [SiteBookingAmount(reservationId: "r2", propertyId: "p1", totalPrice: 90)],
                                       now: now, cleanOrphans: false)
        XCTAssertEqual(cachedWithSite.moneyById()["r2"]?.grossAmount, 90)

        // Dal server, invece, la stessa situazione cancella gli orfani.
        let fromServer = reconcile(data, loadedPropertyIds: ["p1"], reservations: [], siteAmounts: [], now: now,
                                   cleanOrphans: true, orphanCandidates: orphanCandidates(data))
        XCTAssertTrue(fromServer.money.isEmpty)
        XCTAssertFalse(fromServer.expenses.contains { $0.id == "e1" })
    }

    func testSiteAmountsFillMissingMoneyButNeverOverrideManual() {
        var data = FinanceData()
        data.money = [ReservationMoney(reservationId: "r2", propertyId: "p1", grossAmount: 999, source: ReservationMoney.manual)]
        let out = reconcile(data, loadedPropertyIds: ["p1"], reservations: [res("r1"), res("r2")],
                            siteAmounts: [SiteBookingAmount(reservationId: "r1", propertyId: "p1", totalPrice: 300),
                                          SiteBookingAmount(reservationId: "r2", propertyId: "p1", totalPrice: 111)],
                            now: now, orphanCandidates: orphanCandidates(data))
        let m = out.moneyById()
        XCTAssertEqual(m["r1"]?.grossAmount, 300)
        XCTAssertEqual(m["r1"]?.source, ReservationMoney.site)
        XCTAssertEqual(m["r2"]?.grossAmount, 999)
    }

    func testSiteAmountUpdatesAnEarlierSiteAmount() {
        var data = FinanceData()
        data.money = [ReservationMoney(reservationId: "r1", propertyId: "p1", grossAmount: 100, source: ReservationMoney.site)]
        let out = reconcile(data, loadedPropertyIds: ["p1"], reservations: [res("r1")],
                            siteAmounts: [SiteBookingAmount(reservationId: "r1", propertyId: "p1", totalPrice: 150)], now: now)
        XCTAssertEqual(out.moneyById()["r1"]?.grossAmount, 150)
    }

    func testSiteAmountOfAMissingReservationIsIgnored() {
        let out = reconcile(FinanceData(), loadedPropertyIds: ["p1"], reservations: [],
                            siteAmounts: [SiteBookingAmount(reservationId: "zz", propertyId: "p1", totalPrice: 5)], now: now)
        XCTAssertTrue(out.money.isEmpty)
    }

    func testRecurringExpensesAreMaterialisedOnce() {
        var data = FinanceData()
        data.recurring = [rec]
        let once = reconcile(data, loadedPropertyIds: ["p1"], reservations: [], siteAmounts: [], now: now)
        XCTAssertTrue(once.expenses.contains { $0.id == "rec_rc1_2025-10" })
        let twice = reconcile(once, loadedPropertyIds: ["p1"], reservations: [], siteAmounts: [], now: now)
        XCTAssertEqual(once.expenses.count, twice.expenses.count)
    }

    func testPendingWindowKeepsRecentAndFutureOnly() {
        let old = FinReservation(id: "a", propertyId: "p1", checkIn: 0, checkOut: now - 60 * day, platform: "BOOKING")
        let recent = FinReservation(id: "b", propertyId: "p1", checkIn: 1, checkOut: now - 10 * day, platform: "BOOKING")
        let future = FinReservation(id: "c", propertyId: "p1", checkIn: 2, checkOut: now + 10 * day, platform: "AIRBNB")
        let block = FinReservation(id: "blocco-1", propertyId: "p1", guestName: "Date bloccate", checkIn: 0, checkOut: now + 10 * day, platform: "MANUAL")
        let withAmount = FinReservation(id: "d", propertyId: "p1", checkIn: 0, checkOut: now + 10 * day, platform: "AIRBNB", grossAmount: 5)
        XCTAssertEqual(pendingAmounts([old, recent, future, block, withAmount], now: now).map(\.id), ["b", "c"])
    }
}

/// Registra le chiamate al sito (per verificare i gruppi da 20); le case in `failing` fanno fallire il loro gruppo.
private actor RecordingSite: SiteAmountsSource {
    private(set) var calls: [[String]] = []
    let failing: Set<String>

    init(failing: Set<String> = []) { self.failing = failing }

    func amounts(propertyIds: [String]) async throws -> [SiteBookingAmount] {
        calls.append(propertyIds)
        if propertyIds.contains(where: { failing.contains($0) }) { throw URLError(.badServerResponse) }
        return propertyIds.map { SiteBookingAmount(reservationId: "r-\($0)", propertyId: $0, totalPrice: 10) }
    }
}

final class SiteAmountsChunkTests: XCTestCase {
    private let ids = (1...45).map { "p\($0)" }

    func testSiteAmountsAreRequestedInGroupsOfTwenty() async throws {
        let site = RecordingSite()
        let out = try await siteAmountsInChunks(ids) { try await site.amounts(propertyIds: $0) }
        let calls = await site.calls
        XCTAssertEqual(calls.map(\.count), [20, 20, 5])
        XCTAssertEqual(calls.flatMap { $0 }, ids)
        XCTAssertEqual(out.count, 45)
    }

    func testAFailingSiteGroupDoesNotDropTheOthers() async throws {
        let site = RecordingSite(failing: ["p21"])
        let out = try await siteAmountsInChunks(ids) { try await site.amounts(propertyIds: $0) }
        XCTAssertEqual(out.count, 25)
        XCTAssertFalse(out.contains { $0.propertyId == "p21" || $0.propertyId == "p40" })
        XCTAssertTrue(out.contains { $0.propertyId == "p1" })
        XCTAssertTrue(out.contains { $0.propertyId == "p45" })
    }
}

private struct FakeSite: SiteAmountsSource {
    var rows: [SiteBookingAmount] = []
    var fails = false

    func amounts(propertyIds: [String]) async throws -> [SiteBookingAmount] {
        if fails { throw URLError(.notConnectedToInternet) }
        return rows.filter { propertyIds.contains($0.propertyId) }
    }
}

// Specifica: FinanceRepositoryTest dell'app Android.
final class FinanceRepositoryTests: XCTestCase {
    private let now: Int64 = 1_760_000_000_000
    private let day: Int64 = 86_400_000

    private func store() -> FinanceStore {
        FinanceStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fin-\(UUID().uuidString)/u1/finance.json"))
    }

    private func makeRepo(_ store: FinanceStore, reservations: [Reservation] = [], site: FakeSite = FakeSite(),
                      fromCache: Bool = false) -> FinanceRepository {
        let t = now
        return FinanceRepository(
            store: store,
            loadReservations: { ids in (reservations.filter { ids.contains($0.propertyId) }, fromCache) },
            site: site,
            now: { t }
        )
    }

    private func res(_ id: String, _ pid: String = "p1", checkOut: Int64? = nil, guest: String? = "Mario") -> Reservation {
        let out = checkOut ?? now + day
        return Reservation(id: id, propertyId: pid, guestName: guest, checkIn: out - day, checkOut: out, platform: "BOOKING")
    }

    private func fin(_ r: Reservation) -> FinReservation { joinMoney([r], [:])[0] }

    func testSaveGrossTwiceKeepsASingleLinenExpense() async throws {
        let s = store()
        let repo = makeRepo(s)
        let r = fin(res("r1"))
        try await repo.saveGross(r, amount: 100)
        try await repo.saveGross(r, amount: 120)
        let data = await s.read()
        let linen = data.expenses.filter { $0.reservationId == "r1" }
        XCTAssertEqual(linen.count, 1)
        XCTAssertEqual(linen.first?.amount, linenAmount)
        XCTAssertEqual(linen.first?.category, ExpenseCategory.pulizie.key)
        XCTAssertEqual(linen.first?.description, "\(linenDescription) (Mario)")
        XCTAssertEqual(data.moneyById()["r1"]?.grossAmount, 120)
        XCTAssertEqual(data.moneyById()["r1"]?.source, ReservationMoney.manual)
    }

    func testSaveGrossThenClearGrossLeavesNoAmount() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.saveGross(fin(res("r1")), amount: 100)
        try await repo.clearGross("r1")
        var data = await s.read()
        XCTAssertNotNil(data.moneyById()["r1"])
        XCTAssertNil(data.moneyById()["r1"]?.grossAmount)
        // Nessun effetto su una prenotazione senza riga di soldi.
        try await repo.clearGross("sconosciuta")
        data = await s.read()
        XCTAssertNil(data.moneyById()["sconosciuta"])
    }

    func testExcelImportDoesNotOverrideAManualAmountButUpdatesTheRest() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.saveGross(fin(res("r1")), amount: 500)
        let row = ExcelMoneyRow(reservationId: "r1", propertyId: "p1", grossAmount: 300, commissionAmount: 71.4, bookedAt: 42,
                                travelPurpose: "leisure", bookingDevice: "mobile")
        try await repo.applyExcelImport([row], contacts: [], linenFor: ["r1"])
        let data = await s.read()
        let m = data.moneyById()["r1"]
        XCTAssertEqual(m?.grossAmount, 500)
        XCTAssertEqual(m?.source, ReservationMoney.manual)
        XCTAssertEqual(m?.commissionAmount, 71.4)
        XCTAssertEqual(m?.bookedAt, 42)
        XCTAssertEqual(m?.travelPurpose, "leisure")
        // La biancheria c'era già (da saveGross): non si raddoppia.
        XCTAssertEqual(data.expenses.filter { $0.reservationId == "r1" }.count, 1)
    }

    func testExcelImportFillsNewRowsAddsLinenAndContacts() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.applyExcelImport([ExcelMoneyRow(reservationId: "r2", propertyId: "p1", grossAmount: 300)],
                                        contacts: [Contact(phone: "333", name: "Anna", propertyId: "p1")], linenFor: ["r2"])
        let data = await s.read()
        XCTAssertEqual(data.moneyById()["r2"]?.grossAmount, 300)
        XCTAssertEqual(data.moneyById()["r2"]?.source, ReservationMoney.excel)
        XCTAssertEqual(data.expenses.filter { $0.reservationId == "r2" }.count, 1)
        XCTAssertEqual(data.contacts.map(\.phone), ["333"])
    }

    func testOnReservationDeletedRemovesLinkedExpensesAndMoney() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.saveGross(fin(res("r1")), amount: 100)
        try await repo.saveGross(fin(res("r2")), amount: 200)
        try await repo.addExpense(propertyId: "p1", description: "Bolletta", amount: 30, category: .utenze)
        try await repo.onReservationDeleted("r1")
        let data = await s.read()
        XCTAssertFalse(data.expenses.contains { $0.reservationId == "r1" })
        XCTAssertNil(data.moneyById()["r1"])
        XCTAssertEqual(data.expenses.filter { $0.reservationId == "r2" }.count, 1)
        XCTAssertEqual(data.expenses.filter { $0.reservationId == nil }.count, 1)
        XCTAssertEqual(data.moneyById()["r2"]?.grossAmount, 200)
    }

    func testAddAndDeleteExpenseAndRecurring() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.addExpense(propertyId: "p1", description: "Colf", amount: 50, category: .pulizie)
        var data = await s.read()
        XCTAssertEqual(data.expenses.count, 1)
        XCTAssertEqual(data.expenses.first?.authorId, "OWNER")
        try await repo.deleteExpense(data.expenses[0].id)
        data = await s.read()
        XCTAssertTrue(data.expenses.isEmpty)

        try await repo.addRecurring(propertyId: "p1", description: "Affitto", amount: 400, category: .altro)
        data = await s.read()
        XCTAssertEqual(data.recurring.count, 1)
        XCTAssertEqual(data.recurring.first?.startMonth, "2025-10")
        try await repo.deleteRecurring(data.recurring[0].id)
        data = await s.read()
        XCTAssertTrue(data.recurring.isEmpty)
    }

    func testLoadFiltersByHouseJoinsMoneyAndComputesPending() async throws {
        let s = store()
        let server = [
            res("r1"),                               // futura, senza importo -> in pending
            res("r2", checkOut: now - 60 * day),     // vecchia, senza importo -> fuori finestra
            res("r3"),                               // con importo
            res("r9", "p2"),                         // altra casa, non caricata
        ]
        try await s.update {
            $0.withMoney(ReservationMoney(reservationId: "r3", propertyId: "p1", grossAmount: 250))
                .withMoney(ReservationMoney(reservationId: "r9", propertyId: "p2", grossAmount: 77))
        }
        let snap = try await makeRepo(s, reservations: server).load(properties: [Property(id: "p1")])
        XCTAssertEqual(Set(snap.reservations.map(\.id)), ["r1", "r2", "r3"])
        XCTAssertEqual(snap.reservations.first(where: { $0.id == "r3" })?.grossAmount, 250)
        XCTAssertEqual(snap.pending.map(\.id), ["r1"])
        // I soldi della casa non caricata restano nel file.
        let data = await s.read()
        XCTAssertEqual(data.moneyById()["r9"]?.grossAmount, 77)
    }

    func testLoadFillsSiteAmountsAndSurvivesASiteFailure() async throws {
        let s = store()
        let server = [res("r1")]
        let ok = try await makeRepo(s, reservations: server,
                                site: FakeSite(rows: [SiteBookingAmount(reservationId: "r1", propertyId: "p1", totalPrice: 180)]))
            .load(properties: [Property(id: "p1")])
        XCTAssertEqual(ok.reservations.first?.grossAmount, 180)

        let failing = try await makeRepo(s, reservations: server, site: FakeSite(fails: true)).load(properties: [Property(id: "p1")])
        XCTAssertEqual(failing.reservations.first?.grossAmount, 180)
    }

    func testLoadDropsOrphansOfLoadedHouses() async throws {
        let s = store()
        try await s.update { $0.withMoney(ReservationMoney(reservationId: "gone", propertyId: "p1", grossAmount: 10)) }
        _ = try await makeRepo(s, reservations: [res("r1")]).load(properties: [Property(id: "p1")])
        let data = await s.read()
        XCTAssertNil(data.moneyById()["gone"])
    }

    func testLoadFromCacheKeepsMoneyAndLinkedExpenses() async throws {
        let s = store()
        try await makeRepo(s).saveGross(fin(res("r1")), amount: 100)   // soldi + biancheria collegata
        let snap = try await makeRepo(s, fromCache: true).load(properties: [Property(id: "p1")])
        var data = await s.read()
        XCTAssertEqual(data.moneyById()["r1"]?.grossAmount, 100)
        XCTAssertEqual(data.expenses.filter { $0.reservationId == "r1" }.count, 1)
        XCTAssertEqual(snap.expenses.filter { $0.reservationId == "r1" }.count, 1)

        // La stessa lettura dal server toglie gli orfani.
        _ = try await makeRepo(s, fromCache: false).load(properties: [Property(id: "p1")])
        data = await s.read()
        XCTAssertNil(data.moneyById()["r1"])
        XCTAssertFalse(data.expenses.contains { $0.reservationId == "r1" })
    }

    func testMoneyWrittenDuringTheServerReadSurvives() async throws {
        let s = store()
        try await s.update { $0.withMoney(ReservationMoney(reservationId: "vecchia", propertyId: "p1", grossAmount: 10)) }
        let t = now
        let racing = FinanceRepository(
            store: s,
            loadReservations: { _ in
                // Mentre si legge dal server, un import Excel scrive una riga nuova.
                try await s.update { $0.withMoney(ReservationMoney(reservationId: "nuova", propertyId: "p1", grossAmount: 50)) }
                return ([], false)
            },
            site: FakeSite(),
            now: { t }
        )
        _ = try await racing.load(properties: [Property(id: "p1")])
        let data = await s.read()
        XCTAssertEqual(data.moneyById()["nuova"]?.grossAmount, 50)
        XCTAssertNil(data.moneyById()["vecchia"])
    }

    func testWipeEmptiesEverything() async throws {
        let s = store()
        let repo = makeRepo(s)
        try await repo.saveGross(fin(res("r1")), amount: 100)
        await repo.wipe()
        let data = await s.read()
        XCTAssertEqual(data, FinanceData())
    }
}
