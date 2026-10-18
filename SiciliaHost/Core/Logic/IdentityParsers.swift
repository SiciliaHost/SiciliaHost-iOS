import Foundation

// MARK: Codice MRZ dei documenti d'identità

struct MrzData: Equatable {
    let cognome: String
    let nome: String
    let sesso: String
    let dataNascita: String
    let numeroDocumento: String
    let tipoDocumento: String
    let issuingCountryIso: String
    let statoNascitaIso: String
    let cittadinanzaIso: String
    let checkDigitsValid: Bool
}

enum MrzParser {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")

    /// Legge il testo riconosciuto dalla fotocamera: passaporto (TD3: 2 righe da 44) o carta d'identità (TD1: 3 righe da 30).
    static func parse(_ rawText: String) -> MrzData? {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmed.uppercased() }
            .filter { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }

        if lines.count >= 2, lines[0].count == 44, lines[1].count == 44 {
            return parseTD3(lines[0], lines[1])
        }
        if lines.count >= 3, lines[0].count == 30, lines[1].count == 30, lines[2].count == 30 {
            return parseTD1(lines[0], lines[1], lines[2])
        }
        return nil
    }

    private static func slice(_ chars: [Character], _ from: Int, _ to: Int) -> String { String(chars[from ..< to]) }

    private static func trimFiller(_ text: String) -> String {
        var s = Substring(text)
        while s.last == "<" { s = s.dropLast() }
        return String(s)
    }

    static func parseTD3(_ line1: String, _ line2: String) -> MrzData? {
        let l1 = Array(line1), l2 = Array(line2)
        guard l1.count >= 44, l2.count >= 44 else { return nil }

        let issuing = slice(l1, 2, 5)
        let (cognome, nome) = parseName(slice(l1, 5, 44))
        let docNumber = slice(l2, 0, 9)
        let docCheckOk = checkDigit(docNumber) == l2[9].wholeNumberValue
        let nationality = slice(l2, 10, 13)
        let dob = slice(l2, 13, 19)
        let dobCheckOk = checkDigit(dob) == l2[19].wholeNumberValue

        return MrzData(
            cognome: cognome, nome: nome, sesso: parseSex(l2[20]), dataNascita: parseMrzDate(dob),
            numeroDocumento: trimFiller(docNumber), tipoDocumento: String(l1[0]),
            issuingCountryIso: trimFiller(issuing), statoNascitaIso: trimFiller(nationality),
            cittadinanzaIso: trimFiller(nationality), checkDigitsValid: docCheckOk && dobCheckOk
        )
    }

    static func parseTD1(_ line1: String, _ line2: String, _ line3: String) -> MrzData? {
        let l1 = Array(line1), l2 = Array(line2), l3 = Array(line3)
        guard l1.count >= 30, l2.count >= 30, l3.count >= 30 else { return nil }

        let docNumber = slice(l1, 5, 14)
        let docCheckOk = checkDigit(docNumber) == l1[14].wholeNumberValue
        let dob = slice(l2, 0, 6)
        let dobCheckOk = checkDigit(dob) == l2[6].wholeNumberValue
        let nationality = slice(l2, 15, 18)
        let (cognome, nome) = parseName(line3)

        return MrzData(
            cognome: cognome, nome: nome, sesso: parseSex(l2[7]), dataNascita: parseMrzDate(dob),
            numeroDocumento: trimFiller(docNumber), tipoDocumento: String(l1[0]),
            issuingCountryIso: trimFiller(nationality), statoNascitaIso: trimFiller(nationality),
            cittadinanzaIso: trimFiller(nationality), checkDigitsValid: docCheckOk && dobCheckOk
        )
    }

    /// "ROSSI<<MARIO<LUIGI<<<<" → ("ROSSI", "MARIO LUIGI").
    static func parseName(_ nameField: String) -> (cognome: String, nome: String) {
        let parts = trimFiller(nameField).components(separatedBy: "<<")
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "<", with: " ").trimmed }
        return (clean(parts.count > 0 ? parts[0] : ""), clean(parts.count > 1 ? parts[1] : ""))
    }

    /// "800101" → "01/01/1980". L'anno a due cifre è del 2000 se non supera quello corrente, altrimenti del 1900.
    static func parseMrzDate(_ yymmdd: String, currentYear: Int? = nil) -> String {
        let chars = Array(yymmdd)
        guard chars.count >= 6, let yy = Int(slice(chars, 0, 2)) else { return "" }
        let year = currentYear ?? Calendar.current.component(.year, from: Date())
        let century = yy <= year % 100 ? 2000 : 1900
        return "\(slice(chars, 4, 6))/\(slice(chars, 2, 4))/\(century + yy)"
    }

    /// Cifra di controllo ICAO 9303: pesi 7-3-1, cifre = valore, lettere A=10…Z=35, '<' = 0.
    static func checkDigit(_ field: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (i, c) in field.enumerated() {
            let value: Int
            if let digit = c.wholeNumberValue, c.isASCII { value = digit }
            else if c.isLetter, let ascii = c.uppercased().unicodeScalars.first?.value { value = Int(ascii) - 65 + 10 }
            else { value = 0 }
            sum += value * weights[i % 3]
        }
        return sum % 10
    }

    /// Codici Alloggiati Web: "1" = M, "2" = F.
    private static func parseSex(_ c: Character) -> String { c == "F" ? "2" : "1" }
}

// MARK: Link di invito

/// Link di invito `https://siciliahost.com/invito/CODICE` (apre l'app se installata, altrimenti la pagina del sito).
/// Si riconosce anche il vecchio `siciliahost://invito/CODICE`. Il codice ha lo stesso formato di `inviteCode.ts`
/// del sito: 8 caratteri senza I, O, 0, 1.
enum InviteLink {
    private static let prefix = "https://siciliahost.com/invito/"
    private static let codeLength = 8
    private static let link = try! NSRegularExpression(
        pattern: #"(?:siciliahost://|https?://(?:www\.)?siciliahost\.com/)invito/([A-Za-z0-9]+)"#,
        options: [.caseInsensitive]
    )
    private static let codeAlphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func build(_ code: String) -> String { prefix + code }

    /// Accetta il link (anche dentro un testo condiviso) o il codice nudo, con spazi/minuscole/trattini.
    static func extractCode(_ text: String) -> String? {
        if let match = link.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return validate(String(text[range]))
        }
        return validate(text)
    }

    private static func validate(_ raw: String) -> String? {
        let code = String(raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        return code.count == codeLength && code.allSatisfy(codeAlphabet.contains) ? code : nil
    }
}
