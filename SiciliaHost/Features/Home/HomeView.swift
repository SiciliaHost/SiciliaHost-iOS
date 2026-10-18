import SwiftUI

/// Per ora mostra solo le case dell'utente (verifica end-to-end di login + accesso).
/// TODO: porting di `ui/dashboard` (prenotazioni di oggi, da completare, check-in).
struct HomeView: View {
    let scope: AccessScope?
    let onSignOut: () -> Void

    var body: some View {
        List {
            Section(scope?.profileLabel ?? "") {
                ForEach(scope?.properties ?? []) { property in
                    VStack(alignment: .leading) {
                        Text(property.name)
                        if let scope, !scope.canOperate(property) {
                            Text("Solo visibile").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Esci", role: .destructive, action: onSignOut)
            }
        }
    }
}
