import FirebaseFunctions
import Foundation

/// Nome del codice di errore di una callable (stessi nomi dell'Android: `UNAVAILABLE`, `PERMISSION_DENIED`…),
/// o nil se l'errore non viene da Cloud Functions.
func functionsErrorCodeName(_ error: Error) -> String? {
    let ns = error as NSError
    guard ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) else { return nil }
    switch code {
    case .OK: return "OK"
    case .cancelled: return "CANCELLED"
    case .unknown: return "UNKNOWN"
    case .invalidArgument: return "INVALID_ARGUMENT"
    case .deadlineExceeded: return "DEADLINE_EXCEEDED"
    case .notFound: return "NOT_FOUND"
    case .alreadyExists: return "ALREADY_EXISTS"
    case .permissionDenied: return "PERMISSION_DENIED"
    case .resourceExhausted: return "RESOURCE_EXHAUSTED"
    case .failedPrecondition: return "FAILED_PRECONDITION"
    case .aborted: return "ABORTED"
    case .outOfRange: return "OUT_OF_RANGE"
    case .unimplemented: return "UNIMPLEMENTED"
    case .internal: return "INTERNAL"
    case .unavailable: return "UNAVAILABLE"
    case .dataLoss: return "DATA_LOSS"
    case .unauthenticated: return "UNAUTHENTICATED"
    @unknown default: return "UNKNOWN"
    }
}

/// I `details` dell'errore di una callable (es. `{ missing: [...] }` di submitListing).
func functionsErrorDetails(_ error: Error) -> Any? {
    (error as NSError).userInfo[FunctionsErrorDetailsKey]
}

/// Messaggio per l'utente di un errore delle callable degli host (inviti, membri, Alloggiati).
func describeHostError(_ error: Error) -> String {
    if let code = functionsErrorCodeName(error) {
        return describeHostError(code: code, message: (error as NSError).localizedDescription)
    }
    return error.localizedDescription
}

func describeHostError(code: String, message: String?) -> String {
    switch code {
    case "UNAUTHENTICATED": return "Accedi di nuovo per continuare"
    case "PERMISSION_DENIED": return "Non hai i permessi per questa operazione"
    case "UNAVAILABLE", "DEADLINE_EXCEEDED": return "Connessione assente o lenta: riprova"
    case "NOT_FOUND", "ALREADY_EXISTS", "FAILED_PRECONDITION", "INVALID_ARGUMENT":
        if message == "Property not found" { return "Casa non trovata" }
        if let message, !message.trimmed.isEmpty { return message }
        return "Richiesta non valida"
    default: return "Errore del server (\(code))"
    }
}

/// Messaggio per l'utente di un errore di `upsertProperty` e simili (contenuti del sito).
func describeSiteError(_ error: Error) -> String {
    guard let code = functionsErrorCodeName(error) else { return error.localizedDescription }
    return describeSiteError(code: code, message: (error as NSError).localizedDescription)
}

func describeSiteError(code: String, message: String?) -> String {
    switch code {
    case "UNAUTHENTICATED", "PERMISSION_DENIED": return "Non gestisci questa casa"
    case "INVALID_ARGUMENT": return message ?? "Dati non validi"
    case "UNAVAILABLE", "DEADLINE_EXCEEDED": return "Connessione assente o lenta: riprova"
    case "NOT_FOUND": return "Struttura o funzione non trovata sul server"
    default: return "Errore del server (\(code))"
    }
}
