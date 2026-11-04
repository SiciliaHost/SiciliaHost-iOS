import SwiftUI

// MARK: - Contenitore Comune per i Widget

public struct WidgetCard<Content: View>: View {
    @ViewBuilder public let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surfaceContainerHigh.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outlineVariant.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - Dispatcher dei Widget

public struct WidgetView: View {
    public let widget: AnyWidget
    public let active: Bool
    public let answer: String?
    public let onAnswer: (String, [String]?) -> Void

    public init(widget: AnyWidget, active: Bool, answer: String?, onAnswer: @escaping (String, [String]?) -> Void) {
        self.widget = widget
        self.active = active
        self.answer = answer
        self.onAnswer = onAnswer
    }

    public var body: some View {
        switch widget {
        case .choice(let w):
            ChoiceWidgetView(widget: w, active: active, answer: answer, onAnswer: onAnswer)
        case .dates(let w):
            DatesWidgetView(widget: w, active: active, answer: answer, onAnswer: onAnswer)
        case .quickReplies(let w):
            QuickRepliesWidgetView(widget: w, active: active, onAnswer: onAnswer)
        case .summary(let w):
            SummaryWidgetView(widget: w)
        case .amount(let w):
            AmountWidgetView(widget: w, active: active, answer: answer, onAnswer: onAnswer)
        }
    }
}

// MARK: - 1. Widget Scelta (Choice)

public struct ChoiceWidgetView: View {
    public let widget: ChoiceWidget
    public let active: Bool
    public let answer: String?
    public let onAnswer: (String, [String]?) -> Void

    @State private var selectedIds: Set<String> = []

    public var body: some View {
        WidgetCard {
            Text(widget.prompt)
                .font(.headline)
                .foregroundStyle(Theme.onSurface)

            if !active || answer != nil {
                // Sola lettura
                Text(answer ?? AssistantTexts.widgetNotChosen)
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(widget.options) { opt in
                        Button {
                            if widget.multiple {
                                if selectedIds.contains(opt.id) {
                                    selectedIds.remove(opt.id)
                                } else {
                                    selectedIds.insert(opt.id)
                                }
                            } else {
                                selectedIds = [opt.id]
                                confirmChoice()
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: selectedIds.contains(opt.id)
                                      ? (widget.multiple ? "checkmark.square.fill" : "circle.inset.filled")
                                      : (widget.multiple ? "square" : "circle"))
                                    .foregroundStyle(selectedIds.contains(opt.id) ? Theme.primary : Theme.onSurfaceVariant)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label)
                                        .font(.body)
                                        .foregroundStyle(Theme.onSurface)
                                    if let detail = opt.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.onSurfaceVariant)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIds.contains(opt.id) ? Theme.primary.opacity(0.12) : Color.clear)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if widget.multiple && !selectedIds.isEmpty {
                    Button(AssistantTexts.widgetConfirm) {
                        confirmChoice()
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .padding(.top, 6)
                }
            }
        }
    }

    private func confirmChoice() {
        let chosenOptions = widget.options.filter { selectedIds.contains($0.id) }
        let labels = chosenOptions.map(\.label)
        let reply = replyChoice(labels: labels, language: "it")
        let ids = chosenOptions.map(\.id)
        onAnswer(reply, ids)
    }
}

// MARK: - 2. Widget Date (Dates)

public struct DatesWidgetView: View {
    public let widget: DatesWidget
    public let active: Bool
    public let answer: String?
    public let onAnswer: (String, [String]?) -> Void

    @State private var showSheet = false
    @State private var selectedStart: Date = Date()
    @State private var selectedEnd: Date = Date()
    @State private var errorMessage: String? = nil

    private let isoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    public var body: some View {
        WidgetCard {
            Text(widget.prompt)
                .font(.headline)
                .foregroundStyle(Theme.onSurface)

            if !active || answer != nil {
                Text(answer ?? AssistantTexts.widgetNotChosen)
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceVariant)
            } else {
                Button {
                    showSheet = true
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text(AssistantTexts.datesChoose)
                    }
                }
                .buttonStyle(AppOutlinedButtonStyle())
                .sheet(isPresented: $showSheet) {
                    NavigationStack {
                        VStack(spacing: 16) {
                            if widget.mode == .range {
                                DatePicker("Dal", selection: $selectedStart, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                DatePicker("Al", selection: $selectedEnd, in: selectedStart..., displayedComponents: .date)
                            } else {
                                DatePicker("Data", selection: $selectedStart, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                            }

                            if let err = errorMessage {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(Theme.error)
                            }
                            Spacer()
                        }
                        .padding()
                        .navigationTitle(widget.prompt)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(AssistantTexts.datesCancel) { showSheet = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(AssistantTexts.datesConfirm) {
                                    confirmDates()
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func confirmDates() {
        let fromIso = isoFormatter.string(from: selectedStart)
        if widget.mode == .range {
            let toIso = isoFormatter.string(from: selectedEnd)
            if !rangeIsValid(start: fromIso, end: toIso, w: widget) {
                errorMessage = AssistantTexts.datesInvalidRange
                return
            }
            showSheet = false
            let reply = replyDates(from: fromIso, to: toIso, language: "it")
            onAnswer(reply, nil)
        } else {
            if isDayDisabled(day: fromIso, w: widget) {
                errorMessage = AssistantTexts.datesInvalidRange
                return
            }
            showSheet = false
            let reply = replyDates(from: fromIso, to: nil, language: "it")
            onAnswer(reply, nil)
        }
    }
}

// MARK: - 3. Widget Risposte Rapide (Quick Replies)

public struct QuickRepliesWidgetView: View {
    public let widget: QuickRepliesWidget
    public let active: Bool
    public let onAnswer: (String, [String]?) -> Void

    public var body: some View {
        if active {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(widget.options, id: \.label) { opt in
                        Button {
                            onAnswer(opt.text, nil)
                        } label: {
                            Text(opt.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(Theme.surfaceContainerHighest.opacity(0.8))
                                        .overlay(Capsule().stroke(Theme.primary.opacity(0.3), lineWidth: 1))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 4. Widget Riepilogo (Summary)

public struct SummaryWidgetView: View {
    public let widget: SummaryWidget

    public var body: some View {
        WidgetCard {
            Text(widget.title)
                .font(.headline)
                .foregroundStyle(Theme.onSurface)

            VStack(spacing: 6) {
                ForEach(widget.rows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .font(row.emphasis ? .body.bold() : .body)
                            .foregroundStyle(Theme.onSurfaceVariant)
                        Spacer()
                        Text(row.value)
                            .font(row.emphasis ? .body.bold() : .body)
                            .foregroundStyle(row.emphasis ? Theme.primary : Theme.onSurface)
                    }
                }
            }

            if let note = widget.note {
                Text(note)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - 5. Widget Importo (Amount)

public struct AmountWidgetView: View {
    public let widget: AmountWidget
    public let active: Bool
    public let answer: String?
    public let onAnswer: (String, [String]?) -> Void

    @State private var rawText: String = ""
    @State private var currentVal: Double = 0.0
    @State private var errorText: String? = nil

    public var body: some View {
        WidgetCard {
            Text(widget.prompt)
                .font(.headline)
                .foregroundStyle(Theme.onSurface)

            if !active || answer != nil {
                Text(answer ?? AssistantTexts.widgetNotChosen)
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceVariant)
            } else {
                HStack(spacing: 12) {
                    Button {
                        stepAmount(delta: -1.0)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surfaceContainerHighest))
                    }
                    .buttonStyle(.plain)

                    TextField("0", text: $rawText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title3.bold())
                        .frame(minWidth: 80, minHeight: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.outlineVariant, lineWidth: 1)
                        }
                        .onChange(of: rawText) { _, newText in
                            let norm = newText.replacingOccurrences(of: ",", with: ".")
                            if let v = Double(norm) { currentVal = v }
                        }

                    Button {
                        stepAmount(delta: 1.0)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surfaceContainerHighest))
                    }
                    .buttonStyle(.plain)
                }

                if !widget.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(widget.suggestions, id: \.self) { s in
                                Button {
                                    currentVal = s
                                    rawText = formatAmountNumber(s, language: "it", fixed: widget.kind == .euro)
                                } label: {
                                    Text(formatAmountNumber(s, language: "it", fixed: widget.kind == .euro) + (widget.kind == .euro ? " €" : ""))
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Theme.surfaceContainerHighest))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let err = errorText {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }

                Button(AssistantTexts.widgetConfirm) {
                    validateAndSubmit()
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .onAppear {
            let startVal = widget.defaultValue ?? widget.min ?? 0.0
            currentVal = startVal
            rawText = formatAmountNumber(startVal, language: "it", fixed: widget.kind == .euro)
        }
    }

    private func stepAmount(delta: Double) {
        let next = max(widget.min ?? 0.0, currentVal + delta)
        currentVal = next
        rawText = formatAmountNumber(next, language: "it", fixed: widget.kind == .euro)
    }

    private func validateAndSubmit() {
        switch parseAndValidateAmount(rawText, w: widget) {
        case .success(let value):
            errorText = nil
            let reply = replyAmount(value: value, w: widget, language: "it")
            onAnswer(reply, nil)
        case .failure(let err):
            errorText = AssistantTexts.amountError(err, min: widget.min, max: widget.max)
        }
    }
}
