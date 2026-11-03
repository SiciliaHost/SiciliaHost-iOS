import SwiftUI

private let weekdayNames = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]

/// Statistiche complete delle prenotazioni (`BookingStatsScreen`), con gli stessi filtri delle Finanze.
struct BookingStatsView: View {
    let model: FinanceModel
    let view: FinanceViewData
    let onBack: () -> Void

    var body: some View {
        let s = view.stats
        VStack(spacing: 0) {
            CompactTopBar(title: "Statistiche prenotazioni", onBack: onBack)
            ScrollView {
                VStack(spacing: Dimens.sectionSpacing) {
                    FinanceFilters(model: model)
                    KpiGrid(items: statsKpis(view, all: true))
                    if !view.insights.isEmpty {
                        FinanceCard(title: "Da migliorare") {
                            ForEach(Array(view.insights.enumerated()), id: \.offset) { _, i in InsightRow(insight: i) }
                        }
                    }
                    Text("Anticipo, paese, motivo del viaggio, dispositivo e commissione reale arrivano dall'Excel \"Arrivi con recapiti\" di Booking: reimporta il file per aggiungerli anche alle prenotazioni già salvate.")
                        .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                    if !s.monthlyOccupancy.isEmpty {
                        FinanceCard(title: "Occupazione mese per mese") {
                            BarList(entries: s.monthlyOccupancy.map { ($0.label, $0.occupancy) }, valueLabel: FinanceFormat.pct, maxValue: 1)
                        }
                    }
                    if !s.channels.isEmpty {
                        FinanceCard(title: "Canali (notti)") {
                            BarList(entries: s.channels.map { (FinanceFormat.platformName($0.platform), Double($0.nights)) },
                                    valueLabel: { "\(Int($0)) notti" })
                            ForEach(s.channels, id: \.platform) { c in
                                Text("\(FinanceFormat.platformName(c.platform)): \(c.count) prenotazioni · \(FinanceFormat.euro0(c.gross)) lordi · \(FinanceFormat.euro0(c.commission)) di commissioni")
                                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                            }
                        }
                    }
                    if s.reservationCount > 0 {
                        FinanceCard(title: "Durata dei soggiorni") {
                            BarList(entries: s.stayLengths.map { ($0.label, Double($0.count)) }, valueLabel: { "\(Int($0))" },
                                    color: Theme.secondary)
                        }
                        FinanceCard(title: "Giorno di arrivo") {
                            BarList(entries: zip(weekdayNames, s.checkInWeekdays).map { ($0, Double($1)) }, valueLabel: { "\(Int($0))" },
                                    color: Theme.secondary)
                        }
                    }
                    if !s.countries.isEmpty {
                        FinanceCard(title: "Da dove arrivano") {
                            BarList(entries: s.countries.prefix(8).map { (FinanceFormat.countryName($0.label), Double($0.count)) },
                                    valueLabel: { "\(Int($0))" })
                        }
                    }
                    if !s.purposes.isEmpty || !s.devices.isEmpty {
                        FinanceCard(title: "Motivo e dispositivo") {
                            if !s.purposes.isEmpty {
                                BarList(entries: s.purposes.map { ($0.label, Double($0.count)) }, valueLabel: { "\(Int($0))" })
                            }
                            if !s.devices.isEmpty {
                                BarList(entries: s.devices.map { ($0.label, Double($0.count)) }, valueLabel: { "\(Int($0))" },
                                        color: Theme.error)
                            }
                        }
                    }
                }
                .padding(Dimens.screenPadding)
            }
        }
    }
}

/// Spese raggruppate per categoria (`ExpensesScreen`), con filtro di categoria e cancellazione. Le spese generate da una
/// spesa fissa (`rec_…`) non si cancellano qui: si ricreerebbero al caricamento successivo.
struct ExpensesListView: View {
    let model: FinanceModel
    let onBack: () -> Void
    @State private var category: ExpenseCategory?
    @State private var toDelete: Expense?

    init(model: FinanceModel, initialCategory: ExpenseCategory?, onBack: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        let view = model.view()
        let groups = groupsOf(view.expenses)
        VStack(spacing: 0) {
            CompactTopBar(title: "Spese", onBack: onBack)
            ScrollView {
                LazyVStack(spacing: Dimens.itemSpacing) {
                    FinanceFilters(model: model)
                    SelectField(
                        label: "Categoria",
                        options: [""] + ExpenseCategory.allCases.map(\.key),
                        selected: category?.key ?? "",
                        optionLabel: { ExpenseCategory.fromKey($0)?.label ?? "Tutte le categorie" },
                        onSelect: { category = ExpenseCategory.fromKey($0) }
                    )
                    if groups.isEmpty {
                        Text("Nessuna spesa nel periodo.").appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                            .padding(.vertical, 24)
                    }
                    ForEach(groups, id: \.category.key) { group in
                        HStack {
                            Text(group.category.label.uppercased()).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(group.items.count) · \(FinanceFormat.euro2(group.total))").appStyle(.labelLarge).foregroundStyle(Theme.error)
                        }
                        .padding(.top, Dimens.sectionSpacing)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { index, e in
                            ExpenseRow(
                                expense: e,
                                houseName: model.propertyName(e.propertyId),
                                subtitle: "\(dayMonthYearLong(e.timestamp)) · \(model.propertyName(e.propertyId))",
                                onDelete: e.id.hasPrefix("rec_") ? nil : { toDelete = e }
                            )
                            .id(FinanceListKeys.expense(e.id, index: index))
                        }
                    }
                }
                .padding(Dimens.screenPadding)
            }
        }
        .confirmationDialog("Eliminare la spesa?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible, presenting: toDelete) { e in
            Button("Elimina", role: .destructive) { Task { await model.deleteExpense(e) } }
            Button("Annulla", role: .cancel) {}
        } message: { e in
            Text("\"\(e.description)\" (\(FinanceFormat.euro2(e.amount))) viene tolta dal registro.")
        }
    }

    private struct CategoryGroup {
        let category: ExpenseCategory
        let items: [Expense]
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    private func groupsOf(_ expenses: [Expense]) -> [CategoryGroup] {
        var order: [ExpenseCategory] = []
        var byCategory: [ExpenseCategory: [Expense]] = [:]
        for e in expenses {
            let c = ExpenseCategory.of(e)
            guard category == nil || c == category else { continue }
            if byCategory[c] == nil { order.append(c) }
            byCategory[c, default: []].append(e)
        }
        return stableSortedDescending(order.map { CategoryGroup(category: $0, items: byCategory[$0]!) }) { $0.total }
    }
}

/// "03 nov 2026" nel fuso del telefono, come `SimpleDateFormat("dd MMM yyyy", Locale.ITALY)`.
func dayMonthYearLong(_ millis: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "dd MMM yyyy"
    return f.string(from: dateFromMillis(millis))
}
