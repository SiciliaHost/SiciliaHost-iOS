import SwiftUI

/// Privacy e sicurezza (`PrivacySecurityScreen.kt`): cosa fa davvero l'app per i dati, più i link alle pagine legali del sito.
struct PrivacyView: View {
    let onBack: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Privacy e sicurezza", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    Text("Come SiciliaHost protegge i dati tuoi e dei tuoi ospiti.")
                        .appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                    ForEach(privacySections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                            Text(section.body).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Dimens.cardPadding)
                        .appCard()
                    }
                    HStack(spacing: Dimens.itemSpacing) {
                        Button("Informativa completa") { openURL(LegalLinks.privacy) }.buttonStyle(.appOutlined)
                        Button("Termini") { openURL(LegalLinks.terms) }.buttonStyle(.appOutlined)
                    }
                    .padding(.top, Dimens.itemSpacing)
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
