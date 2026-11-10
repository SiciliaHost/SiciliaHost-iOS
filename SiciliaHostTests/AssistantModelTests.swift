import XCTest
@testable import SiciliaHost

final class MockAssistantAPI: AssistantAPI, @unchecked Sendable {
    var statusResult: Bool = true
    var messageHandler: ((String, String?, String, String?, [String]?) async throws -> MessageResult)?
    var confirmHandler: ((String) async throws -> ConfirmResult)?
    var undoHandler: ((String) async throws -> UndoResult)?
    var acceptTermsHandler: ((String) async throws -> Void)?
    var declineHandler: ((String) async throws -> Void)?
    var deleteConversationCalled = false

    func status() async throws -> Bool {
        return statusResult
    }

    func message(
        text: String,
        conversationId: String?,
        locale: String,
        propertyId: String?,
        selection: [String]?
    ) async throws -> MessageResult {
        if let handler = messageHandler {
            return try await handler(text, conversationId, locale, propertyId, selection)
        }
        return MessageResult(conversationId: "c1", reply: "Risposta: \(text)", remainingToday: 20)
    }

    func confirm(proposalId: String) async throws -> ConfirmResult {
        if let handler = confirmHandler {
            return try await handler(proposalId)
        }
        return ConfirmResult(summary: "Confermato \(proposalId)", undoUntil: 1_800_000_000_000)
    }

    func undo(proposalId: String) async throws -> UndoResult {
        if let handler = undoHandler {
            return try await handler(proposalId)
        }
        return UndoResult(summary: "Annullato \(proposalId)")
    }

    func decline(proposalId: String) async throws {
        try await declineHandler?(proposalId)
    }

    func acceptTerms(version: String) async throws {
        try await acceptTermsHandler?(version)
    }

    func deleteConversation(conversationId: String) async throws {
        deleteConversationCalled = true
    }
}

final class AssistantModelTests: XCTestCase {
    func testShowFloatingAssistant() {
        XCTAssertFalse(showFloatingAssistant(available: false, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: nil))
        XCTAssertFalse(showFloatingAssistant(available: true, open: true, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: nil))
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: true, isKeyboardShowing: false, mainReady: true, route: nil))
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: true, mainReady: true, route: nil))

        // Con navbar nascosta e assistente disponibile
        XCTAssertTrue(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: nil))
        XCTAssertTrue(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .houseAccess(propertyId: "p1")))
        XCTAssertTrue(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .members(propertyId: nil)))

        // Impostazioni e sottomenù Collaboratori: mai flottante
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .profile))
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .collaborators))

        // Su schermate escluse (form / scanner)
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .mrzScan(reservationId: "r1", propertyId: "p1")))
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .newCaseWizard(propertyId: nil, level: .app)))
        XCTAssertFalse(showFloatingAssistant(available: true, open: false, navbarVisible: false, isKeyboardShowing: false, mainReady: true, route: .checkin(reservationId: "r1", propertyId: "p1")))
    }

    @MainActor
    func testSendAndReceiveMessage() async {
        let mock = MockAssistantAPI()
        let model = AssistantModel(api: mock)

        let exp = expectation(description: "Message processed")
        mock.messageHandler = { text, _, _, _, _ in
            return MessageResult(
                conversationId: "conv_1",
                reply: "Ciao host!",
                proposals: [
                    ProposalRef(id: "pr1", tool: "tool1", propertyId: "p1", summary: "Modifica", expiresAt: 1_000)
                ],
                remainingToday: 15
            )
        }

        model.send(text: "Ciao")
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages[0].role, .user)
        XCTAssertTrue(model.busy)

        // Attende che l'invio asincrono finisca
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(model.busy)
            XCTAssertEqual(model.messages.count, 2)
            XCTAssertEqual(model.messages[1].role, .assistant)
            XCTAssertEqual(model.messages[1].text, "Ciao host!")
            XCTAssertEqual(model.messages[1].proposals.count, 1)
            XCTAssertEqual(model.remaining, 15)
            XCTAssertEqual(model.conversationId, "conv_1")
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }

    @MainActor
    func testConsentFlow() async {
        let mock = MockAssistantAPI()
        let model = AssistantModel(api: mock)

        var consentAsked = false
        mock.messageHandler = { text, _, _, _, _ in
            if !consentAsked {
                consentAsked = true
                throw AssistantException(error: .consent, consentVersion: "v2")
            } else {
                return MessageResult(conversationId: "c1", reply: "Consenso ok, risposta inviata!", remainingToday: 20)
            }
        }

        let exp = expectation(description: "Consent handled")

        model.send(text: "Richiesta con consenso")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(model.consent)
            XCTAssertEqual(model.consent?.version, "v2")
            XCTAssertEqual(model.pendingSend?.text, "Richiesta con consenso")

            // Host accetta il consenso
            model.acceptConsent()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertNil(model.consent)
                XCTAssertEqual(model.messages.last?.text, "Consenso ok, risposta inviata!")
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }

    @MainActor
    func testProposalConfirmAndUndo() async {
        let mock = MockAssistantAPI()
        let model = AssistantModel(api: mock)

        let prop = ProposalRef(
            id: "p_100",
            tool: "change_price",
            propertyId: "prop1",
            summary: "Aumenta prezzo a 150 €",
            expiresAt: 1_900_000_000_000
        )
        let msg = AssistantChatMessage(
            id: 1,
            role: .assistant,
            text: "Ecco la modifica",
            proposals: [ProposalView(ref: prop)]
        )
        model.messages = [msg]

        let exp = expectation(description: "Confirm and Undo")

        model.confirm(proposalId: "p_100")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let pView = model.messages[0].proposals[0]
            XCTAssertEqual(pView.status, .done)
            XCTAssertEqual(pView.result, "Confermato p_100")
            XCTAssertNotNil(pView.undoUntil)

            // Esegue l'annullamento
            model.undo(proposalId: "p_100")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let undoneView = model.messages[0].proposals[0]
                XCTAssertEqual(undoneView.status, .undone)
                XCTAssertEqual(undoneView.result, "Annullato p_100")
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }

    @MainActor
    func testSyncHouses() {
        let model = AssistantModel()
        let p1 = Property(id: "h1", name: "Villa Mare")
        let p2 = Property(id: "h2", name: "Casa Etna")

        model.syncHouses([p1, p2])
        XCTAssertEqual(model.houses.count, 2)
        XCTAssertNil(model.propertyId)

        // Seleziona una casa
        model.setProperty("h1")
        XCTAssertEqual(model.propertyId, "h1")
        XCTAssertEqual(model.messages.last?.text, "Casa impostata: Villa Mare")

        // Se la casa sparisce e ne resta una sola
        model.syncHouses([p2])
        XCTAssertEqual(model.propertyId, "h2")
        XCTAssertEqual(model.messages.last?.text, "Casa impostata: Casa Etna")
    }
}
