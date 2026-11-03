import SwiftUI

/// Scorte (`InventoryScreen.kt`): ricerca e tre azioni in linea (scansiona, scansione multipla, aggiungi a mano), filtri
/// casa e categoria, elenco con −/+, dettaglio con foto. Prima di aggiungere si sceglie la casa (con più case).
struct InventoryView: View {
    let scope: AccessScope?
    @State private var model: InventoryModel

    @State private var search = ""
    @State private var category = InventoryLogic.allCategories
    @State private var filterPropertyId: String?
    @State private var sheet: InventorySheet?
    @State private var pickingFor: InventorySheet.Mode?
    @State private var photoPromptItemId: String?

    @MainActor
    init(scope: AccessScope?, model: InventoryModel? = nil) {
        self.scope = scope
        _model = State(initialValue: model ?? InventoryModel())
    }

    var body: some View {
        Group {
            if model.properties.isEmpty && !model.isLoading {
                Text("Aggiungi prima una struttura nella sezione Immobili per gestirne l'inventario.")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .task(id: scope) { await model.load(scope: scope) }
        .sheet(item: $sheet) { sheetContent($0) }
        .sheet(item: $pickingFor) { mode in
            PropertyPickerSheet(properties: model.properties, initial: filterPropertyId) { id in
                pickingFor = nil
                open(mode, propertyId: id)
            }
        }
        .alert("Fotografa il prodotto", isPresented: Binding(
            get: { photoPromptItemId != nil }, set: { if !$0 { photoPromptItemId = nil } }
        )) {
            Button("Scatta foto") {
                if let id = photoPromptItemId { sheet = .camera(itemId: id) }
                photoPromptItemId = nil
            }
            Button("Salta", role: .cancel) { photoPromptItemId = nil }
        } message: {
            Text("Vuoi fotografare gli ingredienti o i materiali di cui è composto questo articolo? Per i prodotti semplici, scatta pure una foto dell'intero articolo.")
        }
        .overlay(alignment: .bottom) {
            if let message = model.message {
                Text(message)
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurface)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(Capsule())
                    .padding(.bottom, 16)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        if model.message == message { model.message = nil }
                    }
            }
        }
    }

    private var content: some View {
        let filtered = InventoryLogic.filter(model.items, propertyId: filterPropertyId, category: category, search: search)
        return VStack(spacing: Dimens.itemSpacing) {
            HStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.onSurfaceVariant)
                    TextField("Cerca", text: $search)
                        .appStyle(.bodyMedium)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: Dimens.controlHeight + 8)
                .background(roundedShape(Radius.button).fill(Theme.surfaceContainerLowest.opacity(0.6)))
                .overlay(roundedShape(Radius.button).strokeBorder(Theme.outline, lineWidth: 1))
                action("barcode.viewfinder", "Scansiona un codice", emphasised: true) { request(.single) }
                    .tourTarget(.scorteScan)
                action("square.stack.3d.down.right", "Scansione multipla") { request(.batch) }
                action("plus", "Aggiungi manualmente") { request(.manual) }
            }
            HStack(spacing: Dimens.itemSpacing) {
                if model.properties.count > 1 {
                    SelectField(
                        label: "Casa",
                        options: [""] + model.properties.map(\.id),
                        selected: filterPropertyId ?? "",
                        optionLabel: { $0.isEmpty ? "Tutte le case" : model.propertyName($0) },
                        onSelect: { filterPropertyId = $0.isEmpty ? nil : $0 }
                    )
                }
                SelectField(label: "Categoria", options: InventoryLogic.filterCategories, selected: category,
                            optionLabel: { $0 }, onSelect: { category = $0 })
            }
            if model.isLoading && model.items.isEmpty {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(32)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: Dimens.itemSpacing) {
                        ForEach(filtered) { item in
                            InventoryRow(
                                item: item,
                                propertyName: model.propertyName(item.propertyId),
                                onOpen: { sheet = .detail(itemId: item.id) },
                                onMinus: { model.minus(item) },
                                onPlus: { model.plus(item) }
                            )
                        }
                    }
                }
                .refreshable { await model.load(scope: scope) }
            }
        }
        .padding(Dimens.screenPadding)
    }

    private func action(_ icon: String, _ label: String, emphasised: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon)
                .font(.system(size: Dimens.iconSmall, weight: .semibold))
                .foregroundStyle(emphasised ? Theme.onPrimary : Theme.onSurfaceVariant)
                .frame(width: Dimens.controlHeight, height: Dimens.controlHeight)
                .background(Circle().fill(emphasised ? Theme.primary : Color.clear))
        }
        .buttonStyle(.appIcon)
        .accessibilityLabel(label)
    }

    // MARK: Flussi

    private func request(_ mode: InventorySheet.Mode) {
        if model.properties.isEmpty {
            model.message = "Aggiungi prima una struttura in Immobili"
        } else if model.isLoading {
            model.message = "Inventario in caricamento, riprova tra un istante"
        } else if model.properties.count == 1 {
            open(mode, propertyId: model.properties[0].id)
        } else {
            pickingFor = mode
        }
    }

    private func open(_ mode: InventorySheet.Mode, propertyId: String) {
        switch mode {
        case .single: sheet = .scanner(propertyId: propertyId)
        case .batch:
            model.startBatch()
            sheet = .batch(propertyId: propertyId)
        case .manual: sheet = .addManual(propertyId: propertyId)
        }
    }

    /// Codice letto con la scansione singola: già presente → quante unità aggiungere; nuovo → nome cercato e modulo.
    private func handleSingle(_ raw: String, propertyId: String) {
        let code = normalizeBarcode(raw)
        if let existing = InventoryLogic.existing(barcode: code, propertyId: propertyId, in: model.items) {
            sheet = .addQuantity(itemId: existing.id)
            return
        }
        sheet = nil
        Task {
            let name = await model.lookupName(code)
            // Ricontrollo dopo la ricerca (rete): il prodotto può essere comparso nel frattempo.
            if let now = InventoryLogic.existing(barcode: code, propertyId: propertyId, in: model.items) {
                sheet = .addQuantity(itemId: now.id)
            } else {
                sheet = .addProduct(propertyId: propertyId, barcode: code, name: name ?? "")
            }
        }
    }

    private func created(_ saved: InventoryItem?) {
        sheet = nil
        if let saved { photoPromptItemId = saved.id }
    }

    @ViewBuilder
    private func sheetContent(_ s: InventorySheet) -> some View {
        switch s {
        case let .scanner(propertyId):
            BarcodeScannerSheet(title: "Scansiona codice a barre") { handleSingle($0, propertyId: propertyId) }
        case let .batch(propertyId):
            BatchScannerSheet(model: model, propertyId: propertyId, propertyName: model.propertyName(propertyId)) {
                sheet = model.batchItemIds.isEmpty ? nil : .batchSummary
            }
        case .batchSummary:
            BatchSummarySheet(model: model, onPhoto: { sheet = .camera(itemId: $0) }) { sheet = nil }
        case let .addProduct(propertyId, barcode, name):
            ProductFormSheet(title: "Nuovo prodotto rilevato!", barcodeCaption: barcode, initialName: name,
                             initialQuantity: "5", showsThreshold: false, editsBarcode: false) { values in
                Task {
                    created(await model.create(InventoryLogic.newItem(
                        propertyId: propertyId, name: values.name, barcode: barcode, category: values.category,
                        quantity: values.quantity)))
                }
            }
        case let .addManual(propertyId):
            ProductFormSheet(title: "Aggiungi prodotto manualmente", initialQuantity: "1", initialThreshold: "2") { values in
                Task {
                    created(await model.create(InventoryLogic.newItem(
                        propertyId: propertyId, name: values.name, barcode: values.barcode, category: values.category,
                        quantity: values.quantity, threshold: values.threshold)))
                }
            }
        case let .addQuantity(itemId):
            if let item = model.items.first(where: { $0.id == itemId }) {
                AddQuantitySheet(item: item) { count in
                    model.add(count, to: item)
                    sheet = nil
                }
            }
        case let .edit(itemId):
            if let item = model.items.first(where: { $0.id == itemId }) {
                ProductFormSheet(title: "Modifica prodotto", initialName: item.name, initialBarcode: item.barcode ?? "",
                                 initialCategory: item.category, initialQuantity: String(item.quantity),
                                 initialThreshold: String(item.lowStockThreshold), confirmLabel: "Salva") { values in
                    model.edit(InventoryLogic.edited(item, name: values.name, barcode: values.barcode, category: values.category,
                                                     quantity: values.quantity, threshold: values.threshold))
                    sheet = nil
                }
            }
        case let .detail(itemId):
            if let item = model.items.first(where: { $0.id == itemId }) {
                InventoryDetailSheet(
                    item: item,
                    propertyName: model.propertyName(item.propertyId),
                    onPlus: { model.plus(item) },
                    onMinus: { model.minus(item) },
                    onReportDepleted: { model.reportDepleted(item) },
                    onEdit: { sheet = .edit(itemId: item.id) },
                    onAddPhoto: { sheet = .camera(itemId: item.id) }
                )
            }
        case let .camera(itemId):
            CameraPicker { data in
                sheet = nil
                if let data { Task { await model.uploadPhoto(itemId: itemId, imageData: data) } }
            }
            .ignoresSafeArea()
        }
    }
}

/// I fogli delle Scorte: uno alla volta, come i dialog dell'Android.
enum InventorySheet: Identifiable, Hashable {
    enum Mode: String, Identifiable { case single, batch, manual; var id: String { rawValue } }

    case scanner(propertyId: String)
    case batch(propertyId: String)
    case batchSummary
    case addProduct(propertyId: String, barcode: String, name: String)
    case addManual(propertyId: String)
    case addQuantity(itemId: String)
    case edit(itemId: String)
    case detail(itemId: String)
    case camera(itemId: String)

    var id: Self { self }
}

/// Riga: barretta di stato, miniatura, nome, "casa · categoria", quantità colorata, −/+. Il tocco apre il dettaglio.
private struct InventoryRow: View {
    let item: InventoryItem
    let propertyName: String
    let onOpen: () -> Void
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        let accent = stockAccent(stockStatus(item))
        HStack(spacing: Dimens.cardPadding) {
            roundedShape(2).fill(accent).frame(width: 3, height: 32)
            ProductThumbnail(url: item.imageUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text("\(propertyName) · \(item.category)").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(item.quantity)").appStyle(.titleMedium).foregroundStyle(accent).frame(minWidth: 22)
                .accessibilityLabel("Quantità \(item.quantity), \(stockStatus(item).label.lowercased())")
            Button(action: onMinus) { Image(systemName: "minus") }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Togli uno")
            Button(action: onPlus) { Image(systemName: "plus") }
                .buttonStyle(AppIconButtonStyle(color: Theme.primary))
                .accessibilityLabel("Aggiungi uno")
        }
        .padding(Dimens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAction(named: "Apri dettaglio", onOpen)
    }
}

/// Colore di stato: verde = ok, giallo = da rifornire, rosso = esaurito.
func stockAccent(_ status: StockStatus) -> Color {
    switch status {
    case .depleted: return Theme.error
    case .low: return Theme.secondary
    case .ok: return Theme.primary
    }
}

struct ProductThumbnail: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceContainerHighest }
                }
            } else {
                Image(systemName: "camera")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surfaceContainerHighest)
            }
        }
        .frame(width: size, height: size)
        .clipShape(roundedShape(6))
        .accessibilityHidden(true)
    }
}
