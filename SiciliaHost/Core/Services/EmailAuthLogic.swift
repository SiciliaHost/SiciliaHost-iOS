import Foundation

/// Parte pura dell'accesso con email e password (porta di `ui/login/EmailAuthLogic.kt` dell'Android; testata in
/// `EmailAuthLogicTests`).
///
/// Le regole Firestore/Storage e le Functions ammettono un account con password solo se l'email è VERIFICATA (o se è
/// l'account dimostrativo dei revisori, per uid): senza verifica chiunque potrebbe registrarsi con l'email di un altro.
/// Per questo, dopo l'accesso, un account non verificato esce subito e riceve di nuovo il link di conferma.
enum EmailAuthLogic {
    /// Account dimostrativo dei revisori degli store: email non verificata, ammesso per uid (stesso valore di `firestore.rules`).
    static let demoReviewerUid = "2fJQ2O1jESS23Lh0hgwhBJBiGPS2"

    /// Lunghezza minima della password richiesta da Firebase Auth.
    static let minPasswordLength = 6

    /// Dopo l'accesso con password serve la conferma dell'email, salvo l'account dimostrativo.
    static func needsEmailVerification(uid: String, emailVerified: Bool) -> Bool {
        !emailVerified && uid != demoReviewerUid
    }

    /// Controllo minimo prima di chiamare Firebase (la forma vera dell'indirizzo la giudica Firebase).
    static func isPlausibleEmail(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.contains(" "), let at = e.firstIndex(of: "@") else { return false }
        let local = e[..<at]
        let domain = e[e.index(after: at)...]
        return !local.isEmpty && domain.count >= 3 && domain.dropFirst().contains(".")
    }

    static let notVerifiedMessage =
        "Prima di entrare devi confermare l'email: ti abbiamo inviato il link. Aprilo, poi torna qui e accedi."
    static let registeredNotice =
        "Account creato. Ti abbiamo inviato una email: apri il link per confermare l'indirizzo, poi torna qui e accedi."
    static let resetNotice =
        "Se esiste un account con questa email, ti abbiamo inviato il link per scegliere una nuova password."
    static let invalidEmailNotice = "Scrivi un indirizzo email valido."
    static let emailForResetNotice = "Scrivi prima l'email dell'account."
    static let weakPasswordMessage = "La password è troppo debole: usa almeno \(minPasswordLength) caratteri."
    static let alreadyInUseMessage =
        "Esiste già un account con questa email (vale anche quello del sito SiciliaHost): accedi, oppure usa «Password dimenticata»."
}
