import XCTest
@testable import SiciliaHost

// Specifica: MembersLogicTest, InviteFormTest, InviteFormatTest, InviteViewModelTest dell'app Android.
final class MembersTests: XCTestCase {
    // MARK: MembersLogicTest

    func testValidateTransferEmailAcceptsAWellFormedAddressAndTrims() {
        XCTAssertNil(MembersLogic.validateTransferEmail(" nuovo@example.com ", myEmail: "me@example.com"))
    }

    func testValidateTransferEmailRejectsBlankMalformedAndSelf() {
        XCTAssertEqual(MembersLogic.validateTransferEmail("  ", myEmail: "me@example.com"), "Inserisci l'email del nuovo proprietario")
        XCTAssertEqual(MembersLogic.validateTransferEmail("non-una-email", myEmail: "me@example.com"), "Email non valida")
        XCTAssertEqual(MembersLogic.validateTransferEmail("a@b", myEmail: "me@example.com"), "Email non valida")
        XCTAssertEqual(MembersLogic.validateTransferEmail("ME@example.com", myEmail: "me@example.com"), "Sei già il proprietario")
    }

    func testSortPutsOwnersFirstThenByEmail() {
        let sorted = MembersLogic.sort([
            MemberInfo(uid: "u3", role: .collaborator, email: "zeta@example.com"),
            MemberInfo(uid: "u2", role: .owner, email: "owner@example.com"),
            MemberInfo(uid: "u1", role: .collaborator, email: "alfa@example.com"),
        ])
        XCTAssertEqual(sorted.map(\.uid), ["u2", "u1", "u3"])
    }

    func testSortSortsCollaboratorsByDisplayedLabelIgnoringCase() {
        let sorted = MembersLogic.sort([
            MemberInfo(uid: "u1", role: .collaborator, email: "a@example.com", displayName: "zoe"),
            MemberInfo(uid: "u2", role: .collaborator, email: "z@example.com", displayName: "Anna"),
            MemberInfo(uid: "u3", role: .collaborator, email: "m@example.com"),
        ])
        XCTAssertEqual(sorted.map(\.uid), ["u2", "u3", "u1"])
    }

    func testLabelPrefersDisplayNameThenEmailThenFallback() {
        XCTAssertEqual(MembersLogic.label(MemberInfo(uid: "u1", role: .owner, email: "a@x.it", displayName: "Anna")), "Anna")
        XCTAssertEqual(MembersLogic.label(MemberInfo(uid: "u1", role: .owner, email: "a@x.it")), "a@x.it")
        XCTAssertEqual(MembersLogic.label(MemberInfo(uid: "u1", role: .owner, email: "")), "Account non più disponibile")
    }

    func testCanRemoveOnlyCollaboratorsOtherThanYou() {
        let collab = MemberInfo(uid: "u1", role: .collaborator, email: "a@example.com")
        let owner = MemberInfo(uid: "u2", role: .owner, email: "o@example.com")
        XCTAssertTrue(MembersLogic.canRemove(collab, myUid: "u2"))
        XCTAssertFalse(MembersLogic.canRemove(owner, myUid: "u2"))
        XCTAssertFalse(MembersLogic.canRemove(collab, myUid: "u1"))
        XCTAssertTrue(MembersLogic.canEditPermissions(collab))
        XCTAssertFalse(MembersLogic.canEditPermissions(owner))
    }

    func testTogglePermissionAddsAndRemovesIdempotently() {
        let none = Set<PropertyPermission>()
        let withFinance = MembersLogic.toggle(none, .finance, true)
        XCTAssertEqual(withFinance, [.finance])
        XCTAssertEqual(MembersLogic.toggle(withFinance, .finance, true), withFinance)
        let both = MembersLogic.toggle(withFinance, .site, true)
        XCTAssertEqual(both, [.finance, .site])
        XCTAssertEqual(MembersLogic.toggle(both, .finance, false), [.site])
        XCTAssertEqual(MembersLogic.toggle(none, .prices, false), none)
    }

    // MARK: InviteFormTest

    private let order = ["a", "b", "c"]

    func testCreatePreselectsOnlyTheCurrentHouseWithNoPermissions() {
        let form = InviteForm.create(order: order, currentId: "b")
        XCTAssertTrue(form.isSelected("b"))
        XCTAssertFalse(form.isSelected("a"))
        XCTAssertEqual(form.permissionsOf("b"), [])
        XCTAssertEqual(form.toGrants(), [InviteGrant(propertyId: "b", permissions: [])])
    }

    func testCreateWithUnknownCurrentHouseSelectsNothing() {
        let form = InviteForm.create(order: order, currentId: "zzz")
        XCTAssertFalse(form.canSubmit)
        XCTAssertEqual(form.toGrants(), [])
    }

    func testToGrantsIgnoresUnselectedHousesAndFollowsTheListOrder() {
        let form = InviteForm.create(order: order, currentId: "c")
            .withProperty("a", selected: true)
            .withPermission("a", .finance, enabled: true)
            .withPermission("c", .site, enabled: true)
            .withPermission("c", .prices, enabled: true)
        XCTAssertEqual(form.toGrants(), [
            InviteGrant(propertyId: "a", permissions: [.finance]),
            InviteGrant(propertyId: "c", permissions: [.prices, .site]),
        ])
    }

    func testPermissionsOfAnUnselectedHouseAreIgnoredAndDroppedOnDeselect() {
        let form = InviteForm.create(order: order, currentId: "a").withPermission("b", .finance, enabled: true)
        XCTAssertFalse(form.isSelected("b"))
        XCTAssertEqual(form.permissionsOf("b"), [])
        let again = form.withPermission("a", .site, enabled: true).withProperty("a", selected: false).withProperty("a", selected: true)
        XCTAssertEqual(again.permissionsOf("a"), [])
    }

    func testPermissionCanBeTurnedOffAgain() {
        let form = InviteForm.create(order: order, currentId: "a")
            .withPermission("a", .site, enabled: true).withPermission("a", .site, enabled: false)
        XCTAssertEqual(form.permissionsOf("a"), [])
    }

    func testCanSubmitNeedsAtLeastOneHouse() {
        let form = InviteForm.create(order: order, currentId: "a")
        XCTAssertTrue(form.canSubmit)
        let empty = form.withProperty("a", selected: false)
        XCTAssertFalse(empty.canSubmit)
        XCTAssertEqual(empty.problem, "Scegli almeno una casa")
        XCTAssertNil(form.problem)
    }

    func testShareTextListsHousesPermissionsLinkCodeAndExpiry() {
        let text = InviteText.shareText(
            [InviteShareItem(propertyName: "Casa Mare", permissions: [.finance, .prices]),
             InviteShareItem(propertyName: "Casa Sole", permissions: [])],
            link: "siciliahost://invito/ABCD2345", code: "ABCD2345", expiryDate: "21/10/2026"
        )
        XCTAssertTrue(text.contains("Casa Mare: Finanze, Prezzi e calendario"))
        XCTAssertTrue(text.contains("Casa Sole: solo gestione base"))
        XCTAssertTrue(text.contains("siciliahost://invito/ABCD2345"))
        XCTAssertTrue(text.contains("inserisci: ABCD2345"))
        XCTAssertTrue(text.contains("21/10/2026"))
    }

    func testShareItemsUseHouseNamesInGrantOrder() {
        let items = InviteText.shareItems(
            [InviteGrant(propertyId: "b", permissions: [.site]), InviteGrant(propertyId: "a", permissions: [])],
            namesById: ["a": "Casa A", "b": "Casa B"]
        )
        XCTAssertEqual(items, [InviteShareItem(propertyName: "Casa B", permissions: [.site]),
                               InviteShareItem(propertyName: "Casa A", permissions: [])])
    }

    // MARK: InviteFormatTest

    func testInviteFormat() {
        XCTAssertEqual(InviteText.permissionsText([]), "Solo gestione base")
        XCTAssertEqual(InviteText.permissionsText([.prices, .finance]), "Gestione base + Finanze, Prezzi e calendario")
        XCTAssertEqual(InviteText.permissionsText([.site]), "Gestione base + Contenuti del sito")
        XCTAssertEqual(InviteText.headline("mario@x.it"), "mario@x.it ti invita a collaborare")
        XCTAssertEqual(InviteText.headline("   "), "Un proprietario ti invita a collaborare")
        for word in ["prenotazioni", "scorte", "check-in", "Alloggiati"] {
            XCTAssertTrue(InviteText.baseManagementNote.contains(word))
        }
    }
}

// MARK: InviteViewModelTest

private struct FakeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class FakeInviteAPI: InviteAPI {
    var preview: InvitePreview?
    var failure: String?
    var calls: [String] = []

    init(preview: InvitePreview? = nil, failure: String? = nil) {
        self.preview = preview
        self.failure = failure
    }

    func getInvite(code: String) async throws -> InvitePreview {
        calls.append("get:\(code)")
        if let failure { throw FakeError(message: failure) }
        return preview!
    }

    func declineInvite(code: String) async throws {
        calls.append("decline:\(code)")
        if let failure { throw FakeError(message: failure) }
    }

    func redeemInvite(code: String) async throws -> [String] {
        calls.append("redeem:\(code)")
        if let failure { throw FakeError(message: failure) }
        return ["p1"]
    }
}

@MainActor
final class InviteModelTests: XCTestCase {
    private let preview = InvitePreview(
        code: "ABCD2345", expiresAt: 1_800_000_000_000, inviterEmail: "mario@x.it",
        grants: [InvitePreviewGrant(propertyId: "p1", propertyName: "Casa Mare", permissions: [.finance])]
    )
    private var pending: PendingInvite!

    override func setUp() async throws {
        pending = PendingInvite()
        pending.set("ABCD2345")
    }

    private func model(_ api: FakeInviteAPI) -> InviteModel { InviteModel(code: "ABCD2345", api: api, pending: pending) }

    func testStartLoadsPreviewOnce() async {
        let api = FakeInviteAPI(preview: preview)
        let m = model(api)
        XCTAssertEqual(m.state, .loading)
        await m.start()
        await m.start()
        XCTAssertEqual(m.state, .preview(preview))
        XCTAssertEqual(api.calls, ["get:ABCD2345"])
    }

    func testExpiredInviteShowsMessageAndStaysUntilClosed() async {
        let m = model(FakeInviteAPI(failure: "Invito scaduto"))
        await m.start()
        XCTAssertEqual(m.state, .error("Invito scaduto"))
        XCTAssertEqual(pending.code, "ABCD2345")
        m.close()
        XCTAssertNil(pending.code)
    }

    func testAcceptRedeemsClearsHolderAndSignalsReload() async {
        let api = FakeInviteAPI(preview: preview)
        let m = model(api)
        await m.start()
        await m.accept()
        XCTAssertTrue(api.calls.contains("redeem:ABCD2345"))
        XCTAssertNil(pending.code)
        XCTAssertEqual(pending.accepted, 1)
    }

    func testDeclineClearsHolderWithoutReload() async {
        let api = FakeInviteAPI(preview: preview)
        let m = model(api)
        await m.start()
        await m.decline()
        XCTAssertTrue(api.calls.contains("decline:ABCD2345"))
        XCTAssertNil(pending.code)
        XCTAssertEqual(pending.accepted, 0)
    }

    func testAcceptFailureKeepsHolderAndShowsError() async {
        let api = FakeInviteAPI(preview: preview)
        let m = model(api)
        await m.start()
        api.failure = "Fai già parte di queste case"
        await m.accept()
        XCTAssertEqual(m.state, .error("Fai già parte di queste case"))
        XCTAssertEqual(pending.code, "ABCD2345")
        XCTAssertEqual(pending.accepted, 0)
    }

    func testAcceptBeforePreviewIsIgnored() async {
        let api = FakeInviteAPI(preview: preview)
        await model(api).accept()
        XCTAssertTrue(api.calls.isEmpty)
    }

    func testAfterCloseStartReloadsFresh() async {
        let api = FakeInviteAPI(failure: "Invito scaduto")
        let m = model(api)
        await m.start()
        m.close()
        api.failure = nil
        api.preview = preview
        await m.start()
        XCTAssertEqual(m.state, .preview(preview))
    }
}
