import SwiftUI

/// Sottomenù Collaboratori delle impostazioni (`CollaboratorsScreen.kt`). Per le case di cui sei proprietario porta a
/// «Membri e inviti» (invitare, togliere, dare i permessi, passare la proprietà); per quelle in cui sei collaboratore porta al
/// tuo accesso (`HouseAccessView`: ruolo, permessi, «Lascia questa casa»).
struct CollaboratorsView: View {
    let scope: AccessScope?
    let onBack: () -> Void
    /// Apre «Membri e inviti»; nil lascia scegliere la casa dentro la schermata.
    let onMembers: (String?) -> Void
    let onHouseAccess: (String) -> Void

    var body: some View {
        let overview = collaboratorsOverview(scope)
        VStack(spacing: 0) {
            CompactTopBar(title: "Collaboratori", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    if overview.isEmpty {
                        Text("Non hai ancora nessuna casa. Quando ne crei una, o accetti un invito, qui potrai invitare e gestire i collaboratori.")
                            .appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                    }

                    if !overview.owned.isEmpty {
                        Text("Invita chi ti aiuta con la casa e scegli cosa può fare: prenotazioni, scorte e check-in, più, se vuoi, prezzi e sito.")
                            .appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                        Button {
                            onMembers(overview.owned.count == 1 ? overview.owned[0].propertyId : nil)
                        } label: {
                            Label("Invita un collaboratore", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appPrimary)

                        SectionLabel("Le tue case").padding(.top, Dimens.itemSpacing)
                        ForEach(overview.owned) { row in
                            NavRow(title: row.name, subtitle: "Membri, inviti e permessi") { onMembers(row.propertyId) }
                        }
                    }

                    if !overview.shared.isEmpty {
                        SectionLabel("Case in cui collabori").padding(.top, Dimens.itemSpacing)
                        ForEach(overview.shared) { row in
                            NavRow(
                                title: row.name,
                                subtitle: [row.roleLabel, row.permissionsText].compactMap { $0 }.joined(separator: " · ")
                            ) { onHouseAccess(row.propertyId) }
                        }
                    }
                }
                .frame(maxWidth: 400, alignment: .leading)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
