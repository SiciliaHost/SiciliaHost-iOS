import FirebaseFunctions
import Foundation

/// Chiamata a una Cloud Function callable; ritorna il `data` della risposta.
/// L'autenticazione è il token Firebase dell'utente (aggiunto dall'SDK).
private func callCloud(_ functions: Functions, _ name: String, _ payload: [String: Any?]) async throws -> Any? {
    let args: [String: Any] = payload.mapValues { (value: Any?) -> Any in value ?? NSNull() }
    let result = try await functions.httpsCallable(name).call(args)
    return result.data
}

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: Inviti, membri, trasferimenti, Alloggiati

/// Le operazioni che le firestore.rules negano al client e che vivono nelle Cloud Functions del sito:
/// inviti, membri, trasferimento di proprietà e Alloggiati (le credenziali non lasciano mai il server).
protocol InviteAPI {
    func getInvite(code: String) async throws -> InvitePreview
    func declineInvite(code: String) async throws
    func redeemInvite(code: String) async throws -> [String]
}

struct HostFunctionsService: InviteAPI {
    private let functions = Functions.functions()

    func createInvite(grants: [InviteGrant]) async throws -> Invite {
        guard let invite = parseInvite(try await call("createInvite", inviteGrantsPayload(grants))) else {
            throw ServiceError(message: "Risposta non valida dal server")
        }
        return invite
    }

    /// Anteprima dell'invito (chi invita, quali case e permessi) senza riscattarlo.
    func getInvite(code: String) async throws -> InvitePreview {
        guard let preview = parseInvitePreview(try await call("getInvite", ["code": code])) else {
            throw ServiceError(message: "Risposta non valida dal server")
        }
        return preview
    }

    func declineInvite(code: String) async throws {
        _ = try await call("declineInvite", ["code": code])
    }

    /// Ritorna gli id delle case a cui si è entrati come collaboratore.
    func redeemInvite(code: String) async throws -> [String] {
        let ids = parseRedeemResult(try await call("redeemInvite", ["code": code]))
        if ids.isEmpty { throw ServiceError(message: "Risposta non valida dal server") }
        return ids
    }

    func removeMember(propertyId: String, uid: String) async throws {
        _ = try await call("removeMember", ["propertyId": propertyId, "uid": uid])
    }

    func listMembers(propertyId: String) async throws -> [MemberInfo] {
        parseMembers(try await call("listMembers", ["propertyId": propertyId]))
    }

    /// Solo l'OWNER; insieme vuoto = toglie tutti i permessi al collaboratore.
    func setMemberPermissions(propertyId: String, uid: String, permissions: Set<PropertyPermission>) async throws {
        _ = try await call("setMemberPermissions", [
            "propertyId": propertyId, "uid": uid, "permissions": permissions.map(\.rawValue).sorted(),
        ])
    }

    func transferOwnership(propertyId: String, newOwnerEmail: String, keepPreviousOwner: Bool) async throws -> TransferResult {
        parseTransferResult(try await call("transferOwnership", [
            "propertyId": propertyId, "newOwnerEmail": newOwnerEmail, "keepPreviousOwner": keepPreviousOwner,
        ]))
    }

    /// Completa i trasferimenti in sospeso indirizzati all'email dell'utente. Ritorna le case ricevute.
    func claimPendingTransfers() async throws -> [String] {
        parseClaimed(try await call("claimPendingTransfers", [:]))
    }

    /// `send` = false → solo controllo (operazione Test del servizio), nulla viene segnato come inviato.
    func submitAlloggiati(propertyId: String, reservationId: String, send: Bool) async throws -> ElencoSchedineEsito {
        parseEsito(try await call("submitAlloggiati", [
            "propertyId": propertyId, "reservationId": reservationId, "mode": send ? "send" : "test",
        ]))
    }

    func getAlloggiatiTable(propertyId: String, tipo: String) async throws -> String {
        parseCsvField(try await call("getAlloggiatiTable", ["propertyId": propertyId, "tipo": tipo]))
    }

    /// `date` nel formato `yyyy-MM-dd`; senza data il server usa oggi.
    func getAlloggiatiReceipt(propertyId: String, date: String? = nil) async throws -> Data {
        var payload: [String: Any?] = ["propertyId": propertyId]
        if let date { payload["date"] = date }
        guard let pdf = parseReceipt(try await call("getAlloggiatiReceipt", payload)) else {
            throw ServiceError(message: "Ricevuta non disponibile")
        }
        return pdf
    }

    private func call(_ name: String, _ payload: [String: Any?]) async throws -> Any? {
        try await callCloud(functions, name, payload)
    }
}

// MARK: Ciclo di vita dell'annuncio e anagrafica host

/// Lo stato (`listingStatus`) lo cambiano solo queste callable: il client non lo scrive mai.
struct ListingService {
    private let functions = Functions.functions()

    /// `termsVersion` = versione delle condizioni d'uso accettata (il server la confronta con la sua).
    func submit(propertyId: String, termsVersion: String) async throws {
        _ = try await call("submitListing", ["propertyId": propertyId, "termsVersion": termsVersion])
    }

    func withdraw(propertyId: String) async throws {
        _ = try await call("withdrawListing", ["propertyId": propertyId])
    }

    /// L'host sceglie di pubblicare la casa sul sito: il server scrive il marcatore `siteTrack`.
    func startSitePublication(propertyId: String) async throws {
        _ = try await call("startSitePublication", ["propertyId": propertyId])
    }

    /// Solo il super-admin. `reasons` è obbligatorio quando si rifiuta.
    func review(propertyId: String, approve: Bool, reasons: String?) async throws {
        _ = try await call("reviewListing", [
            "propertyId": propertyId, "decision": approve ? "approve" : "reject", "reasons": reasons,
        ])
    }

    /// Solo il super-admin: correzione della scheda (campi dell'app) di una casa altrui.
    func adminUpsert(propertyId: String, patch: [String: Any?]) async throws {
        let cleaned: [String: Any] = patch.mapValues { (value: Any?) -> Any in value ?? NSNull() }
        _ = try await call("adminUpsertListing", ["propertyId": propertyId, "patch": cleaned])
    }

    func listHosts() async throws -> [HostRow] {
        parseHosts(try await call("listHosts", [:]))
    }

    private func call(_ name: String, _ payload: [String: Any?]) async throws -> Any? {
        try await callCloud(functions, name, payload)
    }
}

// MARK: Prezzi

/// Tariffe stagionali di `properties/{id}/seasonalRates` e promozioni: collezioni "solo sito", le regole
/// Firestore le negano al client, quindi lettura e scrittura passano dalle callable (solo chi gestisce la casa).
struct PriceService {
    private let functions = Functions.functions()

    func getSeasonalRates(propertyId: String) async throws -> [SeasonalRateEntry] {
        parseSeasonalRates(try await call("getSeasonalRates", ["propertyId": propertyId]))
    }

    /// `pricePerNight` nil = riporta le date al prezzo base. Ritorna l'elenco aggiornato.
    func setSeasonalRates(propertyId: String, ranges: [IsoRange], pricePerNight: Double?) async throws -> [SeasonalRateEntry] {
        parseSeasonalRates(try await call("setSeasonalRates", [
            "propertyId": propertyId, "ranges": ranges.map(\.payload), "pricePerNight": pricePerNight,
        ]))
    }

    /// Promozioni automatiche (senza codice) della casa.
    func listPromotions(propertyId: String) async throws -> [PromoEntry] {
        parsePromotions(try await call("listAutoPromotions", ["propertyId": propertyId]))
    }

    /// Una promozione per ogni intervallo continuo di `ranges`; ritorna quelle create.
    func createPromotions(propertyId: String, ranges: [IsoRange], discountType: String, discountValue: Double) async throws -> [PromoEntry] {
        parsePromotions(try await call("createAutoPromotions", [
            "propertyId": propertyId, "ranges": ranges.map(\.payload),
            "discountType": discountType, "discountValue": discountValue,
        ]))
    }

    func deletePromotion(id: String) async throws {
        _ = try await call("deleteAutoPromotion", ["id": id])
    }

    /// Sostituisce l'intera mappa degli extra (numero di ospiti -> euro a notte). Ritorna quella salvata.
    func setGuestSurcharges(propertyId: String, surcharges: [Int: Double]) async throws -> [Int: Double] {
        let wire = Dictionary(uniqueKeysWithValues: surcharges.map { (String($0.key), $0.value) })
        return parseSurcharges(try await call("setGuestSurcharges", ["propertyId": propertyId, "surcharges": wire]))
    }

    private func call(_ name: String, _ payload: [String: Any?]) async throws -> Any? {
        try await callCloud(functions, name, payload)
    }
}
