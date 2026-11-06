import SwiftUI

/// Avvisi in cima al check-in (`CheckinNotices` di `CredentialsDialog.kt`): credenziali mancanti o presenti (con
/// «Ricevuta» e «Modifica»), già inviato, esito incerto, schede vecchie mai inviate.
struct CheckinNotices: View {
    let model: CheckinModel

    @State private var editing = false
    @State private var confirmDelete = false
    @State private var pickingReceipt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.needsCredentials {
                notice("Per il check-in servono le credenziali Alloggiati Web su questo telefono.", action: "Inserisci") {
                    editing = true
                }
            } else {
                HStack(spacing: 4) {
                    Text("Credenziali Alloggiati su questo telefono")
                        .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Ricevuta") { pickingReceipt = true }.buttonStyle(.appText)
                    Button("Modifica") { editing = true }.buttonStyle(.appText)
                }
            }
            if let mark = model.alreadySent {
                notice("Check-in già inviato il \(Self.dateTime(mark.sentAt)) (\(mark.guests) ospiti), da questo o da un altro telefono.")
            }
            if model.hasUncertainOutcome {
                notice("L'ultimo invio ha un esito incerto: controlla la ricevuta sul portale Alloggiati prima di inviare di nuovo.")
            }
            if model.isStale {
                notice("Queste schede non sono mai state inviate e il soggiorno è finito da più di 30 giorni.",
                       action: "Elimina", enabled: !model.isSending) { confirmDelete = true }
            }
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 4)
        .confirmationDialog("Elimina schede", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { if !model.isSending { model.deleteAll() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Eliminare le schede mai inviate? Non si possono recuperare.")
        }
        .sheet(isPresented: $editing) {
            CredentialsSheet(model: model) { editing = false }
        }
        .sheet(isPresented: $pickingReceipt) {
            ReceiptDateSheet(model: model) { pickingReceipt = false }
        }
    }

    /// gg/MM/aaaa HH:mm nel fuso del telefono.
    static func dateTime(_ ms: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: dateFromMillis(ms))
    }

    private func notice(_ text: String, action: String? = nil, enabled: Bool = true,
                        onAction: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 4) {
            Text(text).appStyle(.bodySmall).foregroundStyle(Theme.onSecondaryContainer)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: onAction).buttonStyle(.appText).disabled(!enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(container: Theme.secondaryContainer)
    }
}

/// Credenziali Alloggiati di questo telefono: non vanno sul server. In memoria solo finché il foglio è aperto.
private struct CredentialsSheet: View {
    let model: CheckinModel
    let onClose: () -> Void

    @State private var utente = ""
    @State private var password = ""
    @State private var wsKey = ""
    @State private var loaded = false

    private var value: AlloggiatiCredentials {
        AlloggiatiCredentials(utente: utente.trimmed, password: password, wsKey: wsKey.trimmed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Credenziali Alloggiati Web").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
                Text("Restano solo su questo telefono, nel portachiavi. SiciliaHost non le riceve. "
                     + "Se cambi telefono andranno reinserite. Te le dà il proprietario della casa.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                AppTextField(label: "Utente", text: $utente, capitalization: .never)
                SecureCredentialField(label: "Password", text: $password)
                SecureCredentialField(label: "WsKey", text: $wsKey)
                if !model.needsCredentials {
                    Button("Togli da questo telefono") {
                        model.forgetCredentials()
                        onClose()
                    }
                    .buttonStyle(.appText(color: Theme.error))
                }
                HStack {
                    Spacer()
                    Button("Annulla", action: onClose).buttonStyle(.appText)
                    Button("Salva") {
                        let c = value
                        onClose()
                        Task { await model.saveCredentials(c) }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(!value.isConfigured)
                }
            }
            .padding(Dimens.screenPadding + 4)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Lette una volta all'apertura, non a ogni aggiornamento della vista.
            guard !loaded else { return }
            loaded = true
            let c = model.currentCredentials()
            utente = c.utente
            password = c.password
            wsKey = c.wsKey
        }
    }
}

/// Sceglie il giorno della ricevuta (ultimi 30 giorni escluso oggi, calendario e fuso di Roma) e la scarica (`ReceiptDialog.kt`).
/// Parte dal giorno dell'ultimo invio di questa prenotazione, se la ricevuta c'è già, altrimenti da ieri. Il PDF si apre
/// nello stesso foglio.
private struct ReceiptDateSheet: View {
    let model: CheckinModel
    let onClose: () -> Void

    private let today: CalendarDay
    @State private var selected: Date
    @State private var downloading = false
    @State private var pdfURL: URL?

    init(model: CheckinModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let today = ReceiptDates.romeToday(now: millisFromDate(Date()))
        self.today = today
        _selected = State(initialValue: ReceiptDates.defaultDate(today: today, lastSentAt: model.lastSentAt).romeMidnight)
    }

    private var selectedDay: CalendarDay? {
        let day = CalendarDay.rome(selected)
        return ReceiptDates.isSelectable(day, today: today) ? day : nil
    }

    var body: some View {
        if let pdfURL {
            ReceiptSheet(url: pdfURL)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Giorno della ricevuta").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
                Text("Il servizio dà le ricevute degli ultimi 30 giorni, oggi escluso.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                DatePicker("Giorno", selection: $selected, in: ReceiptDates.pickerRange(today: today), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.primary)
                    .environment(\.timeZone, RomeTime.zone)
                    .environment(\.calendar, RomeTime.calendar)
                    .environment(\.locale, Locale(identifier: "it_IT"))
                HStack {
                    Spacer()
                    Button("Annulla", action: onClose).buttonStyle(.appText)
                    Button {
                        download()
                    } label: {
                        HStack(spacing: 8) {
                            if downloading { ProgressView().tint(Theme.onPrimary) }
                            Text("Scarica")
                        }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(selectedDay == nil || downloading)
                }
            }
            .padding(Dimens.screenPadding + 4)
            .presentationDetents([.large])
        }
    }

    private func download() {
        guard let day = selectedDay, !downloading else { return }
        downloading = true
        Task {
            defer { downloading = false }
            guard let pdf = await model.downloadReceipt(dateIso: day.iso) else {
                onClose() // il motivo è nell'avviso rosso del check-in
                return
            }
            do {
                pdfURL = try ReceiptFiles.write(pdf)
            } catch {
                model.error = "Ricevuta non salvata sul telefono, riprova"
                onClose()
            }
        }
    }
}
