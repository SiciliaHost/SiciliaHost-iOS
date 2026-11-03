import SwiftUI

/// Finanze (`FinanceScreen.kt`): filtri periodo/casa, bilancio, prenotazioni (→ statistiche), suggerimenti, grafici,
/// spese per categoria (→ elenco spese), ultime spese, importi da inserire, spese fisse, regime commissioni.
struct FinanceView: View {
    let scope: AccessScope?
    @State private var model: FinanceModel
    @State private var sub: FinanceSub?
    @State private var dialog: FinanceDialog?
    @State private var recurringToDelete: RecurringExpense?

    private static let monthlyChartMonths = 6
    private static let recentExpenses = 5

    @MainActor
    init(scope: AccessScope?, model: FinanceModel? = nil) {
        self.scope = scope
        _model = State(initialValue: model ?? FinanceModel())
    }

    var body: some View {
        Group {
            switch sub {
            case .stats:
                BookingStatsView(model: model, view: model.view()) { sub = nil }
            case let .expenses(category):
                ExpensesListView(model: model, initialCategory: category) { sub = nil }
            case nil:
                overview
            }
        }
        // Si ricarica a ogni ingresso nella sezione: case, prenotazioni o regimi possono essere cambiati altrove.
        .onAppear { Task { await model.load() } }
        .onChange(of: scope) { _, _ in Task { await model.load() } }
        .sheet(item: $dialog) { d in
            switch d {
            case .newExpense:
                ExpenseFormSheet(title: "Nuova spesa", hint: nil, model: model) { p, desc, amount, cat in
                    Task { await model.addExpense(propertyId: p, description: desc, amount: amount, category: cat) }
                }
            case .newRecurring:
                ExpenseFormSheet(title: "Nuova spesa fissa mensile",
                                 hint: "Verrà registrata ogni mese a partire da questo mese (es. affitto, internet).",
                                 model: model) { p, desc, amount, cat in
                    Task { await model.addRecurring(propertyId: p, description: desc, amount: amount, category: cat) }
                }
            case let .gross(reservationId):
                if let res = model.reservations.first(where: { $0.id == reservationId }) {
                    GrossAmountSheet(reservation: res, houseName: model.propertyName(res.propertyId)) { amount in
                        Task { await model.saveGross(res, amount: amount) }
                    }
                }
            }
        }
        .confirmationDialog("Eliminare la spesa fissa?", isPresented: Binding(
            get: { recurringToDelete != nil }, set: { if !$0 { recurringToDelete = nil } }
        ), titleVisibility: .visible, presenting: recurringToDelete) { rec in
            Button("Elimina", role: .destructive) { Task { await model.deleteRecurring(rec.id) } }
            Button("Annulla", role: .cancel) {}
        } message: { rec in
            Text("\"\(rec.description)\" non verrà più registrata nei mesi futuri. Le spese già registrate restano nel registro.")
        }
        .alert("Finanze", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
    }

    @ViewBuilder
    private var overview: some View {
        if model.isLoading && model.properties.isEmpty && model.reservations.isEmpty {
            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let now = millisFromDate(Date())
            let view = model.view(now: now)
            let houseIds = Set(view.houses.map(\.id))
            let houseReservations = model.reservations.filter { houseIds.contains($0.propertyId) }
            let houseExpenses = model.expenses.filter { houseIds.contains($0.propertyId) }
            let propertyStats = FinanceStats.perProperty(reservations: view.reservations, expenses: view.expenses, properties: model.properties)
            let monthly = FinanceStats.monthly(reservations: houseReservations, expenses: houseExpenses, properties: model.properties,
                                               monthCount: Self.monthlyChartMonths, now: now)
            let platforms = FinanceStats.perPlatform(view.reservations)
            let pending = houseReservations.filter { $0.grossAmount == nil }
            ScrollView {
                LazyVStack(spacing: Dimens.itemSpacing) {
                    FinanceFilters(model: model)
                    BalanceOverview(totals: view.totals).tourTarget(.finanzeBalance)
                    FinanceCard(title: "Prenotazioni", action: {
                        Button("Statistiche") { sub = .stats }.buttonStyle(.appText)
                    }, content: { KpiGrid(items: statsKpis(view, all: false)) })
                    if !view.insights.isEmpty {
                        FinanceCard(title: "Da migliorare", action: {
                            if view.insights.count > 3 {
                                Button("Tutti (\(view.insights.count))") { sub = .stats }.buttonStyle(.appText)
                            }
                        }, content: {
                            ForEach(Array(view.insights.prefix(3).enumerated()), id: \.offset) { _, i in InsightRow(insight: i) }
                        })
                    }
                    if monthly.contains(where: { $0.revenue > 0 || $0.expenses > 0 }) {
                        FinanceSectionLabel(text: "ANDAMENTO ULTIMI \(Self.monthlyChartMonths) MESI")
                        chartCard { MonthlyBarsChart(months: monthly).cappedFontScale() }
                    }
                    if view.totals.gross > 0 && view.houses.count > 1 {
                        FinanceSectionLabel(text: "NETTO PER STRUTTURA")
                        chartCard { PropertyBarsChart(stats: propertyStats) }
                        FinanceSectionLabel(text: "DETTAGLIO STRUTTURE")
                        ForEach(propertyStats, id: \.property.id) { PropertyDetailCard(stat: $0) }
                    }
                    if platforms.count > 1 {
                        FinanceSectionLabel(text: "INCASSI PER PIATTAFORMA")
                        chartCard { PlatformDonutChart(totals: platforms) }
                    }

                    FinanceCard(title: "Spese per categoria", action: {
                        Button { dialog = .newExpense } label: { Image(systemName: "plus") }
                            .buttonStyle(.appIcon)
                            .accessibilityLabel("Aggiungi spesa")
                    }, content: {
                        if view.byCategory.isEmpty {
                            Text("Nessuna spesa nel periodo.").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                        } else {
                            let total = view.byCategory.reduce(0) { $0 + $1.amount }
                            BarList(entries: view.byCategory.map { ($0.category.label, $0.amount) },
                                    valueLabel: { "\(FinanceFormat.euro0($0)) · \(FinanceFormat.pct($0 / total))" },
                                    color: Theme.error,
                                    onTap: { sub = .expenses(view.byCategory[$0].category) })
                        }
                    })
                    if !view.expenses.isEmpty {
                        HStack {
                            FinanceSectionLabel(text: "ULTIME SPESE")
                            Button("Tutte (\(view.expenses.count))") { sub = .expenses(nil) }.buttonStyle(.appText)
                        }
                        ForEach(Array(view.expenses.prefix(Self.recentExpenses).enumerated()),
                                id: \.element.id) { _, e in ExpenseRow(expense: e, houseName: model.propertyName(e.propertyId)) }
                    }
                    if !pending.isEmpty {
                        // Giallo, non rosso: "manca l'importo" è da rivedere, non un errore.
                        FinanceSectionLabel(text: "IMPORTI DA INSERIRE · \(pending.count)", color: Theme.secondary)
                        ForEach(pending) { res in
                            PendingAmountRow(reservation: res, houseName: model.propertyName(res.propertyId)) {
                                dialog = .gross(reservationId: res.id)
                            }
                        }
                    }
                    HStack {
                        FinanceSectionLabel(text: "SPESE FISSE MENSILI")
                        Button { dialog = .newRecurring } label: { Image(systemName: "plus") }
                            .buttonStyle(.appIcon)
                            .accessibilityLabel("Aggiungi spesa fissa mensile")
                    }
                    ForEach(model.recurring.filter { houseIds.contains($0.propertyId) }) { rec in
                        RecurringRow(recurring: rec, houseName: model.propertyName(rec.propertyId)) { recurringToDelete = rec }
                    }
                    FinanceSectionLabel(text: "REGIME COMMISSIONI")
                    ForEach(view.houses) { p in
                        CommissionRow(property: p, canChange: model.isSuperAdmin) { value in
                            Task { await model.setCommissionMode(p, value) }
                        }
                    }
                }
                .padding(Dimens.screenPadding)
            }
            .refreshable { await model.load() }
        }
    }

    private func chartCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(Dimens.cardPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
    }
}

enum FinanceSub: Hashable {
    case stats
    case expenses(ExpenseCategory?)
}

enum FinanceDialog: Identifiable, Hashable {
    case newExpense, newRecurring
    case gross(reservationId: String)
    var id: Self { self }
}

/// Bilancio: saldo grande, entrate/uscite, lordo e netto proprietari.
private struct BalanceOverview: View {
    let totals: FinanceStats.Totals

    var body: some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BILANCIO NETTO STIMATO").appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                Text(FinanceFormat.euroPlain(totals.balance))
                    .appStyle(.displaySmall)
                    .foregroundStyle(totals.balance >= 0 ? Theme.primary : Theme.error)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .cappedFontScale()
            }
            Divider()
            HStack(spacing: Dimens.cardPadding) {
                tile("ENTRATE", totals.adminRevenue, Theme.primary)
                tile("USCITE", totals.expenses, Theme.error)
            }
            HStack(spacing: Dimens.cardPadding) {
                tile("LORDO TOTALE", totals.gross, Theme.onSurface)
                tile("NETTO PROPRIETARI", totals.netOwner, Theme.onSurfaceVariant)
            }
        }
        .padding(Dimens.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func tile(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant).cappedFontScale()
            Text(FinanceFormat.euroPlain(value)).appStyle(.titleMedium).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Entrate, spese e netto di una struttura.
private struct PropertyDetailCard: View {
    let stat: FinanceStats.PropertyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(stat.property.name).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(stat.reservationCount) prenotazioni").appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(.bottom, Dimens.itemSpacing)
            row("Lordo", stat.gross, Theme.onSurface)
            row("Entrate gestione", stat.adminRevenue, Theme.primary)
            row("Spese", stat.expenses, Theme.error)
            Divider().padding(.vertical, Dimens.itemSpacing)
            row("Netto struttura", stat.balance, stat.balance >= 0 ? Theme.primary : Theme.error)
        }
        .padding(Dimens.cardPadding + 2)
        .appCard()
    }

    private func row(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(label).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            Spacer()
            Text(FinanceFormat.euroPlain(value)).appStyle(.bodySmall).foregroundStyle(color)
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let houseName: String
    var subtitle: String?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.description).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(subtitle ?? "\(ExpenseCategory.of(expense).label) · \(houseName)")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("-\(FinanceFormat.euro2(expense.amount))").appStyle(.titleSmall).foregroundStyle(Theme.error)
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.appIcon)
                    .accessibilityLabel("Elimina spesa")
            }
        }
        .padding(Dimens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

private struct PendingAmountRow: View {
    let reservation: Reservation
    let houseName: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName ?? "Ospite").appStyle(.titleSmall).foregroundStyle(Theme.onSecondaryContainer).lineLimit(2)
                Text("\(houseName) · \(FinanceFormat.platformName(reservation.platform))")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSecondaryContainer.opacity(0.75)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Importo", action: onTap)
                .buttonStyle(.appPrimary(container: Theme.secondary, content: Theme.onSecondary))
        }
        .padding(Dimens.cardPadding)
        .appCard(container: Theme.secondaryContainer)
    }
}

private struct RecurringRow: View {
    let recurring: RecurringExpense
    let houseName: String
    let onDelete: () -> Void

    var body: some View {
        let category = ExpenseCategory.fromKey(recurring.category) ?? ExpenseCategory.infer(recurring.description)
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recurring.description).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text("\(category.label) · \(houseName) · dal \(recurring.startMonth)")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(FinanceFormat.euro2(recurring.amount))/mese").appStyle(.titleSmall).foregroundStyle(Theme.error)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Elimina spesa fissa")
        }
        .padding(.leading, Dimens.cardPadding)
        .padding(.vertical, 4)
        .appCard()
    }
}

private struct CommissionRow: View {
    let property: Property
    let canChange: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.name).appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(property.isManagedOnCommission ? "Mandato · 25% + 50€ · aliquota 21%" : "Proprietà diretta · incasso intero")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Solo il super-admin cambia il regime.
            if canChange {
                Toggle("In commissione", isOn: Binding(get: { property.isManagedOnCommission }, set: onChange))
                    .labelsHidden()
                    .tint(Theme.primary)
            }
        }
        .padding(Dimens.cardPadding)
        .appCard()
    }
}

/// Nuova spesa o spesa fissa: descrizione, importo, categoria proposta dalla descrizione finché non la si sceglie, casa.
private struct ExpenseFormSheet: View {
    let title: String
    let hint: String?
    let model: FinanceModel
    let onConfirm: (String, String, Double, ExpenseCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var amount = ""
    @State private var chosenCategory: ExpenseCategory?
    @State private var propertyId = ""

    var body: some View {
        let category = chosenCategory ?? ExpenseCategory.infer(description)
        let value = FinanceActions.parseAmount(amount)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                if let hint { Text(hint).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant) }
                AppTextField(label: "Descrizione", text: $description)
                AppTextField(label: "Importo (€)", text: $amount, keyboard: .decimalPad)
                SelectField(label: "Categoria", options: ExpenseCategory.allCases, selected: category,
                            optionLabel: \.label, onSelect: { chosenCategory = $0 })
                if model.properties.count > 1 {
                    SelectField(label: "Casa", options: model.properties.map(\.id), selected: propertyId,
                                optionLabel: { model.propertyName($0) }, onSelect: { propertyId = $0 })
                }
                HStack {
                    Spacer()
                    Button("Annulla") { dismiss() }.buttonStyle(.appText)
                    Button("Aggiungi") {
                        if let value { onConfirm(propertyId, description.trimmed, value, category) }
                        dismiss()
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(value == nil || (value ?? 0) <= 0 || description.trimmed.isEmpty || propertyId.isEmpty)
                }
            }
            .padding(Dimens.screenPadding * 2)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surfaceContainerLow)
        .onAppear { if propertyId.isEmpty { propertyId = model.propertyFilter ?? model.properties.first?.id ?? "" } }
    }
}

/// "Inserisci importo lordo" di una prenotazione da completare (crea anche la spesa biancheria da 20 €).
private struct GrossAmountSheet: View {
    let reservation: Reservation
    let houseName: String
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inserisci importo lordo").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            Text("Ospite: \(reservation.guestName ?? "")").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
            Text("Struttura: \(houseName)").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
            Text("Piattaforma: \(reservation.platform)").appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
            AppTextField(label: "Lordo (€)", text: $text, keyboard: .decimalPad).padding(.top, 8)
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
                Button("Salva") {
                    if let v = FinanceActions.parseAmount(text) {
                        onSave(v)
                        dismiss()
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(FinanceActions.parseAmount(text) == nil)
            }
        }
        .padding(Dimens.screenPadding * 2)
        .presentationDetents([.medium])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}
