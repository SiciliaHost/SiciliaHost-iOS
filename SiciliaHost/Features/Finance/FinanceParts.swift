import SwiftUI

// Pezzi condivisi delle Finanze (`FinanceParts.kt`, `FinanceCharts.kt`): filtri, tessere, barre, suggerimenti, grafici
// disegnati in SwiftUI (come l'Android, nessuna libreria di grafici).

/// Periodo e casa, affiancati. La casa compare solo con più di una casa.
struct FinanceFilters: View {
    let model: FinanceModel

    var body: some View {
        HStack(spacing: Dimens.itemSpacing) {
            SelectField(label: "Periodo", options: FinancePeriod.allCases, selected: model.period,
                        optionLabel: \.label, onSelect: { model.period = $0 })
            if model.properties.count > 1 {
                SelectField(
                    label: "Casa",
                    options: [""] + model.properties.map(\.id),
                    selected: model.propertyFilter ?? "",
                    optionLabel: { $0.isEmpty ? "Tutte le case" : model.propertyName($0) },
                    onSelect: { model.propertyFilter = $0.isEmpty ? nil : $0 }
                )
            }
        }
    }
}

/// Tessere numeriche, 2 per riga.
struct KpiGrid: View {
    let items: [Kpi]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Dimens.itemSpacing), GridItem(.flexible())], spacing: Dimens.itemSpacing) {
            ForEach(items) { kpi in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kpi.label.uppercased()).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                    Text(kpi.value).appStyle(.titleLarge).fontWeight(.bold).foregroundStyle(Theme.onSurface).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let note = kpi.note {
                        Text(note).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                    }
                }
                .padding(Dimens.cardPadding + 2)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .appCard(container: Theme.surfaceContainer)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Barre orizzontali con etichetta e valore. `onTap` rende ogni riga toccabile; le barre sono in proporzione al massimo
/// (o a `maxValue`, es. 1 per le percentuali).
struct BarList: View {
    let entries: [(label: String, value: Double)]
    let valueLabel: (Double) -> String
    var color: Color = Theme.primary
    var maxValue: Double?
    var onTap: ((Int) -> Void)?

    var body: some View {
        let top = maxValue ?? entries.map(\.value).max() ?? 0
        let max = top > 0 ? top : 1
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let row = VStack(spacing: 3) {
                    HStack {
                        Text(entry.label).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(valueLabel(entry.value)).appStyle(.labelLarge).foregroundStyle(Theme.onSurface)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceContainerHighest)
                            Capsule().fill(color).frame(width: geo.size.width * min(Swift.max(entry.value / max, 0), 1))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                if let onTap {
                    Button { onTap(index) } label: { row }.buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

/// Card con titolo in maiuscoletto, azione a destra e contenuto.
struct FinanceCard<Action: View, Content: View>: View {
    let title: String
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                action()
            }
            content()
        }
        .padding(Dimens.cardPadding + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

extension FinanceCard where Action == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, action: { EmptyView() }, content: content)
    }
}

/// Un suggerimento "Da migliorare": lampadina su fondo giallo, titolo e testo.
struct InsightRow: View {
    let insight: FinanceInsights.Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.onSecondaryContainer)
                .frame(width: 34, height: 34)
                .background(roundedShape(12).fill(Theme.secondaryContainer))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                Text(insight.text).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }
}

/// Occhiello di sezione delle Finanze.
struct FinanceSectionLabel: View {
    let text: String
    var color: Color = Theme.onSurfaceVariant

    var body: some View {
        Text(text).appStyle(.labelSmall).foregroundStyle(color).padding(.top, Dimens.itemSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Grafici

/// Barre affiancate entrate/uscite per mese (altezza fissa).
struct MonthlyBarsChart: View {
    let months: [FinanceStats.MonthStats]

    var body: some View {
        let top = months.map { Swift.max($0.revenue, $0.expenses) }.max() ?? 0
        if top > 0 {
            VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                HStack(alignment: .bottom, spacing: Dimens.itemSpacing) {
                    ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                        VStack(spacing: 4) {
                            HStack(alignment: .bottom, spacing: 2) {
                                bar(month.revenue / top, Theme.primary)
                                bar(month.expenses / top, Theme.error)
                            }
                            .frame(height: 96)
                            Text(month.label).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(month.label): entrate \(FinanceFormat.euro0(month.revenue)), uscite \(FinanceFormat.euro0(month.expenses))")
                    }
                }
                ChartLegend(entries: [("Entrate", Theme.primary), ("Uscite", Theme.error)])
            }
        }
    }

    private func bar(_ fraction: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                    .fill(color)
                    .frame(height: geo.size.height * min(Swift.max(fraction, 0), 1))
            }
        }
    }
}

/// Netto per struttura, barre orizzontali.
struct PropertyBarsChart: View {
    let stats: [FinanceStats.PropertyStats]

    var body: some View {
        let top = stats.map { abs($0.balance) }.max() ?? 0
        if top > 0 {
            VStack(spacing: Dimens.itemSpacing) {
                ForEach(stats, id: \.property.id) { stat in
                    let color = stat.balance >= 0 ? Theme.primary : Theme.error
                    VStack(spacing: 3) {
                        HStack {
                            Text(stat.property.name).appStyle(.bodySmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(FinanceFormat.euroPlain(stat.balance)).appStyle(.bodySmall).foregroundStyle(color)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                roundedShape(3).fill(Theme.surfaceContainerHighest)
                                roundedShape(3).fill(color).frame(width: geo.size.width * min(abs(stat.balance) / top, 1))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Anello del lordo per piattaforma con legenda e importi.
struct PlatformDonutChart: View {
    let totals: [FinanceStats.PlatformTotal]
    private let palette = [Theme.primary, Theme.error, Theme.secondary, Theme.outline]

    var body: some View {
        let total = totals.reduce(0) { $0 + $1.gross }
        if total > 0 {
            HStack(spacing: Dimens.sectionSpacing) {
                ZStack {
                    ForEach(Array(totals.enumerated()), id: \.offset) { index, t in
                        let start = totals.prefix(index).reduce(0) { $0 + $1.gross } / total
                        Circle()
                            .trim(from: start, to: start + t.gross / total)
                            .stroke(palette[index % palette.count], style: StrokeStyle(lineWidth: 20))
                            .rotationEffect(.degrees(-90))
                    }
                }
                .padding(10)
                .frame(width: 110, height: 110)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(totals.enumerated()), id: \.offset) { index, t in
                        HStack(spacing: 6) {
                            Circle().fill(palette[index % palette.count]).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.platform).appStyle(.labelSmall).foregroundStyle(Theme.onSurface)
                                Text("\(FinanceFormat.euroPlain(t.gross)) · \(Int((t.gross / total * 100).rounded()))%")
                                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

struct ChartLegend: View {
    let entries: [(String, Color)]

    var body: some View {
        HStack(spacing: Dimens.sectionSpacing) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 6) {
                    Circle().fill(entry.1).frame(width: 10, height: 10)
                    Text(entry.0).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
