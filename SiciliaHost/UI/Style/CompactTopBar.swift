import SwiftUI

/// Intestazione compatta per le schermate di secondo livello (`ui/common/CompactTopBar.kt`). Le sezioni principali non
/// hanno intestazione: il contenuto parte dall'alto. Qui serve il ritorno indietro, quindi resta una riga sola alta
/// `Dimens.controlHeight`. `actions` finisce a destra sulla stessa riga. Rispetta l'area sicura (isola, notch).
struct CompactTopBar<Actions: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    init(title: String, onBack: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.onBack = onBack
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 2) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Dimens.iconSmall, weight: .semibold))
                        .frame(width: Dimens.controlHeight, height: Dimens.controlHeight)
                }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Indietro")
            }
            Text(title)
                .appStyle(.titleSmall)
                .foregroundStyle(Theme.onSurface)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, onBack == nil ? 8 : 0)
                .accessibilityAddTraits(.isHeader)
            actions()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

extension CompactTopBar where Actions == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil) {
        self.init(title: title, onBack: onBack, actions: { EmptyView() })
    }
}

extension View {
    /// Limita il Dynamic Type per un sotto-albero con geometria fissa (es. le celle quadrate del calendario), dove il
    /// testo non può far crescere il contenitore (`CappedFontScale`, default 1,3×). Il resto dell'app rispetta la
    /// dimensione scelta dall'utente.
    func cappedFontScale(_ maxSize: DynamicTypeSize = .xxLarge) -> some View {
        dynamicTypeSize(...maxSize)
    }
}
