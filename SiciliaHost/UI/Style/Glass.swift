import SwiftUI

// Stile "vetro e profondità" (`ui/style/Glass.kt`): superfici sfocate con una tinta del tema, un filo di luce sul
// bordo e un'ombra morbida. Su iOS la sfocatura è il materiale di sistema (`.ultraThinMaterial`), che sfoca ciò che
// scorre sotto la barra senza bisogno di una libreria.

/// Il filo di luce sul bordo del vetro: più chiaro in alto, quasi invisibile in basso.
func glassBorder(dark: Bool) -> LinearGradient {
    let top = dark ? 0.22 : 0.70
    let bottom = dark ? 0.04 : 0.15
    return LinearGradient(colors: [.white.opacity(top), .white.opacity(bottom)], startPoint: .top, endPoint: .bottom)
}

private struct SoftShadowModifier: ViewModifier {
    let elevation: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        content
            // Ombra morbida e ampia (colore d'inchiostro, non nero puro): un'ambientale larga e una più netta.
            .shadow(color: color.opacity(0.18), radius: elevation * 0.9, x: 0, y: elevation * 0.25)
            .shadow(color: color.opacity(0.28), radius: elevation * 0.4, x: 0, y: elevation * 0.4)
    }
}

extension View {
    /// Ombra morbida delle superfici flottanti.
    func softShadow(_ elevation: CGFloat, color: Color = Color(hex: Brand.ink)) -> some View {
        modifier(SoftShadowModifier(elevation: elevation, color: color))
    }
}

private struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let elevation: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Theme.surfaceContainerHigh.opacity(dark ? 0.55 : 0.62)))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(glassBorder(dark: dark), lineWidth: 1))
            .softShadow(elevation)
    }
}

extension View {
    /// Superficie di vetro: sfocatura di ciò che sta dietro, tinta, bordo luminoso e ombra morbida.
    func glass<S: InsettableShape>(_ shape: S, elevation: CGFloat = 14) -> some View {
        modifier(GlassModifier(shape: shape, elevation: elevation))
    }
}

/// Pannello di vetro per gli elementi a sé stanti (fogli, menù personalizzati): tinta quasi piena, bordo luminoso e
/// ombra, perché dietro non c'è niente di abbastanza interessante da sfocare.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = Radius.dialog
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = roundedShape(cornerRadius)
        let dark = scheme == .dark
        content()
            .foregroundStyle(Theme.onSurface)
            .background(shape.fill(Theme.surfaceContainerHigh.opacity(dark ? 0.92 : 0.95)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(glassBorder(dark: dark), lineWidth: 1))
            .softShadow(24)
    }
}
