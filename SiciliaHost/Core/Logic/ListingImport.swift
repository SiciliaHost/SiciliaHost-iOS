import Foundation

// MARK: Annuncio Airbnb

struct AirbnbListingData: Equatable {
    var name: String?
    var description: String?
    var maxGuests: Int?
    var bedrooms: Int?
    var beds: Int?
    var bathrooms: Double?
}

private func firstGroup(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}

/// Legge i campi disponibili nell'HTML statico di un annuncio Airbnb: il blob JSON-LD "VacationRental" (nome,
/// descrizione, ospiti) e il meta og:title (camere/letti/bagni, testo libero — es. "4 camere da letto · 6 letti ·
/// 2 bagni"). Servizi, regole della casa e orari di check-in/out non sono nell'HTML iniziale (arrivano via GraphQL
/// dal JS del browser dopo il render) e restano fuori scope: i campi risultano nil, non un errore.
func parseAirbnbHtml(_ html: String) -> AirbnbListingData {
    var jsonLd: [String: Any]?
    if let regex = try? NSRegularExpression(
        pattern: #"<script type="application/ld\+json">(.*?)</script>"#, options: [.dotMatchesLineSeparators]
    ) {
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let object = (try? JSONSerialization.jsonObject(with: Data(html[range].utf8))) as? [String: Any],
                  object["@type"] as? String == "VacationRental" else { continue }
            jsonLd = object
            break
        }
    }

    let ogTitle = firstGroup(#"<meta property="og:title" content="([^"]*)""#, in: html)

    var maxGuests: Int?
    if let occupancy = (jsonLd?["containsPlace"] as? [String: Any])?["occupancy"] as? [String: Any],
       let value = (occupancy["value"] as? NSNumber)?.intValue, value > 0 {
        maxGuests = value
    }

    func nonBlank(_ value: Any?) -> String? {
        guard let s = value as? String, !s.trimmed.isEmpty else { return nil }
        return s
    }

    return AirbnbListingData(
        name: nonBlank(jsonLd?["name"]),
        description: nonBlank(jsonLd?["description"]),
        maxGuests: maxGuests,
        bedrooms: ogTitle.flatMap { firstGroup(#"(\d+)\s*camer[ae]"#, in: $0, options: .caseInsensitive) }.flatMap { Int($0) },
        beds: ogTitle.flatMap { firstGroup(#"(\d+)\s*lett[oi]"#, in: $0, options: .caseInsensitive) }.flatMap { Int($0) },
        bathrooms: ogTitle.flatMap { firstGroup(#"([\d,.]+)\s*bagn[oi]"#, in: $0, options: .caseInsensitive) }
            .flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    )
}

/// Scarica l'HTML dell'annuncio e lo passa a `parseAirbnbHtml`. Ritorna nil per qualunque errore di rete/parsing —
/// chi chiama mostra un messaggio e lascia compilare a mano.
func scrapeAirbnbListing(url: String) async -> AirbnbListingData? {
    guard let target = URL(string: url) else { return nil }
    var request = URLRequest(url: target)
    // Senza uno User-Agent da browser Airbnb risponde 403 (anti-bot su UA/IP, verificato sull'Android). Se in futuro
    // bloccasse anche questo, il prossimo passo è un WebView headless o le API GraphQL interne di Airbnb.
    request.setValue(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        forHTTPHeaderField: "User-Agent"
    )
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        return parseAirbnbHtml(String(decoding: data, as: UTF8.self))
    } catch {
        return nil
    }
}

// MARK: Geocoding (Nominatim / OpenStreetMap)

/// User-Agent per tutte le richieste ai server di OpenStreetMap (tile e Nominatim). La tile usage policy
/// (operations.osmfoundation.org/policies/tiles/) vuole un'identificazione dell'applicazione e un modo per contattare
/// chi la gestisce: l'Android usava un identificativo di default (`com.example…`) e OSM rispondeva 200 con un tile
/// "accesso negato" senza errori visibili. Niente dati personali: solo nome app, sito e email di contatto.
let osmUserAgent = "SiciliaHostManager/1.0 (iOS; +https://siciliahost.com; info@siciliahost.com)"

struct GeocodeResult: Equatable {
    let label: String
    let point: LatLng
}

/// Solo funzione pura, testata: `json` deve essere l'array di `format=jsonv2`. Lancia `BookingImportError`-like
/// "Risposta non valida" se non è un array.
func parseNominatimResults(_ json: String) throws -> [GeocodeResult] {
    guard let array = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else {
        throw NominatimError.invalidResponse
    }
    func number(_ value: Any?) -> Double? {
        // `optString` di org.json converte anche i numeri in testo: si accettano entrambi.
        if let s = value as? String { return Double(s) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
    var out: [GeocodeResult] = []
    for item in array {
        guard let object = item as? [String: Any], let lat = number(object["lat"]), let lon = number(object["lon"]),
              (-90.0 ... 90.0).contains(lat), (-180.0 ... 180.0).contains(lon) else { continue }
        let name = (object["display_name"] as? String) ?? ""
        let label = name.trimmed.isEmpty ? String(format: "%.5f, %.5f", lat, lon) : name
        out.append(GeocodeResult(label: label, point: LatLng(lat: lat, lng: lon)))
    }
    return out
}

enum NominatimError: LocalizedError, Equatable {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Risposta non valida"
        case .http(let code): return "HTTP \(code)"
        }
    }
}

/// Ricerca indirizzi con Nominatim. Policy: al massimo 1 richiesta/s, user-agent che identifica l'app, niente
/// autocompletamento mentre si digita → il chiamante cerca solo su tocco di "Cerca".
struct NominatimClient {
    var userAgent = osmUserAgent

    /// Fino a 5 risultati in Italia. Sotto i 3 caratteri non fa nessuna richiesta.
    func search(_ query: String) async -> Result<[GeocodeResult], Error> {
        let q = query.trimmed
        if q.count < 3 { return .success([]) }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"), URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "countrycodes", value: "it"), URLQueryItem(name: "accept-language", value: "it"),
            URLQueryItem(name: "q", value: q),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw NominatimError.http(http.statusCode) }
            return .success(try parseNominatimResults(String(decoding: data, as: UTF8.self)))
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            return .failure(error)
        }
    }
}
