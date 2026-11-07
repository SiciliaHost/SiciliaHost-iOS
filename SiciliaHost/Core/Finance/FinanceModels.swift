import Foundation

/// Soldi di UNA prenotazione, solo sul telefono del proprietario. La chiave è l'id della prenotazione sul server.
/// I netti non si salvano: si ricalcolano (`FinReservation.netOwner`).
struct ReservationMoney: Codable, Equatable, Sendable {
    var reservationId: String
    var propertyId: String
    var grossAmount: Double?
    /// Commissione reale trattenuta da Booking (€), dall'export Excel.
    var commissionAmount: Double?
    var bookedAt: Int64?
    var travelPurpose: String?
    var bookingDevice: String?
    var source: String = ReservationMoney.manual

    static let manual = "MANUAL"   // scritto a mano: mai sovrascritto da sito o Excel
    static let excel = "EXCEL"
    static let site = "SITE"       // prenotazione diretta del sito, da getSiteBookingAmounts

    init(reservationId: String, propertyId: String, grossAmount: Double? = nil, commissionAmount: Double? = nil,
         bookedAt: Int64? = nil, travelPurpose: String? = nil, bookingDevice: String? = nil, source: String = ReservationMoney.manual) {
        self.reservationId = reservationId; self.propertyId = propertyId; self.grossAmount = grossAmount
        self.commissionAmount = commissionAmount; self.bookedAt = bookedAt; self.travelPurpose = travelPurpose
        self.bookingDevice = bookingDevice; self.source = source
    }
}

extension ReservationMoney {
    /// Decodifica tollerante (come `FinanceData`): una chiave mancante (es. `source` in un file scritto da una versione
    /// precedente) prende il default invece di rendere illeggibile l'intero file, che finirebbe in `.bad`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            reservationId: c.value(.reservationId, ""),
            propertyId: c.value(.propertyId, ""),
            grossAmount: c.optional(.grossAmount),
            commissionAmount: c.optional(.commissionAmount),
            bookedAt: c.optional(.bookedAt),
            travelPurpose: c.optional(.travelPurpose),
            bookingDevice: c.optional(.bookingDevice),
            source: c.value(.source, ReservationMoney.manual)
        )
    }
}

/// Tutto ciò che sta nel file del telefono.
struct FinanceData: Codable, Equatable, Sendable {
    var version = 1
    var expenses: [Expense] = []
    var recurring: [RecurringExpense] = []
    var money: [ReservationMoney] = []
    var contacts: [Contact] = []

    init() {}

    // Decodifica tollerante: chiavi mancanti = default, chiavi sconosciute ignorate (compatibilità in avanti).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        recurring = try c.decodeIfPresent([RecurringExpense].self, forKey: .recurring) ?? []
        money = try c.decodeIfPresent([ReservationMoney].self, forKey: .money) ?? []
        contacts = try c.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
    }

    func moneyById() -> [String: ReservationMoney] {
        Dictionary(money.map { ($0.reservationId, $0) }, uniquingKeysWith: { _, last in last })
    }
}

/// Una prenotazione del server con i soldi del telefono: è ciò che leggono Finanze e statistiche.
struct FinReservation: Identifiable, Equatable, Sendable {
    var id: String
    var propertyId: String
    var guestName: String?
    var checkIn: Int64
    var checkOut: Int64
    var platform: String
    var adults = 0
    var children = 0
    var guestCountry: String?
    var grossAmount: Double?
    var commissionAmount: Double?
    var bookedAt: Int64?
    var travelPurpose: String?
    var bookingDevice: String?

    /// Netto del proprietario, ricalcolato (mai salvato): niente valori vecchi dopo un cambio di formula.
    var netOwner: Double? {
        grossAmount.map { FinancialCalculator.netOwner(gross: $0, platform: platform, realCommission: commissionAmount) }
    }
}

func joinMoney(_ reservations: [Reservation], _ money: [String: ReservationMoney]) -> [FinReservation] {
    reservations.map { r in
        let m = money[r.id]
        return FinReservation(
            id: r.id, propertyId: r.propertyId, guestName: r.guestName, checkIn: r.checkIn, checkOut: r.checkOut,
            platform: r.platform, adults: r.adults, children: r.children, guestCountry: r.guestCountry,
            grossAmount: m?.grossAmount, commissionAmount: m?.commissionAmount, bookedAt: m?.bookedAt,
            travelPurpose: m?.travelPurpose, bookingDevice: m?.bookingDevice
        )
    }
}
