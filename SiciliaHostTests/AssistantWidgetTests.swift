import XCTest
@testable import SiciliaHost

final class AssistantWidgetTests: XCTestCase {
    private func resultPayload(widgets: Any?) -> [String: Any] {
        return [
            "conversationId": "c1",
            "reply": "",
            "proposals": [Any](),
            "remainingToday": 5,
            "widgets": widgets as Any
        ]
    }

    func testResultWithoutWidgetsHasEmptyList() {
        let r1 = parseMessageResult(["conversationId": "c1", "reply": "Ciao", "remainingToday": 3])
        XCTAssertEqual(r1?.widgets.count, 0)

        let r2 = parseMessageResult(resultPayload(widgets: "non una lista"))
        XCTAssertEqual(r2?.widgets.count, 0)
    }

    func testEmptyReplyWithWidgetsIsValid() throws {
        let payload = resultPayload(widgets: [
            ["type": "quick_replies", "id": "w1", "options": [["label": "Sì", "text": "Sì, grazie"]]]
        ])
        let r = try XCTUnwrap(parseMessageResult(payload))
        XCTAssertEqual(r.reply, "")
        XCTAssertEqual(r.widgets.count, 1)
        if case .quickReplies(let qr) = r.widgets[0] {
            XCTAssertEqual(qr.id, "w1")
            XCTAssertEqual(qr.options, [QuickReply(label: "Sì", text: "Sì, grazie")])
        } else {
            XCTFail("Atteso widget quick_replies")
        }
    }

    func testParsesChoiceWidget() throws {
        let dict: [String: Any] = [
            "type": "choice",
            "id": "w1",
            "prompt": "Quale?",
            "multiple": true,
            "options": [
                ["id": "a", "label": "Rossi", "detail": "12-15 ago"],
                ["id": "b", "label": "Bianchi"]
            ]
        ]
        let w = try XCTUnwrap(parseWidget(dict))
        if case .choice(let choice) = w {
            XCTAssertEqual(choice.id, "w1")
            XCTAssertEqual(choice.prompt, "Quale?")
            XCTAssertTrue(choice.multiple)
            XCTAssertEqual(choice.options, [
                ChoiceOption(id: "a", label: "Rossi", detail: "12-15 ago"),
                ChoiceOption(id: "b", label: "Bianchi", detail: nil)
            ])
        } else {
            XCTFail("Atteso ChoiceWidget")
        }
    }

    func testParsesDatesWidget() throws {
        let dict: [String: Any] = [
            "type": "dates",
            "id": "w2",
            "prompt": "Quando?",
            "mode": "range",
            "min": "2026-08-01",
            "max": "2026-09-30",
            "disabled": [
                ["from": "2026-08-10", "to": "2026-08-12"]
            ]
        ]
        let w = try XCTUnwrap(parseWidget(dict))
        if case .dates(let dates) = w {
            XCTAssertEqual(dates.id, "w2")
            XCTAssertEqual(dates.prompt, "Quando?")
            XCTAssertEqual(dates.mode, .range)
            XCTAssertEqual(dates.min, "2026-08-01")
            XCTAssertEqual(dates.max, "2026-09-30")
            XCTAssertEqual(dates.disabled, [DateRange(from: "2026-08-10", to: "2026-08-12")])
        } else {
            XCTFail("Atteso DatesWidget")
        }
    }

    func testParsesSummaryAndAmountWidget() throws {
        let summaryDict: [String: Any] = [
            "type": "summary",
            "id": "w4",
            "title": "Agosto",
            "note": "Stima",
            "rows": [
                ["label": "Entrate", "value": "1.200 €", "emphasis": true],
                ["label": "Spese", "value": "300 €"]
            ]
        ]
        let s = try XCTUnwrap(parseWidget(summaryDict))
        if case .summary(let summary) = s {
            XCTAssertEqual(summary.id, "w4")
            XCTAssertEqual(summary.title, "Agosto")
            XCTAssertEqual(summary.note, "Stima")
            XCTAssertEqual(summary.rows, [
                SummaryRow(label: "Entrate", value: "1.200 €", emphasis: true),
                SummaryRow(label: "Spese", value: "300 €", emphasis: false)
            ])
        } else {
            XCTFail("Atteso SummaryWidget")
        }

        let amountDict: [String: Any] = [
            "type": "amount",
            "id": "w5",
            "prompt": "Quanto?",
            "kind": "euro",
            "suggestions": [50, 100.5],
            "min": 0,
            "max": 500,
            "defaultValue": 80,
            "unit": "€"
        ]
        let a = try XCTUnwrap(parseWidget(amountDict))
        if case .amount(let amount) = a {
            XCTAssertEqual(amount.id, "w5")
            XCTAssertEqual(amount.prompt, "Quanto?")
            XCTAssertEqual(amount.kind, .euro)
            XCTAssertEqual(amount.suggestions, [50.0, 100.5])
            XCTAssertEqual(amount.min, 0.0)
            XCTAssertEqual(amount.max, 500.0)
            XCTAssertEqual(amount.defaultValue, 80.0)
            XCTAssertEqual(amount.unit, "€")
        } else {
            XCTFail("Atteso AmountWidget")
        }
    }

    func testDropsMalformedWidgets() {
        let good: [String: Any] = [
            "type": "quick_replies",
            "id": "ok",
            "options": [["label": "A", "text": "a"]]
        ]
        let badList: [[String: Any]] = [
            ["type": "choice", "id": "w", "prompt": "p", "options": [Any]()],
            ["type": "choice", "id": "", "prompt": "p", "options": [["id": "a", "label": "A"]]],
            ["type": "dates", "id": "w", "prompt": "p", "mode": "invalid_mode"],
            ["type": "dates", "id": "w", "prompt": "p", "mode": "day", "min": "2026-02-30"],
            ["type": "summary", "id": "w", "title": "t", "rows": [["label": "a"]]],
            ["type": "amount", "id": "w", "prompt": "p", "kind": "dollari"],
            ["type": "sconosciuto", "id": "w"]
        ]
        for bad in badList {
            XCTAssertNil(parseWidget(bad))
        }

        var allWidgets: [Any] = badList
        allWidgets.append(good)
        let r = parseMessageResult(resultPayload(widgets: allWidgets))
        XCTAssertEqual(r?.widgets.map(\.id), ["ok"])
    }

    func testSanitizeSelection() {
        XCTAssertNil(sanitizeSelection(nil))
        XCTAssertNil(sanitizeSelection([]))
        XCTAssertNil(sanitizeSelection(["invalid id with spaces!", ""]))
        let valid = ["opt_1", "OPT-2", "123"]
        XCTAssertEqual(sanitizeSelection(valid), valid)
        let tooMany = (1...20).map { "id_\($0)" }
        XCTAssertEqual(sanitizeSelection(tooMany)?.count, 12)
    }

    func testActiveWidgetMessageId() {
        let msg1 = ChatMessage(id: 1, role: .assistant, text: "Scegli", widgets: [.choice(ChoiceWidget(id: "c1", prompt: "P", multiple: false, options: []))])
        let msg2 = ChatMessage(id: 2, role: .user, text: "Ho scelto")

        XCTAssertEqual(activeWidgetMessageId(messages: [msg1], blocked: false), 1)
        XCTAssertNil(activeWidgetMessageId(messages: [msg1], blocked: true))
        XCTAssertNil(activeWidgetMessageId(messages: [msg1, msg2], blocked: false))

        let note = ChatMessage(id: 3, role: .note, text: "Casa impostata")
        XCTAssertEqual(activeWidgetMessageId(messages: [msg1, note], blocked: false), 1)
    }

    func testDateLogic() {
        let w = DatesWidget(
            id: "d1",
            prompt: "Date",
            mode: .range,
            min: "2026-08-05",
            max: "2026-08-25",
            disabled: [DateRange(from: "2026-08-10", to: "2026-08-12")]
        )

        XCTAssertTrue(isDayDisabled(day: "2026-08-01", w: w)) // prima del min
        XCTAssertTrue(isDayDisabled(day: "2026-08-30", w: w)) // dopo il max
        XCTAssertTrue(isDayDisabled(day: "2026-08-11", w: w)) // disabilitato
        XCTAssertFalse(isDayDisabled(day: "2026-08-08", w: w)) // valido

        XCTAssertFalse(rangeIsValid(start: "2026-08-09", end: "2026-08-13", w: w)) // attraversa disabled
        XCTAssertTrue(rangeIsValid(start: "2026-08-05", end: "2026-08-09", w: w))  // valido
        XCTAssertFalse(rangeIsValid(start: "2026-08-15", end: "2026-08-10", w: w)) // fine prima di inizio

        XCTAssertEqual(initialDay(w: w, today: "2026-08-01"), "2026-08-05")
        XCTAssertEqual(initialDay(w: w, today: "2026-08-28"), "2026-08-25")
        XCTAssertEqual(initialDay(w: w, today: "2026-08-15"), "2026-08-15")
    }

    func testUtcMillisConversion() {
        let iso = "2026-08-14"
        let millis = isoToUtcMillis(iso)
        XCTAssertEqual(utcMillisToIso(millis), iso)
    }

    func testHostRepliesFormatting() {
        XCTAssertEqual(replyChoice(labels: ["Rossi"], language: "it"), "Scelto: Rossi")
        XCTAssertEqual(replyChoice(labels: ["Rossi", "Bianchi"], language: "it"), "Scelte: Rossi; Bianchi")
        XCTAssertEqual(replyChoice(labels: ["Rossi"], language: "en"), "Chosen: Rossi")

        let singleDateReply = replyDates(from: "2026-08-14", to: nil, language: "it")
        XCTAssertTrue(singleDateReply.contains("Data scelta: 14 agosto 2026"))

        let rangeReply = replyDates(from: "2026-08-14", to: "2026-08-18", language: "it")
        XCTAssertEqual(rangeReply, "Date scelte: dal 14 al 18 agosto 2026")

        let euroWidget = AmountWidget(id: "a1", prompt: "Euro", kind: .euro)
        XCTAssertEqual(replyAmount(value: 120.5, w: euroWidget, language: "it"), "Importo: 120,50 €")

        let qtyWidget = AmountWidget(id: "a2", prompt: "Quantità", kind: .quantity, unit: "pezzi")
        XCTAssertEqual(replyAmount(value: 5.0, w: qtyWidget, language: "it"), "Quantità: 5 pezzi")
    }

    func testValidateAmount() {
        let w = AmountWidget(id: "a1", prompt: "P", kind: .euro, min: 10.0, max: 200.0)
        XCTAssertEqual(parseAndValidateAmount("", w: w), .failure(.empty))
        XCTAssertEqual(parseAndValidateAmount("abc", w: w), .failure(.format))
        XCTAssertEqual(parseAndValidateAmount("12,345", w: w), .failure(.decimals))
        XCTAssertEqual(parseAndValidateAmount("5", w: w), .failure(.min))
        XCTAssertEqual(parseAndValidateAmount("250", w: w), .failure(.max))
        XCTAssertEqual(try? parseAndValidateAmount("50,50", w: w).get(), 50.5)
        XCTAssertEqual(try? parseAndValidateAmount("100", w: w).get(), 100.0)
    }
}
