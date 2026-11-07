import Foundation

enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case home = "Home"
    case agenda = "Agenda"
    case scorte = "Scorte"
    case messaggi = "Messaggi"
    case finanze = "Finanze"
    case case_ = "Case"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .agenda: return "calendar"
        case .scorte: return "shippingbox"
        case .messaggi: return "bubble.left.and.bubble.right"
        case .finanze: return "eurosign.circle"
        case .case_: return "building.2"
        }
    }
}

/// Quali schede mostra la barra principale (porting di `MainTabs.kt`): Home, Agenda e Scorte sempre;
/// Finanze solo per il proprietario di almeno una casa (i soldi stanno sul suo telefono); Case per chi gestisce una casa,
/// per il collaboratore con permesso SITE e per il super-admin. Messaggi (dopo Scorte) solo se il server lo abilita
/// (`getMessagingStatus().host.enabled`: l'utente gestisce almeno una casa online sul sito) e le case sono caricate.
enum MainTabs {
    static func visible(for scope: AccessScope?, messagingEnabled: Bool = false) -> [MainTab] {
        var tabs: [MainTab] = [.home, .agenda, .scorte]
        guard let scope else { return tabs }
        if messagingEnabled { tabs.append(.messaggi) }
        if !scope.financeProperties.isEmpty { tabs.append(.finanze) }
        if scope.canSeeManagementTabs { tabs.append(.case_) }
        return tabs
    }

    /// L'editor dei prezzi compare in Agenda se almeno una casa con prezzi accessibili ha l'annuncio approvato.
    static func canEditPrices(_ scope: AccessScope?, approvedIds: Set<String>) -> Bool {
        scope?.priceProperties.contains { approvedIds.contains($0.id) } == true
    }
}
