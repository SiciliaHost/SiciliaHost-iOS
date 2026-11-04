import XCTest
@testable import SiciliaHost

final class CactusLiveTests: XCTestCase {
    func testLiveReducerTransitions() {
        var state = LiveState()
        XCTAssertFalse(state.isActive)

        state = liveReducer(state: state, action: .start(mode: .do_, stepText: "Inizio"))
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.mode, .do_)
        XCTAssertEqual(state.stepText, "Inizio")
        XCTAssertTrue(state.isActive)

        let stage = LiveStage(kind: .writing, section: .prices, propertyId: "p1", key: "price.base", label: "Prezzo", before: "100", after: "120")
        state = liveReducer(state: state, action: .step(stepText: "Scrivo prezzi", stage: stage, activeChanges: nil, activeKey: "price.base"))
        XCTAssertEqual(state.stepText, "Scrivo prezzi")
        XCTAssertEqual(state.stage?.key, "price.base")

        state = liveReducer(state: state, action: .progress(0.5))
        XCTAssertEqual(state.stage?.progress, 0.5)

        state = liveReducer(state: state, action: .requestStop)
        XCTAssertTrue(state.stopRequested)

        state = liveReducer(state: state, action: .finish(stepText: "Fine", stage: nil))
        XCTAssertEqual(state.phase, .finishing)
        XCTAssertFalse(state.stopRequested)

        state = liveReducer(state: state, action: .reset)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.isActive)
    }

    func testFieldDuration() {
        XCTAssertEqual(fieldDuration(count: 0, valueLength: 10), 0)
        XCTAssertEqual(fieldDuration(count: 1, valueLength: 10), 520)
        XCTAssertEqual(fieldDuration(count: 3, valueLength: 10), 320)
        XCTAssertTrue(fieldDuration(count: 10, valueLength: 10) >= 140)

        // Extra per testo lungo (> 60 car)
        let normal = fieldDuration(count: 1, valueLength: 20)
        let long = fieldDuration(count: 1, valueLength: 100)
        XCTAssertTrue(long > normal)
    }

    func testCountedText() {
        XCTAssertEqual(countedText(before: "80 €", after: "100 €", progress: 0.0), "80 €")
        XCTAssertEqual(countedText(before: "80 €", after: "100 €", progress: 0.5), "90 €")
        XCTAssertEqual(countedText(before: "80 €", after: "100 €", progress: 1.0), "100 €")

        // Con virgola e decimali
        XCTAssertEqual(countedText(before: "10,00 €", after: "20,00 €", progress: 0.5), "15,00 €")

        // Percentuale
        XCTAssertEqual(countedText(before: "10%", after: "20%", progress: 0.5), "15%")
    }

    func testInvertChanges() {
        let ch = [Change(key: "k1", label: "L", before: "A", after: "B")]
        let inv = invertChanges(ch)
        XCTAssertEqual(inv[0].before, "B")
        XCTAssertEqual(inv[0].after, "A")
    }

    func testMergePlans() {
        let plan1 = [
            LiveStep(section: .prices, propertyId: "p1", keys: ["k1", "k2"]),
            LiveStep(section: .texts, propertyId: "p1", keys: ["t1"])
        ]
        let plan2 = [
            LiveStep(section: .prices, propertyId: "p1", keys: ["k2", "k3"])
        ]

        let merged = mergePlans([plan1, plan2])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].section, .prices)
        XCTAssertEqual(merged[0].keys, ["k1", "k2", "k3"])
        XCTAssertEqual(merged[1].section, .texts)
        XCTAssertEqual(merged[1].keys, ["t1"])
    }

    func testLiveTargetFor() {
        let ov = liveTargetFor(step: LiveStep(section: .overview, propertyId: "", keys: []))
        XCTAssertEqual(ov.tab, .home)

        let cal = liveTargetFor(step: LiveStep(section: .calendar, propertyId: "p1", keys: []))
        XCTAssertEqual(cal.tab, .agenda)
        XCTAssertEqual(cal.propertyId, "p1")

        let fin = liveTargetFor(step: LiveStep(section: .finance, propertyId: "p1", keys: []))
        XCTAssertEqual(fin.tab, .finanze)

        let pr = liveTargetFor(step: LiveStep(section: .prices, propertyId: "p1", keys: []))
        XCTAssertEqual(pr.tab, .case_)
        XCTAssertEqual(pr.caseSection, .prezzi)

        let srv = liveTargetFor(step: LiveStep(section: .services, propertyId: "p1", keys: []))
        XCTAssertEqual(srv.tab, .case_)
        XCTAssertEqual(srv.caseSection, .contenuti)
        XCTAssertEqual(srv.caseSub, .services)
    }
}
