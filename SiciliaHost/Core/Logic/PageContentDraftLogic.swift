import Foundation

// Bozza dei contenuti della pagina (`ui/site/content/PageContentDraft.kt`): camere e letti, regole, accesso, tassa di
// soggiorno, dintorni, trasporti, host. Patch a blocchi: ogni blocco viaggia intero e solo se è cambiato; un blocco
// svuotato si manda come `NSNull`.

enum PageContentOptions {
    static let ruleValues = ["allowed", "not_allowed", "on_request"]
    static let parkingTypes = ["none", "private", "street", "paid"]
    static let checkInTypes = ["in_person", "keybox", "smart_lock"]
    static let nearbyTypes = ["sea", "center", "supermarket", "airport", "pharmacy", "restaurant", "bus_stop"]
    static let hostLanguages = ["it", "en", "fr", "pl", "de", "es"]
    /// Letti che si scelgono nelle camere; la culla è a parte (interruttore), come extra opzionale.
    static let roomKinds = ["bedroom", "living_room", "other"]
    static let bedTypes = ["double", "single", "sofa_bed", "queen", "king", "bunk"]
    static let maxRooms = 20
    static let maxBedsPerType = 10
    static let maxNearby = 20
    static let maxName = 80
}

struct NearbyRow: Equatable, Codable {
    var type = "sea"
    var name = ""
    var minutes = ""
    var mode = "walk"
}

/// Una stanza con i suoi letti (tipo → quanti). Niente culla: sta in `PageContentDraft.crib`.
struct RoomRow: Equatable, Codable {
    var kind = "bedroom"
    var beds: [String: Int] = [:]
}

/// Tutto come testo, così un campo numerico può essere vuoto. "" = non indicato; ascensore e senza gradini: "", "yes", "no".
struct PageContentDraft: Equatable, Codable {
    var rooms: [RoomRow] = []
    var crib = false
    var pets = ""
    var smoking = ""
    var parties = ""
    var children = ""
    var quietFrom = ""
    var quietTo = ""
    var minAge = ""
    var rulesNote = ""
    var floor = ""
    var elevator = ""
    var stepFree = ""
    var parking = ""
    var parkingNote = ""
    var checkInType = ""
    var checkInNote = ""
    var taxAmount = ""
    var taxMaxNights = ""
    var taxExemptAge = ""
    var nearby: [NearbyRow] = []
    var transportNote = ""
    var hostName = ""
    var hostEmail = ""
    var hostPhone = ""
    var hostWhatsapp = false
    var hostLanguages: Set<String> = []
    var showPhone = false
    var showEmail = false
}

enum PageContentLogic {
    private typealias O = PageContentOptions

    private static func choice(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "" }
    private static func bool(_ text: String) -> Bool? { text == "yes" ? true : text == "no" ? false : nil }
    private static func int(_ text: String) -> Int? { Int(text.trimmed) }
    private static func orNil(_ text: String) -> String? { text.trimmed.isEmpty ? nil : text.trimmed }

    /// Stanze dal documento. Ogni culla, ovunque sia, diventa l'interruttore `crib`; una stanza con la sola culla sparisce.
    static func sleepingRows(_ source: [SiteSleepingRoom]?) -> (rooms: [RoomRow], crib: Bool) {
        var crib = false
        let rows: [RoomRow] = (source ?? []).compactMap { room in
            var beds: [String: Int] = [:]
            for bed in room.beds {
                guard let type = bed.type, let count = bed.count else { continue }
                if type == "crib" { crib = true } else if O.bedTypes.contains(type) {
                    beds[type] = min(max((beds[type] ?? 0) + count, 1), O.maxBedsPerType)
                }
            }
            guard !beds.isEmpty else { return nil }
            let kind = room.kind.flatMap { O.roomKinds.contains($0) ? $0 : nil } ?? "other"
            return RoomRow(kind: kind, beds: beds)
        }
        return (rows, crib)
    }

    static func draft(from content: PropertySiteContent) -> PageContentDraft {
        let (rooms, crib) = sleepingRows(content.sleepingArrangements)
        let rules = content.rulesStructured, access = content.access, tax = content.fees?.touristTax, host = content.host
        let quiet = rules?.quietHours?.components(separatedBy: "-")
        let hasQuiet = quiet?.count == 2
        var d = PageContentDraft()
        d.rooms = rooms
        d.crib = crib
        d.pets = rules?.pets ?? ""
        d.smoking = rules?.smoking ?? ""
        d.parties = rules?.parties ?? ""
        d.children = rules?.children ?? ""
        d.quietFrom = hasQuiet ? quiet![0] : ""
        d.quietTo = hasQuiet ? quiet![1] : ""
        d.minAge = rules?.minAge.map(String.init) ?? ""
        d.rulesNote = rules?.note ?? ""
        d.floor = access?.floor.map(String.init) ?? ""
        d.elevator = choice(access?.elevator)
        d.stepFree = choice(access?.stepFree)
        d.parking = access?.parking ?? ""
        d.parkingNote = access?.parkingNote ?? ""
        d.checkInType = access?.checkInType ?? ""
        d.checkInNote = access?.checkInNote ?? ""
        d.taxAmount = SiteNumbers.format(tax?.perPersonPerNight)
        d.taxMaxNights = tax?.maxNights.map(String.init) ?? ""
        d.taxExemptAge = tax?.exemptUnderAge.map(String.init) ?? ""
        d.nearby = content.nearby.map {
            NearbyRow(type: $0.type ?? "sea", name: $0.name ?? "", minutes: $0.minutes.map(String.init) ?? "", mode: $0.mode ?? "walk")
        }
        d.transportNote = content.transportNote ?? ""
        // Se l'host non è ancora stato compilato, si parte dal "Referente" del Guest Hub.
        d.hostName = host?.name ?? (host == nil ? content.managerContact?.name ?? "" : "")
        d.hostEmail = host?.email ?? ""
        d.hostPhone = host?.phone ?? (host == nil ? prefillPhone(content.managerContact?.phone) : "")
        d.hostWhatsapp = host?.whatsapp == true
        d.hostLanguages = Set(host?.languages ?? [])
        d.showPhone = host?.showPhone == true
        d.showEmail = host?.showEmail == true
        return d
    }

    private static let maxEmail = 254

    /// Come il server: una sola email, ASCII, max 254.
    static func isValidEmail(_ text: String) -> Bool {
        let t = text.trimmed
        return t.count <= maxEmail && t.wholeMatch(of: #/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/#) != nil
    }

    static func isValidPhone(_ text: String) -> Bool { text.wholeMatch(of: #/\+[1-9][0-9]{6,14}/#) != nil }

    static func normalizePhone(_ text: String) -> String {
        text.filter { !" \t\n-().".contains($0) && !$0.isWhitespace }
    }

    /// Telefono del "Referente" proposto come telefono host: normalizzato e solo se valido (senza prefisso +39, "00" → "+").
    static func prefillPhone(_ raw: String?) -> String {
        let n = normalizePhone(raw ?? "")
        let candidate = n.hasPrefix("+") ? n : n.hasPrefix("00") ? "+" + n.dropFirst(2) : "+39" + n
        return isValidPhone(candidate) ? candidate : ""
    }

    /// Errori per campo (chiave → messaggio). Vuoto = salvabile. Un campo vuoto non è mai un errore.
    static func errors(_ d: PageContentDraft) -> [String: String] {
        var errors: [String: String] = [:]
        func intIn(_ key: String, _ text: String, _ range: ClosedRange<Int>, _ message: String) {
            guard !text.trimmed.isEmpty else { return }
            if let n = int(text), range.contains(n) { return }
            errors[key] = message
        }
        func note(_ key: String, _ text: String) {
            if text.trimmed.count > maxServiceNote { errors[key] = "Massimo \(maxServiceNote) caratteri" }
        }
        let quietPattern = #/([01][0-9]|2[0-3]):[0-5][0-9]/#

        if d.rooms.count > O.maxRooms { errors["rooms"] = "Massimo \(O.maxRooms) stanze" }
        for (i, room) in d.rooms.enumerated() where !room.beds.values.contains(where: { $0 > 0 }) {
            errors["rooms.\(i)"] = "Aggiungi almeno un letto o rimuovi la stanza"
        }
        if !d.quietFrom.trimmed.isEmpty || !d.quietTo.trimmed.isEmpty {
            if d.quietFrom.trimmed.wholeMatch(of: quietPattern) == nil || d.quietTo.trimmed.wholeMatch(of: quietPattern) == nil {
                errors["quietHours"] = "Indica inizio e fine nel formato 22:00"
            }
        }
        intIn("minAge", d.minAge, 1 ... 99, "Età da 1 a 99")
        note("rulesNote", d.rulesNote)
        intIn("floor", d.floor, -2 ... 100, "Piano intero da -2 a 100")
        note("parkingNote", d.parkingNote)
        note("checkInNote", d.checkInNote)

        if !d.taxAmount.trimmed.isEmpty {
            let amount = SiteNumbers.parse(d.taxAmount)
            if amount == nil || amount! <= 0 || amount! > 100 { errors["taxAmount"] = "Importo da 0,01 a 100" }
        }
        if d.taxAmount.trimmed.isEmpty && (!d.taxMaxNights.trimmed.isEmpty || !d.taxExemptAge.trimmed.isEmpty) {
            errors["taxAmount"] = "Indica l'importo della tassa"
        }
        intIn("taxMaxNights", d.taxMaxNights, 1 ... 365, "Notti da 1 a 365")
        intIn("taxExemptAge", d.taxExemptAge, 0 ... 18, "Età da 0 a 18")

        if d.nearby.count > O.maxNearby { errors["nearby"] = "Massimo \(O.maxNearby) luoghi" }
        for (i, row) in d.nearby.enumerated() {
            if let m = int(row.minutes), (1 ... 600).contains(m) {
                if row.name.trimmed.count > O.maxName { errors["nearby.\(i)"] = "Nome: massimo \(O.maxName) caratteri" }
            } else {
                errors["nearby.\(i)"] = "Minuti da 1 a 600"
            }
        }
        note("transportNote", d.transportNote)

        if d.hostName.trimmed.count > O.maxName { errors["hostName"] = "Massimo \(O.maxName) caratteri" }
        if !d.hostEmail.trimmed.isEmpty && !isValidEmail(d.hostEmail) { errors["hostEmail"] = "Email non valida" }
        if !d.hostPhone.trimmed.isEmpty && !isValidPhone(normalizePhone(d.hostPhone)) {
            errors["hostPhone"] = "Usa il formato internazionale, es. +39 333 1234567"
        }
        if d.showEmail && d.hostEmail.trimmed.isEmpty && errors["hostEmail"] == nil {
            errors["hostEmail"] = "Inserisci l'email per mostrarla sul sito"
        }
        if d.showPhone && d.hostPhone.trimmed.isEmpty && errors["hostPhone"] == nil {
            errors["hostPhone"] = "Inserisci il telefono per mostrarlo sul sito"
        }
        return errors
    }

    // MARK: Blocchi del documento (valori confrontabili: AnyHashable)

    /// La culla viaggia come letto `crib` nella prima stanza (o in una stanza "other" se non ce ne sono).
    static func sleepingList(_ d: PageContentDraft) -> AnyHashable? {
        var rooms: [[String: AnyHashable]] = d.rooms.compactMap { room in
            let beds: [AnyHashable] = O.bedTypes.compactMap { type in
                guard let n = room.beds[type], n > 0 else { return nil }
                return AnyHashable(["type": type, "count": n] as [String: AnyHashable])
            }
            return beds.isEmpty ? nil : ["kind": AnyHashable(room.kind), "beds": AnyHashable(beds)]
        }
        if !d.crib { return rooms.isEmpty ? nil : AnyHashable(rooms) }
        let crib: AnyHashable = ["type": "crib", "count": 1] as [String: AnyHashable]
        if rooms.isEmpty { return AnyHashable([["kind": "other", "beds": [crib]] as [String: AnyHashable]]) }
        var first = rooms[0]
        first["beds"] = ((first["beds"] as? [AnyHashable]) ?? []) + [crib]
        rooms[0] = first
        return AnyHashable(rooms)
    }

    private static func nonEmpty(_ m: [String: AnyHashable]) -> AnyHashable? { m.isEmpty ? nil : AnyHashable(m) }

    static func rulesMap(_ d: PageContentDraft) -> AnyHashable? {
        var m: [String: AnyHashable] = [:]
        if let v = orNil(d.pets) { m["pets"] = v }
        if let v = orNil(d.smoking) { m["smoking"] = v }
        if let v = orNil(d.parties) { m["parties"] = v }
        if let v = orNil(d.children) { m["children"] = v }
        if !d.quietFrom.trimmed.isEmpty && !d.quietTo.trimmed.isEmpty { m["quietHours"] = "\(d.quietFrom.trimmed)-\(d.quietTo.trimmed)" }
        if let v = int(d.minAge) { m["minAge"] = v }
        if let v = orNil(d.rulesNote) { m["note"] = v }
        return nonEmpty(m)
    }

    static func accessMap(_ d: PageContentDraft) -> AnyHashable? {
        var m: [String: AnyHashable] = [:]
        if let v = int(d.floor) { m["floor"] = v }
        if let v = bool(d.elevator) { m["elevator"] = v }
        if let v = bool(d.stepFree) { m["stepFree"] = v }
        if let v = orNil(d.parking) { m["parking"] = v }
        if let v = orNil(d.parkingNote) { m["parkingNote"] = v }
        if let v = orNil(d.checkInType) { m["checkInType"] = v }
        if let v = orNil(d.checkInNote) { m["checkInNote"] = v }
        return nonEmpty(m)
    }

    static func feesMap(_ d: PageContentDraft) -> AnyHashable? {
        guard let amount = SiteNumbers.parse(d.taxAmount), amount > 0 else { return nil }
        var tax: [String: AnyHashable] = ["perPersonPerNight": amount]
        if let v = int(d.taxMaxNights) { tax["maxNights"] = v }
        if let v = int(d.taxExemptAge) { tax["exemptUnderAge"] = v }
        return AnyHashable(["touristTax": tax] as [String: AnyHashable])
    }

    static func nearbyList(_ d: PageContentDraft) -> AnyHashable? {
        let rows: [AnyHashable] = d.nearby.compactMap { row in
            guard let minutes = int(row.minutes) else { return nil }
            var m: [String: AnyHashable] = ["type": row.type, "minutes": minutes, "mode": row.mode]
            if let name = orNil(row.name) { m["name"] = name }
            return AnyHashable(m)
        }
        return rows.isEmpty ? nil : AnyHashable(rows)
    }

    static func hostMap(_ d: PageContentDraft) -> AnyHashable? {
        var m: [String: AnyHashable] = [:]
        if let v = orNil(d.hostName) { m["name"] = v }
        if let v = orNil(d.hostEmail) { m["email"] = v }
        if let v = orNil(d.hostPhone) { m["phone"] = normalizePhone(v) }
        if !d.hostLanguages.isEmpty { m["languages"] = d.hostLanguages.sorted() }
        if d.hostWhatsapp { m["whatsapp"] = true }
        if d.showPhone { m["showPhone"] = true }
        if d.showEmail { m["showEmail"] = true }
        return nonEmpty(m)
    }

    /// Patch per `upsertProperty`: i blocchi cambiati, ciascuno intero; quelli svuotati come `NSNull`.
    static func patch(original: PageContentDraft, current: PageContentDraft) -> [String: Any] {
        var patch: [String: Any] = [:]
        func block(_ key: String, _ read: (PageContentDraft) -> AnyHashable?) {
            let before = read(original), after = read(current)
            if before != after { patch[key] = after.map { $0 as Any } ?? NSNull() }
        }
        block("sleepingArrangements", sleepingList)
        block("rulesStructured", rulesMap)
        block("access", accessMap)
        block("fees", feesMap)
        block("nearby", nearbyList)
        block("transportNote") { orNil($0.transportNote).map { AnyHashable($0) } }
        block("host", hostMap)
        return patch
    }
}
