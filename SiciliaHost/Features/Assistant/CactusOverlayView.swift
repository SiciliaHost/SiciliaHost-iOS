import SwiftUI

let cactusCyan = Color(red: 0.0, green: 0.87, blue: 1.0) // #00DEFF

struct CactusOverlayView: View {
    @Bindable var model: AssistantModel
    @Bindable var controller: AssistantController = .shared
    @State private var voice = AssistantVoice()

    @State private var inputText: String = ""
    @State private var showFullHistory: Bool = false
    @State private var isTypingAnimation: Bool = false
    @State private var typingElapsedMs: Int64 = 0
    @State private var timerTask: Task<Void, Never>? = nil

    init(model: AssistantModel, controller: AssistantController = .shared) {
        self.model = model
        self.controller = controller
    }

    var body: some View {
        ZStack {
            // Velo di sfondo oscurato al 38% che assorbe i tocchi
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // Assorbe i tocchi senza chiudere
                }

            // Cornice neon ciano
            RoundedRectangle(cornerRadius: 24)
                .stroke(cactusCyan.opacity(0.55), lineWidth: 2)
                .shadow(color: cactusCyan.opacity(0.35), radius: 10)
                .padding(8)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Barra superiore: Nome assistente e tasto chiusura
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(cactusCyan)
                        Text(AssistantTexts.overlayTitle)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35)) {
                            controller.open = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Avatar di Cactus in alto al centro
                let currentState = avatarStateOf(
                    busy: model.busy,
                    speaking: voice.speaking,
                    typing: isTypingAnimation,
                    listening: voice.listening,
                    errorFlash: model.error != nil
                )
                CactusAvatarView(state: currentState)
                    .frame(height: 110)
                    .padding(.vertical, 4)

                // Area conversazione o storico esteso
                if showFullHistory {
                    fullHistoryView
                        .frame(maxHeight: 260)
                        .padding(.horizontal, 16)
                } else {
                    bubblesView
                        .frame(maxHeight: 260)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 6)

                // Carte dei Widget, Proposte o Consenso (che salgono dal basso)
                activeCardsView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                // Comandi intermedi: Casa, Voce, Conversazione, Nuova chat
                toolbarCommands
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Barra di input testo e microfono
                inputBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            voice.stopSpeaking()
            startTypewriterAnimationIfNeeded()
        }
        .onDisappear {
            timerTask?.cancel()
            voice.stopSpeaking()
            voice.stopListening()
        }
        .onChange(of: model.messages.count) { _, _ in
            startTypewriterAnimationIfNeeded()
        }
    }

    // MARK: - Nuvolette (Vista Compatta)

    private var bubblesView: some View {
        VStack(spacing: 8) {
            let slots = bubbleSlots(messages: model.messages)

            ForEach(slots) { slot in
                switch slot.kind {
                case .previous:
                    HStack {
                        Text(slot.message.text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
                        Spacer()
                    }

                case .ask:
                    HStack {
                        Spacer()
                        Text(AssistantTexts.bubbleAskPrefix + slot.message.text)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceContainerHighest.opacity(0.85)))
                    }

                case .current:
                    HStack {
                        let text = displayedTextForCurrent(slot.message)
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Theme.surfaceContainerHigh.opacity(0.95))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(cactusCyan.opacity(0.5), lineWidth: 1))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Tocco per mostrare subito tutto il testo
                                isTypingAnimation = false
                                model.lastTypedMessageId = slot.message.id
                            }
                        Spacer()
                    }
                }
            }

            // Bolla di attesa quando l'assistente sta pensando
            if model.busy {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(cactusCyan).frame(width: 6, height: 6)
                        Circle().fill(cactusCyan).frame(width: 6, height: 6)
                        Circle().fill(cactusCyan).frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.15)))
                    Spacer()
                }
            }
        }
    }

    private func displayedTextForCurrent(_ msg: AssistantChatMessage) -> String {
        if isTypingAnimation && model.lastTypedMessageId != msg.id {
            let n = typedChars(elapsedMs: typingElapsedMs, length: msg.text.count)
            return typedPrefix(text: msg.text, n: n)
        }
        return msg.text
    }

    private func startTypewriterAnimationIfNeeded() {
        guard let last = model.messages.last(where: { $0.role == .assistant }),
              model.lastTypedMessageId != last.id,
              !last.text.isEmpty else {
            isTypingAnimation = false
            return
        }

        timerTask?.cancel()
        typingElapsedMs = 0
        isTypingAnimation = true
        let totalDuration = typewriterDurationMs(length: last.text.count)

        timerTask = Task {
            while typingElapsedMs < totalDuration && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000)
                typingElapsedMs += 25
            }
            await MainActor.run {
                self.isTypingAnimation = false
                self.model.lastTypedMessageId = last.id
            }
        }
    }

    // MARK: - Storico Completo Conversazione

    private var fullHistoryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.messages) { msg in
                    if msg.role == .note {
                        Text(msg.text)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if msg.role == .user {
                        HStack {
                            Spacer()
                            Text(msg.text)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.primary.opacity(0.85)))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(msg.text)
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))

                            if !msg.widgets.isEmpty {
                                ForEach(msg.widgets) { w in
                                    WidgetView(
                                        widget: w,
                                        active: model.activeWidgetMessageId == msg.id,
                                        answer: msg.answers[w.id],
                                        onAnswer: { reply, sel in
                                            model.answerWidget(messageId: msg.id, widgetId: w.id, text: reply, selection: sel)
                                        }
                                    )
                                }
                            }

                            if !msg.proposals.isEmpty {
                                ProposalGroupView(
                                    proposals: msg.proposals,
                                    onConfirmMany: { model.confirmMany(messageId: msg.id) },
                                    onDeclineMany: { model.declineMany(messageId: msg.id) },
                                    onConfirmSingle: { model.confirm(proposalId: $0) },
                                    onUndoSingle: { model.undo(proposalId: $0) },
                                    onDeclineSingle: { model.decline(proposalId: $0) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Carte Attive (Consenso, Widget o Proposte in corso)

    @ViewBuilder
    private var activeCardsView: some View {
        if let consent = model.consent {
            ConsentView(
                state: consent,
                onAccept: { model.acceptConsent() },
                onDecline: { model.declineConsent() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let cardMsgId = cardsMessageId(messages: model.messages),
                  let msg = model.messages.first(where: { $0.id == cardMsgId }) {
            VStack(spacing: 8) {
                // Widget del messaggio
                ForEach(msg.widgets) { w in
                    WidgetView(
                        widget: w,
                        active: model.activeWidgetMessageId == msg.id,
                        answer: msg.answers[w.id],
                        onAnswer: { reply, sel in
                            model.answerWidget(messageId: msg.id, widgetId: w.id, text: reply, selection: sel)
                        }
                    )
                }

                // Proposte del messaggio
                if !msg.proposals.isEmpty {
                    ProposalGroupView(
                        proposals: msg.proposals,
                        onConfirmMany: { model.confirmMany(messageId: msg.id) },
                        onDeclineMany: { model.declineMany(messageId: msg.id) },
                        onConfirmSingle: { model.confirm(proposalId: $0) },
                        onUndoSingle: { model.undo(proposalId: $0) },
                        onDeclineSingle: { model.decline(proposalId: $0) }
                    )
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Barra Comandi Intermedi

    private var toolbarCommands: some View {
        HStack(spacing: 12) {
            // Menu Selettore Casa
            Menu {
                Button(AssistantTexts.houseNone) {
                    model.setProperty(nil)
                }
                ForEach(model.houses) { h in
                    Button(h.name) {
                        model.setProperty(h.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "house")
                    Text(model.propertyId != nil
                         ? (model.houses.first(where: { $0.id == model.propertyId })?.name ?? AssistantTexts.houseNone)
                         : AssistantTexts.houseNone)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }

            Spacer()

            // Storico / Nuova chat
            Button {
                withAnimation { showFullHistory.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showFullHistory ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    Text(showFullHistory ? AssistantTexts.hideConversation : AssistantTexts.showConversation)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            Button {
                model.newChat()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Barra di Input Testo e Microfono

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(AssistantTexts.inputLabel, text: $inputText)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .foregroundStyle(.white)

            // Pulsante Microfono
            Button {
                if voice.listening {
                    voice.stopListening()
                } else {
                    voice.listen { recognized in
                        inputText = recognized
                        model.send(text: recognized)
                        inputText = ""
                    }
                }
            } label: {
                Image(systemName: voice.listening ? "waveform.circle.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(voice.listening ? cactusCyan : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .scaleEffect(voice.listening ? 1.15 : 1.0)
                    .animation(voice.listening ? .easeInOut(duration: 0.6).repeatForever() : .default, value: voice.listening)
            }
            .buttonStyle(.plain)

            // Pulsante Invia
            Button {
                let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                model.send(text: trimmed)
                inputText = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.primary))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
        }
    }
}

// MARK: - Componente Avatar Cactus

public struct CactusAvatarView: View {
    public let state: CactusState

    @State private var blink = false
    @State private var thinkingPhase = 0

    public var body: some View {
        ZStack {
            // Cerchio d'alone intorno all'avatar
            Circle()
                .fill(cactusCyan.opacity(state == .working || state == .listening ? 0.35 : 0.15))
                .frame(width: 90, height: 90)
                .blur(radius: 12)

            // Sagoma/Avatar Cactus vettoriale elegante
            VStack(spacing: 2) {
                // I 3 Frutti sul capo (fico d'India) che rimbalzano in sequenza durante Thinking
                HStack(spacing: 8) {
                    FruitDot(active: thinkingPhase == 0 || state == .working, isRed: state == .error || state == .working)
                    FruitDot(active: thinkingPhase == 1 || state == .working, isRed: state == .error || state == .working)
                    FruitDot(active: thinkingPhase == 2 || state == .working, isRed: state == .error || state == .working)
                }

                // Testa e Visiera Neon
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "#1E3A2F")) // Verde pala scuro
                        .frame(width: 64, height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cactusCyan, lineWidth: 1.5))

                    // Occhi / Visiera espressiva
                    HStack(spacing: 12) {
                        EyeBar(state: state, blink: blink)
                        EyeBar(state: state, blink: blink)
                    }
                }
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                blink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { blink = false }
            }
            Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
                thinkingPhase = (thinkingPhase + 1) % 3
            }
        }
    }
}

private struct FruitDot: View {
    let active: Bool
    let isRed: Bool

    var body: some View {
        Circle()
            .fill(isRed ? Theme.error : (active ? cactusCyan : Theme.primary))
            .frame(width: 10, height: 10)
            .offset(y: active ? -3 : 0)
            .shadow(color: active ? (isRed ? Theme.error : cactusCyan) : .clear, radius: 4)
            .animation(.spring(response: 0.3), value: active)
    }
}

private struct EyeBar: View {
    let state: CactusState
    let blink: Bool

    var body: some View {
        Capsule()
            .fill(state == .error ? Theme.error : cactusCyan)
            .frame(width: 8, height: blink ? 2 : (state == .listening ? 14 : 10))
            .animation(.spring(response: 0.2), value: blink)
    }
}
