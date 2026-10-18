import SwiftUI

/// Una pagina della presentazione: icona principale, due icone "satellite", titolo e testo.
private struct IntroPage {
    let icon: String? // nil = la prima pagina mostra il logo
    let satellites: [String]
    let title: String
    let text: String
}

private let pages: [IntroPage] = [
    IntroPage(
        icon: nil, satellites: ["globe.europe.africa.fill", "building.2.fill"],
        title: "Benvenuto in SiciliaHost",
        text: "L'app per chi gestisce case vacanza: prenotazioni, check-in, scorte e conti in un posto solo. Funziona per tutti gli host, anche se la tua casa non è sul nostro sito."
    ),
    IntroPage(
        icon: "calendar", satellites: ["arrow.triangle.2.circlepath", "globe.europe.africa.fill"],
        title: "Tutte le prenotazioni in un posto",
        text: "Airbnb e Booking si sincronizzano da soli, il file di Booking completa importi e contatti, e le prenotazioni dirette arrivano qui."
    ),
    IntroPage(
        icon: "doc.text.viewfinder", satellites: ["person.text.rectangle.fill", "checkmark.seal.fill"],
        title: "Check-in in regola",
        text: "Inquadri il documento dell'ospite: l'app compila la schedina e la invia ad Alloggiati Web."
    ),
    IntroPage(
        icon: "eurosign.circle.fill", satellites: ["shippingbox.fill", "qrcode.viewfinder"],
        title: "Scorte e finanze sotto controllo",
        text: "Aggiungi i prodotti scansionando il codice a barre. Entrate nette, spese e grafici si calcolano da soli."
    ),
    IntroPage(
        icon: "building.2.fill", satellites: ["globe.europe.africa.fill", "checkmark.seal.fill"],
        title: "Vuoi più prenotazioni? Usa siciliahost.com",
        text: "È facoltativo. Il sito è in beta gratuita: nessuna commissione, e i pagamenti li gestisci direttamente tu con l'ospite. A regime tratterremo solo il 5% sulle prenotazioni ricevute, meno delle piattaforme più note."
    ),
    IntroPage(
        icon: "hands.clap.fill", satellites: ["checkmark.seal.fill", "person.text.rectangle.fill"],
        title: "Il nostro ruolo: un ponte, non un padrone",
        text: "Mettiamo in contatto te e gli ospiti. La casa, i prezzi e il rapporto con l'ospite restano tuoi. Controlliamo gli annunci, ti aiutiamo a presentarli bene e rispondiamo quando hai bisogno."
    ),
]

/// Presentazione a tutto schermo alla prima apertura: sei pagine sfogliabili con fondo ambiente animato, puntini,
/// "Salta" e "Avanti"/"Inizia". `onDone` la chiude (anche con "Salta").
struct IntroScreen: View {
    let onDone: () -> Void
    @State private var current: Int? = 0

    private var index: Int { current ?? 0 }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        AmbientBackground(animated: true) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLast { Button("Salta", action: onDone).buttonStyle(.appText) }
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 8)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { i in
                            IntroPageContent(page: pages[i])
                                .containerRelativeFrame(.horizontal)
                                .id(i)
                                // Parallax: l'illustrazione e il testo sfumano e scivolano uscendo.
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .opacity(1 - min(abs(phase.value), 1))
                                        .offset(x: phase.value * -40)
                                        .scaleEffect(0.85 + 0.15 * (1 - min(abs(phase.value), 1)))
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)

                Dots(count: pages.count, selected: index)
                Spacer().frame(height: 20)

                Button {
                    if isLast {
                        onDone()
                    } else {
                        withAnimation(.emphasized) { current = index + 1 }
                    }
                } label: {
                    Text(isLast ? "Inizia" : "Avanti").appStyle(.titleSmall).frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .frame(minHeight: 52)
                .padding(.horizontal, 24)
                Spacer().frame(height: 20)
            }
        }
    }
}

private struct IntroPageContent: View {
    let page: IntroPage

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                Illustration(page: page)
                VStack(spacing: 12) {
                    Text(page.title)
                        .appStyle(.headlineMedium)
                        .foregroundStyle(Theme.onSurface)
                        .multilineTextAlignment(.center)
                    Text(page.text)
                        .appStyle(.bodyLarge)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 480)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, minHeight: 440)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Disco di vetro con l'icona (o il logo) al centro e due tessere di vetro che ci galleggiano attorno.
private struct Illustration: View {
    let page: IntroPage

    var body: some View {
        ZStack {
            ZStack {
                Circle().fill(.clear).frame(width: 180, height: 180).glass(Circle(), elevation: 24)
                if let icon = page.icon {
                    Circle()
                        .fill(Theme.primary)
                        .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)))
                        .frame(width: 104, height: 104)
                        .softShadow(16, color: Theme.primary)
                    Image(systemName: icon).font(.system(size: 46)).foregroundStyle(Theme.onPrimary)
                } else {
                    BrandLogo(height: 120)
                }
            }
            if page.satellites.indices.contains(0) {
                Satellite(systemImage: page.satellites[0]).offset(x: 90, y: -90)
            }
            if page.satellites.indices.contains(1) {
                Satellite(systemImage: page.satellites[1]).offset(x: -90, y: 90)
            }
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }
}

private struct Satellite: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 26))
            .foregroundStyle(Theme.primary)
            .frame(width: 60, height: 60)
            .glass(roundedShape(20), elevation: 12)
    }
}

/// Puntini: quello attivo si allunga in una pillola, con una molla.
private struct Dots: View {
    let count: Int
    let selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: i == selected ? 28 : 8, height: 8)
                    .opacity(i == selected ? 1 : 0.35)
            }
        }
        .animation(.slideSpring, value: selected)
        .accessibilityElement()
        .accessibilityLabel("Pagina \(selected + 1) di \(count)")
    }
}
