import SwiftUI

// Pulsanti dell'app (`ui/style/Buttons.kt`). In comune: alla pressione rientrano con una molla (0,95) e tornano con
// un piccolo rimbalzo, e danno una vibrazione leggera. Si usano con `.buttonStyle(.appPrimary)` ecc.

/// Pulsante pieno: gradiente verticale del colore del contenitore (più chiaro in alto, come una superficie
/// illuminata dall'alto) e ombra morbida della stessa tinta. Disabilitato = piatto e spento.
struct AppPrimaryButtonStyle: ButtonStyle {
    var container: Color = Theme.primary
    var content: Color = Theme.onPrimary
    var cornerRadius: CGFloat = Radius.button
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = roundedShape(cornerRadius)
        configuration.label
            .appStyle(.labelLarge)
            .foregroundStyle(isEnabled ? content : Theme.onSurface.opacity(0.38))
            .padding(.horizontal, 20)
            .frame(minHeight: Dimens.controlHeight)
            .background {
                if isEnabled {
                    shape.fill(container)
                        // Più chiaro in alto (18% di bianco), come una superficie illuminata dall'alto.
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)))
                        .softShadow(8, color: container)
                } else {
                    shape.fill(Theme.onSurface.opacity(0.12))
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
            .animation(.pressSpring, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Pulsante secondario in vetro: tinta di superficie traslucida e filo di luce sul bordo.
struct AppOutlinedButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Radius.button
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = roundedShape(cornerRadius)
        configuration.label
            .appStyle(.labelLarge)
            .foregroundStyle(isEnabled ? Theme.primary : Theme.onSurface.opacity(0.38))
            .padding(.horizontal, 20)
            .frame(minHeight: Dimens.controlHeight)
            .background(shape.fill(Theme.surfaceContainerHighest.opacity(0.55)))
            .overlay(
                shape.strokeBorder(
                    isEnabled
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.primary.opacity(0.55), Theme.outline.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Theme.outlineVariant),
                    lineWidth: 1
                )
            )
            .contentShape(shape)
            .softShadow(isEnabled ? 4 : 0)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
            .animation(.pressSpring, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Pulsante di solo testo.
struct AppTextButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appStyle(.labelLarge)
            .foregroundStyle(isEnabled ? color : Theme.onSurface.opacity(0.38))
            .padding(.horizontal, 12)
            .frame(minHeight: Dimens.controlHeight)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
            .animation(.pressSpring, value: configuration.isPressed)
    }
}

/// Pulsante con la sola icona: rientra di più (0,85).
struct AppIconButtonStyle: ButtonStyle {
    var color: Color = Theme.onSurfaceVariant
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? color : Theme.onSurface.opacity(0.38))
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && isEnabled ? 0.85 : 1)
            .animation(.pressSpring, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == AppPrimaryButtonStyle {
    static var appPrimary: AppPrimaryButtonStyle { AppPrimaryButtonStyle() }
    /// Pulsante pieno di un altro colore di stato (es. rosso per le azioni distruttive).
    static func appPrimary(container: Color, content: Color) -> AppPrimaryButtonStyle {
        AppPrimaryButtonStyle(container: container, content: content)
    }
}

extension ButtonStyle where Self == AppOutlinedButtonStyle {
    static var appOutlined: AppOutlinedButtonStyle { AppOutlinedButtonStyle() }
}

extension ButtonStyle where Self == AppTextButtonStyle {
    static var appText: AppTextButtonStyle { AppTextButtonStyle() }
    static func appText(color: Color) -> AppTextButtonStyle { AppTextButtonStyle(color: color) }
}

extension ButtonStyle where Self == AppIconButtonStyle {
    static var appIcon: AppIconButtonStyle { AppIconButtonStyle() }
}
