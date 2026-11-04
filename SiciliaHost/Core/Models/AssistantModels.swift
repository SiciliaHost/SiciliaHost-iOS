import Foundation

// MARK: - Costanti di configurazione

/// Come `MAX_MESSAGE_CHARS` del server (`functions/src/assistant/config.ts`).
public let maxAssistantMessageChars = 4000

/// Pannello chiuso (o app in secondo piano) da tanto: la conversazione si cancella (10 minuti).
public let assistantIdleDeleteMs: Int64 = 10 * 60 * 1000

/// Limite oltre cui i testi lunghi nella tabella prima/dopo vengono accorciati con «Mostra tutto».
public let assistantTruncateLimit = 160

/// Lingue supportate dall'assistente (le stesse del server: `LOCALES` in `functions/src/assistant/config.ts`).
public let assistantLanguages = ["it", "en", "fr", "pl"]

// MARK: - Modelli di Proposta e Messa in Scena

/// Un campo che la proposta cambia: prima/dopo già formattati dal server; `nil` = valore nuovo o tolto.
public struct Change: Equatable, Sendable {
    public let key: String
    public let label: String
    public let before: String?
    public let after: String?
    public let long: Bool

    public init(key: String, label: String, before: String?, after: String?, long: Bool = false) {
        self.key = key
        self.label = label
        self.before = before
        self.after = after
        self.long = long
    }
}

/// Le sezioni che la messa in scena sa aprire durante una modifica.
public enum LiveSection: String, CaseIterable, Sendable {
    case overview = "overview"
    case prices = "prices"
    case texts = "texts"
    case conditions = "conditions"
    case services = "services"
    case guestInfo = "guestInfo"
    case calendar = "calendar"
    case finance = "finance"
    case inventory = "inventory"

    public static func fromWire(_ wire: String?) -> LiveSection? {
        guard let wire = wire else { return nil }
        return LiveSection(rawValue: wire)
    }
}

/// Un passo della messa in scena: quale sezione di quale casa aprire e quali chiavi (`Change.key`) appartengono a quel passo.
public struct LiveStep: Equatable, Sendable {
    public let section: LiveSection
    public let propertyId: String
    public let keys: [String]

    public init(section: LiveSection, propertyId: String, keys: [String]) {
        self.section = section
        self.propertyId = propertyId
        self.keys = keys
    }
}

/// Una modifica proposta dall'assistente: non succede nulla finché l'host non la conferma.
public struct ProposalRef: Equatable, Sendable {
    public let id: String
    public let tool: String
    public let propertyId: String
    public let summary: String
    public let warnings: [String]
    public let expiresAt: Int64
    public let changes: [Change]?
    public let plan: [LiveStep]?
    public let reason: String?

    public init(
        id: String,
        tool: String,
        propertyId: String,
        summary: String,
        warnings: [String] = [],
        expiresAt: Int64,
        changes: [Change]? = nil,
        plan: [LiveStep]? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.propertyId = propertyId
        self.summary = summary
        self.warnings = warnings
        self.expiresAt = expiresAt
        self.changes = changes
        self.plan = plan
        self.reason = reason
    }
}

/// La risposta di `assistantConfirm`: riepilogo, modifiche applicate e scadenza dell'annullamento (10 min).
public struct ConfirmResult: Equatable, Sendable {
    public let summary: String
    public let changes: [Change]
    public let undoUntil: Int64?

    public init(summary: String, changes: [Change] = [], undoUntil: Int64? = nil) {
        self.summary = summary
        self.changes = changes
        self.undoUntil = undoUntil
    }
}

/// La risposta di `assistantUndo`: riepilogo e modifiche invertite (prima/dopo scambiati).
public struct UndoResult: Equatable, Sendable {
    public let summary: String
    public let changes: [Change]

    public init(summary: String, changes: [Change] = []) {
        self.summary = summary
        self.changes = changes
    }
}

/// Risultato di un messaggio inviato all'assistente.
public struct MessageResult: Equatable, Sendable {
    public let conversationId: String
    public let reply: String
    public let proposals: [ProposalRef]
    public let remainingToday: Int
    public let widgets: [AnyWidget]

    public init(
        conversationId: String,
        reply: String,
        proposals: [ProposalRef] = [],
        remainingToday: Int,
        widgets: [AnyWidget] = []
    ) {
        self.conversationId = conversationId
        self.reply = reply
        self.proposals = proposals
        self.remainingToday = remainingToday
        self.widgets = widgets
    }
}

// MARK: - Errori

public enum ChatError: String, Equatable, Sendable {
    case consent
    case termsVersion
    case disabled
    case notHost
    case model
    case quota
    case full
    case expired
    case already
    case executeFailed
    case stale
    case undoExpired
    case notUndoable
    case partial
    case denied
    case notFound
    case tooLong
    case generic
}

/// Errori transitori per Conferma/Annulla: la proposta resta in attesa, con i pulsanti, per riprovare.
public let transientErrors: Set<ChatError> = [.generic, .model, .denied]

/// Errori definitivi di `assistantUndo`: tolgono il pulsante «Annulla la modifica» lasciando solo il messaggio d'errore.
public let undoFinalErrors: Set<ChatError> = [.stale, .undoExpired, .notUndoable, .already, .partial]

public struct AssistantException: Error, Equatable, Sendable {
    public let error: ChatError
    public let consentVersion: String?
    public let serverMessage: String?

    public init(error: ChatError, consentVersion: String? = nil, serverMessage: String? = nil) {
        self.error = error
        self.consentVersion = consentVersion
        self.serverMessage = serverMessage
    }
}

/// Traduce il codice della callable (minuscolo, con trattini) e il motivo (`details.reason`) nell'errore da mostrare.
public func chatErrorOf(code: String?, reason: String?) -> ChatError {
    guard let code = code else { return .generic }
    switch code {
    case "permission-denied":
        return reason == "not-host" ? .notHost : .denied
    case "unauthenticated":
        return .denied
    case "not-found":
        return .notFound
    case "unavailable":
        return reason == "disabled" ? .disabled : .model
    case "resource-exhausted":
        return reason == "conversation-full" ? .full : .quota
    case "failed-precondition":
        switch reason {
        case "consent": return .consent
        case "terms-version": return .termsVersion
        case "expired": return .expired
        case "already": return .already
        case "execute-failed": return .executeFailed
        case "stale": return .stale
        case "undo-expired": return .undoExpired
        case "not-undoable": return .notUndoable
        case "partial": return .partial
        default: return .generic
        }
    default:
        return .generic
    }
}

// MARK: - Validazione bozza e testo vocale

public enum DraftProblem: Equatable, Sendable {
    case empty
    case tooLong
}

public func validateDraft(_ text: String) -> DraftProblem? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .empty }
    if trimmed.count > maxAssistantMessageChars { return .tooLong }
    return nil
}

private let marksRegex = try! NSRegularExpression(pattern: "[*_`#>]")
private let bulletRegex = try! NSRegularExpression(pattern: "(?m)^\\s*[-•]\\s+")
private let blanksRegex = try! NSRegularExpression(pattern: "\\s+")

/// Il testo da leggere ad alta voce: senza segni di formattazione markdown e con spazi ridotti.
public func speechText(_ reply: String) -> String {
    var str = reply
    let range = NSRange(location: 0, length: str.utf16.count)
    str = marksRegex.stringByReplacingMatches(in: str, options: [], range: range, withTemplate: "")
    let range2 = NSRange(location: 0, length: str.utf16.count)
    str = bulletRegex.stringByReplacingMatches(in: str, options: [], range: range2, withTemplate: "")
    let range3 = NSRange(location: 0, length: str.utf16.count)
    str = blanksRegex.stringByReplacingMatches(in: str, options: [], range: range3, withTemplate: " ")
    return str.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Stato della Chat e Messaggi

/// Ruolo del messaggio nella conversazione.
public enum ChatRole: Equatable, Sendable {
    case user
    case assistant
    case note
}

public enum ProposalStatus: Equatable, Sendable {
    case pending
    case busy
    case done
    case declined
    case error
    case undoing
    case undone
}

public struct ProposalView: Equatable, Sendable {
    public let ref: ProposalRef
    public var status: ProposalStatus
    public var result: String?
    public var error: ChatError?
    public var errorText: String?
    public var appliedChanges: [Change]?
    public var undoUntil: Int64?
    public var unsavedNotice: Bool
    public var undoError: ChatError?

    public init(
        ref: ProposalRef,
        status: ProposalStatus = .pending,
        result: String? = nil,
        error: ChatError? = nil,
        errorText: String? = nil,
        appliedChanges: [Change]? = nil,
        undoUntil: Int64? = nil,
        unsavedNotice: Bool = false,
        undoError: ChatError? = nil
    ) {
        self.ref = ref
        self.status = status
        self.result = result
        self.error = error
        self.errorText = errorText
        self.appliedChanges = appliedChanges
        self.undoUntil = undoUntil
        self.unsavedNotice = unsavedNotice
        self.undoError = undoError
    }
}

public struct TruncatedText: Equatable, Sendable {
    public let short: String
    public let truncated: Bool

    public init(short: String, truncated: Bool) {
        self.short = short
        self.truncated = truncated
    }
}

/// Accorcia un testo lungo a `max` caratteri senza spezzare una parola a metà quando possibile.
public func truncateText(_ text: String, max: Int = assistantTruncateLimit) -> TruncatedText {
    if text.count <= max {
        return TruncatedText(short: text, truncated: false)
    }
    let prefixIndex = text.index(text.startIndex, offsetBy: max)
    let cut = String(text[..<prefixIndex])
    if let lastSpace = cut.lastIndex(of: " ") {
        let spaceOffset = text.distance(from: text.startIndex, to: lastSpace)
        if Double(spaceOffset) > Double(max) * 0.6 {
            let head = String(text[..<lastSpace]).trimmingCharacters(in: .whitespaces)
            return TruncatedText(short: "\(head)…", truncated: true)
        }
    }
    return TruncatedText(short: "\(cut.trimmingCharacters(in: .whitespaces))…", truncated: true)
}

/// Formatta i millisecondi rimasti per «Annulla la modifica» come `m:ss` (es. `9:41`, `0:05`, `0:00`).
public func formatCountdown(ms: Int64) -> String {
    let total = ms <= 0 ? 0 : (ms + 999) / 1000
    let m = total / 60
    let s = total % 60
    return String(format: "%lld:%02lld", m, s)
}

/// Il widget (di un messaggio di Cactus) da cui è nato un messaggio dell'host.
public struct WidgetRef: Equatable, Sendable {
    public let messageId: Int
    public let widgetId: String

    public init(messageId: Int, widgetId: String) {
        self.messageId = messageId
        self.widgetId = widgetId
    }
}

public struct AssistantChatMessage: Equatable, Identifiable, Sendable {
    public let id: Int
    public let role: ChatRole
    public let text: String
    public var proposals: [ProposalView]
    public let widgets: [AnyWidget]
    public var answers: [String: String]
    public let widgetRef: WidgetRef?

    public init(
        id: Int,
        role: ChatRole,
        text: String,
        proposals: [ProposalView] = [],
        widgets: [AnyWidget] = [],
        answers: [String: String] = [:],
        widgetRef: WidgetRef? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.proposals = proposals
        self.widgets = widgets
        self.answers = answers
        self.widgetRef = widgetRef
    }
}

public typealias AssistantMessage = AssistantChatMessage

/// Una casa dell'elenco della chat (id e nome).
public struct HouseOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Il consenso da mostrare all'utente.
public struct ConsentState: Equatable, Sendable {
    public let version: String
    public var busy: Bool
    public var failed: Bool

    public init(version: String, busy: Bool = false, failed: Bool = false) {
        self.version = version
        self.busy = busy
        self.failed = failed
    }
}

// MARK: - Lingua e Voce

/// La lingua dell'assistente: quella del dispositivo se è tra it/en/fr/pl, altrimenti italiano.
public func assistantLanguage(_ deviceLanguage: String?) -> String {
    guard let lang = deviceLanguage?.lowercased() else { return "it" }
    let prefix = lang.prefix(2)
    let code = String(prefix)
    return assistantLanguages.contains(code) ? code : "it"
}

/// Il Locale per la voce e formattazione.
public func assistantLocale(_ device: Locale = .current) -> Locale {
    let language = assistantLanguage(device.language.languageCode?.identifier ?? device.identifier)
    switch language {
    case "en": return Locale(identifier: "en_GB")
    case "fr": return Locale(identifier: "fr_FR")
    case "pl": return Locale(identifier: "pl_PL")
    default: return Locale(identifier: "it_IT")
    }
}

public enum MicStep: Equatable, Sendable {
    case listen
    case explain
    case ask
}

public func micStep(granted: Bool, shouldShowRationale: Bool) -> MicStep {
    if granted { return .listen }
    if shouldShowRationale { return .explain }
    return .ask
}

public func micDeniedPermanently(shouldShowRationaleAfterDenial: Bool) -> Bool {
    return !shouldShowRationaleAfterDenial
}
