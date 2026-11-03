import Observation
import SwiftUI

/// Dati dell'Agenda (`CalendarViewModel`): tutte le prenotazioni delle case su cui si opera e i loro nomi.
@MainActor
@Observable
final class AgendaModel {
    private(set) var reservations: [Reservation] = []
    private(set) var propertyNames: [String: String] = [:]
    private(set) var isLoading = false

    private let fetch: ([String]) async throws -> [Reservation]

    init(fetch: @escaping ([String]) async throws -> [Reservation] = { try await FirestoreService().getReservations(propertyIds: $0) }) {
        self.fetch = fetch
    }

    func load(scope: AccessScope?) async {
        let operable = scope?.operable ?? []
        isLoading = true
        defer { isLoading = false }
        do {
            reservations = try await fetch(operable.map(\.id))
            propertyNames = Dictionary(operable.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        } catch {
            // Come l'Android: in caso d'errore resta quel che c'era.
        }
    }
}

/// Agenda (`CalendarScreen.kt`): griglia del mese con i giorni di arrivo (pallino verde) e partenza (pallino rosso),
/// elenco di arrivi e partenze del giorno scelto (tocco → modifica prenotazione), "Modifica prezzi" se l'utente ha
/// almeno una casa con prezzi modificabili e annuncio approvato.
struct AgendaView: View {
    let scope: AccessScope?
    let canEditPrices: Bool
    let onEditReservation: (String) -> Void
    let onEditPrices: () -> Void
    @State var model: AgendaModel

    @State private var month: Date = Date()
    @State private var selectedDay: Date = Date()

    private var calendar: Calendar { .current }

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthGrid.cappedFontScale()
                dayEvents
            }
            .padding(Dimens.screenPadding)
        }
        .refreshable { await model.load(scope: scope) }
        // Si ricarica a ogni ritorno sull'Agenda: le prenotazioni appena sincronizzate o modificate devono comparire.
        .onAppear { Task { await model.load(scope: scope) } }
        .onChange(of: scope) { _, newScope in Task { await model.load(scope: newScope) } }
    }

    // MARK: Mese

    private var monthGrid: some View {
        VStack(spacing: Dimens.itemSpacing) {
            if canEditPrices {
                HStack {
                    Spacer()
                    Button("Modifica prezzi", action: onEditPrices)
                        .buttonStyle(.appOutlined)
                        .tourTarget(.agendaPrices)
                }
            }
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: Dimens.iconSmall, weight: .semibold))
                }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Mese precedente")
                Spacer()
                Text(monthTitle(month))
                    .appStyle(.labelSmall)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: Dimens.iconSmall, weight: .semibold))
                }
                .buttonStyle(.appIcon)
                .accessibilityLabel("Mese successivo")
            }

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(AgendaLogic.weekdayHeaders, id: \.self) { day in
                        Text(day)
                            .appStyle(.labelMedium)
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 4) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                if let day { dayCell(day) } else { Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity) }
                            }
                        }
                    }
                }
            }
            // Celle quadrate sotto i ~56 pt anche su schermi larghi.
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
    }

    private var rows: [[Int?]] {
        let first = firstOfMonth(month)
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = calendar.component(.weekday, from: first) - 1 // 0 = domenica, come l'Android
        return monthGridRows(daysInMonth: days, firstDayOfWeek: weekday)
    }

    private func dayCell(_ dayNumber: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: firstOfMonth(month)) ?? month
        let millis = millisFromDate(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let marks = AgendaLogic.marks(on: millis, in: model.reservations, calendar: calendar)
        return Button { selectedDay = date } label: {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .appStyle(.bodyMedium)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Theme.onPrimary : (marks.hasEvent ? Theme.primary : Theme.onSurface))
                if marks.hasEvent && !isSelected {
                    HStack(spacing: 2) {
                        if marks.checkIns { Circle().fill(Theme.primary).frame(width: 4, height: 4) }
                        if marks.checkOuts { Circle().fill(Theme.error).frame(width: 4, height: 4) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Circle().fill(
                isSelected ? Theme.primary : (marks.hasEvent ? Theme.primaryContainer.opacity(0.5) : Color.clear)
            ))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(dayAccessibility(date, marks))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Giorno scelto

    private var dayEvents: some View {
        let events = AgendaLogic.events(on: millisFromDate(selectedDay), in: model.reservations, calendar: calendar)
        return VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            Text(dayTitle(selectedDay))
                .appStyle(.labelSmall)
                .foregroundStyle(Theme.onSurfaceVariant)
            if events.isEmpty {
                Text("Nessun check-in o check-out in questa data.")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(events) { res in
                    Button { onEditReservation(res.id) } label: {
                        AgendaReservationRow(
                            reservation: res,
                            isCheckIn: AgendaLogic.isSameDay(res.checkIn, millisFromDate(selectedDay), calendar: calendar),
                            propertyName: model.propertyNames[res.propertyId] ?? res.propertyId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Date

    private func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func shiftMonth(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: firstOfMonth(month)) ?? month
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).uppercased()
    }

    private func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date).uppercased()
    }

    private func dayAccessibility(_ date: Date, _ marks: AgendaLogic.DayMarks) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMMM"
        var parts = [f.string(from: date)]
        if marks.checkIns { parts.append("arrivi") }
        if marks.checkOuts { parts.append("partenze") }
        return parts.joined(separator: ", ")
    }
}

/// Riga di un arrivo o di una partenza: barretta verde (entra) o rossa (esce), nome, "Casa · PIATTAFORMA · N pers.".
struct AgendaReservationRow: View {
    let reservation: Reservation
    let isCheckIn: Bool
    let propertyName: String

    var body: some View {
        let accent = isCheckIn ? Theme.primary : Theme.error
        HStack(spacing: Dimens.cardPadding) {
            roundedShape(2).fill(accent).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.guestName ?? "Ospite")
                    .appStyle(.titleSmall).foregroundStyle(Theme.onSurface).lineLimit(2)
                Text(AgendaLogic.rowSubtitle(reservation, propertyName: propertyName))
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
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
