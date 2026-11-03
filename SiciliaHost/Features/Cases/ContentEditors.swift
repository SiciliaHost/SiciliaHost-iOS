import SwiftUI

// Editor a schermo intero dei contenuti della pagina (`ServicesEditor.kt`, `PageContentEditor.kt`): si salvano a parte,
// ciascuno con il suo pulsante, tramite `upsertProperty`.

// MARK: Servizi

/// Servizi della casa: spunte per categoria dal catalogo, nota e "a pagamento" per ogni servizio, servizi personalizzati
/// e import da un elenco incollato. Salva con la patch `services`.
struct ServicesEditorView: View {
    let content: PropertySiteContent
    let siteModel: SiteContentModel
    let onSaved: () -> Void

    private let original: ServicesDraft
    @State private var draft: ServicesDraft
    @State private var query = ""
    @State private var editing: ServiceEntry?
    @State private var showCustom = false
    @State private var showImport = false

    init(content: PropertySiteContent, siteModel: SiteContentModel, onSaved: @escaping () -> Void) {
        self.content = content
        self.siteModel = siteModel
        self.onSaved = onSaved
        original = ServicesDraftLogic.fromServices(content)
        _draft = State(initialValue: ServicesDraftLogic.from(content))
    }

    var body: some View {
        let errors = ServicesDraftLogic.errors(draft)
        // Anche la conversione da `amenities` (originale vuoto, bozza piena) produce una patch.
        let patch = ServicesDraftLogic.patch(original: original, current: draft)
        let canSave = patch != nil && errors.isEmpty && !siteModel.isSaving
        let needle = normalizeForMatch(query)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                Text("\(draft.entries.filter { !$0.isOpaque }.count) servizi selezionati")
                    .appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                SectionNote(text: "Sono quelli che gli ospiti vedono sul sito, divisi per categoria.")
                FlowButtons {
                    Button("Incolla da Airbnb") { showImport = true }.buttonStyle(.appOutlined)
                    Button("Servizio personalizzato") { showCustom = true }.buttonStyle(.appOutlined)
                }
                AppTextField(label: "Cerca un servizio", text: $query, capitalization: .never)

                let custom = draft.entries.filter { $0.key == customServiceKey }
                if !custom.isEmpty {
                    categoryTitle("Personalizzati")
                    ForEach(custom, id: \.identity) { entry in
                        ServiceRow(label: entry.name, checked: true, detail: detail(entry), error: errors[entry.identity],
                                   onToggle: { draft = draft.remove(entry) }, onEdit: { editing = entry })
                    }
                }
                ForEach(ServiceCategory.allCases, id: \.self) { category in
                    let services = ServiceCatalog.all.filter {
                        $0.category == category && (needle.isEmpty || normalizeForMatch($0.label).contains(needle))
                    }
                    if !services.isEmpty {
                        categoryTitle(category.label)
                        ForEach(services, id: \.key) { service in
                            let entry = draft.entries.first { $0.key == service.key }
                            ServiceRow(
                                label: service.label, checked: entry != nil, detail: entry.map(detail) ?? "",
                                error: entry.flatMap { errors[$0.identity] },
                                onToggle: { draft = draft.toggle(service.key) },
                                onEdit: entry.map { e in { editing = e } }
                            )
                        }
                    }
                }
                if let total = errors["total"] { Text(total).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
                if let error = siteModel.saveError { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
                Button {
                    guard let patch else { return }
                    Task { if await siteModel.savePatch(content.id, ["services": patch]) { onSaved() } }
                } label: {
                    Text(siteModel.isSaving ? "Salvataggio…" : "Salva i servizi").frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .disabled(!canSave)
                .padding(.top, 8)
            }
            .padding(Dimens.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: content.id) { siteModel.saveError = nil }
        .sheet(item: Binding(get: { editing.map(EditingEntry.init) }, set: { editing = $0?.entry })) { wrapper in
            EditServiceSheet(
                entry: wrapper.entry,
                nameTaken: { draft.nameTaken($0, except: wrapper.entry) },
                onDismiss: { editing = nil },
                onConfirm: { updated in
                    draft = draft.replace(wrapper.entry, with: updated)
                    editing = nil
                },
                onDelete: wrapper.entry.key == customServiceKey ? {
                    draft = draft.remove(wrapper.entry)
                    editing = nil
                } : nil
            )
        }
        .sheet(isPresented: $showCustom) {
            CustomServiceSheet(onDismiss: { showCustom = false }, onConfirm: { name, category in
                draft = draft.withCustom(name, category: category)
                showCustom = false
            })
        }
        .sheet(isPresented: $showImport) {
            ServicesImportSheet(onDismiss: { showImport = false }, onConfirm: { result, accepted in
                draft = draft.mergeImport(result, acceptedCustom: accepted)
                showImport = false
            })
        }
    }

    private func detail(_ e: ServiceEntry) -> String {
        [e.paid ? "a pagamento" : nil, e.note.trimmed.isEmpty ? nil : e.note].compactMap { $0 }.joined(separator: " · ")
    }

    private func categoryTitle(_ text: String) -> some View {
        Text(text).appStyle(.titleSmall).foregroundStyle(Theme.primary).padding(.top, 10)
    }
}

/// `ServiceEntry` per `.sheet(item:)`: l'identità come id.
private struct EditingEntry: Identifiable {
    let entry: ServiceEntry
    var id: String { entry.identity }
}

private struct ServiceRow: View {
    let label: String
    let checked: Bool
    let detail: String
    let error: String?
    let onToggle: () -> Void
    let onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked ? Theme.primary : Theme.onSurfaceVariant)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface)
                            if !detail.isEmpty {
                                Text(detail).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checked ? .isSelected : [])
                if let onEdit { Button("Dettagli", action: onEdit).buttonStyle(.appText) }
            }
            if let error { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
        }
    }
}

private struct EditServiceSheet: View {
    let entry: ServiceEntry
    let nameTaken: (String) -> Bool
    let onDismiss: () -> Void
    let onConfirm: (ServiceEntry) -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var category: String
    @State private var paid: Bool
    @State private var note: String

    init(entry: ServiceEntry, nameTaken: @escaping (String) -> Bool, onDismiss: @escaping () -> Void,
         onConfirm: @escaping (ServiceEntry) -> Void, onDelete: (() -> Void)?) {
        self.entry = entry
        self.nameTaken = nameTaken
        self.onDismiss = onDismiss
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        _name = State(initialValue: entry.name)
        _category = State(initialValue: entry.category)
        _paid = State(initialValue: entry.paid)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        let isCustom = entry.key == customServiceKey
        let duplicate = isCustom && nameTaken(name)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(isCustom ? "Servizio personalizzato" : ServiceCatalog.label(for: entry.key))
                    .appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
                if isCustom {
                    SiteTextField(label: "Nome", text: $name, error: duplicate ? "Esiste già un servizio con questo nome" : nil)
                    FlowButtons {
                        ForEach(ServiceCategory.allCases, id: \.self) { c in
                            FilterChip(label: c.label, selected: category == c.key) { category = c.key }
                        }
                    }
                }
                SiteTextField(label: "Nota per gli ospiti (facoltativa)", text: $note, multiline: true)
                SectionNote(text: "La nota è pubblica: non scrivere indirizzo, codici o istruzioni di accesso.")
                SwitchRow(label: "A pagamento", isOn: $paid)
                if let onDelete {
                    Button("Elimina servizio", action: onDelete).buttonStyle(.appText(color: Theme.error))
                }
                HStack {
                    Spacer()
                    Button("Annulla", action: onDismiss).buttonStyle(.appText)
                    Button("OK") {
                        var updated = entry
                        updated.name = name.trimmed
                        updated.category = category
                        updated.paid = paid
                        updated.note = note.trimmed
                        onConfirm(updated)
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isCustom && (name.trimmed.isEmpty || duplicate))
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CustomServiceSheet: View {
    let onDismiss: () -> Void
    let onConfirm: (String, ServiceCategory) -> Void

    @State private var name = ""
    @State private var category = ServiceCategory.entertainment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Servizio personalizzato").appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
                SiteTextField(label: "Nome (es. Telescopio)", text: $name)
                Text("Categoria").appStyle(.labelMedium).foregroundStyle(Theme.onSurfaceVariant)
                FlowButtons {
                    ForEach(ServiceCategory.allCases, id: \.self) { c in
                        FilterChip(label: c.label, selected: category == c) { category = c }
                    }
                }
                SectionNote(text: "Il nome viene tradotto in automatico in inglese, francese e polacco.")
                HStack {
                    Spacer()
                    Button("Annulla", action: onDismiss).buttonStyle(.appText)
                    Button("Aggiungi") { onConfirm(name, category) }
                        .buttonStyle(.appPrimary)
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ServicesImportSheet: View {
    let onDismiss: () -> Void
    let onConfirm: (ServiceImportResult, Set<String>) -> Void

    @State private var pasted = ""
    @State private var result: ServiceImportResult?
    @State private var accepted: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Incolla da Airbnb").appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
                Text("Su Airbnb apri l'annuncio, tocca «Mostra tutti i servizi», copia l'elenco e incollalo qui.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                SiteTextField(label: "Elenco dei servizi", text: $pasted, multiline: true)
                    .onChange(of: pasted) { _, _ in result = nil }
                Button("Riconosci") {
                    let r = parsePastedServices(pasted)
                    result = r
                    accepted = Set(r.unmatched.map(\.name))
                }
                .buttonStyle(.appOutlined)
                .disabled(pasted.trimmed.isEmpty)
                if let r = result {
                    Text("Riconosciuti: \(r.matched.count)" + (r.unmatched.isEmpty ? "" : " · da confermare: \(r.unmatched.count)"))
                        .appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                    ForEach(r.unmatched, id: \.name) { custom in
                        Button {
                            if accepted.contains(custom.name) { accepted.remove(custom.name) } else { accepted.insert(custom.name) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: accepted.contains(custom.name) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(custom.name).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface)
                                    Text("Personalizzato · \(custom.category.label)")
                                        .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Spacer()
                    Button("Annulla", action: onDismiss).buttonStyle(.appText)
                    Button("Aggiungi") { if let result { onConfirm(result, accepted) } }
                        .buttonStyle(.appPrimary)
                        .disabled(result == nil)
                }
            }
            .padding(20)
        }
        .presentationDetents([.large])
    }
}

// MARK: Regole, accesso, dintorni e host

private let roomLabels = ["bedroom": "Camera da letto", "living_room": "Soggiorno", "other": "Altro spazio"]
private let bedLabels = [
    "double": "Letto matrimoniale", "single": "Letto singolo", "sofa_bed": "Divano letto",
    "queen": "Letto queen size", "king": "Letto king size", "bunk": "Letto a castello",
]
private let ruleOptions: [(String, String)] = [("allowed", "Sì"), ("not_allowed", "No"), ("on_request", "Su richiesta")]
private let yesNoOptions: [(String, String)] = [("yes", "Sì"), ("no", "No")]
private let parkingOptions: [(String, String)] = [
    ("none", "Non disponibile"), ("private", "Privato"), ("street", "In strada"), ("paid", "A pagamento"),
]
private let checkInOptions: [(String, String)] = [("in_person", "Di persona"), ("keybox", "Keybox"), ("smart_lock", "Serratura smart")]
private let nearbyOptions: [(String, String)] = [
    ("sea", "Mare"), ("center", "Centro"), ("supermarket", "Supermercato"), ("airport", "Aeroporto"),
    ("pharmacy", "Farmacia"), ("restaurant", "Ristorante"), ("bus_stop", "Fermata bus"),
]
private let languageOptions: [(String, String)] = [
    ("it", "Italiano"), ("en", "Inglese"), ("fr", "Francese"), ("pl", "Polacco"), ("de", "Tedesco"), ("es", "Spagnolo"),
]

/// Regole, accesso e arrivo, tassa di soggiorno, dintorni e host della pagina pubblica. Ogni campo è facoltativo: quello
/// che resta vuoto non compare sul sito.
struct PageContentEditorView: View {
    let content: PropertySiteContent
    let siteModel: SiteContentModel
    let onSaved: () -> Void

    private let original: PageContentDraft
    @State private var draft: PageContentDraft

    init(content: PropertySiteContent, siteModel: SiteContentModel, onSaved: @escaping () -> Void) {
        self.content = content
        self.siteModel = siteModel
        self.onSaved = onSaved
        let start = PageContentLogic.draft(from: content)
        original = start
        _draft = State(initialValue: start)
    }

    var body: some View {
        let errors = PageContentLogic.errors(draft)
        let patch = PageContentLogic.patch(original: original, current: draft)
        let canSave = !patch.isEmpty && errors.isEmpty && !siteModel.isSaving

        ScrollView {
            VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
                SectionNote(text: "I testi di questa pagina sono pubblici e vengono tradotti in automatico in inglese, francese e polacco. Non scrivere indirizzo esatto, codici o istruzioni di accesso.")
                roomsBlock(errors)
                rulesBlock(errors)
                accessBlock(errors)
                taxBlock(errors)
                nearbyBlock(errors)
                hostBlock(errors)
                if let error = siteModel.saveError { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
                Button {
                    Task { if await siteModel.savePatch(content.id, patch) { onSaved() } }
                } label: {
                    Text(siteModel.isSaving ? "Salvataggio…" : "Salva").frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .disabled(!canSave)
            }
            .padding(Dimens.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: content.id) { siteModel.saveError = nil }
    }

    private func title(_ text: String) -> some View {
        Text(text).appStyle(.titleMedium).foregroundStyle(Theme.primary).padding(.top, 8)
    }

    @ViewBuilder
    private func roomsBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Camere e letti")
            SectionNote(text: "Sul sito ogni camera da letto mostra il suo numero e i letti: matrimoniali, singoli, divano letto.")
            ForEach(Array(draft.rooms.enumerated()), id: \.offset) { i, room in
                let before = draft.rooms.prefix(i).filter { $0.kind == room.kind }.count
                let total = draft.rooms.filter { $0.kind == room.kind }.count
                let base = roomLabels[room.kind] ?? room.kind
                RoomEditor(
                    title: room.kind == "bedroom" || total > 1 ? "\(base) \(before + 1)" : base,
                    room: Binding(get: { draft.rooms.indices.contains(i) ? draft.rooms[i] : room },
                                  set: { if draft.rooms.indices.contains(i) { draft.rooms[i] = $0 } }),
                    error: errors["rooms.\(i)"],
                    onRemove: { if draft.rooms.indices.contains(i) { draft.rooms.remove(at: i) } }
                )
            }
            if let error = errors["rooms"] { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
            Button("Aggiungi stanza") { draft.rooms.append(RoomRow()) }.buttonStyle(.appOutlined)
            SwitchRow(label: "Culla per bambini piccoli (opzionale)", isOn: $draft.crib)
            SectionNote(text: "Sul sito la culla compare a parte, come extra su richiesta, non tra i letti della camera.")
        }
    }

    private func rulesBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Regole della casa")
            ChoiceRow(label: "Animali", options: ruleOptions, selected: $draft.pets)
            ChoiceRow(label: "Fumo", options: ruleOptions, selected: $draft.smoking)
            ChoiceRow(label: "Feste ed eventi", options: ruleOptions, selected: $draft.parties)
            ChoiceRow(label: "Bambini", options: ruleOptions, selected: $draft.children)
            FieldPair {
                SiteTextField(label: "Silenzio dalle (es. 22:00)", text: $draft.quietFrom, error: errors["quietHours"],
                              keyboard: .numbersAndPunctuation)
            } b: {
                SiteTextField(label: "fino alle (es. 08:00)", text: $draft.quietTo, keyboard: .numbersAndPunctuation)
            }
            SiteTextField(label: "Età minima", text: $draft.minAge, error: errors["minAge"], keyboard: .numberPad)
            SiteTextField(label: "Nota sulle regole", text: $draft.rulesNote, error: errors["rulesNote"], multiline: true)
        }
    }

    private func accessBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Accesso e arrivo")
            SiteTextField(label: "Piano (0 = piano terra)", text: $draft.floor, error: errors["floor"], keyboard: .numberPad)
            ChoiceRow(label: "Ascensore", options: yesNoOptions, selected: $draft.elevator)
            ChoiceRow(label: "Accesso senza gradini", options: yesNoOptions, selected: $draft.stepFree)
            ChoiceRow(label: "Parcheggio", options: parkingOptions, selected: $draft.parking)
            SiteTextField(label: "Nota sul parcheggio", text: $draft.parkingNote, error: errors["parkingNote"])
            ChoiceRow(label: "Check-in", options: checkInOptions, selected: $draft.checkInType)
            SiteTextField(label: "Nota sul check-in (senza codici)", text: $draft.checkInNote, error: errors["checkInNote"])
        }
    }

    private func taxBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Tassa di soggiorno")
            SectionNote(text: "Sul sito è solo un'informazione («da pagare in struttura»): non viene aggiunta al totale della prenotazione.")
            FieldPair {
                SiteTextField(label: "€ a persona e notte", text: $draft.taxAmount, error: errors["taxAmount"], keyboard: .decimalPad)
            } b: {
                SiteTextField(label: "Massimo notti", text: $draft.taxMaxNights, error: errors["taxMaxNights"], keyboard: .numberPad)
            }
            SiteTextField(label: "Esenti sotto i (anni)", text: $draft.taxExemptAge, error: errors["taxExemptAge"], keyboard: .numberPad)
        }
    }

    private func nearbyBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Dintorni")
            ForEach(Array(draft.nearby.enumerated()), id: \.offset) { i, row in
                NearbyEditor(
                    row: Binding(get: { draft.nearby.indices.contains(i) ? draft.nearby[i] : row },
                                 set: { if draft.nearby.indices.contains(i) { draft.nearby[i] = $0 } }),
                    error: errors["nearby.\(i)"],
                    onRemove: { if draft.nearby.indices.contains(i) { draft.nearby.remove(at: i) } }
                )
            }
            if let error = errors["nearby"] { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
            Button("Aggiungi luogo") { draft.nearby.append(NearbyRow()) }.buttonStyle(.appOutlined)
            SiteTextField(label: "Come muoversi (mezzi, navette)", text: $draft.transportNote, error: errors["transportNote"],
                          multiline: true)
        }
    }

    private func hostBlock(_ errors: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            title("Host")
            SiteTextField(label: "Nome", text: $draft.hostName, error: errors["hostName"], capitalization: .words)
            SiteTextField(label: "Email (riceve i messaggi dal sito)", text: $draft.hostEmail, error: errors["hostEmail"],
                          keyboard: .emailAddress, capitalization: .never)
            SiteTextField(label: "Telefono (es. +39 333 1234567)", text: $draft.hostPhone, error: errors["hostPhone"], keyboard: .phonePad)
            SwitchRow(label: "Il telefono ha WhatsApp", isOn: $draft.hostWhatsapp)
            Text("Lingue parlate").appStyle(.labelMedium).foregroundStyle(Theme.onSurfaceVariant)
            FlowButtons {
                ForEach(languageOptions, id: \.0) { code, label in
                    FilterChip(label: label, selected: draft.hostLanguages.contains(code)) {
                        if draft.hostLanguages.contains(code) { draft.hostLanguages.remove(code) } else { draft.hostLanguages.insert(code) }
                    }
                }
            }
            SectionNote(text: "Chi apre la pagina può sempre scriverti dal modulo del sito: il tuo indirizzo non viene mostrato. Attiva le due opzioni solo se vuoi che telefono o email siano visibili a tutti.")
            SwitchRow(label: "Mostra il telefono sul sito", isOn: $draft.showPhone)
            SwitchRow(label: "Mostra l'email sul sito", isOn: $draft.showEmail)
        }
    }
}

/// Scelta singola tra poche opzioni; toccare di nuovo l'opzione scelta la toglie ("non indicato").
private struct ChoiceRow: View {
    let label: String
    let options: [(String, String)]
    @Binding var selected: String
    var allowsClear = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).appStyle(.labelMedium).foregroundStyle(Theme.onSurfaceVariant)
            FlowButtons {
                ForEach(options, id: \.0) { value, text in
                    FilterChip(label: text, selected: selected == value) {
                        selected = selected == value && allowsClear ? "" : value
                    }
                }
            }
        }
    }
}

private struct NearbyEditor: View {
    @Binding var row: NearbyRow
    let error: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowButtons {
                ForEach(nearbyOptions, id: \.0) { value, text in
                    FilterChip(label: text, selected: row.type == value) { row.type = value }
                }
            }
            SiteTextField(label: "Nome (facoltativo)", text: $row.name)
            HStack(alignment: .top, spacing: 8) {
                SiteTextField(label: "Minuti", text: $row.minutes, error: error, keyboard: .numberPad).frame(maxWidth: 120)
                ChoiceRow(label: "Come", options: [("walk", "A piedi"), ("car", "In auto")], selected: $row.mode, allowsClear: false)
            }
            Button("Rimuovi luogo", action: onRemove).buttonStyle(.appText(color: Theme.error))
        }
        .padding(.vertical, 4)
    }
}

private struct RoomEditor: View {
    let title: String
    @Binding var room: RoomRow
    let error: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
            FlowButtons {
                ForEach(PageContentOptions.roomKinds, id: \.self) { kind in
                    FilterChip(label: roomLabels[kind] ?? kind, selected: room.kind == kind) { room.kind = kind }
                }
            }
            ForEach(PageContentOptions.bedTypes, id: \.self) { type in
                let count = room.beds[type] ?? 0
                HStack {
                    Text(bedLabels[type] ?? type).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("−") { set(type, count - 1) }.buttonStyle(.appOutlined).disabled(count <= 0)
                    Text("\(count)").appStyle(.titleMedium).foregroundStyle(Theme.onSurface).frame(minWidth: 28)
                    Button("+") { set(type, count + 1) }.buttonStyle(.appOutlined)
                        .disabled(count >= PageContentOptions.maxBedsPerType)
                }
            }
            if let error { Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
            Button("Rimuovi stanza", action: onRemove).buttonStyle(.appText(color: Theme.error))
        }
        .padding(.vertical, 4)
    }

    private func set(_ type: String, _ n: Int) {
        if n <= 0 { room.beds.removeValue(forKey: type) } else { room.beds[type] = n }
    }
}
