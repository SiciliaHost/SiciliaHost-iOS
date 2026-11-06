import Foundation

/// Profilo minimo (`users/{uid}`): i ruoli stanno sulle case, non qui.
struct UserProfile: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var email = ""
    var fcmToken: String?
}

extension UserProfile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        email = c.value(.email, "")
        fcmToken = c.optional(.fcmToken)
    }
}

/// Specchio di `Expense.kt`. `timestamp` è epoch in millisecondi.
struct Expense: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var propertyId = ""
    var reservationId: String?
    var description = ""
    var amount = 0.0
    var authorId = ""
    var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var category: String?
}

extension Expense {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        propertyId = c.value(.propertyId, "")
        reservationId = c.optional(.reservationId)
        description = c.value(.description, "")
        amount = c.value(.amount, 0.0)
        authorId = c.value(.authorId, "")
        timestamp = c.value(.timestamp, Int64(Date().timeIntervalSince1970 * 1000))
        category = c.optional(.category)
    }
}

/// Spesa fissa mensile; `startMonth` nel formato "yyyy-MM".
struct RecurringExpense: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var propertyId = ""
    var description = ""
    var amount = 0.0
    var startMonth = ""
    var category: String?
}

extension RecurringExpense {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        propertyId = c.value(.propertyId, "")
        description = c.value(.description, "")
        amount = c.value(.amount, 0.0)
        startMonth = c.value(.startMonth, "")
        category = c.optional(.category)
    }
}

struct InventoryItem: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var propertyId = ""
    var name = ""
    var barcode: String?
    var quantity = 0
    var lowStockThreshold = 1
    var isDepleted = false
    var imageUrl: String?
    var category = "Altro"
}

extension InventoryItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        propertyId = c.value(.propertyId, "")
        name = c.value(.name, "")
        barcode = c.optional(.barcode)
        quantity = c.value(.quantity, 0)
        lowStockThreshold = c.value(.lowStockThreshold, 1)
        isDepleted = c.value(.isDepleted, false)
        imageUrl = c.optional(.imageUrl)
        category = c.value(.category, "Altro")
    }
}

/// Scheda alloggiato (Alloggiati Web): vive SOLO sul telefono (`GuestRecordStore`), mai in Firestore; i dati dei documenti
/// vanno direttamente alla Polizia di Stato. `sesso`: "1" = M, "2" = F; `dataNascita`: dd/MM/yyyy.
struct GuestRecord: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var reservationId = ""
    var propertyId = ""
    var tipoAlloggiato = ""
    var cognome = ""
    var nome = ""
    var sesso = ""
    var dataNascita = ""
    var comuneNascitaCode: String?
    var provinciaNascita: String?
    var statoNascitaCode = ""
    var cittadinanzaCode = ""
    var tipoDocumentoCode = ""
    var numeroDocumento = ""
    var luogoRilascioCode = ""
    var schedInaSent = false
    var sendTimestamp: Int64?
    var sendError: String?
    /// Inizio di un invio in corso (blocca un secondo invio per 2 minuti), `nil` fuori dall'invio. Millisecondi.
    var sendingAt: Int64?
}

extension GuestRecord: CustomStringConvertible, CustomDebugStringConvertible {
    /// Niente nomi, date o documenti nei log (come `toString()` dell'Android).
    var description: String {
        "GuestRecord(id=\(id), reservationId=\(reservationId), propertyId=\(propertyId), schedInaSent=\(schedInaSent), "
            + "sendTimestamp=\(String(describing: sendTimestamp)), sendError=\(String(describing: sendError)), "
            + "sendingAt=\(String(describing: sendingAt)))"
    }

    var debugDescription: String { description }
}

extension GuestRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        reservationId = c.value(.reservationId, "")
        propertyId = c.value(.propertyId, "")
        tipoAlloggiato = c.value(.tipoAlloggiato, "")
        cognome = c.value(.cognome, "")
        nome = c.value(.nome, "")
        sesso = c.value(.sesso, "")
        dataNascita = c.value(.dataNascita, "")
        comuneNascitaCode = c.optional(.comuneNascitaCode)
        provinciaNascita = c.optional(.provinciaNascita)
        statoNascitaCode = c.value(.statoNascitaCode, "")
        cittadinanzaCode = c.value(.cittadinanzaCode, "")
        tipoDocumentoCode = c.value(.tipoDocumentoCode, "")
        numeroDocumento = c.value(.numeroDocumento, "")
        luogoRilascioCode = c.value(.luogoRilascioCode, "")
        schedInaSent = c.value(.schedInaSent, false)
        sendTimestamp = c.optional(.sendTimestamp)
        sendError = c.optional(.sendError)
        sendingAt = c.optional(.sendingAt)
    }
}
