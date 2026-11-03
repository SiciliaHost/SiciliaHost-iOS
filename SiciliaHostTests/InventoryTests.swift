import XCTest
@testable import SiciliaHost

// Specifica: StockStatusTest e NormalizeBarcodeTest dell'app Android, più le regole di quantità e filtri di
// `InventoryScreen.kt` (estratte in `InventoryLogic`).
final class InventoryTests: XCTestCase {
    private func item(_ quantity: Int, threshold: Int = 2, depleted: Bool = false) -> InventoryItem {
        InventoryItem(name: "Detersivo", quantity: quantity, lowStockThreshold: threshold, isDepleted: depleted)
    }

    // MARK: StockStatusTest

    func testQuantityAboveThresholdIsOk() { XCTAssertEqual(stockStatus(item(3, threshold: 2)), .ok) }
    func testQuantityEqualToThresholdIsLow() { XCTAssertEqual(stockStatus(item(2, threshold: 2)), .low) }
    func testQuantityBelowThresholdIsLow() { XCTAssertEqual(stockStatus(item(1, threshold: 2)), .low) }
    func testDepletedFlagWinsOverQuantity() { XCTAssertEqual(stockStatus(item(5, threshold: 2, depleted: true)), .depleted) }
    func testZeroQuantityWithoutFlagIsLow() { XCTAssertEqual(stockStatus(item(0, threshold: 1)), .low) }

    // MARK: NormalizeBarcodeTest

    func testUpcAPadsToEan13() { XCTAssertEqual(normalizeBarcode("036000291452"), "0036000291452") }
    func testEan13StaysUnchanged() { XCTAssertEqual(normalizeBarcode("0036000291452"), "0036000291452") }
    func testNonNumericCodeStaysUnchanged() { XCTAssertEqual(normalizeBarcode("ABC-123-XYZ"), "ABC-123-XYZ") }
    func testElevenDigitCodeIsNotPadded() { XCTAssertEqual(normalizeBarcode("12345678901"), "12345678901") }
    func testWhitespaceIsTrimmed() { XCTAssertEqual(normalizeBarcode("  036000291452  "), "0036000291452") }

    // MARK: Regole dell'elenco

    func testQuantityTransitions() {
        let plus = InventoryLogic.plusOne(item(0, depleted: true))
        XCTAssertEqual(plus.quantity, 1)
        XCTAssertFalse(plus.isDepleted)
        XCTAssertNil(InventoryLogic.minusOne(item(0)))
        let lastOne = InventoryLogic.minusOne(item(1))!
        XCTAssertEqual(lastOne.quantity, 0)
        XCTAssertTrue(lastOne.isDepleted)
        let depleted = InventoryLogic.reportDepleted(item(4))
        XCTAssertEqual(depleted.quantity, 0)
        XCTAssertTrue(depleted.isDepleted)
        XCTAssertEqual(InventoryLogic.settingQuantity(-3, of: item(2)).quantity, 0)
        XCTAssertTrue(InventoryLogic.settingQuantity(-3, of: item(2)).isDepleted)
    }

    func testEditKeepsOldNumbersWhenTextIsNotANumber() {
        let base = InventoryItem(id: "i", name: "Old", barcode: "1", quantity: 4, lowStockThreshold: 3, category: "Altro")
        let e = InventoryLogic.edited(base, name: " Sapone ", barcode: "036000291452", category: "Pulizia", quantity: "x", threshold: "")
        XCTAssertEqual(e.name, "Sapone")
        XCTAssertEqual(e.barcode, "0036000291452")
        XCTAssertEqual(e.quantity, 4)
        XCTAssertEqual(e.lowStockThreshold, 3)
        XCTAssertEqual(e.category, "Pulizia")
        XCTAssertNil(InventoryLogic.edited(base, name: "a", barcode: "  ", category: "Altro", quantity: "0", threshold: "1").barcode)
        XCTAssertTrue(InventoryLogic.edited(base, name: "a", barcode: "", category: "Altro", quantity: "0", threshold: "1").isDepleted)
    }

    func testNewItemDefaults() {
        let n = InventoryLogic.newItem(propertyId: "p", name: " Carta ", barcode: nil, category: "Consumabili", quantity: "")
        XCTAssertEqual(n.name, "Carta")
        XCTAssertEqual(n.quantity, 1)
        XCTAssertEqual(n.lowStockThreshold, 2)
        XCTAssertNil(n.barcode)
        XCTAssertFalse(n.isDepleted)
    }

    func testExistingIsScopedToTheHouseAndNormalized() {
        let a = InventoryItem(id: "a", propertyId: "p1", name: "Caffè", barcode: "036000291452")
        let b = InventoryItem(id: "b", propertyId: "p2", name: "", barcode: "0036000291452")
        XCTAssertEqual(InventoryLogic.existing(barcode: "0036000291452", propertyId: "p1", in: [a, b])?.id, "a")
        XCTAssertEqual(InventoryLogic.existing(barcode: "0036000291452", propertyId: "p2", in: [a, b])?.id, "b")
        XCTAssertNil(InventoryLogic.existing(barcode: "0036000291452", propertyId: "p3", in: [a, b]))
        XCTAssertEqual(InventoryLogic.knownName(barcode: "0036000291452", in: [b, a]), "Caffè")
    }

    func testFilter() {
        let items = [
            InventoryItem(id: "1", propertyId: "p1", name: "Detersivo piatti", category: "Pulizia"),
            InventoryItem(id: "2", propertyId: "p2", name: "Lenzuola", category: "Biancheria"),
        ]
        XCTAssertEqual(InventoryLogic.filter(items, propertyId: nil, category: "Tutte", search: "").count, 2)
        XCTAssertEqual(InventoryLogic.filter(items, propertyId: "p2", category: "Tutte", search: "").map(\.id), ["2"])
        XCTAssertEqual(InventoryLogic.filter(items, propertyId: nil, category: "Pulizia", search: "").map(\.id), ["1"])
        XCTAssertEqual(InventoryLogic.filter(items, propertyId: nil, category: "Tutte", search: "PIATTI").map(\.id), ["1"])
    }

    func testOpenFactsResponseParsing() {
        let ok = Data(#"{"status":1,"product":{"product_name":" Nutella "}}"#.utf8)
        XCTAssertEqual(InventoryLogic.productName(fromOpenFactsJson: ok), "Nutella")
        XCTAssertNil(InventoryLogic.productName(fromOpenFactsJson: Data(#"{"status":0}"#.utf8)))
        XCTAssertNil(InventoryLogic.productName(fromOpenFactsJson: Data(#"{"status":1,"product":{"product_name":""}}"#.utf8)))
        XCTAssertNil(InventoryLogic.productName(fromOpenFactsJson: Data("non json".utf8)))
    }
}
