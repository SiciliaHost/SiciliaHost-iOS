import Foundation

public enum CactusState: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    case working
    case error
}

/// Calcola lo stato dell'avatar in base alle precedenze.
/// Precedenza: errore > lavoro (Live Staging) > ascolto microfono > attesa risposta > parlato/digitazione > riposo.
public func avatarStateOf(
    busy: Bool,
    speaking: Bool,
    typing: Bool,
    listening: Bool,
    errorFlash: Bool,
    working: Bool = false
) -> CactusState {
    if errorFlash { return .error }
    if working { return .working }
    if listening { return .listening }
    if busy { return .thinking }
    if speaking || typing { return .speaking }
    return .idle
}

// MARK: - Nuvolette (Bubble Slots)

public enum BubbleKind: Equatable, Sendable {
    case current
    case previous
    case ask
}

public struct BubbleSlot: Equatable, Identifiable, Sendable {
    public var id: Int { message.id }
    public let message: ChatMessage
    public let kind: BubbleKind

    public init(message: ChatMessage, kind: BubbleKind) {
        self.message = message
        self.kind = kind
    }
}

private let maxAsksAfter = 2

/// Determina quali nuvolette mostrare a schermo.
public func bubbleSlots(messages: [ChatMessage]) -> [BubbleSlot] {
    let chat = messages.filter { $0.role != .note && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard let current = chat.lastIndex(where: { $0.role == .assistant }) else {
        return Array(chat.suffix(maxAsksAfter)).map { BubbleSlot(message: $0, kind: .ask) }
    }

    let beforeCurrent = Array(chat[..<current])
    let previous = beforeCurrent.lastIndex(where: { $0.role == .assistant })
    var out: [BubbleSlot] = []

    if let prevIdx = previous {
        out.append(BubbleSlot(message: beforeCurrent[prevIdx], kind: .previous))
        if let lastAsk = beforeCurrent[(prevIdx + 1)...].last(where: { $0.role == .user }) {
            out.append(BubbleSlot(message: lastAsk, kind: .ask))
        }
    }

    out.append(BubbleSlot(message: chat[current], kind: .current))

    let afterCurrent = Array(chat[(current + 1)...])
    let userAsks = afterCurrent.filter { $0.role == .user }
    for ask in userAsks.suffix(maxAsksAfter) {
        out.append(BubbleSlot(message: ask, kind: .ask))
    }

    return out
}

/// Identifica l'ultimo messaggio di Cactus che contiene widget o proposte.
public func cardsMessageId(messages: [ChatMessage]) -> Int? {
    return messages.last(where: { $0.role == .assistant && (!$0.widgets.isEmpty || !$0.proposals.isEmpty) })?.id
}

// MARK: - Animazione Macchina da Scrivere (Typewriter)

private let typeMsPerChar: Int64 = 8 // ~120 car/sec
private let typeMaxMs: Int64 = 3_000

public func typewriterDurationMs(length: Int) -> Int64 {
    return min(Int64(length) * typeMsPerChar, typeMaxMs)
}

public func typedChars(elapsedMs: Int64, length: Int) -> Int {
    if length <= 0 { return 0 }
    let total = typewriterDurationMs(length: length)
    if elapsedMs >= total { return length }
    let clampedElapsed = max(0, elapsedMs)
    return Int((Int64(length) * clampedElapsed) / total)
}

public func typedPrefix(text: String, n: Int) -> String {
    if n <= 0 { return "" }
    if n >= text.count { return text }
    let idx = text.index(text.startIndex, offsetBy: n)
    return String(text[..<idx])
}
