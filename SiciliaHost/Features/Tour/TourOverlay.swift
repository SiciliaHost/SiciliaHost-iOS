import SwiftUI

// Tour guidato (`ui/tour/*`): un velo scuro con un buco arrotondato attorno all'elemento del passo e un alone che
// pulsa sul bordo, più un fumetto di vetro con testo, puntini, "Salta" e "Avanti"/"Fine".

/// Le posizioni degli elementi indicati dal tour, raccolte con le preferenze di layout.
struct TourBoundsKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Registra la posizione di questo elemento per il tour. Sparisce da sola quando l'elemento esce dalla gerarchia
    /// (pagina lasciata, sezione chiusa), così il tour non indica il vuoto.
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourBoundsKey.self, value: .bounds) { [target: $0] }
    }
}

/// Quanto aspettare che un elemento compaia (pagina da comporre, casa da aprire) prima di saltarlo.
private let targetTimeout: Duration = .milliseconds(2_500)
private let bookingTimeout: Duration = .milliseconds(10_000)

struct TourOverlay: View {
    let state: TourState
    /// L'app è ferma sulla sezione giusta (nessuno scorrimento in corso).
    let ready: Bool
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void

    var body: some View {
        if let step = state.current {
            GeometryReader { proxy in
                let target = ready ? anchors[step.target].map { proxy[$0] } : nil
                content(step: step, target: target, container: proxy.size)
            }
            // Elemento che non arriva (permessi, nessuna casa gestita, pulsante assente): si va avanti.
            .task(id: TaskKey(index: state.index, missing: !(ready && anchors[step.target] != nil))) {
                guard !(ready && anchors[step.target] != nil) else { return }
                try? await Task.sleep(for: step.target == .caseBookingImport ? bookingTimeout : targetTimeout)
                if Task.isCancelled { return }
                if state.isLast { onFinish() } else { state.next() }
            }
            .ignoresSafeArea()
        }
    }

    private struct TaskKey: Hashable {
        let index: Int
        let missing: Bool
    }

    @ViewBuilder
    private func content(step: TourStep, target: CGRect?, container: CGSize) -> some View {
        let pad: CGFloat = 8
        let radius: CGFloat = 18
        ZStack(alignment: .topLeading) {
            // Velo con il buco: riempimento "pari-dispari" (rettangolo intero meno il rettangolo arrotondato).
            TimelineView(.animation) { timeline in
                let pulse = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                Canvas { context, size in
                    var scrim = Path(CGRect(origin: .zero, size: size))
                    var ring: Path?
                    if let target {
                        let hole = target.insetBy(dx: -pad, dy: -pad)
                        scrim.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
                        let grow = pulse * pad * 1.6
                        ring = Path(roundedRect: hole.insetBy(dx: -grow, dy: -grow), cornerRadius: radius + grow)
                        context.fill(scrim, with: .color(Color(hex: 0x0D0D0B).opacity(0.62)), style: FillStyle(eoFill: true))
                        context.stroke(ring!, with: .color(Theme.primary.opacity((1 - pulse) * 0.9)), lineWidth: 3)
                    } else {
                        context.fill(scrim, with: .color(Color(hex: 0x0D0D0B).opacity(0.37)))
                    }
                }
            }
            // Il tour è modale: i tocchi non arrivano all'app sotto.
            .contentShape(Rectangle())
            .onTapGesture {}

            if let target {
                bubble(step: step, target: target, container: container, pad: pad)
                    .transition(.opacity.combined(with: .offset(y: 24)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: target == nil)
    }

    private func bubble(step: TourStep, target: CGRect, container: CGSize, pad: CGFloat) -> some View {
        let gap: CGFloat = 20
        // Sotto l'elemento se è nella metà alta dello schermo, altrimenti sopra.
        let below = target.midY < container.height / 2
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                Text(step.text).appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
            }
            .id(step.target)
            .transition(.opacity)

            HStack {
                HStack(spacing: 5) {
                    ForEach(state.steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == state.index ? Theme.primary : Theme.onSurfaceVariant.opacity(0.35))
                            .frame(width: i == state.index ? 16 : 6, height: 6)
                    }
                }
                Spacer()
                if !state.isLast { Button("Salta", action: onFinish).buttonStyle(.appText) }
                Button(state.isLast ? "Fine" : "Avanti") {
                    if state.isLast { onFinish() } else { state.next() }
                }
                .buttonStyle(.appPrimary)
            }
        }
        .padding(18)
        .glass(roundedShape(Radius.extraLarge), elevation: 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .position(x: container.width / 2, y: bubbleCenterY(target: target, container: container, pad: pad, gap: gap, below: below))
        .animation(.easeInOut(duration: 0.22), value: step.target)
    }

    /// Centro verticale approssimato del fumetto (altezza stimata): sotto o sopra il buco, sempre dentro lo schermo.
    private func bubbleCenterY(target: CGRect, container: CGSize, pad: CGFloat, gap: CGFloat, below: Bool) -> CGFloat {
        let estimatedHeight: CGFloat = 190
        let y = below ? target.maxY + pad + gap + estimatedHeight / 2 : target.minY - pad - gap - estimatedHeight / 2
        return min(max(y, estimatedHeight / 2 + 8), container.height - estimatedHeight / 2 - 8)
    }
}
