import SwiftUI

struct MainTabView: View {
    let scope: AccessScope?
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            ForEach(MainTabs.visible(for: scope)) { tab in
                NavigationStack {
                    content(for: tab)
                        .navigationTitle(tab.rawValue)
                }
                .tabItem { Label(tab.rawValue, systemImage: tab.systemImage) }
            }
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
        ContentUnavailableView(
            "\(feature): da portare",
            systemImage: "hammer",
            description: Text("Sorgente Android: \(androidSource). Vedi docs/MAPPA_PORTING.md.")
        )
    }
}
