import SwiftUI

/// Check-in di una prenotazione (`CheckinScreen.kt`): elenco degli ospiti registrati, "Scansiona documento", modifica ed
/// eliminazione di una scheda, "Testa e invia schedine".
struct CheckinView: View {
    let model: CheckinModel
    let onScan: () -> Void
    let onEditGuest: (String) -> Void
    let onSend: () -> Void
    let onBack: () -> Void

    @State private var toDelete: GuestRecord?

    var body: some View {
        VStack(spacing: 0) {
            // Nome e date su una riga sola.
            CompactTopBar(title: CheckinLogic.headerTitle(model.reservation), onBack: onBack)
            if let error = model.error { ErrorBanner(text: error) { model.error = nil } }
            ZStack(alignment: .bottomTrailing) {
                content
                Button(action: onScan) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: Dimens.iconSmall, weight: .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(roundedShape(Radius.medium).fill(Theme.primary))
                        .softShadow(6, color: Theme.primary)
                }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Scansiona documento")
                .padding(Dimens.screenPadding)
            }
            if !model.guestRecords.isEmpty {
                Button("Testa e invia schedine (\(model.guestRecords.count))", action: onSend)
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(Dimens.screenPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Elimina ospite", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible, presenting: toDelete) { record in
            Button("Elimina", role: .destructive) { Task { await model.delete(record.id) } }
            Button("Annulla", role: .cancel) {}
        } message: { record in
            Text("Rimuovere \(record.cognome) \(record.nome)?")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.guestRecords.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "camera").font(.system(size: 54)).foregroundStyle(Theme.outlineVariant)
                Text("Nessun ospite aggiunto").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                Text("Usa il tasto fotocamera per scansionare un documento")
                    .appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant).multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.guestRecords) { record in
                        GuestRecordRow(record: record, onEdit: { onEditGuest(record.id) }, onDelete: { toDelete = record })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 56)
            }
            .refreshable { await model.load() }
        }
    }
}

private struct GuestRecordRow: View {
    let record: GuestRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.cognome) \(record.nome)").appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text("Doc: \(record.tipoDocumentoCode) \(record.numeroDocumento)")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                if record.schedInaSent {
                    Text("Inviata").appStyle(.labelSmall).foregroundStyle(Theme.primary)
                }
                if let error = record.sendError {
                    Text("Errore: \(error)").appStyle(.labelSmall).foregroundStyle(Theme.error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Modifica")
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(AppIconButtonStyle(color: Theme.error))
                .accessibilityLabel("Elimina")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

/// Riga d'errore rossa sotto l'intestazione, chiudibile (al posto della Snackbar dell'Android).
struct ErrorBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.onErrorContainer)
            Text(text).appStyle(.bodySmall).foregroundStyle(Theme.onErrorContainer)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(AppIconButtonStyle(color: Theme.onErrorContainer))
                .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.errorContainer)
    }
}

/// Invio delle schedine (`CheckinSendScreen.kt`): esito per ospite, "Testa correttezza", poi (solo con tutto corretto)
/// "Invia alla Polizia di Stato" con conferma; dopo l'invio "Scarica ricevuta PDF".
struct CheckinSendView: View {
    let model: CheckinModel
    let onBack: () -> Void

    @State private var testResult: ElencoSchedineEsito?
    @State private var sendDone = false
    @State private var showConfirm = false
    @State private var receiptURL: URL?

    var body: some View {
        let pending = model.pendingRecords
        VStack(spacing: 0) {
            CompactTopBar(title: "Invio schedine", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ospiti da inviare (\(pending.count))").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                        .padding(.bottom, 8)
                    ForEach(model.guestRecords) { record in
                        row(record, esito: CheckinLogic.esito(for: record, records: model.guestRecords, result: testResult))
                    }
                    Spacer().frame(height: 8)
                    if !sendDone {
                        Button {
                            Task { if let r = await model.submit(send: false) { testResult = r } }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isSending && testResult == nil { ProgressView().tint(Theme.onPrimary) }
                                Text("Testa correttezza")
                            }
                        }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isSending)
                        if CheckinLogic.allOk(testResult) {
                            Button { showConfirm = true } label: {
                                HStack(spacing: 8) {
                                    if model.isSending { ProgressView().tint(Theme.onPrimary) }
                                    Text("Invia alla Polizia di Stato")
                                }
                            }
                            .buttonStyle(.appPrimary)
                            .frame(maxWidth: .infinity)
                            .disabled(model.isSending)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                            Text("Schedine inviate con successo").appStyle(.bodyMedium).foregroundStyle(Theme.onPrimaryContainer)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard(container: Theme.primaryContainer)
                        Button {
                            Task { await openReceipt() }
                        } label: {
                            Label("Scarica ricevuta PDF", systemImage: "arrow.down")
                        }
                        .buttonStyle(.appOutlined)
                        .frame(maxWidth: .infinity)
                    }
                    if let error = model.error {
                        Text(error)
                            .appStyle(.bodyMedium)
                            .foregroundStyle(Theme.onErrorContainer)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(container: Theme.errorContainer)
                    }
                }
                .frame(maxWidth: 640)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Conferma invio", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Invia") {
                Task {
                    if let r = await model.submit(send: true) {
                        testResult = r
                        sendDone = r.dettaglio.contains(where: \.esito)
                    }
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Stai per inviare \(pending.count) schedine alla Polizia di Stato. L'operazione non è reversibile.")
        }
        .sheet(item: Binding(get: { receiptURL.map(IdentifiedURL.init) }, set: { receiptURL = $0?.url })) { item in
            ReceiptSheet(url: item.url)
        }
    }

    private func row(_ record: GuestRecord, esito: EsitoSingolo?) -> some View {
        let container: Color = {
            if record.schedInaSent { return Theme.surfaceContainerHigh }
            guard let esito else { return Theme.surfaceContainerLow }
            return esito.esito ? Theme.primaryContainer : Theme.errorContainer
        }()
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.cognome) \(record.nome)").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                if record.schedInaSent {
                    Text("Già inviata").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                } else if let esito, !esito.esito {
                    Text(esito.erroreDettaglio).appStyle(.bodySmall).foregroundStyle(Theme.error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if record.schedInaSent {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
            } else if let esito {
                Image(systemName: esito.esito ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(esito.esito ? Theme.primary : Theme.error)
                    .accessibilityLabel(esito.esito ? "Corretta" : "Errore")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(container: container)
    }

    private func openReceipt() async {
        guard let pdf = await model.downloadReceipt() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ricevuta_\(millisFromDate(Date())).pdf")
        do {
            try pdf.write(to: url)
            receiptURL = url
        } catch {
            model.error = "Non riesco a salvare la ricevuta sul telefono."
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Anteprima della ricevuta PDF con condivisione (salva in File, stampa, invia).
private struct ReceiptSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Chiudi") { dismiss() }.buttonStyle(.appText)
                Spacer()
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Condividi ricevuta")
                    .padding(.horizontal, 12)
            }
            PDFKitView(url: url)
        }
    }
}
