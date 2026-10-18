import Foundation

/// Stato di un annuncio sul sito. Specchio di `functions/src/listing/listingStatus.ts`.
enum ListingStatus: String, CaseIterable, Sendable {
    case draft, pending, approved, rejected

    /// Il valore salvato su Firestore (`listingStatus`).
    var wire: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Bozza"
        case .pending: return "Da approvare"
        case .approved: return "Approvato"
        case .rejected: return "Rifiutato"
        }
    }

    static func fromWire(_ value: String?) -> ListingStatus? {
        value.flatMap { ListingStatus(rawValue: $0) }
    }
}

/// Il campo manca nelle case già online prima dell'approvazione: contano come approvate.
func effectiveListingStatus(stored: String?, publishedOnSite: Bool?) -> ListingStatus {
    ListingStatus.fromWire(stored) ?? (publishedOnSite == true ? .approved : .draft)
}

/// Motivi dell'ultimo rifiuto, letti dal documento della casa.
struct SiteRejection: Codable, Equatable, Sendable {
    var reasons: String?
    var at: Int64?
    var by: String?
}

extension SiteRejection {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reasons = c.optional(.reasons)
        at = c.optional(.at)
        by = c.optional(.by)
    }
}

/// Sul percorso del sito = ha scelto di pubblicare (`siteTrack`, scritto da `startSitePublication`), oppure ha
/// già uno stato salvato di invio, oppure è già online, oppure ha già contenuti del sito (zona, foto o prezzo).
func isOnSiteTrack(siteTrack: Bool?, listingStatus: String?, publishedOnSite: Bool?, hasSiteContent: Bool = false) -> Bool {
    siteTrack == true
        || hasSiteContent
        || [ListingStatus.pending.wire, ListingStatus.approved.wire, ListingStatus.rejected.wire].contains(listingStatus ?? "")
        || publishedOnSite == true
}

/// I prezzi per data dal calendario hanno senso solo con un annuncio approvato.
func canEditCalendarPrices(_ status: ListingStatus) -> Bool { status == .approved }

/// Gli id delle case con annuncio approvato, dato lo stato di ciascuna.
func approvedIds(_ statuses: [String: ListingStatus]) -> Set<String> {
    Set(statuses.filter { canEditCalendarPrices($0.value) }.keys)
}
