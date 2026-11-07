import Foundation

// Logica pura di membri e inviti (`ui/members/MembersLogic.kt`, `InviteForm.kt`, `ui/invite/InviteFormat.kt`).

enum MembersLogic {
    private static let emailPattern = #/^[^\s@]+@[^\s@]+\.[^\s@]+$/#

    /// Messaggio d'errore, o nil se l'email del nuovo proprietario va bene.
    static func validateTransferEmail(_ input: String, myEmail: String) -> String? {
        let email = input.trimmed
        if email.isEmpty { return "Inserisci l'email del nuovo proprietario" }
        if email.wholeMatch(of: emailPattern) == nil { return "Email non valida" }
        if email.caseInsensitiveCompare(myEmail.trimmed) == .orderedSame { return "Sei già il proprietario" }
        return nil
    }

    /// Proprietari per primi, poi per etichetta mostrata (nome o email), senza badare alle maiuscole.
    static func sort(_ members: [MemberInfo]) -> [MemberInfo] {
        members.enumerated().sorted { a, b in
            let ownerA = a.element.role == .owner, ownerB = b.element.role == .owner
            if ownerA != ownerB { return ownerA }
            let la = label(a.element).lowercased(), lb = label(b.element).lowercased()
            if la != lb { return la < lb }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func label(_ member: MemberInfo) -> String {
        if !member.displayName.trimmed.isEmpty { return member.displayName }
        if !member.email.trimmed.isEmpty { return member.email }
        return "Account non più disponibile"
    }

    /// Il proprietario rimuove i collaboratori; non rimuove sé stesso (prima trasferisce la casa).
    static func canRemove(_ member: MemberInfo, myUid: String) -> Bool { member.role == .collaborator && member.uid != myUid }

    static func toggle(_ current: Set<PropertyPermission>, _ permission: PropertyPermission, _ enabled: Bool) -> Set<PropertyPermission> {
        enabled ? current.union([permission]) : current.subtracting([permission])
    }

    /// Solo i collaboratori hanno permessi da scegliere: il proprietario ha già tutto.
    static func canEditPermissions(_ member: MemberInfo) -> Bool { member.role == .collaborator }
}

/// Modulo "Invita un collaboratore": quali case (tra quelle di cui si è proprietari, in `order`) e con quali permessi
/// extra. I permessi esistono solo per le case selezionate.
struct InviteForm: Equatable {
    private let order: [String]
    private var selections: [String: Set<PropertyPermission>]

    private init(order: [String], selections: [String: Set<PropertyPermission>]) {
        self.order = order
        self.selections = selections
    }

    static func create(order: [String], currentId: String?) -> InviteForm {
        let form = InviteForm(order: order, selections: [:])
        return currentId.map { form.withProperty($0, selected: true) } ?? form
    }

    func isSelected(_ id: String) -> Bool { selections[id] != nil }
    func permissionsOf(_ id: String) -> Set<PropertyPermission> { selections[id] ?? [] }

    /// Selezionare una casa parte sempre senza permessi; deselezionarla li scarta.
    func withProperty(_ id: String, selected: Bool) -> InviteForm {
        guard order.contains(id) else { return self }
        var copy = self
        if selected { if !isSelected(id) { copy.selections[id] = [] } } else { copy.selections[id] = nil }
        return copy
    }

    func withPermission(_ id: String, _ permission: PropertyPermission, enabled: Bool) -> InviteForm {
        guard let current = selections[id] else { return self }
        var copy = self
        copy.selections[id] = MembersLogic.toggle(current, permission, enabled)
        return copy
    }

    var canSubmit: Bool { !selections.isEmpty }
    var problem: String? { canSubmit ? nil : "Scegli almeno una casa" }

    /// Solo le case selezionate, nell'ordine dell'elenco.
    func toGrants() -> [InviteGrant] {
        order.compactMap { id in selections[id].map { InviteGrant(propertyId: id, permissions: $0) } }
    }
}

struct InviteShareItem: Equatable {
    let propertyName: String
    let permissions: Set<PropertyPermission>
}

enum InviteText {
    static let baseManagementNote = "La gestione base comprende prenotazioni, scorte, check-in e invio Alloggiati."

    /// Permessi in ordine stabile (Prezzi, Sito).
    private static func ordered(_ permissions: Set<PropertyPermission>) -> [PropertyPermission] {
        PropertyPermission.allCases.filter { permissions.contains($0) }
    }

    static func permissionsText(_ permissions: Set<PropertyPermission>) -> String {
        permissions.isEmpty ? "Solo gestione base" : "Gestione base + " + ordered(permissions).map(\.label).joined(separator: ", ")
    }

    static func headline(_ inviterEmail: String) -> String {
        let who = inviterEmail.trimmed
        return "\(who.isEmpty ? "Un proprietario" : who) ti invita a collaborare"
    }

    static func shareItems(_ grants: [InviteGrant], namesById: [String: String]) -> [InviteShareItem] {
        grants.map { InviteShareItem(propertyName: namesById[$0.propertyId] ?? "Casa", permissions: $0.permissions) }
    }

    /// Il codice è ripetuto accanto al link perché WhatsApp può non rendere il link cliccabile.
    static func shareText(_ items: [InviteShareItem], link: String, code: String, expiryDate: String) -> String {
        var text = "Ti invito a collaborare alla gestione su Sicilia Host:\n"
        for item in items {
            let perms = item.permissions.isEmpty ? "solo gestione base" : ordered(item.permissions).map(\.label).joined(separator: ", ")
            text += "- \(item.propertyName): \(perms)\n"
        }
        text += "\nApri il link: \(link)\n"
        text += "Se il link non si apre, apri l'app, scegli \"Ho un codice invito\" e inserisci: \(code)\n"
        text += "Il codice vale una sola volta ed è valido fino al \(expiryDate)."
        return text
    }
}
