import XCTest
@testable import SiciliaHost

final class AssistantTests: XCTestCase {
    private let proposalDict: [String: Any] = [
        "id": "pr1",
        "tool": "propose_block_dates",
        "propertyId": "p1",
        "summary": "Chiudi dal 20 al 25 agosto",
        "warnings": ["Si sovrappone a Rossi"],
        "expiresAt": 1_800_000_000_000,
    ]

    func testParsesMessageResultWithProposals() throws {
        let payload: [String: Any] = [
            "conversationId": "c1",
            "reply": "Ho preparato la proposta.",
            "proposals": [proposalDict],
            "remainingToday": 29
        ]
        let result = try XCTUnwrap(parseMessageResult(payload))
        XCTAssertEqual(result.conversationId, "c1")
        XCTAssertEqual(result.reply, "Ho preparato la proposta.")
        XCTAssertEqual(result.remainingToday, 29)
        XCTAssertEqual(result.proposals.count, 1)
        XCTAssertEqual(result.proposals[0].id, "pr1")
        XCTAssertEqual(result.proposals[0].warnings, ["Si sovrappone a Rossi"])
        XCTAssertEqual(result.proposals[0].expiresAt, 1_800_000_000_000)
    }

    func testParsesChangesPlanAndReasonOnProposal() throws {
        var richProposal = proposalDict
        richProposal["reason"] = "L'ospite ha chiesto uno sconto"
        richProposal["changes"] = [
            ["key": "price.base", "label": "Prezzo a notte", "before": "100 €", "after": "120 €"],
            ["key": "text.description.it", "label": "Descrizione (IT)", "before": NSNull(), "after": "Testo lungo", "long": true]
        ]
        richProposal["plan"] = [
            [
                "section": "prices",
                "propertyId": "p1",
                "keys": ["price.base"]
            ]
        ]

        let payload: [String: Any] = [
            "conversationId": "c1",
            "reply": "Ecco.",
            "proposals": [richProposal],
            "remainingToday": 20
        ]

        let result = try XCTUnwrap(parseMessageResult(payload))
        let parsed = result.proposals[0]
        XCTAssertEqual(parsed.reason, "L'ospite ha chiesto uno sconto")
        XCTAssertEqual(parsed.changes, [
            Change(key: "price.base", label: "Prezzo a notte", before: "100 €", after: "120 €", long: false),
            Change(key: "text.description.it", label: "Descrizione (IT)", before: nil, after: "Testo lungo", long: true)
        ])
        XCTAssertEqual(parsed.plan, [
            LiveStep(section: .prices, propertyId: "p1", keys: ["price.base"])
        ])

        // Una voce malformata in changes o plan scarta l'intero blocco ma lascia valida la proposta
        var broken = proposalDict
        broken["changes"] = [["key": "price.base", "label": "", "before": "a", "after": "b"]]
        broken["plan"] = [["section": "unknown_section", "propertyId": "p1", "keys": [String]()]]

        let parsedBroken = try XCTUnwrap(parseProposal(broken))
        XCTAssertNil(parsedBroken.changes)
        XCTAssertNil(parsedBroken.plan)
    }

    func testAcceptsResultWithoutProposals() throws {
        let payload: [String: Any] = [
            "conversationId": "c1",
            "reply": "Ciao",
            "proposals": [Any](),
            "remainingToday": 3
        ]
        let result = try XCTUnwrap(parseMessageResult(payload))
        XCTAssertEqual(result.proposals.count, 0)
    }

    func testSkipsMalformedProposal() throws {
        let payload: [String: Any] = [
            "conversationId": "c1",
            "reply": "Ok",
            "proposals": [["id": 5], proposalDict],
            "remainingToday": 3
        ]
        let result = try XCTUnwrap(parseMessageResult(payload))
        XCTAssertEqual(result.proposals.map(\.id), ["pr1"])
    }

    func testRejectsNonResults() {
        XCTAssertNil(parseMessageResult(nil))
        XCTAssertNil(parseMessageResult("ciao"))
        XCTAssertNil(parseMessageResult(["reply": "Ciao", "remainingToday": 3]))
        XCTAssertNil(parseMessageResult(["conversationId": "c1", "remainingToday": 3]))
        XCTAssertNil(parseMessageResult(["conversationId": "c1", "reply": "Ciao"]))
    }

    func testChatErrorMapping() {
        XCTAssertEqual(chatErrorOf(code: "permission-denied", reason: "not-host"), .notHost)
        XCTAssertEqual(chatErrorOf(code: "permission-denied", reason: nil), .denied)
        XCTAssertEqual(chatErrorOf(code: "unauthenticated", reason: nil), .denied)
        XCTAssertEqual(chatErrorOf(code: "not-found", reason: nil), .notFound)
        XCTAssertEqual(chatErrorOf(code: "unavailable", reason: "disabled"), .disabled)
        XCTAssertEqual(chatErrorOf(code: "unavailable", reason: nil), .model)
        XCTAssertEqual(chatErrorOf(code: "resource-exhausted", reason: "conversation-full"), .full)
        XCTAssertEqual(chatErrorOf(code: "resource-exhausted", reason: "other"), .quota)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "consent"), .consent)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "terms-version"), .termsVersion)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "expired"), .expired)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "already"), .already)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "execute-failed"), .executeFailed)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "stale"), .stale)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "undo-expired"), .undoExpired)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "not-undoable"), .notUndoable)
        XCTAssertEqual(chatErrorOf(code: "failed-precondition", reason: "partial"), .partial)
        XCTAssertEqual(chatErrorOf(code: "unknown", reason: nil), .generic)
    }

    func testValidateDraft() {
        XCTAssertEqual(validateDraft(""), .empty)
        XCTAssertEqual(validateDraft("   \n\t "), .empty)
        XCTAssertNil(validateDraft("Ciao Cactus"))
        let longText = String(repeating: "a", count: 4001)
        XCTAssertEqual(validateDraft(longText), .tooLong)
    }

    func testSpeechText() {
        let markdown = "*Ciao* **mondo** `test` # Titolo > citazione\n- punto 1\n• punto 2"
        let clean = speechText(markdown)
        XCTAssertEqual(clean, "Ciao mondo test Titolo citazione punto 1 punto 2")
    }

    func testTruncateText() {
        let short = "Testo corto"
        XCTAssertEqual(truncateText(short, max: 20), TruncatedText(short: "Testo corto", truncated: false))

        let long = "Questo è un testo abbastanza lungo da richiedere un troncamento ragionevole"
        let truncated = truncateText(long, max: 25)
        XCTAssertTrue(truncated.truncated)
        XCTAssertTrue(truncated.short.hasSuffix("…"))
    }

    func testFormatCountdown() {
        XCTAssertEqual(formatCountdown(ms: 600_000), "10:00")
        XCTAssertEqual(formatCountdown(ms: 581_000), "9:41")
        XCTAssertEqual(formatCountdown(ms: 5_000), "0:05")
        XCTAssertEqual(formatCountdown(ms: 0), "0:00")
        XCTAssertEqual(formatCountdown(ms: -1_000), "0:00")
    }

    func testBuildMessagePayload() {
        let payload = buildMessagePayload(
            text: "Ciao",
            conversationId: "conv123",
            locale: "it",
            propertyId: "prop1",
            selection: ["opt1", "opt2"]
        )
        XCTAssertEqual(payload["message"] as? String, "Ciao")
        XCTAssertEqual(payload["conversationId"] as? String, "conv123")
        XCTAssertEqual(payload["locale"] as? String, "it")
        XCTAssertEqual(payload["propertyId"] as? String, "prop1")
        XCTAssertEqual(payload["supportsWidgets"] as? Bool, true)
        let sel = payload["selection"] as? [String: Any]
        XCTAssertEqual(sel?["ids"] as? [String], ["opt1", "opt2"])
    }

    func testParseConfirmAndUndoResult() {
        let confirmPayload: [String: Any] = [
            "summary": "Prezzo aggiornato",
            "changes": [
                ["key": "price", "label": "Prezzo", "before": "100", "after": "120", "long": false]
            ],
            "undoUntil": 1_800_000_000_000
        ]
        let confirm = parseConfirmResult(confirmPayload)
        XCTAssertEqual(confirm.summary, "Prezzo aggiornato")
        XCTAssertEqual(confirm.changes.count, 1)
        XCTAssertEqual(confirm.undoUntil, 1_800_000_000_000)

        let undoPayload: [String: Any] = [
            "summary": "Prezzo ripristinato",
            "changes": [
                ["key": "price", "label": "Prezzo", "before": "120", "after": "100", "long": false]
            ]
        ]
        let undo = parseUndoResult(undoPayload)
        XCTAssertEqual(undo.summary, "Prezzo ripristinato")
        XCTAssertEqual(undo.changes.count, 1)
    }
}
