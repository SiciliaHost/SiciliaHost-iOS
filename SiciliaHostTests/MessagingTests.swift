import XCTest
@testable import SiciliaHost

// Specifica: MessagingRepositoryTest, MessagesFormatTest e il caso Messaggi di MainTabsTest dell'app Android.
final class MessagingTests: XCTestCase {
    private let conversation: [String: Any] = [
        "id": "p1__g1",
        "propertyId": "p1",
        "propertyTitle": ["it": "Casa Mare", "en": "Sea House"],
        "guestName": "Anna",
        "guestEmail": NSNull(),
        "request": ["checkIn": "2026-12-01", "checkOut": "2026-12-04", "guests": 2],
        "booking": ["id": "b1", "status": "confirmed", "checkIn": "2026-12-10", "checkOut": "2026-12-12",
                    "guests": NSNull(), "totalPrice": 400, "depositAmount": 120.5] as [String: Any],
        "hostContact": NSNull(),
        "lastMessage": ["text": "Ciao", "from": "guest", "at": 1_700_000_000_000] as [String: Any],
        "unread": true,
        "updatedAt": 1_700_000_000_000,
    ]

    func testParsesAConversationWithBookingAndRequest() throws {
        let c = try XCTUnwrap(parseConversation(conversation))
        XCTAssertEqual(c.propertyName, "Casa Mare")
        XCTAssertEqual(c.request, StayRequest(checkIn: "2026-12-01", checkOut: "2026-12-04", guests: 2))
        XCTAssertEqual(c.booking?.status, "confirmed")
        XCTAssertEqual(c.booking?.totalPrice, 400)
        XCTAssertTrue(c.unread)
        XCTAssertEqual(c.lastMessage?.text, "Ciao")
        // La prenotazione vince sulla richiesta; gli ospiti mancanti si prendono dalla richiesta.
        XCTAssertEqual(c.stay, StayRequest(checkIn: "2026-12-10", checkOut: "2026-12-12", guests: 2))
    }

    func testSkipsMalformedRowsAndReadsTheDetail() throws {
        let list = parseConversations(["conversations": [conversation, ["id": "x"], "junk"]] as [String: Any])
        XCTAssertEqual(list.map(\.id), ["p1__g1"])
        let detail = try XCTUnwrap(parseConversationDetail([
            "conversation": conversation,
            "messages": [
                ["id": "m1", "from": "guest", "text": "Ciao", "at": 5,
                 "context": ["checkIn": "2026-12-01", "checkOut": "2026-12-04", "guests": 2]] as [String: Any],
                ["id": "m2", "from": "host", "text": "Salve", "at": 6, "context": NSNull()] as [String: Any],
            ],
        ] as [String: Any]))
        XCTAssertEqual(detail.messages.count, 2)
        XCTAssertEqual(detail.messages[0].context?.guests, 2)
        XCTAssertNil(detail.messages[1].context)
        XCTAssertNil(parseConversationDetail(["messages": [Any]()] as [String: Any]))
    }

    func testReadsTheStatusAndTheContacts() {
        let status = parseMessagingStatus(["host": ["enabled": true, "unread": 3], "guest": ["enabled": true]] as [String: Any])
        XCTAssertTrue(status.hostEnabled)
        XCTAssertEqual(status.hostUnread, 3)
        XCTAssertFalse(parseMessagingStatus(nil).hostEnabled)
        XCTAssertEqual(parseContactDetails(["phone": "333", "whatsapp": NSNull()] as [String: Any])?.phone, "333")
        XCTAssertNil(parseContactDetails(nil))
    }

    func testMergesPolledMessagesWithoutDuplicates() {
        let a = ChatMessage(id: "a", from: "guest", text: "a", at: 1)
        let b = ChatMessage(id: "b", from: "host", text: "b", at: 3)
        let c = ChatMessage(id: "c", from: "guest", text: "c", at: 2)
        XCTAssertEqual(mergeMessages([a, b], [b, c]).map(\.id), ["a", "c", "b"])
    }

    func testValidatesPhonesLikeTheServer() {
        XCTAssertTrue(isValidPhone("333 123 4567"))
        XCTAssertTrue(isValidPhone("+44 20 7946 0958"))
        XCTAssertTrue(isValidPhone(""))
        XCTAssertFalse(isValidPhone("chiamami"))
        XCTAssertFalse(isValidPhone("12"))
    }

    func testDescribesTheStay() {
        XCTAssertEqual(MessagesFormat.stayLine(StayRequest(checkIn: "2026-12-01", checkOut: "2026-12-04", guests: 2)),
                       "1 dic 2026 → 4 dic 2026 · 3 notti · 2 ospiti")
        XCTAssertEqual(MessagesFormat.stayLine(StayRequest(checkIn: "2026-12-01", checkOut: "2026-12-02", guests: 1), long: false),
                       "1 dic → 2 dic · 1 notte · 1 ospite")
        XCTAssertEqual(MessagesFormat.stayLine(StayRequest(guests: 3)), "3 ospiti")
        XCTAssertEqual(MessagesFormat.stayLine(StayRequest()), "Date non indicate")
        // Una data impossibile non si inventa: resta com'è, senza notti.
        XCTAssertEqual(MessagesFormat.shortDate("2026-02-30"), "2026-02-30")
    }

    func testLabelsTheBookingStatus() {
        XCTAssertEqual(MessagesFormat.statusLabel(nil), "Richiesta")
        XCTAssertEqual(MessagesFormat.statusLabel("confirmed"), "Confermata")
        XCTAssertEqual(MessagesFormat.statusLabel("pending_payment"), "Caparra in attesa")
    }

    func testGroupsMessagesByRomeDay() {
        // 22:30 e 23:30 UTC del 3 novembre = 23:30 del 3 e 00:30 del 4 a Roma.
        let first: Int64 = 1_762_209_000_000
        let second = first + 3_600_000
        let groups = MessagesFormat.groupByDay([
            ChatMessage(id: "a", from: "guest", text: "", at: first),
            ChatMessage(id: "b", from: "host", text: "", at: second),
        ])
        XCTAssertEqual(groups.map(\.day), ["2025-11-03", "2025-11-04"])
        XCTAssertEqual(MessagesFormat.time(first), "23:30")
        XCTAssertEqual(MessagesFormat.dayLabel(second, now: second + 1000), "Oggi")
        XCTAssertEqual(MessagesFormat.dayLabel(first, now: first + millisPerDay), "Ieri")
        XCTAssertEqual(MessagesFormat.dayLabel(first, now: first + 5 * millisPerDay), "3 novembre 2025")
        XCTAssertEqual(MessagesFormat.listTime(first, now: first + 1000), "23:30")
        XCTAssertEqual(MessagesFormat.listTime(first, now: first + 5 * millisPerDay), "3 nov")
    }

    func testMessagesTabOnlyWhenTheServerEnablesIt() {
        let house = Property(id: "a", name: "A", members: ["u": "OWNER"], memberUids: ["u"])
        let scope = AccessScope(uid: "u", isSuperAdmin: false, properties: [house])
        XCTAssertFalse(MainTabs.visible(for: scope).contains(.messaggi))
        XCTAssertEqual(MainTabs.visible(for: scope, messagingEnabled: true)[3], .messaggi)
        // Senza case caricate niente Messaggi, anche se il server lo permetterebbe.
        XCTAssertEqual(MainTabs.visible(for: nil, messagingEnabled: true), [.home, .agenda, .scorte])
    }
}
