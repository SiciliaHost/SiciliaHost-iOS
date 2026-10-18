import SwiftUI

/// Movimento dell'app (`ui/style/Motion.kt`): molle che rientrano veloci e tornano con un piccolo rimbalzo.
extension Animation {
    /// Pressione dei pulsanti: rientra veloce e torna con un rimbalzo.
    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.45)
    /// Indicatori che si spostano (barra di navigazione, punti dello slider).
    static let slideSpring = Animation.spring(response: 0.5, dampingFraction: 0.6)
    /// Curva "emphasized" di Material 3: parte decisa e si posa morbida.
    static let emphasized = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)
}

/// Transizione tra schermate: la nuova entra da destra, leggermente rimpicciolita, e si posa; quella sotto arretra.
extension AnyTransition {
    static var screenForward: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }
}
