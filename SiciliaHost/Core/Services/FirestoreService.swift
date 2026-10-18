import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Un documento Firestore con un `id` che vale l'id del documento.
protocol FirestoreDocument: Decodable {
    var id: String { get set }
}

extension Property: FirestoreDocument {}
extension Reservation: FirestoreDocument {}
extension Expense: FirestoreDocument {}
extension RecurringExpense: FirestoreDocument {}
extension InventoryItem: FirestoreDocument {}
extension GuestRecord: FirestoreDocument {}
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
        created.alloggiatiConfigured = false
        var data = created.appFields
        data["members"] = created.members
        data["memberUids"] = created.memberUids
        data["createdBy"] = ownerUid
        data["alloggiatiConfigured"] = false
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

    // MARK: Credenziali Alloggiati (solo OWNER, vedi firestore.rules)

    func getAlloggiatiCredentials(_ propertyId: String) async throws -> AlloggiatiCredentials {
        let doc = try await db.collection("properties").document(propertyId)
            .collection("private").document("alloggiati").getDocument()
        let data = doc.data() ?? [:]
        return AlloggiatiCredentials(
            utente: data["wsUtente"] as? String ?? "",
            password: data["wsPassword"] as? String ?? "",
            wsKey: data["wsKey"] as? String ?? ""
        )
    }

    /// Scrive le credenziali e il flag `alloggiatiConfigured` della casa nello stesso batch.
    func saveAlloggiatiCredentials(_ propertyId: String, credentials: AlloggiatiCredentials) async throws {
        let propertyRef = db.collection("properties").document(propertyId)
        let batch = db.batch()
        batch.setData(
            ["wsUtente": credentials.utente, "wsPassword": credentials.password, "wsKey": credentials.wsKey],
            forDocument: propertyRef.collection("private").document("alloggiati")
        )
        batch.updateData(["alloggiatiConfigured": credentials.isConfigured], forDocument: propertyRef)
        try await batch.commit()
    }

    // MARK: Elenchi per più case (una query per casa, vedi fanOut)

    func getReservations(propertyIds: [String]) async throws -> [Reservation] {
        try await fanOut(propertyIds) { id in
            decodeAll(try await db.collection("reservations").whereField("propertyId", isEqualTo: id).getDocuments())
        }
    }

    func getExpenses(propertyIds: [String]) async throws -> [Expense] {
        try await fanOut(propertyIds) { id in
            decodeAll(try await db.collection("expenses").whereField("propertyId", isEqualTo: id).getDocuments())
        }
    }

    func getRecurringExpenses(propertyIds: [String]) async throws -> [RecurringExpense] {
        try await fanOut(propertyIds) { id in
            decodeAll(try await db.collection("recurring_expenses").whereField("propertyId", isEqualTo: id).getDocuments())
        }
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

    /// Aggiunge/aggiorna solo `fields` di una prenotazione esistente (merge; `propertyId` non cambia).
    func mergeReservationFields(_ id: String, fields: [String: Any]) async throws {
        try await db.collection("reservations").document(id).setData(fields, merge: true)
    }

    /// Usa `icalUid` come id del documento (dedup): stesso evento iCal = stesso documento, mai duplicati anche
    /// se la sincronizzazione gira più volte sullo stesso evento. Ritorna i soli documenti creati ora (o
    /// completati con un importo che mancava): serve a chi importa prezzi già noti (import Excel Booking) per
    /// creare la spesa biancheria una volta sola per prenotazione.
    func syncIcalReservationsBatch(_ reservations: [Reservation]) async throws -> [Reservation] {
        if reservations.isEmpty { return [] }

        let withIds: [(docId: String, res: Reservation)] = reservations.map {
            ($0.icalUid ?? db.collection("reservations").document().documentID, $0)
        }

        // Quali documenti esistono già, per non sovrascrivere un importo/`needsReview` impostato a mano a ogni
        // sincronizzazione. Una lettura per id non si può fare (le regole rifiutano i documenti inesistenti) e un
        // `whereIn` sull'id non ha `propertyId`: si legge l'elenco di ciascuna casa coinvolta e si confrontano gli id.
        var existingIds = Set<String>()
        var existingWithoutGross = Set<String>()
        let wantedIds = Set(withIds.map { $0.docId })
        var seenProperties = Set<String>()
        for propertyId in withIds.map({ $0.res.propertyId }) where seenProperties.insert(propertyId).inserted {
            let snapshot = try await db.collection("reservations").whereField("propertyId", isEqualTo: propertyId).getDocuments()
            for doc in snapshot.documents where wantedIds.contains(doc.documentID) {
                existingIds.insert(doc.documentID)
                if (doc.data()["grossAmount"] as? NSNumber) == nil { existingWithoutGross.insert(doc.documentID) }
            }
        }

        var newlyInserted: [Reservation] = []
        for start in stride(from: 0, to: withIds.count, by: 500) {
            let chunk = withIds[start ..< min(start + 500, withIds.count)]
            let batch = db.batch()
            for (docId, res) in chunk {
                let ref = db.collection("reservations").document(docId)
                if existingIds.contains(docId) {
                    // Già esistente: aggiorna solo i campi che arrivano dalla piattaforma, senza toccare
                    // importi e `needsReview`.
                    var updates: [String: Any] = [
                        "guestName": orNull(res.guestName),
                        "checkIn": res.checkIn,
                        "checkOut": res.checkOut,
                        "platform": res.platform,
                        "propertyId": res.propertyId,
                    ]
                    // Eccezione: se il documento non ha ancora un importo (import precedente fallito a metà, o
                    // creato senza prezzo) e questa riga lo porta (Excel Booking), lo si completa.
                    if existingWithoutGross.contains(docId), let gross = res.grossAmount {
                        updates["grossAmount"] = gross
                        updates["netAmountOwner"] = orNull(res.netAmountOwner)
                        updates["netAmountAdmin"] = orNull(res.netAmountAdmin)
                        updates["needsReview"] = false
                        updates["adults"] = res.adults
                        updates["children"] = res.children
                        var completed = res
                        completed.id = docId
                        newlyInserted.append(completed)
                    }
                    // Dati statistici dell'export Booking: un nuovo import li aggiunge anche alle prenotazioni già
                    // salvate. Mai sovrascritti con null.
                    if let v = res.bookedAt { updates["bookedAt"] = v }
                    if let v = res.guestCountry { updates["guestCountry"] = v }
                    if let v = res.travelPurpose { updates["travelPurpose"] = v }
                    if let v = res.bookingDevice { updates["bookingDevice"] = v }
                    if let v = res.commissionAmount { updates["commissionAmount"] = v }
                    if res.adults > 0 && updates["adults"] == nil {
                        updates["adults"] = res.adults
                        updates["children"] = res.children
                    }
                    batch.setData(updates, forDocument: ref, merge: true)
                } else {
                    var created = res
                    created.id = docId
                    batch.setData(created.firestoreData, forDocument: ref)
                    newlyInserted.append(created)
                }
            }
            try await batch.commit()
        }
        return newlyInserted
    }

    /// Rubrica marketing (import Excel Booking). Telefono come id: dedup naturale su un secondo soggiorno
    /// dello stesso ospite, più affidabile del nome (nel file arriva in formati incoerenti).
    func saveContactsBatch(_ contacts: [Contact]) async throws {
        let valid = contacts.filter { !$0.phone.trimmed.isEmpty }
        for start in stride(from: 0, to: valid.count, by: 500) {
            let batch = db.batch()
            for contact in valid[start ..< min(start + 500, valid.count)] {
                batch.setData(contact.firestoreData, forDocument: db.collection("contacts").document(contact.phone))
            }
            try await batch.commit()
        }
    }

    func getPendingReviewReservations(propertyId: String) async throws -> [Reservation] {
        decodeAll(try await db.collection("reservations")
            .whereField("propertyId", isEqualTo: propertyId)
            .whereField("needsReview", isEqualTo: true)
            .getDocuments())
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

    /// Elimina la prenotazione e, se `withExpenses`, le spese collegate (es. i 20 € biancheria) in un unico batch.
    /// Le spese si leggono e si cancellano solo con il permesso sulle finanze (proprietario): per un collaboratore
    /// si passa `withExpenses = false`, e le spese rimaste senza prenotazione le elimina la schermata Finanze.
    func deleteReservationWithExpenses(reservationId: String, propertyId: String, withExpenses: Bool) async throws {
        let batch = db.batch()
        if withExpenses {
            let expenses = try await db.collection("expenses")
                .whereField("propertyId", isEqualTo: propertyId)
                .whereField("reservationId", isEqualTo: reservationId)
                .getDocuments()
            for doc in expenses.documents { batch.deleteDocument(doc.reference) }
        }
        batch.deleteDocument(db.collection("reservations").document(reservationId))
        try await batch.commit()
    }

    // MARK: Spese

    /// Elimina spese per id (batch da 500). Solo chi gestisce le finanze della casa può farlo.
    func deleteExpenses(_ ids: [String]) async throws {
        for start in stride(from: 0, to: ids.count, by: 500) {
            let batch = db.batch()
            for id in ids[start ..< min(start + 500, ids.count)] {
                batch.deleteDocument(db.collection("expenses").document(id))
            }
            try await batch.commit()
        }
    }

    func addExpense(_ expense: Expense) async throws {
        let ref = db.collection("expenses").document()
        var created = expense
        created.id = ref.documentID
        try await ref.setData(created.firestoreData)
    }

    /// Spesa con id scelto dal chiamante (spese generate dalle fisse mensili: id deterministico).
    func setExpense(_ expense: Expense) async throws {
        try await db.collection("expenses").document(expense.id).setData(expense.firestoreData)
    }

    // MARK: Spese fisse mensili

    func addRecurringExpense(_ expense: RecurringExpense) async throws {
        let ref = db.collection("recurring_expenses").document()
        var created = expense
        created.id = ref.documentID
        try await ref.setData(created.firestoreData)
    }

    /// Elimina la definizione; le spese già generate restano nel registro.
    func deleteRecurringExpense(_ id: String) async throws {
        try await db.collection("recurring_expenses").document(id).delete()
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

    // MARK: Ospiti (Alloggiati)

    /// `propertyId` obbligatorio: le regole lo usano per decidere l'accesso e rifiutano la query senza.
    func getGuestRecords(propertyId: String, reservationId: String) async throws -> [GuestRecord] {
        decodeAll(try await db.collection("guest_records")
            .whereField("propertyId", isEqualTo: propertyId)
            .whereField("reservationId", isEqualTo: reservationId)
            .getDocuments())
    }

    func saveGuestRecord(_ record: GuestRecord) async throws -> GuestRecord {
        if record.id.isEmpty {
            let ref = db.collection("guest_records").document()
            var created = record
            created.id = ref.documentID
            try await ref.setData(created.firestoreData)
            return created
        }
        try await db.collection("guest_records").document(record.id).setData(record.firestoreData)
        return record
    }

    func deleteGuestRecord(_ id: String) async throws {
        try await db.collection("guest_records").document(id).delete()
    }

    func markGuestRecordSent(_ id: String, error: String? = nil) async throws {
        try await db.collection("guest_records").document(id).updateData([
            "schedInaSent": error == nil,
            "sendTimestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sendError": orNull(error),
        ])
    }
}

/// Confermate/cancellate dell'ultimo import Booking di una casa (`BookingStats.ImportCounts` su Android).
struct BookingImportCounts: Equatable, Sendable {
    let confirmed: Int
    let cancelled: Int
}
