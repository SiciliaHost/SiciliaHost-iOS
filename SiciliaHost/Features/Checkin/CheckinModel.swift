import Foundation
import Observation

/// Testi fissi del check-in (fuori dalla classe `@MainActor`, così li usano anche le funzioni non isolate).
enum CheckinTexts {
    static let unreachable = "Servizio Alloggiati non raggiungibile, riprova tra poco"
    static let phoneError = "Operazione non riuscita sul telefono, riprova."
    static let noApartment = "Manca l'ID Appartamento: lo imposta il proprietario nella scheda della casa (Gestione)"
}

/// Stato condiviso del check-in di una prenotazione (`CheckinViewModel.kt`): lo usano le quattro schermate (elenco ospiti,
/// scansione, modulo, invio). Check-in interamente sul telefono: schede in `GuestRecordStore`, credenziali nel portachiavi
/// (`KeychainCredentialStore`), invio diretto ad Alloggiati Web. Sul server va solo il segno `checkin`.
@MainActor
@Observable
final class CheckinModel {
    let reservationId: String
    let propertyId: String

    private(set) var reservation: Reservation?
    private(set) var property: Property?
    private(set) var guestRecords: [GuestRecord] = []
    private(set) var isLoading = false
    var error: String?

    /// Dati letti dal documento: li usa il prossimo modulo "Nuovo ospite", poi si cancellano.
    var pendingMrz: MrzData?

    private(set) var tipiAlloggiato: [LookupEntry] = []
    private(set) var tipiDocumento: [LookupEntry] = []
    private(set) var luoghi: [LookupEntry] = []

    private(set) var isSending = false
    private(set) var isSaving = false

    /// Mancano le credenziali Alloggiati su questo telefono.
    private(set) var needsCredentials = false

    /// Il check-in è già stato inviato (da questo o da un altro telefono).
    private(set) var alreadySent: CheckinMark?

    /// Le schedine già accettate non vanno rinviate: Send ha successo parziale, quindi reinviare l'intero gruppo
    /// duplicherebbe le righe già acquisite dalla Polizia di Stato.
    var pendingRecords: [GuestRecord] { CheckinLogic.pending(guestRecords) }

    /// Ultimo invio di questa prenotazione: dalle schede, altrimenti dal segno sul server.
    var lastSentAt: Int64? { guestRecords.compactMap(\.sendTimestamp).max() ?? alreadySent?.sentAt }

    /// Esito incerto dichiarato, oppure un blocco d'invio rimasto sul disco (invio interrotto a metà).
    var hasUncertainOutcome: Bool {
        SendPlan.hasUncertain(guestRecords) || guestRecords.contains { $0.sendingAt != nil && !$0.schedInaSent }
    }

    /// Schede mai inviate di un soggiorno finito da più di 30 giorni. Calcolato in memoria: niente disco dalla vista.
    var isStale: Bool {
        SendPlan.isStaleUnsent(
            StoredCheckin(propertyId: propertyId, reservationId: reservationId, checkOut: checkOut, records: guestRecords),
            now: Self.now()
        )
    }

    private let db = FirestoreService()
    private let store: GuestRecordStore
    private let credentials: CredentialStore
    private let client: AlloggiatiClient
    private let lookups: LookupService
    private var loadTask: Task<Void, Never>?

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private var checkOut: Int64 { reservation?.checkOut ?? 0 }

    init(
        reservationId: String,
        propertyId: String,
        store: GuestRecordStore = .shared,
        credentials: CredentialStore = KeychainCredentialStore(),
        client: AlloggiatiClient = .shared
    ) {
        self.reservationId = reservationId
        self.propertyId = propertyId
        self.store = store
        self.credentials = credentials
        self.client = client
        lookups = LookupService { tipo in
            guard let c = credentials.get(propertyId), c.isConfigured else { throw AlloggiatiError.refused("Credenziali mancanti") }
            return try await CheckinModel.withToken(client, c) { token in
                try await client.table(utente: c.utente, token: token, tipo: tipo)
            }
        }
        Task { await load() }
    }

    /// Chiede il token ed esegue `call`. Un esito incerto del token non conta (non è stato inviato nulla): diventa un
    /// errore normale. Se il servizio rifiuta la chiamata il token viene dimenticato, così il tentativo successivo ne chiede
    /// uno nuovo; un esito incerto della chiamata passa così com'è.
    nonisolated static func withToken<T>(
        _ client: AlloggiatiClient, _ creds: AlloggiatiCredentials, _ call: (String) async throws -> T
    ) async throws -> T {
        let token = try await tokenForCall(client, creds)
        do {
            return try await call(token)
        } catch let e as AlloggiatiError where e.isRefusal {
            await client.invalidate(creds)
            throw e
        }
    }

    nonisolated static func tokenForCall(_ client: AlloggiatiClient, _ creds: AlloggiatiCredentials) async throws -> String {
        do {
            return try await client.token(creds)
        } catch let e as AlloggiatiError where e.kind == .uncertain {
            throw AlloggiatiError.refused(CheckinTexts.unreachable)
        }
    }

    /// Messaggio per l'utente, mai vuoto. Gli errori di Alloggiati hanno già un testo per l'utente; l'archivio rovinato
    /// ha un testo suo; il resto un testo fisso.
    func describe(_ error: Error) -> String {
        if let e = error as? AlloggiatiError { return e.message.trimmed.isEmpty ? CheckinTexts.unreachable : e.message }
        if let e = error as? GuestRecordStoreError {
            switch e {
            case .corrupt: return "Archivio delle schede danneggiato: scrivi a info@siciliahost.com"
            case .unreadable: return e.errorDescription ?? CheckinTexts.phoneError
            }
        }
        return CheckinTexts.phoneError
    }

    private func readRecords() throws -> [GuestRecord] {
        try store.list(propertyId: propertyId, reservationId: reservationId)
    }

    // MARK: Caricamento

    /// Ricarica tutto. La chiama anche `CheckinView` a ogni ingresso: un modello riusato dopo l'uscita dall'account o la
    /// cancellazione delle schede non mostra schede che sul disco non ci sono più. Un solo caricamento alla volta; gira in
    /// un `Task` proprio, così aprire il modulo (che annulla il `.task` della vista) non lo interrompe.
    func load() async {
        if let running = loadTask {
            await running.value
            return
        }
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        // Prima il disco (subito), poi la rete: le schede cancellate spariscono senza attendere Firestore.
        if let records = try? readRecords() { guestRecords = records }
        do {
            property = try await AccessSession.shared.scope().operable.first { $0.id == propertyId }
            let res = try await db.getReservation(reservationId)
            reservation = res?.propertyId == propertyId ? res : nil
            // Un blocco d'invio scaduto (app chiusa durante un invio) diventa subito «esito incerto».
            let stored = try readRecords()
            let normalized = SendPlan.normalizeStaleLocks(stored, now: Self.now())
            if normalized != stored {
                try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: checkOut, records: normalized)
            }
            guestRecords = normalized
            // Un errore di lettura non cancella il segno già caricato.
            if let mark = try? await db.getCheckinMark(reservationId) { alreadySent = mark }
            await loadLookupTables()
        } catch is CancellationError {
            // Uscita dalla schermata: nessun errore da mostrare.
        } catch let e as AlloggiatiError {
            error = describe(e)
        } catch let e as GuestRecordStoreError {
            error = describe(e)
        } catch {
            // Firestore o accesso: un testo che parla di connessione (l'Android usa il testo fisso «sul telefono»).
            self.error = "Caricamento non riuscito. Controlla la connessione e riprova."
        }
    }

    private func loadLookupTables() async {
        guard let p = property else { return }
        needsCredentials = credentials.get(propertyId)?.isConfigured != true
        guard p.idAppartamento != nil else {
            error = CheckinTexts.noApartment
            return
        }
        guard !needsCredentials else { return }
        tipiAlloggiato = await lookups.tipiAlloggiato()
        tipiDocumento = await lookups.tipiDocumento()
        luoghi = await lookups.luoghi()
    }

    // MARK: Credenziali di questo telefono

    func currentCredentials() -> AlloggiatiCredentials { credentials.get(propertyId) ?? AlloggiatiCredentials() }

    /// Credenziali sbagliate o rete assente: messaggio, non un crash. Restano salvate e modificabili.
    func saveCredentials(_ c: AlloggiatiCredentials) async {
        do {
            try credentials.put(propertyId, c)
        } catch {
            self.error = "Credenziali non salvate su questo telefono, riprova"
            return
        }
        error = nil
        await client.clearTokens()
        await loadLookupTables()
    }

    func forgetCredentials() {
        credentials.remove(propertyId)
        needsCredentials = true
        let client = self.client
        Task { await client.clearTokens() }
    }

    func filterLuoghi(_ query: String) -> [LookupEntry] { LookupService.filterLuoghi(luoghi, query: query) }

    // MARK: Schede

    /// Salva i dati dell'ospite; lo stato dell'invio resta quello sul disco (il modulo non lo conosce). Una scheda già
    /// inviata o in invio non si modifica. `false` = non salvata, il motivo è in `error`.
    func save(_ record: GuestRecord) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            var existing: GuestRecord?
            if !record.id.trimmed.isEmpty { existing = try readRecords().first { $0.id == record.id } }
            if existing?.schedInaSent == true {
                error = "Scheda già inviata: non si può modificare"
                return false
            }
            if existing?.sendingAt != nil {
                error = "Invio in corso"
                return false
            }
            var r = record
            r.reservationId = reservationId
            r.propertyId = propertyId
            r.schedInaSent = existing?.schedInaSent ?? false
            r.sendTimestamp = existing?.sendTimestamp
            // Un vecchio rifiuto non vale per i dati corretti; l'esito incerto invece resta.
            r.sendError = existing?.sendError == SendPlan.uncertainMessage ? SendPlan.uncertainMessage : nil
            r.sendingAt = existing?.sendingAt
            try store.save(r, checkOut: checkOut)
            guestRecords = try readRecords()
            pendingMrz = nil
            return true
        } catch {
            self.error = describe(error)
            return false
        }
    }

    func delete(_ id: String) async {
        do {
            try store.delete(propertyId: propertyId, reservationId: reservationId, id: id)
            guestRecords = try readRecords()
        } catch {
            self.error = describe(error)
        }
    }

    /// «Elimina le schede di questa prenotazione» (anche quelle mai inviate).
    func deleteAll() {
        do {
            try store.deleteReservation(propertyId: propertyId, reservationId: reservationId)
            guestRecords = []
        } catch {
            self.error = describe(error)
        }
    }

    // MARK: Prova e invio

    /// Prova (`send = false`, `GestioneAppartamenti_Test`) o invio vero (`GestioneAppartamenti_Send`).
    func submit(send: Bool) async -> ElencoSchedineEsito? {
        // Un secondo tocco mentre un invio è in corso non parte: il blocco sul disco non lo fermerebbe (le schede si
        // bloccano solo dopo la lettura).
        if isSending { return nil }
        guard let res = reservation else { return nil }
        guard let idAppartamento = property?.idAppartamento else {
            error = CheckinTexts.noApartment
            return nil
        }
        guard let creds = credentials.get(propertyId), creds.isConfigured else {
            needsCredentials = true
            return nil
        }
        isSending = true
        error = nil
        defer { isSending = false }
        let now = Self.now()
        let pending: [GuestRecord]
        do {
            // Un blocco d'invio scaduto vuol dire un invio interrotto con esito sconosciuto: si segna «esito incerto» e ci
            // si ferma, perché rinviare potrebbe duplicare le schede.
            let stored = try readRecords()
            let normalized = SendPlan.normalizeStaleLocks(stored, now: now)
            if normalized != stored {
                try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut, records: normalized)
                guestRecords = normalized
                error = SendPlan.uncertainMessage
                return nil
            }
            pending = SendPlan.pending(normalized, now: now, respectLock: send)
        } catch {
            self.error = describe(error)
            return nil
        }
        if pending.isEmpty {
            error = "Tutte le schedine sono già state inviate o l'invio è in corso"
            return nil
        }
        let ids = pending.map(\.id)
        if send {
            do {
                try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                     records: SendPlan.lock(try readRecords(), ids: ids, now: now))
            } catch {
                self.error = describe(error)
                return nil
            }
        }
        var settled = !send
        // Da quando parte la richiesta Send la Polizia può aver acquisito le schede: se l'esito non finisce sul disco le
        // schede diventano «esito incerto», mai di nuovo inviabili.
        var requestStarted = false
        defer {
            if !settled && requestStarted {
                // Se non riesce nemmeno questo il blocco resta sul disco e normalizeStaleLocks lo renderà «esito
                // incerto» al prossimo caricamento: in ogni caso niente doppio invio.
                if let current = try? readRecords() {
                    try? store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                          records: SendPlan.markUncertain(current, ids: ids))
                }
                error = SendPlan.uncertainMessage
            } else if !settled {
                do {
                    try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                         records: SendPlan.releaseLocks(try readRecords(), ids: ids))
                } catch {
                    self.error = describe(error)
                }
            }
            do {
                guestRecords = try readRecords()
            } catch {
                self.error = describe(error)
            }
        }
        let client = self.client
        do {
            let rows = try Schedina.rows(pending, checkIn: res.checkIn, checkOut: res.checkOut)
            let esito: ElencoSchedineEsito
            if send {
                let token = try await Self.tokenForCall(client, creds)
                requestStarted = true
                do {
                    esito = try await client.send(utente: creds.utente, token: token, idAppartamento: idAppartamento, rows: rows)
                } catch let e as AlloggiatiError where e.isRefusal {
                    await client.invalidate(creds)
                    throw e
                }
            } else {
                esito = try await Self.withToken(client, creds) { token in
                    try await client.test(utente: creds.utente, token: token, idAppartamento: idAppartamento, rows: rows)
                }
            }
            if send {
                let current = try readRecords()
                guard let outcomes = SendPlan.outcomes(count: pending.count, esito.dettaglio) else {
                    try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                         records: SendPlan.markUncertain(current, ids: ids))
                    settled = true
                    error = SendPlan.uncertainMessage
                    return nil
                }
                try store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                     records: SendPlan.apply(current, ids: ids, outcomes: outcomes, now: Self.now()))
                settled = true
                if outcomes.contains(where: \.sent) {
                    let sentCount = (try? readRecords().filter(\.schedInaSent).count) ?? outcomes.filter(\.sent).count
                    markSentInBackground(guests: sentCount)
                }
            }
            return esito
        } catch let e as AlloggiatiError where e.kind == .uncertain {
            // La richiesta può essere arrivata: in invio le schede restano da controllare, mai sbloccate.
            if send {
                if let current = try? readRecords() {
                    try? store.replaceAll(propertyId: propertyId, reservationId: reservationId, checkOut: res.checkOut,
                                          records: SendPlan.markUncertain(current, ids: ids))
                }
                settled = true
            }
            error = e.message
        } catch let e as AlloggiatiError where e.kind == .rejected {
            // Rifiuto certo del servizio: nulla è stato acquisito, quindi le schede si sbloccano e si possono correggere e
            // rinviare.
            requestStarted = false
            error = describe(e)
        } catch let e as AlloggiatiError {
            // Prima della richiesta (schede non valide, token): nulla inviato. Dopo: resta incerto.
            error = requestStarted ? SendPlan.uncertainMessage : describe(e)
        } catch let e as GuestRecordStoreError {
            error = requestStarted ? SendPlan.uncertainMessage : describe(e)
        } catch {
            self.error = requestStarted ? SendPlan.uncertainMessage : CheckinTexts.unreachable
        }
        return nil
    }

    /// Il segno sul server, senza tenere acceso `isSending` se la rete cade: il check-in è comunque inviato e le schede
    /// lo dicono. Il segno ricaricato si usa solo se la rilettura riesce.
    private func markSentInBackground(guests: Int) {
        let db = self.db
        let id = reservationId
        Task { [weak self] in
            try? await db.markCheckinSent(id, guests: guests, now: Int64(Date().timeIntervalSince1970 * 1000))
            if let mark = try? await db.getCheckinMark(id) { self?.alreadySent = mark }
        }
    }

    // MARK: Ricevuta

    /// Ricevuta del giorno `dateIso` (yyyy-MM-dd, fuso italiano). Il servizio la dà solo per gli ultimi 30 giorni escluso
    /// oggi: la scelta del giorno è limitata da `ReceiptDates`.
    func downloadReceipt(dateIso: String) async -> Data? {
        guard let creds = credentials.get(propertyId), creds.isConfigured else {
            needsCredentials = true
            return nil
        }
        error = nil
        let client = self.client
        do {
            return try await Self.withToken(client, creds) { token in
                try await client.receipt(utente: creds.utente, token: token, dateIso: dateIso)
            }
        } catch {
            let refusal = (error as? AlloggiatiError)?.isRefusal == true
            self.error = "Ricevuta non scaricata: \(refusal ? describe(error) : CheckinTexts.unreachable)"
            return nil
        }
    }
}

/// Un `CheckinModel` per prenotazione, condiviso dalle schermate del check-in finché restano sullo stack.
@MainActor
@Observable
final class CheckinModels {
    // Non osservato: si legge e si riempie mentre SwiftUI costruisce la destinazione.
    @ObservationIgnored private var models: [String: CheckinModel] = [:]

    func model(reservationId: String, propertyId: String) -> CheckinModel {
        let key = "\(reservationId)_\(propertyId)"
        if let existing = models[key] { return existing }
        let created = CheckinModel(reservationId: reservationId, propertyId: propertyId)
        models[key] = created
        return created
    }

    /// Tenere solo i modelli delle prenotazioni ancora presenti sullo stack.
    func retain(only keys: Set<String>) { models = models.filter { keys.contains($0.key) } }
}
