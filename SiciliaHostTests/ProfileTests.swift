import XCTest
@testable import SiciliaHost

// Specifica: DisplayNameTest e HouseAccessLogicTest dell'app Android.
final class ProfileTests: XCTestCase {
    func testCleanDisplayNameTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(cleanDisplayName("  Anna \t  Rossi \n"), "Anna Rossi")
    }

    func testValidateDisplayName() {
        XCTAssertNil(validateDisplayName("Anna"))
        XCTAssertNil(validateDisplayName("  Maria Grazia D'Angelo  "))
        XCTAssertNil(validateDisplayName(String(repeating: "A", count: displayNameMax)))
        XCTAssertEqual(validateDisplayName("   "), "Inserisci un nome")
        XCTAssertEqual(validateDisplayName(String(repeating: "A", count: displayNameMax + 1)), "Al massimo \(displayNameMax) caratteri")
        XCTAssertEqual(validateDisplayName("Anna\u{0000}"), "Caratteri non validi")
    }

    private let me = "me"

    private func house(_ id: String, _ name: String, _ role: String, perms: [String] = []) -> Property {
        Property(id: id, name: name, members: [me: role, "other": "OWNER"], memberUids: [me, "other"],
                 permissions: perms.isEmpty ? [:] : [me: perms])
    }

    private func scope(_ houses: [Property], admin: Bool = false) -> AccessScope {
        AccessScope(uid: me, isSuperAdmin: admin, properties: houses)
    }

    func testPermissionsSummaryListsLabelsInFixedOrder() {
        XCTAssertEqual(permissionsSummary([.prices, .finance]), "Finanze, Prezzi e calendario")
        XCTAssertEqual(permissionsSummary([]), "Nessun permesso aggiuntivo")
    }

    func testHouseRowsPutOwnedFirstThenByName() {
        let rows = houseRows(scope([house("1", "Zagara", "COLLABORATOR"), house("2", "Bottega", "OWNER"), house("3", "Agrumeto", "COLLABORATOR")]))
        XCTAssertEqual(rows.map(\.propertyId), ["2", "3", "1"])
    }

    func testHouseRowsShowPermissionsOnlyForCollaborators() {
        let rows = Dictionary(uniqueKeysWithValues: houseRows(scope([
            house("1", "Casa A", "OWNER"), house("2", "Casa B", "COLLABORATOR", perms: ["FINANCE"]),
        ])).map { ($0.propertyId, $0) })
        XCTAssertEqual(rows["1"]?.roleLabel, "Proprietario")
        XCTAssertNil(rows["1"]?.permissionsText)
        XCTAssertEqual(rows["2"]?.roleLabel, "Collaboratore")
        XCTAssertEqual(rows["2"]?.permissionsText, "Finanze")
    }

    func testSuperAdminOnAnotherHostsHouseIsLabelledAdministrator() {
        let foreign = Property(id: "9", name: "Altrui", members: ["x": "OWNER"], memberUids: ["x"])
        let s = scope([foreign], admin: true)
        XCTAssertEqual(houseRoleLabel(s, foreign), "Amministratore")
        XCTAssertEqual(houseRows(s).map(\.propertyId), ["9"])
    }

    func testLeaveAndManageRules() {
        let owned = house("1", "A", "OWNER"), shared = house("2", "B", "COLLABORATOR")
        let s = scope([owned, shared])
        XCTAssertFalse(canLeaveHouse(s, owned))
        XCTAssertTrue(canLeaveHouse(s, shared))
        XCTAssertTrue(canManageMembers(s, owned))
        XCTAssertFalse(canManageMembers(s, shared))
    }

    // Specifica: PrivacyContentTest.
    func testPrivacySectionsAreComplete() {
        XCTAssertFalse(privacySections.isEmpty)
        for section in privacySections {
            XCTAssertFalse(section.title.trimmed.isEmpty)
            XCTAssertFalse(section.body.trimmed.isEmpty, section.title)
        }
        XCTAssertEqual(Set(privacySections.map(\.title)).count, privacySections.count)
        XCTAssertEqual(LegalLinks.privacy.absoluteString, "https://siciliahost.com/it/privacy")
        XCTAssertEqual(LegalLinks.terms.absoluteString, "https://siciliahost.com/it/termini")
        let location = privacySections.first { $0.title == "Posizione delle case" }?.body ?? ""
        XCTAssertTrue(location.contains("pin") && location.contains("mai l'indirizzo"))
    }
}
