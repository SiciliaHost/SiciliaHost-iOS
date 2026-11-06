import Foundation

// Come l'Android, le scritture rendono espliciti TUTTI i campi, con `NSNull` per i nulli: scrivendo un modello con
// `Codable` i campi `nil` verrebbero omessi e, nei salvataggi con merge, non cancellerebbero il valore vecchio.
// I nomi dei campi sono quelli reali dei documenti Firestore (condivisi con Android e sito).

/// `NSNull` al posto di nil, per scrivere esplicitamente un campo nullo su Firestore.
func orNull(_ value: Any?) -> Any { value ?? NSNull() }

extension Reservation {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "propertyId": propertyId,
            "guestName": orNull(guestName),
            "checkIn": checkIn,
            "checkOut": checkOut,
            "platform": platform,
            "grossAmount": orNull(grossAmount),
            "netAmountOwner": orNull(netAmountOwner),
            "netAmountAdmin": orNull(netAmountAdmin),
            "icalUid": orNull(icalUid),
            "adults": adults,
            "children": children,
            "needsReview": needsReview,
            "bookedAt": orNull(bookedAt),
            "guestCountry": orNull(guestCountry),
            "travelPurpose": orNull(travelPurpose),
            "bookingDevice": orNull(bookingDevice),
            "commissionAmount": orNull(commissionAmount),
        ]
    }
}

extension Expense {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "propertyId": propertyId,
            "reservationId": orNull(reservationId),
            "description": description,
            "amount": amount,
            "authorId": authorId,
            "timestamp": timestamp,
            "category": orNull(category),
        ]
    }
}

extension RecurringExpense {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "propertyId": propertyId,
            "description": description,
            "amount": amount,
            "startMonth": startMonth,
            "category": orNull(category),
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

extension Contact {
    var firestoreData: [String: Any] {
        ["phone": phone, "name": name, "address": address, "country": country,
         "propertyId": propertyId, "source": source]
    }
}

extension UserProfile {
    /// Le regole di creazione del profilo accettano solo `id`, `email`, `fcmToken`.
    var firestoreData: [String: Any] {
        ["id": id, "email": email, "fcmToken": orNull(fcmToken)]
    }
}
