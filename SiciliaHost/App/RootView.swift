import SwiftUI

/// Login oppure app, in base alla sessione Firebase.
struct RootView: View {
    @State private var auth = AuthService()

    var body: some View {
        Group {
            if let user = auth.currentUser {
                // `.id(uid)`: cambiando account lo stato del gate riparte da zero (su Android serviva
                // la chiave `main_<uid>` del ViewModel per lo stesso motivo).
                MainGateView(user: user, onSignOut: { try? auth.signOut() })
                    .id(user.uid)
            } else {
                LoginView(auth: auth)
            }
        }
    }
}
