import SwiftUI

/// Fondo dell'app: il colore del tema con tre macchie molto morbide nei colori del logo (verde pala, giallo fiore,
/// rosso frutto). È quello che il vetro sfoca: su un fondo piatto le superfici di vetro sarebbero solo grigie.
/// Ferme per default: un fondo animato sotto tutta l'app ridisegnerebbe (e risfocherebbe) lo schermo a ogni frame.
/// `animated` le fa derivare lentamente (presentazione); restano ferme se l'utente ha ridotto il movimento.
/// `drift` sposta in più le macchie in orizzontale (lo slider di benvenuto ci passa lo sfoglio).
struct AmbientBackground<Content: View>: View {
    var animated = false
    var drift: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if animated && !reduceMotion {
                TimelineView(.animation) { timeline in
                    canvas(phase: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40)
                }
            } else {
                canvas(phase: 0.15)
            }
            content()
        }
    }

    private func canvas(phase: Double) -> some View {
        let dark = scheme == .dark
        let alpha = dark ? 0.20 : 0.26
        let green = Theme.primary.opacity(alpha)
        let yellow = (dark ? Theme.secondary : Color(hex: Brand.yellow)).opacity(alpha * 0.9)
        let red = Theme.error.opacity(alpha * 0.7)
        let drift = Double(drift)
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.background))
            let t = phase * 2 * .pi
            func blob(_ color: Color, x: Double, y: Double, radiusFactor: Double) {
                let center = CGPoint(x: size.width * x, y: size.height * y)
                let radius = max(size.width, size.height) * radiusFactor
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0, endRadius: radius)
                )
            }
            blob(green, x: 0.10 + 0.06 * cos(t) - drift * 0.15, y: 0.12 + 0.04 * sin(t), radiusFactor: 0.75)
            blob(yellow, x: 0.95 + 0.05 * sin(t) - drift * 0.25, y: 0.40 + 0.05 * cos(t), radiusFactor: 0.60)
            blob(red, x: 0.25 + 0.05 * sin(t + 1) - drift * 0.35, y: 0.92 + 0.03 * cos(t), radiusFactor: 0.65)
        }
        .ignoresSafeArea()
    }
}

/// Sfondo di una schermata intera: ogni schermata ha il suo fondo ambiente pieno, così durante le transizioni le due
/// non si mescolano.
struct AppScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        AmbientBackground { content() }
    }
}
