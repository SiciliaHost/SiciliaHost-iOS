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

/// Riprende la continuazione una sola volta (la prima che arriva tra il lavoro e il timeout).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}

@MainActor
@Observable
final class MainViewModel {
    private(set) var scope: AccessScope?
    private(set) var isLoading = true
    private(set) var hasFailed = false

    /// Un'azione dell'onboarding (crea casa, usa invito) è in corso.
    private(set) var isBusy = false
    private(set) var actionError: String?

    private let user: User
    private let db = FirestoreService()
    private let host = HostFunctionsService()

    init(user: User) { self.user = user }

    var access: AccessState { accessState(loading: isLoading, failed: hasFailed, scope: scope) }

    /// Profilo + trasferimenti di proprietà in sospeso + case dell'utente. Ripetibile (Riprova).
    func load() async {
        isLoading = true
        hasFailed = false
        do {
            _ = try await db.getOrCreateUserProfile(uid: user.uid, email: user.email ?? "")
            await claimPendingTransfers()
            scope = try await AccessSession.shared.scope(forceRefresh: true, db: db)
        } catch {
            hasFailed = true
        }
        isLoading = false
    }

    /// Invito accettato dalla schermata a tutto schermo: le case cambiano, si ricaricano senza riavviare. Con case già
    /// caricate l'aggiornamento è silenzioso (niente spinner, le sezioni restano dove sono); dall'onboarding si passa da
    /// `load()`, che porta alla schermata principale.
    func reloadAfterInvite() async {
        guard scope != nil else {
            await load()
            return
        }
        do {
            scope = try await AccessSession.shared.scope(forceRefresh: true, db: db)
        } catch {
            await load()
        }
    }

    /// Un trasferimento di proprietà fatto prima che questa persona avesse un account si completa qui, al primo
    /// accesso. Un errore non deve bloccare l'ingresso e una Function lenta non deve tenere l'utente sullo spinner: si
    /// aspetta al massimo 5 secondi, poi si prosegue (al prossimo avvio si riprova).
    private func claimPendingTransfers() async {
        let host = self.host
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task { _ = try? await host.claimPendingTransfers(); once.resume() }
            Task { try? await Task.sleep(for: .seconds(5)); once.resume() }
        }
    }

    func clearActionError() { actionError = nil }

    func showActionError(_ message: String) { actionError = message }
}
