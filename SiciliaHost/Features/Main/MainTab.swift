import Foundation

enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case home = "Home"
    case agenda = "Agenda"
    case scorte = "Scorte"
    case finanze = "Finanze"
    case case_ = "Case"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .agenda: return "calendar"
        case .scorte: return "shippingbox"
        case .finanze: return "eurosign.circle"
        case .case_: return "building.2"
        }
    }
}

/// Quali schede mostra la barra principale (porting di `MainTabs.kt`): Home, Agenda e Scorte sempre;
/// Finanze se l'utente ha i permessi finanze su almeno una casa; Case per chi gestisce una casa,
/// per il collaboratore con permesso SITE e per il super-admin.
enum MainTabs {
    static func visible(for scope: AccessScope?) -> [MainTab] {
        var tabs: [MainTab] = [.home, .agenda, .scorte]
        guard let scope else { return tabs }
        if !scope.financeProperties.isEmpty { tabs.append(.finanze) }
        if scope.canSeeManagementTabs { tabs.append(.case_) }
        return tabs
    }

    /// L'editor dei prezzi compare in Agenda se almeno una casa con prezzi accessibili ha l'annuncio approvato.
    static func canEditPrices(_ scope: AccessScope?, approvedIds: Set<String>) -> Bool {
        scope?.priceProperties.contains { approvedIds.contains($0.id) } == true
    }
}
