import Foundation
import Observation

/// Stato condiviso del check-in di una prenotazione (`CheckinViewModel.kt`): lo usano le quattro schermate (elenco ospiti,
/// scansione, modulo, invio), come il ViewModel unico dell'Android con la chiave `checkin_<prenotazione>_<casa>`.
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

    var pendingRecords: [GuestRecord] { CheckinLogic.pending(guestRecords) }

    private let db = FirestoreService()
    private let host = HostFunctionsService()
    private let lookups: LookupService

    init(reservationId: String, propertyId: String) {
        self.reservationId = reservationId
        self.propertyId = propertyId
        let host = HostFunctionsService()
        lookups = LookupService { tipo in try await host.getAlloggiatiTable(propertyId: propertyId, tipo: tipo) }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            property = try await AccessSession.shared.scope().operable.first { $0.id == propertyId }
            let res = try await db.getReservation(reservationId)
            reservation = res?.propertyId == propertyId ? res : nil
            guestRecords = try await db.getGuestRecords(propertyId: propertyId, reservationId: reservationId)
            await loadLookupTables()
        } catch {
            self.error = "Caricamento non riuscito. Controlla la connessione e riprova."
        }
    }

    private func loadLookupTables() async {
        guard let p = property else { return }
        guard p.alloggiatiConfigured, p.idAppartamento != nil else {
            error = "Credenziali web service non configurate per questa proprietà"
            return
        }
        tipiAlloggiato = await lookups.tipiAlloggiato()
        tipiDocumento = await lookups.tipiDocumento()
        luoghi = await lookups.luoghi()
    }

    func filterLuoghi(_ query: String) -> [LookupEntry] { LookupService.filterLuoghi(luoghi, query: query) }

    /// Salva la scheda e ricarica l'elenco; `true` se riuscito.
    func save(_ record: GuestRecord) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await db.saveGuestRecord(record)
            guestRecords = try await db.getGuestRecords(propertyId: propertyId, reservationId: reservationId)
            pendingMrz = nil
            return true
        } catch {
            self.error = "Salvataggio dell'ospite non riuscito. Controlla la connessione e riprova."
            return false
        }
    }

    func delete(_ id: String) async {
        do {
            try await db.deleteGuestRecord(id)
            guestRecords.removeAll { $0.id == id }
        } catch {
            self.error = "Eliminazione non riuscita. Controlla la connessione e riprova."
        }
    }

    /// Prova (`send = false`) o invio vero. Dopo un invio l'elenco si ricarica (il server segna le schede inviate).
    func submit(send: Bool) async -> ElencoSchedineEsito? {
        guard property != nil, reservation != nil else { return nil }
        isSending = true
        error = nil
        defer { isSending = false }
        if pendingRecords.isEmpty {
            error = "Tutte le schedine sono già state inviate"
            return nil
        }
        do {
            let esito = try await host.submitAlloggiati(propertyId: propertyId, reservationId: reservationId, send: send)
            if send {
                guestRecords = (try? await db.getGuestRecords(propertyId: propertyId, reservationId: reservationId)) ?? guestRecords
            }
            return esito
        } catch {
            self.error = describeHostError(error)
            return nil
        }
    }

    /// Ricevuta PDF. Il servizio copre gli ultimi 30 giorni escluso oggi: quella degli invii di oggi arriva da domani.
    func downloadReceipt() async -> Data? {
        do {
            return try await host.getAlloggiatiReceipt(propertyId: propertyId)
        } catch {
            self.error = "Ricevuta del giorno corrente non disponibile: la finestra del servizio copre gli ultimi 30 giorni "
                + "escluso oggi. Dettaglio: \(describeHostError(error))"
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
