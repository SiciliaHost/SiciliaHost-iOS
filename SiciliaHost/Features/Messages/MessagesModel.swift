import Foundation
import Observation

/// La scheda Messaggi (`MessagesViewModel.kt`): le conversazioni degli ospiti sulle case che l'utente gestisce. Elenco riletto
/// ogni `listRefresh`, chat aperta riletta ogni `poll` (solo i messaggi nuovi) finché la scheda è in primo piano
/// (`runPolling`, cancellato dalla vista quando la scheda esce o l'app va in sfondo).
@MainActor
@Observable
final class MessagesModel {
    static let pollInterval: Duration = .seconds(8)
    static let listRefreshInterval: Duration = .seconds(32)
    static let maxText = 2000

    private(set) var conversations: [Conversation] = []
    private(set) var isLoading = true
    private(set) var loadError: String?

    private(set) var openId: String?
    private(set) var openConversation: Conversation?
    private(set) var messages: [ChatMessage] = []
    private(set) var chatLoading = false
    private(set) var chatError: String?
    private(set) var sending = false
    var sendError: String?

    private(set) var contacts: HostContactDetails?
    private(set) var contactsSaving = false
    var contactsMessage: String?

    private let service = MessagingService()
    private var contactsLoaded = false

    func loadContactsOnce() async {
        guard !contactsLoaded else { return }
        contactsLoaded = true
        contacts = try? await service.contactDetails()
    }

    func loadList(silent: Bool = false) async {
        if !silent { isLoading = true }
        do {
            conversations = try await service.list()
            loadError = nil
        } catch is CancellationError {
            // la scheda è uscita di scena: niente da segnalare
        } catch {
            if conversations.isEmpty { loadError = "Non riesco a caricare i messaggi. Controlla la connessione e riprova." }
        }
        isLoading = false
    }

    func open(_ id: String?) async {
        openId = id
        openConversation = conversations.first { $0.id == id }
        messages = []
        chatError = nil
        sendError = nil
        guard let id else { return }
        chatLoading = true
        defer { if openId == id { chatLoading = false } }
        do {
            let detail = try await service.open(id)
            guard openId == id else { return }
            apply(detail.conversation)
            messages = detail.messages
        } catch is CancellationError {
            // la vista si è chiusa
        } catch {
            if openId == id { chatError = "Non riesco ad aprire la conversazione." }
        }
    }

    func close() {
        openId = nil
        openConversation = nil
        messages = []
        chatError = nil
        sendError = nil
    }

    private func apply(_ conversation: Conversation) {
        openConversation = conversation
        conversations = ([conversation] + conversations.filter { $0.id != conversation.id }).sorted { $0.updatedAt > $1.updatedAt }
    }

    private func refreshOpen() async throws {
        guard let id = openId else { return }
        let detail = try await service.open(id, after: messages.last?.at)
        guard openId == id else { return }
        apply(detail.conversation)
        messages = mergeMessages(messages, detail.messages)
    }

    /// Rilegge la chat aperta e, più di rado, l'elenco; esce quando il task viene cancellato.
    func runPolling() async {
        var sinceList: Duration = .zero
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { return }
            try? await refreshOpen()
            sinceList += Self.pollInterval
            if sinceList >= Self.listRefreshInterval {
                sinceList = .zero
                await loadList(silent: true)
            }
        }
    }

    /// Ritorna `true` se il messaggio è partito (la vista allora svuota il campo).
    func send(_ text: String) async -> Bool {
        guard let id = openId else { return false }
        let clean = text.trimmed
        guard !clean.isEmpty, !sending else { return false }
        if clean.count > Self.maxText {
            sendError = "Al massimo \(Self.maxText) caratteri."
            return false
        }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            let message = try await service.send(id, text: clean)
            if openId == id { messages = mergeMessages(messages, [message]) }
            try? await refreshOpen()
            return true
        } catch {
            sendError = functionsErrorCodeName(error) == "RESOURCE_EXHAUSTED"
                ? "Troppi messaggi in poco tempo: riprova più tardi."
                : "Invio non riuscito. Riprova."
            return false
        }
    }

    /// Ritorna `true` se i recapiti sono stati salvati (la vista chiude il foglio).
    func saveContacts(phone: String, whatsapp: String) async -> Bool {
        guard isValidPhone(phone), isValidPhone(whatsapp) else {
            contactsMessage = "Numero non valido: usa solo cifre, spazi e il prefisso (es. +39)."
            return false
        }
        contactsSaving = true
        contactsMessage = nil
        defer { contactsSaving = false }
        do {
            let p = phone.trimmed, w = whatsapp.trimmed
            contacts = try await service.setContactDetails(HostContactDetails(phone: p.isEmpty ? nil : p, whatsapp: w.isEmpty ? nil : w))
            return true
        } catch {
            contactsMessage = "Salvataggio non riuscito. Controlla i numeri e riprova."
            return false
        }
    }
}
