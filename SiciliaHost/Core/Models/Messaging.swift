import Foundation

// Messaggistica interna ospite ↔ host (Cloud Functions del sito, `functions/src/messaging/`). L'app è sempre il lato
// **host**. Specchio di `data/model/Messaging.kt`; le risposte di `listConversations` / `getConversation` si leggono
// con i parser di `CallableParsers.swift`.

struct StayRequest: Equatable, Sendable {
    var checkIn: String?
    var checkOut: String?
    var guests: Int?

    init(checkIn: String? = nil, checkOut: String? = nil, guests: Int? = nil) {
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.guests = guests
    }
}

struct BookingSummary: Equatable, Sendable {
    let id: String
    let status: String
    let checkIn: String
    let checkOut: String
    var guests: Int?
    var totalPrice: Double?
    var depositAmount: Double?
}

struct LastMessage: Equatable, Sendable {
    let text: String
    let from: String
    let at: Int64
}

struct Conversation: Equatable, Identifiable, Sendable {
    let id: String
    let propertyId: String
    /// Titolo in italiano della casa (lingua dell'app).
    var propertyName: String
    var guestName: String
    /// Solo con una prenotazione confermata.
    var guestEmail: String?
    var request = StayRequest()
    var booking: BookingSummary?
    var lastMessage: LastMessage?
    var unread = false
    var updatedAt: Int64 = 0

    /// Le date da mettere in evidenza: quelle della prenotazione se c'è, altrimenti della richiesta.
    var stay: StayRequest {
        guard let booking else { return request }
        return StayRequest(checkIn: booking.checkIn, checkOut: booking.checkOut, guests: booking.guests ?? request.guests)
    }
}

struct ChatMessage: Equatable, Identifiable, Sendable {
    let id: String
    /// "guest" | "host" | "system"
    let from: String
    let text: String
    let at: Int64
    /// Date e ospiti della richiesta quando quel messaggio li ha cambiati.
    var context: StayRequest?
}

struct MessagingStatus: Equatable, Sendable {
    var hostEnabled = false
    var hostUnread = 0
}

struct HostContactDetails: Equatable, Sendable {
    var phone: String?
    var whatsapp: String?
}
