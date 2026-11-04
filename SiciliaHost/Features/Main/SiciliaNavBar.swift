import SwiftUI

/// Barra di navigazione compatta in vetro (`SiciliaNavBar` dell'Android): pillola sfocata sopra il contenuto. Solo
/// icone: la voce attiva si allarga a mostrare l'etichetta, le altre restano quadrate. L'evidenziatore verde non salta:
/// scivola da una voce all'altra con una molla, e l'icona appena scelta fa un piccolo rimbalzo.
struct SiciliaNavBar: View {
    let tabs: [MainTab]
    @Binding var selected: MainTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                NavPill(tab: tab, isSelected: tab == selected, indicator: indicator) {
                    withAnimation(.slideSpring) { selected = tab }
                }
            }
            if AssistantController.shared.available {
                AssistantPill {
                    withAnimation(.spring(response: 0.35)) {
                        AssistantController.shared.open = true
                    }
                }
            }
        }
        .padding(4)
        .glass(Capsule(), elevation: 18)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
    }
}

private struct NavPill: View {
    let tab: MainTab
    let isSelected: Bool
    let indicator: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: Dimens.iconSmall, weight: .medium))
                    .symbolEffect(.bounce, value: isSelected) // rimbalzo dell'icona quando la voce diventa attiva
                if isSelected {
                    Text(tab.rawValue)
                        .appStyle(.labelLarge)
                        .lineLimit(1) // con testo grande l'etichetta si accorcia invece di spingere le altre fuori schermo
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(isSelected ? Theme.onPrimary : Theme.onSurfaceVariant)
            .padding(.horizontal, isSelected ? 12 : 11)
            .frame(minHeight: 40)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.primary)
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)))
                        .softShadow(6, color: Theme.primary)
                        .matchedGeometryEffect(id: "indicator", in: indicator)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(isSelected ? 0 : 1)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
