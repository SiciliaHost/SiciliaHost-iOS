import Foundation

// MARK: - Protocollo Base e Contenitore

public protocol AssistantWidget: Equatable, Sendable {
    var id: String { get }
}

/// Contenitore per i widget supportati da Cactus (choice, dates, quick_replies, summary, amount).
public enum AnyWidget: Equatable, Identifiable, Sendable {
    case choice(ChoiceWidget)
    case dates(DatesWidget)
    case quickReplies(QuickRepliesWidget)
    case summary(SummaryWidget)
    case amount(AmountWidget)

    public var id: String {
        switch self {
        case .choice(let w): return w.id
        case .dates(let w): return w.id
        case .quickReplies(let w): return w.id
        case .summary(let w): return w.id
        case .amount(let w): return w.id
        }
    }
}

// MARK: - Widget Scelta (Choice)

public struct ChoiceOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

public struct ChoiceWidget: AssistantWidget, Sendable {
    public let id: String
    public let prompt: String
    public let multiple: Bool
    public let options: [ChoiceOption]

    public init(id: String, prompt: String, multiple: Bool, options: [ChoiceOption]) {
        self.id = id
        self.prompt = prompt
        self.multiple = multiple
        self.options = options
    }
}

// MARK: - Widget Date (Dates)

public enum DatesMode: String, Equatable, Sendable {
    case day = "day"
    case range = "range"
}

public struct DateRange: Equatable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct DatesWidget: AssistantWidget, Sendable {
    public let id: String
    public let prompt: String
    public let mode: DatesMode
    public let min: String?
    public let max: String?
    public let disabled: [DateRange]

    public init(
        id: String,
        prompt: String,
        mode: DatesMode,
        min: String? = nil,
        max: String? = nil,
        disabled: [DateRange] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.mode = mode
        self.min = min
        self.max = max
        self.disabled = disabled
    }
}

// MARK: - Widget Risposte Rapide (Quick Replies)

public struct QuickReply: Equatable, Sendable {
    public let label: String
    public let text: String

    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }
}

public struct QuickRepliesWidget: AssistantWidget, Sendable {
    public let id: String
    public let options: [QuickReply]

    public init(id: String, options: [QuickReply]) {
        self.id = id
        self.options = options
    }
}

// MARK: - Widget Riepilogo (Summary)

public struct SummaryRow: Equatable, Sendable {
    public let label: String
    public let value: String
    public let emphasis: Bool

    public init(label: String, value: String, emphasis: Bool = false) {
        self.label = label
        self.value = value
        self.emphasis = emphasis
    }
}

public struct SummaryWidget: AssistantWidget, Sendable {
    public let id: String
    public let title: String
    public let rows: [SummaryRow]
    public let note: String?

    public init(id: String, title: String, rows: [SummaryRow], note: String? = nil) {
        self.id = id
        self.title = title
        self.rows = rows
        self.note = note
    }
}

// MARK: - Widget Importo (Amount)

public enum AmountKind: String, Equatable, Sendable {
    case euro = "euro"
    case quantity = "quantity"
}

public struct AmountWidget: AssistantWidget, Sendable {
    public let id: String
    public let prompt: String
    public let kind: AmountKind
    public let suggestions: [Double]
    public let min: Double?
    public let max: Double?
    public let defaultValue: Double?
    public let unit: String?

    public init(
        id: String,
        prompt: String,
        kind: AmountKind,
        suggestions: [Double] = [],
        min: Double? = nil,
        max: Double? = nil,
        defaultValue: Double? = nil,
        unit: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.kind = kind
        self.suggestions = suggestions
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.unit = unit
    }
}

// MARK: - Sanitize Selection

public let maxSelectionCount = 12
private let selectionIdRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,40}$")

/// Gli id scelti da mandare in `selection`: solo quelli validi, al massimo 12; `nil` se vuoto.
public func sanitizeSelection(_ ids: [String]?) -> [String]? {
    guard let ids = ids else { return nil }
    let valid = ids.filter { id in
        let range = NSRange(location: 0, length: id.utf16.count)
        return selectionIdRegex.firstMatch(in: id, options: [], range: range) != nil
    }
    let trimmed = Array(valid.prefix(maxSelectionCount))
    return trimmed.isEmpty ? nil : trimmed
}
