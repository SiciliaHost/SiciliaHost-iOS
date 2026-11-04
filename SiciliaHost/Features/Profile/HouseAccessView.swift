import SwiftUI

/// Ruolo e permessi su una casa (`HouseAccessScreen.kt`): al proprietario "Membri e inviti", al collaboratore "Lascia questa casa".
struct HouseAccessView: View {
    let propertyId: String
    let onBack: () -> Void
    let onOpenMembers: () -> Void
    /// L'utente è uscito dalla casa: si torna alla schermata principale.
    let onLeft: () -> Void

    @State private var model = HouseAccessModel()
    @State private var confirmLeave = false

    var body: some View {
        let property = model.property
        VStack(spacing: 0) {
            CompactTopBar(
                title: (property?.name.trimmed.isEmpty == false ? property?.name : nil) ?? "Casa",
                onBack: onBack
            )
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    if let scope = model.scope, let property {
                        VStack(alignment: .leading, spacing: 10) {
                            fact("Il tuo ruolo", houseRoleLabel(scope, property))
                            if canLeaveHouse(scope, property) {
                                fact("I tuoi permessi", permissionsSummary(property.permissionsOf(scope.uid)))
                            }
                            if let owner = model.ownerLabel { fact("Proprietario", owner) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Dimens.cardPadding)
                        .appCard()

                        if canManageMembers(scope, property) {
                            Button("Membri e inviti", action: onOpenMembers).buttonStyle(.appOutlined)
                            Text("Per lasciare questa casa devi prima trasferirla a un altro proprietario.")
                                .appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                        }
                        if canLeaveHouse(scope, property) {
                            Button("Lascia questa casa") { confirmLeave = true }
                                .buttonStyle(.appOutlined)
                                .disabled(model.isBusy)
                        }
                    } else if model.isLoading {
                        Text("Caricamento…").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                    }
                    if model.error != nil, property == nil, !model.isLoading {
                        Button("Riprova") { Task { await model.load(propertyId) } }.buttonStyle(.appOutlined)
                    }
                    if let error = model.error {
                        Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error)
                    }
                }
                .frame(maxWidth: 400, alignment: .leading)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: propertyId) { await model.load(propertyId) }
        .onChange(of: model.left) { _, left in if left { onLeft() } }
        .alert("Lasciare \(property?.name.trimmed.isEmpty == false ? property!.name : "questa casa")?", isPresented: $confirmLeave) {
            Button("Lascia", role: .destructive) { Task { await model.leave() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Non vedrai più prenotazioni, scorte e check-in di questa casa. Per rientrare servirà un nuovo invito.")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
            Text(value).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).lineLimit(3)
        }
    }
}
