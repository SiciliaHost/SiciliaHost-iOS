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

    /// Scorte inventate.
    static let inventory: [InventoryItem] = [
        InventoryItem(id: "i1", propertyId: "p1", name: "Detersivo piatti", barcode: "8001090000000", quantity: 6, lowStockThreshold: 2, category: "Pulizia"),
        InventoryItem(id: "i2", propertyId: "p1", name: "Carta igienica", quantity: 2, lowStockThreshold: 2, category: "Consumabili"),
        InventoryItem(id: "i3", propertyId: "p2", name: "Caffè macinato", quantity: 0, lowStockThreshold: 1, isDepleted: true, category: "Consumabili"),
        InventoryItem(id: "i4", propertyId: "p2", name: "Lenzuola matrimoniali", quantity: 4, lowStockThreshold: 2, category: "Biancheria"),
    ]

    /// Prenotazioni inventate attorno a oggi (nomi di fantasia, nessun dato reale). Senza importi: Home e Agenda.
    static var reservations: [Reservation] {
        let today = AgendaLogic.startOfDay(millisFromDate(Date()))
        let day: Int64 = 86_400_000
        return [
            Reservation(id: "r1", propertyId: "p1", guestName: "Mario Rossi", checkIn: today, checkOut: today + 3 * day,
                        platform: "AIRBNB", adults: 2),
            Reservation(id: "r2", propertyId: "p2", guestName: "Anna Muster", checkIn: today, checkOut: today + 2 * day,
                        platform: "BOOKING", adults: 2, children: 1),
            Reservation(id: "r3", propertyId: "p1", guestName: nil, checkIn: today + 5 * day, checkOut: today + 8 * day,
                        platform: "BOOKING"),
            Reservation(id: "r4", propertyId: "p2", guestName: "Luca Bianchi", checkIn: today - 2 * day, checkOut: today + day,
                        platform: "MANUAL"),
        ]
    }

    /// Le stesse prenotazioni con gli importi del telefono, per le Finanze (r3 e r4 senza lordo: «Importi da inserire»).
    static var financeReservations: [FinReservation] {
        let today = AgendaLogic.startOfDay(millisFromDate(Date()))
        let day: Int64 = 86_400_000
        return [
            FinReservation(id: "r1", propertyId: "p1", guestName: "Mario Rossi", checkIn: today, checkOut: today + 3 * day,
                           platform: "AIRBNB", adults: 2, grossAmount: 360),
            FinReservation(id: "r2", propertyId: "p2", guestName: "Anna Muster", checkIn: today, checkOut: today + 2 * day,
                           platform: "BOOKING", adults: 2, children: 1, grossAmount: 210),
            FinReservation(id: "r3", propertyId: "p1", guestName: nil, checkIn: today + 5 * day, checkOut: today + 8 * day,
                           platform: "BOOKING"),
            FinReservation(id: "r4", propertyId: "p2", guestName: "Luca Bianchi", checkIn: today - 2 * day, checkOut: today + day,
                           platform: "MANUAL"),
        ]
    }
}

struct UIPreviewRoot: View {
    let screen: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        switch screen {
        case "login":
            LoginView(auth: AuthService())
        case "intro":
            IntroScreen(onDone: {})
        case "loading":
            CactusLoading()
        case "onboarding":
            AppScreen {
                OnboardingView(isBusy: false, error: nil, onCreateHouse: {}, onInviteCode: { _ in }, onDismissError: {}, onLogout: {}, showsAccountActions: false)
            }
        case "home":
            AppScreen { MainTabView(scope: UIPreview.scope, router: AppRouter(), onSignOut: { onDismiss?() }) }
        case "arrivals":
            AppScreen {
                HomeView(scope: UIPreview.scope, onProfile: {},
                         model: HomeModel(fetch: { _ in ReservationsWithCheckin(reservations: UIPreview.reservations) }, create: { $0 }))
            }
        case "agenda":
            AppScreen {
                AgendaView(scope: UIPreview.scope, canEditPrices: true,
                           model: AgendaModel(fetch: { _ in ReservationsWithCheckin(reservations: UIPreview.reservations) }))
            }
        case "inventory":
            AppScreen {
                InventoryView(scope: UIPreview.scope, model: InventoryModel(db: nil, preview: (UIPreview.inventory, UIPreview.scope.properties)))
            }
        case "finance":
            AppScreen {
                FinanceView(scope: UIPreview.scope, model: FinanceModel(db: nil, preview: (
                    UIPreview.scope.properties, UIPreview.financeReservations,
                    [Expense(id: "x1", propertyId: "p1", description: "Bolletta luce", amount: 84),
                     Expense(id: "x2", propertyId: "p2", description: "Detersivi e carta", amount: 32)],
                    [RecurringExpense(id: "f1", propertyId: "p1", description: "Internet", amount: 29.9, startMonth: "2026-01")]
                )))
            }
        case "tour":
            AppScreen { MainTabView(scope: UIPreview.scope, router: AppRouter(), onSignOut: {}) }
                .task {
                    OnboardingController.shared.tourForced = true
                    OnboardingController.shared.tourRequested = true
                }
        case "profile":
            AppScreen {
                ProfileView(roleLabel: "PROPRIETARIO", scope: UIPreview.scope, onBack: {}, onHouse: { _ in }, onPrivacy: {}, onReplayTour: {}, onLogout: {}, showsAccountActions: false)
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
