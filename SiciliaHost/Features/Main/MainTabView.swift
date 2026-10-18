import SwiftUI

/// Schermata principale: sezioni sfogliabili con un gesto (come il pager dell'Android) sotto una barra di vetro
/// flottante. Le sezioni di primo livello non hanno intestazione, solo contenuto.
struct MainTabView: View {
    let scope: AccessScope?
    let onSignOut: () -> Void
    @State private var selected: MainTab = .home

    var body: some View {
        let tabs = MainTabs.visible(for: scope)
        ZStack(alignment: .bottom) {
            TabView(selection: $selected) {
                ForEach(tabs) { tab in
                    NavigationStack {
                        content(for: tab)
                            .toolbar(.hidden, for: .navigationBar)
                            // La barra flottante non deve coprire la fine delle liste.
                            .safeAreaPadding(.bottom, Dimens.bottomBarInset)
                    }
                    .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            SiciliaNavBar(tabs: tabs, selected: $selected)
                .padding(.bottom, 8)
        }
        .onChange(of: tabs) { _, newTabs in
            if !newTabs.contains(selected) { selected = .home }
        }
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home: HomeView(scope: scope, onSignOut: onSignOut)
        case .agenda: PlaceholderView(feature: "Agenda", androidSource: "ui/calendar, ui/reservation")
        case .scorte: PlaceholderView(feature: "Scorte", androidSource: "ui/inventory")
        case .finanze: PlaceholderView(feature: "Finanze", androidSource: "ui/finance")
        case .case_: PlaceholderView(feature: "Case", androidSource: "ui/cases, ui/site, ui/members")
        }
    }
}

/// Segnaposto per le schermate non ancora portate. Rimuoverlo schermata per schermata.
struct PlaceholderView: View {
    let feature: String
    let androidSource: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer")
                .font(.system(size: 28))
                .foregroundStyle(Theme.onSurfaceVariant)
            SectionLabel(feature)
            Text("Schermata da portare dall'app Android")
                .appStyle(.bodyMedium)
                .foregroundStyle(Theme.onSurface)
            Text(androidSource)
                .appStyle(.bodySmall)
                .foregroundStyle(Theme.onSurfaceVariant)
        }
        .multilineTextAlignment(.center)
        .padding(Dimens.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
