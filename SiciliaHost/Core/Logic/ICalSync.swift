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

    /// Decide cosa importare e cosa cancellare, per piattaforma:
    /// - AIRBNB: importa solo gli eventi non bloccati; cancella le prenotazioni note il cui UID non è più nel feed
    ///   (UID stabili per Airbnb, quindi è il modo preciso per rilevare una cancellazione).
    /// - BOOKING: importa OGNI evento come segnaposto (`guestName` nil, mai il summary letterale "CLOSED - Not
    ///   available"), scartando quelli le cui date si sovrappongono a una prenotazione Booking già nota (Excel o iCal);
    ///   cancella le prenotazioni note le cui date non si sovrappongono più a nessun evento del feed fresco (gli UID
    ///   Excel/iCal sono estranei tra loro, quindi qui il confronto è per data, non per UID).
    static func buildSyncPlan(
        events: [ParsedEvent], propertyId: String, platform: String, existingFutureReservations: [Reservation]
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
            let toUpsert = validEvents
                .filter { event in
                    !existingFutureReservations.contains {
                        dateRangesOverlap($0.checkIn, $0.checkOut, event.checkIn, event.checkOut)
                    }
                }
                .map { event in
                    Reservation(
                        propertyId: propertyId, guestName: nil, checkIn: event.checkIn, checkOut: event.checkOut,
                        platform: platform, icalUid: event.uid, needsReview: true
                    )
                }
            let toDelete = existingFutureReservations.filter { existing in
                !validEvents.contains { dateRangesOverlap(existing.checkIn, existing.checkOut, $0.checkIn, $0.checkOut) }
            }
            return Plan(toUpsert: toUpsert, toDelete: toDelete)

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
