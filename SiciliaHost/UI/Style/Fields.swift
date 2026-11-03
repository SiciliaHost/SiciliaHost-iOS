import SwiftUI

// Campi dei moduli (equivalente di `OutlinedTextField` dell'Android con etichetta e testo di aiuto), stessa forma di
// `SelectField`: fondo leggero, bordo, raggio dei pulsanti. Il bordo diventa rosso con un errore.

/// Contenitore di un campo: etichetta piccola sopra il valore, testo di aiuto o errore sotto.
struct FieldFrame<Content: View, Trailing: View>: View {
    let label: String
    var supporting: String?
    var error: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let shape = roundedShape(Radius.button)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).appStyle(.bodySmall).foregroundStyle(error == nil ? Theme.onSurfaceVariant : Theme.error)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(shape.fill(Theme.surfaceContainerLowest.opacity(0.6)))
            .overlay(shape.strokeBorder(error == nil ? Theme.outline : Theme.error, lineWidth: 1))
            if let text = error ?? supporting {
                Text(text)
                    .appStyle(.bodySmall)
                    .foregroundStyle(error == nil ? Theme.onSurfaceVariant : Theme.error)
                    .padding(.horizontal, 14)
            }
        }
    }
}

extension FieldFrame where Trailing == EmptyView {
    init(label: String, supporting: String? = nil, error: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: label, supporting: supporting, error: error, content: content, trailing: { EmptyView() })
    }
}

/// Campo di testo con etichetta.
struct AppTextField: View {
    let label: String
    @Binding var text: String
    var supporting: String?
    var error: String?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        FieldFrame(label: label, supporting: supporting, error: error) {
            TextField("", text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .appStyle(.bodyLarge)
                .foregroundStyle(Theme.onSurface)
                .accessibilityLabel(label)
        }
    }
}

/// Campo data in sola lettura che apre il selettore del giorno (come il campo con l'icona calendario dell'Android).
struct AppDateField: View {
    let label: String
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FieldFrame(label: label) {
                Text(text).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface)
            } trailing: {
                Image(systemName: "calendar").foregroundStyle(Theme.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(text)")
        .accessibilityHint("Scegli la data")
    }
}
