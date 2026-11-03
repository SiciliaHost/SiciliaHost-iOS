import Foundation
import Observation

/// Stato dell'editor prezzi (`PriceEditorViewModel.kt`): casa, tariffe stagionali, selezione di notti, extra per ospiti
/// e promozioni automatiche. Tutto passa dalle callable del sito (`PriceService`): le regole vietano al client di
/// scrivere `seasonalRates`, `guestSurcharges` e `promotions`.
@MainActor
@Observable
final class PriceEditorModel {
    private(set) var properties: [PropertySiteContent] = []
    private(set) var propertyId: String?
    private(set) var rates: [SeasonalRateEntry] = []
    private(set) var month = YearMonth(Date())
    private(set) var selection: Set<LocalDay> = []
    var priceText = "" {
        didSet { if priceError { priceError = false; error = nil } }
    }
    private(set) var priceError = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// true solo se le tariffe della casa corrente sono state lette con successo.
    private(set) var ratesLoaded = false
    private(set) var error: String?
    private(set) var message: String?

    var calendarVisible = true

    // Extra per ospiti (fissi per casa).
    private(set) var surcharges: [Int: Double] = [:]
    private(set) var extraOpen = false
    private(set) var selectedGuests: Int?
    var extraText = ""
    private(set) var extraError: String?
    private(set) var extraMessage: String?
    private(set) var isSavingExtra = false
    private var maxGuestsById: [String: Int?] = [:]
    var maxGuests: Int? { propertyId.flatMap { maxGuestsById[$0] ?? nil } }

    // Promozioni automatiche.
    private(set) var promotions: [PromoEntry] = []
    private(set) var promosLoaded = false
    var promoType = discountPercentage
    var promoValueText = ""
    private(set) var promoError: String?
    private(set) var promoMessage: String?
    private(set) var isSavingPromo = false

    var basePrice: Double? { properties.first { $0.id == propertyId }?.basePricePerNight }

    private let prices = PriceService()
    private let siteContent = SiteContentService()
    private var loadTask: Task<Void, Never>?
    private var loadSeq = 0

    /// Parte da zero a ogni apertura della schermata.
    func load(initialPropertyId: String? = nil) {
        priceText = ""
        calendarVisible = true
        if let initialPropertyId { propertyId = initialPropertyId }
        startLoad(loadProperties: true, requested: nil, clearSelection: true)
    }

    func selectProperty(_ id: String) {
        if isSaving { return }
        startLoad(loadProperties: false, requested: id, clearSelection: true)
    }

    /// "Riprova" dopo un caricamento delle tariffe fallito: tiene la selezione.
    func retryRates() {
        guard let id = propertyId, !isSaving else { return }
        startLoad(loadProperties: false, requested: id, clearSelection: false)
    }

    // Ogni richiesta ha un numero: una risposta arrivata in ritardo (numero vecchio) non tocca lo stato.
    private func startLoad(loadProperties: Bool, requested: String?, clearSelection: Bool) {
        loadSeq += 1
        let token = loadSeq
        loadTask?.cancel()
        if clearSelection { selection = [] }
        error = nil
        priceError = false
        message = nil
        extraError = nil
        extraMessage = nil
        promoError = nil
        promoMessage = nil
        if let requested {
            propertyId = requested
            rates = []
            ratesLoaded = false
            promotions = []
            promosLoaded = false
            applyPropertyExtras(requested)
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            defer { if token == loadSeq { isLoading = false } }
            do {
                var id = requested
                if loadProperties {
                    let scope = try await AccessSession.shared.scope()
                    let priceScope = scope.isSuperAdmin ? scope.listingProperties : scope.priceProperties
                    let list = try await siteContent.getProperties(priceScope.map(\.id))
                        .filter { canEditCalendarPrices($0.status) }
                        .sorted { $0.name < $1.name }
                    guard token == loadSeq else { return }
                    properties = list
                    maxGuestsById = Dictionary(priceScope.map { ($0.id, $0.maxGuests) }, uniquingKeysWith: { first, _ in first })
                    id = propertyId.flatMap { current in list.contains { $0.id == current } ? current : nil } ?? list.first?.id
                    propertyId = id
                    if let id { applyPropertyExtras(id) }
                    rates = []
                    ratesLoaded = false
                    promotions = []
                    promosLoaded = false
                }
                guard let id else { return }
                let loaded = try await prices.getSeasonalRates(propertyId: id)
                guard token == loadSeq else { return }
                rates = loaded
                ratesLoaded = true
                // Le promozioni hanno un errore proprio: se falliscono il prezzo a notte resta utilizzabile.
                do {
                    let promos = try await prices.listPromotions(propertyId: id)
                    guard token == loadSeq else { return }
                    promotions = promos
                    promosLoaded = true
                } catch {
                    if token == loadSeq && !Task.isCancelled {
                        promosLoaded = false
                        promotions = []
                        promoError = describeSiteError(error)
                    }
                }
            } catch {
                if token == loadSeq && !Task.isCancelled {
                    rates = []
                    ratesLoaded = false
                    promosLoaded = false
                    self.error = describeSiteError(error)
                }
            }
        }
    }

    func toggleCalendar() { calendarVisible.toggle() }

    /// Legge gli extra della casa dalla lista già caricata e prepara la sezione "Extra per ospiti".
    private func applyPropertyExtras(_ id: String) {
        surcharges = PriceLogic.toSurchargeMap(properties.first { $0.id == id }?.guestSurcharges)
        extraOpen = !surcharges.isEmpty
        selectedGuests = surcharges.keys.min() ?? ((maxGuests ?? 0) >= 2 ? 2 : nil)
        let text = selectedGuests.flatMap { surcharges[$0] }.map { PriceLogic.formatPrice($0) }
        extraText = (text == nil || text == "—") ? "" : text!
    }

    func openExtra() { extraOpen = true }

    func selectGuests(_ n: Int) {
        selectedGuests = n
        extraText = surcharges[n].map { PriceLogic.formatPrice($0) } ?? ""
        extraError = nil
        extraMessage = nil
    }

    func saveExtra() {
        guard let id = propertyId, let n = selectedGuests else { return }
        guard let value = PriceLogic.parseExtra(extraText) else {
            extraError = "Inserisci un importo valido (es. 10 o 7,50)"
            return
        }
        writeExtras(id, PriceLogic.mergeSurcharges(surcharges, guests: n, value: value),
                    value == 0 ? "Extra rimosso per \(n) ospiti" : "Extra salvato per \(n) ospiti")
    }

    func removeExtra() {
        guard let id = propertyId, let n = selectedGuests else { return }
        var next = surcharges
        next.removeValue(forKey: n)
        writeExtras(id, next, "Extra rimosso per \(n) ospiti")
    }

    private func writeExtras(_ id: String, _ next: [Int: Double], _ doneLabel: String) {
        if isSavingExtra { return }
        Task {
            isSavingExtra = true
            extraError = nil
            extraMessage = nil
            defer { isSavingExtra = false }
            do {
                let saved = try await prices.setGuestSurcharges(propertyId: id, surcharges: next)
                // Tiene allineata la lista caricata: tornando su questa casa gli extra salvati ci sono ancora.
                properties = properties.map { p in
                    guard p.id == id else { return p }
                    var copy = p
                    copy.guestSurcharges = PriceLogic.surchargesToRaw(saved)
                    return copy
                }
                if propertyId == id {
                    surcharges = saved
                    extraMessage = doneLabel
                    extraText = selectedGuests.flatMap { saved[$0] }.map { PriceLogic.formatPrice($0) } ?? ""
                }
            } catch {
                if propertyId == id { extraError = describeSiteError(error) }
            }
        }
    }

    /// Crea una promozione per ogni intervallo continuo di notti selezionate.
    func createPromotions() {
        guard let id = propertyId else { return }
        guard let value = PriceLogic.parsePromoValue(discountType: promoType, promoValueText) else {
            promoError = promoType == discountPercentage ? "Inserisci una percentuale tra 1 e 100" : "Inserisci un importo valido in euro"
            return
        }
        let dates = selection
        if dates.isEmpty || isSavingPromo { return }
        Task {
            isSavingPromo = true
            promoError = nil
            promoMessage = nil
            defer { isSavingPromo = false }
            do {
                let created = try await prices.createPromotions(
                    propertyId: id, ranges: PriceLogic.groupIntoRanges(dates), discountType: promoType, discountValue: value
                )
                if propertyId == id {
                    promotions = (promotions + created).sorted { $0.startDate < $1.startDate }
                    promoMessage = "Promozione creata (\(created.count) \(created.count == 1 ? "periodo" : "periodi"))"
                    selection = []
                    promoValueText = ""
                }
            } catch {
                if propertyId == id { promoError = describeSiteError(error) }
            }
        }
    }

    func deletePromotion(_ promoId: String) {
        guard let id = propertyId, !isSavingPromo else { return }
        Task {
            isSavingPromo = true
            promoError = nil
            promoMessage = nil
            defer { isSavingPromo = false }
            do {
                try await prices.deletePromotion(id: promoId)
                if propertyId == id {
                    promotions.removeAll { $0.id == promoId }
                    promoMessage = "Promozione eliminata"
                }
            } catch {
                if propertyId == id { promoError = describeSiteError(error) }
            }
        }
    }

    func shiftMonth(_ delta: Int) { if !isSaving { month = month.plusMonths(delta) } }
    func select(_ dates: Set<LocalDay>) { if isSaving { return }; selection = dates; message = nil }
    func toggleDay(_ day: LocalDay) {
        if isSaving { return }
        if selection.contains(day) { selection.remove(day) } else { selection.insert(day) }
        message = nil
    }
    func toggleWholeMonth() { if isSaving { return }; selection = PriceLogic.toggleMonth(selection, month); message = nil }
    func clearSelection() { selection = [] }

    func save() {
        guard let price = PriceLogic.parsePrice(priceText) else {
            error = "Inserisci un prezzo valido (es. 120 o 99,50)"
            priceError = true
            return
        }
        apply(price, "Prezzo salvato")
    }

    func restoreBasePrice() { apply(nil, "Prezzo base ripristinato") }

    private func apply(_ price: Double?, _ doneLabel: String) {
        guard let id = propertyId else { return }
        let dates = selection
        if dates.isEmpty || isSaving || !ratesLoaded { return }
        Task {
            isSaving = true
            error = nil
            defer { isSaving = false }
            do {
                let updated = try await prices.setSeasonalRates(
                    propertyId: id, ranges: PriceLogic.groupIntoRanges(dates), pricePerNight: price
                )
                if propertyId == id {
                    rates = updated
                    message = "\(doneLabel) per \(dates.count) \(dates.count == 1 ? "notte" : "notti")"
                    selection = []
                }
            } catch {
                // Selezione e prezzo restano: si può riprovare senza rifare tutto.
                if propertyId == id { self.error = describeSiteError(error) }
            }
        }
    }
}
