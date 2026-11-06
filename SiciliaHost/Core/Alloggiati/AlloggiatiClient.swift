import Foundation

/// Trasporto SOAP: in produzione HTTPS verso la Polizia, nei test un finto.
protocol SoapTransport: Sendable {
    func post(_ body: String) async throws -> String
}

/// HTTPS con `URLSession`. Un errore prima che la richiesta parta (niente rete, host irraggiungibile, TLS) si rilancia
/// così com'è: riprovare è sicuro. Da quando la richiesta può essere arrivata (tempo scaduto, connessione persa a metà,
/// risposta senza busta SOAP) l'esito è incerto (`.uncertain`): l'Android distingue scrittura e lettura dello stream,
/// `URLSession` non lo permette, quindi si decide dal codice di `URLError`.
struct URLSessionSoapTransport: SoapTransport {
    var url: URL = AlloggiatiSoap.url

    /// Errori per cui la richiesta certamente non è arrivata al servizio.
    static func requestNeverSent(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        switch e.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection, .internationalRoamingOff,
             .dataNotAllowed, .callIsActive, .badURL, .unsupportedURL:
            return true
        default:
            return false
        }
    }

    func post(_ body: String) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let data: Data
        do {
            // Un rifiuto SOAP arriva anche con HTTP 500: il corpo dice il perché, quindi lo stato HTTP non si guarda.
            let (received, _) = try await URLSession.shared.data(for: request)
            data = received
        } catch {
            if Self.requestNeverSent(error) { throw error }
            throw AlloggiatiError.uncertain(alloggiatiUncertainTransportMessage)
        }
        return try AlloggiatiSoap.requireSoapBody(String(decoding: data, as: UTF8.self))
    }
}

/// Chiamate ad Alloggiati Web (porta di `AlloggiatiClient.kt`). Il token resta in memoria 10 minuti, mai su disco; la
/// chiave comprende tutte le credenziali, così cambiarle non riusa il vecchio token. Un solo client per processo.
actor AlloggiatiClient {
    static let shared = AlloggiatiClient()

    private static let tokenTtlMs: Int64 = 10 * 60 * 1000

    private let transport: SoapTransport
    private let clock: @Sendable () -> Int64
    private var tokens: [String: (token: String, validUntil: Int64)] = [:]

    init(transport: SoapTransport = URLSessionSoapTransport(),
         clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.transport = transport
        self.clock = clock
    }

    private static func tokenKey(_ c: AlloggiatiCredentials) -> String { "\(c.utente)\u{0}\(c.password)\u{0}\(c.wsKey)" }

    func token(_ c: AlloggiatiCredentials) async throws -> String {
        let key = Self.tokenKey(c)
        if let hit = tokens[key], clock() < hit.validUntil { return hit.token }
        let xml = try await transport.post(AlloggiatiSoap.envelope(
            "GenerateToken",
            "<all:Utente>\(AlloggiatiSoap.esc(c.utente))</all:Utente><all:Password>\(AlloggiatiSoap.esc(c.password))</all:Password>"
                + "<all:WsKey>\(AlloggiatiSoap.esc(c.wsKey))</all:WsKey>"
        ))
        guard AlloggiatiSoap.extractBool(xml, "esito") else {
            let des = AlloggiatiSoap.erroreDes(xml)
            throw AlloggiatiError.refused(des.isEmpty ? "Token rifiutato dal servizio" : des)
        }
        let token = AlloggiatiSoap.extractText(xml, "token")
        guard !token.isEmpty else { throw AlloggiatiError.refused("Il servizio non ha restituito un token") }
        tokens[key] = (token, clock() + Self.tokenTtlMs)
        return token
    }

    func clearTokens() { tokens.removeAll() }

    /// Dimentica il token di queste credenziali (rifiutato dal servizio).
    func invalidate(_ c: AlloggiatiCredentials) { tokens[Self.tokenKey(c)] = nil }

    private func schedine(_ method: String, utente: String, token: String, idAppartamento: Int, rows: [String]) async throws -> ElencoSchedineEsito {
        let list = rows.map { "<all:string>\(AlloggiatiSoap.esc($0))</all:string>" }.joined()
        let xml = try await transport.post(AlloggiatiSoap.envelope(
            method,
            "<all:Utente>\(AlloggiatiSoap.esc(utente))</all:Utente><all:token>\(AlloggiatiSoap.esc(token))</all:token>"
                + "<all:ElencoSchedine>\(list)</all:ElencoSchedine><all:IdAppartamento>\(idAppartamento)</all:IdAppartamento>"
        ))
        return try AlloggiatiSoap.parseEsito(xml)
    }

    func test(utente: String, token: String, idAppartamento: Int, rows: [String]) async throws -> ElencoSchedineEsito {
        try await schedine("GestioneAppartamenti_Test", utente: utente, token: token, idAppartamento: idAppartamento, rows: rows)
    }

    func send(utente: String, token: String, idAppartamento: Int, rows: [String]) async throws -> ElencoSchedineEsito {
        try await schedine("GestioneAppartamenti_Send", utente: utente, token: token, idAppartamento: idAppartamento, rows: rows)
    }

    func table(utente: String, token: String, tipo: String) async throws -> String {
        let xml = try await transport.post(AlloggiatiSoap.envelope(
            "Tabella",
            "<all:Utente>\(AlloggiatiSoap.esc(utente))</all:Utente><all:token>\(AlloggiatiSoap.esc(token))</all:token>"
                + "<all:tipo>\(AlloggiatiSoap.esc(tipo))</all:tipo>"
        ))
        guard AlloggiatiSoap.extractBool(xml, "esito") else {
            let des = AlloggiatiSoap.erroreDes(xml)
            throw AlloggiatiError.refused(des.isEmpty ? "Tabella non disponibile" : des)
        }
        return AlloggiatiSoap.extractText(xml, "CSV")
    }

    /// `dateIso` = yyyy-MM-dd. Il servizio dà le ricevute degli ultimi 30 giorni, oggi escluso.
    func receipt(utente: String, token: String, dateIso: String) async throws -> Data {
        let xml = try await transport.post(AlloggiatiSoap.envelope(
            "Ricevuta",
            "<all:Utente>\(AlloggiatiSoap.esc(utente))</all:Utente><all:token>\(AlloggiatiSoap.esc(token))</all:token>"
                + "<all:Data>\(AlloggiatiSoap.esc(dateIso))T00:00:00</all:Data>"
        ))
        guard AlloggiatiSoap.extractBool(xml, "esito") else {
            let des = AlloggiatiSoap.erroreDes(xml)
            throw AlloggiatiError.refused(des.isEmpty ? "Ricevuta non disponibile" : des)
        }
        let pdf = AlloggiatiSoap.extractText(xml, "PDF").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdf.isEmpty else { throw AlloggiatiError.refused("Ricevuta non disponibile") }
        guard let bytes = Data(base64Encoded: pdf, options: .ignoreUnknownCharacters), !bytes.isEmpty else {
            throw AlloggiatiError.refused("Ricevuta non leggibile")
        }
        return bytes
    }
}
