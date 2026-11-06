import AuthenticationServices
import FirebaseAuth
import FirebaseFunctions
import GoogleSignIn
import Observation
import SwiftUI
import UIKit

/// Logica pura di "Elimina account" (testata in `AccountDeletionTests`).
enum AccountDeletionLogic {
    enum Provider: Equatable { case google, apple }

    /// Provider con cui rifare l'accesso prima dell'eliminazione: la Function `deleteMyAccount` vuole un login degli
    /// ultimi 5 minuti. Apple prima di Google: chi ha entrambi deve revocare anche il token Apple.
    static func provider(for providerIDs: [String]) -> Provider? {
        if providerIDs.contains("apple.com") { return .apple }
        if providerIDs.contains("google.com") { return .google }
        return nil
    }

    /// Messaggio quando l'utente è ancora proprietario di qualche casa (il server rifiuta con `owns-properties`).
    static func ownedHousesMessage(_ names: [String]) -> String {
        let list = names.filter { !$0.trimmed.isEmpty }
        let what = list.isEmpty ? "delle case" : (list.count == 1 ? "di «\(list[0])»" : "di " + list.map { "«\($0)»" }.joined(separator: ", "))
        return "Sei ancora proprietario \(what). Prima eliminale o cedile a un altro host dalla scheda della casa, poi elimina l'account."
    }

    /// Nomi delle case di cui l'utente è OWNER, per il controllo prima di chiedere il nuovo accesso.
    static func ownedHouseNames(_ scope: AccessScope?) -> [String] {
        guard let scope else { return [] }
        return scope.properties.filter { scope.isOwner($0) }.map(\.name)
    }

    /// Messaggio per un errore di `deleteMyAccount`.
    static func describe(code: String?, message: String?, details: Any?) -> String {
        if code == "FAILED_PRECONDITION" {
            let info = details as? [String: Any]
            if info?["reason"] as? String == "owns-properties" || message == "owns-properties" {
                return ownedHousesMessage(info?["properties"] as? [String] ?? [])
            }
            if message == "recent-login-required" { return "Per sicurezza accedi di nuovo e riprova." }
            if message == "Staff accounts cannot be deleted here" {
                return "Questo account ha un ruolo di amministrazione: scrivi a info@siciliahost.com per eliminarlo."
            }
        }
        switch code {
        case "UNAVAILABLE", "DEADLINE_EXCEEDED": return "Connessione assente o lenta: riprova."
        case "UNAUTHENTICATED": return "Sessione scaduta: esci, accedi di nuovo e riprova."
        case nil: return message ?? "Eliminazione non riuscita: riprova."
        default: return "Eliminazione non riuscita (\(code!)): riprova o scrivi a info@siciliahost.com."
        }
    }
}

/// "Elimina account" (Linee guida App Store 5.1.1(v)): nuovo accesso con lo stesso provider, revoca del token "Accedi con
/// Apple" (richiesta da Apple per chi lo usa), poi la callable `deleteMyAccount`, che cancella l'utente Firebase, il profilo e
/// le partecipazioni come collaboratore. Chi è proprietario di una casa viene fermato prima (anche dal server).
@MainActor
@Observable
final class AccountDeletionModel {
    private(set) var isBusy = false
    var error: String?

    /// Ritorna `true` se l'account è stato eliminato (chi chiama esce dall'app).
    func delete(scope: AccessScope?) async -> Bool {
        guard !isBusy else { return false }
        error = nil
        let owned = AccountDeletionLogic.ownedHouseNames(scope)
        if !owned.isEmpty {
            error = AccountDeletionLogic.ownedHousesMessage(owned)
            return false
        }
        guard let user = Auth.auth().currentUser,
              let provider = AccountDeletionLogic.provider(for: user.providerData.map(\.providerID)) else {
            error = "Sessione scaduta: esci, accedi di nuovo e riprova."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch provider {
            case .google:
                guard try await reauthenticateWithGoogle(user) else { return false }
            case .apple:
                guard let code = try await reauthenticateWithApple(user) else { return false }
                // Va fatto prima di cancellare l'utente: dopo il token Firebase non vale più.
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            }
            _ = try await Functions.functions().httpsCallable("deleteMyAccount").call([String: Any]())
            return true
        } catch {
            self.error = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if let code = functionsErrorCodeName(error) {
            return AccountDeletionLogic.describe(
                code: code, message: (error as NSError).localizedDescription, details: functionsErrorDetails(error)
            )
        }
        if (error as NSError).domain == AuthErrorDomain { return AuthService.describe(error) }
        return AccountDeletionLogic.describe(code: nil, message: nil, details: nil)
    }

    /// `false` se l'utente annulla.
    private func reauthenticateWithGoogle(_ user: User) async throws -> Bool {
        guard let presenter = Self.topViewController() else { throw AuthService.SignInError(message: "Impossibile aprire l'accesso con Google") }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthService.SignInError(message: "Errore: token Google non ricevuto")
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await user.reauthenticate(with: credential)
            return true
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            return false
        }
    }

    /// Ritorna il codice di autorizzazione Apple (per la revoca), o nil se l'utente annulla.
    private func reauthenticateWithApple(_ user: User) async throws -> String? {
        let nonce = AppleNonce.random()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = AppleNonce.sha256(nonce)
        let authorization: ASAuthorization
        do {
            authorization = try await AppleAuthorizationRunner().run(request)
        } catch let error as NSError where error.domain == ASAuthorizationError.errorDomain && error.code == ASAuthorizationError.canceled.rawValue {
            return nil
        }
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken, let idToken = String(data: tokenData, encoding: .utf8),
              let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
            throw AuthService.SignInError(message: "Errore: token Apple non ricevuto")
        }
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: nil)
        try await user.reauthenticate(with: credential)
        return code
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Esegue una richiesta "Accedi con Apple" senza il pulsante di sistema (serve per il nuovo accesso prima di eliminare).
@MainActor
private final class AppleAuthorizationRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    func run(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller // tiene vivo il controller (e se stesso, tramite il delegate) fino alla risposta
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

/// Sezione "Account" in fondo al Profilo e alla schermata senza case: "Segnala un problema" ed "Elimina account" (in rosso,
/// con conferma). `onDeleted` esce dall'app (come "Esci").
struct AccountActionsSection: View {
    let scope: AccessScope?
    let onDeleted: () -> Void

    @State private var model = AccountDeletionModel()
    @State private var confirming = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            NavRow(title: "Segnala un problema", subtitle: "Scrivi all'assistenza: aggiungiamo noi versione dell'app e modello del telefono") {
                if let url = SupportMail.url() { openURL(url) }
            }
            Button(role: .destructive) {
                model.error = nil
                confirming = true
            } label: {
                Text(model.isBusy ? "Eliminazione…" : "Elimina account")
                    .appStyle(.bodyLarge)
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Dimens.cardPadding)
                    .appCard()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            if let error = model.error {
                Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
            }
        }
        .confirmationDialog("Eliminare l'account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Elimina definitivamente", role: .destructive) {
                Task { if await model.delete(scope: scope) { onDeleted() } }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Cancelliamo il tuo accesso, il profilo e la partecipazione alle case di cui sei collaboratore. Non si può annullare. Ti chiederemo di accedere di nuovo per conferma.")
        }
    }
}

/// Email precompilata a info@siciliahost.com con versione dell'app e dispositivo.
enum SupportMail {
    static let address = "info@siciliahost.com"

    static func body(appVersion: String, build: String, device: String, system: String) -> String {
        "\n\n\n---\nApp: CactusHost \(appVersion) (\(build))\nDispositivo: \(device)\nSistema: iOS \(system)"
    }

    static func url() -> URL? {
        let info = Bundle.main.infoDictionary
        let text = body(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            device: deviceModel(),
            system: UIDevice.current.systemVersion
        )
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Segnalazione dall'app CactusHost"),
            URLQueryItem(name: "body", value: text),
        ]
        return components.url
    }

    /// Identificativo del modello (es. "iPhone16,2"), più preciso di `UIDevice.model` ("iPhone").
    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}
