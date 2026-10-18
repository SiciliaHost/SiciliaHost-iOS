import Foundation

struct ImportedService: Equatable {
    let key: String
    let paid: Bool
}

struct ImportedCustom: Equatable {
    let name: String
    let category: ServiceCategory
}

struct ServiceImportResult: Equatable {
    let matched: [ImportedService]
    let unmatched: [ImportedCustom]
}

/// Minuscolo, senza accenti, solo lettere e cifre separate da un singolo spazio ("Wi-Fi" → "wi fi").
func normalizeForMatch(_ text: String) -> String {
    var out = ""
    var pendingSpace = false
    for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
        if scalar.properties.generalCategory == .nonspacingMark { continue } // accenti separati dalla lettera
        let isAlnum = (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
        if isAlnum {
            if pendingSpace && !out.isEmpty { out.append(" ") }
            pendingSpace = false
            out.unicodeScalars.append(scalar)
        } else {
            pendingSpace = true
        }
    }
    return out
}

private func containsPhrase(_ haystack: String, _ phrase: String) -> Bool { " \(haystack) ".contains(" \(phrase) ") }

// Titoli di sezione dell'elenco servizi di Airbnb: non sono servizi, ma dicono a che categoria appartengono le righe
// che li seguono.
private let sectionCategory: [String: ServiceCategory] = [
    "bagno": .bathroom,
    "camera da letto e lavanderia": .bedroom,
    "intrattenimento": .entertainment,
    "famiglia": .family,
    "riscaldamento e aria condizionata": .climate,
    "sicurezza della casa": .safety,
    "cucina e sala da pranzo": .kitchen,
    "all aperto": .outdoor,
    "parcheggio e strutture": .outdoor,
    "caratteristiche della posizione": .outdoor,
]
private let genericHeaders: Set<String> = ["cosa troverai in questo alloggio", "cosa offre questo alloggio", "servizi", "servizi offerti"]
private let stopHeader = "non incluso"

/// Riconosce i servizi in un testo copiato dall'elenco "Servizi" di un annuncio (o da `amenities`). Le righe
/// riconosciute diventano servizi del catalogo; le altre (3-60 caratteri con almeno una lettera) sono proposte come
/// servizi personalizzati, nella categoria della sezione in cui compaiono (intrattenimento se la riga non ha
/// sezione). "Non disponibile: …", "Mostra …" e tutto ciò che segue "Non incluso" si ignora.
func parsePastedServices(_ text: String) -> ServiceImportResult {
    var matchedOrder: [String] = []
    var matched: [String: Bool] = [:]
    var unmatchedOrder: [String] = []
    var unmatched: [String: ImportedCustom] = [:]
    var section: ServiceCategory?
    let bullets: Set<Character> = ["•", "-", "*", "·", " "]

    for raw in text.components(separatedBy: .newlines) {
        // Come `trim().trimStart(...)` di Kotlin: i simboli si tolgono solo all'inizio della riga.
        let line = String(raw.trimmed.drop(while: { bullets.contains($0) })).trimmed
        let norm = normalizeForMatch(line)
        if norm.isEmpty { continue }
        if norm == stopHeader { break }
        if norm.hasPrefix("non disponibile") || norm.hasPrefix("mostra ") { continue }
        if let category = sectionCategory[norm] {
            section = category
            continue
        }
        if genericHeaders.contains(norm) {
            section = nil
            continue
        }

        let paid = containsPhrase(norm, "a pagamento")
        let hits = ServiceCatalog.all.filter { s in
            s.keywords.contains { containsPhrase(norm, $0) } && !s.notWith.contains { containsPhrase(norm, $0) }
        }
        if !hits.isEmpty {
            for hit in hits {
                if matched[hit.key] == nil { matchedOrder.append(hit.key) }
                matched[hit.key] = (matched[hit.key] ?? false) || paid
            }
            continue
        }
        if (3 ... 60).contains(line.utf16.count), unmatched[norm] == nil {
            unmatchedOrder.append(norm)
            unmatched[norm] = ImportedCustom(name: line, category: section ?? .entertainment)
        }
    }
    return ServiceImportResult(
        matched: matchedOrder.map { ImportedService(key: $0, paid: matched[$0]!) },
        unmatched: unmatchedOrder.map { unmatched[$0]! }
    )
}

/// Conversione del vecchio elenco `amenities` (testo libero) nei servizi strutturati.
func servicesFromLegacyAmenities(_ amenities: [String]) -> ServiceImportResult {
    parsePastedServices(amenities.joined(separator: "\n"))
}
