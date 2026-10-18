import FirebaseAuth
import Foundation

/// Le case dell'utente loggato e cosa può farne, caricate una volta e condivise da tutte le schermate. Si invalida
/// quando cambia l'appartenenza (casa creata, invito usato, trasferimento) o l'utente esce.
actor AccessSession {
    static let shared = AccessSession()

    private var cached: AccessScope?

    func scope(forceRefresh: Bool = false, db: FirestoreService = FirestoreService()) async throws -> AccessScope {
        guard let user = Auth.auth().currentUser else { throw ServiceError(message: "Nessun utente connesso") }
        // Un'altra persona sullo stesso telefono non deve ereditare la sessione precedente.
        if !forceRefresh, let existing = cached, existing.uid == user.uid { return existing }

        let superAdmin = isSuperAdminAccount(email: user.email, emailVerified: user.isEmailVerified)
        let properties = superAdmin ? try await db.getAllProperties() : try await db.getMyProperties(uid: user.uid)
        let scope = AccessScope(uid: user.uid, isSuperAdmin: superAdmin, properties: properties)
        cached = scope
        return scope
    }

    func invalidate() { cached = nil }
}
