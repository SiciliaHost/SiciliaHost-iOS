import XCTest
@testable import SiciliaHost

// Specifica: IntroLogicTest, TourLogicTest, PendingInviteTest, AccessStateTest, MainTabsTest dell'app Android.
final class OnboardingTests: XCTestCase {
    // MARK: Presentazione

    func testBeforeLoginOnlyTheDeviceCounts() {
        XCTAssertTrue(shouldShowIntro(signedIn: false, deviceSeen: false, accountSeen: nil, shownThisRun: false))
        XCTAssertFalse(shouldShowIntro(signedIn: false, deviceSeen: true, accountSeen: false, shownThisRun: false))
    }

    func testAfterLoginTheAccountCounts() {
        XCTAssertTrue(shouldShowIntro(signedIn: true, deviceSeen: true, accountSeen: false, shownThisRun: false))
        XCTAssertFalse(shouldShowIntro(signedIn: true, deviceSeen: false, accountSeen: true, shownThisRun: false))
    }

    func testNotBeforeTheProfileIsLoadedAndNotTwiceInARow() {
        XCTAssertFalse(shouldShowIntro(signedIn: true, deviceSeen: false, accountSeen: nil, shownThisRun: false))
        XCTAssertFalse(shouldShowIntro(signedIn: true, deviceSeen: true, accountSeen: false, shownThisRun: true))
    }

    func testIntroPrefsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test-intro-\(UUID().uuidString)"))
        XCTAssertFalse(IntroPrefs.introSeen(defaults))
        IntroPrefs.markIntroSeen(defaults)
        XCTAssertTrue(IntroPrefs.introSeen(defaults))
    }

    // MARK: Tour

    private let allTabs = ["Home", "Agenda", "Scorte", "Finanze", "Case"]

    func testOwnerSeesEveryStepInOrder() {
        let targets = tourSteps(visibleTabs: allTabs, canManageAHouse: true, canEditPrices: true).map(\.target)
        XCTAssertEqual(targets, TourTarget.allCases)
    }

    func testHiddenTabsAreSkipped() {
        let targets = tourSteps(visibleTabs: ["Home", "Agenda", "Scorte"], canManageAHouse: false, canEditPrices: true).map(\.target)
        XCTAssertEqual(targets, [.navBar, .homeReview, .agendaPrices, .scorteScan, .profile])
    }

    func testBookingImportNeedsAManagedHouse() {
        let targets = tourSteps(visibleTabs: allTabs, canManageAHouse: false, canEditPrices: true).map(\.target)
        XCTAssertFalse(targets.contains(.caseBookingImport))
    }

    func testPricesStepIsSkippedWithoutAnApprovedListing() {
        let targets = tourSteps(visibleTabs: allTabs, canManageAHouse: true, canEditPrices: false).map(\.target)
        XCTAssertFalse(targets.contains(.agendaPrices))
        XCTAssertTrue(targets.contains(.scorteScan))
    }

    @MainActor
    func testTourStateWalksThroughTheStepsAndStops() {
        let state = TourState()
        XCTAssertFalse(state.isActive)
        state.start(tourSteps(visibleTabs: allTabs, canManageAHouse: true, canEditPrices: true))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.current?.target, .navBar)
        while !state.isLast { state.next() }
        XCTAssertEqual(state.current?.target, .profile)
        state.next() // l'ultimo "Avanti" chiude il tour
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.current)
    }

    // MARK: Invito in sospeso

    @MainActor
    func testPendingInviteSetClearAndAccepted() {
        let pending = PendingInvite()
        XCTAssertNil(pending.code)
        pending.set("ABCD2345")
        XCTAssertEqual(pending.code, "ABCD2345")
        pending.clear()
        XCTAssertNil(pending.code)
        XCTAssertEqual(pending.accepted, 0)
        pending.notifyAccepted()
        pending.notifyAccepted()
        XCTAssertEqual(pending.accepted, 2)
    }

    // MARK: Accesso e sezioni (già in AccessScopeTests, qui i casi aggiunti con i permessi sul prezzo)

    func testCanEditPricesNeedsAnApprovedListingOnAPriceHouse() {
        let house = Property(id: "a", members: ["u": "OWNER"], memberUids: ["u"])
        let scope = AccessScope(uid: "u", isSuperAdmin: false, properties: [house])
        XCTAssertTrue(MainTabs.canEditPrices(scope, approvedIds: ["a"]))
        XCTAssertFalse(MainTabs.canEditPrices(scope, approvedIds: ["b"]))
        XCTAssertFalse(MainTabs.canEditPrices(nil, approvedIds: ["a"]))
    }

    // MARK: Stile

    func testTypographyScaleMatchesTheCompactAndroidScale() {
        XCTAssertEqual(AppTextStyle.displaySmall.spec, AppTextStyle.Spec(size: 26, lineHeight: 30, weight: .black, tracking: -0.5))
        XCTAssertEqual(AppTextStyle.bodyMedium.spec.size, 13)
        XCTAssertEqual(AppTextStyle.labelSmall.spec, AppTextStyle.Spec(size: 10, lineHeight: 13, weight: .bold, tracking: 1.2))
        XCTAssertEqual(AppTextStyle.allCases.count, 13)
    }

    func testBrandColorsAreTheFixedLogoColors() {
        XCTAssertEqual(Brand.green, 0x3C9650)
        XCTAssertEqual(Brand.yellow, 0xF0C607)
        XCTAssertEqual(Brand.red, 0xB7332D)
        XCTAssertEqual(Brand.ink, 0x151515)
    }

    // MARK: Accesso con Apple

    func testAppleNonceIsRandomAndHashedAsSha256() {
        let a = AppleNonce.random(), b = AppleNonce.random()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(AppleNonce.random(length: 10).count, 10)
        // SHA-256 di "abc" (vettore di prova standard)
        XCTAssertEqual(AppleNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
