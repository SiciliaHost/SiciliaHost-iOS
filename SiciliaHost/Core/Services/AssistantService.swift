import FirebaseFunctions
import Foundation

public protocol AssistantAPI: Sendable {
    func status() async throws -> Bool
    func message(text: String, conversationId: String?, locale: String, propertyId: String?, selection: [String]?) async throws -> MessageResult
    func confirm(proposalId: String) async throws -> ConfirmResult
    func undo(proposalId: String) async throws -> UndoResult
    func decline(proposalId: String) async throws
    func acceptTerms(version: String) async throws
    func deleteConversation(conversationId: String) async throws
}

public let assistantCallableTimeoutSeconds: TimeInterval = 130.0

public final class AssistantService: AssistantAPI, @unchecked Sendable {
    private let functions: Functions

    public init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    public func status() async throws -> Bool {
        let result = try await call("assistantStatus", payload: [:])
        return parseAvailable(result)
    }

    public func message(
        text: String,
        conversationId: String?,
        locale: String,
        propertyId: String?,
        selection: [String]?
    ) async throws -> MessageResult {
        let payload = buildMessagePayload(
            text: text,
            conversationId: conversationId,
            locale: locale,
            propertyId: propertyId,
            selection: selection
        )
        let result = try await call("assistantMessage", payload: payload)
        guard let messageResult = parseMessageResult(result) else {
            throw AssistantException(error: .generic)
        }
        return messageResult
    }

    public func confirm(proposalId: String) async throws -> ConfirmResult {
        let result = try await call("assistantConfirm", payload: ["proposalId": proposalId])
        return parseConfirmResult(result)
    }

    public func undo(proposalId: String) async throws -> UndoResult {
        let result = try await call("assistantUndo", payload: ["proposalId": proposalId])
        return parseUndoResult(result)
    }

    public func decline(proposalId: String) async throws {
        _ = try await call("assistantDecline", payload: ["proposalId": proposalId])
    }

    public func acceptTerms(version: String) async throws {
        _ = try await call("assistantAcceptTerms", payload: ["version": version])
    }

    public func deleteConversation(conversationId: String) async throws {
        _ = try await call("assistantDeleteConversation", payload: ["conversationId": conversationId])
    }

    private func call(_ name: String, payload: [String: Any]) async throws -> Any? {
        let callable = functions.httpsCallable(name)
        callable.timeoutInterval = assistantCallableTimeoutSeconds
        do {
            let result = try await callable.call(payload)
            return result.data
        } catch {
            throw toAssistantException(error)
        }
    }
}

public func toAssistantException(_ error: Error) -> AssistantException {
    let details = functionsErrorDetails(error) as? [String: Any]
    let reason = details?["reason"] as? String
    let version = details?["version"] as? String
    let code = functionsErrorCodeName(error)?.lowercased().replacingOccurrences(of: "_", with: "-")
    return AssistantException(
        error: chatErrorOf(code: code, reason: reason),
        consentVersion: version,
        serverMessage: (error as NSError).localizedDescription
    )
}
