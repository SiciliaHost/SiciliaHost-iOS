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
}
