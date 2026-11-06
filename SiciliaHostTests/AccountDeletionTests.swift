import XCTest
@testable import SiciliaHost

// "Elimina account" e "Segnala un problema" (stessi casi di AccountDeletionLogicTest dell'Android).
final class AccountDeletionTests: XCTestCase {
    func testProviderPrefersAppleSoTheTokenGetsRevoked() {
        XCTAssertEqual(AccountDeletionLogic.provider(for: ["apple.com"]), .apple)
        XCTAssertEqual(AccountDeletionLogic.provider(for: ["google.com"]), .google)
        XCTAssertEqual(AccountDeletionLogic.provider(for: ["google.com", "apple.com"]), .apple)
        XCTAssertNil(AccountDeletionLogic.provider(for: ["password"]))
        XCTAssertNil(AccountDeletionLogic.provider(for: []))
    }

    func testOwnedHouseNamesOnlyCountsOwnedHouses() {
        let mine = Property(id: "p1", name: "Casa Kalsa", members: ["me": "OWNER"], memberUids: ["me"])
        let theirs = Property(id: "p2", name: "Altra", members: ["me": "COLLABORATOR", "x": "OWNER"], memberUids: ["me", "x"])
        let scope = AccessScope(uid: "me", isSuperAdmin: false, properties: [mine, theirs])
        XCTAssertEqual(AccountDeletionLogic.ownedHouseNames(scope), ["Casa Kalsa"])
        XCTAssertEqual(AccountDeletionLogic.ownedHouseNames(nil), [])
    }

    func testOwnedHousesMessage() {
        XCTAssertTrue(AccountDeletionLogic.ownedHousesMessage(["Casa Kalsa"]).contains("di «Casa Kalsa»"))
        XCTAssertTrue(AccountDeletionLogic.ownedHousesMessage(["A", "B"]).contains("di «A», «B»"))
        XCTAssertTrue(AccountDeletionLogic.ownedHousesMessage([""]).contains("delle case"))
    }

    func testDescribeServerErrors() {
        let owns = AccountDeletionLogic.describe(
            code: "FAILED_PRECONDITION", message: "owns-properties",
            details: ["reason": "owns-properties", "properties": ["Casa Kalsa"]]
        )
        XCTAssertTrue(owns.contains("«Casa Kalsa»"))
        XCTAssertEqual(
            AccountDeletionLogic.describe(code: "FAILED_PRECONDITION", message: "recent-login-required", details: nil),
            "Per sicurezza accedi di nuovo e riprova."
        )
        XCTAssertTrue(AccountDeletionLogic.describe(code: "UNAVAILABLE", message: nil, details: nil).contains("Connessione"))
        XCTAssertTrue(AccountDeletionLogic.describe(code: "INTERNAL", message: nil, details: nil).contains("INTERNAL"))
    }

    func testSupportMailBodyCarriesVersionAndDevice() {
        let body = SupportMail.body(appVersion: "1.0", build: "42", device: "iPhone16,2", system: "18.1")
        XCTAssertTrue(body.contains("CactusHost 1.0 (42)"))
        XCTAssertTrue(body.contains("iPhone16,2"))
        XCTAssertTrue(body.contains("iOS 18.1"))
    }

    func testSupportMailURL() throws {
        let url = try XCTUnwrap(SupportMail.url())
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:info@siciliahost.com?"))
    }
}
