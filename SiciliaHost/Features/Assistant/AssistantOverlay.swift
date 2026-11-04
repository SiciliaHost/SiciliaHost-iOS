import SwiftUI

/// Pulsante compatto di Cactus in fondo alla barra di navigazione principale.
struct AssistantPill: View {
    let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(cactusCyan)
                Text("AI")
                    .font(.caption2.bold())
                    .foregroundStyle(cactusCyan)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(Capsule().fill(cactusCyan.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AssistantTexts.openAssistant)
    }
}

/// Pulsante rotondo flottante da 56pt in basso a destra sulle schermate secondarie.
struct FloatingAssistantButton: View {
    let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var body: some View {
        Button(action: onClick) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceContainerHigh)
                    .softShadow(10)
                    .overlay(Circle().stroke(cactusCyan.opacity(0.4), lineWidth: 1.5))

                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(cactusCyan)
                    Text("AI")
                        .font(.caption.bold())
                        .foregroundStyle(cactusCyan)
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel(AssistantTexts.openAssistant)
    }
}

/// Contenitore per presentare l'overlay di Cactus sopra l'intera gerarchia di viste.
struct AssistantOverlayHost<Content: View>: View {
    @Bindable var controller: AssistantController = .shared
    var model: AssistantModel
    @ViewBuilder let content: () -> Content

    init(model: AssistantModel, @ViewBuilder content: @escaping () -> Content) {
        self.model = model
        self.content = content
    }

    var body: some View {
        ZStack {
            content()

            if controller.open {
                CactusOverlayView(model: model, controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(999)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.open)
    }
}
