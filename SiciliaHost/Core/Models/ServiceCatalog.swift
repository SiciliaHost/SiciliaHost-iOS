import Foundation

enum ServiceCategory: String, CaseIterable, Sendable {
    case kitchen, bathroom, bedroom, climate, entertainment, outdoor, work, family, safety

    var key: String { rawValue }

    var label: String {
        switch self {
        case .kitchen: return "Cucina"
        case .bathroom: return "Bagno"
        case .bedroom: return "Camera e biancheria"
        case .climate: return "Clima"
        case .entertainment: return "Intrattenimento"
        case .outdoor: return "Esterni e vista"
        case .work: return "Lavoro e connessione"
        case .family: return "Famiglia"
        case .safety: return "Sicurezza"
        }
    }

    static func fromKey(_ key: String?) -> ServiceCategory? {
        key.flatMap { ServiceCategory(rawValue: $0) }
    }
}

/// Un servizio del catalogo. `keywords` sono frasi già normalizzate (minuscole, senza accenti, solo lettere e
/// cifre separate da spazi) cercate come parole intere; `notWith` esclude il servizio se la riga contiene una di
/// quelle frasi (es. "forno a microonde" non è un forno).
struct CatalogService: Equatable, Sendable {
    let key: String
    let category: ServiceCategory
    let label: String
    let keywords: [String]
    var notWith: [String] = []
}

/// Le chiavi sono lo stesso vocabolario di functions/src/properties/serviceCatalog.ts e delle etichette del
/// sito (messages/*.json `services`): aggiungerne una qui significa aggiungerla lì.
enum ServiceCatalog {
    private typealias S = CatalogService
    private static let K = ServiceCategory.kitchen
    private static let B = ServiceCategory.bathroom
    private static let R = ServiceCategory.bedroom
    private static let C = ServiceCategory.climate
    private static let E = ServiceCategory.entertainment
    private static let O = ServiceCategory.outdoor
    private static let W = ServiceCategory.work
    private static let F = ServiceCategory.family
    private static let Y = ServiceCategory.safety

    static let all: [CatalogService] = [
        S(key: "kitchen", category: K, label: "Cucina attrezzata", keywords: ["cucina"]),
        S(key: "refrigerator", category: K, label: "Frigorifero", keywords: ["frigorifero", "frigo"]),
        S(key: "freezer", category: K, label: "Congelatore", keywords: ["congelatore", "freezer"]),
        S(key: "oven", category: K, label: "Forno", keywords: ["forno"], notWith: ["microonde"]),
        S(key: "stove", category: K, label: "Piano cottura", keywords: ["piano cottura", "fornelli", "induzione"]),
        S(key: "microwave", category: K, label: "Microonde", keywords: ["microonde"]),
        S(key: "dishwasher", category: K, label: "Lavastoviglie", keywords: ["lavastoviglie"]),
        S(key: "coffee_machine", category: K, label: "Macchina del caffè", keywords: ["macchina del caffe", "macchina per il caffe", "macchinetta", "nespresso"]),
        S(key: "moka", category: K, label: "Moka", keywords: ["moka"]),
        S(key: "kettle", category: K, label: "Bollitore", keywords: ["bollitore"]),
        S(key: "toaster", category: K, label: "Tostapane", keywords: ["tostapane"]),
        S(key: "cookware", category: K, label: "Pentole e utensili", keywords: ["pentole", "padelle", "utensili da cucina", "utensili per la cottura"]),
        S(key: "dishes_cutlery", category: K, label: "Piatti e posate", keywords: ["stoviglie", "posate", "piatti"]),
        S(key: "wine_glasses", category: K, label: "Bicchieri da vino", keywords: ["bicchieri da vino", "calici"]),
        S(key: "dining_table", category: K, label: "Tavolo da pranzo", keywords: ["tavolo da pranzo"]),

        S(key: "hair_dryer", category: B, label: "Asciugacapelli", keywords: ["asciugacapelli", "phon", "fon"]),
        S(key: "shower", category: B, label: "Doccia", keywords: ["doccia"], notWith: ["esterna", "aperto"]),
        S(key: "bathtub", category: B, label: "Vasca da bagno", keywords: ["vasca da bagno", "vasca"], notWith: ["bambini", "bambino"]),
        S(key: "bidet", category: B, label: "Bidet", keywords: ["bidet"]),
        S(key: "towels", category: B, label: "Asciugamani", keywords: ["asciugamani"], notWith: ["spiaggia"]),
        S(key: "toiletries", category: B, label: "Prodotti da bagno", keywords: ["shampoo", "bagnoschiuma", "balsamo", "sapone", "gel doccia", "prodotti da bagno"]),
        S(key: "washing_machine", category: B, label: "Lavatrice", keywords: ["lavatrice"]),
        S(key: "dryer", category: B, label: "Asciugatrice", keywords: ["asciugatrice"]),

        S(key: "bed_linen", category: R, label: "Lenzuola", keywords: ["biancheria da letto", "lenzuola", "lenzuolo"]),
        S(key: "iron", category: R, label: "Ferro da stiro", keywords: ["ferro da stiro", "asse da stiro"]),
        S(key: "clothes_rack", category: R, label: "Stendibiancheria", keywords: ["stendibiancheria", "stendino", "stenditoio"]),
        S(key: "wardrobe", category: R, label: "Armadio", keywords: ["armadio", "guardaroba", "appendiabiti"]),
        S(key: "extra_blankets", category: R, label: "Coperte e cuscini extra", keywords: ["cuscini e coperte extra", "coperte extra", "cuscini extra", "coperte e cuscini"]),
        S(key: "blackout_curtains", category: R, label: "Tende oscuranti", keywords: ["tende oscuranti"]),
        S(key: "mosquito_nets", category: R, label: "Zanzariere", keywords: ["zanzariera", "zanzariere"]),

        S(key: "air_conditioning", category: C, label: "Aria condizionata", keywords: ["aria condizionata", "condizionatore", "climatizzatore", "climatizzazione"]),
        S(key: "heating", category: C, label: "Riscaldamento", keywords: ["riscaldamento"]),
        S(key: "fan", category: C, label: "Ventilatore", keywords: ["ventilatore"]),
        S(key: "fireplace", category: C, label: "Camino", keywords: ["camino", "caminetto", "stufa a legna"]),

        S(key: "tv", category: E, label: "TV", keywords: ["tv", "televisione", "televisore"]),
        S(key: "streaming", category: E, label: "Servizi di streaming", keywords: ["netflix", "prime video", "amazon prime", "disney", "streaming"]),
        S(key: "sound_system", category: E, label: "Impianto audio", keywords: ["sistema audio", "impianto audio", "sistema stereo", "altoparlante bluetooth"]),
        S(key: "books", category: E, label: "Libri", keywords: ["libri"]),
        S(key: "board_games", category: E, label: "Giochi da tavolo", keywords: ["giochi da tavolo", "giochi di societa"]),

        S(key: "terrace_balcony", category: O, label: "Terrazzo o balcone", keywords: ["terrazzo", "balcone", "terrazza", "patio"]),
        S(key: "garden", category: O, label: "Giardino", keywords: ["giardino", "cortile"]),
        S(key: "pool", category: O, label: "Piscina", keywords: ["piscina"]),
        S(key: "bbq", category: O, label: "Barbecue", keywords: ["barbecue", "bbq"]),
        S(key: "outdoor_furniture", category: O, label: "Mobili da esterno", keywords: ["mobili da esterno", "mobili da giardino", "arredi da esterno", "sedie a sdraio"]),
        S(key: "sea_view", category: O, label: "Vista mare", keywords: ["vista mare", "vista sul mare", "affaccio sul mare", "fronte mare"]),
        S(key: "mountain_view", category: O, label: "Vista montagna", keywords: ["vista montagna", "vista sulla montagna", "vista sulle montagne"]),
        S(key: "beach_gear", category: O, label: "Attrezzatura da spiaggia", keywords: ["attrezzatura da spiaggia", "articoli da spiaggia", "asciugamani da spiaggia", "ombrellone", "lettini"]),
        S(key: "outdoor_shower", category: O, label: "Doccia esterna", keywords: ["doccia esterna", "doccia all aperto"]),
        S(key: "parking", category: O, label: "Parcheggio", keywords: ["parcheggio"]),

        S(key: "wifi", category: W, label: "Wi-Fi", keywords: ["wifi", "wi fi"]),
        S(key: "workspace", category: W, label: "Spazio per lavorare", keywords: ["spazio di lavoro", "spazio per lavorare", "scrivania", "postazione di lavoro"]),
        S(key: "printer", category: W, label: "Stampante", keywords: ["stampante"]),

        S(key: "crib", category: F, label: "Culla", keywords: ["culla", "lettino"]),
        S(key: "high_chair", category: F, label: "Seggiolone", keywords: ["seggiolone"]),
        S(key: "baby_bath", category: F, label: "Vaschetta per il bagnetto", keywords: ["vaschetta per il bagnetto", "vaschetta bagnetto", "bagnetto per bambini", "vasca da bagno per bambini"]),
        S(key: "safety_gates", category: F, label: "Cancelletti di sicurezza", keywords: ["cancelletti di sicurezza", "cancelletto", "protezione per bambini"]),
        S(key: "toys", category: F, label: "Giocattoli", keywords: ["giocattoli", "giochi per bambini"]),

        S(key: "smoke_detector", category: Y, label: "Rilevatore di fumo", keywords: ["rilevatore di fumo", "rilevatori di fumo", "allarme antincendio"]),
        S(key: "co_detector", category: Y, label: "Rilevatore di monossido", keywords: ["monossido di carbonio", "rilevatore di monossido"]),
        S(key: "fire_extinguisher", category: Y, label: "Estintore", keywords: ["estintore"]),
        S(key: "first_aid_kit", category: Y, label: "Kit di primo soccorso", keywords: ["kit di primo soccorso", "primo soccorso", "kit pronto soccorso"]),
        S(key: "safe", category: Y, label: "Cassaforte", keywords: ["cassaforte", "cassetta di sicurezza"]),
    ]

    static let byKey: [String: CatalogService] = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    static func label(for key: String) -> String { byKey[key]?.label ?? key }
}
