import Foundation

/// Parte pura della sincronizzazione dei calendari iCal (Airbnb/Booking): lettura del feed e piano di cosa importare
/// e cosa cancellare. Il lavoro in sfondo (download, scrittura su Firestore, pianificazione) è in F10.
enum ICalSync {
    struct ParsedEvent: Equatable {
        let uid: String
        let summary: String?
        let checkIn: Int64
        let checkOut: Int64
    }

    struct Plan {
        let toUpsert: [Reservation]
        let toDelete: [Reservation]
        /// Eventi Booking che sono solo l'eco di prenotazioni di altre piattaforme (non importati).
        var echoes = 0
    }

    // Summary usato dalle piattaforme per le date bloccate a causa di una prenotazione arrivata da un'altra
    // piattaforma: non è una prenotazione reale. Si applica solo ad AIRBNB: Airbnb distingue "Reserved" da
    // "Airbnb (Not available)", Booking no (vedi `buildSyncPlan`).
    private static let blockedSummaryPatterns = ["closed", "not available"]

    private static func isBlockedEvent(_ summary: String?) -> Bool {
        guard let s = summary?.lowercased() else { return false }
        return blockedSummaryPatterns.contains { s.contains($0) }
    }

    /// Un feed valido inizia con BEGIN:VCALENDAR. Una risposta diversa (URL morto, pagina di errore HTML) non deve
    /// mai essere letta come "calendario vuoto", altrimenti ogni prenotazione nota verrebbe cancellata.
    static func isValidFeed(_ text: String) -> Bool { text.contains("BEGIN:VCALENDAR") }

    /// "20260801" → millisecondi UTC; nil se non sono 8 cifre di una data valida.
    private static func parseDay(_ text: String) -> Int64? {
        let digits = String(text.prefix(8))
        guard digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)), let d = Int(digits.suffix(2)),
              (1 ... 12).contains(m), (1 ... 31).contains(d) else { return nil }
        return utcMillis(year: y, month: m, day: d)
    }

    /// Parsing puro di ogni VEVENT del feed, senza filtri di piattaforma: quella decisione spetta a `buildSyncPlan`.
    static func parseEvents(_ icalText: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        var inEvent = false
        var uid: String?
        var summary: String?
        var dtStart: Int64 = 0
        var dtEnd: Int64 = 0

        for raw in icalText.components(separatedBy: .newlines) {
            let l = raw.trimmed
            if l == "BEGIN:VEVENT" {
                inEvent = true
                uid = nil; summary = nil; dtStart = 0; dtEnd = 0
                continue
            }
            if l == "END:VEVENT" && inEvent {
                inEvent = false
                if let uid { events.append(ParsedEvent(uid: uid, summary: summary, checkIn: dtStart, checkOut: dtEnd)) }
                continue
            }
            guard inEvent else { continue }
            if l.hasPrefix("UID:") {
                uid = String(l.dropFirst("UID:".count))
            } else if l.hasPrefix("SUMMARY:") {
                summary = String(l.dropFirst("SUMMARY:".count))
            } else if l.hasPrefix("DESCRIPTION:") && (summary ?? "").isEmpty {
                summary = String(l.dropFirst("DESCRIPTION:".count))
            } else if l.hasPrefix("DTSTART") {
                // Dopo l'ultimo ':' (es. `DTSTART;VALUE=DATE:20260801`); un valore non valido lascia 0.
                if let day = parseDay(l.components(separatedBy: ":").last ?? "") { dtStart = day }
            } else if l.hasPrefix("DTEND") {
                if let day = parseDay(l.components(separatedBy: ":").last ?? "") { dtEnd = day }
            }
        }
        return events
    }

    private static let rome: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    /// Giorno di calendario a Roma (giorni dal 1970). I documenti iCal sono a mezzanotte UTC, quelli scritti a mano a
    /// mezzanotte di Roma: confrontando i millisecondi non coinciderebbero mai.
    static func romeDay(_ epochMs: Int64) -> Int64 {
        let c = rome.dateComponents([.year, .month, .day], from: dateFromMillis(epochMs))
        return utcMillis(year: c.year!, month: c.month!, day: c.day!) / millisPerDay
    }

    /// Notti [from, to) di un soggiorno, nil se vuoto o rovesciato.
    private static func nightsOf(_ checkIn: Int64, _ checkOut: Int64) -> Range<Int64>? {
        let from = romeDay(checkIn), to = romeDay(checkOut)
        return to > from ? from..<to : nil
    }

    /// Unione delle notti occupate, con gli intervalli contigui fusi (due soggiorni attaccati coprono anche una chiusura
    /// Booking che li abbraccia entrambi). Ogni elemento: (prima notte, mattina di uscita).
    private static func mergedNights(_ reservations: [Reservation]) -> [(Int64, Int64)] {
        let sorted = reservations.compactMap { r in nightsOf(r.checkIn, r.checkOut).map { ($0.lowerBound, $0.upperBound) } }
            .sorted { $0.0 < $1.0 }
        var merged: [(Int64, Int64)] = []
        for n in sorted {
            if let last = merged.last, n.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, n.1))
            } else {
                merged.append(n)
            }
        }
        return merged
    }

    /// Eco = stesse notti di una prenotazione di un'altra piattaforma, o di più prenotazioni attaccate: notti tutte
    /// coperte E inizio/fine uguali all'inizio/fine di una di esse. Un evento strettamente dentro un soggiorno più lungo
    /// (Airbnb 1-10, Booking 3-5) non è un'eco: è il tipico overbooking nato dal ritardo di sincronizzazione.
    private static func echoMatcher(_ foreign: [Reservation]) -> (Int64, Int64) -> Bool {
        let merged = mergedNights(foreign)
        let nights = foreign.compactMap { nightsOf($0.checkIn, $0.checkOut) }
        let starts = Set(nights.map(\.lowerBound))
        let ends = Set(nights.map(\.upperBound))
        return { checkIn, checkOut in
            guard let n = nightsOf(checkIn, checkOut) else { return false }
            return starts.contains(n.lowerBound) && ends.contains(n.upperBound)
                && merged.contains { $0.0 <= n.lowerBound && $0.1 >= n.upperBound }
        }
    }

    /// Segnaposto Booking creato dall'iCal e mai toccato dall'host: niente importo, niente nome, non dall'Excel. Solo
    /// questi si tolgono come «eco» senza perdere dati (non hanno la spesa biancheria).
    static func isUntouchedPlaceholder(_ r: Reservation) -> Bool {
        guard let uid = r.icalUid else { return false }
        return !uid.hasPrefix("booking-xls-") && r.grossAmount == nil && (r.guestName ?? "").trimmed.isEmpty
    }

    /// Decide cosa importare e cosa cancellare, per piattaforma:
    /// - AIRBNB: importa solo gli eventi non bloccati; cancella le prenotazioni note il cui UID non è più nel feed
    ///   (UID stabili per Airbnb, quindi è il modo preciso per rilevare una cancellazione).
    /// - BOOKING: importa OGNI evento come segnaposto (`guestName` nil, mai il summary letterale "CLOSED - Not
    ///   available"), scartando quelli le cui date si sovrappongono a una prenotazione Booking già nota (Excel o iCal);
    ///   cancella le prenotazioni note le cui date non si sovrappongono più a nessun evento del feed fresco (gli UID
    ///   Excel/iCal sono estranei tra loro, quindi qui il confronto è per data, non per UID).
    /// - ECHI (solo BOOKING): Booking scrive «CLOSED - Not available» anche per le date che ha importato dai calendari
    ///   collegati (Airbnb, il sito). Un evento le cui notti sono tutte occupate da prenotazioni future di ALTRE
    ///   piattaforme (`otherFutureReservations`: Airbnb, MANUAL) è l'eco di quelle e non si importa; un segnaposto mai
    ///   toccato diventato eco si cancella. Una sovrapposizione solo parziale si importa comunque: è un vero doppio.
    /// Porta 1:1 `ICalSyncWorker.buildSyncPlan` dell'Android e `reservationSyncPlan.ts` del sito: cambiare tutti e tre.
    /// `now`: Booking crea solo da eventi con checkout futuro (stesso taglio delle prenotazioni note).
    static func buildSyncPlan(
        events: [ParsedEvent], propertyId: String, platform: String, existingFutureReservations: [Reservation],
        otherFutureReservations: [Reservation] = [], now: Int64 = 0
    ) -> Plan {
        // Un feed valido ma con zero eventi è indistinguibile da un feed rotto: non è un segnale abbastanza forte da
        // giustificare la cancellazione di ogni prenotazione nota. Senza eventi non si importa né si cancella nulla.
        if events.isEmpty { return Plan(toUpsert: [], toDelete: []) }

        let validEvents = events.filter { $0.checkIn > 0 && $0.checkOut > 0 }

        switch platform {
        case "AIRBNB":
            let toUpsert = validEvents
                .filter { !isBlockedEvent($0.summary) }
                .map { event in
                    Reservation(
                        propertyId: propertyId, guestName: event.summary, checkIn: event.checkIn, checkOut: event.checkOut,
                        platform: platform, icalUid: event.uid, needsReview: true
                    )
                }
            let feedUids = Set(validEvents.map(\.uid))
            let toDelete = existingFutureReservations.filter { $0.icalUid != nil && !feedUids.contains($0.icalUid!) }
            return Plan(toUpsert: toUpsert, toDelete: toDelete)

        case "BOOKING":
            let isEcho = echoMatcher(otherFutureReservations)
            let futureEvents = validEvents.filter { $0.checkOut > now }
            let echoes = futureEvents.filter { isEcho($0.checkIn, $0.checkOut) }.count
            // Due eventi con le stesse identiche date nello stesso feed sono una sola occupazione.
            var seen = Set<[Int64]>()
            let toUpsert = futureEvents
                .filter { !isEcho($0.checkIn, $0.checkOut) }
                .filter { event in
                    !existingFutureReservations.contains {
                        dateRangesOverlap($0.checkIn, $0.checkOut, event.checkIn, event.checkOut)
                    }
                }
                .filter { seen.insert([$0.checkIn, $0.checkOut]).inserted }
                .map { event in
                    Reservation(
                        propertyId: propertyId, guestName: nil, checkIn: event.checkIn, checkOut: event.checkOut,
                        platform: platform, icalUid: event.uid, needsReview: true
                    )
                }
            // Mai creare e cancellare lo stesso id nello stesso giro: un evento che si sovrappone a un segnaposto
            // cancellato ora resta fuori fino al giro dopo.
            let toDelete = existingFutureReservations.filter { existing in
                !validEvents.contains { dateRangesOverlap(existing.checkIn, existing.checkOut, $0.checkIn, $0.checkOut) }
                    || (isUntouchedPlaceholder(existing) && isEcho(existing.checkIn, existing.checkOut))
            }
            return Plan(toUpsert: toUpsert, toDelete: toDelete, echoes: echoes)

        default:
            return Plan(toUpsert: [], toDelete: [])
        }
    }

    /// Motivo di errore sicuro da mostrare in UI: tiene il tipo di errore (basta a distinguere un URL morto da un
    /// problema di rete) e cancella qualsiasi URL, perché i link iCal di Airbnb/Booking contengono un token segreto.
    static func safeErrorReason(typeName: String, message: String?) -> String {
        guard let message, !message.isEmpty else { return typeName }
        let cleaned = message.replacingOccurrences(of: #"https?://\S+"#, with: "<url iCal>", options: .regularExpression)
        return "\(typeName): \(cleaned.prefix(120))"
    }

    static func safeErrorReason(_ error: Error) -> String {
        safeErrorReason(typeName: String(describing: type(of: error)), message: (error as NSError).localizedDescription)
    }
}
