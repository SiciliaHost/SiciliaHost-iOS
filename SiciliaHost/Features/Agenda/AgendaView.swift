import Observation
import SwiftUI

/// Prezzi e promozioni di una casa per le celle del calendario: prezzo base, tariffe per date, promozioni automatiche.
struct HousePrices: Equatable, Sendable {
    var base: Double?
    var rates: [SeasonalRateEntry] = []
    var promotions: [PromoEntry] = []
}

/// Dati dell'Agenda (`CalendarViewModel`): tutte le prenotazioni delle case su cui si opera, i loro nomi, la casa scelta
/// (il calendario mostra una casa alla volta) e i suoi prezzi.
@MainActor
@Observable
final class AgendaModel {
    private(set) var reservations: [Reservation] = []
    private(set) var propertyNames: [String: String] = [:]
    /// Le case su cui l'utente opera, per nome.
    private(set) var properties: [Property] = []
    private(set) var selectedPropertyId: String?
    /// Prenotazioni il cui check-in è già stato inviato (segno `checkin`).
    private(set) var checkinSentIds: Set<String> = []
    private(set) var isLoading = false
    private(set) var prices = HousePrices()

    private let fetch: ([String]) async throws -> ReservationsWithCheckin
    private let fetchPrices: (AccessScope?, String) async -> HousePrices?

    init(
        fetch: @escaping ([String]) async throws -> ReservationsWithCheckin = {
            try await FirestoreService().getReservationsWithCheckin(propertyIds: $0)
        },
        // Solo per chi ha il permesso prezzi e per un annuncio approvato; se mancano (o la callable non risponde) il
        // calendario non mostra prezzi, il resto funziona.
        fetchPrices: @escaping (AccessScope?, String) async -> HousePrices? = { scope, id in
            guard let scope, scope.priceProperties.contains(where: { $0.id == id }) else { return nil }
            guard let content = try? await SiteContentService().getProperties([id]).first,
                  canEditCalendarPrices(content.status) else { return nil }
            let service = PriceService()
            guard let rates = try? await service.getSeasonalRates(propertyId: id) else { return nil }
            let promotions = (try? await service.listPromotions(propertyId: id)) ?? []
            return HousePrices(base: content.basePricePerNight, rates: rates, promotions: promotions)
        }
    ) {
        self.fetch = fetch
        self.fetchPrices = fetchPrices
    }

    func load(scope: AccessScope?) async {
        let operable = scope?.operable ?? []
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await fetch(operable.map(\.id))
            reservations = loaded.reservations
            checkinSentIds = loaded.checkinSentIds
            propertyNames = Dictionary(operable.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            properties = operable.sorted { $0.name.lowercased() < $1.name.lowercased() }
            if selectedPropertyId == nil || !properties.contains(where: { $0.id == selectedPropertyId }) {
                selectedPropertyId = properties.first?.id
            }
        } catch {
            // Come l'Android: in caso d'errore resta quel che c'era.
        }
        await loadPrices(scope: scope)
    }

    func select(_ id: String, scope: AccessScope?) async {
        guard id != selectedPropertyId, properties.contains(where: { $0.id == id }) else { return }
        selectedPropertyId = id
        prices = HousePrices()
        await loadPrices(scope: scope)
    }

    private func loadPrices(scope: AccessScope?) async {
        guard let id = selectedPropertyId else { return }
        let loaded = await fetchPrices(scope, id)
        // Una risposta arrivata dopo un cambio di casa non tocca i prezzi della casa nuova.
        guard selectedPropertyId == id else { return }
        prices = loaded ?? HousePrices()
    }
}

/// Agenda (`CalendarScreen.kt`): un calendario a mesi che scorre in verticale (come Airbnb), una casa alla volta. Ogni
/// giorno è una cella con il prezzo a notte e l'eventuale sconto; le prenotazioni sono barre che attraversano i giorni,
/// con il nome e gli ospiti. Toccando una barra si apre la modifica della prenotazione. «Modifica prezzi» se l'utente
/// ha almeno una casa con prezzi modificabili e annuncio approvato.
struct AgendaView: View {
    let scope: AccessScope?
    let canEditPrices: Bool
    let onEditReservation: (String) -> Void
    let onEditPrices: () -> Void
    @State var model: AgendaModel

    @State private var visibleMonths: Set<Int> = []
    @State private var didScrollToToday = false

    // Quanti mesi si vedono prima e dopo il mese corrente.
    private static let monthsBefore = 3
    private static let monthsAfter = 24
    private static let gap: CGFloat = 3

    @MainActor
    init(
        scope: AccessScope?,
        canEditPrices: Bool,
        onEditReservation: @escaping (String) -> Void = { _ in },
        onEditPrices: @escaping () -> Void = {},
        model: AgendaModel? = nil
    ) {
        self.scope = scope
        self.canEditPrices = canEditPrices
        self.onEditReservation = onEditReservation
        self.onEditPrices = onEditPrices
        _model = State(initialValue: model ?? AgendaModel())
    }

    private var today: Int { MonthCalendar.romeDay(millisFromDate(Date())) }

    private struct MonthID: Hashable, Identifiable {
        let year: Int
        let month: Int
        var id: Int { year * 100 + month }
    }

    private var months: [MonthID] {
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = TimeZone(identifier: "Europe/Rome")!
        let now = rome.dateComponents([.year, .month], from: Date())
        let base = now.year! * 12 + (now.month! - 1)
        return (-Self.monthsBefore...Self.monthsAfter).map { offset in
            let index = base + offset
            return MonthID(year: index / 12, month: index % 12 + 1)
        }
    }

    private var todayMonthId: Int { months[Self.monthsBefore].id }

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayHeader
            Divider().overlay(Theme.outlineVariant)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(months) { month in
                            monthSection(month)
                                .id(month.id)
                                .onAppear { visibleMonths.insert(month.id) }
                                .onDisappear { visibleMonths.remove(month.id) }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .overlay(alignment: .bottomTrailing) { todayButton(proxy) }
                // Si parte dal mese corrente.
                .task {
                    guard !didScrollToToday else { return }
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(todayMonthId, anchor: .top)
                    didScrollToToday = true
                }
            }
            .cappedFontScale()
        }
        .padding(.horizontal, Dimens.screenPadding)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        // Si ricarica a ogni ritorno sull'Agenda: le prenotazioni appena sincronizzate o modificate devono comparire.
        .onAppear { Task { await model.load(scope: scope) } }
        .onChange(of: scope) { _, newScope in Task { await model.load(scope: newScope) } }
    }

    // MARK: Intestazione

    @ViewBuilder
    private var header: some View {
        if model.properties.count > 1 || canEditPrices {
            HStack(spacing: 8) {
                if model.properties.count > 1 {
                    SelectField(
                        label: "Casa",
                        options: model.properties.map(\.id),
                        selected: model.selectedPropertyId,
                        optionLabel: { id in
                            let name = model.propertyNames[id] ?? ""
                            return name.trimmed.isEmpty ? "Casa senza nome" : name
                        },
                        onSelect: { id in Task { await model.select(id, scope: scope) } }
                    )
                } else {
                    Spacer()
                }
                if canEditPrices {
                    Button("Modifica prezzi", action: onEditPrices)
                        .buttonStyle(.appOutlined)
                        .tourTarget(.agendaPrices)
                }
            }
            .padding(.top, Dimens.itemSpacing)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: Self.gap) {
            ForEach(MonthCalendar.weekdayHeaders, id: \.self) { day in
                Text(day)
                    .appStyle(.labelMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Dimens.itemSpacing)
        .padding(.bottom, 4)
    }

    // «Oggi» compare solo quando il mese corrente non si vede più.
    @ViewBuilder
    private func todayButton(_ proxy: ScrollViewProxy) -> some View {
        if !visibleMonths.isEmpty && !visibleMonths.contains(todayMonthId) {
            let scrolledPast = (visibleMonths.min() ?? 0) > todayMonthId
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(todayMonthId, anchor: .top) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: scrolledPast ? "arrow.up" : "arrow.down")
                        .font(.system(size: Dimens.iconSmall, weight: .semibold))
                    Text("Oggi").appStyle(.labelLarge).fontWeight(.semibold)
                }
                .foregroundStyle(Theme.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.surfaceContainerLowest))
                .overlay(Capsule().strokeBorder(Theme.outlineVariant, lineWidth: 1))
                .softShadow(6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .padding(.bottom, 12)
            .accessibilityLabel("Vai a oggi")
        }
    }

    // MARK: Mese

    private func monthSection(_ month: MonthID) -> some View {
        let reservations = model.reservations.filter { $0.propertyId == model.selectedPropertyId }
        let weeks = MonthCalendar.monthWeeks(year: month.year, month: month.month)
        let showYear = month.year != months[Self.monthsBefore].year
        let name = MonthCalendar.monthNames[month.month - 1]
        return VStack(alignment: .leading, spacing: Self.gap) {
            Text(showYear ? "\(name) \(month.year)" : name)
                .appStyle(.headlineSmall)
                .foregroundStyle(Theme.onSurface)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                WeekRowView(
                    week: week, today: today, reservations: reservations, prices: model.prices,
                    gap: Self.gap, onEditReservation: onEditReservation
                )
            }
        }
    }
}

/// Una riga-settimana: sette celle e, sopra, le barre dei soggiorni (una corsia in più per ogni sovrapposizione).
private struct WeekRowView: View {
    let week: [Int?]
    let today: Int
    let reservations: [Reservation]
    let prices: HousePrices
    let gap: CGFloat
    let onEditReservation: (String) -> Void

    private let cellHeight: CGFloat = 86
    private let barTop: CGFloat = 28
    private let barHeight: CGFloat = 26
    private let lanePitch: CGFloat = 30

    var body: some View {
        let bars = MonthCalendar.weekBars(week: week, reservations: reservations)
        let touched = MonthCalendar.daysTouched(week: week, bars: bars)
        let rowHeight = cellHeight + lanePitch * CGFloat(MonthCalendar.laneCount(bars) - 1)
        GeometryReader { geo in
            let cellWidth = (geo.size.width - gap * 6) / 7
            let pitch = cellWidth + gap
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let past = day < today
                            let showPrice = !past && !touched.contains(day)
                            DayCellView(
                                day: day, isToday: day == today, isPast: past,
                                price: showPrice ? MonthCalendar.nightlyPrice(day: day, base: prices.base, rates: prices.rates) : nil,
                                discount: showPrice ? MonthCalendar.discountLabel(day: day, promotions: prices.promotions) : nil
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                ForEach(bars) { bar in
                    Button { onEditReservation(bar.reservation.id) } label: {
                        StayBarView(bar: bar, past: MonthCalendar.romeDay(bar.reservation.checkOut) < today, height: barHeight)
                    }
                    .buttonStyle(.plain)
                    .frame(width: pitch * CGFloat(bar.x1 - bar.x0), height: barHeight)
                    .offset(x: pitch * CGFloat(bar.x0), y: barTop + lanePitch * CGFloat(bar.lane))
                }
            }
        }
        .frame(height: rowHeight)
    }
}

private struct DayCellView: View {
    let day: Int
    let isToday: Bool
    let isPast: Bool
    let price: Double?
    let discount: String?

    var body: some View {
        let shape = roundedShape(10)
        let number = String(Int(MonthCalendar.iso(day).suffix(2)) ?? 0)
        VStack(alignment: .leading, spacing: 0) {
            if isToday {
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.primary))
            } else {
                Text(number)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.onSurface.opacity(isPast ? 0.45 : 1))
                    .padding(.leading, 2)
                    .padding(.top, 2)
            }
            if let price {
                Text(MonthCalendar.formatEuro(price))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
                    .padding(.leading, 2)
                    .padding(.top, 6)
            }
            if let discount {
                Text(discount)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(roundedShape(6).fill(Theme.surfaceContainerHigh))
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.top, 5)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(isPast ? Theme.surfaceContainerLow : Theme.surfaceContainerLowest))
        .overlay(shape.strokeBorder(Theme.outlineVariant, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

private struct StayBarView: View {
    let bar: MonthCalendar.BarSegment
    let past: Bool
    let height: CGFloat

    var body: some View {
        let reservation = bar.reservation
        let block = MonthCalendar.isBlock(reservation)
        let background: Color = block ? Theme.surfaceContainerHigh : (past ? Theme.outline : Theme.onSurface)
        let foreground: Color = block ? Theme.onSurfaceVariant : Theme.surfaceContainerLowest
        let round = height / 2
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.roundStart ? round : 0, bottomLeadingRadius: bar.roundStart ? round : 0,
            bottomTrailingRadius: bar.roundEnd ? round : 0, topTrailingRadius: bar.roundEnd ? round : 0,
            style: .continuous
        )
        HStack(spacing: 6) {
            // Il cerchietto con l'iniziale solo dove il soggiorno comincia, e il colore dice la piattaforma.
            if bar.roundStart && !block {
                Text(MonthCalendar.stayInitial(reservation))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(avatarForeground(reservation))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(avatarBackground(reservation)))
            }
            Text(MonthCalendar.stayLabel(reservation))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, bar.roundStart ? 3 : 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape.fill(background))
        .clipShape(shape)
        .contentShape(shape)
    }

    private func avatarBackground(_ r: Reservation) -> Color {
        switch r.platform {
        case "AIRBNB": return Theme.errorContainer
        case "BOOKING": return Theme.secondaryContainer
        default: return Theme.primaryContainer
        }
    }

    private func avatarForeground(_ r: Reservation) -> Color {
        switch r.platform {
        case "AIRBNB": return Theme.onErrorContainer
        case "BOOKING": return Theme.onSecondaryContainer
        default: return Theme.onPrimaryContainer
        }
    }
}

/// Riga di un arrivo o di una partenza: barretta verde (entra) o rossa (esce), nome, "Casa · PIATTAFORMA · N pers.".
struct AgendaReservationRow: View {
    let reservation: Reservation
    let isCheckIn: Bool
    let propertyName: String
    var checkinSent = false

    var body: some View {
        let accent = isCheckIn ? Theme.primary : Theme.error
        HStack(spacing: Dimens.cardPadding) {
            roundedShape(2).fill(accent).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName ?? "Ospite")
                    .appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(AgendaLogic.rowSubtitle(reservation, propertyName: propertyName))
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                if checkinSent { CheckinSentLabel() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(isCheckIn ? "ENTRA" : "ESCE")
                .appStyle(.labelSmall)
                .foregroundStyle(accent)
                .padding(.leading, 8)
        }
        .padding(Dimens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .contentShape(Rectangle())
    }
}
