import FirebaseAuth
import Foundation
import Observation

/// Cosa mostrare dopo il login (porting di `AccessState.kt`).
enum AccessState { case loading, failed, noHouses, ready }

func accessState(loading: Bool, failed: Bool, scope: AccessScope?) -> AccessState {
    if loading { return .loading }
    guard let scope, !failed else { return .failed }
    return scope.properties.isEmpty ? .noHouses : .ready
}

@MainActor
@Observable
final class MainViewModel {
    private(set) var scope: AccessScope?
    private(set) var isLoading = true
    private(set) var hasFailed = false

    private let user: User
    private let db = FirestoreService()

    init(user: User) { self.user = user }

    var access: AccessState { accessState(loading: isLoading, failed: hasFailed, scope: scope) }

    /// Carica profilo e case dell'utente. Il super-admin vede tutte le case.
    func load() async {
        isLoading = true
        hasFailed = false
        do {
            let email = user.email ?? ""
            _ = try await db.getOrCreateUserProfile(uid: user.uid, email: email)
            let superAdmin = isSuperAdminAccount(email: user.email, emailVerified: user.isEmailVerified)
            let properties = superAdmin
                ? try await db.getAllProperties()
                : try await db.getMyProperties(uid: user.uid)
            scope = AccessScope(uid: user.uid, isSuperAdmin: superAdmin, properties: properties)
        } catch {
            hasFailed = true
        }
        isLoading = false
    }
}
