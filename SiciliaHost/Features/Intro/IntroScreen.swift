import SwiftUI

/// Una pagina della presentazione: la posa di Cactus, un'icona (nessuna sulla prima), titolo e testo (`IntroScreen.kt`).
private struct IntroPage {
    let pose: CactusState
    let icon: String? // nil = la prima pagina è Cactus che si presenta
    let title: String
    let text: String
}

private let pages: [IntroPage] = [
    IntroPage(
        pose: .idle, icon: nil,
        title: "Ciao, sono Cactus!",
        text: "Ti aiuto a gestire le tue case vacanza: prenotazioni, check-in, scorte e conti in un posto solo. Funziona per tutti gli host, anche se la tua casa non è sul sito SiciliaHost."
    ),
    IntroPage(
        pose: .thinking, icon: "calendar",
        title: "Tutte le prenotazioni in un posto",
        text: "Airbnb e Booking si sincronizzano da soli, il file di Booking completa importi e contatti, e le prenotazioni dirette arrivano qui."
    ),
    IntroPage(
        pose: .listening, icon: "doc.text.viewfinder",
        title: "Check-in in regola",
        text: "Inquadri il documento dell'ospite: l'app compila la schedina e la invia ad Alloggiati Web."
    ),
    IntroPage(
        pose: .working, icon: "eurosign.circle.fill",
        title: "Scorte e finanze sotto controllo",
        text: "Aggiungi i prodotti scansionando il codice a barre. Entrate nette, spese e grafici si calcolano da soli, e restano sul tuo telefono."
    ),
    IntroPage(
        pose: .speaking, icon: "building.2.fill",
        title: "Vuoi più prenotazioni? Usa siciliahost.com",
        text: "È facoltativo. Il sito è in beta gratuita: nessuna commissione, e i pagamenti li gestisci direttamente tu con l'ospite. A regime tratterremo solo il 5% sulle prenotazioni ricevute, meno delle piattaforme più note."
    ),
    IntroPage(
        pose: .idle, icon: "hands.clap.fill",
        title: "Il nostro ruolo: un ponte, non un padrone",
        text: "Mettiamo in contatto te e gli ospiti. La casa, i prezzi e il rapporto con l'ospite restano tuoi. Controlliamo gli annunci, ti aiutiamo a presentarli bene e rispondiamo quando hai bisogno."
    ),
]

/// Presentazione a tutto schermo alla prima apertura: sei pagine sfogliabili con Cactus sempre in alto (cambia posa a ogni
/// pagina), testo bianco sotto, puntini, «Salta» e «Avanti»/«Inizia», e in fondo «powered by SiciliaHost». `onDone` la
/// chiude (anche con «Salta»). Cactus è uno solo, sopra il paginatore: non uno per pagina.
struct IntroScreen: View {
    let onDone: () -> Void
    @State private var current: Int? = 0

    private var index: Int { current ?? 0 }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        BrandBackdrop {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLast {
                        Button(action: onDone) {
                            Text("Salta").appStyle(.labelLarge).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 8)

                CactusHero(state: pages[index].pose)
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { i in
                            IntroPageContent(page: pages[i])
                                .containerRelativeFrame(.horizontal)
                                .id(i)
                                // Parallax leggero: il testo scivola e sfuma uscendo.
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .opacity(1 - min(abs(phase.value), 1))
                                        .offset(x: phase.value * -40)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)
                .frame(height: 250)

                Dots(count: pages.count, selected: index)
                Spacer().frame(height: 18)

                Button {
                    if isLast {
                        onDone()
                    } else {
                        withAnimation(.emphasized) { current = index + 1 }
                    }
                } label: {
                    Text(isLast ? "Inizia" : "Avanti").appStyle(.titleSmall).frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(
                    container: isLast ? Color(hex: Brand.yellow) : .white, content: Color(hex: Brand.ink), cornerRadius: 14
                ))
                .frame(maxWidth: 420, minHeight: 52)
                .padding(.horizontal, 24)

                PoweredBySiciliaHost().padding(.top, 14).padding(.bottom, 10)
            }
        }
    }
}

private struct IntroPageContent: View {
    let page: IntroPage

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let icon = page.icon {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: Brand.yellow))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .padding(.bottom, 14)
                        .accessibilityHidden(true)
                }
                Text(page.title)
                    .appStyle(.headlineMedium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                Text(page.text)
                    .appStyle(.bodyLarge)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Puntini: quello attivo (giallo) si allunga in una pillola, con una molla; gli altri sono bianchi.
private struct Dots: View {
    let count: Int
    let selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule()
                    .fill(i == selected ? Color(hex: Brand.yellow) : Color.white)
                    .frame(width: i == selected ? 28 : 8, height: 8)
                    .opacity(i == selected ? 1 : 0.4)
            }
        }
        .animation(.slideSpring, value: selected)
        .accessibilityElement()
        .accessibilityLabel("Pagina \(selected + 1) di \(count)")
    }
}
