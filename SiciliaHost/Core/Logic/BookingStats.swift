import Foundation

/// Statistiche delle prenotazioni per le Finanze. Logica pura: niente Firestore, date in UTC come le prenotazioni
/// (mezzanotti UTC). I dati dell'export Booking (anticipo, paese, motivo, dispositivo, commissione reale) esistono
/// solo per le prenotazioni importate dall'Excel: le medie relative usano solo quelle che li hanno, e dicono su
/// quante si basano.
enum BookingStats {
    struct Channel: Equatable {
        let platform: String
        let count: Int
        let nights: Int
        let gross: Double
        let commission: Double
    }

    struct MonthOccupancy: Equatable {
        let label: String
        let occupancy: Double
    }

    struct Summary {
        let reservationCount: Int
        let nightsSold: Int
        let availableNights: Int
        let gross: Double
        /// Prezzo medio a notte (ADR) sulle prenotazioni con importo.
        let adr: Double?
        /// Ricavo per notte disponibile (RevPAR).
        let revPar: Double?
        let avgNights: Double?
        let avgGuests: Double?
        let avgAdults: Double?
        let avgChildren: Double?
        let shareWithChildren: Double?
        /// Su quante prenotazioni ci sono i dati degli ospiti.
        let guestSample: Int
        let avgLeadDays: Double?
        let leadSample: Int
        let channels: [Channel]
        let commissionsPaid: Double
        /// Commissione Booking reale media (% sul lordo) dall'export, se c'è.
        let bookingRealCommissionRate: Double?
        let countries: [LabelCount]
        let purposes: [LabelCount]
        let devices: [LabelCount]
        /// Arrivi per giorno della settimana, lunedì = 0.
        let checkInWeekdays: [Int]
        /// Soggiorni per durata: "1 notte", "2–3 notti", "4–6 notti", "7+ notti".
        let stayLengths: [LabelCount]
        let monthlyOccupancy: [MonthOccupancy]
        /// Notti libere isolate (buchi di 1–2 notti tra due prenotazioni) da oggi in poi.
        let orphanNights: Int
        let cancellationRate: Double?

        var occupancy: Double? { availableNights > 0 ? Double(nightsSold) / Double(availableNights) : nil }
    }

    static func nights(_ res: Reservation) -> Int { max(0, Int((res.checkOut - res.checkIn) / millisPerDay)) }

    /// Statistiche delle `reservations` (già filtrate per casa) nel `range` (nil = tutto), su `houseCount` case.
    /// Una prenotazione conta nel periodo se arriva dentro il periodo; le notti vendute contano solo la parte che
    /// cade nel periodo (occupazione corretta ai bordi).
    static func compute(
        reservations: [Reservation], range: Range<Int64>?, houseCount: Int, now: Int64,
        importCounts: [BookingImportCounts] = []
    ) -> Summary {
        let valid = reservations.filter { $0.checkOut > $0.checkIn }
        let start = range?.lowerBound ?? valid.map(\.checkIn).min() ?? now
        let end = range?.upperBound ?? max(valid.map(\.checkOut).max() ?? now, now)
        let inPeriod = valid.filter { $0.checkIn >= start && $0.checkIn < end }

        let nightsSold = valid.reduce(0) { $0 + overlapNights($1.checkIn, $1.checkOut, start, end) }
        let availableNights = max(Int((end - start) / millisPerDay), 0) * max(houseCount, 0)

        let withGross = inPeriod.filter { $0.grossAmount != nil }
        let gross = withGross.reduce(0) { $0 + ($1.grossAmount ?? 0) }
        let grossNights = withGross.reduce(0) { $0 + nights($1) }

        let withGuests = inPeriod.filter { $0.adults + $0.children > 0 }
        let leads = inPeriod.compactMap { r in r.bookedAt.map { max(Double(r.checkIn - $0) / Double(millisPerDay), 0) } }

        // Canali per piattaforma, nell'ordine di comparsa, poi per notti decrescenti (stabile).
        var platformOrder: [String] = []
        var byPlatform: [String: [Reservation]] = [:]
        for r in inPeriod {
            if byPlatform[r.platform] == nil { platformOrder.append(r.platform) }
            byPlatform[r.platform, default: []].append(r)
        }
        let channels = stableSortedDescending(platformOrder.map { platform -> Channel in
            let list = byPlatform[platform]!
            return Channel(
                platform: platform, count: list.count, nights: list.reduce(0) { $0 + nights($1) },
                gross: list.reduce(0) { $0 + ($1.grossAmount ?? 0) }, commission: list.reduce(0) { $0 + commissionOf($1) }
            )
        }, by: \.nights)

        let bookingWithReal = inPeriod.filter { $0.platform == "BOOKING" && $0.commissionAmount != nil && ($0.grossAmount ?? 0) > 0 }
        let realRate: Double? = bookingWithReal.isEmpty ? nil
            : bookingWithReal.reduce(0) { $0 + ($1.commissionAmount ?? 0) } / bookingWithReal.reduce(0) { $0 + ($1.grossAmount ?? 0) }

        var weekdays = [Int](repeating: 0, count: 7)
        for r in inPeriod {
            // Calendar.weekday: domenica = 1 (come Java), quindi lunedì → 0.
            let weekday = utcCalendar.component(.weekday, from: dateFromMillis(r.checkIn))
            weekdays[(weekday + 5) % 7] += 1
        }

        var bucketCounts = ["1 notte": 0, "2–3 notti": 0, "4–6 notti": 0, "7+ notti": 0]
        for r in inPeriod {
            let n = nights(r)
            let key: String?
            switch n {
            case 1: key = "1 notte"
            case 2, 3: key = "2–3 notti"
            case 4 ... 6: key = "4–6 notti"
            default: key = n >= 7 ? "7+ notti" : nil
            }
            if let key { bucketCounts[key]! += 1 }
        }
        let bucketOrder = ["1 notte", "2–3 notti", "4–6 notti", "7+ notti"]

        let confirmed = importCounts.reduce(0) { $0 + $1.confirmed }
        let cancelled = importCounts.reduce(0) { $0 + $1.cancelled }

        func average(_ values: [Int]) -> Double? {
            values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        }

        return Summary(
            reservationCount: inPeriod.count,
            nightsSold: nightsSold,
            availableNights: availableNights,
            gross: gross,
            adr: grossNights > 0 ? gross / Double(grossNights) : nil,
            revPar: availableNights > 0 && gross > 0 ? gross / Double(availableNights) : nil,
            avgNights: average(inPeriod.map { nights($0) }),
            avgGuests: average(withGuests.map { $0.adults + $0.children }),
            avgAdults: average(withGuests.map(\.adults)),
            avgChildren: average(withGuests.map(\.children)),
            shareWithChildren: withGuests.isEmpty ? nil : Double(withGuests.filter { $0.children > 0 }.count) / Double(withGuests.count),
            guestSample: withGuests.count,
            avgLeadDays: leads.isEmpty ? nil : leads.reduce(0, +) / Double(leads.count),
            leadSample: leads.count,
            channels: channels,
            commissionsPaid: channels.reduce(0) { $0 + $1.commission },
            bookingRealCommissionRate: realRate,
            countries: topCounts(inPeriod.compactMap { $0.guestCountry }.filter { !$0.trimmed.isEmpty }),
            purposes: topCounts(inPeriod.compactMap { $0.travelPurpose }.filter { !$0.trimmed.isEmpty }),
            devices: topCounts(inPeriod.compactMap { $0.bookingDevice }.filter { !$0.trimmed.isEmpty }),
            checkInWeekdays: weekdays,
            stayLengths: bucketOrder.map { LabelCount(label: $0, count: bucketCounts[$0]!) },
            monthlyOccupancy: monthlyOccupancy(valid, start: start, end: end, houseCount: houseCount),
            orphanNights: orphanNights(valid, now: now),
            cancellationRate: confirmed + cancelled > 0 ? Double(cancelled) / Double(confirmed + cancelled) : nil
        )
    }

    /// Commissione della piattaforma: quella reale dell'export se c'è, altrimenti la tariffa dell'app.
    static func commissionOf(_ r: Reservation) -> Double {
        if let real = r.commissionAmount { return real }
        guard let g = r.grossAmount else { return 0 }
        return g - FinancialCalculator.calculate(grossAmount: g, platform: r.platform, isManagedOnCommission: false).netAmountOwner
    }

    private static func overlapNights(_ checkIn: Int64, _ checkOut: Int64, _ start: Int64, _ end: Int64) -> Int {
        let from = max(checkIn, start)
        let to = min(checkOut, end)
        return to > from ? Int((to - from) / millisPerDay) : 0
    }

    /// Occupazione mese per mese nel periodo (al massimo gli ultimi 12 mesi del periodo).
    private static func monthlyOccupancy(_ valid: [Reservation], start: Int64, end: Int64, houseCount: Int) -> [MonthOccupancy] {
        if houseCount <= 0 || end <= start { return [] }
        var monthStart = startOfMonthUTC(start)
        var months: [MonthOccupancy] = []
        while monthStart < end {
            let mStart = max(monthStart, start)
            let name = shortMonthYearLabel(monthStart)
            monthStart = addMonthsUTC(monthStart, 1)
            let mEnd = min(monthStart, end)
            let days = Int((mEnd - mStart) / millisPerDay)
            if days <= 0 { continue }
            let sold = valid.reduce(0) { $0 + overlapNights($1.checkIn, $1.checkOut, mStart, mEnd) }
            months.append(MonthOccupancy(label: name, occupancy: Double(sold) / Double(days * houseCount)))
        }
        return Array(months.suffix(12))
    }

    /// Buchi di 1–2 notti tra due prenotazioni della stessa casa, che iniziano da oggi in poi.
    static func orphanNights(_ reservations: [Reservation], now: Int64) -> Int {
        Dictionary(grouping: reservations, by: \.propertyId).values.reduce(0) { total, list in
            let sorted = list.sorted { $0.checkIn < $1.checkIn }
            var sum = 0
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let gap = Int((b.checkIn - a.checkOut) / millisPerDay)
                if (1 ... 2).contains(gap) && a.checkOut >= now - millisPerDay { sum += gap }
            }
            return total + sum
        }
    }
}
