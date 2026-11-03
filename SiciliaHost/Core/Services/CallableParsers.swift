import Foundation

// Parser puri delle risposte delle Cloud Functions (specchio dei parser di HostFunctionsRepository,
// ListingRepository e PriceRepository, testati). Le risposte arrivano come `Any?`: dizionari e array JSON
// con numeri che possono essere Int, Int64 o Double a seconda della grandezza. Le voci malformate si
// scartano, mai un errore.

// MARK: Estrazione tollerante

private func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

private func strings(_ value: Any?) -> [String] { (value as? [Any])?.compactMap { $0 as? String } ?? [] }

private func number(_ value: Any?) -> NSNumber? {
    guard let n = value as? NSNumber else { return nil }
    // I booleani JSON non sono numeri.
    if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
    return n
}

private func int64(_ value: Any?) -> Int64? { number(value)?.int64Value }
private func int(_ value: Any?) -> Int? { number(value).map { Int(truncating: $0) } }
private func double(_ value: Any?) -> Double? { number(value)?.doubleValue }

private func permissions(_ value: Any?) -> Set<PropertyPermission> {
    Set(strings(value).compactMap { PropertyPermission(rawValue: $0) })
}

// MARK: Inviti e membri

func parseInvite(_ data: Any?) -> Invite? {
    guard let map = dict(data), let code = map["code"] as? String, let expires = int64(map["expiresAt"]) else { return nil }
    return Invite(code: code, expiresAt: expires)
}

func inviteGrantsPayload(_ grants: [InviteGrant]) -> [String: Any] {
    ["grants": grants.map { grant -> [String: Any] in
        ["propertyId": grant.propertyId, "permissions": grant.permissions.map(\.rawValue).sorted()]
    }]
}

func parseInvitePreview(_ data: Any?) -> InvitePreview? {
    guard let map = dict(data), let code = map["code"] as? String, let expires = int64(map["expiresAt"]) else { return nil }
    let grants = ((map["grants"] as? [Any]) ?? []).compactMap { item -> InvitePreviewGrant? in
        guard let g = dict(item), let propertyId = g["propertyId"] as? String else { return nil }
        return InvitePreviewGrant(
            propertyId: propertyId,
            propertyName: g["propertyName"] as? String ?? "",
            permissions: permissions(g["permissions"])
        )
    }
    return InvitePreview(code: code, expiresAt: expires, inviterEmail: map["inviterEmail"] as? String ?? "", grants: grants)
}

/// Preferisce `propertyIds`; ripiega sul vecchio `propertyId`. Vuota se la risposta non è valida.
func parseRedeemResult(_ data: Any?) -> [String] {
    guard let map = dict(data) else { return [] }
    let ids = strings(map["propertyIds"])
    if !ids.isEmpty { return ids }
    return (map["propertyId"] as? String).map { [$0] } ?? []
}

func parseMembers(_ data: Any?) -> [MemberInfo] {
    guard let list = dict(data)?["members"] as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = dict(item), let uid = m["uid"] as? String,
              let role = PropertyRole.parse(m["role"] as? String) else { return nil }
        return MemberInfo(uid: uid, role: role, email: m["email"] as? String ?? "", permissions: permissions(m["permissions"]),
                          displayName: (m["displayName"] as? String)?.trimmed ?? "")
    }
}

func parseTransferResult(_ data: Any?) -> TransferResult {
    guard let map = dict(data), map["status"] as? String == "completed" else {
        return TransferResult(completed: false, newOwnerUid: nil)
    }
    return TransferResult(completed: true, newOwnerUid: map["newOwnerUid"] as? String)
}

func parseClaimed(_ data: Any?) -> [String] { strings(dict(data)?["claimed"]) }

// MARK: Alloggiati

func parseEsito(_ data: Any?) -> ElencoSchedineEsito {
    guard let map = dict(data) else { return ElencoSchedineEsito(schedineValide: 0, dettaglio: []) }
    let details = ((map["dettaglio"] as? [Any]) ?? []).compactMap { item -> EsitoSingolo? in
        guard let m = dict(item) else { return nil }
        return EsitoSingolo(
            esito: m["esito"] as? Bool ?? false,
            errorCod: m["errorCod"] as? String ?? "",
            errorDes: m["errorDes"] as? String ?? "",
            erroreDettaglio: m["erroreDettaglio"] as? String ?? ""
        )
    }
    return ElencoSchedineEsito(schedineValide: int(map["schedineValide"]) ?? 0, dettaglio: details)
}

/// Il CSV di una tabella Alloggiati (`{ csv: "..." }`), o stringa vuota.
func parseCsvField(_ data: Any?) -> String { dict(data)?["csv"] as? String ?? "" }

/// Il PDF della ricevuta (`{ pdfBase64: "..." }`), o nil se assente, vuoto o non valido.
func parseReceipt(_ data: Any?) -> Data? {
    guard let b64 = dict(data)?["pdfBase64"] as? String, !b64.trimmed.isEmpty else { return nil }
    return Data(base64Encoded: b64)
}

// MARK: Annunci e host

/// Legge `{ hosts: [{uid,email,displayName,propertyCount,pendingCount,propertyNames}] }` ignorando le righe malformate.
func parseHosts(_ data: Any?) -> [HostRow] {
    guard let list = dict(data)?["hosts"] as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = dict(item), let uid = m["uid"] as? String else { return nil }
        return HostRow(
            uid: uid,
            email: m["email"] as? String ?? "",
            displayName: m["displayName"] as? String ?? "",
            propertyCount: int(m["propertyCount"]) ?? 0,
            pendingCount: int(m["pendingCount"]) ?? 0,
            propertyNames: strings(m["propertyNames"])
        )
    }
}

/// I `details` di un errore `failed-precondition` di submitListing: `{ missing: [..] }`.
func parseMissing(_ details: Any?) -> [String] { strings(dict(details)?["missing"]) }

// MARK: Prezzi

/// Legge `{ rates: [{startDate, endDate, pricePerNight}] }` ignorando le voci malformate.
func parseSeasonalRates(_ data: Any?) -> [SeasonalRateEntry] {
    guard let list = dict(data)?["rates"] as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = dict(item), let start = m["startDate"] as? String, let end = m["endDate"] as? String,
              let price = double(m["pricePerNight"]) else { return nil }
        return SeasonalRateEntry(startDate: start, endDate: end, pricePerNight: price)
    }
}

/// Legge `{ promotions: [{id, startDate, endDate, discountType, discountValue}] }` ignorando le voci malformate.
func parsePromotions(_ data: Any?) -> [PromoEntry] {
    guard let list = dict(data)?["promotions"] as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = dict(item), let id = m["id"] as? String, let start = m["startDate"] as? String,
              let end = m["endDate"] as? String, let type = m["discountType"] as? String,
              let value = double(m["discountValue"]) else { return nil }
        return PromoEntry(id: id, startDate: start, endDate: end, discountType: type, discountValue: value)
    }
}

/// Legge `{ surcharges: { "3": 10 } }` come mappa numero di ospiti -> euro, scartando le voci non valide.
func parseSurcharges(_ data: Any?) -> [Int: Double] {
    guard let map = dict(dict(data)?["surcharges"]) else { return [:] }
    var result: [Int: Double] = [:]
    for (key, value) in map {
        if let guests = Int(key), let amount = double(value) { result[guests] = amount }
    }
    return result
}
