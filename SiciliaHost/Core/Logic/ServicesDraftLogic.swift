import Foundation

// Bozza dei servizi della pagina (`ui/site/content/ServicesDraft.kt`). La patch è a blocchi: la lista viaggia intera
// solo se è cambiata. Una chiave sconosciuta (scritta da una versione più recente) si conserva senza mostrarla.

let customServiceKey = "custom"
let maxServices = 80
let maxServiceNote = 300
let maxCustomServiceName = 60

struct ServiceEntry: Equatable, Codable, Hashable {
    var key: String
    var name = ""
    var category: String
    var paid = false
    var note = ""

    /// Chiave di confronto: i servizi personalizzati si distinguono per nome (senza maiuscole).
    var identity: String { key == customServiceKey ? "\(customServiceKey):\(name.trimmed.lowercased())" : key }

    /// Chiave che questa versione non conosce: non si mostra ma si conserva.
    var isOpaque: Bool { key != customServiceKey && ServiceCatalog.byKey[key] == nil }

    /// Forma nel documento: `key`, `category`, `name` solo per i personalizzati, `paid` solo se vero, `note` solo se c'è.
    var wire: [String: AnyHashable] {
        var m: [String: AnyHashable] = ["key": key, "category": category]
        if key == customServiceKey { m["name"] = name.trimmed }
        if paid { m["paid"] = true }
        if !note.trimmed.isEmpty { m["note"] = note.trimmed }
        return m
    }
}

struct ServicesDraft: Equatable, Codable {
    var entries: [ServiceEntry] = []

    func has(_ key: String) -> Bool { entries.contains { $0.key == key } }

    /// Seleziona o deseleziona un servizio del catalogo. Chiavi sconosciute si ignorano.
    func toggle(_ key: String) -> ServicesDraft {
        guard let service = ServiceCatalog.byKey[key] else { return self }
        if has(key) { return ServicesDraft(entries: entries.filter { $0.key != key }) }
        return ServicesDraft(entries: entries + [ServiceEntry(key: key, category: service.category.key)])
    }

    func withCustom(_ name: String, category: ServiceCategory) -> ServicesDraft {
        let entry = ServiceEntry(key: customServiceKey, name: name.trimmed, category: category.key)
        return entries.contains { $0.identity == entry.identity } ? self : ServicesDraft(entries: entries + [entry])
    }

    /// Vero se un'altra voce (diversa da `except`) ha già questo nome da servizio personalizzato.
    func nameTaken(_ name: String, except: ServiceEntry) -> Bool {
        let identity = ServiceEntry(key: customServiceKey, name: name, category: except.category).identity
        return entries.contains { $0 != except && $0.identity == identity }
    }

    /// Rifiuta (restituisce `self`) una modifica che darebbe a `new` l'identità di un'altra voce.
    func replace(_ old: ServiceEntry, with new: ServiceEntry) -> ServicesDraft {
        if entries.contains(where: { $0 != old && $0.identity == new.identity }) { return self }
        return ServicesDraft(entries: entries.map { $0 == old ? new : $0 })
    }

    func remove(_ entry: ServiceEntry) -> ServicesDraft {
        var copy = entries
        if let i = copy.firstIndex(of: entry) { copy.remove(at: i) }
        return ServicesDraft(entries: copy)
    }

    /// Aggiunge i riconosciuti non ancora presenti e i personalizzati accettati dall'utente.
    func mergeImport(_ result: ServiceImportResult, acceptedCustom: Set<String>) -> ServicesDraft {
        var draft = self
        for m in result.matched {
            guard let service = ServiceCatalog.byKey[m.key], !draft.has(m.key) else { continue }
            draft.entries.append(ServiceEntry(key: m.key, category: service.category.key, paid: m.paid))
        }
        for c in result.unmatched where acceptedCustom.contains(c.name) {
            draft = draft.withCustom(c.name, category: c.category)
        }
        return draft
    }
}

enum ServicesDraftLogic {
    private static func validEntry(_ s: SiteService) -> ServiceEntry? {
        let category = ServiceCategory.fromKey(s.category)
        if s.key == customServiceKey {
            let name = (s.name ?? "").trimmed
            guard !name.isEmpty, let category else { return nil }
            return ServiceEntry(key: customServiceKey, name: name, category: category.key, paid: s.paid == true, note: s.note ?? "")
        }
        if let service = ServiceCatalog.byKey[s.key] {
            // La categoria dei servizi del catalogo è quella del catalogo, qualunque cosa dica il documento.
            return ServiceEntry(key: s.key, category: service.category.key, paid: s.paid == true, note: s.note ?? "")
        }
        // Chiave sconosciuta ma categoria valida: voce opaca, rimandata com'è per non cancellarla.
        guard let category else { return nil }
        return ServiceEntry(key: s.key, category: category.key, paid: s.paid == true, note: s.note ?? "")
    }

    /// I servizi davvero salvati: l'"originale" con cui si calcola la patch.
    static func fromServices(_ content: PropertySiteContent) -> ServicesDraft {
        ServicesDraft(entries: (content.services ?? []).compactMap(validEntry))
    }

    /// Punto di partenza dell'editor: i servizi salvati, o la conversione del vecchio elenco testuale (solo se il campo
    /// `services` manca: `[]` vuol dire che l'host li ha tolti tutti).
    static func from(_ content: PropertySiteContent) -> ServicesDraft {
        let saved = fromServices(content)
        if content.services != nil || content.amenities.isEmpty { return saved }
        let legacy = servicesFromLegacyAmenities(content.amenities)
        return ServicesDraft().mergeImport(legacy, acceptedCustom: Set(legacy.unmatched.map(\.name)))
    }

    /// Errori per voce (chiave = identità) e `total`. Vuoto = salvabile.
    static func errors(_ draft: ServicesDraft) -> [String: String] {
        var errors: [String: String] = [:]
        if draft.entries.count > maxServices { errors["total"] = "Massimo \(maxServices) servizi" }
        for e in draft.entries {
            if e.note.trimmed.count > maxServiceNote { errors[e.identity] = "Nota: massimo \(maxServiceNote) caratteri" }
            if e.key == customServiceKey && (e.name.trimmed.isEmpty || e.name.trimmed.count > maxCustomServiceName) {
                errors[e.identity] = "Nome: da 1 a \(maxCustomServiceName) caratteri"
            }
        }
        return errors
    }

    /// Lista per `upsertProperty`, solo se è cambiata (nil = niente da salvare).
    static func patch(original: ServicesDraft, current: ServicesDraft) -> [[String: AnyHashable]]? {
        let before = original.entries.map(\.wire), after = current.entries.map(\.wire)
        return before == after ? nil : after
    }
}
