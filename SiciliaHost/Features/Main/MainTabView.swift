import SwiftUI

/// Schermata principale (`MainScreen.kt`): sezioni sfogliabili con un gesto (come il pager dell'Android) sotto una barra di
/// vetro flottante, più il tour guidato. Le sezioni di primo livello non hanno intestazione, solo contenuto.
struct MainTabView: View {
    let scope: AccessScope?
    let router: AppRouter
    let onSignOut: () -> Void

    @State private var selected: MainTab
    @State private var tour = TourState()
    /// L'app è ferma sulla sezione giusta (lo scorrimento tra sezioni è finito): serve al tour per posizionarsi.
    @State private var settled = true
    /// Le case con prezzi accessibili e annuncio approvato: solo per queste esiste "Modifica prezzi".
    @State private var approved: Set<String> = []

    private let db = FirestoreService()
    private let siteContent = SiteContentService()
    private var onboarding: OnboardingController { .shared }

    init(scope: AccessScope?, router: AppRouter, onSignOut: @escaping () -> Void, initialTab: MainTab = .home) {
        self.scope = scope
        self.router = router
        self.onSignOut = onSignOut
        _selected = State(initialValue: initialTab)
    }

    var body: some View {
        let tabs = MainTabs.visible(for: scope)
        ZStack(alignment: .bottom) {
            TabView(selection: $selected) {
                ForEach(tabs) { tab in
                    content(for: tab)
                        // La barra flottante non deve coprire la fine delle liste.
                        .safeAreaPadding(.bottom, Dimens.bottomBarInset)
                        .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            SiciliaNavBar(tabs: tabs, selected: $selected)
                .tourTarget(.navBar)
                .padding(.bottom, 8)
        }
        .overlayPreferenceValue(TourBoundsKey.self) { anchors in
            if tour.isActive {
                TourOverlay(
                    state: tour,
                    ready: settled && (tour.current?.tab == nil || tour.current?.tab == selected.rawValue),
                    anchors: anchors,
                    onFinish: finishTour
                )
            }
        }
        .onChange(of: tabs) { _, newTabs in
            if !newTabs.contains(selected) { selected = .home }
        }
        // Dopo un cambio di sezione si aspetta che lo scorrimento si fermi prima di indicare un elemento.
        .onChange(of: selected) { _, _ in
            settled = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                settled = true
            }
        }
        // Ogni passo del tour porta sulla sua sezione.
        .onChange(of: tour.current) { _, step in
            guard let title = step?.tab, let tab = tabs.first(where: { $0.rawValue == title }), tab != selected else { return }
            withAnimation(.emphasized) { selected = tab }
        }
        .task(id: scope) { await loadApprovedListings() }
        // Tour guidato: dopo la prima casa, o da Profilo → "Rivedi il tour".
        .onChange(of: onboarding.tourRequested, initial: true) { _, requested in
            guard requested, let scope else { return }
            Task { await startTour(scope: scope, tabs: tabs) }
        }
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home: HomeView(scope: scope, onProfile: { router.push(.profile) })
        case .agenda: PlaceholderView(feature: "Agenda", androidSource: "ui/calendar, ui/reservation")
        case .scorte: PlaceholderView(feature: "Scorte", androidSource: "ui/inventory")
        case .finanze: PlaceholderView(feature: "Finanze", androidSource: "ui/finance")
        case .case_: PlaceholderView(feature: "Case", androidSource: "ui/cases, ui/site, ui/members")
        }
    }

    private func loadApprovedListings() async {
        let ids = scope?.priceProperties.map(\.id) ?? []
        guard !ids.isEmpty else { approved = []; return }
        do {
            let contents = try await siteContent.getProperties(ids)
            approved = approvedIds(Dictionary(contents.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            approved = []
        }
    }

    private func startTour(scope: AccessScope, tabs: [MainTab]) async {
        onboarding.tourRequested = false
        let forced = onboarding.tourForced
        onboarding.tourForced = false
        let alreadyDone = forced ? false : ((try? await db.getOnboardingFlags(scope.uid).tourDone) ?? false)
        guard !alreadyDone else { return }
        router.popToRoot()
        tour.start(tourSteps(
            visibleTabs: tabs.map(\.rawValue),
            canManageAHouse: !scope.managed.isEmpty,
            canEditPrices: MainTabs.canEditPrices(scope, approvedIds: approved)
        ))
    }

    private func finishTour() {
        tour.stop()
        withAnimation(.emphasized) { selected = .home }
        guard let uid = scope?.uid else { return }
        // Regole non ancora deployate o offline: il tour potrebbe ripresentarsi dopo un'altra casa.
        Task { try? await db.markOnboarding(uid, field: .tourDoneAt) }
    }
}

/// Segnaposto per le schermate non ancora portate. Rimuoverlo schermata per schermata.
struct PlaceholderView: View {
    let feature: String
    let androidSource: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer")
                .font(.system(size: 28))
                .foregroundStyle(Theme.onSurfaceVariant)
            SectionLabel(feature)
            Text("Schermata da portare dall'app Android")
                .appStyle(.bodyMedium)
                .foregroundStyle(Theme.onSurface)
            Text(androidSource)
                .appStyle(.bodySmall)
                .foregroundStyle(Theme.onSurfaceVariant)
        }
        .multilineTextAlignment(.center)
        .padding(Dimens.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
