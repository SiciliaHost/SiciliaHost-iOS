import FirebaseFirestore
import Foundation

/// Equivalente di `DatabaseRepository.kt`, portato per gruppi man mano che servono alle schermate.
/// Collezioni condivise con l'Android e col sito: non cambiare nomi o forma dei documenti.
struct FirestoreService {
    private let db = Firestore.firestore()

    // MARK: Profilo

    /// Legge il profilo o lo crea minimale (`id`, `email`) al primo accesso.
    func getOrCreateUserProfile(uid: String, email: String) async throws -> UserProfile {
        let ref = db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        if snapshot.exists, var profile = try? snapshot.data(as: UserProfile.self) {
            profile.id = uid
            return profile
        }
        let profile = UserProfile(id: uid, email: email)
        try await ref.setData(["id": uid, "email": email], merge: true)
        return profile
    }

    // MARK: Case

    private func property(from doc: DocumentSnapshot) -> Property? {
        guard var p = try? doc.data(as: Property.self) else { return nil }
        p.id = doc.documentID
        return p
    }

    /// Le case di cui `uid` è membro (`memberUids`).
    func getMyProperties(uid: String) async throws -> [Property] {
        let snap = try await db.collection("properties").whereField("memberUids", arrayContains: uid).getDocuments()
        return snap.documents.compactMap(property(from:))
    }

    /// Tutte le case: solo per il super-admin (le rules lo consentono solo a lui).
    func getAllProperties() async throws -> [Property] {
        let snap = try await db.collection("properties").getDocuments()
        return snap.documents.compactMap(property(from:))
    }

    /// Salva i soli campi dell'app con merge: i campi del sito (prezzo, foto, traduzioni…) restano intatti.
    func updateProperty(_ property: Property) async throws {
        try await db.collection("properties").document(property.id).setData(property.appFields, merge: true)
    }

    // MARK: Prenotazioni

    func getReservations(propertyIds: [String]) async throws -> [Reservation] {
        var result: [Reservation] = []
        for id in propertyIds {
            let snap = try await db.collection("reservations").whereField("propertyId", isEqualTo: id).getDocuments()
            result += snap.documents.compactMap { doc -> Reservation? in
                guard var r = try? doc.data(as: Reservation.self) else { return nil }
                r.id = doc.documentID
                return r
            }
        }
        return result
    }

    // MARK: Spese

    func getExpenses(propertyIds: [String]) async throws -> [Expense] {
        var result: [Expense] = []
        for id in propertyIds {
            let snap = try await db.collection("expenses").whereField("propertyId", isEqualTo: id).getDocuments()
            result += snap.documents.compactMap { doc -> Expense? in
                guard var e = try? doc.data(as: Expense.self) else { return nil }
                e.id = doc.documentID
                return e
            }
        }
        return result
    }

    // MARK: Scorte

    func getInventory(propertyId: String) async throws -> [InventoryItem] {
        let snap = try await db.collection("inventory").whereField("propertyId", isEqualTo: propertyId).getDocuments()
        return snap.documents.compactMap { doc -> InventoryItem? in
            guard var i = try? doc.data(as: InventoryItem.self) else { return nil }
            i.id = doc.documentID
            return i
        }
    }

    // MARK: Ospiti (Alloggiati)

    func getGuestRecords(propertyId: String, reservationId: String) async throws -> [GuestRecord] {
        let snap = try await db.collection("guest_records")
            .whereField("propertyId", isEqualTo: propertyId)
            .whereField("reservationId", isEqualTo: reservationId)
            .getDocuments()
        return snap.documents.compactMap { doc -> GuestRecord? in
            guard var g = try? doc.data(as: GuestRecord.self) else { return nil }
            g.id = doc.documentID
            return g
        }
    }
}
