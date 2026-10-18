import SwiftUI

// Card e campi dell'app (`ui/style/Surfaces.kt`, `SelectField.kt`).

private struct AppCardModifier: ViewModifier {
    let container: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = roundedShape(cornerRadius)
        content
            .background(shape.fill(container))
            .clipShape(shape)
            // Profondità: filo di luce sul bordo e ombra morbida invece della card piatta.
            .overlay(shape.strokeBorder(glassBorder(dark: scheme == .dark), lineWidth: 1))
            .softShadow(3)
    }
}

extension View {
    /// Card con profondità sul fondo ambiente. Il contenuto porta il suo padding (`Dimens.cardPadding`).
    func appCard(container: Color = Theme.surfaceContainerLow, cornerRadius: CGFloat = Radius.medium) -> some View {
        modifier(AppCardModifier(container: container, cornerRadius: cornerRadius))
    }
}

/// Occhiello di sezione: maiuscolo molto spaziato, come "RENTAL HOMES" sotto il marchio.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .appStyle(.labelSmall)
            .foregroundStyle(Theme.onSurfaceVariant)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Scelta di UNA voce da un elenco (casa, host, categoria, periodo…): campo con l'opzione scelta e la freccia, menù con
/// la spunta sull'opzione attiva. Da usare al posto di chip, schede o radio quando si sceglie una voce tra tante.
struct SelectField<Option: Hashable>: View {
    let label: String
    let options: [Option]
    let selected: Option?
    let optionLabel: (Option) -> String
    let onSelect: (Option) -> Void
    var placeholder = "Scegli…"
    var systemImage: String?

    var body: some View {
        let shape = roundedShape(Radius.button)
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == selected {
                        Label(optionLabel(option), systemImage: "checkmark")
                    } else {
                        Text(optionLabel(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(Theme.onSurfaceVariant)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                    Text(selected.map(optionLabel) ?? placeholder)
                        .appStyle(.bodyLarge)
                        .foregroundStyle(selected == nil ? Theme.onSurfaceVariant : Theme.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(shape.fill(Theme.surfaceContainerLowest.opacity(0.6)))
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Il marchio (cactus + scritta) dalle risorse dell'app, ritagliato ai margini.
struct BrandLogo: View {
    var height: CGFloat = 150

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Sicilia Host")
    }
}
