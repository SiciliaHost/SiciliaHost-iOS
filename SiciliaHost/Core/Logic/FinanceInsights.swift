import Foundation

/// Suggerimenti "Da migliorare" delle Finanze: regole semplici sui numeri di `BookingStats` e delle spese. Ogni
/// regola scatta solo quando il dato la giustifica (e con abbastanza prenotazioni). Ordinati dal più importante.
enum FinanceInsights {
    struct Insight: Equatable {
        let title: String
        let text: String
        let priority: Int
    }

    /// Lingue in cui il sito SiciliaHost è tradotto.
    static let siteLanguages: Set<String> = ["it", "en", "fr", "pl"]

    // Paese del prenotante → lingua in cui leggerebbe l'annuncio (solo i casi chiari).
    private static let countryLanguage: [String: String] = [
        "it": "it", "de": "de", "at": "de", "ch": "de", "fr": "fr", "be": "fr", "pl": "pl",
        "gb": "en", "us": "en", "ie": "en", "ca": "en", "au": "en", "es": "es", "nl": "nl",
        "pt": "pt", "br": "pt", "cz": "cs", "sk": "sk", "ro": "ro",
    ]

    private static let minSample = 5

    static func compute(
        stats: BookingStats.Summary,
        expensesByCategory: [ExpenseCategory: Double],
        netRevenue: Double,
        upcomingMonths: [BookingStats.MonthOccupancy] = []
    ) -> [Insight] {
        var out: [Insight] = []
        let enough = stats.reservationCount >= minSample

        // Commissioni delle piattaforme: quanto costa non avere prenotazioni dirette.
        if stats.commissionsPaid >= 100 {
            let directNights = stats.channels.first { $0.platform == "MANUAL" }?.nights
            let directShare = directNights.map { Double($0) / Double(max(stats.nightsSold, 1)) } ?? 0.0
            out.append(Insight(
                title: "Commissioni: \(euro(stats.commissionsPaid))",
                text: "Nel periodo Airbnb e Booking hanno trattenuto \(euro(stats.commissionsPaid)). "
                    + "Le prenotazioni dirette dal sito SiciliaHost (oggi \(pct(directShare)) delle notti) non pagano commissioni: "
                    + "invita gli ospiti che tornano a prenotare lì.",
                priority: 90
            ))
        }

        // Mesi in arrivo poco occupati.
        let weak = upcomingMonths.filter { $0.occupancy < 0.4 }
        if !weak.isEmpty {
            out.append(Insight(
                title: "Mesi da riempire",
                text: "\(weak.map { "\($0.label) (\(pct($0.occupancy)))" }.joined(separator: ", ")): occupazione sotto il 40%. "
                    + "Una promozione su quelle date o un prezzo più basso nei giorni feriali può aiutare.",
                priority: 85
            ))
        }

        if stats.orphanNights > 0 {
            out.append(Insight(
                title: "\(stats.orphanNights) notti isolate",
                text: "Ci sono \(stats.orphanNights) notti libere chiuse tra due prenotazioni: difficilmente si vendono da sole. "
                    + "Uno sconto su quelle notti o un soggiorno minimo più basso può riempirle.",
                priority: 80
            ))
        }

        if let rate = stats.cancellationRate, rate > 0.15 {
            out.append(Insight(
                title: "Cancellazioni al \(pct(rate))",
                text: "Su Booking una prenotazione su \(kotlinRound(1 / rate)) viene cancellata. "
                    + "Valuta una politica di cancellazione più rigida o una tariffa non rimborsabile scontata.",
                priority: 75
            ))
        }

        if enough {
            let short = stats.stayLengths.first { $0.label == "1 notte" }?.count ?? 0
            let shortShare = Double(short) / Double(stats.reservationCount)
            if shortShare >= 0.25 {
                out.append(Insight(
                    title: "Molti soggiorni di una notte",
                    text: "\(pct(shortShare)) delle prenotazioni è di una sola notte: ogni cambio costa pulizie e biancheria. "
                        + "Un minimo di 2 notti nei fine settimana o un supplemento pulizie le rende più convenienti.",
                    priority: 70
                ))
            }
        }

        if let lead = stats.avgLeadDays, stats.leadSample >= minSample {
            if lead < 14 {
                out.append(Insight(
                    title: "Prenotano all'ultimo",
                    text: "In media gli ospiti prenotano \(kotlinRound(lead)) giorni prima. Tieni i prezzi alti fino a pochi giorni "
                        + "dall'arrivo e abbassali solo se la data resta libera.",
                    priority: 55
                ))
            } else if lead > 60 {
                out.append(Insight(
                    title: "Prenotano con largo anticipo",
                    text: "In media gli ospiti prenotano \(kotlinRound(lead)) giorni prima: le date si riempiono presto. "
                        + "Puoi alzare i prezzi dei periodi più richiesti già mesi prima.",
                    priority: 55
                ))
            }
        }

        // Paese prevalente che non legge l'annuncio nella sua lingua.
        let countryTotal = stats.countries.reduce(0) { $0 + $1.count }
        if countryTotal >= minSample {
            var byLanguage: [String: Int] = [:]
            var languageOrder: [String] = []
            for c in stats.countries {
                guard let lang = countryLanguage[c.label] else { continue }
                if byLanguage[lang] == nil { languageOrder.append(lang) }
                byLanguage[lang, default: 0] += c.count
            }
            let candidates = languageOrder.filter { !siteLanguages.contains($0) }
            // maxByOrNull: a parità vince il primo incontrato.
            var best: (lang: String, n: Int)?
            for lang in candidates where best == nil || byLanguage[lang]! > best!.n { best = (lang, byLanguage[lang]!) }
            if let (lang, n) = best {
                let share = Double(n) / Double(countryTotal)
                if share >= 0.2 {
                    out.append(Insight(
                        title: "Ospiti di lingua \(languageName(lang))",
                        text: "\(pct(share)) degli ospiti parla \(languageName(lang)), ma il sito non è tradotto in questa lingua: "
                            + "una descrizione anche su Booking e Airbnb in \(languageName(lang)) può convertire di più.",
                        priority: 50
                    ))
                }
            }
        }

        // Una categoria di spesa che pesa troppo.
        let totalExpenses = expensesByCategory.values.reduce(0, +)
        if totalExpenses > 0 {
            // Ordine deterministico (le categorie nell'ordine dichiarato): a parità vince la prima.
            var top: (cat: ExpenseCategory, amount: Double)?
            for cat in ExpenseCategory.allCases {
                if let amount = expensesByCategory[cat], top == nil || amount > top!.amount { top = (cat, amount) }
            }
            if let (cat, amount) = top {
                let share = amount / totalExpenses
                if share > 0.35 && expensesByCategory.count > 1 {
                    out.append(Insight(
                        title: "\(cat.label): \(pct(share)) delle spese",
                        text: "È la voce che pesa di più (\(euro(amount))). Confronta fornitori o tariffe: è dove un risparmio si sente subito.",
                        priority: 45
                    ))
                }
            }
            if netRevenue > 0 && totalExpenses / netRevenue > 0.5 {
                out.append(Insight(
                    title: "Spese alte rispetto agli incassi",
                    text: "Le spese sono il \(pct(totalExpenses / netRevenue)) delle entrate nette del periodo.",
                    priority: 60
                ))
            }
        }

        if let real = stats.bookingRealCommissionRate, abs(real - 0.238) > 0.02 {
            out.append(Insight(
                title: "Commissione Booking reale: \(pct(real))",
                text: "Dal file di Booking la commissione effettiva è \(pct(real)), mentre i netti dell'app usano il 23,8%: "
                    + "i netti delle prenotazioni Booking possono essere diversi da quelli reali.",
                priority: 40
            ))
        }

        return stableSortedDescending(out, by: \.priority)
    }

    /// "€1.234": arrotondato all'euro, punto come separatore delle migliaia (come `%,.0f` con Locale.ITALY).
    static func euro(_ value: Double) -> String {
        let rounded = Int(value.rounded(.toNearestOrAwayFromZero))
        let digits = String(abs(rounded))
        var grouped = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        return "€" + (rounded < 0 ? "-" : "") + String(grouped.reversed())
    }

    static func pct(_ value: Double) -> String { "\(kotlinRound(value * 100))%" }

    static func languageName(_ code: String) -> String {
        let name = Locale(identifier: "it").localizedString(forLanguageCode: code) ?? ""
        return name.trimmed.isEmpty ? code : name
    }

    /// `roundToInt()` di Kotlin: arrotonda i .5 verso +infinito.
    private static func kotlinRound(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }
}
