import Foundation

// Logica pura della scheda Case (`ui/cases/CaseLogic.kt`, `CaseSaveLogic.kt`, `DeleteCase.kt`,
// `ui/property/CredentialsLogic.kt`) e della creazione guidata (`ui/wizard/WizardLogic.kt`).

/// Una riga dell'elenco Case. `missing` = ciò che manca perché l'annuncio si possa inviare.
struct CaseSummary: Equatable, Identifiable {
    let id: String
    let name: String
    let ownerUid: String?
    let memberUids: Set<String>
    let status: ListingStatus
    let zone: String?
    let coverUrl: String?
    let price: Double?
    let missing: [String]
}

/// Filtro dell'elenco (solo il super-admin vede Tutte / Host).
enum CaseFilter: Hashable {
    case mine
    case all
    case host(uid: String)
}

/// Le sezioni della scheda casa, nell'ordine in cui compaiono.
enum CaseSection: String, CaseIterable, Identifiable {
    case stato, informazioni, prezzi, foto, contenuti, posizione, infoOspiti, orari, gestione

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stato: return "Stato e pubblicazione"
        case .informazioni: return "Informazioni"
        case .prezzi: return "Prezzi e prenotazione"
        case .foto: return "Foto"
        case .contenuti: return "Contenuti della pagina"
        case .posizione: return "Posizione"
        case .infoOspiti: return "Info per gli ospiti"
        case .orari: return "Orari e regole"
        case .gestione: return "Gestione"
        }
    }

    /// Sezioni solo del sito: prezzi, foto, contenuti, posizione, info ospiti e stato dell'annuncio.
    var isSiteOnly: Bool { [.stato, .prezzi, .foto, .contenuti, .posizione, .infoOspiti].contains(self) }
}

enum CaseLogic {
    static func filter(_ cases: [CaseSummary], _ filter: CaseFilter, myUid: String) -> [CaseSummary] {
        switch filter {
        case .mine: return cases.filter { $0.memberUids.contains(myUid) }
        case .all: return cases
        case let .host(uid): return cases.filter { $0.ownerUid == uid }
        }
    }

    /// In attesa per prime (da approvare), poi per nome.
    static func sort(_ cases: [CaseSummary]) -> [CaseSummary] {
        cases.enumerated().sorted { a, b in
            let pa = a.element.status == .pending, pb = b.element.status == .pending
            if pa != pb { return pa }
            let na = a.element.name.lowercased(), nb = b.element.name.lowercased()
            if na != nb { return na < nb }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func pendingCount(_ cases: [CaseSummary]) -> Int { cases.filter { $0.status == .pending }.count }

    /// Ricerca locale per email, nome o nome di una sua casa (senza distinguere maiuscole).
    static func searchHosts(_ hosts: [HostRow], query: String) -> [HostRow] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return hosts }
        return hosts.filter { h in
            h.email.lowercased().contains(q) || h.displayName.lowercased().contains(q)
                || h.propertyNames.contains { $0.lowercased().contains(q) }
        }
    }

    /// Quando l'originale ricaricato cambia: se la bozza era uguale al VECCHIO originale (nessuna modifica dell'utente) si
    /// riallinea al nuovo, altrimenti le modifiche dell'utente restano.
    static func realign<T: Equatable>(oldOriginal: T, newOriginal: T, draft: T) -> T {
        oldOriginal != newOriginal && draft == oldOriginal ? newOriginal : draft
    }

    /// "Gestione" solo per chi gestisce davvero la casa; le sezioni del sito solo per le case sul percorso del sito.
    static func visibleSections(canManage: Bool, onSiteTrack: Bool) -> [CaseSection] {
        CaseSection.allCases.filter { ($0 != .gestione || canManage) && (onSiteTrack || !$0.isSiteOnly) }
    }
}

// MARK: Salvataggio unico

enum AppWrite: Equatable { case none, direct, adminCallable }

/// Cosa scrivere al salvataggio unico: i campi dell'app (e come) e/o quelli del sito.
struct SavePlan: Equatable {
    let app: AppWrite
    let site: Bool
}

enum CaseSaveLogic {
    static func planSave(appChanged: Bool, siteChanged: Bool, access: AppFieldsAccess) -> SavePlan {
        let app: AppWrite
        if !appChanged { app = .none } else {
            switch access {
            case .direct: app = .direct
            case .viaAdmin: app = .adminCallable
            case .readOnly: app = .none
            }
        }
        return SavePlan(app: app, site: siteChanged)
    }

    /// Le due scritture sono separate: se una fallisce l'utente deve sapere quale.
    static func partialFailureMessage(appFailed: String?, siteFailed: String?) -> String {
        switch (appFailed, siteFailed) {
        case let (a?, s?): return "Salvataggio non riuscito: \(a) / \(s)"
        case let (a?, nil): return "Salvate le informazioni del sito; non salvate quelle della scheda: \(a)"
        case let (nil, s?): return "Salvata la scheda; non salvate le informazioni del sito: \(s)"
        case (nil, nil): return ""
        }
    }

    /// Cosa scrivere nel documento riservato delle credenziali al salvataggio. nil = non toccarlo: o l'utente non è
    /// proprietario (le regole negherebbero la scrittura), o le credenziali non si sono potute leggere e il modulo era
    /// vuoto per errore (salvarlo sovrascriverebbe quelle vere con stringhe vuote).
    static func credentialsToSave(loaded: AlloggiatiCredentials?, isOwner: Bool) -> AlloggiatiCredentials? {
        isOwner ? loaded : nil
    }
}

// MARK: Eliminazione della casa

enum DeleteCaseLogic {
    /// Il nome con cui confermare: lo stesso confronto della callable `deleteProperty` (nome senza spazi ai lati, oppure
    /// l'id se la casa non ha nome).
    static func confirmName(name: String, id: String) -> String { name.trimmed.isEmpty ? id : name.trimmed }

    static func nameMatches(typed: String, name: String, id: String) -> Bool { typed.trimmed == confirmName(name: name, id: id) }

    /// Messaggio per un errore di `deleteProperty`: `code` è il nome del codice (`FAILED_PRECONDITION`…), `details` i
    /// suoi dettagli (`{ activeBookings: n }`).
    static func errorMessage(code: String?, details: Any?) -> String {
        switch code {
        case "FAILED_PRECONDITION":
            let n = ((details as? [String: Any])?["activeBookings"] as? NSNumber)?.intValue ?? 1
            let who = n == 1 ? "Un ospite del sito ha" : "\(n) ospiti del sito hanno"
            return "\(who) un soggiorno in corso o futuro: annulla prima la prenotazione."
        case "PERMISSION_DENIED", "UNAUTHENTICATED": return "Solo il proprietario può eliminare la casa."
        case "INVALID_ARGUMENT": return "Il nome non corrisponde: scrivilo esattamente com'è."
        case "NOT_FOUND": return "La casa non esiste più o la funzione non è disponibile."
        case "UNAVAILABLE", "DEADLINE_EXCEEDED":
            return "Connessione assente o lenta: riprova. La casa resta finché l'eliminazione non si completa."
        default: return "Eliminazione non riuscita. Riprova: la casa resta finché l'operazione non si completa."
        }
    }
}

// MARK: Creazione guidata

/// Le fasi dei due livelli (`WizardLevel` è in `Router.swift`).
enum WizardStep: String, CaseIterable {
    case struttura, invito, importa, casa, dove, foto, descrizione, prezzi, riepilogo

    var level: WizardLevel { [.struttura, .invito].contains(self) ? .app : .site }

    var title: String {
        switch self {
        case .struttura: return "La tua struttura"
        case .invito: return "Casa creata"
        case .importa: return "Da dove parti?"
        case .casa: return "La tua casa"
        case .dove: return "Dove si trova"
        case .foto: return "Le foto"
        case .descrizione: return "Racconta la casa"
        case .prezzi: return "Prezzi e regole"
        case .riepilogo: return "Riepilogo"
        }
    }

    var hint: String {
        switch self {
        case .struttura: return "Nome, camere e ospiti: il resto lo aggiungi quando vuoi."
        case .invito: return "La casa è già pronta nell'app. Vuoi pubblicarla anche sul sito?"
        case .importa: return "Incolla i link dei tuoi annunci: la casa si compila da sola."
        case .casa: return "Il codice identificativo (CIN), i letti e i bagni."
        case .dove: return "La zona compare sul sito; l'indirizzo esatto lo vedono solo gli ospiti confermati."
        case .foto: return "Almeno una. La prima è la copertina dell'annuncio."
        case .descrizione: return "Cosa la rende speciale, gli spazi, i dintorni."
        case .prezzi: return "Prezzo a notte, pulizie, acconto e cancellazione gratuita."
        case .riepilogo: return "Controlla e scegli: salvi la bozza o la invii per l'approvazione."
        }
    }

    var next: WizardStep? { WizardLogic.neighbor(self, 1) }
    var previous: WizardStep? { WizardLogic.neighbor(self, -1) }
}

enum WizardLogic {
    static let missingName = "Nome della casa"
    static let missingCin = "CIN"
    private static let zone = "Zona"
    private static let photo = "Almeno una foto"

    static func steps(_ level: WizardLevel) -> [WizardStep] { WizardStep.allCases.filter { $0.level == level } }

    static func neighbor(_ step: WizardStep, _ delta: Int) -> WizardStep? {
        let list = steps(step.level)
        guard let i = list.firstIndex(of: step), list.indices.contains(i + delta) else { return nil }
        return list[i + delta]
    }

    /// Cosa manca, in questa fase, perché l'annuncio si possa inviare. Il CIN lo chiede solo l'app.
    static func stepMissing(_ step: WizardStep, app: AppFieldsDraft, site: SiteDraft, photoCount: Int) -> [String] {
        let all = SiteDraftLogic.publishBlockers(site, photoCount: photoCount)
        switch step {
        case .struttura: return app.name.trimmed.isEmpty ? [missingName] : []
        case .casa: return app.cin.trimmed.isEmpty ? [missingCin] : []
        case .dove: return all.filter { $0 == zone }
        case .foto: return all.filter { $0 == photo }
        case .prezzi: return all.filter { $0 != zone && $0 != photo }
        case .importa, .invito, .descrizione, .riepilogo: return []
        }
    }

    /// Tutto ciò che manca per l'invio, nell'ordine delle fasi. Vuota = si può inviare.
    static func missing(app: AppFieldsDraft, site: SiteDraft, photoCount: Int) -> [String] {
        WizardStep.allCases.flatMap { stepMissing($0, app: app, site: site, photoCount: photoCount) }
    }

    static func firstIncomplete(app: AppFieldsDraft, site: SiteDraft, photoCount: Int) -> WizardStep? {
        WizardStep.allCases.first { !stepMissing($0, app: app, site: site, photoCount: photoCount).isEmpty }
    }

    /// Solo il nome blocca (serve per creare la casa); il resto si può lasciare a metà.
    static func canAdvance(_ step: WizardStep, app: AppFieldsDraft) -> Bool { step != .struttura || !app.name.trimmed.isEmpty }

    /// La prima fase del livello (il secondo livello inizia dall'import, saltabile).
    static func startStep(_ level: WizardLevel) -> WizardStep { steps(level)[0] }
}
