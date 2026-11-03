import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Contenuti del sito sul documento condiviso `properties/{id}`. Letture dirette da Firestore; scritture solo
/// tramite la callable `upsertProperty` (allow-list e validazione lato server).
struct SiteContentService: @unchecked Sendable {
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let storage = Storage.storage()

    /// I contenuti del sito delle sole case indicate (quelle che l'utente gestisce).
    func getProperties(_ propertyIds: [String]) async throws -> [PropertySiteContent] {
        try await fanOut(propertyIds) { id in
            let doc = try await db.collection("properties").document(id).getDocument()
            guard var content = try? doc.data(as: PropertySiteContent.self) else { return [] }
            if content.id.isEmpty { content.id = doc.documentID }
            return [content]
        }
    }

    func upsert(propertyId: String, patch: [String: Any?]) async throws {
        var payload: [String: Any] = patch.mapValues { (value: Any?) -> Any in plainCallableValue(value ?? NSNull()) }
        payload["id"] = propertyId
        _ = try await functions.httpsCallable("upsertProperty").call(payload)
    }

    /// Carica una foto della casa (JPEG già ridimensionato) e ne ritorna l'URL.
    func uploadPhoto(propertyId: String, jpeg: Data) async throws -> String {
        let ref = storage.reference().child("properties/\(propertyId)/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpeg, metadata: metadata)
        return try await ref.downloadURL().absoluteString
    }

    /// Best effort: l'URL è già stato tolto dalla scheda, un file orfano in Storage non è grave.
    func deletePhoto(url: String) async {
        try? await storage.reference(forURL: url).delete()
    }
}

/// Toglie gli `AnyHashable` (usati dalle bozze per confrontare le patch) da dizionari e liste prima di passarli all'SDK
/// delle Functions, che serializza solo tipi Foundation.
func plainCallableValue(_ value: Any) -> Any {
    if type(of: value) == AnyHashable.self, let hashable = value as? AnyHashable { return plainCallableValue(hashable.base) }
    if let dict = value as? [String: Any] { return dict.mapValues(plainCallableValue) }
    if let list = value as? [Any] { return list.map(plainCallableValue) }
    return value
}
