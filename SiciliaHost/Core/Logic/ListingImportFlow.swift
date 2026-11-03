import Foundation

// Import di un annuncio Airbnb/Booking nella creazione guidata (`ui/wizard/importing/*`): link, risposta delle callable
// `importListing`/`importListingPhotos`, applicazione alle bozze, avanzamento delle foto, errori. Logica pura: il
// download delle pagine è in `Features/Wizard/ListingFetcher.swift`.

// MARK: Dichiarazione di proprietà

/// Versione del testo: la stessa di `OWNERSHIP_TEXT_VERSION` in `functions/src/importListing/ownership.ts`. Cambiare il
/// testo = cambiare la versione in entrambi i posti (e nell'Android), altrimenti l'import è rifiutato.
let ownershipTextVersion = "v1-2026-10-28"

let ownershipText = "Dichiaro di essere il proprietario degli annunci che importo, o di avere il suo permesso. "
    + "Testi e foto importati servono solo a creare la mia casa su SiciliaHost."

// MARK: Link

enum Portal: String, CaseIterable, Hashable {
    case airbnb, booking

    var wire: String { rawValue }

    var label: String {
        switch self {
        case .airbnb: return "Airbnb"
        case .booking: return "Booking"
        }
    }
}

// Gli stessi domini ammessi dal server (`portalUrlOk` in importApi.ts).
func isAirbnbHost(_ host: String) -> Bool {
    host.lowercased().wholeMatch(of: #/(?:www\.)?airbnb\.[a-z]{2,3}(?:\.[a-z]{2})?/#) != nil
}

func isBookingHost(_ host: String) -> Bool {
    host.lowercased().wholeMatch(of: #/(?:www\.)?booking\.com/#) != nil
}

private func hostMatches(_ portal: Portal, _ host: String) -> Bool {
    switch portal {
    case .airbnb: return isAirbnbHost(host)
    case .booking: return isBookingHost(host)
    }
}

/// Il link pulito (sempre https) se è del portale giusto, altrimenti nil.
func cleanListingUrl(_ portal: Portal, _ raw: String) -> String? {
    let trimmed = raw.trimmed
    if trimmed.isEmpty || trimmed.contains(where: \.isWhitespace) { return nil }
    let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let components = URLComponents(string: withScheme),
          let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
          components.user == nil, components.password == nil,
          let host = components.host?.lowercased(), hostMatches(portal, host),
          let range = withScheme.range(of: "://") else { return nil }
    return "https://" + withScheme[range.upperBound...]
}

/// Messaggio per un campo link: nil se vuoto (il link è facoltativo) o valido.
func urlProblem(_ portal: Portal, _ raw: String) -> String? {
    raw.trimmed.isEmpty || cleanListingUrl(portal, raw) != nil ? nil : "Questo non sembra un link di \(portal.label)"
}

// MARK: Campi da controllare

/// Campi importati che l'host deve ancora guardare. Il marcatore sparisce quando li tocca.
enum ReviewKey {
    static let name = "name"
    static let description = "description"
    static let cin = "cin"
    static let maxGuests = "maxGuests"
    static let bedrooms = "bedrooms"
    static let beds = "beds"
    static let bathrooms = "bathrooms"
    static let checkIn = "checkIn"
    static let checkOut = "checkOut"
    static let address = "address"
    static let location = "location"
    static let zone = "zone"
    static let services = "services"
}

/// Le chiavi che si vedono in ciascun passo (il banner «da controllare» conta solo queste).
func reviewKeysFor(_ step: WizardStep) -> Set<String> {
    switch step {
    case .struttura: return [ReviewKey.name]
    case .casa: return [ReviewKey.cin, ReviewKey.maxGuests, ReviewKey.bedrooms, ReviewKey.beds, ReviewKey.bathrooms]
    case .dove: return [ReviewKey.address, ReviewKey.location, ReviewKey.zone]
    case .descrizione: return [ReviewKey.description, ReviewKey.services]
    case .prezzi: return [ReviewKey.checkIn, ReviewKey.checkOut]
    default: return []
    }
}

/// I campi dell'app che differiscono tra `old` e `new`.
func touchedKeys(_ old: AppFieldsDraft, _ new: AppFieldsDraft) -> Set<String> {
    var keys = Set<String>()
    if old.name != new.name { keys.insert(ReviewKey.name) }
    if old.description != new.description { keys.insert(ReviewKey.description) }
    if old.cin != new.cin { keys.insert(ReviewKey.cin) }
    if old.maxGuests != new.maxGuests { keys.insert(ReviewKey.maxGuests) }
    if old.bedrooms != new.bedrooms { keys.insert(ReviewKey.bedrooms) }
    if old.beds != new.beds { keys.insert(ReviewKey.beds) }
    if old.bathrooms != new.bathrooms { keys.insert(ReviewKey.bathrooms) }
    if old.checkInTime != new.checkInTime { keys.insert(ReviewKey.checkIn) }
    if old.checkOutTime != new.checkOutTime { keys.insert(ReviewKey.checkOut) }
    return keys
}

/// I campi del sito che differiscono tra `old` e `new`.
func touchedKeys(_ old: SiteDraft, _ new: SiteDraft) -> Set<String> {
    var keys = Set<String>()
    if old.zone != new.zone { keys.insert(ReviewKey.zone) }
    if old.address != new.address { keys.insert(ReviewKey.address) }
    if old.lat != new.lat || old.lng != new.lng || old.areaLat != new.areaLat || old.areaLng != new.areaLng {
        keys.insert(ReviewKey.location)
    }
    return keys
}

// MARK: Risposta delle callable

struct ImportedRules: Equatable {
    var pets: String?
    var smoking: String?
    var parties: String?
    var quietHours: String?
    var minAge: Int?
}

struct ImportedLocation: Equatable {
    let lat: Double
    let lng: Double
    let area: String?
    let exact: Bool
}

/// Un dato su cui i due portali non concordano: `values` per portale e quello scelto dal server.
struct ImportConflict: Equatable {
    let field: String
    let values: [String: String]
    let chosen: String
}

/// `merged` della risposta di `importListing`: ciò che si è letto dagli annunci, tutto facoltativo.
struct ListingDraft: Equatable {
    var portals: [String] = []
    var name: String?
    var description: String?
    var descriptionLanguage: String?
    var maxGuests: Int?
    var bedrooms: Int?
    var beds: Int?
    var bathrooms: Double?
    var services: [String] = []
    var rules = ImportedRules()
    var checkInType: String?
    var address: String?
    var cin: String?
    var checkInFrom: String?
    var checkOutUntil: String?
    var location: ImportedLocation?
    var photos: [String] = []
    var found: [String] = []
    var conflicts: [ImportConflict] = []
}

struct ListingImport: Equatable {
    let importId: String
    let draft: ListingDraft
    let failedPortals: [String]
}

struct PhotoBatch: Equatable {
    let stored: [String]
    let failedCount: Int
    let nextOffset: Int?
    let total: Int
}

private extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? {
        guard let s = (self[key] as? String)?.trimmed, !s.isEmpty else { return nil }
        return s
    }

    func int(_ key: String) -> Int? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }

    func strings(_ key: String) -> [String] { (self[key] as? [Any])?.compactMap { $0 as? String } ?? [] }

    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}

/// Un valore di un conflitto come testo: i numeri interi senza decimali ("1", "1.5").
private func valueText(_ value: Any?) -> String {
    if let n = value as? NSNumber {
        let d = n.doubleValue
        return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(d)) : "\(d)"
    }
    if let s = value as? String { return s }
    if let value, !(value is NSNull) { return "\(value)" }
    return ""
}

/// Legge la risposta di `importListing`; nil se manca `importId` o `merged`.
func parseListingImport(_ data: Any?) -> ListingImport? {
    guard let root = data as? [String: Any], let importId = root.str("importId"), let merged = root.dict("merged") else { return nil }
    let rules = merged.dict("rules")
    let loc = merged.dict("location")
    let conflicts: [ImportConflict] = (merged["conflicts"] as? [Any])?.compactMap { raw in
        guard let c = raw as? [String: Any], let field = c.str("field") else { return nil }
        let values = (c["values"] as? [String: Any])?.mapValues(valueText) ?? [:]
        return ImportConflict(field: field, values: values, chosen: valueText(c["chosen"]))
    } ?? []
    var location: ImportedLocation?
    if let lat = loc?.double("lat"), let lng = loc?.double("lng") {
        location = ImportedLocation(lat: lat, lng: lng, area: loc?.str("area"), exact: (loc?["exact"] as? Bool) == true)
    }
    let draft = ListingDraft(
        portals: merged.strings("portals"),
        name: merged.str("name"),
        description: merged.str("description"),
        descriptionLanguage: merged.str("descriptionLanguage"),
        maxGuests: merged.int("maxGuests"),
        bedrooms: merged.int("bedrooms"),
        beds: merged.int("beds"),
        bathrooms: merged.double("bathrooms"),
        services: merged.strings("services"),
        rules: ImportedRules(
            pets: rules?.str("pets"), smoking: rules?.str("smoking"), parties: rules?.str("parties"),
            quietHours: rules?.str("quietHours"), minAge: rules?.int("minAge")
        ),
        checkInType: merged.str("checkInType"),
        address: merged.str("address"),
        cin: merged.str("cin"),
        checkInFrom: merged.str("checkInFrom"),
        checkOutUntil: merged.str("checkOutUntil"),
        location: location,
        photos: merged.strings("photos"),
        found: merged.strings("found"),
        conflicts: conflicts
    )
    let failed = (root["failures"] as? [Any])?.compactMap { ($0 as? [String: Any])?.str("portal") } ?? []
    return ListingImport(importId: importId, draft: draft, failedPortals: failed)
}

/// Legge la risposta di `importListingPhotos`; nil se non è una mappa.
func parsePhotoBatch(_ data: Any?) -> PhotoBatch? {
    guard let root = data as? [String: Any] else { return nil }
    let stored = (root["stored"] as? [Any])?.compactMap { ($0 as? [String: Any])?.str("url") } ?? []
    let failed = (root["failed"] as? [Any])?.count ?? 0
    return PhotoBatch(stored: stored, failedCount: failed, nextOffset: root.int("nextOffset"), total: root.int("total") ?? 0)
}

// MARK: Applicazione alle bozze

/// Le bozze compilate, `sitePatch` (servizi, regole, check-in: non stanno nelle bozze, si scrivono con `upsertProperty`
/// appena la casa esiste) e le chiavi `review` da far controllare all'host.
struct AppliedImport {
    let app: AppFieldsDraft
    let site: SiteDraft
    let sitePatch: [String: Any]
    let review: Set<String>
}

private let maxImportedDescription = 10_000
private let importRuleValues: Set<String> = ["allowed", "not_allowed", "on_request"]
private let importCheckInTypes: Set<String> = ["in_person", "keybox", "smart_lock"]

private func coordText(_ v: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), v) }

/// Compila solo i campi ancora vuoti: ciò che l'host ha già scritto non si tocca mai. `bearingRad` è la direzione del
/// centro dell'area pubblica rispetto al pin (casuale; fissa nei test): un centro sopra la casa pubblicherebbe il punto
/// esatto.
func applyImport(
    _ d: ListingDraft, app: AppFieldsDraft, site: SiteDraft,
    bearingRad: Double = Double.random(in: 0 ..< 2 * .pi)
) -> AppliedImport {
    var a = app
    var s = site
    var review = Set<String>()
    func fill(_ key: String, _ current: String, _ value: String?, _ set: (String) -> Void) {
        guard let value, !value.trimmed.isEmpty, current.trimmed.isEmpty else { return }
        set(value)
        review.insert(key)
    }

    fill(ReviewKey.name, a.name, d.name) { a.name = $0 }
    fill(ReviewKey.description, a.description, d.description.map { String($0.prefix(maxImportedDescription)) }) { a.description = $0 }
    fill(ReviewKey.cin, a.cin, d.cin) { a.cin = $0 }
    fill(ReviewKey.maxGuests, a.maxGuests, d.maxGuests.map(String.init)) { a.maxGuests = $0 }
    fill(ReviewKey.bedrooms, a.bedrooms, d.bedrooms.map(String.init)) { a.bedrooms = $0 }
    fill(ReviewKey.beds, a.beds, d.beds.map(String.init)) { a.beds = $0 }
    fill(ReviewKey.bathrooms, a.bathrooms, d.bathrooms.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : "\($0)" }) {
        a.bathrooms = $0
    }
    fill(ReviewKey.checkIn, a.checkInTime, d.checkInFrom) { a.checkInTime = $0 }
    fill(ReviewKey.checkOut, a.checkOutTime, d.checkOutUntil) { a.checkOutTime = $0 }

    fill(ReviewKey.address, s.address, d.address) { s.address = $0 }
    let zone = d.location?.area.map { String($0.split(separator: ",", omittingEmptySubsequences: false).first ?? "").trimmed }
    fill(ReviewKey.zone, s.zone, zone) { s.zone = $0 }
    if let loc = d.location, s.lat.trimmed.isEmpty, s.lng.trimmed.isEmpty {
        let pin = LatLng(lat: loc.lat, lng: loc.lng)
        if pin.isValid {
            let exact = pin.rounded()
            let area = defaultAreaCenter(exact: exact, bearingRad: bearingRad).rounded()
            s.lat = coordText(exact.lat)
            s.lng = coordText(exact.lng)
            s.areaLat = coordText(area.lat)
            s.areaLng = coordText(area.lng)
            review.insert(ReviewKey.location)
        }
    }

    var seen = Set<String>()
    let services = d.services.filter { seen.insert($0).inserted && ServiceCatalog.byKey[$0] != nil }.prefix(maxServices)
    var rules: [String: Any] = [:]
    if let v = d.rules.pets, importRuleValues.contains(v) { rules["pets"] = v }
    if let v = d.rules.smoking, importRuleValues.contains(v) { rules["smoking"] = v }
    if let v = d.rules.parties, importRuleValues.contains(v) { rules["parties"] = v }
    if let v = d.rules.quietHours, v.wholeMatch(of: #/([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d/#) != nil {
        rules["quietHours"] = v
    }
    if let v = d.rules.minAge, (1 ... 99).contains(v) { rules["minAge"] = v }
    var patch: [String: Any] = [:]
    if !services.isEmpty {
        patch["services"] = services.map { key -> [String: Any] in
            ["key": key, "category": ServiceCatalog.byKey[key]!.category.key]
        }
        review.insert(ReviewKey.services)
    }
    if !rules.isEmpty { patch["rulesStructured"] = rules }
    if let type = d.checkInType, importCheckInTypes.contains(type) { patch["access"] = ["checkInType": type] }
    return AppliedImport(app: a, site: s, sitePatch: patch, review: review)
}

/// Una voce della griglia «trovato / mancante» che chiude l'import: icona e conteggio opzionale.
struct FoundChip: Equatable {
    let key: String
    let label: String
    let found: Bool
    var count: Int?
}

func foundChips(_ d: ListingDraft) -> [FoundChip] {
    [
        FoundChip(key: "name", label: "Nome", found: d.name != nil),
        FoundChip(key: "description", label: "Descrizione", found: d.description != nil),
        FoundChip(key: "rooms", label: "Camere e letti",
                  found: d.maxGuests != nil || d.bedrooms != nil || d.beds != nil || d.bathrooms != nil),
        FoundChip(key: "services", label: "Servizi", found: !d.services.isEmpty, count: d.services.isEmpty ? nil : d.services.count),
        FoundChip(key: "location", label: "Posizione", found: d.location != nil || d.address != nil),
        FoundChip(key: "photos", label: "Foto", found: !d.photos.isEmpty, count: d.photos.isEmpty ? nil : d.photos.count),
        FoundChip(key: "cin", label: "CIN", found: d.cin != nil),
        FoundChip(key: "times", label: "Orari", found: d.checkInFrom != nil || d.checkOutUntil != nil),
        FoundChip(key: "rules", label: "Regole", found: d.rules != ImportedRules() || d.checkInType != nil),
    ]
}

// MARK: Errori

/// Messaggio per un errore dell'import. Il messaggio libero del server non viene mostrato (può contenere URL o testo
/// dell'annuncio).
func describeImportError(code: String, message: String?) -> String {
    switch code {
    case "RESOURCE_EXHAUSTED": return "Hai fatto troppe importazioni oggi: riprova domani o compila a mano"
    case "FAILED_PRECONDITION" where message == "noData":
        return "Non riesco a leggere l'annuncio: controlla il link o compila a mano"
    case "UNAUTHENTICATED", "UNAVAILABLE", "DEADLINE_EXCEEDED", "PERMISSION_DENIED":
        return describeHostError(code: code, message: message)
    default: return "Import non riuscito: compila a mano"
    }
}

func describeImportError(_ error: Error) -> String {
    guard let code = functionsErrorCodeName(error) else { return "Import non riuscito: compila a mano" }
    return describeImportError(code: code, message: (error as NSError).localizedDescription)
}

// MARK: Foto

/// Avanzamento dell'import delle foto. `base` = le foto della casa PRIMA dell'import, fissate al primo avvio: una
/// ripartenza non le rilegge dalla casa (ci sarebbero già quelle importate e si duplicherebbero). Il lotto si conta
/// appena arriva dal server, così «Riprova» dopo un errore di scrittura non scarica due volte le stesse foto.
struct PhotoProgress: Equatable {
    let base: [String]
    var saved: [String] = []
    var offset = 0
    var finished = false
    /// Ci sono foto salvate in Storage che non sono ancora nell'elenco della casa.
    var unwritten = false

    func afterBatch(_ stored: [String], next: Int?) -> PhotoProgress {
        var p = self
        p.saved = uniqued(saved + stored)
        p.offset = next ?? offset
        p.finished = next == nil
        p.unwritten = unwritten || !stored.isEmpty
        return p
    }

    func written() -> PhotoProgress {
        var p = self
        p.unwritten = false
        return p
    }

    /// L'elenco intero da scrivere in `photos`.
    func photos() -> [String] { uniqued(base + saved) }

    private func uniqued(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}

// MARK: Download delle pagine (parte pura)

/// Lo stesso tetto del server (`MAX_HTML_CHARS` in importApi.ts).
let maxHtmlChars = 4_000_000

/// Un valore JSON di JavaScript (stringa tra virgolette, con escape) come testo; nil se non è una stringa.
func decodeJsString(_ raw: String?) -> String? {
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
}

/// La pagina vera di Booking ha la cache dati; la sfida anti-bot (AWS WAF) no.
func looksLikeBookingData(_ html: String) -> Bool { html.contains("data-capla-store-data") }

/// Solo https: niente `file:`, `javascript:` o `http`.
func isHttpsUrl(_ url: String) -> Bool { url.lowercased().hasPrefix("https://") }

/// Un salto è ammesso solo se resta su https e su un host Airbnb.
func isSafeAirbnbUrl(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && isAirbnbHost(url.host ?? "")
}

/// `Location` può essere relativo.
func resolveRedirect(_ base: URL, _ location: String) -> URL? { URL(string: location, relativeTo: base)?.absoluteURL }

/// Accumula i byte di una pagina e si ferma appena supera il tetto (una pagina più grande non si legge tutta).
struct CappedBuffer {
    let maxBytes: Int
    private(set) var data = Data()
    private(set) var overflowed = false

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    /// Falso quando il tetto è superato: chi legge si ferma.
    mutating func append(_ chunk: Data) -> Bool {
        data.append(chunk)
        if data.count > maxBytes { overflowed = true }
        return !overflowed
    }
}
