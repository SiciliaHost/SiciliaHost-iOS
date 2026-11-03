import SwiftUI

/// "Modifica prezzi" (`PriceEditorScreen.kt`): schermata intera aperta dall'Agenda. Si sceglie la casa, si selezionano le
/// notti trascinando il dito sul calendario (o "Tutto il mese") e si imposta il prezzo a notte; sotto, gli extra per
/// numero di ospiti e le promozioni automatiche sulle notti selezionate.
struct PriceEditorView: View {
    let onBack: () -> Void
    var initialPropertyId: String?
    @State private var model = PriceEditorModel()
    @State private var reservations: [Reservation] = []

    private static let gridGap: CGFloat = 4
    private static let gridMaxWidth: CGFloat = 300
    private static let cellAspect: CGFloat = 1.25 // larghezza / altezza: celle più basse che larghe

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Modifica prezzi", onBack: onBack)
            if model.isSaving || model.isLoading {
                ProgressView().progressViewStyle(.linear).tint(Theme.primary)
            } else {
                Spacer().frame(height: 4)
            }
            // Il trascinamento sulla griglia seleziona i giorni: per scorrere la pagina si tocca fuori dalla griglia.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topControls
                    if model.calendarVisible {
                        Spacer().frame(height: Dimens.itemSpacing)
                        monthHeader
                        Spacer().frame(height: Dimens.itemSpacing)
                        PriceGrid(model: model, reservations: reservations).cappedFontScale()
                    }
                    Spacer().frame(height: Dimens.sectionSpacing)
                    VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
                        editBar
                        Divider()
                        guestExtraSection
                        Divider()
                        promotionsSection
                    }
                }
                .padding(Dimens.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.load(initialPropertyId: initialPropertyId)
            // Le prenotazioni servono solo a segnare le notti occupate: un errore non blocca l'editor.
            if let scope = try? await AccessSession.shared.scope() {
                reservations = (try? await FirestoreService().getReservations(propertyIds: scope.operable.map(\.id))) ?? []
            }
        }
    }

    // MARK: Casa e calendario

    private var topControls: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if model.properties.isEmpty {
                Text(model.isLoading ? "Carico le case…" : "Nessuna casa trovata.")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SelectField(
                    label: "Casa",
                    // `PropertySiteContent` non è Hashable: le opzioni sono gli id, l'etichetta è il nome.
                    options: model.properties.map(\.id),
                    selected: model.propertyId,
                    optionLabel: { id in
                        let name = model.properties.first { $0.id == id }?.name ?? ""
                        return name.trimmed.isEmpty ? id : name
                    },
                    onSelect: { model.selectProperty($0) }
                )
                .disabled(model.isSaving)
            }
            Button(action: model.toggleCalendar) {
                Label(model.calendarVisible ? "Nascondi calendario" : "Mostra calendario",
                      systemImage: model.calendarVisible ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.appText)
        }
    }

    private var monthHeader: some View {
        let wholeMonth = PriceLogic.monthDates(model.month).isSubset(of: model.selection)
        return HStack(spacing: 4) {
            Button { model.shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: Dimens.iconSmall, weight: .semibold))
            }
            .buttonStyle(.appIcon)
            .accessibilityLabel("Mese precedente")
            Text(model.month.title).appStyle(.labelSmall).foregroundStyle(Theme.primary)
            Button { model.shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: Dimens.iconSmall, weight: .semibold))
            }
            .buttonStyle(.appIcon)
            .accessibilityLabel("Mese successivo")
            Spacer(minLength: 4)
            FilterChip(label: "Tutto il mese", selected: wholeMonth, action: model.toggleWholeMonth)
        }
        .disabled(model.isSaving)
    }

    // MARK: Prezzo a notte

    private var editBar: some View {
        let n = model.selection.count
        let canApply = n > 0 && !model.isSaving && model.ratesLoaded
        return VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            SectionTitle("PREZZO A NOTTE")
            Text(n == 0 ? "Nessuna data selezionata" : "\(n) \(n == 1 ? "notte selezionata" : "notti selezionate")")
                .appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
            AppTextField(label: "Prezzo a notte (€)", text: $model.priceText,
                         error: model.priceError ? "" : nil, keyboard: .decimalPad)
            FlowButtons {
                Button("Salva", action: model.save).buttonStyle(.appPrimary).disabled(!canApply)
                Button("Ripristina prezzo base", action: model.restoreBasePrice).buttonStyle(.appOutlined).disabled(!canApply)
                Button("Deseleziona", action: model.clearSelection).buttonStyle(.appText).disabled(n == 0)
            }
            if let error = model.error { feedback(error, isError: true) }
            if !model.ratesLoaded && model.propertyId != nil && !model.isLoading && model.error != nil {
                Text("Tariffe non caricate: non si può salvare.").appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
                Button("Riprova", action: model.retryRates).buttonStyle(.appOutlined)
            }
            if let message = model.message { feedback(message, isError: false) }
            if model.basePrice == nil && model.propertyId != nil {
                Text("Questa casa non ha ancora un prezzo base (scheda Sito): le date senza tariffa mostrano “—”.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: Extra per ospiti

    @ViewBuilder
    private var guestExtraSection: some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            SectionTitle("EXTRA PER OSPITI")
            if let max = model.maxGuests, max >= 2 {
                Text("Il prezzo base resta quello sopra. Per più ospiti puoi aggiungere un extra a notte (fisso tutto l'anno).")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                if !model.extraOpen {
                    Button("Aggiungi un extra per più ospiti", action: model.openExtra)
                        .buttonStyle(.appOutlined)
                        .disabled(model.propertyId == nil)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(2 ... max, id: \.self) { n in
                            FilterChip(
                                label: model.surcharges[n] != nil ? "\(n) ospiti •" : "\(n) ospiti",
                                selected: model.selectedGuests == n,
                                action: { model.selectGuests(n) }
                            )
                            .disabled(model.isSavingExtra)
                        }
                    }
                    AppTextField(
                        label: "Extra a notte per \(model.selectedGuests.map(String.init) ?? "—") ospiti (€)",
                        text: $model.extraText, error: model.extraError == nil ? nil : "", keyboard: .decimalPad
                    )
                    FlowButtons {
                        Button("Salva extra", action: model.saveExtra)
                            .buttonStyle(.appPrimary)
                            .disabled(model.selectedGuests == nil || model.isSavingExtra)
                        Button("Rimuovi extra", action: model.removeExtra)
                            .buttonStyle(.appOutlined)
                            .disabled(model.selectedGuests.map { model.surcharges[$0] == nil } ?? true || model.isSavingExtra)
                    }
                    if let error = model.extraError { feedback(error, isError: true) }
                    if let message = model.extraMessage { feedback(message, isError: false) }
                }
            } else {
                Text("Imposta gli ospiti massimi (almeno 2) nel modulo della casa, in Immobili, per aggiungere un extra.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: Promozioni

    private var promotionsSection: some View {
        let n = model.selection.count
        return VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            SectionTitle("PROMOZIONI")
            Text("Sul sito il prezzo normale appare barrato e quello scontato evidenziato, per le notti scelte.")
                .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            if model.promotions.isEmpty {
                Text(model.promosLoaded ? "Nessuna promozione attiva o futura." : "Promozioni non caricate.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
            }
            ForEach(model.promotions) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PriceLogic.formatPromoRange(p)).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).lineLimit(2)
                        Text(promoExample(p)).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.deletePromotion(p.id) } label: {
                        Image(systemName: "trash").font(.system(size: Dimens.iconSmall))
                    }
                    .buttonStyle(.appIcon)
                    .disabled(model.isSavingPromo)
                    .accessibilityLabel("Elimina promozione")
                }
            }
            Divider()
            Text("Nuova promozione sulle notti selezionate").appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
            HStack(spacing: 6) {
                FilterChip(label: "Sconto %", selected: model.promoType == discountPercentage) { model.promoType = discountPercentage }
                FilterChip(label: "Sconto € a notte", selected: model.promoType == discountFixed) { model.promoType = discountFixed }
            }
            AppTextField(
                label: model.promoType == discountPercentage ? "Percentuale (1-100)" : "Euro scontati a notte",
                text: $model.promoValueText, error: model.promoError == nil ? nil : "", keyboard: .decimalPad
            )
            Button(n == 0 ? "Seleziona le notti nel calendario" : "Crea per \(n) \(n == 1 ? "notte" : "notti")",
                   action: model.createPromotions)
                .buttonStyle(.appPrimary)
                .disabled(n == 0 || model.promoValueText.trimmed.isEmpty || model.isSavingPromo || !model.promosLoaded)
            if let error = model.promoError { feedback(error, isError: true) }
            if let message = model.promoMessage { feedback(message, isError: false) }
        }
    }

    private func promoExample(_ p: PromoEntry) -> String {
        guard let base = model.basePrice else { return PriceLogic.formatDiscount(p) }
        let after = PriceLogic.discountedPrice(base, p)
        return "\(PriceLogic.formatDiscount(p)) · €\(PriceLogic.formatPrice(base)) → €\(PriceLogic.formatPrice(after))"
    }

    private func feedback(_ text: String, isError: Bool) -> some View {
        Text(text).appStyle(.bodySmall).foregroundStyle(isError ? Theme.error : Theme.primary)
    }
}

// MARK: Griglia del mese

/// Griglia dei prezzi: un solo gesto. L'ancora è il giorno del primo contatto; se il dito si sposta è un trascinamento
/// (ancora → giorno corrente, sommato a ciò che era già selezionato), se si solleva senza muoversi è un tocco che
/// inverte il giorno.
private struct PriceGrid: View {
    let model: PriceEditorModel
    let reservations: [Reservation]

    @State private var gridWidth: CGFloat = 0
    @State private var anchor: LocalDay?
    @State private var base: Set<LocalDay> = []
    @State private var dragging = false

    private let gap: CGFloat = 4
    private let aspect: CGFloat = 1.25

    private var rows: [[Int?]] {
        monthGridRows(daysInMonth: model.month.lengthOfMonth, firstDayOfWeek: model.month.atDay(1).weekdayFromSunday)
    }

    var body: some View {
        let grid = rows
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(AgendaLogic.weekdayHeaders, id: \.self) { d in
                    Text(d).appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 300)
            VStack(spacing: gap) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, dayNum in
                            if let dayNum {
                                cell(model.month.atDay(dayNum), dayNum: dayNum)
                            } else {
                                Color.clear.aspectRatio(aspect, contentMode: .fit).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { gridWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in gridWidth = w }
            })
            .contentShape(Rectangle())
            .gesture(selectionGesture(rows: grid))
            Text("Trascina il dito sui giorni per selezionarli. Il punto indica una notte già prenotata. In verde il prezzo con promozione.")
                .appStyle(.bodySmall)
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.top, 2)
        }
    }

    private func dayAt(_ point: CGPoint, rows: [[Int?]]) -> LocalDay? {
        guard let cell = PriceLogic.gridCellAt(
            x: point.x, y: point.y, gridWidth: gridWidth, gap: gap, rowCount: rows.count, cellAspect: aspect
        ), let dayNum = rows[cell.row][cell.col] else { return nil }
        return model.month.atDay(dayNum)
    }

    private func selectionGesture(rows: [[Int?]]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if anchor == nil && !dragging {
                    anchor = dayAt(value.startLocation, rows: rows)
                    base = model.selection
                }
                if !dragging && hypot(value.translation.width, value.translation.height) > 8 { dragging = true }
                if dragging, let anchor, let day = dayAt(value.location, rows: rows) {
                    model.select(base.union(PriceLogic.dragRange(anchor, day)))
                }
            }
            .onEnded { _ in
                if !dragging, let anchor { model.toggleDay(anchor) }
                anchor = nil
                dragging = false
            }
    }

    private func cell(_ day: LocalDay, dayNum: Int) -> some View {
        let price = PriceLogic.priceForDay(day, rates: model.rates, basePrice: model.basePrice)
        let promo = PriceLogic.promoPriceForDay(day, price: price.amount, promos: model.promotions)
        let selected = model.selection.contains(day)
        let booked = model.propertyId.map { PriceLogic.isNightBooked(day, propertyId: $0, reservations: reservations) } ?? false
        let bg = selected ? Theme.primary : (price.isSeasonal ? Theme.primaryContainer.opacity(0.5) : Theme.surfaceContainerLow)
        let fg = selected ? Theme.onPrimary : Theme.onSurface
        let sub = selected ? Theme.onPrimary : ((promo != nil || price.isSeasonal) ? Theme.primary : Theme.onSurfaceVariant)
        let shown = PriceLogic.formatPrice(promo ?? price.amount)
        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text("\(dayNum)")
                    .font(.system(size: 11, weight: selected ? .bold : .regular))
                    .foregroundStyle(fg)
                Text(shown)
                    .font(.system(size: 8, weight: (price.isSeasonal || promo != nil) ? .semibold : .regular))
                    .foregroundStyle(sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if booked {
                Circle().fill(selected ? Theme.onPrimary : Theme.error).frame(width: 4, height: 4).padding(2)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(roundedShape(6).fill(bg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dayNum), \(shown == "—" ? "nessun prezzo" : "€ \(shown)")\(booked ? ", prenotata" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.toggleDay(day) }
    }
}

// MARK: Componenti locali

/// Occhiello verde di una sezione dell'editor.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).appStyle(.labelSmall).foregroundStyle(Theme.primary).accessibilityAddTraits(.isHeader)
    }
}

/// Pastiglia selezionabile (equivalente di `FilterChip`).
struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(label).appStyle(.labelLarge)
            }
            .foregroundStyle(selected ? Theme.onPrimaryContainer : Theme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(roundedShape(Radius.small).fill(selected ? Theme.primaryContainer : Color.clear))
            .overlay(roundedShape(Radius.small).strokeBorder(selected ? Color.clear : Theme.outline, lineWidth: 1))
            .contentShape(roundedShape(Radius.small))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Pulsanti che vanno a capo se non stanno su una riga (equivalente di `FlowRow`).
struct FlowButtons<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { FlowLayout(spacing: 8) { content() } }
}

/// Disposizione a righe che vanno a capo: gli elementi si affiancano finché c'è spazio.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
