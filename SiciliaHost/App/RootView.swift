import SwiftUI

/// Login oppure app, in base alla sessione Firebase; la presentazione iniziale sta sopra a tutto (come `IntroOverlay`
/// dell'Android in `MainActivity`).
struct RootView: View {
    @State private var auth = AuthService()

    var body: some View {
        ZStack {
            if let user = auth.currentUser {
                // `.id(uid)`: cambiando account lo stato del gate riparte da zero (su Android serviva la chiave
                // `main_<uid>` del ViewModel per lo stesso motivo). Ogni schermata ha il suo fondo ambiente pieno:
                // durante le transizioni le due non si mescolano.
                AppScreen {
                    MainGateView(user: user, onSignOut: { try? auth.signOut() })
                        .id(user.uid)
                }
            } else {
                LoginView(auth: auth)
            }
            // Invito in attesa (link o codice incollato): sopra all'app, sotto alla presentazione.
            InviteOverlay(uid: auth.currentUser?.uid)
            IntroOverlay(uid: auth.currentUser?.uid)
        }
        // Link `https://siciliahost.com/invito/CODICE` o `siciliahost://invito/CODICE`: il codice resta in memoria finché
        // l'utente non lo gestisce. Il ritorno del browser del login Google passa da qui.
        .onOpenURL { url in
            if AuthService.handle(url: url) { return }
            if let code = InviteLink.extractCode(url.absoluteString) { PendingInvite.shared.set(code) }
        }
    }
}
