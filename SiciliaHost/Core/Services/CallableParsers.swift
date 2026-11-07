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

// MARK: Messaggistica ospite ↔ host (`MessagingRepository.kt`)

private func stayRequest(_ data: Any?) -> StayRequest? {
    guard let map = dict(data) else { return nil }
    return StayRequest(checkIn: map["checkIn"] as? String, checkOut: map["checkOut"] as? String, guests: int(map["guests"]))
}

private func bookingSummary(_ data: Any?) -> BookingSummary? {
    guard let map = dict(data), let id = map["id"] as? String, let status = map["status"] as? String,
          let checkIn = map["checkIn"] as? String, let checkOut = map["checkOut"] as? String else { return nil }
    return BookingSummary(
        id: id, status: status, checkIn: checkIn, checkOut: checkOut, guests: int(map["guests"]),
        totalPrice: double(map["totalPrice"]), depositAmount: double(map["depositAmount"])
    )
}

func parseConversation(_ data: Any?) -> Conversation? {
    guard let map = dict(data), let id = map["id"] as? String, let propertyId = map["propertyId"] as? String else { return nil }
    let last: LastMessage? = dict(map["lastMessage"]).flatMap { m in
        guard let text = m["text"] as? String else { return nil }
        return LastMessage(text: text, from: m["from"] as? String ?? "", at: int64(m["at"]) ?? 0)
    }
    return Conversation(
        id: id,
        propertyId: propertyId,
        propertyName: dict(map["propertyTitle"])?["it"] as? String ?? "",
        guestName: map["guestName"] as? String ?? "",
        guestEmail: map["guestEmail"] as? String,
        request: stayRequest(map["request"]) ?? StayRequest(),
        booking: bookingSummary(map["booking"]),
        lastMessage: last,
        unread: map["unread"] as? Bool == true,
        updatedAt: int64(map["updatedAt"]) ?? 0
    )
}

func parseConversations(_ data: Any?) -> [Conversation] {
    ((dict(data)?["conversations"] as? [Any]) ?? []).compactMap(parseConversation)
}

func parseChatMessage(_ data: Any?) -> ChatMessage? {
    guard let map = dict(data), let id = map["id"] as? String, let from = map["from"] as? String, let at = int64(map["at"]) else { return nil }
    return ChatMessage(id: id, from: from, text: map["text"] as? String ?? "", at: at, context: stayRequest(map["context"]))
}

func parseConversationDetail(_ data: Any?) -> (conversation: Conversation, messages: [ChatMessage])? {
    guard let map = dict(data), let conversation = parseConversation(map["conversation"]) else { return nil }
    return (conversation, ((map["messages"] as? [Any]) ?? []).compactMap(parseChatMessage))
}

func parseMessagingStatus(_ data: Any?) -> MessagingStatus {
    guard let host = dict(dict(data)?["host"]) else { return MessagingStatus() }
    return MessagingStatus(hostEnabled: host["enabled"] as? Bool == true, hostUnread: int(host["unread"]) ?? 0)
}

func parseContactDetails(_ data: Any?) -> HostContactDetails? {
    guard let map = dict(data) else { return nil }
    return HostContactDetails(phone: map["phone"] as? String, whatsapp: map["whatsapp"] as? String)
}

// MARK: Finanze

/// Risposta di `getSiteBookingAmounts`: `{ amounts: [{ reservationId, propertyId, totalPrice }] }`. Voci senza id,
/// senza casa, senza prezzo o con prezzo negativo scartate.
func parseSiteBookingAmounts(_ data: Any?) -> [SiteBookingAmount] {
    guard let list = dict(data)?["amounts"] as? [Any] else { return [] }
    return list.compactMap { item in
        guard let m = dict(item), let id = m["reservationId"] as? String, let pid = m["propertyId"] as? String,
              let price = double(m["totalPrice"]), price >= 0 else { return nil }
        return SiteBookingAmount(reservationId: id, propertyId: pid, totalPrice: price)
    }
}
