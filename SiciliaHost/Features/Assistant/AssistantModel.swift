import Foundation
import SwiftUI

struct PendingSend: Equatable, Sendable {
    let text: String
    let widgetRef: WidgetRef?
    let selection: [String]?
    let propertyId: String?

    init(text: String, widgetRef: WidgetRef? = nil, selection: [String]? = nil, propertyId: String? = nil) {
        self.text = text
        self.widgetRef = widgetRef
        self.selection = selection
        self.propertyId = propertyId
    }
}

/// Modello e gestione dello stato per l'assistente Cactus in SwiftUI / iOS 17+.
@Observable
final class AssistantModel: @unchecked Sendable {
    private let api: AssistantAPI
    let language: String

    var messages: [AssistantChatMessage] = []
    var busy: Bool = false
    var error: ChatError? = nil
    var remaining: Int? = nil
    var consent: ConsentState? = nil
    var hasConversation: Bool = false

    /// Disponibilità dell'assistente per l'account (letto da `assistantStatus`).
    var available: Bool = false
    var statusKnown: Bool = false

    /// Casa selezionata per la conversazione (indipendente dalla selezione nelle schermate).
    var propertyId: String? = nil

    /// Lista case disponibili per il selettore in alto.
    var houses: [HouseOption] = []

    /// ID dell'ultimo messaggio di Cactus la cui nuvoletta è già stata animata a macchina.
    var lastTypedMessageId: Int? = nil

    var conversationId: String? = nil
    var pendingSend: PendingSend? = nil

    /// Traccia le proposte in esecuzione (singole o batch) per evitare rientranze.
    private var busyProposals: Set<String> = []
    private var groupRunning: Set<Int> = []

    private var nextMessageId = 1
    private var undoTimerTask: Task<Void, Never>? = nil

    init(
        api: AssistantAPI = AssistantService(),
        language: String = assistantLanguage(Locale.current.language.languageCode?.identifier)
    ) {
        self.api = api
        self.language = language
    }

    deinit {
        undoTimerTask?.cancel()
    }

    /// ID del messaggio i cui widget possono essere toccati adesso.
    var activeWidgetMessageId: Int? {
        activeWidgetMessageId(messages: messages, blocked: busy || consent != nil)
    }

    // MARK: - Gestione Disponibilità e Case

    func refreshAvailability() async {
        guard !statusKnown || !available else { return }
        do {
            let isAvail = try await api.status()
            await MainActor.run {
                self.available = isAvail
                self.statusKnown = true
                AssistantController.shared.available = isAvail
            }
        } catch {
            await MainActor.run {
                self.statusKnown = true
            }
        }
    }

    func syncHouses(_ properties: [Property]) {
        let opts = properties.map { HouseOption(id: $0.id, name: $0.name.isEmpty ? AssistantTexts.houseUnnamed : $0.name) }
        self.houses = opts

        // Se la casa selezionata non esiste più, torna a nil o all'unica rimasta
        if let current = propertyId, !opts.contains(where: { $0.id == current }) {
            let next = opts.count == 1 ? opts[0].id : nil
            setProperty(next)
        } else if propertyId == nil && opts.count == 1 {
            propertyId = opts[0].id
        }
    }

    func setProperty(_ newId: String?) {
        guard newId != propertyId else { return }
        propertyId = newId
        let name: String
        if let id = newId, let opt = houses.first(where: { $0.id == id }) {
            name = opt.name
        } else {
            name = AssistantTexts.houseNone
        }
        let noteMsg = AssistantChatMessage(
            id: nextMessageId,
            role: .note,
            text: AssistantTexts.houseSet(name)
        )
        nextMessageId += 1
        messages.append(noteMsg)
    }

    // MARK: - Invio Messaggi

    func send(text: String, widgetRef: WidgetRef? = nil, selection: [String]? = nil) {
        if let prob = validateDraft(text) {
            if prob == .tooLong {
                self.error = .tooLong
            }
            return
        }

        // Se c'è il consenso aperto, non si invia
        if consent != nil {
            return
        }

        let currentProp = propertyId
        let userMsg = AssistantChatMessage(
            id: nextMessageId,
            role: .user,
            text: text,
            widgetRef: widgetRef
        )
        nextMessageId += 1
        messages.append(userMsg)

        busy = true
        error = nil

        Task {
            await executeSend(text: text, widgetRef: widgetRef, selection: selection, propId: currentProp)
        }
    }

    private func executeSend(text: String, widgetRef: WidgetRef?, selection: [String]?, propId: String?) async {
        do {
            let result = try await api.message(
                text: text,
                conversationId: conversationId,
                locale: language,
                propertyId: propId,
                selection: selection
            )

            await MainActor.run {
                self.conversationId = result.conversationId
                self.remaining = result.remainingToday
                self.hasConversation = true
                self.busy = false
                self.pendingSend = nil

                var proposalViews: [ProposalView] = []
                for p in result.proposals {
                    proposalViews.append(ProposalView(ref: p))
                }

                let assistantMsg = AssistantChatMessage(
                    id: self.nextMessageId,
                    role: .assistant,
                    text: result.reply,
                    proposals: proposalViews,
                    widgets: result.widgets
                )
                self.nextMessageId += 1
                self.messages.append(assistantMsg)
            }
        } catch let ex as AssistantException {
            await MainActor.run {
                self.busy = false
                if ex.error == .consent {
                    // Salva messaggio in attesa di consenso
                    self.pendingSend = PendingSend(text: text, widgetRef: widgetRef, selection: selection, propertyId: propId)
                    self.consent = ConsentState(version: ex.consentVersion ?? "1")
                    // Rimuove l'ultimo messaggio dell'utente per reinviarlo dopo il consenso
                    if let last = self.messages.last, last.role == .user {
                        self.messages.removeLast()
                    }
                } else {
                    self.error = ex.error
                    // Se l'invio fallisce ed era nato da un widget, ripristina il widget rimuovendo il messaggio
                    if widgetRef != nil {
                        if let last = self.messages.last, last.role == .user {
                            self.messages.removeLast()
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.busy = false
                self.error = .generic
                if widgetRef != nil {
                    if let last = self.messages.last, last.role == .user {
                        self.messages.removeLast()
                    }
                }
            }
        }
    }

    // MARK: - Risposta ai Widget

    func answerWidget(messageId: Int, widgetId: String, text: String, selection: [String]? = nil) {
        guard activeWidgetMessageId == messageId else { return }

        // Segna risposta nel messaggio
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            var updated = messages[idx]
            updated.answers[widgetId] = text
            messages[idx] = updated
        }

        let ref = WidgetRef(messageId: messageId, widgetId: widgetId)
        send(text: text, widgetRef: ref, selection: selection)
    }

    // MARK: - Consenso

    func acceptConsent() {
        guard let current = consent else { return }
        consent?.busy = true
        consent?.failed = false

        Task {
            do {
                try await api.acceptTerms(version: current.version)
                await MainActor.run {
                    self.consent = nil
                    // Se c'era un messaggio in attesa, riavvia l'invio
                    if let pending = self.pendingSend {
                        self.send(text: pending.text, widgetRef: pending.widgetRef, selection: pending.selection)
                    }
                }
            } catch {
                await MainActor.run {
                    self.consent?.busy = false
                    self.consent?.failed = true
                }
            }
        }
    }

    func declineConsent() {
        consent = nil
        pendingSend = nil
    }

    // MARK: - Proposte e Modifiche (Conferma, Annulla, Raggruppamento)

    func confirm(proposalId: String) {
        guard !busyProposals.contains(proposalId) else { return }
        busyProposals.insert(proposalId)
        updateProposalStatus(id: proposalId, status: .busy)

        Task {
            do {
                let res = try await api.confirm(proposalId: proposalId)
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .done
                        view.result = res.summary
                        view.appliedChanges = res.changes
                        view.undoUntil = res.undoUntil
                    }
                    AssistantController.shared.notifyLiveDataChanged()
                    self.startUndoCountdownIfNeeded()
                }
            } catch let ex as AssistantException {
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .error
                        view.error = ex.error
                        view.errorText = ex.serverMessage
                    }
                }
            } catch {
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .error
                        view.error = .generic
                    }
                }
            }
        }
    }

    func undo(proposalId: String) {
        guard !busyProposals.contains(proposalId) else { return }
        busyProposals.insert(proposalId)
        updateProposalStatus(id: proposalId, status: .undoing)

        Task {
            do {
                let res = try await api.undo(proposalId: proposalId)
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .undone
                        view.result = res.summary
                        view.appliedChanges = res.changes
                        view.undoUntil = nil
                    }
                    AssistantController.shared.notifyLiveDataChanged()
                }
            } catch let ex as AssistantException {
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .done // resta confermata ma con errore di annullamento
                        view.undoError = ex.error
                    }
                }
            } catch {
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .done
                        view.undoError = .generic
                    }
                }
            }
        }
    }

    func decline(proposalId: String) {
        guard !busyProposals.contains(proposalId) else { return }
        busyProposals.insert(proposalId)
        updateProposalStatus(id: proposalId, status: .busy)

        Task {
            do {
                try await api.decline(proposalId: proposalId)
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .declined
                    }
                }
            } catch {
                await MainActor.run {
                    self.busyProposals.remove(proposalId)
                    self.updateProposal(id: proposalId) { view in
                        view.status = .declined
                    }
                }
            }
        }
    }

    func confirmMany(messageId: Int) {
        guard !groupRunning.contains(messageId) else { return }
        groupRunning.insert(messageId)

        guard let msg = messages.first(where: { $0.id == messageId }) else { return }
        let pendings = msg.proposals.filter { $0.status == .pending }

        Task {
            for p in pendings {
                confirm(proposalId: p.ref.id)
            }
            await MainActor.run {
                self.groupRunning.remove(messageId)
            }
        }
    }

    func declineMany(messageId: Int) {
        guard !groupRunning.contains(messageId) else { return }
        groupRunning.insert(messageId)

        guard let msg = messages.first(where: { $0.id == messageId }) else { return }
        let pendings = msg.proposals.filter { $0.status == .pending }

        Task {
            for p in pendings {
                decline(proposalId: p.ref.id)
            }
            await MainActor.run {
                self.groupRunning.remove(messageId)
            }
        }
    }

    private func updateProposal(id: String, block: (inout ProposalView) -> Void) {
        for mIdx in messages.indices {
            for pIdx in messages[mIdx].proposals.indices {
                if messages[mIdx].proposals[pIdx].ref.id == id {
                    block(&messages[mIdx].proposals[pIdx])
                    return
                }
            }
        }
    }

    private func updateProposalStatus(id: String, status: ProposalStatus) {
        updateProposal(id: id) { view in
            view.status = status
        }
    }

    // MARK: - Timer Annulla Modifica

    private func startUndoCountdownIfNeeded() {
        guard undoTimerTask == nil else { return }
        undoTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.checkUndoExpirations()
                }
            }
        }
    }

    private func checkUndoExpirations() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var anyActive = false

        for mIdx in messages.indices {
            for pIdx in messages[mIdx].proposals.indices {
                if let until = messages[mIdx].proposals[pIdx].undoUntil {
                    if now >= until {
                        messages[mIdx].proposals[pIdx].undoUntil = nil
                    } else {
                        anyActive = true
                    }
                }
            }
        }

        if !anyActive {
            undoTimerTask?.cancel()
            undoTimerTask = nil
        }
    }

    // MARK: - Reset e Pulizia Conversazione

    func newChat() {
        if let cid = conversationId {
            Task {
                try? await api.deleteConversation(conversationId: cid)
            }
        }
        reset()
    }

    func reset() {
        conversationId = nil
        messages.removeAll()
        busy = false
        error = nil
        remaining = nil
        consent = nil
        hasConversation = false
        lastTypedMessageId = nil
        pendingSend = nil
        busyProposals.removeAll()
        groupRunning.removeAll()
        undoTimerTask?.cancel()
        undoTimerTask = nil
    }

    func discardAndWait() async {
        guard let cid = conversationId else { return }
        try? await api.deleteConversation(conversationId: cid)
        reset()
    }
}
