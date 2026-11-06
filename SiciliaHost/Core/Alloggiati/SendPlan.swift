import Foundation

/// Le schede di una prenotazione come stanno sul telefono (un file per prenotazione).
struct StoredCheckin: Codable, Equatable, Sendable {
    var propertyId: String
    var reservationId: String
    /// Partenza della prenotazione (ms), per proporre di cancellare le schede mai inviate. 0 = sconosciuta.
    var checkOut: Int64 = 0
    var records: [GuestRecord] = []
}

extension StoredCheckin {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        propertyId = try c.decode(String.self, forKey: .propertyId)
        reservationId = try c.decode(String.self, forKey: .reservationId)
        checkOut = c.value(.checkOut, 0)
        records = try c.decodeIfPresent([GuestRecord].self, forKey: .records) ?? []
    }
}

/// Esito di una scheda inviata.
struct SendOutcome: Equatable, Sendable {
    let sent: Bool
    let error: String?
}

/// Regole d'invio (porta di `SendPlan.kt`): mai doppio invio, esito incerto visibile, conservazione 30 giorni.
enum SendPlan {
    static let lockMs: Int64 = 2 * 60 * 1000
    static let retentionMs: Int64 = 30 * 24 * 60 * 60 * 1000
    static let uncertainMessage = "Esito incerto: controlla la ricevuta sul portale prima di riprovare"

    /// Le schede da provare o inviare: mai quelle già accettate; per l'invio nemmeno quelle in invio da meno di 2 minuti.
    static func pending(_ records: [GuestRecord], now: Int64, respectLock: Bool) -> [GuestRecord] {
        records.filter { r in
            let locked = r.sendingAt.map { now - $0 < lockMs } ?? false
            return !r.schedInaSent && !(respectLock && locked)
        }
    }

    /// Un esito per scheda, per indice. Se i conti non tornano l'esito è sconosciuto (`nil`).
    static func outcomes(count: Int, _ dettaglio: [EsitoSingolo]) -> [SendOutcome]? {
        guard dettaglio.count == count else { return nil }
        return dettaglio.map {
            $0.esito ? SendOutcome(sent: true, error: nil)
                : SendOutcome(sent: false, error: $0.errorDes.isEmpty ? "Scheda rifiutata" : $0.errorDes)
        }
    }

    static func apply(_ records: [GuestRecord], ids: [String], outcomes: [SendOutcome], now: Int64) -> [GuestRecord] {
        var byId: [String: SendOutcome] = [:]
        for (id, outcome) in zip(ids, outcomes) { byId[id] = outcome }
        return records.map { r in
            guard let o = byId[r.id] else { return r }
            var c = r
            c.schedInaSent = o.sent
            c.sendTimestamp = now
            c.sendError = o.error
            c.sendingAt = nil
            return c
        }
    }

    static func lock(_ records: [GuestRecord], ids: [String], now: Int64) -> [GuestRecord] {
        records.map { r in
            guard ids.contains(r.id) else { return r }
            var c = r
            c.sendingAt = now
            return c
        }
    }

    static func markUncertain(_ records: [GuestRecord], ids: [String]) -> [GuestRecord] {
        records.map { r in
            guard ids.contains(r.id) else { return r }
            var c = r
            c.sendError = uncertainMessage
            c.sendingAt = nil
            return c
        }
    }

    /// Un blocco più vecchio di `lockMs` vuol dire che l'app è stata chiusa durante l'invio: l'esito è sconosciuto, quindi
    /// la scheda diventa «esito incerto» invece di poter essere rinviata.
    static func normalizeStaleLocks(_ records: [GuestRecord], now: Int64) -> [GuestRecord] {
        records.map { r in
            guard let at = r.sendingAt, now - at >= lockMs else { return r }
            var c = r
            c.sendError = uncertainMessage
            c.sendingAt = nil
            return c
        }
    }

    static func releaseLocks(_ records: [GuestRecord], ids: [String]) -> [GuestRecord] {
        records.map { r in
            guard ids.contains(r.id) else { return r }
            var c = r
            c.sendingAt = nil
            return c
        }
    }

    static func hasUncertain(_ records: [GuestRecord]) -> Bool { records.contains { $0.sendError == uncertainMessage } }

    /// Tutte inviate e l'ultimo invio più vecchio di 30 giorni: si cancellano da sole.
    static func isExpired(_ c: StoredCheckin, now: Int64) -> Bool {
        guard !c.records.isEmpty, c.records.allSatisfy(\.schedInaSent),
              let last = c.records.compactMap(\.sendTimestamp).max() else { return false }
        return now - last > retentionMs
    }

    /// Schede mai inviate di un soggiorno finito da più di 30 giorni: l'app propone di cancellarle.
    static func isStaleUnsent(_ c: StoredCheckin, now: Int64) -> Bool {
        c.checkOut > 0 && now - c.checkOut > retentionMs && c.records.contains { !$0.schedInaSent }
    }
}
