import XCTest
@testable import SiciliaHost

final class AccessScopeTests: XCTestCase {
    private func house(_ id: String, members: [String: String], permissions: [String: [String]] = [:],
                       commission: Bool = false) -> Property {
        Property(id: id, name: id, isManagedOnCommission: commission, members: members,
                 memberUids: Array(members.keys), permissions: permissions)
    }

    func testOwnerManagesAndOperates() {
        let h = house("a", members: ["u1": "OWNER"])
        let scope = AccessScope(uid: "u1", isSuperAdmin: false, properties: [h])
        XCTAssertTrue(scope.canOperate(h))
        XCTAssertTrue(scope.canManage(h))
        XCTAssertTrue(scope.canFinance(h))
        XCTAssertEqual(scope.profileLabel, "PROPRIETARIO")
    }

    func testCollaboratorWithoutPermissionsOnlyOperates() {
        let h = house("a", members: ["u2": "COLLABORATOR"])
        let scope = AccessScope(uid: "u2", isSuperAdmin: false, properties: [h])
        XCTAssertTrue(scope.canOperate(h))
        XCTAssertFalse(scope.canManage(h))
        XCTAssertFalse(scope.canFinance(h))
        XCTAssertEqual(MainTabs.visible(for: scope), [.home, .agenda, .scorte])
    }

    func testCollaboratorPermissionsGrantTabsButNeverFinance() {
        // Un FINANCE rimasto nei dati vecchi non dà più le Finanze: sono del solo proprietario.
        let h = house("a", members: ["u2": "COLLABORATOR"], permissions: ["u2": ["FINANCE", "SITE", "BOGUS"]])
        let scope = AccessScope(uid: "u2", isSuperAdmin: false, properties: [h])
        XCTAssertFalse(scope.canFinance(h))
        XCTAssertTrue(scope.financeProperties.isEmpty)
        XCTAssertTrue(scope.canEditSite(h))
        XCTAssertFalse(scope.canEditPrices(h))
        XCTAssertEqual(MainTabs.visible(for: scope), [.home, .agenda, .scorte, .case_])
    }

    func testFinanceOnlyForOwner() {
        let mine = house("a", members: ["u1": "OWNER"])
        let shared = house("b", members: ["x": "OWNER", "u1": "COLLABORATOR"], permissions: ["u1": ["PRICES", "SITE"]])
        let scope = AccessScope(uid: "u1", isSuperAdmin: false, properties: [mine, shared])
        XCTAssertTrue(scope.canFinance(mine))
        XCTAssertFalse(scope.canFinance(shared))
        XCTAssertEqual(scope.financeProperties.map(\.id), ["a"])
        XCTAssertEqual(MainTabs.visible(for: scope), [.home, .agenda, .scorte, .finanze, .case_])
    }

    func testSuperAdminOnCommissionHouseManagesButHasNoFinance() {
        let commission = house("b", members: ["x": "OWNER"], commission: true)
        let scope = AccessScope(uid: "admin", isSuperAdmin: true, properties: [commission])
        XCTAssertTrue(scope.canManage(commission))
        XCTAssertFalse(scope.canFinance(commission))
        XCTAssertTrue(scope.financeProperties.isEmpty)
        XCTAssertFalse(MainTabs.visible(for: scope).contains(.finanze))
    }

    func testPermissionsIgnoredWhenNoLongerCollaborator() {
        let h = house("a", members: ["u2": "OWNER"], permissions: ["u2": ["FINANCE"]])
        XCTAssertTrue(h.permissionsOf("u2").isEmpty)
    }

    func testSuperAdminOnlyManagesOwnedOrCommissionHouses() {
        let other = house("a", members: ["x": "OWNER"])
        let commission = house("b", members: ["x": "OWNER"], commission: true)
        let scope = AccessScope(uid: "admin", isSuperAdmin: true, properties: [other, commission])
        XCTAssertFalse(scope.canOperate(other))
        XCTAssertTrue(scope.canManage(commission))
        XCTAssertEqual(scope.others.map(\.id), ["a"])
        XCTAssertEqual(scope.appFieldsAccess(other), .viaAdmin)
        XCTAssertEqual(scope.profileLabel, "AMMINISTRATORE")
    }

    func testSuperAdminAccountNeedsVerifiedExactEmail() {
        XCTAssertTrue(isSuperAdminAccount(email: superAdminEmail, emailVerified: true))
        XCTAssertFalse(isSuperAdminAccount(email: superAdminEmail, emailVerified: false))
        XCTAssertFalse(isSuperAdminAccount(email: "altro@example.com", emailVerified: true))
    }

    func testAccessState() {
        let empty = AccessScope(uid: "u", isSuperAdmin: false, properties: [])
        XCTAssertEqual(accessState(loading: true, failed: false, scope: nil), .loading)
        XCTAssertEqual(accessState(loading: false, failed: true, scope: empty), .failed)
        XCTAssertEqual(accessState(loading: false, failed: false, scope: nil), .failed)
        XCTAssertEqual(accessState(loading: false, failed: false, scope: empty), .noHouses)
    }

    func testAppFieldsNeverContainMembership() {
        let h = house("a", members: ["u1": "OWNER"])
        let keys = Set(h.appFields.keys)
        XCTAssertFalse(keys.contains("members"))
        XCTAssertFalse(keys.contains("memberUids"))
        XCTAssertFalse(keys.contains("permissions"))
        XCTAssertFalse(keys.contains("alloggiatiConfigured"))
    }
}
