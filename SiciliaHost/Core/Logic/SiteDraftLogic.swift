import Foundation

// Logica pura delle bozze della scheda casa: posizione (`ui/site/position/PositionState.kt`), campi del sito
// (`ui/site/SiteDraft.kt`) e campi dell'app (`ui/cases/AppFieldsDraft.kt`). Niente SwiftUI né Firebase.
// `SiteDraftSaver.kt` (salvataggio nel Bundle Android) qui non serve: le bozze sono valori in `@State` e `Codable`.

// MARK: Posizione

/// Pin esatto + centro dell'area pubblica. L'invariante 50–250 m tra i due vale per costruzione; `problem()` resta come
/// rete di sicurezza (coordinate digitate a mano o salvate altrove).
struct PositionState: Equatable {
    var exact: LatLng?
    var area: LatLng?

    private static let toleranceM = 1.0

    /// nil = valido. Un pin senza area è "non valido" solo perché un salvataggio deve crearla.
    func problem() -> String? {
        if let e = exact, !e.isValid { return "Posizione non valida" }
        if let a = area, !a.isValid { return "Posizione non valida" }
        guard let exact else { return area == nil ? nil : "Manca il pin esatto" }
        guard let area else { return "Manca l'area pubblica" }
        let d = distanceMeters(exact, area)
        if d < minAreaOffsetM - Self.toleranceM { return "L'area pubblica è troppo vicina al pin: sposta la maniglia" }
        if d > maxAreaOffsetM + Self.toleranceM { return "Il pin esatto deve stare dentro l'area pubblica" }
        return nil
    }

    /// Posiziona o sposta il pin esatto. Con un'area valida la trascina dello stesso vettore (riportata in 50–250 m),
    /// altrimenti la crea a 150 m in una direzione casuale: un centro sopra la casa pubblicherebbe il punto esatto.
    /// Un punto non valido è ignorato.
    func withExact(_ point: LatLng, bearing: () -> Double = { Double.random(in: 0 ..< 2 * .pi) }) -> PositionState {
        guard point.isValid else { return self }
        let newExact = point.rounded()
        let currentExact = exact.flatMap { $0.isValid ? $0 : nil }
        let currentArea = area.flatMap { $0.isValid ? $0 : nil }
        let newArea: LatLng
        if let currentExact, let currentArea {
            newArea = clampAreaCenter(exact: newExact, candidate: currentArea.shifted(from: currentExact, to: newExact))
        } else {
            newArea = defaultAreaCenter(exact: newExact, bearingRad: bearing())
        }
        return PositionState(exact: newExact, area: newArea.rounded())
    }

    /// Maniglia dell'area: cambia solo lo scostamento, sempre dentro 50–250 m.
    func withAreaHandle(_ point: LatLng) -> PositionState {
        guard point.isValid, let pin = exact, pin.isValid else { return self }
        return PositionState(exact: exact, area: clampAreaCenter(exact: pin, candidate: point).rounded())
    }
}

// MARK: Bozza dei campi del sito

let translationLangs = ["en", "fr", "pl"]
let allSiteLangs = ["it"] + translationLangs

/// Stato del modulo come testo, così un campo numerico può essere vuoto. Le foto non ne fanno parte: si caricano e si
/// salvano subito.
struct SiteDraft: Equatable, Codable {
    var published = false
    var zone = ""
    var price = ""
    var cleaningFee = ""
    var depositPercentage = ""
    var freeCancelDays = ""
    var manualConfirmation = false
    var lat = ""
    var lng = ""
    var address = ""
    var areaLat = ""
    var areaLng = ""
    var wifiSsid = ""
    var wifiPassword = ""
    var managerName = ""
    var managerPhone = ""
    var localTips: [String: String] = [:]
    var departureChecklist: [String: String] = [:]
    var titleTr: [String: String] = [:]
    var descriptionTr: [String: String] = [:]
    var houseRulesTr: [String: String] = [:]

    init() {}

    init(_ c: PropertySiteContent) {
        published = c.publishedOnSite == true
        zone = c.zone ?? ""
        price = SiteNumbers.format(c.basePricePerNight)
        cleaningFee = SiteNumbers.format(c.cleaningFee)
        depositPercentage = SiteNumbers.format(c.depositPercentage)
        freeCancelDays = c.cancellationPolicy?.freeUntilDaysBefore.map(String.init) ?? ""
        manualConfirmation = c.requiresManualConfirmation == true
        lat = SiteNumbers.format(c.coordinates?.lat)
        lng = SiteNumbers.format(c.coordinates?.lng)
        address = c.address ?? ""
        areaLat = SiteNumbers.format(c.publicArea?.lat)
        areaLng = SiteNumbers.format(c.publicArea?.lng)
        wifiSsid = c.wifiInfo?.ssid ?? ""
        wifiPassword = c.wifiInfo?.password ?? ""
        managerName = c.managerContact?.name ?? ""
        managerPhone = c.managerContact?.phone ?? ""
        localTips = c.localTips ?? [:]
        departureChecklist = c.departureChecklist ?? [:]
        titleTr = c.titleTranslations ?? [:]
        descriptionTr = c.descriptionTranslations ?? [:]
        houseRulesTr = c.houseRulesTranslations ?? [:]
    }

    /// Una coppia vale solo se entrambi i numeri sono validi.
    var positionState: PositionState {
        PositionState(exact: Self.pair(lat, lng), area: Self.pair(areaLat, areaLng))
    }

    func withPosition(_ state: PositionState) -> SiteDraft {
        var d = self
        d.lat = SiteNumbers.format(state.exact?.lat)
        d.lng = SiteNumbers.format(state.exact?.lng)
        d.areaLat = SiteNumbers.format(state.area?.lat)
        d.areaLng = SiteNumbers.format(state.area?.lng)
        return d
    }

    private static func pair(_ lat: String, _ lng: String) -> LatLng? {
        guard let a = SiteNumbers.parse(lat), let b = SiteNumbers.parse(lng) else { return nil }
        return LatLng(lat: a, lng: b)
    }

    func positionChanged(from original: SiteDraft) -> Bool {
        address != original.address || lat != original.lat || lng != original.lng
            || areaLat != original.areaLat || areaLng != original.areaLng
    }
}

/// Numeri dei campi del sito: solo decimali semplici, virgola o punto.
enum SiteNumbers {
    /// "1.000" in italiano è mille ma verrebbe letto come 1,0: un punto seguito da esattamente tre cifre (parte intera
    /// di 1-3 cifre) è ambiguo e si rifiuta. Niente esponenti, suffissi, NaN.
    static func parse(_ text: String) -> Double? {
        let t = text.trimmed
        if t.wholeMatch(of: #/-?[0-9]{1,3}\.[0-9]{3}/#) != nil { return nil }
        guard t.wholeMatch(of: #/-?[0-9]+([.,][0-9]+)?/#) != nil,
              let value = Double(t.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }

    /// Interi senza decimali; tre decimali col punto (ambigui) scritti con la virgola.
    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 { return String(Int64(value)) }
        let text = kotlinDoubleString(value)
        return text.wholeMatch(of: #/-?[0-9]{1,3}\.[0-9]{3}/#) != nil ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// Come `Double.toString()` di Kotlin per i valori comuni (la rappresentazione più corta che torna allo stesso numero).
    private static func kotlinDoubleString(_ v: Double) -> String { "\(v)" }
}

enum SiteDraftLogic {
    /// Cosa manca perché la scheda si possa mostrare sul sito (gli stessi campi da cui il server calcola il prezzo del
    /// soggiorno). Vuota = pubblicabile.
    static func publishBlockers(_ d: SiteDraft, photoCount: Int) -> [String] {
        var out: [String] = []
        if d.zone.trimmed.isEmpty { out.append("Zona") }
        if (SiteNumbers.parse(d.price) ?? 0) <= 0 { out.append("Prezzo a notte (maggiore di 0)") }
        if SiteNumbers.parse(d.cleaningFee) == nil { out.append("Costo pulizie") }
        if SiteNumbers.parse(d.depositPercentage) == nil { out.append("Caparra %") }
        if Int(d.freeCancelDays.trimmed) == nil { out.append("Giorni di cancellazione gratuita") }
        if photoCount <= 0 { out.append("Almeno una foto") }
        return out
    }

    /// Errori per campo (chiave → messaggio). Un campo già valorizzato non si può svuotare: la callable non ha modo di
    /// cancellare un campo obbligatorio.
    static func fieldErrors(original: SiteDraft, current: SiteDraft) -> [String: String] {
        var errors: [String: String] = [:]
        func set(_ key: String, _ message: String) { errors[key] = message }
        func has(_ key: String) -> Bool { errors[key] != nil }
        let cannotEmpty = "Non si può svuotare"

        if current.zone.trimmed.isEmpty && !original.zone.trimmed.isEmpty { set("zone", cannotEmpty) }

        func number(_ key: String, _ cur: String, _ orig: String, max: Double? = nil) {
            if cur.trimmed.isEmpty {
                if !orig.trimmed.isEmpty { set(key, cannotEmpty) }
                return
            }
            guard let n = SiteNumbers.parse(cur), n >= 0 else { set(key, "Numero non valido (0 o più)"); return }
            if let max, n > max { set(key, "Massimo \(SiteNumbers.format(max))") }
        }
        number("price", current.price, original.price)
        number("cleaningFee", current.cleaningFee, original.cleaningFee)
        number("deposit", current.depositPercentage, original.depositPercentage, max: 100)

        if current.freeCancelDays.trimmed.isEmpty {
            if !original.freeCancelDays.trimmed.isEmpty { set("freeCancelDays", cannotEmpty) }
        } else if (Int(current.freeCancelDays.trimmed) ?? -1) < 0 {
            set("freeCancelDays", "Numero intero non valido (0 o più)")
        }

        let lat = SiteNumbers.parse(current.lat), lng = SiteNumbers.parse(current.lng)
        if !current.lat.trimmed.isEmpty && (lat == nil || !(-90.0 ... 90.0).contains(lat!)) {
            set("lat", "Latitudine non valida (-90..90)")
        }
        if !current.lng.trimmed.isEmpty && (lng == nil || !(-180.0 ... 180.0).contains(lng!)) {
            set("lng", "Longitudine non valida (-180..180)")
        }
        if current.lat.trimmed.isEmpty != current.lng.trimmed.isEmpty {
            set(current.lat.trimmed.isEmpty ? "lat" : "lng", "Inserisci sia latitudine che longitudine")
        }

        if current.address.trimmed.count > 300 { set("address", "Massimo 300 caratteri") }

        let aLat = SiteNumbers.parse(current.areaLat), aLng = SiteNumbers.parse(current.areaLng)
        var areaFormatOk = true
        if current.areaLat.trimmed.isEmpty != current.areaLng.trimmed.isEmpty {
            set("area", "Inserisci sia latitudine che longitudine dell'area")
            areaFormatOk = false
        } else if !current.areaLat.trimmed.isEmpty
                    && (aLat == nil || aLng == nil || !(-90.0 ... 90.0).contains(aLat!) || !(-180.0 ... 180.0).contains(aLng!)) {
            set("area", "Area pubblica non valida")
            areaFormatOk = false
        }
        // La regola pin + area vale solo quando l'utente ha toccato la posizione: un pin storico senza area non deve
        // bloccare il salvataggio di un prezzo.
        if areaFormatOk && !has("lat") && !has("lng") && current.positionChanged(from: original),
           let message = current.positionState.problem() {
            set("area", message == "Manca l'area pubblica" ? "Imposta l'area pubblica (Modifica posizione)" : message)
        }

        func needsItalian(_ key: String, _ texts: [String: String]) {
            let other = texts.contains { $0.key != "it" && !$0.value.trimmed.isEmpty }
            if other && (texts["it"] ?? "").trimmed.isEmpty { set(key, "Scrivi prima la versione italiana") }
        }
        needsItalian("localTips", current.localTips)
        needsItalian("departureChecklist", current.departureChecklist)
        return errors
    }

    private static func cleanTexts(_ texts: [String: String]) -> [String: String] {
        texts.mapValues(\.trimmed).filter { !$0.value.isEmpty }
    }

    /// Solo i campi cambiati, nel formato di `upsertProperty`. Una bozza pubblicata include sempre l'insieme
    /// obbligatorio. I campi opzionali svuotati viaggiano come `NSNull`. `photos` solo se pubblicata.
    static func buildPatch(original: SiteDraft, current: SiteDraft, photos: [String]) -> [String: Any] {
        var patch: [String: Any] = [:]
        let forced = current.published
        if current.published != original.published { patch["publishedOnSite"] = current.published }

        let zone = current.zone.trimmed
        if !zone.isEmpty && (forced || zone != original.zone.trimmed) { patch["zone"] = zone }

        func number(_ key: String, _ cur: String, _ orig: String) {
            guard let n = SiteNumbers.parse(cur) else { return }
            if forced || cur != orig { patch[key] = n }
        }
        number("basePricePerNight", current.price, original.price)
        number("cleaningFee", current.cleaningFee, original.cleaningFee)
        number("depositPercentage", current.depositPercentage, original.depositPercentage)

        if let days = Int(current.freeCancelDays.trimmed), forced || current.freeCancelDays != original.freeCancelDays {
            patch["cancellationPolicy"] = ["freeUntilDaysBefore": days]
        }
        if forced || current.manualConfirmation != original.manualConfirmation {
            patch["requiresManualConfirmation"] = current.manualConfirmation
        }
        if forced { patch["photos"] = photos }

        // Il gruppo Posizione viaggia sempre intero: il server valida lo stato unito e deve ricevere pin e area coerenti.
        if current.positionChanged(from: original) {
            func pair(_ lat: String, _ lng: String) -> Any {
                guard let a = SiteNumbers.parse(lat), let b = SiteNumbers.parse(lng) else { return NSNull() }
                return ["lat": a, "lng": b] as [String: Double]
            }
            let address = current.address.trimmed
            patch["address"] = address.isEmpty ? NSNull() as Any : address as Any
            patch["coordinates"] = pair(current.lat, current.lng)
            patch["publicArea"] = pair(current.areaLat, current.areaLng)
        }
        if current.wifiSsid != original.wifiSsid || current.wifiPassword != original.wifiPassword {
            let empty = current.wifiSsid.trimmed.isEmpty && current.wifiPassword.trimmed.isEmpty
            let wifi: [String: Any] = ["ssid": current.wifiSsid.trimmed, "password": current.wifiPassword]
            patch["wifiInfo"] = empty ? NSNull() as Any : wifi as Any
        }
        if current.managerName != original.managerName || current.managerPhone != original.managerPhone {
            let empty = current.managerName.trimmed.isEmpty && current.managerPhone.trimmed.isEmpty
            let contact: [String: Any] = ["name": current.managerName.trimmed, "phone": current.managerPhone.trimmed]
            patch["managerContact"] = empty ? NSNull() as Any : contact as Any
        }

        func texts(_ key: String, _ cur: [String: String], _ orig: [String: String]) {
            let cleaned = cleanTexts(cur)
            if cleaned != cleanTexts(orig) { patch[key] = cleaned.isEmpty ? NSNull() as Any : cleaned as Any }
        }
        texts("localTips", current.localTips, original.localTips)
        texts("departureChecklist", current.departureChecklist, original.departureChecklist)
        texts("titleTranslations", current.titleTr, original.titleTr)
        texts("descriptionTranslations", current.descriptionTr, original.descriptionTr)
        texts("houseRulesTranslations", current.houseRulesTr, original.houseRulesTr)
        return patch
    }
}

// MARK: Bozza dei campi dell'app

/// Messaggio d'errore della scheda, o nil (`validatePropertyForm` dell'Android).
func validatePropertyForm(name: String, idAppartamentoText: String) -> String? {
    if name.trimmed.isEmpty { return "Il nome è obbligatorio" }
    if !idAppartamentoText.trimmed.isEmpty && Int(idAppartamentoText.trimmed) == nil {
        return "ID Appartamento deve essere un numero"
    }
    return nil
}

/// Campi "dell'app" della scheda casa, come testo dei campi che li modificano. Dice cosa è cambiato.
struct AppFieldsDraft: Equatable, Codable {
    var name = ""
    var cin = ""
    var maxGuests = ""
    var bedrooms = ""
    var beds = ""
    var bathrooms = ""
    var description = ""
    var amenitiesText = ""
    var houseRules = ""
    var checkInTime = ""
    var checkOutTime = ""
    // Gestione (solo OWNER / commissione): mai inviati dal flusso del super-admin.
    var icalUrlAirbnb = ""
    var icalUrlBooking = ""
    var idAppartamento = ""
    var isManagedOnCommission = false

    init() {}

    init(_ p: Property?) {
        name = p?.name ?? ""
        cin = p?.cin ?? ""
        maxGuests = p?.maxGuests.map(String.init) ?? ""
        bedrooms = p?.bedrooms.map(String.init) ?? ""
        beds = p?.beds.map(String.init) ?? ""
        bathrooms = p?.bathrooms.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : "\($0)" } ?? ""
        description = p?.description ?? ""
        amenitiesText = p?.amenities.joined(separator: "\n") ?? ""
        houseRules = p?.houseRules ?? ""
        checkInTime = p?.checkInTime ?? ""
        checkOutTime = p?.checkOutTime ?? ""
        icalUrlAirbnb = p?.icalUrlAirbnb ?? ""
        icalUrlBooking = p?.icalUrlBooking ?? ""
        idAppartamento = p?.idAppartamento.map(String.init) ?? ""
        isManagedOnCommission = p?.isManagedOnCommission ?? false
    }

    func error() -> String? { validatePropertyForm(name: name, idAppartamentoText: idAppartamento) }

    private static func blankToNil(_ s: String) -> String? { s.trimmed.isEmpty ? nil : s.trimmed }

    /// La `base` aggiornata con questa bozza (id, appartenenza e il resto restano della base).
    func apply(to base: Property) -> Property {
        var p = base
        p.name = name.trimmed
        p.cin = Self.blankToNil(cin)
        p.maxGuests = Int(maxGuests.trimmed)
        p.bedrooms = Int(bedrooms.trimmed)
        p.beds = Int(beds.trimmed)
        p.bathrooms = Double(bathrooms.trimmed.replacingOccurrences(of: ",", with: "."))
        p.description = Self.blankToNil(description)
        p.amenities = amenitiesText.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        p.houseRules = Self.blankToNil(houseRules)
        p.checkInTime = Self.blankToNil(checkInTime)
        p.checkOutTime = Self.blankToNil(checkOutTime)
        p.icalUrlAirbnb = Self.blankToNil(icalUrlAirbnb)
        p.icalUrlBooking = Self.blankToNil(icalUrlBooking)
        p.idAppartamento = Int(idAppartamento.trimmed)
        p.isManagedOnCommission = isManagedOnCommission
        return p
    }

    private static func value(_ v: Any?) -> Any { v ?? NSNull() }

    /// Patch per `adminUpsertListing`: i soli campi della scheda (non la Gestione) cambiati rispetto a `original`.
    func adminPatch(original: AppFieldsDraft) -> [String: Any] {
        let mine = apply(to: Property()), before = original.apply(to: Property())
        var out: [String: Any] = [:]
        if mine.name != before.name { out["name"] = mine.name }
        if mine.cin != before.cin { out["cin"] = Self.value(mine.cin) }
        if mine.maxGuests != before.maxGuests { out["maxGuests"] = Self.value(mine.maxGuests) }
        if mine.bedrooms != before.bedrooms { out["bedrooms"] = Self.value(mine.bedrooms) }
        if mine.beds != before.beds { out["beds"] = Self.value(mine.beds) }
        if mine.bathrooms != before.bathrooms { out["bathrooms"] = Self.value(mine.bathrooms) }
        if mine.description != before.description { out["description"] = Self.value(mine.description) }
        if mine.amenities != before.amenities { out["amenities"] = mine.amenities }
        if mine.houseRules != before.houseRules { out["houseRules"] = Self.value(mine.houseRules) }
        if mine.checkInTime != before.checkInTime { out["checkInTime"] = Self.value(mine.checkInTime) }
        if mine.checkOutTime != before.checkOutTime { out["checkOutTime"] = Self.value(mine.checkOutTime) }
        return out
    }

    /// I soli campi della scheda (Gestione compresa) per una scrittura diretta in merge: niente
    /// `lastBookingExcelImportAt` né appartenenza, che una copia in memoria potrebbe avere vecchi.
    func directFields() -> [String: Any] {
        let p = apply(to: Property())
        return [
            "name": p.name, "cin": Self.value(p.cin), "maxGuests": Self.value(p.maxGuests), "bedrooms": Self.value(p.bedrooms),
            "beds": Self.value(p.beds), "bathrooms": Self.value(p.bathrooms), "description": Self.value(p.description),
            "amenities": p.amenities, "houseRules": Self.value(p.houseRules), "checkInTime": Self.value(p.checkInTime),
            "checkOutTime": Self.value(p.checkOutTime), "icalUrlAirbnb": Self.value(p.icalUrlAirbnb),
            "icalUrlBooking": Self.value(p.icalUrlBooking), "idAppartamento": Self.value(p.idAppartamento),
            "isManagedOnCommission": isManagedOnCommission,
        ]
    }
}
