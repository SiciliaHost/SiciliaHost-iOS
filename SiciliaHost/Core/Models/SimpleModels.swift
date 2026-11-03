import Foundation

/// Credenziali del web service Alloggiati: stanno in `properties/{id}/private/alloggiati`, solo OWNER.
struct AlloggiatiCredentials: Equatable, Sendable {
    var utente = ""
    var password = ""
    var wsKey = ""

    var isConfigured: Bool {
        !utente.trimmed.isEmpty && !password.trimmed.isEmpty && !wsKey.trimmed.isEmpty
    }
}

/// Rubrica marketing (import Excel Booking): il telefono è l'id del documento.
struct Contact: Equatable, Sendable {
    var phone = ""
    var name = ""
    var address = ""
    var country = ""
    var propertyId = ""
    var source = "BOOKING_XLS_IMPORT"
}

/// Una casa dell'invito con i permessi extra concessi (vuoto = solo gestione base).
struct InviteGrant: Equatable, Sendable {
    let propertyId: String
    let permissions: Set<PropertyPermission>
}

/// Una promozione automatica (senza codice) di `promotions/{id}`: arriva e parte solo dalle callable
/// list/create/deleteAutoPromotion. Date ISO, fine inclusa; `discountType` = "percentage" | "fixed".
struct PromoEntry: Equatable, Identifiable, Sendable {
    let id: String
    let startDate: String
    let endDate: String
    let discountType: String
    let discountValue: Double
}

let discountPercentage = "percentage"
let discountFixed = "fixed"

/// Un intervallo di tariffa stagionale (date ISO, fine inclusa). Arriva e parte solo dalle callable get/setSeasonalRates.
struct SeasonalRateEntry: Equatable, Sendable {
    let startDate: String
    let endDate: String
    let pricePerNight: Double
}

/// Intervallo di date ISO inclusivo, nel formato che la callable setSeasonalRates si aspetta.
struct IsoRange: Equatable, Sendable {
    let startDate: String
    let endDate: String
    var payload: [String: Any] { ["startDate": startDate, "endDate": endDate] }
}

/// Un host dell'elenco (risposta di `listHosts`, solo super-admin).
struct HostRow: Equatable, Identifiable, Sendable {
    let uid: String
    let email: String
    let displayName: String
    let propertyCount: Int
    let pendingCount: Int
    let propertyNames: [String]
    var id: String { uid }
}

/// Cosa ha già visto l'account: la presentazione dell'app e il tour guidato.
struct OnboardingFlags: Equatable, Sendable {
    let introSeen: Bool
    let tourDone: Bool
}

// MARK: Alloggiati Web

struct EsitoSingolo: Equatable, Sendable {
    let esito: Bool
    let errorCod: String
    let errorDes: String
    let erroreDettaglio: String
}

struct ElencoSchedineEsito: Equatable, Sendable {
    let schedineValide: Int
    let dettaglio: [EsitoSingolo]
}

struct LookupEntry: Equatable, Sendable {
    let code: String
    let description: String
}

// MARK: Risposte delle callable degli inviti e dei membri

struct Invite: Equatable, Sendable {
    let code: String
    let expiresAt: Int64
}

struct MemberInfo: Equatable, Identifiable, Sendable {
    let uid: String
    let role: PropertyRole
    let email: String
    var permissions: Set<PropertyPermission> = []
    /// Nome visualizzato dell'account (Firebase Auth), vuoto se non c'è.
    var displayName = ""
    var id: String { uid }
}

struct InvitePreviewGrant: Equatable, Sendable {
    let propertyId: String
    let propertyName: String
    let permissions: Set<PropertyPermission>
}

struct InvitePreview: Equatable, Sendable {
    let code: String
    let expiresAt: Int64
    let inviterEmail: String
    let grants: [InvitePreviewGrant]
}

struct TransferResult: Equatable, Sendable {
    let completed: Bool
    let newOwnerUid: String?
}

extension String {
    /// Come `isBlank()`/`trim()` di Kotlin: spazi e a capo ai bordi.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
