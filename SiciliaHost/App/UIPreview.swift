import SwiftUI

/// Anteprime a schermo intero con dati inventati, per fotografare l'interfaccia nel simulatore durante la CI
/// (`tools/ci_screenshots.sh`) senza accedere né toccare dati reali. Si attiva SOLO nelle build di debug, con
/// l'argomento di avvio `-UIPreview <schermata>` (es. `xcrun simctl launch <udid> <bundle> -UIPreview home`).
enum UIPreview {
    static var requestedScreen: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "UIPreview")
        #else
        return nil
        #endif
    }

    /// Case e profilo inventati: un proprietario con due case (vede tutte le sezioni).
    static let scope = AccessScope(
        uid: "preview", isSuperAdmin: false,
        properties: [
            Property(id: "p1", name: "Casa Mare · Trappeto", members: ["preview": "OWNER"], memberUids: ["preview"]),
            Property(id: "p2", name: "Appartamento Centro · Palermo", members: ["preview": "OWNER"], memberUids: ["preview"]),
        ]
    )
}

struct UIPreviewRoot: View {
    let screen: String

    var body: some View {
        switch screen {
        case "login":
            LoginView(auth: AuthService())
        case "intro":
            IntroScreen(onDone: {})
        case "onboarding":
            AppScreen {
                OnboardingView(isBusy: false, error: nil, onCreateHouse: {}, onInviteCode: { _ in }, onDismissError: {}, onLogout: {})
            }
        case "home":
            AppScreen { MainTabView(scope: UIPreview.scope, router: AppRouter(), onSignOut: {}) }
        case "tour":
            AppScreen { MainTabView(scope: UIPreview.scope, router: AppRouter(), onSignOut: {}) }
                .task {
                    OnboardingController.shared.tourForced = true
                    OnboardingController.shared.tourRequested = true
                }
        case "profile":
            AppScreen {
                ProfileView(roleLabel: "PROPRIETARIO", showMembers: true, onBack: {}, onMembers: {}, onReplayTour: {}, onLogout: {})
            }
        case "failed":
            AppScreen {
                StateMessage(
                    systemImage: "lock.fill", title: "Caricamento non riuscito",
                    message: "Non riesco a caricare le tue case. Controlla la connessione e riprova."
                ) {
                    Button("Riprova") {}.buttonStyle(.appPrimary)
                    Button("Esci") {}.buttonStyle(.appOutlined)
                }
            }
        case "terms":
            AppScreen { Color.clear }
                .sheet(isPresented: .constant(true)) { HostTermsSheet(onAccept: {}, onDismiss: {}) }
        case "gallery":
            AppScreen { Gallery() }
        default:
            Text("Anteprima sconosciuta: \(screen)")
        }
    }
}

/// Tavolozza, tipografia e componenti in una pagina, per controllare il marchio a colpo d'occhio.
private struct Gallery: View {
    @State private var selectedTab: MainTab = .agenda
    @State private var selectedOption: String? = "Ultimi 12 mesi"

    private let swatches: [(String, Color)] = [
        ("primary", Theme.primary), ("secondary", Theme.secondary), ("error", Theme.error),
        ("container", Theme.primaryContainer), ("surface", Theme.surfaceContainerLow), ("high", Theme.surfaceContainerHigh),
        ("outline", Theme.outline), ("ink", Theme.onSurface),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
                BrandLogo(height: 56).frame(maxWidth: .infinity)

                SectionLabel("Palette")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(swatches, id: \.0) { name, color in
                        VStack(spacing: 2) {
                            roundedShape(Radius.small).fill(color).frame(height: 30)
                                .overlay(roundedShape(Radius.small).strokeBorder(Theme.outlineVariant, lineWidth: 1))
                            Text(name).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                        }
                    }
                }

                SectionLabel("Stati")
                HStack(spacing: 8) {
                    statePill("CONFERMATO", Theme.primary)
                    statePill("DA RIVEDERE", Theme.secondary)
                    statePill("IN USCITA", Theme.error)
                }

                SectionLabel("Tipografia")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppTextStyle.allCases, id: \.self) { style in
                        Text(style == .labelSmall ? "RENTAL HOMES" : "SiciliaHost \(String(describing: style))")
                            .appStyle(style)
                            .foregroundStyle(Theme.onSurface)
                    }
                }

                SectionLabel("Pulsanti")
                HStack(spacing: 8) {
                    Button("Pieno") {}.buttonStyle(.appPrimary)
                    Button("Vetro") {}.buttonStyle(.appOutlined)
                    Button("Testo") {}.buttonStyle(.appText)
                    Button("Spento") {}.buttonStyle(.appPrimary).disabled(true)
                }

                SectionLabel("Card e campi")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Casa Mare · Trappeto").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                    Text("Arrivo oggi · 4 ospiti").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(Dimens.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
                SelectField(
                    label: "Periodo", options: ["Questo mese", "Ultimi 12 mesi", "Anno in corso"],
                    selected: selectedOption, optionLabel: { $0 }, onSelect: { selectedOption = $0 }
                )

                SectionLabel("Barra di navigazione")
                SiciliaNavBar(tabs: MainTab.allCases, selected: $selectedTab).frame(maxWidth: .infinity)
            }
            .padding(Dimens.screenPadding)
        }
    }

    private func statePill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .appStyle(.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
