import Foundation

/// Errore del check-in Alloggiati: il messaggio è per l'utente. Porta delle tre eccezioni di `AlloggiatiSoap.kt`:
/// - `.refused` = `AlloggiatiException`: il servizio ha detto di no (credenziali, token, tabella, ricevuta, date).
/// - `.rejected` = `AlloggiatiRejectedException` (sottotipo di `.refused` su Android): rifiuto CERTO di Test/Send, niente
///   acquisito; solo in questo caso le schede si sbloccano e si possono rinviare.
/// - `.uncertain` = `AlloggiatiUncertainException`: l'esito non è noto (la richiesta può essere arrivata): non riprovare
///   senza controllare la ricevuta.
struct AlloggiatiError: LocalizedError, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case refused, rejected, uncertain }

    let kind: Kind
    let message: String

    init(_ kind: Kind = .refused, _ message: String) {
        self.kind = kind
        self.message = message
    }

    var errorDescription: String? { message }

    /// Come `e is AlloggiatiException` su Android: anche il rifiuto certo conta.
    var isRefusal: Bool { kind == .refused || kind == .rejected }

    static func refused(_ message: String) -> AlloggiatiError { AlloggiatiError(.refused, message) }
    static func rejected(_ message: String) -> AlloggiatiError { AlloggiatiError(.rejected, message) }
    static func uncertain(_ message: String) -> AlloggiatiError { AlloggiatiError(.uncertain, message) }
}

/// Testo di un esito incerto del trasporto o di una risposta non chiara (`UNCERTAIN_TRANSPORT_MESSAGE`).
let alloggiatiUncertainTransportMessage =
    "Risposta del servizio non chiara: controlla la ricevuta sul portale prima di riprovare"

/// Parti pure del protocollo SOAP di Alloggiati Web (porta di `AlloggiatiSoap.kt`, che viene da
/// `functions/src/alloggiati/soap.ts`). L'app parla direttamente con il servizio della Polizia: nessun dato passa dai
/// server di SiciliaHost.
enum AlloggiatiSoap {
    static let url = URL(string: "https://alloggiatiweb.poliziadistato.it/service/service.asmx")!

    static func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Decodifica le entità XML dei testi d'errore (`&amp;` per ultimo, così «&amp;lt;» resta «&lt;»).
    static func unesc(_ value: String) -> String {
        value.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func envelope(_ method: String, _ inner: String) -> String {
        "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:all=\"AlloggiatiService\">"
            + "<soap:Header/><soap:Body><all:\(method)>\(inner)</all:\(method)></soap:Body></soap:Envelope>"
    }

    /// Esatto sul nome del tag: token, CSV, PDF.
    static func extractText(_ xml: String, _ tag: String) -> String {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return "" }
        return String(xml[open.upperBound..<close.lowerBound])
    }

    /// La specifica usa maiuscole incoerenti (errorCod / ErroreCod): sul nome del tag non si distingue.
    static func extractTextCI(_ xml: String, _ tag: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)>([\\s\\S]*?)</\(tag)>", options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return "" }
        return String(xml[range])
    }

    static func extractBool(_ xml: String, _ tag: String) -> Bool {
        extractTextCI(xml, tag).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private static func firstNonEmpty(_ values: String...) -> String { values.first { !$0.isEmpty } ?? "" }
    static func erroreCod(_ xml: String) -> String {
        unesc(firstNonEmpty(extractTextCI(xml, "ErroreCod"), extractTextCI(xml, "errorCod")))
    }
    static func erroreDes(_ xml: String) -> String {
        unesc(firstNonEmpty(extractTextCI(xml, "ErroreDes"), extractTextCI(xml, "errorDes")))
    }
    static func erroreDettaglio(_ xml: String) -> String {
        unesc(firstNonEmpty(extractTextCI(xml, "ErroreDettaglio"), extractTextCI(xml, "erroreDettaglio")))
    }

    private static let blockPattern = "<EsitoOperazioneServizio>([\\s\\S]*?)</EsitoOperazioneServizio>"

    /// Esito a livello di chiamata: nei messaggi d'errore (token scaduto, credenziali errate) non ci sono blocchi per riga,
    /// quindi ciò che precede il primo EsitoOperazioneServizio decide la chiamata. Un esito falso è un rifiuto certo
    /// (`.rejected`) solo se ha un codice o un testo d'errore, nessun esito per riga e nessuna schedina valida; altrimenti
    /// l'esito è incerto (`.uncertain`), perché alcune schede potrebbero essere state acquisite.
    static func parseEsito(_ xml: String) throws -> ElencoSchedineEsito {
        let firstBlock = xml.range(of: "<EsitoOperazioneServizio>", options: .caseInsensitive)
        let head = firstBlock.map { String(xml[..<$0.lowerBound]) } ?? xml
        let validiText = extractTextCI(xml, "SchedineValide").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extractBool(head, "esito") {
            let hasError = !erroreCod(head).trimmed.isEmpty || !erroreDes(head).trimmed.isEmpty
            let noneValid = validiText.isEmpty || Int(validiText) == 0
            if hasError && firstBlock == nil && noneValid {
                let message = [erroreDes(head), erroreDettaglio(head)].filter { !$0.trimmed.isEmpty }.joined(separator: ": ")
                throw AlloggiatiError.rejected(message.isEmpty ? "Il servizio ha rifiutato la richiesta" : message)
            }
            throw AlloggiatiError.uncertain(alloggiatiUncertainTransportMessage)
        }
        let validi = Int(validiText) ?? 0
        guard let regex = try? NSRegularExpression(pattern: blockPattern, options: .caseInsensitive) else {
            return ElencoSchedineEsito(schedineValide: validi, dettaglio: [])
        }
        let dettaglio = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match -> EsitoSingolo? in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            let block = String(xml[range])
            return EsitoSingolo(
                esito: extractBool(block, "esito"), errorCod: erroreCod(block),
                errorDes: erroreDes(block), erroreDettaglio: erroreDettaglio(block)
            )
        }
        return ElencoSchedineEsito(schedineValide: validi, dettaglio: dettaglio)
    }

    /// Una risposta senza busta SOAP (pagina d'errore, proxy...) non dice se l'invio è andato a buon fine.
    static func requireSoapBody(_ body: String) throws -> String {
        guard body.range(of: "Envelope", options: .caseInsensitive) != nil else {
            throw AlloggiatiError.uncertain(alloggiatiUncertainTransportMessage)
        }
        return body
    }
}
