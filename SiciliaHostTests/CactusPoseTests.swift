import XCTest
@testable import SiciliaHost

final class CactusPoseTests: XCTestCase {
    func testFruitPoseAtRest() {
        // Fuori da thinking i frutti sono a riposo
        XCTAssertEqual(fruitPose(state: .idle, t: 1.0, index: 0), FruitPose.rest)
        XCTAssertEqual(fruitPose(state: .listening, t: 2.0, index: 1), FruitPose.rest)
        XCTAssertEqual(fruitPose(state: .speaking, t: 3.0, index: 2), FruitPose.rest)
    }

    func testFruitPoseBounceInThinking() {
        // A tempo 0, il frutto 0 è all'inizio del ciclo
        let p0 = fruitPose(state: .thinking, t: 0.1, index: 0)
        XCTAssertTrue(p0.dy >= 0)
        XCTAssertTrue(p0.sy >= 1.0)

        // Sfasamento tra i frutti: a pari tempo frutti diversi hanno pose diverse
        let p1 = fruitPose(state: .thinking, t: 0.1, index: 1)
        XCTAssertNotEqual(p0, p1)
    }

    func testEyeScale() {
        let listeningEye = eyeScale(state: .listening, t: 0.0)
        XCTAssertEqual(listeningEye.sx, 1.15)
        XCTAssertEqual(listeningEye.sy, 1.25)

        let errorEye = eyeScale(state: .error, t: 0.0)
        XCTAssertEqual(errorEye.sx, 1.0)
        XCTAssertEqual(errorEye.sy, 0.7)

        let thinkingEye = eyeScale(state: .thinking, t: 0.0)
        XCTAssertEqual(thinkingEye.sx, 1.0)
        XCTAssertEqual(thinkingEye.sy, 1.0)
    }

    func testMouthLength() {
        XCTAssertEqual(mouthLength(state: .listening, t: 0.0, index: 0), 0.25)
        XCTAssertEqual(mouthLength(state: .error, t: 0.0, index: 0), 0.2)
        XCTAssertEqual(mouthLength(state: .idle, t: 0.0, index: 0), 0.4)

        let speakingH = mouthLength(state: .speaking, t: 0.5, index: 2)
        XCTAssertTrue(speakingH >= 0.3 && speakingH <= 1.0)
    }

    func testEffectivePose() {
        let disabled = effectivePose(state: .thinking, t: 5.0, animationsEnabled: false)
        XCTAssertEqual(disabled.state, .idle)
        XCTAssertEqual(disabled.timeS, 0.0)

        let enabled = effectivePose(state: .thinking, t: 5.0, animationsEnabled: true)
        XCTAssertEqual(enabled.state, .thinking)
        XCTAssertEqual(enabled.timeS, 5.0)
    }
}
