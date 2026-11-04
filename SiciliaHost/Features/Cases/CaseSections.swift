import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Le sezioni della scheda casa (`CaseSections.kt`, `SitePhotosSection.kt`, `SiteTranslationsSection.kt`,
// `SiteFormParts.kt`). I campi sono quelli dei vecchi form Immobili e Sito, solo spostati in sezioni comprimibili.

/// Una sezione comprimibile: titolo da toccare e, se aperta, il contenuto.
struct CaseSectionCard<Content: View>: View {
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(title).appStyle(.titleMedium).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .accessibilityLabel(expanded ? "Comprimi" : "Espandi")
                }
                .padding(Dimens.cardPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) { content() }
                    .padding([.horizontal, .bottom], Dimens.cardPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

/// Campo dei moduli del sito (`SiteField`): una riga o più righe, con errore sotto.
struct SiteTextField: View {
    let label: String
    @Binding var text: String
    var error: String?
    var keyboard: UIKeyboardType = .default
    var multiline = false
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        FieldFrame(label: label, error: error) {
            Group {
                if multiline {
                    TextField("", text: $text, axis: .vertical).lineLimit(2 ... 8)
                } else {
                    TextField("", text: $text)
                }
            }
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .appStyle(.bodyLarge)
            .foregroundStyle(Theme.onSurface)
            .accessibilityLabel(label)
        }
    }
}

struct SectionNote: View {
    let text: String

    var body: some View { Text(text).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant) }
}

struct SubsectionTitle: View {
    let text: String

    var body: some View { Text(text).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).padding(.top, 6) }
}

/// Riga con testo e interruttore.
struct SwitchRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { Text(label).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface) }
            .tint(Theme.primary)
    }
}

/// Due campi affiancati (`FieldRow`): su schermi stretti restano comunque uno accanto all'altro.
struct FieldPair<A: View, B: View>: View {
    @ViewBuilder let a: () -> A
    @ViewBuilder let b: () -> B

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            a().frame(maxWidth: .infinity)
            b().frame(maxWidth: .infinity)
        }
    }
}

// MARK: Informazioni

struct InformazioniSection: View {
    @Binding var draft: AppFieldsDraft
    let enabled: Bool

    @State private var importUrl = ""
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        if enabled {
            SubsectionTitle(text: "Importa da Airbnb")
            HStack(alignment: .center, spacing: 8) {
                AppTextField(label: "Link annuncio Airbnb", text: $importUrl, keyboard: .URL, capitalization: .never)
                Button {
                    Task { await importFromAirbnb() }
                } label: {
                    if importing { ProgressView().tint(Theme.onPrimary) } else { Text("Importa") }
                }
                .buttonStyle(.appPrimary)
                .disabled(importUrl.trimmed.isEmpty || importing)
            }
            if let importError { Text(importError).appStyle(.bodySmall).foregroundStyle(Theme.error) }
        }
        Group {
            AppTextField(label: "Nome struttura", text: $draft.name, capitalization: .words)
            AppTextField(label: "CIN (Codice Identificativo Nazionale)", text: $draft.cin, capitalization: .characters)
            SubsectionTitle(text: "Capienza")
            FieldPair {
                AppTextField(label: "Ospiti max", text: $draft.maxGuests, keyboard: .numberPad)
            } b: {
                AppTextField(label: "Camere", text: $draft.bedrooms, keyboard: .numberPad)
            }
            FieldPair {
                AppTextField(label: "Letti", text: $draft.beds, keyboard: .numberPad)
            } b: {
                AppTextField(label: "Bagni", text: $draft.bathrooms, keyboard: .decimalPad)
            }
            SubsectionTitle(text: "Descrizione")
            SiteTextField(label: "Descrizione struttura", text: $draft.description, multiline: true)
            SubsectionTitle(text: "Servizi (testo libero)")
            FieldFrame(
                label: "Un servizio per riga (es. Wifi, Cucina, TV...)",
                supporting: "Se in Contenuti della pagina → Servizi hai già impostato i servizi, il sito usa quelli e non questo elenco."
            ) {
                TextField("", text: $draft.amenitiesText, axis: .vertical)
                    .lineLimit(3 ... 10)
                    .appStyle(.bodyLarge)
                    .foregroundStyle(Theme.onSurface)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }

    private func importFromAirbnb() async {
        importing = true
        importError = nil
        let result = await scrapeAirbnbListing(url: importUrl.trimmed)
        importing = false
        guard let result else {
            importError = "Impossibile leggere l'annuncio, inserisci i dati manualmente."
            return
        }
        // Si parte dalla bozza di adesso: nel frattempo l'utente ha potuto scrivere altro.
        var d = draft
        if let v = result.name { d.name = v }
        if let v = result.description { d.description = v }
        if let v = result.maxGuests { d.maxGuests = String(v) }
        if let v = result.bedrooms { d.bedrooms = String(v) }
        if let v = result.beds { d.beds = String(v) }
        if let v = result.bathrooms { d.bathrooms = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : "\(v)" }
        draft = d
    }
}

// MARK: Orari e regole

struct OrariRegoleSection: View {
    @Binding var draft: AppFieldsDraft
    let enabled: Bool

    var body: some View {
        Group {
            FieldPair {
                AppTextField(label: "Check-in dopo (es. 15:00)", text: $draft.checkInTime, keyboard: .numbersAndPunctuation)
            } b: {
                AppTextField(label: "Check-out entro (es. 11:00)", text: $draft.checkOutTime, keyboard: .numbersAndPunctuation)
            }
            SiteTextField(label: "Altre regole della casa", text: $draft.houseRules, multiline: true)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

// MARK: Gestione (iCal, commissione, Alloggiati, membri)

struct GestioneSection: View {
    let property: Property
    @Binding var draft: AppFieldsDraft
    @Binding var creds: CredsState
    let isOwner: Bool
    let isSuperAdmin: Bool
    @Binding var importMessage: String?
    let onImport: (Data) -> Void
    let onSyncNow: () -> Void
    let onOpenMembers: () -> Void

    @State private var picking = false

    var body: some View {
        SubsectionTitle(text: "Sincronizzazione calendari (iCal)")
        AppTextField(label: "URL iCal Airbnb", text: $draft.icalUrlAirbnb, keyboard: .URL, capitalization: .never)
        AppTextField(label: "URL iCal Booking", text: $draft.icalUrlBooking, keyboard: .URL, capitalization: .never)
        SectionNote(text: "L'iCal Booking importa le date bloccate come prenotazioni da completare (nome/importo). Per prezzo e contatti già pronti usa anche \"Importa Excel Booking\".")
        FlowButtons {
            // "Sincronizza ora" usa gli URL salvati: con modifiche non salvate si salva prima.
            if !ICalSyncService.feeds(of: property).isEmpty {
                Button("Sincronizza ora", action: onSyncNow).buttonStyle(.appOutlined)
            }
            Button("Importa Excel Booking") { picking = true }
                .buttonStyle(.appOutlined)
                .tourTarget(.caseBookingImport)
            if isOwner { Button("Membri e inviti", action: onOpenMembers).buttonStyle(.appOutlined) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                onImport(data)
            } else {
                importMessage = "Impossibile aprire il file selezionato"
            }
        }
        if let importMessage {
            HStack {
                Text(importMessage).appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("OK") { self.importMessage = nil }.buttonStyle(.appText)
            }
        }

        if isSuperAdmin {
            SwitchRow(label: "Gestione a commissione (21% tasse + tuo 25%+50€)", isOn: $draft.isManagedOnCommission)
                .padding(.top, 6)
        }

        SubsectionTitle(text: "Credenziali Alloggiati Web")
        switch creds {
        case .loading:
            ProgressView()
        case .unavailable:
            SectionNote(text: "Non disponibili (non sei il proprietario di questa casa, oppure non si sono potute leggere). Riprova più tardi.")
            // L'ID Appartamento non è un segreto (sta sul documento della casa): resta modificabile.
            AppTextField(label: "ID Appartamento", text: $draft.idAppartamento, keyboard: .numberPad)
        case let .ready(c):
            FieldPair {
                AppTextField(label: "Utente", text: credsBinding(c, \.utente), capitalization: .never)
            } b: {
                SecureCredentialField(label: "Password", text: credsBinding(c, \.password))
            }
            FieldPair {
                SecureCredentialField(label: "WsKey", text: credsBinding(c, \.wsKey))
            } b: {
                AppTextField(label: "ID Appartamento", text: $draft.idAppartamento, keyboard: .numberPad)
            }
        }
    }

    /// Le credenziali restano solo in memoria (mai salvate sul telefono): sono segreti.
    private func credsBinding(_ current: AlloggiatiCredentials, _ field: WritableKeyPath<AlloggiatiCredentials, String>) -> Binding<String> {
        Binding(
            get: { creds.value?[keyPath: field] ?? current[keyPath: field] },
            set: { newValue in
                var updated = creds.value ?? current
                updated[keyPath: field] = newValue
                creds = .ready(updated)
            }
        )
    }
}

struct SecureCredentialField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        FieldFrame(label: label) {
            SecureField("", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .appStyle(.bodyLarge)
                .foregroundStyle(Theme.onSurface)
                .accessibilityLabel(label)
        }
    }
}

// MARK: Prezzi e prenotazione

struct PrezziSection: View {
    @Binding var draft: SiteDraft
    let errors: [String: String]
    let onOpenPriceEditor: (() -> Void)?

    var body: some View {
        FieldPair {
            SiteTextField(label: "Prezzo a notte (€)", text: $draft.price, error: errors["price"], keyboard: .decimalPad)
        } b: {
            SiteTextField(label: "Pulizie (€)", text: $draft.cleaningFee, error: errors["cleaningFee"], keyboard: .decimalPad)
        }
        FieldPair {
            SiteTextField(label: "Caparra (%)", text: $draft.depositPercentage, error: errors["deposit"], keyboard: .decimalPad)
        } b: {
            SiteTextField(label: "Cancellazione gratuita (giorni prima)", text: $draft.freeCancelDays,
                          error: errors["freeCancelDays"], keyboard: .numberPad)
        }
        SwitchRow(label: "Conferma manuale della prenotazione", isOn: $draft.manualConfirmation)
        if let onOpenPriceEditor {
            Button(action: onOpenPriceEditor) { Text("Prezzi per date, extra e promozioni").frame(maxWidth: .infinity) }
                .buttonStyle(.appOutlined)
        }
    }
}

// MARK: Contenuti della pagina

struct ContenutiSection: View {
    let content: PropertySiteContent
    let onOpen: (CaseSubEditor) -> Void

    var body: some View {
        SectionNote(text: "Servizi, regole, accesso, dintorni e host: si salvano a parte, con il loro pulsante.")
        Button { onOpen(.services) } label: {
            Text("Servizi (\(content.services?.count ?? content.amenities.count))").frame(maxWidth: .infinity)
        }
        .buttonStyle(.appOutlined)
        Button { onOpen(.details) } label: { Text("Regole, accesso, dintorni e host").frame(maxWidth: .infinity) }
            .buttonStyle(.appOutlined)
    }
}

// MARK: Posizione

struct PosizioneSection: View {
    @Binding var draft: SiteDraft
    let errors: [String: String]

    var body: some View {
        SiteTextField(label: "Zona", text: $draft.zone, error: errors["zone"], capitalization: .words)
        PositionSection(draft: $draft, errors: errors)
    }
}

// MARK: Info per gli ospiti

struct InfoOspitiSection: View {
    let content: PropertySiteContent
    @Binding var draft: SiteDraft
    let errors: [String: String]

    var body: some View {
        FieldPair {
            SiteTextField(label: "Wi-Fi (nome rete)", text: $draft.wifiSsid, capitalization: .never)
        } b: {
            SiteTextField(label: "Wi-Fi (password)", text: $draft.wifiPassword, capitalization: .never)
        }
        FieldPair {
            SiteTextField(label: "Referente (nome)", text: $draft.managerName, capitalization: .words)
        } b: {
            SiteTextField(label: "Referente (telefono)", text: $draft.managerPhone, keyboard: .phonePad)
        }
        SiteTranslationsSection(content: content, draft: $draft, errors: errors)
    }
}

/// Titolo, descrizione e regole: l'italiano è dell'app (si modifica in Informazioni, qui sola lettura), le altre lingue
/// sono del sito. Consigli locali e checklist di partenza sono del sito e si scrivono in tutte e quattro le lingue.
struct SiteTranslationsSection: View {
    let content: PropertySiteContent
    @Binding var draft: SiteDraft
    let errors: [String: String]

    @State private var lang = "en"

    var body: some View {
        SubsectionTitle(text: "Traduzioni")
        FlowButtons {
            ForEach(allSiteLangs, id: \.self) { code in
                FilterChip(label: code.uppercased(), selected: lang == code) { lang = code }
            }
        }
        let upper = lang.uppercased()
        if lang == "it" {
            SectionNote(text: "Titolo, descrizione e regole in italiano si modificano in Informazioni.")
            ReadOnlyField(label: "Titolo (IT)", value: content.name)
            ReadOnlyField(label: "Descrizione (IT)", value: content.description ?? "")
            ReadOnlyField(label: "Regole della casa (IT)", value: content.houseRules ?? "")
        } else {
            SiteTextField(label: "Titolo (\(upper))", text: textBinding(\.titleTr))
            SiteTextField(label: "Descrizione (\(upper))", text: textBinding(\.descriptionTr), multiline: true)
            SiteTextField(label: "Regole della casa (\(upper))", text: textBinding(\.houseRulesTr), multiline: true)
        }
        SiteTextField(label: "Consigli locali (\(upper))", text: textBinding(\.localTips), error: errors["localTips"], multiline: true)
        SiteTextField(label: "Checklist di partenza (\(upper))", text: textBinding(\.departureChecklist),
                      error: errors["departureChecklist"], multiline: true)
    }

    private func textBinding(_ field: WritableKeyPath<SiteDraft, [String: String]>) -> Binding<String> {
        let code = lang
        return Binding(
            get: { draft[keyPath: field][code] ?? "" },
            set: { draft[keyPath: field][code] = $0 }
        )
    }
}

struct ReadOnlyField: View {
    let label: String
    let value: String

    var body: some View {
        FieldFrame(label: label) {
            Text(value.isEmpty ? "—" : value).appStyle(.bodyLarge).foregroundStyle(Theme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Foto

/// Le foto della casa: la prima è la copertina; aggiungere, spostare e togliere salvano subito.
struct SitePhotosSection: View {
    let content: PropertySiteContent
    let siteModel: SiteContentModel

    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingDelete: Int?

    var body: some View {
        SectionNote(text: "La prima foto è la copertina. Le modifiche alle foto si salvano subito.")
        if siteModel.photoBusy { ProgressView().progressViewStyle(.linear).tint(Theme.primary) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(content.photos.enumerated()), id: \.offset) { index, url in
                    photoTile(index: index, url: url)
                }
            }
        }
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Aggiungi foto", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.appOutlined)
        .disabled(siteModel.photoBusy)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await siteModel.addPhoto(content.id, imageData: data)
                } else {
                    siteModel.photoError = "Impossibile leggere la foto"
                }
            }
        }
        if let error = siteModel.photoError { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
        Color.clear.frame(height: 0)
            .alert("Eliminare la foto?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Elimina", role: .destructive) {
                    if let index = pendingDelete { Task { await siteModel.deletePhoto(content.id, at: index) } }
                    pendingDelete = nil
                }
                Button("Annulla", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("La foto verrà rimossa dal sito e cancellata definitivamente.")
            }
    }

    private func photoTile(index: Int, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: URL(string: url)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.surfaceContainerHigh
            }
            .frame(width: 156, height: 100)
            .clipShape(roundedShape(Radius.small))
            .accessibilityLabel(index == 0 ? "Foto di copertina" : "Foto \(index + 1)")
            if index == 0 { Text("Copertina").appStyle(.labelSmall).foregroundStyle(Theme.primary) }
            HStack {
                Button { Task { await siteModel.reorderPhoto(content.id, from: index, to: index - 1) } } label: {
                    Image(systemName: "arrow.left")
                }
                .accessibilityLabel("Sposta prima")
                .disabled(index == 0 || siteModel.photoBusy)
                Spacer()
                Button { Task { await siteModel.reorderPhoto(content.id, from: index, to: index + 1) } } label: {
                    Image(systemName: "arrow.right")
                }
                .accessibilityLabel("Sposta dopo")
                .disabled(index == content.photos.count - 1 || siteModel.photoBusy)
                Spacer()
                Button { pendingDelete = index } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Elimina foto")
                    .disabled(siteModel.photoBusy)
            }
            .buttonStyle(.appIcon)
        }
        .frame(width: 156)
    }
}

// MARK: Stato e pubblicazione

/// Dove si corregge ciascuna voce della checklist "Mancano".
func sectionForMissing(_ label: String) -> CaseSection {
    if label == WizardLogic.missingCin { return .informazioni }
    if label.hasPrefix("Zona") { return .posizione }
    if label.hasPrefix("Almeno una foto") { return .foto }
    return .prezzi
}

struct StatoSection: View {
    let item: CaseItem
    let site: PropertySiteContent
    let scope: AccessScope
    let model: CasesModel
    let missing: [String]
    let dirty: Bool
    let onGoTo: (CaseSection) -> Void

    @State private var showApprove = false
    @State private var showTerms = false
    @State private var showReject = false
    @State private var reasons = ""

    var body: some View {
        let status = site.status
        let id = item.property.id
        // Chi invia è l'host (o chi ha il permesso SITE); il super-admin sulle case altrui non invia al posto loro.
        let canSubmit = !scope.isSuperAdmin || item.property.memberUids.contains(scope.uid)

        HStack(spacing: 8) {
            ListingStatusPill(status: status)
            Text(statusText(status)).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let text = site.rejection?.reasons, !text.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Motivi del rifiuto").appStyle(.labelLarge)
                Text(text).appStyle(.bodyMedium)
            }
            .foregroundStyle(Theme.onErrorContainer)
            .padding(Dimens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(roundedShape(Radius.small).fill(Theme.errorContainer))
        }

        if status == .draft || status == .rejected {
            if missing.isEmpty {
                Text("Pronto per l'invio.").appStyle(.bodyMedium).foregroundStyle(Theme.primary)
            } else {
                Text("Per inviare mancano:").appStyle(.labelLarge).foregroundStyle(Theme.onSurface)
                ForEach(missing, id: \.self) { label in
                    Button { onGoTo(sectionForMissing(label)) } label: {
                        Text("• \(label)").appStyle(.bodyMedium).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Azioni dell'host
        if (status == .draft || status == .rejected) && canSubmit {
            Button { showTerms = true } label: {
                Text(status == .rejected ? "Invia di nuovo per approvazione" : "Invia per approvazione").frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .disabled(!missing.isEmpty || dirty || model.busy)
            if dirty && missing.isEmpty {
                SectionNote(text: "Salva prima le modifiche, poi invia.")
            }
        }
        if status == .draft && !canSubmit {
            SectionNote(text: "Resta una bozza finché l'host non la invia.")
        }
        if status == .pending && canSubmit {
            Button { Task { await model.withdraw(id) } } label: { Text("Ritira invio").frame(maxWidth: .infinity) }
                .buttonStyle(.appOutlined)
                .disabled(model.busy)
        }
        if status == .approved {
            Toggle(isOn: Binding(
                get: { site.publishedOnSite == true },
                set: { visible in Task { await model.setVisible(id, visible) } }
            )) {
                Text("Visibile sul sito").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
            }
            .tint(Theme.primary)
            .disabled(model.busy)
        }

        // Decisione del super-admin
        if scope.isSuperAdmin && status == .pending {
            HStack(spacing: 8) {
                Button("Approva") { showApprove = true }.buttonStyle(.appPrimary).disabled(model.busy)
                Button("Rifiuta") {
                    reasons = ""
                    showReject = true
                }
                .buttonStyle(.appText(color: Theme.error))
                .disabled(model.busy)
            }
            if dirty {
                SectionNote(text: "Hai modifiche non salvate: l'host vedrà solo quelle salvate.")
            }
        }

        Color.clear.frame(height: 0)
            .sheet(isPresented: $showTerms) {
                HostTermsSheet(onAccept: {
                    showTerms = false
                    Task { await model.submit(id) }
                }, onDismiss: { showTerms = false })
            }
            .alert("Approvare l'annuncio?", isPresented: $showApprove) {
                Button("Approva") { Task { await model.approve(id) } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("\(item.property.name.trimmed.isEmpty ? "La casa" : item.property.name) andrà online sul sito e l'host riceverà una notifica.")
            }
            .alert("Rifiutare l'annuncio", isPresented: $showReject) {
                TextField("Motivi del rifiuto (li vedrà l'host)", text: $reasons, axis: .vertical)
                Button("Rifiuta", role: .destructive) {
                    let text = reasons.trimmed
                    guard !text.isEmpty else { return }
                    Task { await model.reject(id, reasons: text) }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Scrivi i motivi: sono obbligatori e li vedrà l'host.")
            }
    }

    private func statusText(_ status: ListingStatus) -> String {
        switch status {
        case .draft: return "Non è visibile sul sito."
        case .pending: return "In attesa di approvazione."
        case .approved: return site.publishedOnSite == true ? "Online sul sito." : "Approvato ma nascosto dal sito."
        case .rejected: return "Rifiutato: correggi e invia di nuovo."
        }
    }
}
