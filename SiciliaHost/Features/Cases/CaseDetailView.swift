import SwiftUI

/// Stato di lettura delle credenziali Alloggiati: "non disponibili" non va confuso con "vuote".
enum CredsState: Equatable {
    case loading
    case ready(AlloggiatiCredentials)
    case unavailable

    var value: AlloggiatiCredentials? {
        if case let .ready(c) = self { return c }
        return nil
    }
}

/// Editor a schermo intero aperto da "Contenuti della pagina".
enum CaseSubEditor { case services, details }

/// La scheda di una casa (`CaseDetailScreen.kt`): sezioni comprimibili, un solo Salva. Salvare NON richiede completezza
/// (una bozza incompleta si salva); la completezza si controlla solo per "Invia per approvazione".
struct CaseDetailView: View {
    let model: CasesModel
    let tourTarget: TourTarget?
    let onBack: () -> Void
    let onOpenMembers: () -> Void
    let onOpenSiteWizard: (String) -> Void
    private let id: String

    @State private var siteModel = SiteContentModel()
    @State private var appDraft: AppFieldsDraft
    @State private var siteDraft: SiteDraft
    @State private var credsOriginal: AlloggiatiCredentials?
    @State private var creds: CredsState = .loading
    @State private var expanded: Set<CaseSection> = [.stato, .informazioni]
    @State private var sub: CaseSubEditor?
    @State private var showLeave = false
    @State private var showPrices = false
    @State private var showDelete = false
    @State private var importMessage: String?
    @State private var bannerTask: Task<Void, Never>?

    /// `initial` serve solo a riempire le bozze: i dati vivi si rileggono dal modello a ogni aggiornamento.
    init(initial: CaseItem, model: CasesModel, tourTarget: TourTarget? = nil, onBack: @escaping () -> Void,
         onOpenMembers: @escaping () -> Void, onOpenSiteWizard: @escaping (String) -> Void = { _ in }) {
        self.model = model
        self.onOpenSiteWizard = onOpenSiteWizard
        self.tourTarget = tourTarget
        self.onBack = onBack
        self.onOpenMembers = onOpenMembers
        id = initial.property.id
        _appDraft = State(initialValue: AppFieldsDraft(initial.property))
        _siteDraft = State(initialValue: SiteDraft(initial.site))
    }

    var body: some View {
        if let item = model.item(id), let scope = model.scope {
            content(item: item, scope: scope)
        } else {
            Color.clear.onAppear(perform: onBack)
        }
    }

    @ViewBuilder
    private func content(item: CaseItem, scope: AccessScope) -> some View {
        let site = siteModel.content(id) ?? item.site
        let title = [item.property.name, site.name].first { !$0.trimmed.isEmpty } ?? "Casa"
        if let sub {
            VStack(spacing: 0) {
                CompactTopBar(title: (sub == .services ? "Servizi · " : "Dettagli pagina · ") + title, onBack: { self.sub = nil })
                switch sub {
                case .services: ServicesEditorView(content: site, siteModel: siteModel, onSaved: closeSub)
                case .details: PageContentEditorView(content: site, siteModel: siteModel, onSaved: closeSub)
                }
            }
        } else {
            mainScreen(item: item, scope: scope, site: site, title: title)
        }
    }

    private func closeSub() {
        sub = nil
        Task { await model.load() }
    }

    // MARK: Bozze

    private func appOriginal(_ item: CaseItem) -> AppFieldsDraft { AppFieldsDraft(item.property) }
    private func siteOriginal(_ item: CaseItem) -> SiteDraft { SiteDraft(item.site) }

    /// La pubblicazione non si cambia dal form: passa solo da invio/approvazione/Nascondi.
    private func siteCurrent(_ item: CaseItem) -> SiteDraft {
        var current = siteDraft
        current.published = siteOriginal(item).published
        return current
    }

    private var credsChanged: Bool {
        guard let now = creds.value else { return false }
        return now != credsOriginal
    }

    private func dirty(_ item: CaseItem) -> Bool {
        appDraft != appOriginal(item) || siteCurrent(item) != siteOriginal(item) || credsChanged
    }

    private func save(_ item: CaseItem) async -> Bool {
        let credsToSave = creds.value
        let ok = await model.saveCase(
            id, originalApp: appOriginal(item), currentApp: appDraft,
            originalSite: siteOriginal(item), currentSite: siteCurrent(item),
            photos: (siteModel.content(id) ?? item.site).photos
        )
        guard ok else { return false }
        if item.canManage, credsChanged, let credsToSave {
            if await model.saveCredentials(id, credsToSave) { credsOriginal = credsToSave }
        }
        // La casa è già stata ricaricata: le bozze ripartono dai valori salvati (normalizzati).
        if let fresh = model.item(id) {
            appDraft = AppFieldsDraft(fresh.property)
            siteDraft = SiteDraft(fresh.site)
        }
        return true
    }

    // MARK: Schermata

    private func mainScreen(item: CaseItem, scope: AccessScope, site: PropertySiteContent, title: String) -> some View {
        let original = siteOriginal(item)
        let current = siteCurrent(item)
        let errors = SiteDraftLogic.fieldErrors(original: original, current: current)
        let appError = appDraft.error()
        let missing = SiteDraftLogic.publishBlockers(current, photoCount: site.photos.count)
            + (appDraft.cin.trimmed.isEmpty ? [WizardLogic.missingCin] : [])
        let busy = model.busy || siteModel.photoBusy || siteModel.isSaving
        let isDirty = dirty(item)
        let canSave = isDirty && appError == nil && errors.isEmpty && !busy
        let canToggle = site.status == .approved && scope.canEditListing(item.property)
        let canDelete = scope.isOwner(item.property)

        return VStack(spacing: 0) {
            CompactTopBar(title: title, onBack: { if isDirty { showLeave = true } else { onBack() } }) {
                if canToggle || canDelete {
                    Menu {
                        if canToggle {
                            let online = site.publishedOnSite == true
                            Button(online ? "Nascondi dal sito" : "Rimetti online sul sito") {
                                Task { await model.setVisible(id, !online) }
                            }
                        }
                        if canDelete {
                            Button("Elimina casa…", role: .destructive) {
                                model.deleteError = nil
                                showDelete = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: Dimens.controlHeight, height: Dimens.controlHeight)
                    }
                    .buttonStyle(.appIcon)
                    .disabled(busy)
                    .accessibilityLabel("Altre azioni sulla casa")
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                        if !site.onSiteTrack && scope.canEditSite(item.property) {
                            PublishOnSiteCard(busy: model.busy) {
                                Task { if await model.startSitePublication(id) { onOpenSiteWizard(id) } }
                            }
                        }
                        ForEach(CaseLogic.visibleSections(canManage: item.canManage, onSiteTrack: site.onSiteTrack)) { section in
                            CaseSectionCard(title: section.title, expanded: expanded.contains(section)) {
                                toggle(section)
                            } content: {
                                sectionContent(section, item: item, scope: scope, site: site, errors: errors,
                                               missing: missing, dirty: isDirty) { target in
                                    expanded.insert(target)
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(80))
                                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                                    }
                                }
                            }
                            .id(section)
                        }
                    }
                    .padding(Dimens.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                // Tour guidato: per indicare "Importa Excel Booking" si apre e si porta in vista la sezione Gestione.
                .onChange(of: tourTarget, initial: true) { _, target in
                    guard target == .caseBookingImport, item.canManage else { return }
                    expanded.insert(.gestione)
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation { proxy.scrollTo(CaseSection.gestione, anchor: .top) }
                    }
                }
            }
            saveBar(appError: appError, errors: errors, canSave: canSave, dirty: isDirty, item: item)
        }
        .onChange(of: appOriginal(item)) { old, new in
            // Dopo un ricaricamento gli originali cambiano: una bozza non toccata li segue, le modifiche restano.
            appDraft = CaseLogic.realign(oldOriginal: old, newOriginal: new, draft: appDraft)
        }
        .onChange(of: original) { old, new in
            siteDraft = CaseLogic.realign(oldOriginal: old, newOriginal: new, draft: siteDraft)
        }
        .task(id: id) {
            model.clearMessages()
            await siteModel.load()
        }
        .task(id: item.canManage) { await loadCredentials(canManage: item.canManage) }
        // Ogni foto cambiata ricarica anche l'elenco Case.
        .onChange(of: siteModel.photoBusy) { was, now in
            if was && !now { Task { await model.load() } }
        }
        .onChange(of: model.message) { _, message in
            guard message != nil else { return }
            bannerTask?.cancel()
            bannerTask = Task {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { model.clearMessages() }
            }
        }
        .sheet(isPresented: $showDelete) {
            DeleteCaseSheet(
                name: item.property.name, id: id,
                canPause: site.status == .approved && site.publishedOnSite == true,
                busy: model.busy, error: model.deleteError,
                onConfirm: { typed in
                    Task {
                        if await model.deleteCase(id, confirmName: typed) {
                            showDelete = false
                            onBack()
                        }
                    }
                },
                onDismiss: {
                    showDelete = false
                    model.deleteError = nil
                }
            )
        }
        .fullScreenCover(isPresented: $showPrices, onDismiss: { Task { await model.load() } }) {
            PriceEditorView(onBack: { showPrices = false }, initialPropertyId: id)
                .background(Theme.background)
        }
        .confirmationDialog("Hai modifiche non salvate", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Salva come bozza") {
                Task { if await save(item) { onBack() } }
            }
            .disabled(!canSave)
            Button("Scarta", role: .destructive) { onBack() }
            Button("Continua a modificare", role: .cancel) {}
        } message: {
            Text("Puoi salvarle come bozza, scartarle o continuare a modificare."
                + (credsChanged ? "\nLe credenziali Alloggiati non salvate andranno perse." : ""))
        }
    }

    private func toggle(_ section: CaseSection) {
        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
    }

    private func loadCredentials(canManage: Bool) async {
        guard canManage else {
            creds = .unavailable
            return
        }
        let loaded = await model.loadCredentials(id)
        credsOriginal = loaded
        creds = loaded.map(CredsState.ready) ?? .unavailable
    }

    @ViewBuilder
    private func sectionContent(
        _ section: CaseSection, item: CaseItem, scope: AccessScope, site: PropertySiteContent,
        errors: [String: String], missing: [String], dirty: Bool, goTo: @escaping (CaseSection) -> Void
    ) -> some View {
        let appEnabled = item.appAccess != .readOnly
        switch section {
        case .stato:
            StatoSection(item: item, site: site, scope: scope, model: model, missing: missing, dirty: dirty, onGoTo: goTo)
        case .informazioni:
            if !appEnabled { SectionNote(text: "Solo il proprietario modifica questi dati.") }
            InformazioniSection(draft: $appDraft, enabled: appEnabled)
        case .prezzi:
            let canEditPrices = site.status == .approved && (scope.isSuperAdmin || scope.canEditPrices(item.property))
            PrezziSection(draft: $siteDraft, errors: errors, onOpenPriceEditor: canEditPrices ? { showPrices = true } : nil)
        case .foto:
            SitePhotosSection(content: site, siteModel: siteModel)
        case .contenuti:
            ContenutiSection(content: site) { sub = $0 }
        case .posizione:
            PosizioneSection(draft: $siteDraft, errors: errors)
        case .infoOspiti:
            InfoOspitiSection(content: site, draft: $siteDraft, errors: errors)
        case .orari:
            if !appEnabled { SectionNote(text: "Solo il proprietario modifica questi dati.") }
            OrariRegoleSection(draft: $appDraft, enabled: appEnabled)
        case .gestione:
            GestioneSection(
                property: item.property, draft: $appDraft, creds: $creds,
                isOwner: scope.isOwner(item.property), isSuperAdmin: scope.isSuperAdmin,
                importMessage: $importMessage,
                onImport: { data in
                    importMessage = "Importazione in corso..."
                    Task { importMessage = await model.importBookingExcel(id, data: data) }
                },
                onOpenMembers: onOpenMembers
            )
        }
    }

    /// Barra Salva in vetro in fondo: errori e messaggi sopra il pulsante.
    private func saveBar(appError: String?, errors: [String: String], canSave: Bool, dirty: Bool, item: CaseItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.actionError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            if let message = model.message { Text(message).appStyle(.bodySmall).foregroundStyle(Theme.primary) }
            if let error = siteModel.photoError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            if let appError { Text(appError).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            if !errors.isEmpty {
                Text("Controlla i campi: \(orderedUnique(errors.values.sorted()).joined(separator: " · "))")
                    .appStyle(.bodySmall)
                    .foregroundStyle(Theme.error)
            }
            Button {
                Task { _ = await save(item) }
            } label: {
                Text(model.busy ? "Salvataggio…" : dirty ? "Salva" : "Nessuna modifica").frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .disabled(!canSave)
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Invito a portare una casa "solo app" su siciliahost.com (beta gratuita).
struct PublishOnSiteCard: View {
    let busy: Bool
    let onPublish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pubblica sul sito").appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
            Text("Porta la casa su siciliahost.com: beta gratuita, nessuna commissione, pagamenti diretti con l'ospite. La gestisci comunque da qui.")
                .appStyle(.bodyMedium)
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.bottom, 6)
            Button(action: onPublish) { Text("Pubblica sul sito").frame(maxWidth: .infinity) }
                .buttonStyle(.appPrimary)
                .disabled(busy)
        }
        .padding(Dimens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

/// Conferma dell'eliminazione definitiva (`DeleteCaseDialog`): si riscrive il nome della casa.
struct DeleteCaseSheet: View {
    let name: String
    let id: String
    let canPause: Bool
    let busy: Bool
    let error: String?
    let onConfirm: (String) -> Void
    let onDismiss: () -> Void

    @State private var typed = ""

    var body: some View {
        let matches = DeleteCaseLogic.nameMatches(typed: typed, name: name, id: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Eliminare la casa?").appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
                Text("L'eliminazione è definitiva e non si può annullare. Anche i collaboratori perdono la casa.")
                    .appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                Text("Si cancellano foto, prenotazioni del calendario, storico delle Finanze, scorte, schede ospite e promozioni. Restano solo i pagamenti degli ospiti del sito, per la contabilità.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                if canPause {
                    Text("Vuoi solo fermarla per un periodo? Usa «Nascondi dal sito»: tieni tutti i dati.")
                        .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                }
                Text("Per confermare scrivi il nome della casa:").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                Text(DeleteCaseLogic.confirmName(name: name, id: id)).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                AppTextField(label: "Nome della casa", text: $typed, capitalization: .never)
                    .autocorrectionDisabled()
                    .disabled(busy)
                if let error { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
                HStack {
                    Spacer()
                    Button("Annulla", action: onDismiss).buttonStyle(.appText).disabled(busy)
                    Button(busy ? "Eliminazione…" : "Elimina per sempre") { onConfirm(typed.trimmed) }
                        .buttonStyle(.appText(color: Theme.error))
                        .disabled(!matches || busy)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }
}
