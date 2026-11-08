import XCTest
@testable import SiciliaHost

final class EmailAuthLogicTests: XCTestCase {
    func testUnverifiedAccountMustConfirmTheEmail() {
        XCTAssertTrue(EmailAuthLogic.needsEmailVerification(uid: "uid-qualunque", emailVerified: false))
    }

    func testVerifiedAccountEnters() {
        XCTAssertFalse(EmailAuthLogic.needsEmailVerification(uid: "uid-qualunque", emailVerified: true))
    }

    func testDemoReviewerEntersWithoutVerification() {
        XCTAssertFalse(EmailAuthLogic.needsEmailVerification(uid: EmailAuthLogic.demoReviewerUid, emailVerified: false))
    }

    func testPlausibleEmails() {
        XCTAssertTrue(EmailAuthLogic.isPlausibleEmail("a@b.it"))
        XCTAssertTrue(EmailAuthLogic.isPlausibleEmail("  mario.rossi@example.com "))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail(""))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail("senza-chiocciola"))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail("@dominio.it"))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail("a@b"))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail("a@.it"))
        XCTAssertFalse(EmailAuthLogic.isPlausibleEmail("a b@c.it"))
    }

    func testMessagesMentionTheRightThing() {
        XCTAssertTrue(EmailAuthLogic.weakPasswordMessage.contains("\(EmailAuthLogic.minPasswordLength)"))
        XCTAssertTrue(EmailAuthLogic.notVerifiedMessage.contains("confermare l'email"))
    }
}
