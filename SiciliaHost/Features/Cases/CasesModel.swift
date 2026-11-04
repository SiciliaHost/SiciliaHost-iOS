import FirebaseAuth
import Foundation
import Observation

/// Una casa con tutto ciò che serve alla scheda: campi dell'app, contenuti del sito e accessi (`CaseItem` dell'Android).
struct CaseItem: Equatable {
    let property: Property
    let site: PropertySiteContent
    let appAccess: AppFieldsAccess
    let canManage: Bool

    var summary: CaseSummary {
        CaseSummary(
            id: property.id,
            name: property.name.trimmed.isEmpty ? site.name : property.name,
            ownerUid: property.members.first { $0.value == "OWNER" }?.key,
            memberUids: Set(property.memberUids),
            status: site.status,
            zone: site.zone,
            coverUrl: site.photos.first,
            price: site.basePricePerNight,
            missing: SiteDraftLogic.publishBlockers(SiteDraft(site), photoCount: site.photos.count)
        )
    }
}

/// Il tab "Case" (`CasesViewModel.kt`): elenco, ciclo di vita dell'annuncio, salvataggio unico della scheda, eliminazione.
/// Vive quanto la schermata principale: si ricarica a ogni ingresso nel tab.
@MainActor
@Observable
final class CasesModel {
    private(set) var scope: AccessScope?
    private(set) var items: [CaseItem] = []
    private(set) var hosts: [HostRow] = []
    var filter: CaseFilter = .mine
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var busy = false
    var actionError: String?
    var message: String?
    /// Errore dell'ultima eliminazione, mostrato nel foglio di conferma (non nella barra in basso).
    var deleteError: String?

    private let db = FirestoreService()
    private let siteRepo = SiteContentService()
    private let listing = ListingService()

    var isSuperAdmin: Bool { scope?.isSuperAdmin == true }

    /// Riepilogo per l'elenco: filtrato, con le in attesa per prime.
    var summaries: [CaseSummary] {
        guard let scope else { return [] }
        return CaseLogic.sort(CaseLogic.filter(items.map(\.summary), filter, myUid: scope.uid))
    }

    var allSummaries: [CaseSummary] { items.map(\.summary) }
    var pendingAll: Int { CaseLogic.pendingCount(allSummaries) }

    func item(_ id: String) -> CaseItem? { items.first { $0.property.id == id } }

    func clearMessages() {
        actionError = nil
        message = nil
    }

    /// Ricarica case, contenuti del sito ed eventualmente host; non lancia mai (un errore finisce in `loadError`).
    func load() async {
        if items.isEmpty { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            let s = try await AccessSession.shared.scope(forceRefresh: true)
            scope = s
            let houses = s.listingProperties
            let contents = try await siteRepo.getProperties(houses.map(\.id))
            let site = Dictionary(contents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            items = houses.map { p in
                CaseItem(
                    property: p, site: site[p.id] ?? PropertySiteContent(id: p.id, name: p.name),
                    appAccess: s.appFieldsAccess(p), canManage: s.canManage(p)
                )
            }
            // Un host normale vede solo le proprie case: il filtro "Mie" è l'unico possibile.
            if !s.isSuperAdmin { filter = .mine }
            if s.isSuperAdmin && hosts.isEmpty { await loadHosts() }
        } catch {
            loadError = describeSiteError(error)
        }
    }

    func loadHosts() async {
        do {
            hosts = try await listing.listHosts()
        } catch {
            actionError = describeSiteError(error)
        }
    }

    /// Crea una casa vuota (solo il nome) di cui l'utente è OWNER: nasce in bozza (`listingStatus` e `publishedOnSite`
    /// mancano). Restituisce l'id, o nil se non è riuscita.
    func createCase(name: String) async -> String? {
        guard !busy else { return nil }
        if let problem = validatePropertyForm(name: name, idAppartamentoText: "") {
            actionError = problem
            return nil
        }
        busy = true
        clearMessages()
        defer { busy = false }
        do {
            guard let uid = Auth.auth().currentUser?.uid else { throw ServiceError(message: "Nessun utente connesso") }
            let saved = try await db.addProperty(Property(name: name.trimmed), ownerUid: uid)
            await AccessSession.shared.invalidate()
            await load()
            filter = .mine
            return saved.id
        } catch {
            actionError = "Creazione non riuscita: \(describeSiteError(error))"
            return nil
        }
    }

    // MARK: Ciclo di vita dell'annuncio

    /// Invio per l'approvazione, dopo che l'utente ha accettato le condizioni d'uso (`HostTerms.version`).
    @discardableResult
    func submit(_ propertyId: String) async -> Bool {
        await act("Inviata per approvazione") { try await self.listing.submit(propertyId: propertyId, termsVersion: HostTerms.version) }
    }

    func withdraw(_ propertyId: String) async {
        await act("Invio ritirato") { try await self.listing.withdraw(propertyId: propertyId) }
    }

    /// Avvia la pubblicazione sul sito. Vero se la callable ha risposto.
    @discardableResult
    func startSitePublication(_ propertyId: String) async -> Bool {
        await act("Pubblicazione sul sito avviata") { try await self.listing.startSitePublication(propertyId: propertyId) }
    }

    func approve(_ propertyId: String) async {
        await act("Annuncio approvato") { try await self.listing.review(propertyId: propertyId, approve: true, reasons: nil) }
    }

    func reject(_ propertyId: String, reasons: String) async {
        await act("Annuncio rifiutato") { try await self.listing.review(propertyId: propertyId, approve: false, reasons: reasons) }
    }

    /// Nascondi / ripubblica un annuncio già approvato (il server rifiuta se non lo è).
    func setVisible(_ propertyId: String, _ visible: Bool) async {
        await act(visible ? "Annuncio ripubblicato" : "Annuncio nascosto") {
            try await self.siteRepo.upsert(propertyId: propertyId, patch: ["publishedOnSite": visible])
        }
    }

    @discardableResult
    private func act(_ done: String, _ block: @escaping () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        clearMessages()
        do {
            try await block()
            busy = false
            message = done
            await load()
            if isSuperAdmin { await loadHosts() }
            return true
        } catch {
            busy = false
            actionError = describeSiteError(error)
            return false
        }
    }

    /// Elimina per sempre la casa (callable `deleteProperty`, solo OWNER). Dopo l'eliminazione l'accesso si ricarica da
    /// zero: la casa sparisce anche da Home, Agenda, Finanze. Vero se eliminata.
    func deleteCase(_ propertyId: String, confirmName: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        deleteError = nil
        clearMessages()
        do {
            try await listing.deleteProperty(propertyId: propertyId, confirmName: confirmName)
            await AccessSession.shared.houseRemoved()
        } catch {
            busy = false
            deleteError = DeleteCaseLogic.errorMessage(code: functionsErrorCodeName(error), details: functionsErrorDetails(error))
            return false
        }
        busy = false
        await load()
        message = "Casa eliminata"
        if isSuperAdmin { await loadHosts() }
        return true
    }

    /// Salvataggio unico della scheda: campi dell'app (diretti o via admin) e campi del sito, in due scritture
    /// indipendenti. Vero solo se entrambe riescono (o non c'era niente da salvare).
    func saveCase(
        _ id: String, originalApp: AppFieldsDraft, currentApp: AppFieldsDraft,
        originalSite: SiteDraft, currentSite: SiteDraft, photos: [String]
    ) async -> Bool {
        guard !busy, let caseItem = item(id) else { return false }
        // Cambiata davvero = le bozze differiscono (la pubblicazione non si cambia da qui). Su una casa pubblicata la
        // patch del sito non è mai vuota: non basta per decidere.
        var comparable = currentSite
        comparable.published = originalSite.published
        let siteChanged = comparable != originalSite
        // Le foto si modificano con le loro azioni: qui non si riscrivono con una lista in memoria.
        var sitePatch = siteChanged ? SiteDraftLogic.buildPatch(original: originalSite, current: currentSite, photos: photos) : [:]
        sitePatch.removeValue(forKey: "photos")
        let plan = CaseSaveLogic.planSave(appChanged: originalApp != currentApp, siteChanged: siteChanged, access: caseItem.appAccess)
        if plan.app == .none && !plan.site { return true }

        busy = true
        clearMessages()
        var appError: String?
        var siteError: String?
        switch plan.app {
        case .direct:
            do { try await db.updatePropertyFields(id, fields: currentApp.directFields()) } catch { appError = describeSiteError(error) }
        case .adminCallable:
            do {
                try await listing.adminUpsert(propertyId: id, patch: currentApp.adminPatch(original: originalApp).mapValues { $0 as Any? })
            } catch { appError = describeSiteError(error) }
        case .none:
            break
        }
        if plan.site {
            do {
                try await siteRepo.upsert(propertyId: id, patch: sitePatch.mapValues { $0 as Any? })
            } catch { siteError = describeSiteError(error) }
        }
        busy = false
        let ok = appError == nil && siteError == nil
        if ok {
            message = "Salvato"
        } else {
            actionError = CaseSaveLogic.partialFailureMessage(appFailed: appError, siteFailed: siteError)
        }
        await load()
        return ok
    }

    // MARK: Gestione (credenziali Alloggiati, import Excel Booking)

    /// Le credenziali Alloggiati della casa, o nil se non sono disponibili (non proprietario, errore di lettura).
    func loadCredentials(_ propertyId: String) async -> AlloggiatiCredentials? {
        guard let scope = try? await AccessSession.shared.scope(),
              let property = scope.properties.first(where: { $0.id == propertyId }), scope.isOwner(property) else { return nil }
        return try? await db.getAlloggiatiCredentials(propertyId)
    }

    /// Scrive le credenziali solo se l'utente è proprietario (le regole negherebbero la scrittura). Vero se salvate.
    func saveCredentials(_ propertyId: String, _ credentials: AlloggiatiCredentials) async -> Bool {
        guard let scope = try? await AccessSession.shared.scope(),
              let property = scope.properties.first(where: { $0.id == propertyId }),
              let toSave = CaseSaveLogic.credentialsToSave(loaded: credentials, isOwner: scope.isOwner(property)) else { return false }
        do {
            try await db.saveAlloggiatiCredentials(propertyId, credentials: toSave)
            return true
        } catch {
            actionError = "Credenziali non salvate: \(error.localizedDescription)"
            return false
        }
    }

    /// "Sincronizza ora" (`syncNow` dell'Android): un giro immediato per ogni URL iCal salvato, con l'esito per l'utente.
    func syncNow(_ propertyId: String) async -> String {
        guard let property = item(propertyId)?.property else { return "Casa non trovata" }
        guard !ICalSyncService.feeds(of: property).isEmpty else { return "Nessun URL iCal configurato per questa struttura" }
        let failed = await ICalSyncService().syncProperty(property)
        return failed.isEmpty ? "Sincronizzazione completata" : "Sincronizzazione fallita — " + failed.joined(separator: " | ")
    }

    /// Import dell'export "Arrivi con recapiti" di Booking (.xls o CSV), come `importBookingExcel` dell'Android: il
    /// prezzo è già nel file, quindi le prenotazioni entrano complete. Una riga sovrapposta a un segnaposto iCal lo
    /// completa; una prenotazione già completa riceve solo i dati statistici. Restituisce il messaggio per l'utente.
    func importBookingExcel(_ propertyId: String, data: Data) async -> String {
        do {
            let commission = item(propertyId)?.property.isManagedOnCommission ?? false
            let result = try BookingExcelParser.parse(data: data, propertyId: propertyId, isManagedOnCommission: commission)
            let existing = try await db.getReservations(propertyId: propertyId, platform: "BOOKING")
            let plan = planBookingImport(rows: result.reservations, existingBooking: existing)

            var completed: [Reservation] = []
            for (placeholder, row) in plan.complete {
                var updated = row
                updated.id = placeholder.id
                updated.icalUid = placeholder.icalUid
                try await db.updateReservation(updated)
                completed.append(updated)
            }
            // Già complete: solo i dati statistici, nessuna nuova spesa biancheria.
            for (existingReservation, row) in plan.enrich {
                let fields = statsFields(row)
                if !fields.isEmpty { try await db.mergeReservationFields(existingReservation.id, fields: fields) }
            }
            let inserted = try await db.syncIcalReservationsBatch(plan.insert)
            // La rubrica contiene dati personali di clienti ed è riservata al super-admin (regole).
            let savedContacts = (try? await AccessSession.shared.scope())?.isSuperAdmin == true
            if savedContacts { try await db.saveContactsBatch(result.contacts) }

            // Spesa biancheria da 20 € solo per le prenotazioni nuove o appena completate.
            for reservation in inserted + completed {
                try await db.addExpense(Expense(
                    propertyId: reservation.propertyId, reservationId: reservation.id,
                    description: "Spesa fissa biancheria", amount: 20, authorId: "SYSTEM",
                    category: ExpenseCategory.pulizie.key
                ))
            }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try await db.updatePropertyFields(propertyId, fields: ["lastBookingExcelImportAt": now])
            // Confermate e cancellate del file: solo per il tasso di cancellazione delle Finanze.
            var stats: [String: Any] = [
                "confirmed": result.reservations.count, "cancelled": result.cancelledRows, "importedAt": now,
            ]
            stats["from"] = result.periodFrom.map { $0 as Any } ?? NSNull()
            stats["to"] = result.periodTo.map { $0 as Any } ?? NSNull()
            try? await db.updatePropertyFields(propertyId, fields: ["bookingImportStats": stats])

            return "Importazione completata: \(result.reservations.count) prenotazioni, \(result.skippedRows) righe scartate"
                + (savedContacts ? ", \(result.contacts.count) contatti aggiornati" : "")
        } catch {
            return "Importazione fallita: \(error.localizedDescription)"
        }
    }
}

/// Contenuti del sito delle case modificabili, foto e salvataggi a patch (`SiteContentViewModel.kt`): il motore delle
/// foto e degli editor Servizi/Dettagli della scheda casa.
@MainActor
@Observable
final class SiteContentModel {
    private(set) var properties: [PropertySiteContent] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isSaving = false
    var saveError: String?
    private(set) var photoBusy = false
    var photoError: String?

    private let repo = SiteContentService()

    func content(_ id: String) -> PropertySiteContent? { properties.first { $0.id == id } }

    /// Lo spinner compare solo al primo caricamento; non lancia mai (un errore finisce in `loadError`).
    func load() async {
        if properties.isEmpty { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            let ids = try await AccessSession.shared.scope().listingProperties.map(\.id)
            properties = try await repo.getProperties(ids).sorted { $0.name.lowercased() < $1.name.lowercased() }
        } catch {
            loadError = describeSiteError(error)
        }
    }

    /// Salva una patch già costruita (Servizi, Dettagli pagina). Una patch vuota chiude senza chiamare il server.
    /// Vero se salvata (il ricaricamento è atteso, e un suo errore non è un errore di salvataggio).
    func savePatch(_ propertyId: String, _ patch: [String: Any]) async -> Bool {
        guard !isSaving else { return false }
        if patch.isEmpty { return true }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await repo.upsert(propertyId: propertyId, patch: patch.mapValues { $0 as Any? })
        } catch {
            saveError = describeSiteError(error)
            return false
        }
        await load()
        return true
    }

    func addPhoto(_ propertyId: String, imageData: Data) async {
        guard !photoBusy, !isSaving, let current = content(propertyId) else { return }
        await photoAction {
            let jpeg = try await Task.detached { try PhotoEncoder.encodeJpeg(imageData) }.value
            let url = try await self.repo.uploadPhoto(propertyId: propertyId, jpeg: jpeg)
            try await self.repo.upsert(propertyId: propertyId, patch: ["photos": current.photos + [url]])
        }
    }

    func deletePhoto(_ propertyId: String, at index: Int) async {
        guard !photoBusy, !isSaving, let current = content(propertyId), current.photos.indices.contains(index) else { return }
        let url = current.photos[index]
        let remaining = removePhoto(current.photos, at: index)
        if remaining.isEmpty && current.publishedOnSite == true {
            photoError = "Disattiva prima la pubblicazione: una scheda online ha bisogno di almeno una foto"
            return
        }
        await photoAction {
            try await self.repo.upsert(propertyId: propertyId, patch: ["photos": remaining])
            // Se lo stesso URL compare ancora nella lista (duplicato), il file è ancora usato.
            if !remaining.contains(url) { await self.repo.deletePhoto(url: url) }
        }
    }

    func reorderPhoto(_ propertyId: String, from: Int, to: Int) async {
        guard !photoBusy, !isSaving, let current = content(propertyId) else { return }
        let reordered = movePhoto(current.photos, from: from, to: to)
        guard reordered != current.photos else { return }
        await photoAction { try await self.repo.upsert(propertyId: propertyId, patch: ["photos": reordered]) }
    }

    private func photoAction(_ block: @escaping () async throws -> Void) async {
        photoBusy = true
        photoError = nil
        defer { photoBusy = false }
        do {
            try await block()
            await load()
        } catch {
            photoError = describeSiteError(error)
        }
    }
}
