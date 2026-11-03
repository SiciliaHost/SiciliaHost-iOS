import SwiftUI

/// Scheda **Messaggi** (`MessagesScreen.kt`), solo per chi gestisce almeno una casa online sul sito (`MainTabs`). Elenco delle
/// conversazioni con gli ospiti e chat; in cima alla chat date, notti, ospiti e stato della prenotazione. «Recapiti» per
/// telefono e WhatsApp, che gli ospiti vedono solo a prenotazione confermata. Su iPhone la chat prende il posto dell'elenco.
struct MessagesView: View {
    let model: MessagesModel
    /// La scheda è quella in primo piano: solo allora si rilegge a intervalli.
    let isActive: Bool
    /// La chat è aperta: la barra flottante lascia posto alla tastiera.
    var onChatOpen: (Bool) -> Void = { _ in }

    @Environment(\.scenePhase) private var scenePhase
    @State private var showContacts = false

    var body: some View {
        VStack(spacing: 0) {
            if model.openId == nil {
                HStack {
                    Text("Messaggi").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showContacts = true } label: {
                        Label("Recapiti", systemImage: "phone.circle").appStyle(.labelLarge)
                    }
                    .buttonStyle(.appText)
                }
                .padding(.horizontal, Dimens.screenPadding)
                .padding(.vertical, 6)
            }
            if model.openId != nil {
                ChatPane(model: model)
            } else if model.isLoading && model.conversations.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.loadError {
                VStack(spacing: 12) {
                    Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error).multilineTextAlignment(.center)
                    Button("Riprova") { Task { await model.loadList() } }.buttonStyle(.appPrimary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ConversationList(model: model)
            }
        }
        // Rilettura solo con la scheda in primo piano e l'app attiva.
        .task(id: isActive && scenePhase == .active) {
            guard isActive, scenePhase == .active else { return }
            await model.loadList(silent: true)
            await model.runPolling()
        }
        .task { await model.loadContactsOnce() }
        .onChange(of: model.openId) { _, id in onChatOpen(id != nil) }
        .onDisappear { onChatOpen(false) }
        .sheet(isPresented: $showContacts, onDismiss: { model.contactsMessage = nil }) {
            ContactsSheet(model: model) { showContacts = false }
        }
    }
}

// MARK: Elenco

private struct ConversationList: View {
    let model: MessagesModel

    var body: some View {
        if model.conversations.isEmpty {
            Text("Nessun messaggio dagli ospiti per ora. Arrivano qui quando qualcuno scrive dalla pagina di una tua casa sul sito.")
                .appStyle(.bodyMedium)
                .foregroundStyle(Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Dimens.itemSpacing) {
                    ForEach(model.conversations) { c in
                        Button { Task { await model.open(c.id) } } label: { ConversationRow(conversation: c) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Dimens.screenPadding)
                .padding(.bottom, 8)
            }
            .refreshable { await model.loadList(silent: true) }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        let c = conversation
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if c.unread {
                    Circle().fill(Theme.error).frame(width: 9, height: 9).accessibilityLabel("Da leggere")
                }
                Text(c.guestName)
                    .appStyle(.titleSmall)
                    .fontWeight(c.unread ? .bold : .semibold)
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let last = c.lastMessage {
                    Text(MessagesFormat.listTime(last.at)).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            Text(c.propertyName).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
            if c.stay.checkIn != nil || c.stay.guests != nil {
                Text(MessagesFormat.stayLine(c.stay, long: false)).appStyle(.bodySmall).foregroundStyle(Theme.onSurface).lineLimit(2)
            }
            if let last = c.lastMessage {
                Text((last.from == "host" ? "Tu: " : "") + last.text)
                    .appStyle(.bodySmall)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Dimens.cardPadding)
        .appCard()
        .contentShape(Rectangle())
    }
}

// MARK: Chat

private struct ChatPane: View {
    let model: MessagesModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.close() } label: {
                    Label("Tutti i messaggi", systemImage: "chevron.left").appStyle(.labelLarge)
                }
                .buttonStyle(.appText)
                Spacer()
            }
            .padding(.horizontal, Dimens.screenPadding - 4)
            if let conversation = model.openConversation {
                StayHeader(conversation: conversation)
                    .padding(.horizontal, Dimens.screenPadding)
            }
            messageList
            if let error = model.sendError {
                Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Dimens.screenPadding)
            }
            composer
        }
        .onChange(of: model.openId) { _, _ in draft = "" }
    }

    @ViewBuilder
    private var messageList: some View {
        if model.chatLoading && model.messages.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.chatError {
            Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(MessagesFormat.groupByDay(model.messages), id: \.day) { group in
                            Text(MessagesFormat.dayLabel(group.messages[0].at))
                                .appStyle(.labelSmall)
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            ForEach(group.messages) { m in
                                Bubble(message: m, guestName: model.openConversation?.guestName ?? "Ospite").id(m.id)
                            }
                        }
                    }
                    .padding(.horizontal, Dimens.screenPadding)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.id) { _, last in
                    guard let last else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onAppear { if let last = model.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Scrivi una risposta…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .appStyle(.bodyLarge)
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(roundedShape(Radius.button).fill(Theme.surfaceContainerLowest.opacity(0.6)))
                .overlay(roundedShape(Radius.button).strokeBorder(Theme.outline, lineWidth: 1))
                .onChange(of: draft) { _, text in
                    if text.count > MessagesModel.maxText { draft = String(text.prefix(MessagesModel.maxText)) }
                }
            Button {
                Task { if await model.send(draft) { draft = "" } }
            } label: {
                Group {
                    if model.sending { ProgressView() } else { Image(systemName: "paperplane.fill") }
                }
                .frame(width: Dimens.controlHeight, height: Dimens.controlHeight)
            }
            .buttonStyle(.appIcon)
            .disabled(draft.trimmed.isEmpty || model.sending)
            .accessibilityLabel("Invia")
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 6)
    }
}

private struct StayHeader: View {
    let conversation: Conversation
    @Environment(\.openURL) private var openURL

    var body: some View {
        let c = conversation
        let status = c.booking?.status
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.guestName).appStyle(.titleMedium).foregroundStyle(Theme.onSurface).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(MessagesFormat.statusLabel(status).uppercased())
                    .appStyle(.labelSmall)
                    .foregroundStyle(pillColor(status))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(pillColor(status), lineWidth: 1))
            }
            Text(c.propertyName).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            Text(MessagesFormat.stayLine(c.stay)).appStyle(.bodyMedium).fontWeight(.semibold).foregroundStyle(Theme.onSurface)
            if let booking = c.booking, let total = booking.totalPrice {
                Text("Totale \(MessagesFormat.euro(total)) · caparra \(MessagesFormat.euro(booking.depositAmount ?? 0))")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
            }
            if let email = c.guestEmail, let url = URL(string: "mailto:\(email)") {
                Button(email) { openURL(url) }.buttonStyle(.appText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Dimens.cardPadding)
        .appCard()
    }

    private func pillColor(_ status: String?) -> Color {
        switch status {
        case "confirmed": return Theme.primary
        case "cancelled", "conflict": return Theme.error
        default: return Theme.secondary
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage
    let guestName: String

    var body: some View {
        let mine = message.from == "host"
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if let context = message.context, context.checkIn != nil, context.checkOut != nil {
                Text(MessagesFormat.stayLine(context, long: false))
                    .appStyle(.labelSmall)
                    .foregroundStyle(Theme.onSurface)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Theme.secondary, lineWidth: 1))
            }
            Text(message.text)
                .appStyle(.bodyMedium)
                .foregroundStyle(mine ? Theme.onPrimary : Theme.onSurface)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(roundedShape(14).fill(mine ? Theme.primary : Theme.surfaceContainerHigh))
                .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                .textSelection(.enabled)
            Text("\(mine ? "Tu" : guestName) · \(MessagesFormat.time(message.at))")
                .appStyle(.labelSmall)
                .foregroundStyle(Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

// MARK: Recapiti

private struct ContactsSheet: View {
    let model: MessagesModel
    let onClose: () -> Void

    @State private var phone = ""
    @State private var whatsapp = ""
    @State private var same = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recapiti per gli ospiti").appStyle(.titleLarge).foregroundStyle(Theme.onSurface)
            Text("Telefono e WhatsApp non sono pubblici: li vede solo chi ha una prenotazione confermata in una tua casa, nella chat e nella pagina ospite. Valgono per tutte le case di cui sei proprietario.")
                .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            AppTextField(label: "Telefono", text: $phone, supporting: "Con il prefisso se non è italiano (es. +44…)",
                         keyboard: .phonePad, capitalization: .never)
            AppTextField(label: "WhatsApp (se disponibile)", text: same ? .constant(phone) : $whatsapp,
                         keyboard: .phonePad, capitalization: .never)
                .disabled(same)
                .opacity(same ? 0.55 : 1)
            Toggle("Uguale al telefono", isOn: $same).appStyle(.bodyMedium).tint(Theme.primary)
            if let message = model.contactsMessage {
                Text(message).appStyle(.bodySmall).foregroundStyle(Theme.error)
            }
            HStack {
                Button("Annulla", action: onClose).buttonStyle(.appText)
                Spacer()
                Button(model.contactsSaving ? "Salvataggio…" : "Salva") {
                    Task { if await model.saveContacts(phone: phone, whatsapp: same ? phone : whatsapp) { onClose() } }
                }
                .buttonStyle(.appPrimary)
                .disabled(model.contactsSaving)
            }
            Spacer(minLength: 0)
        }
        .padding(Dimens.screenPadding + 4)
        .presentationDetents([.medium, .large])
        .onAppear {
            let current = model.contacts
            phone = current?.phone ?? ""
            whatsapp = current?.whatsapp ?? ""
            same = current?.phone != nil && current?.phone == current?.whatsapp
        }
    }
}
