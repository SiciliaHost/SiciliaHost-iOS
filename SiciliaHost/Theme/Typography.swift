import SwiftUI

/// Scala tipografica compatta dell'app Android (`theme/Type.kt`): ogni livello è 2–6 pt più piccolo di una scala di
/// sistema, così i contenuti entrano anche sugli schermi stretti. Il display segue il marchio (geometrico, maiuscolo,
/// spaziato), non un serif; la personalità sta nelle etichette maiuscole spaziate ("RENTAL HOMES").
/// I corpi seguono la dimensione del testo scelta dall'utente (Dynamic Type) con `@ScaledMetric`.
enum AppTextStyle: CaseIterable {
    case displaySmall, headlineLarge, headlineMedium, headlineSmall
    case titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall
    case labelLarge, labelMedium, labelSmall

    struct Spec: Equatable {
        let size: CGFloat
        let lineHeight: CGFloat
        let weight: Font.Weight
        let tracking: CGFloat
    }

    var spec: Spec {
        switch self {
        case .displaySmall: return Spec(size: 26, lineHeight: 30, weight: .black, tracking: -0.5)
        case .headlineLarge: return Spec(size: 22, lineHeight: 26, weight: .bold, tracking: -0.25)
        case .headlineMedium: return Spec(size: 18, lineHeight: 22, weight: .bold, tracking: 0)
        case .headlineSmall: return Spec(size: 16, lineHeight: 20, weight: .semibold, tracking: 0)
        case .titleLarge: return Spec(size: 16, lineHeight: 20, weight: .semibold, tracking: 0)
        case .titleMedium: return Spec(size: 14, lineHeight: 18, weight: .semibold, tracking: 0.1)
        case .titleSmall: return Spec(size: 13, lineHeight: 17, weight: .semibold, tracking: 0.1)
        case .bodyLarge: return Spec(size: 14, lineHeight: 19, weight: .regular, tracking: 0.15)
        case .bodyMedium: return Spec(size: 13, lineHeight: 17, weight: .regular, tracking: 0.15)
        case .bodySmall: return Spec(size: 11, lineHeight: 15, weight: .regular, tracking: 0.2)
        case .labelLarge: return Spec(size: 12, lineHeight: 16, weight: .semibold, tracking: 0.3)
        case .labelMedium: return Spec(size: 11, lineHeight: 14, weight: .medium, tracking: 0.5)
        // Occhiello maiuscolo molto spaziato, come "RENTAL HOMES" sotto il marchio: usalo con testo già in maiuscolo.
        case .labelSmall: return Spec(size: 10, lineHeight: 13, weight: .bold, tracking: 1.2)
        }
    }

    /// Stile di sistema da cui scala col Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .displaySmall: return .title
        case .headlineLarge: return .title2
        case .headlineMedium, .headlineSmall, .titleLarge: return .headline
        case .titleMedium, .titleSmall, .bodyLarge, .bodyMedium: return .body
        case .bodySmall, .labelLarge, .labelMedium, .labelSmall: return .caption
        }
    }
}

private struct AppTextModifier: ViewModifier {
    let style: AppTextStyle
    @ScaledMetric private var size: CGFloat

    init(_ style: AppTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.spec.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        let spec = style.spec
        content
            .font(.system(size: size, weight: spec.weight))
            .tracking(spec.tracking)
            // Interlinea = altezza di riga − altezza naturale del font (circa 1,17 × corpo).
            .lineSpacing(max(spec.lineHeight - spec.size * 1.17, 0) * (size / spec.size))
    }
}

extension View {
    /// Applica uno stile della scala tipografica dell'app.
    func appStyle(_ style: AppTextStyle) -> some View { modifier(AppTextModifier(style)) }
}
