import Foundation

/// Ruolo di un utente su una casa (`properties/{id}.members`, vedi firestore.rules).
enum PropertyRole: String, Sendable {
    case owner = "OWNER"
    case collaborator = "COLLABORATOR"

    static func parse(_ value: String?) -> PropertyRole? {
        value.flatMap { PropertyRole(rawValue: $0) }
    }
}

/// Funzioni extra che il proprietario concede a un collaboratore (`properties/{id}.permissions[uid]`,
/// scritto solo dalle Cloud Functions).
enum PropertyPermission: String, CaseIterable, Sendable {
    case finance = "FINANCE"
    case prices = "PRICES"
    case site = "SITE"

    var label: String {
        switch self {
        case .finance: return "Finanze"
        case .prices: return "Prezzi e calendario"
        case .site: return "Contenuti del sito"
        }
    }
}

/// Specchio di `Property.kt`. Il documento Firestore è condiviso con il sito: qui ci sono solo i campi
/// dell'app, e i salvataggi usano SEMPRE `appFields` con merge (mai l'intero documento).
struct Property: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var name = ""
    var cin: String?
    var isManagedOnCommission = false
    var idAppartamento: Int?
    var maxGuests: Int?
    var bedrooms: Int?
    var beds: Int?
    var bathrooms: Double?
    var description: String?
    var amenities: [String] = []
    var checkInTime: String?
    var checkOutTime: String?
    var houseRules: String?
    var icalUrlAirbnb: String?
    var icalUrlBooking: String?
    var lastBookingExcelImportAt: Int64?
    // Appartenenza: scritta alla creazione e poi solo dalle Cloud Functions. Mai nei salvataggi.
    var members: [String: String] = [:]
    var memberUids: [String] = []
    var createdBy: String?
    var permissions: [String: [String]] = [:]

    func roleOf(_ uid: String) -> PropertyRole? { PropertyRole.parse(members[uid]) }

    /// Permessi extra di `uid`: contano solo se è ancora COLLABORATOR; valori sconosciuti ignorati.
    func permissionsOf(_ uid: String) -> Set<PropertyPermission> {
        guard roleOf(uid) == .collaborator else { return [] }
        return Set((permissions[uid] ?? []).compactMap { PropertyPermission(rawValue: $0) })
    }

    /// I soli campi che l'app possiede, per i salvataggi con merge. NON include appartenenza,
    /// credenziali (che stanno solo sul telefono). I campi nulli restano nella mappa (come `NSNull`):
    /// svuotare un campo nel form lo cancella.
    var appFields: [String: Any] {
        return [
            "id": id,
            "name": name,
            "cin": orNull(cin),
            "isManagedOnCommission": isManagedOnCommission,
            "idAppartamento": orNull(idAppartamento),
            "maxGuests": orNull(maxGuests),
            "bedrooms": orNull(bedrooms),
            "beds": orNull(beds),
            "bathrooms": orNull(bathrooms),
            "description": orNull(description),
            "amenities": amenities,
            "checkInTime": orNull(checkInTime),
            "checkOutTime": orNull(checkOutTime),
            "houseRules": orNull(houseRules),
            "icalUrlAirbnb": orNull(icalUrlAirbnb),
            "icalUrlBooking": orNull(icalUrlBooking),
            "lastBookingExcelImportAt": orNull(lastBookingExcelImportAt),
        ]
    }
}

extension Property {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        name = c.value(.name, "")
        cin = c.optional(.cin)
        isManagedOnCommission = c.value(.isManagedOnCommission, false)
        idAppartamento = c.optional(.idAppartamento)
        maxGuests = c.optional(.maxGuests)
        bedrooms = c.optional(.bedrooms)
        beds = c.optional(.beds)
        bathrooms = c.optional(.bathrooms)
        description = c.optional(.description)
        amenities = c.value(.amenities, [])
        checkInTime = c.optional(.checkInTime)
        checkOutTime = c.optional(.checkOutTime)
        houseRules = c.optional(.houseRules)
        icalUrlAirbnb = c.optional(.icalUrlAirbnb)
        icalUrlBooking = c.optional(.icalUrlBooking)
        lastBookingExcelImportAt = c.optional(.lastBookingExcelImportAt)
        members = c.value(.members, [:])
        memberUids = c.value(.memberUids, [])
        createdBy = c.optional(.createdBy)
        permissions = c.value(.permissions, [:])
    }
}
