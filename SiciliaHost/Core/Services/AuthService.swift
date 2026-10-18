import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import UIKit

/// Sessione di accesso. Firebase Auth salva la sessione nel Keychain: se c'è già un utente si entra direttamente
/// nell'app (come fa l'Android all'avvio).
///
/// **Solo Google.** Le firestore.rules, le storage.rules e le Cloud Functions ammettono come "host" solo chi ha
/// effettuato l'accesso con Google (`sign_in_provider == 'google.com'`): un account email/password o Apple verrebbe
/// rifiutato da tutto. Per questo qui non c'è l'accesso con email. Accedi con Apple è in attesa di una decisione:
/// vedi DIARIO.md ("Accesso con Apple").
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

    struct SignInError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Accesso con Google. Ritorna `false` se l'utente ha annullato (nessun messaggio da mostrare, come l'Android
    /// con il codice 12501), `true` se è entrato.
    @discardableResult
    func signInWithGoogle() async throws -> Bool {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw SignInError(message: "Configurazione Google mancante (GoogleService-Info.plist)")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = Self.topViewController() else {
            throw SignInError(message: "Impossibile aprire l'accesso con Google")
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw SignInError(message: "Errore: token Google non ricevuto")
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
            return true
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            return false
        }
    }

    /// Esce da Firebase e anche dall'account Google ricordato dal dispositivo: senza, il prossimo "Accedi con Google"
    /// rientra in silenzio con lo stesso account e non permette di cambiarlo. Svuota la sessione di accesso condivisa
    /// (un altro account non deve ereditare le case del precedente).
    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        Task { await AccessSession.shared.invalidate() }
    }

    /// Ritorno dal browser del login Google (e altri URL: i link d'invito li gestisce `InviteLinkHandler`).
    @discardableResult
    static func handle(url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }

    /// Messaggio in italiano per gli errori di Firebase Auth più comuni.
    static func describe(_ error: Error) -> String {
        if let signIn = error as? SignInError { return signIn.message }
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) else {
            return error.localizedDescription
        }
        switch code {
        case .networkError: return "Nessuna connessione. Riprova."
        case .tooManyRequests: return "Troppi tentativi. Riprova tra poco."
        case .userDisabled: return "Questo account è stato disattivato."
        case .credentialAlreadyInUse, .accountExistsWithDifferentCredential: return "Esiste già un account con questa email."
        default: return error.localizedDescription
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
