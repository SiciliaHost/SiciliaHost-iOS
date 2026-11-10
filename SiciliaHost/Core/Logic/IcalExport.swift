import Foundation

/// Il calendario che l'host incolla su Airbnb e Booking. Lo serve la Function HTTP `exportIcalFeed` del sito (non l'app):
/// prenotazioni dirette confermate di siciliahost.com e date bloccate su SiciliaHost, solo date, senza chiave segreta.
/// Lo stesso indirizzo sta nell'app Android (`IcalExport.kt`) e nella documentazione del sito: cambiarli insieme.
enum IcalExport {
    static let baseURL = "https://us-central1-siciliahostmanager.cloudfunctions.net/exportIcalFeed"

    /// L'indirizzo da incollare per una casa; il `.ics` finale serve ai portali che lo pretendono.
    static func url(propertyId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = propertyId.addingPercentEncoding(withAllowedCharacters: allowed) ?? propertyId
        return "\(baseURL)/\(encoded).ics"
    }
}
