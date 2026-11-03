import SwiftUI

/// Valori di partenza di una casa nuova: l'host li cambia con − e +.
let defaultWizardGuests = "2"
let defaultWizardBedrooms = "1"

/// Creazione guidata di una casa in due livelli (`NewCaseWizardScreen.kt`): il primo chiede solo i dati dell'app (nome,
/// camere, ospiti) e finisce con l'invito a pubblicare sul sito; il secondo, se l'host accetta (`startSitePublication`),
/// chiede i dati dell'annuncio, a partire dall'import facoltativo da Airbnb/Booking. La casa nasce al primo "Avanti" e
/// ogni "Avanti" salva la fase con lo stesso salvataggio della scheda casa (`CasesModel.saveCase`).
///
/// `propertyId` = riprendere una casa esistente (nil = casa nuova), `level` = da quale livello partire. `onFinished` alla
/// fine (primo livello chiuso, bozza salvata o invio fatto), `onClose` uscendo prima.
struct NewCaseWizardView: View {
    let propertyId: String?
    let level: WizardLevel
    let onClose: () -> Void
    let onFinished: () -> Void

    @State private var cases = CasesModel()
    @State private var siteModel = SiteContentModel()
    @State private var importModel = ImportModel()

    @State private var id: String?
    @State private var step: WizardStep
    @State private var appDraft: AppFieldsDraft
    @State private var siteDraft = SiteDraft()
    @State private var initialized: Bool
    @State private var review: Set<String> = []
    @State private var airbnbLink = ""
    @State private var bookingLink = ""
    @State private var declared = false
    @State private var showExit = false
    @State private var showTerms = false
    @State private var showServices = false
    @State private var showDeclaration = false
    @State private var saving = false

    init(propertyId: String?, level: WizardLevel, onClose: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.propertyId = propertyId
        self.level = level
        self.onClose = onClose
        self.onFinished = onFinished
        _id = State(initialValue: propertyId)
        _step = State(initialValue: WizardLogic.startStep(level))
        var draft = AppFieldsDraft()
        draft.maxGuests = defaultWizardGuests
        draft.bedrooms = defaultWizardBedrooms
        _appDraft = State(initialValue: draft)
        _initialized = State(initialValue: propertyId == nil)
    }

    private var item: CaseItem? { id.flatMap { cases.item($0) } }
    private var site: PropertySiteContent? { id.flatMap { siteModel.content($0) } ?? item?.site }
    private var photoCount: Int { site?.photos.count ?? 0 }
    private var busy: Bool { saving || cases.busy || siteModel.photoBusy || siteModel.isSaving }

    private var siteOriginal: SiteDraft { item.map { SiteDraft($0.site) } ?? SiteDraft() }
    private var errors: [String: String] {
        var current = siteDraft
        current.published = siteOriginal.published
        return SiteDraftLogic.fieldErrors(original: siteOriginal, current: current)
    }

    var body: some View {
        Group {
            if showServices, let site {
                VStack(spacing: 0) {
                    CompactTopBar(title: "Servizi", onBack: { showServices = false })
                    ServicesEditorView(content: site, siteModel: siteModel) {
                        showServices = false
                        review.remove(ReviewKey.services)
                        Task { await cases.load() }
                    }
                }
            } else {
                wizard
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if id != nil {
                await cases.load()
                await siteModel.load()
            }
            // Bozza ripresa: le bozze partono dai valori salvati, una volta sola.
            if !initialized, let item {
                appDraft = AppFieldsDraft(item.property)
                siteDraft = SiteDraft(item.site)
                initialized = true
            }
        }
        // Import terminato: le bozze si compilano una volta sola, solo i campi vuoti.
        .onChange(of: importModel.importId) { _, _ in
            guard shouldApplyImport(importModel.ui, applied: importModel.applied), let result = importModel.ui.result else { return }
            let applied = applyImport(result.draft, app: appDraft, site: siteDraft)
            appDraft = applied.app
            siteDraft = applied.site
            review = applied.review
            importModel.markApplied(applied)
        }
        .confirmationDialog("Uscire dalla procedura?", isPresented: $showExit, titleVisibility: .visible) {
            Button(id == nil ? "Esci" : "Salva ed esci") {
                if id == nil {
                    onClose()
                } else {
                    Task {
                        if await saveStep() {
                            AccessEvents.shared.notifyChanged()
                            onClose()
                        }
                    }
                }
            }
            .disabled(busy)
            Button("Continua", role: .cancel) {}
        } message: {
            Text(id == nil ? "La casa non è ancora stata creata."
                : step.level == .app ? "La casa resta nell'app: puoi completare o pubblicare quando vuoi."
                : "La casa resta in bozza nel tab Case: puoi completarla quando vuoi.")
        }
        .sheet(isPresented: $showTerms) {
            HostTermsSheet(onAccept: {
                showTerms = false
                // Prima si salva l'ultima fase, poi si invia: il server controlla i dati salvati.
                Task {
                    guard await saveStep(), let current = id else { return }
                    if await cases.submit(current) { finish() }
                }
            }, onDismiss: { showTerms = false })
        }
        .alert("Dichiarazione", isPresented: $showDeclaration) {
            Button("Chiudi", role: .cancel) {}
        } message: {
            Text(ownershipText)
        }
    }

    // MARK: Struttura

    private var wizard: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: propertyId == nil ? "Nuova casa" : "Completa la casa", onBack: { showExit = true })
            StepProgress(step: step).padding(.horizontal, Dimens.screenPadding).padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing + 4) {
                    Text(step.title).appStyle(.headlineMedium).foregroundStyle(Theme.onSurface)
                    Text(step.hint).appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                    if !review.isDisjoint(with: reviewKeysFor(step)) {
                        ReviewBanner { review.subtract(reviewKeysFor(step)) }
                    }
                    stepContent
                    Spacer(minLength: 24)
                }
                .padding(Dimens.screenPadding)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    private var appBinding: Binding<AppFieldsDraft> {
        Binding(get: { appDraft }, set: { new in
            // Toccare un campo importato toglie il suo marcatore.
            review.subtract(touchedKeys(appDraft, new))
            appDraft = new
        })
    }

    private var siteBinding: Binding<SiteDraft> {
        Binding(get: { siteDraft }, set: { new in
            review.subtract(touchedKeys(siteDraft, new))
            siteDraft = new
        })
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .importa:
            ImportStepView(airbnb: $airbnbLink, booking: $bookingLink, declared: $declared, ui: importModel.ui,
                           onShowDeclaration: { showDeclaration = true })
        case .struttura:
            StrutturaStep(draft: appBinding)
        case .invito:
            InvitoStep()
        case .casa:
            AppTextField(label: "CIN (Codice Identificativo Nazionale)", text: appBinding.cin, capitalization: .characters)
            SubsectionTitle(text: "Letti e bagni")
            FieldPair {
                AppTextField(label: "Letti", text: appBinding.beds, keyboard: .numberPad)
            } b: {
                AppTextField(label: "Bagni", text: appBinding.bathrooms, keyboard: .decimalPad)
            }
        case .dove:
            PosizioneSection(draft: siteBinding, errors: errors)
        case .foto:
            if let site {
                ImportedPhotosView(model: importModel, propertyId: site.id, existing: site.photos) { await siteModel.load() }
                SitePhotosSection(content: site, siteModel: siteModel)
            } else {
                ProgressView()
            }
        case .descrizione:
            SiteTextField(label: "Descrizione", text: appBinding.description, multiline: true)
            SectionNote(text: "Puoi scriverla in italiano: le traduzioni per il sito si aggiungono dalla scheda della casa.")
            Button { showServices = true } label: {
                Text("Scegli i servizi (Wi-Fi, aria condizionata…)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.appOutlined)
            .disabled(site == nil)
        case .prezzi:
            PrezziSection(draft: siteBinding, errors: errors, onOpenPriceEditor: nil)
            SubsectionTitle(text: "Orari")
            FieldPair {
                AppTextField(label: "Check-in dalle", text: appBinding.checkInTime, keyboard: .numbersAndPunctuation)
            } b: {
                AppTextField(label: "Check-out entro le", text: appBinding.checkOutTime, keyboard: .numbersAndPunctuation)
            }
        case .riepilogo:
            RiepilogoStep(app: appDraft, site: siteDraft, photoCount: photoCount) { step = $0 }
        }
    }

    // MARK: Barra in basso

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = cases.actionError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            if let error = siteModel.saveError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            if let error = siteModel.photoError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
            // Sulla prima fase il nome vuoto blocca già "Avanti": l'errore si mostra dalle altre.
            if step != .struttura && step != .importa, let error = appDraft.error() {
                Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
            }
            bottomButtons
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var bottomButtons: some View {
        switch step {
        case .importa:
            if importModel.ui.result != nil {
                Button { step = .casa } label: { Text("Avanti").frame(maxWidth: .infinity) }.buttonStyle(.appPrimary)
            } else {
                let links = importLinks
                let badLinks = urlProblem(.airbnb, airbnbLink) != nil || urlProblem(.booking, bookingLink) != nil
                Button {
                    Task { await importModel.start(links: links) }
                } label: {
                    Group {
                        if importModel.ui.isRunning { ProgressView().tint(Theme.onPrimary) } else { Text("Importa") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .disabled(links.isEmpty || badLinks || !declared || importModel.ui.isRunning)
                Button { step = .casa } label: { Text("Salta, compilo io").frame(maxWidth: .infinity) }
                    .buttonStyle(.appOutlined)
                    .disabled(importModel.ui.isRunning)
            }
        case .invito:
            Button {
                guard let current = id else { return }
                Task {
                    if await cases.startSitePublication(current) { step = WizardLogic.steps(.site)[0] }
                }
            } label: { Text("Pubblica sul sito").frame(maxWidth: .infinity) }
                .buttonStyle(.appPrimary)
                .disabled(busy || id == nil)
            Button(action: finish) { Text("Più tardi").frame(maxWidth: .infinity) }
                .buttonStyle(.appOutlined)
                .disabled(busy)
        case .riepilogo:
            let ready = WizardLogic.missing(app: appDraft, site: siteDraft, photoCount: photoCount).isEmpty
            Button { showTerms = true } label: { Text("Invia per approvazione").frame(maxWidth: .infinity) }
                .buttonStyle(.appPrimary)
                .disabled(!ready || busy || id == nil)
            Button {
                Task { if await saveStep() { finish() } }
            } label: { Text("Salva come bozza e continua dopo").frame(maxWidth: .infinity) }
                .buttonStyle(.appOutlined)
                .disabled(busy)
        default:
            HStack(spacing: 10) {
                if step.previous != nil {
                    Button("Indietro") { back() }.buttonStyle(.appOutlined).disabled(busy)
                }
                Button {
                    Task {
                        if await saveStep(), let next = step.next { step = next }
                    }
                } label: {
                    Group {
                        if busy { ProgressView().tint(Theme.onPrimary) } else { Text("Avanti") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .disabled(!WizardLogic.canAdvance(step, app: appDraft) || appDraft.error() != nil || !errors.isEmpty || busy)
            }
        }
    }

    private var importLinks: [Portal: String] {
        var links: [Portal: String] = [:]
        if let url = cleanListingUrl(.airbnb, airbnbLink) { links[.airbnb] = url }
        if let url = cleanListingUrl(.booking, bookingLink) { links[.booking] = url }
        return links
    }

    private func back() {
        if let previous = step.previous { step = previous } else { showExit = true }
    }

    /// Fine della procedura: la schermata principale ricarica le case (la prima casa porta fuori dall'onboarding).
    private func finish() {
        AccessEvents.shared.notifyChanged()
        onFinished()
    }

    // MARK: Salvataggio

    /// Salva la fase corrente (e crea la casa la prima volta). Vero se riuscito.
    private func saveStep() async -> Bool {
        saving = true
        defer { saving = false }
        var pid = id
        if pid == nil {
            guard let created = await cases.createCase(name: appDraft.name) else { return false }
            id = created
            pid = created
            await siteModel.load()
        }
        guard let pid, let current = cases.item(pid) else { return false }
        let original = SiteDraft(current.site)
        var site = siteDraft
        site.published = original.published
        guard await cases.saveCase(
            pid, originalApp: AppFieldsDraft(current.property), currentApp: appDraft,
            originalSite: original, currentSite: site, photos: current.site.photos
        ) else { return false }
        // Servizi, regole e tipo di check-in importati: non stanno nelle bozze, si scrivono ora. Si cancellano solo a
        // scrittura riuscita, e in ogni caso si prosegue.
        if !importModel.pendingPatch.isEmpty, await siteModel.savePatch(pid, importModel.pendingPatch) {
            importModel.clearSitePatch()
        }
        // Le bozze ripartono dai valori salvati (normalizzati: "90,00" → "90"), altrimenti ogni salvataggio successivo
        // riscriverebbe tutto.
        if let fresh = cases.item(pid) {
            appDraft = AppFieldsDraft(fresh.property)
            siteDraft = SiteDraft(fresh.site)
        }
        return true
    }
}

// MARK: Parti

/// Barra di avanzamento a tacche: fatte verdi, quella corrente piena, le prossime chiare.
private struct StepProgress: View {
    let step: WizardStep

    var body: some View {
        let steps = WizardLogic.steps(step.level)
        let current = steps.firstIndex(of: step) ?? 0
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index < current ? Theme.primary.opacity(0.55) : index == current ? Theme.primary : Theme.outlineVariant.opacity(0.6))
                    .frame(height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passo \(current + 1) di \(steps.count)")
    }
}

/// Fase "La tua struttura": nome, camere e ospiti massimi. Solo il nome è obbligatorio.
private struct StrutturaStep: View {
    @Binding var draft: AppFieldsDraft

    var body: some View {
        VStack(spacing: 16) {
            AppTextField(label: "Nome della struttura", text: $draft.name, supporting: "Es. Casa sul mare", capitalization: .words)
            Counter(label: "Camere da letto", value: $draft.bedrooms, min: 1)
            Counter(label: "Ospiti massimi", value: $draft.maxGuests, min: 1)
        }
    }
}

/// Un numero intero con − e +, senza tastiera.
private struct Counter: View {
    let label: String
    @Binding var value: String
    let min: Int

    var body: some View {
        let n = Int(value.trimmed) ?? min
        HStack(spacing: 12) {
            Text(label).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface).frame(maxWidth: .infinity, alignment: .leading)
            Button { value = String(Swift.max(n - 1, min)) } label: { Image(systemName: "minus") }
                .buttonStyle(.appIcon)
                .disabled(n <= min)
                .accessibilityLabel("Meno: \(label)")
            Text("\(n)").appStyle(.titleMedium).foregroundStyle(Theme.onSurface).frame(minWidth: 28)
            Button { value = String(Swift.min(n + 1, 99)) } label: { Image(systemName: "plus") }
                .buttonStyle(.appIcon)
                .disabled(n >= 99)
                .accessibilityLabel("Più: \(label)")
        }
        .frame(minHeight: 48)
    }
}

/// Ultima fase del primo livello (pubblicare sul sito): tre icone; i pulsanti stanno nella barra in basso.
private struct InvitoStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("lock.fill", "Resta privata", "La casa è già pronta nell'app: la usi da sola per gestire le prenotazioni.")
            row("globe", "Online, se vuoi", "Pubblicala su siciliahost.com: nessuna commissione durante la beta.")
            row("laptopcomputer", "Anche dal sito", "Una volta creata, la modifichi anche dal pannello su siciliahost.com.")
        }
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.primary).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                Text(text).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }
}

private struct RiepilogoStep: View {
    let app: AppFieldsDraft
    let site: SiteDraft
    let photoCount: Int
    let onGoTo: (WizardStep) -> Void

    var body: some View {
        ForEach(WizardLogic.steps(.site).filter { $0 != .riepilogo }, id: \.self) { s in
            let missing = WizardLogic.stepMissing(s, app: app, site: site, photoCount: photoCount)
            let ok = missing.isEmpty
            Button { onGoTo(s) } label: {
                HStack(spacing: 12) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(ok ? Theme.primary : Theme.secondary)
                        .accessibilityLabel(ok ? "Completa" : "Da completare")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                        Text(ok ? "Fatto" : "Manca: \(missing.joined(separator: ", "))")
                            .appStyle(.bodySmall)
                            .foregroundStyle(ok ? Theme.onSurfaceVariant : Theme.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(14)
                .appCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if !WizardLogic.missing(app: app, site: site, photoCount: photoCount).isEmpty {
            SectionNote(text: "Puoi salvare la bozza e completarla dopo dal tab Case: per l'invio servono tutte le voci.")
        }
    }
}

/// Banner in cima a un passo con campi importati: sparisce quando l'host tocca i campi o preme «Va bene».
private struct ReviewBanner: View {
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.secondary)
            Text("Importato dall'annuncio: controlla").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Va bene", action: onConfirm).buttonStyle(.appOutlined)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appCard()
    }
}

/// Passo «Da dove parti?»: due link, la dichiarazione di proprietà, l'avanzamento per portale e, a fine import, cosa si è
/// trovato. I pulsanti «Importa» e «Salta» stanno nella barra in basso del wizard.
private struct ImportStepView: View {
    @Binding var airbnb: String
    @Binding var booking: String
    @Binding var declared: Bool
    let ui: ImportUi
    let onShowDeclaration: () -> Void

    var body: some View {
        let running = ui.isRunning
        VStack(alignment: .leading, spacing: 14) {
            AppTextField(label: "Link Airbnb", text: $airbnb, supporting: "Incolla il link dell'annuncio",
                         error: urlProblem(.airbnb, airbnb), keyboard: .URL, capitalization: .never)
                .disabled(running)
            AppTextField(label: "Link Booking", text: $booking, supporting: "Incolla il link dell'annuncio",
                         error: urlProblem(.booking, booking), keyboard: .URL, capitalization: .never)
                .disabled(running)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: declared ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(declared ? Theme.primary : Theme.onSurfaceVariant)
                        .accessibilityLabel(declared ? "Dichiarazione data" : "Dichiarazione mancante")
                    Text("Sono il proprietario di questi annunci").appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                }
                FlowButtons {
                    Button(declared ? "Dichiarato" : "Dichiaro") { declared.toggle() }
                        .buttonStyle(.appPrimary)
                        .disabled(running)
                    Button { onShowDeclaration() } label: { Label("Leggi il testo", systemImage: "info.circle") }
                        .buttonStyle(.appText)
                }
            }
            .padding(14)
            .appCard()

            switch ui {
            case .idle:
                EmptyView()
            case let .running(portals):
                PortalRow(portals: portals, working: true)
            case let .failed(message, portals):
                PortalRow(portals: portals, working: false)
                Text(message).appStyle(.bodyMedium).foregroundStyle(Theme.error)
            case let .done(result, portals):
                PortalRow(portals: portals, working: false)
                if !result.failedPortals.isEmpty {
                    Text("Non ho potuto leggere: \(result.failedPortals.map(\.capitalized).joined(separator: ", "))")
                        .appStyle(.bodySmall).foregroundStyle(Theme.error)
                }
                FlowButtons {
                    ForEach(foundChips(result.draft), id: \.key) { chip in FoundChipView(chip: chip) }
                }
                ForEach(result.draft.conflicts, id: \.field) { c in
                    let values = c.values.sorted { $0.key < $1.key }.map { "\($0.key.capitalized) \($0.value)" }.joined(separator: " · ")
                    Text("\(conflictLabel(c.field)): \(values). Ho scelto \(c.chosen).")
                        .appStyle(.bodySmall).foregroundStyle(Theme.secondary)
                }
                SectionNote(text: "Controlla i dati nei prossimi passi: li ho segnati.")
            }
        }
    }

    private func conflictLabel(_ field: String) -> String {
        switch field {
        case "bathrooms": return "Bagni"
        case "bedrooms": return "Camere"
        case "beds": return "Letti"
        case "maxGuests": return "Ospiti"
        case "name": return "Nome"
        case "pets": return "Animali"
        case "smoking": return "Fumo"
        case "parties": return "Feste"
        default: return field
        }
    }
}

/// Una pastiglia per portale: gira mentre scarica, poi segno verde o rosso; il testo dice lo stato.
private struct PortalRow: View {
    let portals: [Portal: PortalStatus]
    let working: Bool

    var body: some View {
        FlowButtons {
            ForEach(Portal.allCases.filter { portals[$0] != nil }, id: \.self) { portal in
                let status = portals[portal] ?? .waiting
                HStack(spacing: 8) {
                    switch status {
                    case .waiting, .downloading:
                        if working { ProgressView().controlSize(.small) }
                    case .ok:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                    case .failed:
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.error)
                    }
                    Text("\(portal.label): \(label(status))").appStyle(.labelLarge).foregroundStyle(Theme.onSurface)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .appCard()
            }
        }
    }

    private func label(_ status: PortalStatus) -> String {
        switch status {
        case .waiting: return "in attesa"
        case .downloading: return "scarico"
        case .ok: return "letto"
        case .failed: return "non riuscito"
        }
    }
}

private struct FoundChipView: View {
    let chip: FoundChip

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: chip.found ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(chip.found ? Theme.primary : Theme.outline)
                .accessibilityLabel(chip.found ? "Trovato" : "Non trovato")
            Text(chip.label + (chip.count.map { " · \($0)" } ?? ""))
                .appStyle(.labelLarge)
                .foregroundStyle(chip.found ? Theme.onSurface : Theme.outline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appCard()
    }
}

/// Avanzamento del download delle foto degli annunci: parte da solo entrando nel passo Foto.
private struct ImportedPhotosView: View {
    let model: ImportModel
    let propertyId: String
    let existing: [String]
    let onProgress: () async -> Void

    var body: some View {
        Group {
            switch model.photoUi {
            case .idle:
                EmptyView()
            case let .running(done, total):
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scarico le foto… \(done)/\(total)").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                }
            case let .done(saved, failed):
                if failed > 0 {
                    Text("\(saved) foto importate, \(failed) non scaricate.").appStyle(.bodySmall).foregroundStyle(Theme.secondary)
                }
            case let .failed(message, _):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).appStyle(.bodySmall).foregroundStyle(Theme.error)
                    Button("Riprova") {
                        Task { await model.retryPhotos(propertyId: propertyId, existing: existing, onProgress: onProgress) }
                    }
                    .buttonStyle(.appOutlined)
                }
            }
        }
        .task(id: "\(model.importId ?? "")-\(propertyId)") {
            if model.importId != nil, model.photoTotal > 0, model.photoUi == .idle {
                await model.importPhotos(propertyId: propertyId, existing: existing, onProgress: onProgress)
            }
        }
    }
}
