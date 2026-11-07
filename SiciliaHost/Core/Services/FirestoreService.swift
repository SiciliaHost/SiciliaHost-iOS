import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Un documento Firestore con un `id` che vale l'id del documento.
protocol FirestoreDocument: Decodable {
    var id: String { get set }
}

extension Property: FirestoreDocument {}
extension Reservation: FirestoreDocument {}
extension InventoryItem: FirestoreDocument {}
extension UserProfile: FirestoreDocument {}

/// Equivalente di `DatabaseRepository.kt`. Collezioni condivise con l'Android e col sito: non cambiare
/// nomi dei campi né la forma dei documenti (vedi `Androidapp/CLAUDE.md`, "Who owns what").
struct FirestoreService: @unchecked Sendable {
    private let db = Firestore.firestore()

    private func decode<T: FirestoreDocument>(_ doc: DocumentSnapshot) -> T? {
        guard var value = try? doc.data(as: T.self) else { return nil }
        if value.id.isEmpty { value.id = doc.documentID }
        return value
    }

    private func decodeAll<T: FirestoreDocument>(_ snapshot: QuerySnapshot) -> [T] {
        snapshot.documents.compactMap { decode($0) }
    }

    // MARK: Utenti

    func getUserProfile(_ userId: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard snapshot.exists else { return nil }
        return decode(snapshot)
    }

    func saveUserProfile(_ user: UserProfile) async throws {
        try await db.collection("users").document(user.id).setData(user.firestoreData)
    }

    /// Presentazione e tour già visti da questo account (`users/{uid}.introSeenAt` / `tourDoneAt`). Non stanno nel
    /// profilo apposta: `saveUserProfile` fa un `set` completo e la regola di creazione accetta solo `id`, `email`, `fcmToken`.
    func getOnboardingFlags(_ userId: String) async throws -> OnboardingFlags {
        let data = try await db.collection("users").document(userId).getDocument().data() ?? [:]
        return OnboardingFlags(introSeen: data["introSeenAt"] != nil, tourDone: data["tourDoneAt"] != nil)
    }

    enum OnboardingField: String { case introSeenAt, tourDoneAt }

    /// Segna il campo con l'ora del server.
    func markOnboarding(_ userId: String, field: OnboardingField) async throws {
        try await db.collection("users").document(userId).updateData([field.rawValue: FieldValue.serverTimestamp()])
    }

    /// Ogni accesso crea il proprio profilo minimo (firestore.rules: solo id, email, fcmToken).
    /// Chi non ha case passa dall'onboarding; non esiste un'approvazione manuale.
    func getOrCreateUserProfile(uid: String, email: String) async throws -> UserProfile {
        if let existing = try await getUserProfile(uid) { return existing }
        let user = UserProfile(id: uid, email: email)
        try await saveUserProfile(user)
        return user
    }

    /// Salva il token FCM per ricevere le notifiche push. Errori ignorati (come l'Android).
    func updateFcmToken(userId: String, token: String) async {
        let ref = db.collection("users").document(userId)
        do {
            try await ref.updateData(["fcmToken": token])
        } catch {
            // Documento non ancora esistente: tentativo di crearlo (con le regole attuali può essere rifiutato).
            try? await ref.setData(["id": userId, "fcmToken": token])
        }
    }

    // MARK: Case

    /// L'id del documento è la fonte di verità (le regole confrontano `propertyId` dei figli con questo).
    /// I documenti salvati prima del fix avevano il flag scritto come "managedOnCommission".
    private func property(from doc: DocumentSnapshot) -> Property? {
        guard var property = try? doc.data(as: Property.self) else { return nil }
        property.id = doc.documentID
        if doc.data()?["isManagedOnCommission"] == nil {
            property.isManagedOnCommission = doc.data()?["managedOnCommission"] as? Bool ?? false
        }
        return property
    }

    /// Le case di cui `uid` è membro (query `array-contains` su `memberUids`, ammessa dalle regole).
    func getMyProperties(uid: String) async throws -> [Property] {
        let snap = try await db.collection("properties").whereField("memberUids", arrayContains: uid).getDocuments()
        return snap.documents.compactMap(property(from:))
    }

    /// Una casa per id, o nil se non esiste o non è accessibile all'utente.
    func getProperty(_ propertyId: String) async throws -> Property? {
        do {
            return property(from: try await db.collection("properties").document(propertyId).getDocument())
        } catch {
            let ns = error as NSError
            if ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.permissionDenied.rawValue { return nil }
            throw error
        }
    }

    /// Tutte le case: ammesso dalle regole solo al super-admin.
    func getAllProperties() async throws -> [Property] {
        let snap = try await db.collection("properties").getDocuments()
        return snap.documents.compactMap(property(from:))
    }

    /// Crea una casa di cui `ownerUid` è l'unico OWNER. Le regole accettano la creazione solo con questa forma
    /// esatta (members = {uid: OWNER}, memberUids = [uid], createdBy = uid).
    func addProperty(_ property: Property, ownerUid: String) async throws -> Property {
        let ref = db.collection("properties").document()
        var created = property
        created.id = ref.documentID
        created.members = [ownerUid: "OWNER"]
        created.memberUids = [ownerUid]
        created.createdBy = ownerUid
        var data = created.appFields
        data["members"] = created.members
        data["memberUids"] = created.memberUids
        data["createdBy"] = ownerUid
        try await ref.setData(data)
        return created
    }

    /// Merge: il documento è condiviso col sito, che scrive campi (prezzo, foto, traduzioni…) che questa struct
    /// non conosce. Si scrivono solo i campi dell'app (`appFields`): mai appartenenza e credenziali.
    func updateProperty(_ property: Property) async throws {
        try await db.collection("properties").document(property.id).setData(property.appFields, merge: true)
    }

    /// Scrive in merge solo i `fields` indicati (es. i campi della scheda), lasciando intatto il resto.
    func updatePropertyFields(_ id: String, fields: [String: Any]) async throws {
        try await db.collection("properties").document(id).setData(fields, merge: true)
    }

    /// Confermate/cancellate dell'ultimo import Booking di ogni casa (`properties/{id}.bookingImportStats`),
    /// letto a parte perché serve solo alle Finanze.
    func getBookingImportCounts(_ ids: [String]) async throws -> [String: BookingImportCounts] {
        var result: [String: BookingImportCounts] = [:]
        for id in ids {
            let snap = try await db.collection("properties").document(id).getDocument()
            guard let stats = snap.data()?["bookingImportStats"] as? [String: Any],
                  let confirmed = (stats["confirmed"] as? NSNumber)?.intValue else { continue }
            let cancelled = (stats["cancelled"] as? NSNumber)?.intValue ?? 0
            result[id] = BookingImportCounts(confirmed: confirmed, cancelled: cancelled)
        }
        return result
    }

    // MARK: Elenchi per più case (una query per casa, vedi fanOut)

    func getReservations(propertyIds: [String]) async throws -> [Reservation] {
        try await fanOut(propertyIds) { id in
            decodeAll(try await db.collection("reservations").whereField("propertyId", isEqualTo: id).getDocuments())
        }
    }

    /// Come `getReservations(propertyIds:)` ma dice anche se almeno una lettura è venuta dalla cache locale di Firestore
    /// (offline): in quel caso l'elenco può essere parziale e il riallineamento delle finanze non deve cancellare nulla.
    func getReservationsReportingCache(propertyIds: [String]) async throws -> (reservations: [Reservation], fromCache: Bool) {
        let pages: [ReservationsPage] = try await fanOut(propertyIds) { id in
            let snapshot = try await db.collection("reservations").whereField("propertyId", isEqualTo: id).getDocuments()
            return [ReservationsPage(reservations: decodeAll(snapshot), fromCache: snapshot.metadata.isFromCache)]
        }
        return (pages.flatMap(\.reservations), pages.contains(where: \.fromCache))
    }

    /// Come `getReservations(propertyIds:)`, più gli id delle prenotazioni con il segno `checkin` (check-in inviato). Il
    /// segno si legge a parte e non è un campo di `Reservation`: un salvataggio della prenotazione non lo riscrive mai.
    func getReservationsWithCheckin(propertyIds: [String]) async throws -> ReservationsWithCheckin {
        let rows: [ReservationWithMark] = try await fanOut(propertyIds) { id in
            let snapshot = try await db.collection("reservations").whereField("propertyId", isEqualTo: id).getDocuments()
            return snapshot.documents.compactMap { doc -> ReservationWithMark? in
                guard let reservation: Reservation = decode(doc) else { return nil }
                return ReservationWithMark(reservation: reservation, sent: CheckinMark.parse(doc.data()["checkin"]) != nil)
            }
        }
        return ReservationsWithCheckin(
            reservations: rows.map(\.reservation),
            checkinSentIds: Set(rows.filter(\.sent).map(\.reservation.id))
        )
    }

    func getInventory(propertyIds: [String]) async throws -> [InventoryItem] {
        try await fanOut(propertyIds) { id in try await getInventory(propertyId: id) }
    }

    // MARK: Prenotazioni

    func addReservation(_ reservation: Reservation) async throws -> Reservation {
        let ref = db.collection("reservations").document()
        var created = reservation
        created.id = ref.documentID
        try await ref.setData(created.firestoreData)
        return created
    }

    /// Usa `icalUid` come id del documento (dedup): stesso evento iCal = stesso documento, mai duplicati anche
    /// se la sincronizzazione gira più volte sullo stesso evento. Ritorna i soli documenti creati ora. Nessun campo
    /// di denaro: importi e dati dell'Excel stanno solo sul telefono (`FinanceData`).
    func syncIcalReservationsBatch(_ reservations: [Reservation]) async throws -> [Reservation] {
        if reservations.isEmpty { return [] }

        let withIds: [(docId: String, res: Reservation)] = reservations.map {
            ($0.icalUid ?? db.collection("reservations").document().documentID, $0)
        }

        // Quali documenti esistono già. Una lettura per id non si può fare (le regole rifiutano i documenti
        // inesistenti) e un `whereIn` sull'id non ha `propertyId`: si legge l'elenco di ciascuna casa coinvolta e si
        // confrontano gli id.
        var existingIds = Set<String>()
        let wantedIds = Set(withIds.map { $0.docId })
        var seenProperties = Set<String>()
        for propertyId in withIds.map({ $0.res.propertyId }) where seenProperties.insert(propertyId).inserted {
            let snapshot = try await db.collection("reservations").whereField("propertyId", isEqualTo: propertyId).getDocuments()
            for doc in snapshot.documents where wantedIds.contains(doc.documentID) {
                existingIds.insert(doc.documentID)
            }
        }

        var created: [Reservation] = []
        for start in stride(from: 0, to: withIds.count, by: 500) {
            let chunk = withIds[start ..< min(start + 500, withIds.count)]
            let batch = db.batch()
            for (docId, res) in chunk {
                let ref = db.collection("reservations").document(docId)
                if existingIds.contains(docId) {
                    // Già esistente: aggiorna solo i campi che arrivano dalla piattaforma.
                    var updates: [String: Any] = [
                        "guestName": orNull(res.guestName),
                        "checkIn": res.checkIn,
                        "checkOut": res.checkOut,
                        "platform": res.platform,
                        "propertyId": res.propertyId,
                    ]
                    if let country = res.guestCountry { updates["guestCountry"] = country }
                    if res.adults > 0 {
                        updates["adults"] = res.adults
                        updates["children"] = res.children
                    }
                    batch.setData(updates, forDocument: ref, merge: true)
                } else {
                    var newRes = res
                    newRes.id = docId
                    batch.setData(newRes.firestoreData, forDocument: ref)
                    created.append(newRes)
                }
            }
            try await batch.commit()
        }
        return created
    }

    /// Completa un segnaposto iCal con i soli dati condivisi dell'Excel (mappa esplicita, mai l'intera prenotazione).
    func completePlaceholder(_ id: String, row: Reservation) async throws {
        var fields: [String: Any] = ["adults": row.adults, "children": row.children]
        fields["guestName"] = orNull(row.guestName)
        if let country = row.guestCountry { fields["guestCountry"] = country }
        try await db.collection("reservations").document(id).setData(fields, merge: true)
    }

    /// Merge con tutti i campi (i nulli cancellano il valore: come `set(reservation, merge)` dell'Android).
    func updateReservation(_ reservation: Reservation) async throws {
        try await db.collection("reservations").document(reservation.id).setData(reservation.firestoreData, merge: true)
    }

    func getReservations(propertyId: String, platform: String) async throws -> [Reservation] {
        decodeAll(try await db.collection("reservations")
            .whereField("propertyId", isEqualTo: propertyId)
            .whereField("platform", isEqualTo: platform)
            .getDocuments())
    }

    func getReservation(_ id: String) async throws -> Reservation? {
        let snapshot = try await db.collection("reservations").document(id).getDocument()
        return snapshot.exists ? decode(snapshot) : nil
    }

    /// Il segno «check-in inviato» della prenotazione (vedi `CheckinMark`), o nil.
    func getCheckinMark(_ reservationId: String) async throws -> CheckinMark? {
        let snapshot = try await db.collection("reservations").document(reservationId).getDocument()
        return CheckinMark.parse(snapshot.data()?["checkin"])
    }

    /// Scrive solo il campo `checkin`: nessun dato degli ospiti.
    func markCheckinSent(_ reservationId: String, guests: Int, now: Int64) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw CheckinMarkError.notSignedIn }
        try await db.collection("reservations").document(reservationId)
            .updateData(["checkin": ["sentAt": now, "guests": max(0, guests), "by": uid] as [String: Any]])
    }

    /// Elimina solo la prenotazione condivisa. Spese e importi locali li ripulisce `FinanceRepository` (orfani).
    func deleteReservation(_ id: String) async throws {
        try await db.collection("reservations").document(id).delete()
    }

    // MARK: Scorte

    func getInventory(propertyId: String) async throws -> [InventoryItem] {
        decodeAll(try await db.collection("inventory").whereField("propertyId", isEqualTo: propertyId).getDocuments())
    }

    func addInventoryItem(_ item: InventoryItem) async throws -> InventoryItem {
        let ref = db.collection("inventory").document()
        var created = item
        created.id = ref.documentID
        try await ref.setData(created.firestoreData)
        return created
    }

    func updateInventoryItem(_ item: InventoryItem) async throws {
        try await db.collection("inventory").document(item.id).setData(item.firestoreData)
    }

    /// Scrive solo l'URL della foto, senza bisogno dell'oggetto completo: se l'elenco in memoria è vuoto (processo
    /// riavviato) un update basato su di esso perderebbe l'immagine appena caricata.
    func updateInventoryImageUrl(itemId: String, imageUrl: String) async throws {
        try await db.collection("inventory").document(itemId).updateData(["imageUrl": imageUrl])
    }

    /// Cache dei nomi prodotto per codice a barre (evita di richiamare il servizio online due volte).
    func getCachedProductName(barcode: String) async -> String? {
        let snapshot = try? await db.collection("products_cache").document(barcode).getDocument()
        return snapshot?.data()?["name"] as? String
    }

    func saveProductToCache(barcode: String, name: String) async {
        let data: [String: Any] = ["name": name, "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]
        try? await db.collection("products_cache").document(barcode).setData(data)
    }

    /// Carica su Storage la foto di un articolo (JPEG già compresso). Ritorna l'URL, o nil in caso di errore.
    func uploadProductImage(itemId: String, jpeg: Data) async -> String? {
        do {
            let ref = Storage.storage().reference().child("inventory/\(itemId).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(jpeg, metadata: metadata)
            return try await ref.downloadURL().absoluteString
        } catch {
            return nil
        }
    }
}

/// Confermate/cancellate dell'ultimo import Booking di una casa (`BookingStats.ImportCounts` su Android).
struct BookingImportCounts: Equatable, Sendable {
    let confirmed: Int
    let cancelled: Int
}

/// Una prenotazione e se ha il segno `checkin`.
/// Le prenotazioni di una casa e se la lettura è venuta dalla cache (`getReservationsReportingCache`).
struct ReservationsPage: Sendable {
    let reservations: [Reservation]
    let fromCache: Bool
}

struct ReservationWithMark: Sendable {
    let reservation: Reservation
    let sent: Bool
}

/// Le prenotazioni di più case con gli id di quelle già inviate ad Alloggiati (Home, Agenda).
struct ReservationsWithCheckin: Sendable {
    var reservations: [Reservation] = []
    var checkinSentIds: Set<String> = []
}

enum CheckinMarkError: LocalizedError {
    case notSignedIn
    var errorDescription: String? { "Nessun utente connesso" }
}
