import SwiftUI

/// La casa di cui si mostra il calendario da esportare (per `.sheet(item:)`).
struct CalendarHouse: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Il calendario di una casa da incollare su Airbnb e Booking (`IcalExport.url`, `IcalExportDialog.kt`): spiega cosa
/// contiene e dove si incolla, e lascia copiare o condividere l'indirizzo. Il contenuto lo decide la Function
/// `exportIcalFeed` del sito.
struct IcalExportSheet: View {
    let house: CalendarHouse
    let onClose: () -> Void

    @State private var copied = false

    private var url: String { IcalExport.url(propertyId: house.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calendario di \(house.name)").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
                Text("Incolla questo indirizzo su Airbnb e su Booking: le date prenotate su siciliahost.com e quelle che blocchi su SiciliaHost si chiudono da sole anche lì. Le chiusure fatte direttamente su Airbnb o Booking restano su quel portale.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                Text(url)
                    .appStyle(.bodyMedium).foregroundStyle(Theme.primary)
                    .textSelection(.enabled)
                Text("Airbnb: Calendario → Disponibilità → Sincronizza calendari → Importa calendario.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                Text("Booking: Tariffe e disponibilità → Sincronizza calendari → Aggiungi calendario.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                Text("I portali aggiornano il calendario ogni poche ore: una nuova prenotazione non si vede subito.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)

                Button(copied ? "Link copiato" : "Copia il link") {
                    UIPasteboard.general.string = url
                    copied = true
                }
                .buttonStyle(.appPrimary)
                .frame(maxWidth: .infinity)
                ShareLink(item: url) {
                    Label("Condividi", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.appOutlined)
                Button("Chiudi", action: onClose).buttonStyle(.appText)
            }
            .padding(Dimens.screenPadding + 4)
        }
        .presentationDetents([.large])
    }
}
