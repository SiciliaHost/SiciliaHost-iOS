import XCTest
@testable import SiciliaHost

final class CactusAvatarTests: XCTestCase {
    func testClassifyFace() {
        let children = [
            FaceChild(childCount: 2, x: 0.0),    // Visor
            FaceChild(childCount: 1, x: -0.3),   // Left eye
            FaceChild(childCount: 1, x: 0.3),    // Right eye
            FaceChild(childCount: 5, x: 0.0)     // Mouth
        ]

        let layout = classifyFace(children: children)
        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.visor, 0)
        XCTAssertEqual(layout?.leftEye, 1)
        XCTAssertEqual(layout?.rightEye, 2)
        XCTAssertEqual(layout?.mouth, 3)

        // Bambino con conteggio errato fallisce
        let broken = [
            FaceChild(childCount: 2, x: 0.0),
            FaceChild(childCount: 1, x: -0.3),
            FaceChild(childCount: 1, x: 0.3),
            FaceChild(childCount: 4, x: 0.0)
        ]
        XCTAssertNil(classifyFace(children: broken))
    }

    func testOrderByX() {
        let xs: [Float] = [0.5, -0.2, 0.0, -0.8]
        let sortedIndices = orderByX(xs)
        XCTAssertEqual(sortedIndices, [3, 1, 2, 0])
    }

    class TestNode {
        let name: String
        var children: [TestNode] = []
        init(name: String) { self.name = name }
    }

    func testFruitGlowNodes() {
        let fruit = TestNode(name: "Frutto_Rosso_1")
        let detail = TestNode(name: "Frutto_Rosso_1_Details")
        let sub = TestNode(name: "Frutto_Rosso_1_Mesh")
        fruit.children = [detail, sub]

        let glowNodes = fruitGlowNodes(fruit: fruit, nameOf: { $0.name }, childrenOf: { $0.children })
        XCTAssertEqual(glowNodes.count, 2)
        XCTAssertTrue(glowNodes.contains(where: { $0.name == "Frutto_Rosso_1" }))
        XCTAssertTrue(glowNodes.contains(where: { $0.name == "Frutto_Rosso_1_Mesh" }))
        XCTAssertFalse(glowNodes.contains(where: { $0.name == "Frutto_Rosso_1_Details" }))
    }

    func testAvatarGate() {
        let store = InMemoryGateStore()
        let gate = AvatarGate(store: store, isSupported: true, appStampProvider: { 100 })

        // Primo avvio consentito
        XCTAssertTrue(gate.begin())
        XCTAssertTrue(store.read().initPending)

        // Fine inizializzazione riuscita
        gate.initFinished()
        XCTAssertFalse(store.read().initPending)
        XCTAssertEqual(store.read().failedStarts, 0)

        // Simula avvio interrotto (crash / abort nativo)
        XCTAssertTrue(gate.begin()) // abort 1
        // Prossimo avvio rileva initPending ma riprova una volta (failedStarts = 1)
        XCTAssertTrue(gate.begin()) // riprova (1 fallito), abort 2
        XCTAssertEqual(store.read().failedStarts, 1)

        // Secondo crash consecutivo spegne l'avatar per questa versione
        XCTAssertFalse(gate.begin()) // 2 falliti di fila: spento
        XCTAssertEqual(store.read().disabledStamp, 100)
        XCTAssertFalse(store.read().initPending)

        // Rifiutato finché l'app non viene aggiornata (appStamp cambia)
        XCTAssertFalse(gate.begin())

        // Dopo aggiornamento app (appStamp = 101)
        let updatedGate = AvatarGate(store: store, isSupported: true, appStampProvider: { 101 })
        XCTAssertTrue(updatedGate.begin())
    }

    func testStartConfirmed() {
        XCTAssertFalse(startConfirmed(framesDrawn: 0, animated: true))
        XCTAssertFalse(startConfirmed(framesDrawn: 5, animated: true))
        XCTAssertTrue(startConfirmed(framesDrawn: 15, animated: true))
        XCTAssertTrue(startConfirmed(framesDrawn: 1, animated: false)) // con animazioni disattivate basta 1 fotogramma
    }
}
