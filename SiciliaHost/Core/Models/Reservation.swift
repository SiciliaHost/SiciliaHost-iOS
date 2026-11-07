import Foundation

/// Specchio di `Reservation.kt`. `checkIn`/`checkOut` sono epoch in millisecondi (come scrive Android
/// e come legge il sito per bloccare le date): NON cambiare tipo o significato.
/// Nessun campo di denaro: stanno solo sul telefono (`FinanceData`). I campi vecchi dei documenti
/// (`grossAmount`, `needsReview`, `netAmountOwner`…) si ignorano in lettura.
struct Reservation: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    var propertyId = ""
    var guestName: String?
    var checkIn: Int64 = 0
    var checkOut: Int64 = 0
    var platform = "MANUAL" // AIRBNB, BOOKING, MANUAL
    /// Nel documento Firestore il campo si chiama `icalUid` (la mappatura di Firestore su Android abbassa le
    /// maiuscole iniziali di `iCalUid`; il sito legge `icalUid`). NON rinominarlo in `iCalUid`.
    var icalUid: String?
    var adults = 0
    var children = 0
    var guestCountry: String?

    var checkInDate: Date { Date(timeIntervalSince1970: Double(checkIn) / 1000) }
    var checkOutDate: Date { Date(timeIntervalSince1970: Double(checkOut) / 1000) }
}

extension Reservation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        propertyId = c.value(.propertyId, "")
        guestName = c.optional(.guestName)
        checkIn = c.value(.checkIn, 0)
        checkOut = c.value(.checkOut, 0)
        platform = c.value(.platform, "MANUAL")
        icalUid = c.optional(.icalUid)
        adults = c.value(.adults, 0)
        children = c.value(.children, 0)
        guestCountry = c.optional(.guestCountry)
    }
}
