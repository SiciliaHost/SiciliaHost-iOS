import Foundation

// Vista di lettura dei campi che appartengono al sito sul documento condiviso `properties/{id}`.
// Solo lettura: le scritture passano dalla callable `upsertProperty`. Campi sconosciuti ignorati.
// Ogni struttura legge in modo tollerante (campo mancante o di tipo inatteso = nil/default).

struct SiteCancellationPolicy: Codable, Equatable, Sendable {
    var freeUntilDaysBefore: Int?
    init(freeUntilDaysBefore: Int? = nil) { self.freeUntilDaysBefore = freeUntilDaysBefore }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freeUntilDaysBefore = c.optional(.freeUntilDaysBefore)
    }
}

struct SiteCoordinates: Codable, Equatable, Sendable {
    var lat: Double?
    var lng: Double?
    init(lat: Double? = nil, lng: Double? = nil) { self.lat = lat; self.lng = lng }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = c.optional(.lat)
        lng = c.optional(.lng)
    }
}

struct SiteWifiInfo: Codable, Equatable, Sendable {
    var ssid: String?
    var password: String?
    init(ssid: String? = nil, password: String? = nil) { self.ssid = ssid; self.password = password }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ssid = c.optional(.ssid)
        password = c.optional(.password)
    }
}

struct SiteManagerContact: Codable, Equatable, Sendable {
    var name: String?
    var phone: String?
    init(name: String? = nil, phone: String? = nil) { self.name = name; self.phone = phone }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.optional(.name)
        phone = c.optional(.phone)
    }
}

struct SiteService: Codable, Equatable, Sendable {
    var key = ""
    var name: String?
    var category = ""
    var paid: Bool?
    var note: String?
    init(key: String = "", name: String? = nil, category: String = "", paid: Bool? = nil, note: String? = nil) {
        self.key = key; self.name = name; self.category = category; self.paid = paid; self.note = note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.value(.key, "")
        name = c.optional(.name)
        category = c.value(.category, "")
        paid = c.optional(.paid)
        note = c.optional(.note)
    }
}

struct SiteRules: Codable, Equatable, Sendable {
    var pets: String?
    var smoking: String?
    var parties: String?
    var children: String?
    var quietHours: String?
    var minAge: Int?
    var note: String?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pets = c.optional(.pets)
        smoking = c.optional(.smoking)
        parties = c.optional(.parties)
        children = c.optional(.children)
        quietHours = c.optional(.quietHours)
        minAge = c.optional(.minAge)
        note = c.optional(.note)
    }
}

struct SiteAccess: Codable, Equatable, Sendable {
    var floor: Int?
    var elevator: Bool?
    var stepFree: Bool?
    var parking: String?
    var parkingNote: String?
    var checkInType: String?
    var checkInNote: String?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floor = c.optional(.floor)
        elevator = c.optional(.elevator)
        stepFree = c.optional(.stepFree)
        parking = c.optional(.parking)
        parkingNote = c.optional(.parkingNote)
        checkInType = c.optional(.checkInType)
        checkInNote = c.optional(.checkInNote)
    }
}

struct SiteTouristTax: Codable, Equatable, Sendable {
    var perPersonPerNight: Double?
    var maxNights: Int?
    var exemptUnderAge: Int?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        perPersonPerNight = c.optional(.perPersonPerNight)
        maxNights = c.optional(.maxNights)
        exemptUnderAge = c.optional(.exemptUnderAge)
    }
}

struct SiteFees: Codable, Equatable, Sendable {
    var touristTax: SiteTouristTax?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        touristTax = c.optional(.touristTax)
    }
}

struct SiteNearby: Codable, Equatable, Sendable {
    var type: String?
    var name: String?
    var minutes: Int?
    var mode: String?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.optional(.type)
        name = c.optional(.name)
        minutes = c.optional(.minutes)
        mode = c.optional(.mode)
    }
}

struct SiteHost: Codable, Equatable, Sendable {
    var name: String?
    var languages: [String] = []
    var email: String?
    var phone: String?
    var whatsapp: Bool?
    var showPhone: Bool?
    var showEmail: Bool?
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.optional(.name)
        languages = c.value(.languages, [])
        email = c.optional(.email)
        phone = c.optional(.phone)
        whatsapp = c.optional(.whatsapp)
        showPhone = c.optional(.showPhone)
        showEmail = c.optional(.showEmail)
    }
}

struct SiteBed: Codable, Equatable, Sendable {
    var type: String?
    var count: Int?
    init(type: String? = nil, count: Int? = nil) { self.type = type; self.count = count }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.optional(.type)
        count = c.optional(.count)
    }
}

struct SiteSleepingRoom: Codable, Equatable, Sendable {
    var kind: String?
    var beds: [SiteBed] = []
    init(kind: String? = nil, beds: [SiteBed] = []) { self.kind = kind; self.beds = beds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.optional(.kind)
        beds = c.value(.beds, [])
    }
}

struct PropertySiteContent: Identifiable, Codable, Equatable, Sendable {
    var id = ""
    // Campi dell'app, solo per mostrare l'italiano di riferimento nelle traduzioni.
    var name = ""
    var description: String?
    var houseRules: String?
    // Campi del sito.
    var publishedOnSite: Bool?
    /// Scritto SOLO dalle callable submit/withdraw/reviewListing. Assente = dedotto da `publishedOnSite`.
    var listingStatus: String?
    /// "Ha scelto di pubblicare sul sito": scritto SOLO dalla callable `startSitePublication`.
    var siteTrack: Bool?
    var submittedAt: Int64?
    var rejection: SiteRejection?
    var zone: String?
    var basePricePerNight: Double?
    var cleaningFee: Double?
    var depositPercentage: Double?
    /// Extra a notte per numero di ospiti ("3" -> euro). Scritto solo dalla callable `setGuestSurcharges`.
    var guestSurcharges: [String: Double]?
    var cancellationPolicy: SiteCancellationPolicy?
    var requiresManualConfirmation: Bool?
    var photos: [String] = []
    var coordinates: SiteCoordinates?
    var address: String?
    var publicArea: SiteCoordinates?
    var wifiInfo: SiteWifiInfo?
    var managerContact: SiteManagerContact?
    var localTips: [String: String]?
    var departureChecklist: [String: String]?
    var titleTranslations: [String: String]?
    var descriptionTranslations: [String: String]?
    var houseRulesTranslations: [String: String]?
    // Contenuti ricchi della pagina di dettaglio.
    /// Vecchio testo libero dell'app, solo per convertirlo in servizi.
    var amenities: [String] = []
    /// nil = campo assente (mai salvato); [] = l'host ha tolto tutti i servizi. Non sono la stessa cosa.
    var services: [SiteService]?
    var rulesStructured: SiteRules?
    var access: SiteAccess?
    var fees: SiteFees?
    var nearby: [SiteNearby] = []
    var transportNote: String?
    var host: SiteHost?
    /// Stanze con i letti. La culla è un letto "crib": il sito la mostra come extra opzionale.
    var sleepingArrangements: [SiteSleepingRoom]?

    var status: ListingStatus { effectiveListingStatus(stored: listingStatus, publishedOnSite: publishedOnSite) }

    var onSiteTrack: Bool {
        isOnSiteTrack(
            siteTrack: siteTrack, listingStatus: listingStatus, publishedOnSite: publishedOnSite,
            hasSiteContent: !(zone ?? "").trimmed.isEmpty || !photos.isEmpty || basePricePerNight != nil
        )
    }
}

extension PropertySiteContent {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, "")
        name = c.value(.name, "")
        description = c.optional(.description)
        houseRules = c.optional(.houseRules)
        publishedOnSite = c.optional(.publishedOnSite)
        listingStatus = c.optional(.listingStatus)
        siteTrack = c.optional(.siteTrack)
        submittedAt = c.optional(.submittedAt)
        rejection = c.optional(.rejection)
        zone = c.optional(.zone)
        basePricePerNight = c.optional(.basePricePerNight)
        cleaningFee = c.optional(.cleaningFee)
        depositPercentage = c.optional(.depositPercentage)
        guestSurcharges = c.optional(.guestSurcharges)
        cancellationPolicy = c.optional(.cancellationPolicy)
        requiresManualConfirmation = c.optional(.requiresManualConfirmation)
        photos = c.value(.photos, [])
        coordinates = c.optional(.coordinates)
        address = c.optional(.address)
        publicArea = c.optional(.publicArea)
        wifiInfo = c.optional(.wifiInfo)
        managerContact = c.optional(.managerContact)
        localTips = c.optional(.localTips)
        departureChecklist = c.optional(.departureChecklist)
        titleTranslations = c.optional(.titleTranslations)
        descriptionTranslations = c.optional(.descriptionTranslations)
        houseRulesTranslations = c.optional(.houseRulesTranslations)
        amenities = c.value(.amenities, [])
        services = c.optional(.services)
        rulesStructured = c.optional(.rulesStructured)
        access = c.optional(.access)
        fees = c.optional(.fees)
        nearby = c.value(.nearby, [])
        transportNote = c.optional(.transportNote)
        host = c.optional(.host)
        sleepingArrangements = c.optional(.sleepingArrangements)
    }
}
