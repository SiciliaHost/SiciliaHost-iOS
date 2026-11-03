import PDFKit
import SwiftUI

/// Modulo ospite (`GuestFormScreen.kt`): tipo alloggiato, anagrafica, cittadinanza e nascita (comune e provincia solo per
/// gli italiani), documento e luogo di rilascio. I luoghi si cercano per nome (almeno 2 lettere). Precompilato dal MRZ se
/// il documento è stato scansionato; un avviso se le cifre di controllo non tornano.
struct GuestFormView: View {
    let model: CheckinModel
    let guestRecordId: String?
    let onDone: () -> Void

    @State private var values: GuestFormValues
    @State private var cittadinanzaText = ""
    @State private var statoNascitaText = ""
    @State private var comuneNascitaText = ""
    @State private var luogoRilascioText = ""
    private let mrz: MrzData?
    private let existing: GuestRecord?

    init(model: CheckinModel, guestRecordId: String?, onDone: @escaping () -> Void) {
        self.model = model
        self.guestRecordId = guestRecordId
        self.onDone = onDone
        let existing = guestRecordId.flatMap { id in model.guestRecords.first { $0.id == id } }
        self.existing = existing
        // I dati del MRZ valgono solo per un ospite nuovo.
        self.mrz = existing == nil ? model.pendingMrz : nil
        _values = State(initialValue: CheckinLogic.initialValues(existing: existing, mrz: existing == nil ? model.pendingMrz : nil))
    }

    private var isItalian: Bool { CheckinLogic.isItalian(cittadinanzaCode: values.cittadinanzaCode, luoghi: model.luoghi) }
    private var checkDigitsOk: Bool { mrz?.checkDigitsValid ?? true }

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: guestRecordId == nil ? "Nuovo ospite" : "Modifica ospite", onBack: onDone)
            if let error = model.error { ErrorBanner(text: error) { model.error = nil } }
            ScrollView {
                VStack(spacing: Dimens.itemSpacing) {
                    if mrz != nil && !checkDigitsOk {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.onErrorContainer)
                            Text("Alcuni campi dal MRZ non hanno superato la verifica. Controlla i campi evidenziati.")
                                .appStyle(.bodySmall).foregroundStyle(Theme.onErrorContainer)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard(container: Theme.errorContainer)
                    }

                    lookupMenu("Tipo alloggiato", entries: model.tipiAlloggiato, code: $values.tipoAlloggiato)

                    HStack(spacing: Dimens.itemSpacing) {
                        AppTextField(label: "Cognome", text: upper($values.cognome), error: mrzMark, capitalization: .characters)
                        AppTextField(label: "Nome", text: upper($values.nome), capitalization: .characters)
                    }

                    AppTextField(label: "Data di nascita (gg/mm/aaaa)",
                                 text: Binding(get: { values.dataNascita }, set: { values.dataNascita = CheckinLogic.sanitizeDate($0) }),
                                 keyboard: .numbersAndPunctuation)

                    HStack(spacing: 6) {
                        Text("Sesso").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                        FilterChip(label: "M", selected: values.sesso == "1") { values.sesso = "1" }
                        FilterChip(label: "F", selected: values.sesso == "2") { values.sesso = "2" }
                        Spacer()
                    }

                    LookupSearchField(label: "Cittadinanza", text: $cittadinanzaText, selectedCode: values.cittadinanzaCode,
                                      results: model.filterLuoghi(cittadinanzaText)) { values.cittadinanzaCode = $0.code }
                    LookupSearchField(label: "Stato di nascita", text: $statoNascitaText, selectedCode: values.statoNascitaCode,
                                      results: model.filterLuoghi(statoNascitaText)) { values.statoNascitaCode = $0.code }

                    if isItalian {
                        LookupSearchField(label: "Comune di nascita (solo italiani)", text: $comuneNascitaText,
                                          selectedCode: values.comuneNascitaCode,
                                          results: model.filterLuoghi(comuneNascitaText)) { values.comuneNascitaCode = $0.code }
                        AppTextField(label: "Provincia di nascita (sigla)",
                                     text: Binding(get: { values.provinciaNascita },
                                                   set: { values.provinciaNascita = CheckinLogic.sanitizeProvince($0) }),
                                     capitalization: .characters)
                    }

                    lookupMenu("Tipo documento", entries: model.tipiDocumento, code: $values.tipoDocumentoCode)
                    AppTextField(label: "Numero documento", text: upper($values.numeroDocumento), error: mrzMark,
                                 capitalization: .characters)
                    LookupSearchField(label: "Luogo di rilascio documento", text: $luogoRilascioText,
                                      selectedCode: values.luogoRilascioCode,
                                      results: model.filterLuoghi(luogoRilascioText)) { values.luogoRilascioCode = $0.code }

                    Button("Salva ospite", action: save)
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .disabled(!CheckinLogic.isValid(values, isItalian: isItalian) || model.isSaving)
                        .padding(.top, 8)
                }
                .padding(.horizontal, Dimens.screenPadding)
                .padding(.vertical, Dimens.itemSpacing)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: fillLookupTexts)
        .onChange(of: model.luoghi.count) { _, _ in fillLookupTexts() }
    }

    /// Campo letto dal MRZ con cifre di controllo sbagliate: bordo rosso (testo vuoto, l'avviso è in cima).
    private var mrzMark: String? { mrz != nil && !checkDigitsOk ? "Da controllare" : nil }

    private func upper(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0.uppercased() })
    }

    private func lookupMenu(_ label: String, entries: [LookupEntry], code: Binding<String>) -> some View {
        SelectField(
            label: label,
            options: entries.map(\.code),
            selected: code.wrappedValue.isEmpty ? nil : code.wrappedValue,
            optionLabel: { c in entries.first { $0.code == c }.map { "\($0.code) - \($0.description)" } ?? c },
            onSelect: { code.wrappedValue = $0 },
            placeholder: entries.isEmpty ? "Tabella non caricata" : "Scegli…"
        )
    }

    /// Nei campi di ricerca di una scheda esistente si mostra il nome del luogo già scelto.
    private func fillLookupTexts() {
        func name(_ code: String) -> String { model.luoghi.first { $0.code == code }?.description ?? "" }
        if cittadinanzaText.isEmpty { cittadinanzaText = name(values.cittadinanzaCode) }
        if statoNascitaText.isEmpty { statoNascitaText = name(values.statoNascitaCode) }
        if comuneNascitaText.isEmpty { comuneNascitaText = name(values.comuneNascitaCode) }
        if luogoRilascioText.isEmpty { luogoRilascioText = name(values.luogoRilascioCode) }
    }

    private func save() {
        let record = CheckinLogic.record(
            from: values, isItalian: isItalian, existing: existing,
            reservationId: model.reservationId, propertyId: model.propertyId
        )
        Task { if await model.save(record) { onDone() } }
    }
}

/// Ricerca di un luogo per nome: sotto il campo compaiono al massimo 30 risultati (da 2 lettere in su); toccarne uno
/// sceglie il codice. Il segno verde dice che un luogo è stato scelto.
private struct LookupSearchField: View {
    let label: String
    @Binding var text: String
    let selectedCode: String
    let results: [LookupEntry]
    let onSelect: (LookupEntry) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldFrame(label: label) {
                TextField("", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .appStyle(.bodyLarge)
                    .foregroundStyle(Theme.onSurface)
                    .focused($focused)
                    .accessibilityLabel(label)
            } trailing: {
                if !selectedCode.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary).accessibilityLabel("Scelto")
                }
            }
            if focused && !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results, id: \.code) { entry in
                        Button {
                            onSelect(entry)
                            text = entry.description
                            focused = false
                        } label: {
                            Text(entry.description)
                                .appStyle(.bodyMedium)
                                .foregroundStyle(Theme.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .appCard(container: Theme.surfaceContainerHigh)
            }
        }
    }
}

/// Visualizzatore PDF di sistema.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
