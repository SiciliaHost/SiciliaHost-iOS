import FirebaseAuth
import SwiftUI

/// La presentazione, disegnata sopra la navigazione. Compare:
/// - alla prima apertura sul telefono, prima del login;
/// - dopo il login, una volta per account (`users/{uid}.introSeenAt`), se non è appena comparsa qui;
/// - su richiesta dal Profilo (`OnboardingController.introRequested`).
/// Chiudendola si segna vista sul telefono e, se c'è un utente, sul suo profilo.
struct IntroOverlay: View {
    let uid: String?
    private let db = FirestoreService()
    private var onboarding: OnboardingController { .shared }

    @State private var deviceSeen = IntroPrefs.introSeen()
    /// nil = profilo non ancora letto. Si rilegge a ogni cambio di account.
    @State private var accountSeen: Bool?

    var body: some View {
        let show = onboarding.introRequested
            || shouldShowIntro(signedIn: uid != nil, deviceSeen: deviceSeen, accountSeen: accountSeen, shownThisRun: onboarding.introShownThisRun)
        ZStack {
            if show {
                IntroScreen(onDone: done)
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: show)
        .task(id: uid) { await loadAccountFlag() }
    }

    private func loadAccountFlag() async {
        accountSeen = nil
        guard let uid else { return }
        do {
            accountSeen = try await db.getOnboardingFlags(uid).introSeen
        } catch {
            // Profilo illeggibile (offline, regole): meglio non mostrarla che mostrarla a ogni avvio.
            accountSeen = true
        }
        // Vista prima del login su questo telefono: vale anche per l'account appena entrato.
        if accountSeen == false && onboarding.introShownThisRun {
            await markAccount(uid)
            accountSeen = true
        }
    }

    private func done() {
        onboarding.introRequested = false
        onboarding.introShownThisRun = true
        IntroPrefs.markIntroSeen()
        deviceSeen = true
        if let uid, accountSeen != true {
            accountSeen = true
            Task { await markAccount(uid) }
        }
    }

    private func markAccount(_ uid: String) async {
        // Regole non ancora deployate o offline: si ripresenterà, nessun blocco.
        try? await db.markOnboarding(uid, field: .introSeenAt)
    }
}
