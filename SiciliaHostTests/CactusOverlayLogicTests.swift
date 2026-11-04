import XCTest
@testable import SiciliaHost

final class CactusOverlayLogicTests: XCTestCase {
    func testAvatarStatePrecedence() {
        // Errore ha precedenza massima
        XCTAssertEqual(avatarStateOf(busy: true, speaking: true, typing: true, listening: true, errorFlash: true, working: true), .error)
        // Working (Live Staging) vince su listening/busy
        XCTAssertEqual(avatarStateOf(busy: true, speaking: true, typing: false, listening: true, errorFlash: false, working: true), .working)
        // Listening vince su busy
        XCTAssertEqual(avatarStateOf(busy: true, speaking: false, typing: false, listening: true, errorFlash: false, working: false), .listening)
        // Busy (thinking) vince su speaking
        XCTAssertEqual(avatarStateOf(busy: true, speaking: true, typing: false, listening: false, errorFlash: false, working: false), .thinking)
        // Speaking o typing
        XCTAssertEqual(avatarStateOf(busy: false, speaking: true, typing: false, listening: false, errorFlash: false, working: false), .speaking)
        XCTAssertEqual(avatarStateOf(busy: false, speaking: false, typing: true, listening: false, errorFlash: false, working: false), .speaking)
        // Idle
        XCTAssertEqual(avatarStateOf(busy: false, speaking: false, typing: false, listening: false, errorFlash: false, working: false), .idle)
    }

    func testBubbleSlots() {
        let m1 = AssistantChatMessage(id: 1, role: .user, text: "Domanda 1")
        let m2 = AssistantChatMessage(id: 2, role: .assistant, text: "Risposta 1")
        let m3 = AssistantChatMessage(id: 3, role: .user, text: "Domanda 2")
        let m4 = AssistantChatMessage(id: 4, role: .assistant, text: "Risposta 2")
        let m5 = AssistantChatMessage(id: 5, role: .user, text: "Domanda 3")

        let slots = bubbleSlots(messages: [m1, m2, m3, m4, m5])
        XCTAssertEqual(slots.count, 4) // previous (m2), ask (m3), current (m4), ask (m5)
        XCTAssertEqual(slots[0].kind, .previous)
        XCTAssertEqual(slots[0].message.id, 2)
        XCTAssertEqual(slots[1].kind, .ask)
        XCTAssertEqual(slots[1].message.id, 3)
        XCTAssertEqual(slots[2].kind, .current)
        XCTAssertEqual(slots[2].message.id, 4)
        XCTAssertEqual(slots[3].kind, .ask)
        XCTAssertEqual(slots[3].message.id, 5)
    }

    func testCardsMessageId() {
        let m1 = AssistantChatMessage(id: 1, role: .assistant, text: "Testo senza carte")
        let m2 = AssistantChatMessage(id: 2, role: .assistant, text: "Testo con widget", widgets: [.summary(SummaryWidget(id: "s1", title: "T", rows: []))])
        let m3 = AssistantChatMessage(id: 3, role: .user, text: "Domanda utente")

        XCTAssertEqual(cardsMessageId(messages: [m1, m2, m3]), 2)
        XCTAssertNil(cardsMessageId(messages: [m1, m3]))
    }

    func testTypewriterLogic() {
        let len = 100
        let total = typewriterDurationMs(length: len)
        XCTAssertTrue(total > 0 && total <= 3_000)

        XCTAssertEqual(typedChars(elapsedMs: 0, length: len), 0)
        XCTAssertEqual(typedChars(elapsedMs: total / 2, length: len), 50)
        XCTAssertEqual(typedChars(elapsedMs: total * 2, length: len), len)

        let str = "Buongiorno Cactus!"
        XCTAssertEqual(typedPrefix(text: str, n: 0), "")
        XCTAssertEqual(typedPrefix(text: str, n: 10), "Buongiorno")
        XCTAssertEqual(typedPrefix(text: str, n: 50), "Buongiorno Cactus!")
    }
}
