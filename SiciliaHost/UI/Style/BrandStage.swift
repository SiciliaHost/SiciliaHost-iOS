import SwiftUI

/// Il palcoscenico di Cactus (porting di `ui/brand/BrandStage.kt` e `CactusLoading.kt` dell'Android): il fondo verde del
/// marchio con tre macchie morbide (giallo fiore, rosso frutto, verde pala) su cui stanno presentazione, accesso e
/// caricamento. Statico, disegnato con gradienti e senza sfocature.
struct BrandBackdrop<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Solo il fondo esce dalle aree sicure: il contenuto resta fuori da notch e barra home.
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: Brand.green900), Color(hex: Brand.green700), Color(hex: Brand.green)],
                        startPoint: .top, endPoint: .bottom
                    )
                    Canvas { context, size in
                        func blob(_ color: Color, x: Double, y: Double, factor: Double, alpha: Double) {
                            let center = CGPoint(x: size.width * x, y: size.height * y)
                            let radius = min(size.width, size.height) * factor
                            context.fill(
                                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                with: .radialGradient(
                                    Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                    center: center, startRadius: 0, endRadius: radius
                                )
                            )
                        }
                        blob(Color(hex: Brand.yellow), x: 0.12, y: 0.10, factor: 0.85, alpha: 0.30)
                        blob(Color(hex: Brand.red), x: 0.95, y: 0.46, factor: 0.70, alpha: 0.22)
                        blob(Color(hex: 0x9BE15D), x: 0.30, y: 0.98, factor: 0.90, alpha: 0.28)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .preferredColorScheme(.dark) // fondo scuro fisso: controlli di sistema coerenti
    }
}

/// Cactus, il protagonista, con un respiro di luce dietro e un'ombra morbida sul "terreno"; `state` ne guida il movimento.
///
/// **Su iOS non è un modello 3D vero**: il motore SceneKit (`CactusAvatarEngine`) non ha ancora un modello da disegnare (il
/// `cactus_avatar.glb` dell'Android non si legge con SceneKit senza una conversione in USDZ) e l'avatar dell'assistente è
/// ancora un disegno vettoriale. Qui si usa quindi il render 3D `cactus_avatar_3d.png` (lo stesso che l'Android mostra se
/// il motore non parte) con un movimento procedurale per posa. Niente motore 3D = niente rischio di due motori insieme.
/// Con «Riduci movimento» l'immagine sta ferma.
struct CactusHero: View {
    var state: CactusState = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                stage(time: 0, moving: false)
            } else {
                TimelineView(.animation) { timeline in
                    stage(time: timeline.date.timeIntervalSinceReferenceDate, moving: true)
                }
            }
        }
        .accessibilityHidden(true) // decorativo: le parole stanno nei testi
    }

    private func stage(time t: Double, moving: Bool) -> some View {
        let glow = moving ? 0.525 + 0.175 * sin(t * 2 * .pi / 5.2) : 0.5
        let m = moving ? motion(time: t) : Motion()
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // alone di luce dietro il personaggio
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0xBFF7C8).opacity(glow * 0.55), .clear],
                        center: .center, startRadius: 0, endRadius: min(w, h) * 0.62
                    ))
                    .frame(width: min(w, h) * 1.24, height: min(w, h) * 1.24)
                    .position(x: w / 2, y: h * 0.46)
                // ombra a terra (si stringe quando Cactus salta)
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Color.black.opacity(0.38), .clear],
                        center: .center, startRadius: 0, endRadius: w * 0.23
                    ))
                    .frame(width: w * 0.46 * (1 - m.lift * 0.02), height: w * 0.46 * 0.14)
                    .position(x: w / 2, y: h * 0.94)
                Image("CactusHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h * 0.92)
                    .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                    .offset(x: m.shakeX, y: -m.lift)
                    .position(x: w / 2, y: h * 0.46)
            }
        }
    }

    private struct Motion {
        var lift: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var tilt: Double = 0
        var shakeX: CGFloat = 0
    }

    /// Un movimento per posa, come le pose dell'Android: riposo = respiro lento; pensa = rimbalzi; ascolta = si inclina;
    /// lavora = piccoli scatti; parla = pulsa; errore = scuote.
    private func motion(time t: Double) -> Motion {
        var m = Motion()
        switch state {
        case .idle:
            m.lift = CGFloat(2 + 2 * sin(t * 1.6))
            m.scaleY = CGFloat(1 + 0.012 * sin(t * 1.6))
        case .thinking:
            let hop = abs(sin(t * 4.2))
            m.lift = CGFloat(hop * 12)
            m.scaleY = CGFloat(1 + hop * 0.03)
            m.scaleX = CGFloat(1 - hop * 0.02)
        case .listening:
            m.tilt = 4 * sin(t * 2.2)
            m.scaleX = 1.03
            m.scaleY = 1.03
        case .working:
            m.tilt = 2.5 * sin(t * 9)
            m.lift = CGFloat(abs(sin(t * 4.5)) * 4)
        case .speaking:
            let pulse = sin(t * 8)
            m.scaleX = CGFloat(1 + 0.02 * pulse)
            m.scaleY = CGFloat(1 + 0.03 * pulse)
        case .error:
            m.shakeX = CGFloat(6 * sin(t * 30))
        }
        return m
    }
}

/// «powered by» + il logo SiciliaHost su una pastiglia chiara (il marchio ha il contorno nero: sul verde non si leggerebbe).
/// Usa sempre la variante `Logo` (scritta scura): la pastiglia è chiara anche col tema scuro, `BrandLogo` sceglierebbe
/// `LogoDark` (scritta chiara) e sparirebbe.
struct PoweredBySiciliaHost: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("powered by")
                .appStyle(.labelSmall)
                .foregroundStyle(Color.white.opacity(0.72))
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: 0xFAF7F1).opacity(0.92)))
        }
        .accessibilityHidden(true)
    }
}

/// La schermata di caricamento dopo l'accesso (`CactusLoading.kt`): Cactus «pensa» (rimbalza) su fondo verde, con il marchio
/// SiciliaHost in secondo piano.
struct CactusLoading: View {
    var message = "Un attimo, preparo le tue case…"

    var body: some View {
        BrandBackdrop {
            VStack {
                Spacer(minLength: 4)
                VStack(spacing: 8) {
                    CactusHero(state: .thinking)
                        .frame(width: 260, height: 280)
                    Text(message)
                        .appStyle(.titleMedium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer(minLength: 4)
                PoweredBySiciliaHost().padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
    }
}
