import AVFoundation
import SwiftUI
import UIKit
import VisionKit

// Fogli delle Scorte: scelta della casa, scanner (singolo e multiplo), moduli prodotto, quantità, dettaglio, fotocamera.

/// "A quale casa aggiungere?" (preselezionata sul filtro attivo).
struct PropertyPickerSheet: View {
    let properties: [Property]
    let initial: String?
    let onContinue: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
            Text("A quale casa aggiungere?").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            SelectField(label: "Casa", options: properties.map(\.id), selected: chosen,
                        optionLabel: { id in properties.first { $0.id == id }?.name ?? id }, onSelect: { chosen = $0 })
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
                Button("Continua") { if let chosen { onContinue(chosen) } }
                    .buttonStyle(.appPrimary)
                    .disabled(chosen == nil)
            }
        }
        .padding(Dimens.screenPadding * 2)
        .presentationDetents([.height(240)])
        .presentationBackground(Theme.surfaceContainerLow)
        .onAppear { chosen = initial ?? properties.first?.id }
    }
}

/// Fotocamera che legge codici a barre (VisionKit). Passa solo il primo codice di ogni lettura: un fotogramma può
/// contenerne due (codice principale + promozionale) e due classificazioni insieme aprirebbero due fogli.
struct BarcodeDataScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in added {
                if case let .barcode(code) = item, let value = code.payloadStringValue, !value.isEmpty {
                    onCode(value)
                    return
                }
            }
        }
    }
}

/// Lo scanner se disponibile, altrimenti il motivo (permesso negato, iPhone non supportato).
struct ScannerOrMessage<Overlay: View>: View {
    let onCode: (String) -> Void
    @ViewBuilder var overlay: () -> Overlay
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            if permission == .authorized && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ZStack { BarcodeDataScanner(onCode: onCode); overlay() }
            } else {
                VStack(spacing: 12) {
                    Text(permission == .authorized
                         ? "Questo iPhone non supporta la lettura dei codici con la fotocamera: aggiungi il prodotto a mano."
                         : "Permesso fotocamera necessario per scansionare i codici.")
                        .appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).multilineTextAlignment(.center)
                    if permission == .denied || permission == .restricted {
                        Button("Apri Impostazioni") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.appPrimary)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

/// Scansione singola: al primo codice letto il foglio passa al passo successivo.
struct BarcodeScannerSheet: View {
    let title: String
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var handled = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                Spacer()
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
            }
            ScannerOrMessage(onCode: { code in
                // Solo la prima lettura per apertura: altri fotogrammi possono arrivare prima della chiusura.
                guard !handled else { return }
                handled = true
                onCode(code)
            }, overlay: { EmptyView() })
            .frame(height: 300)
            .clipShape(roundedShape(12))
        }
        .padding(Dimens.screenPadding)
        .presentationDetents([.medium])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// Scansione multipla: la fotocamera resta aperta, ogni codice si salva subito con un avviso in alto e il contatore in basso.
struct BatchScannerSheet: View {
    let model: InventoryModel
    let propertyId: String
    let propertyName: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Scansione multipla · \(propertyName)") {
                Button("Termina", action: onFinish).buttonStyle(.appText)
            }
            ScannerOrMessage(onCode: { model.batchScanned($0, propertyId: propertyId) }) {
                VStack {
                    if let message = model.batchLastMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .appStyle(.bodyMedium)
                            .foregroundStyle(Theme.onPrimaryContainer)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .appCard(container: Theme.primaryContainer)
                            .padding(16)
                    }
                    Spacer()
                    Text("Scansionati: \(model.batchScanCount)")
                        .appStyle(.labelLarge)
                        .foregroundStyle(Theme.onSurface)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .appCard(container: Theme.surfaceContainerHigh)
                        .padding(16)
                }
            }
        }
        .interactiveDismissDisabled()
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// Riepilogo di fine scansione multipla: quantità salvate subito, nomi salvati con "Fine", foto mancanti.
struct BatchSummarySheet: View {
    let model: InventoryModel
    let onPhoto: (String) -> Void
    let onDone: () -> Void
    @State private var editedNames: [String: String] = [:]

    var body: some View {
        let items = model.items.filter { model.batchItemIds.contains($0.id) }
        VStack(spacing: 0) {
            CompactTopBar(title: "Riepilogo scansione (\(items.count))")
            ScrollView {
                VStack(spacing: Dimens.itemSpacing) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                if item.imageUrl != nil {
                                    ProductThumbnail(url: item.imageUrl, size: 48)
                                } else {
                                    Button { onPhoto(item.id) } label: { Image(systemName: "camera") }
                                        .buttonStyle(.appIcon)
                                        .accessibilityLabel("Aggiungi foto")
                                }
                                AppTextField(label: "Nome prodotto", text: Binding(
                                    get: { editedNames[item.id] ?? item.name }, set: { editedNames[item.id] = $0 }
                                ))
                            }
                            HStack(spacing: 8) {
                                Text("Quantità:").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                                Button { if item.quantity > 0 { model.save(InventoryLogic.settingQuantity(item.quantity - 1, of: item)) } }
                                    label: { Image(systemName: "minus") }
                                    .buttonStyle(.appIcon)
                                    .accessibilityLabel("Togli uno")
                                Text("\(item.quantity)").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                                Button { model.save(InventoryLogic.settingQuantity(item.quantity + 1, of: item)) }
                                    label: { Image(systemName: "plus") }
                                    .buttonStyle(.appIcon)
                                    .accessibilityLabel("Aggiungi uno")
                            }
                        }
                        .padding(12)
                        .appCard()
                    }
                }
                .padding(Dimens.screenPadding)
            }
            Button("Fine") {
                model.finishBatch(editedNames: editedNames)
                onDone()
            }
            .buttonStyle(.appPrimary)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .interactiveDismissDisabled()
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

struct ProductFormValues {
    var name: String
    var barcode: String
    var category: String
    var quantity: String
    var threshold: String
}

/// Modulo prodotto: nuovo da scansione (codice fisso, quantità iniziale), aggiunta manuale o modifica.
struct ProductFormSheet: View {
    let title: String
    var barcodeCaption: String?
    var showsThreshold = true
    var editsBarcode = true
    var confirmLabel = "Aggiungi"
    let onConfirm: (ProductFormValues) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: ProductFormValues

    init(
        title: String, barcodeCaption: String? = nil, initialName: String = "", initialBarcode: String = "",
        initialCategory: String = "Consumabili", initialQuantity: String = "1", initialThreshold: String = "2",
        showsThreshold: Bool = true, editsBarcode: Bool = true, confirmLabel: String = "Aggiungi",
        onConfirm: @escaping (ProductFormValues) -> Void
    ) {
        self.title = title
        self.barcodeCaption = barcodeCaption
        self.showsThreshold = showsThreshold
        self.editsBarcode = editsBarcode
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        _values = State(initialValue: ProductFormValues(name: initialName, barcode: initialBarcode, category: initialCategory,
                                                        quantity: initialQuantity, threshold: initialThreshold))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                if let barcodeCaption {
                    Text("Codice a barre: \(barcodeCaption)").appStyle(.titleSmall).foregroundStyle(Theme.onSurfaceVariant)
                }
                AppTextField(label: "Nome prodotto", text: $values.name)
                SelectField(label: "Categoria", options: InventoryLogic.categories, selected: values.category,
                            optionLabel: { $0 }, onSelect: { values.category = $0 })
                if editsBarcode {
                    AppTextField(label: confirmLabel == "Salva" ? "Codice a barre" : "Codice a barre (opzionale)",
                                 text: $values.barcode, capitalization: .never)
                }
                HStack(spacing: 8) {
                    AppTextField(label: showsThreshold ? "Quantità" : "Quantità iniziale", text: $values.quantity, keyboard: .numberPad)
                    if showsThreshold {
                        AppTextField(label: "Soglia minima", text: $values.threshold, keyboard: .numberPad)
                    }
                }
                HStack {
                    Spacer()
                    Button("Annulla") { dismiss() }.buttonStyle(.appText)
                    Button(confirmLabel) { onConfirm(values) }
                        .buttonStyle(.appPrimary)
                        // L'Android avvisava "Il nome è obbligatorio": qui il pulsante resta spento finché manca.
                        .disabled(values.name.trimmed.isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(Dimens.screenPadding * 2)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// Prodotto già registrato: quante unità aggiungere.
struct AddQuantitySheet: View {
    let item: InventoryItem
    let onAdd: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prodotto già registrato").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            Text("\"\(item.name)\" è già in inventario (scorte attuali: \(item.quantity)).")
                .appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
            AppTextField(label: "Quante unità aggiungi?", text: $text, keyboard: .numberPad)
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
                Button("Aggiungi") { onAdd(Int(text.trimmed) ?? 0) }.buttonStyle(.appPrimary)
            }
        }
        .padding(Dimens.screenPadding * 2)
        .presentationDetents([.height(280)])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// Dettaglio di un articolo (`InventoryItemDetailDialog.kt`): foto intera, stato, quantità con −/+, soglia, codice,
/// "Segnala esaurito", "Modifica", "Aggiungi foto" se manca.
struct InventoryDetailSheet: View {
    let item: InventoryItem
    let propertyName: String
    let onPlus: () -> Void
    let onMinus: () -> Void
    let onReportDepleted: () -> Void
    let onEdit: () -> Void
    let onAddPhoto: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let status = stockStatus(item)
        let accent = stockAccent(status)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let url = item.imageUrl.flatMap({ URL(string: $0) }) {
                    // Fit: è la foto di un'etichetta, va letta per intero.
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .background(Theme.surfaceContainerHighest)
                    .accessibilityLabel(item.name)
                } else {
                    Button(action: onAddPhoto) {
                        VStack(spacing: 4) {
                            Image(systemName: "camera").font(.system(size: Dimens.iconMedium))
                            Text("Aggiungi foto").appStyle(.labelLarge)
                        }
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(Theme.surfaceContainerHighest)
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                        Text("\(propertyName) · \(item.category)").appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                    }
                    Text(status.label)
                        .appStyle(.labelSmall).foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.16)))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QUANTITÀ").appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                            Text("Soglia minima: \(item.lowStockThreshold)").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: onMinus) { Image(systemName: "minus") }
                            .buttonStyle(.appIcon)
                            .disabled(item.quantity <= 0)
                            .accessibilityLabel("Togli uno")
                        Text("\(item.quantity)").appStyle(.titleLarge).foregroundStyle(accent).frame(minWidth: 32)
                        Button(action: onPlus) { Image(systemName: "plus") }
                            .buttonStyle(AppIconButtonStyle(color: Theme.primary))
                            .accessibilityLabel("Aggiungi uno")
                    }
                    if let code = item.barcode, !code.trimmed.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CODICE A BARRE").appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                            Text(code).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).textSelection(.enabled)
                        }
                    }
                    FlowLayout(spacing: 8) {
                        Button("Chiudi") { dismiss() }.buttonStyle(.appText)
                        Button("Segnala esaurito", action: onReportDepleted)
                            .buttonStyle(.appText(color: Theme.error))
                            .disabled(item.isDepleted)
                        Button("Modifica", action: onEdit).buttonStyle(.appPrimary)
                    }
                }
                .padding(16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surfaceContainerHigh)
    }
}

/// Fotocamera di sistema per la foto del prodotto. Restituisce i byte (poi compressi dal modello) o nil se annullata.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.95))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
