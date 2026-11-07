import Foundation

// Come l'Android, le scritture rendono espliciti TUTTI i campi, con `NSNull` per i nulli: scrivendo un modello con
// `Codable` i campi `nil` verrebbero omessi e, nei salvataggi con merge, non cancellerebbero il valore vecchio.
// I nomi dei campi sono quelli reali dei documenti Firestore (condivisi con Android e sito).

/// `NSNull` al posto di nil, per scrivere esplicitamente un campo nullo su Firestore.
func orNull(_ value: Any?) -> Any { value ?? NSNull() }

extension Reservation {
    /// Solo i campi condivisi: nessun importo, commissione o dato statistico dell'Excel (stanno sul telefono).
    var firestoreData: [String: Any] {
        [
            "id": id,
            "propertyId": propertyId,
            "guestName": orNull(guestName),
            "checkIn": checkIn,
            "checkOut": checkOut,
            "platform": platform,
            "icalUid": orNull(icalUid),
            "adults": adults,
            "children": children,
            "guestCountry": orNull(guestCountry),
        ]
    }
}

extension InventoryItem {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "propertyId": propertyId,
            "name": name,
            "barcode": orNull(barcode),
            "quantity": quantity,
            "lowStockThreshold": lowStockThreshold,
            "isDepleted": isDepleted,
            "imageUrl": orNull(imageUrl),
            "category": category,
        ]
    }
}

extension UserProfile {
    /// Le regole di creazione del profilo accettano solo `id`, `email`, `fcmToken`.
    var firestoreData: [String: Any] {
        ["id": id, "email": email, "fcmToken": orNull(fcmToken)]
    }
}
