import FirebaseAuth
import Foundation
import Observation

/// Sessione di accesso. Firebase Auth salva la sessione nel Keychain: se c'è già un utente si entra
/// direttamente nell'app (come fa l'Android all'avvio).
/// TODO: Accedi con Apple (obbligatorio da App Store se si offre Google) e Google Sign-In.
@MainActor
@Observable
final class AuthService {
    private(set) var currentUser: User?
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        currentUser = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.currentUser = user }
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    var isSignedIn: Bool { currentUser != nil }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func register(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    /// Esce e svuota la sessione di accesso condivisa (un altro account non deve ereditare le case del precedente).
    /// TODO F3: uscire anche dall'account Google ricordato dal dispositivo, quando ci sarà il login Google.
    func signOut() throws {
        try Auth.auth().signOut()
        Task { await AccessSession.shared.invalidate() }
    }

    /// Messaggio in italiano per gli errori di Firebase Auth più comuni.
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) else {
            return error.localizedDescription
        }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound: return "Email o password non corretti."
        case .invalidEmail: return "Indirizzo email non valido."
        case .emailAlreadyInUse: return "Esiste già un account con questa email."
        case .weakPassword: return "La password è troppo debole (almeno 6 caratteri)."
        case .networkError: return "Nessuna connessione. Riprova."
        case .tooManyRequests: return "Troppi tentativi. Riprova tra poco."
        default: return error.localizedDescription
        }
    }
}
