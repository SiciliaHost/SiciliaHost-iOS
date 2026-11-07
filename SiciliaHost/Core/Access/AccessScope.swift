import Foundation

/// Email del super-admin: stessa di `isSuperAdmin()` in firestore.rules, di `DatabaseRepository.ADMIN_EMAIL`
/// (Android) e di `SUPER_ADMIN_EMAIL` nelle Functions. Cambiarle tutte insieme.
let superAdminEmail = "aleloverde@gmail.com"

/// Stessa condizione delle rules: email fissa, verificata, esatta.
func isSuperAdminAccount(email: String?, emailVerified: Bool) -> Bool {
    emailVerified && email == superAdminEmail
}

enum AppFieldsAccess { case direct, viaAdmin, readOnly }

/// Cosa può fare l'utente loggato su ciascuna casa. Porting 1:1 di `AccessScope.kt` (specchio delle
/// firestore.rules): un membro "opera"; solo l'OWNER "gestisce"; Finanze solo l'OWNER (i soldi stanno sul suo
/// telefono, nemmeno il super-admin sulle case in commissione); il COLLABORATOR può ricevere PRICES / SITE;
/// il super-admin opera/gestisce solo le case di cui è OWNER e quelle in commissione.
struct AccessScope: Equatable, Sendable {
    let uid: String
    let isSuperAdmin: Bool
    let properties: [Property]

    func roleIn(_ property: Property) -> PropertyRole? { property.roleOf(uid) }

    private func superManages(_ property: Property) -> Bool {
        isSuperAdmin && (roleIn(property) == .owner || property.isManagedOnCommission)
    }

    func canOperate(_ property: Property) -> Bool { roleIn(property) != nil || superManages(property) }
    func canManage(_ property: Property) -> Bool { roleIn(property) == .owner || superManages(property) }
    func isOwner(_ property: Property) -> Bool { roleIn(property) == .owner }

    private func hasPermission(_ property: Property, _ permission: PropertyPermission) -> Bool {
        canManage(property) || property.permissionsOf(uid).contains(permission)
    }

    /// Finanze: solo il proprietario della casa (i soldi stanno sul suo telefono). Né collaboratori né super-admin in commissione.
    func canFinance(_ property: Property) -> Bool { isOwner(property) }
    func canEditPrices(_ property: Property) -> Bool { hasPermission(property, .prices) }
    func canEditSite(_ property: Property) -> Bool { hasPermission(property, .site) }

    /// Case su cui si lavora ogni giorno: Home, Agenda, Scorte, check-in.
    var operable: [Property] { properties.filter(canOperate) }
    /// Case su cui si decide: Finanze, Immobili, Sito, prezzi.
    var managed: [Property] { properties.filter(canManage) }
    var financeProperties: [Property] { properties.filter(canFinance) }
    var priceProperties: [Property] { properties.filter(canEditPrices) }
    var siteProperties: [Property] { properties.filter(canEditSite) }
    var owned: [Property] { properties.filter(isOwner) }
    /// Visibili ma non utilizzabili (le elenca solo il super-admin).
    var others: [Property] { properties.filter { !canOperate($0) } }

    /// Contenuti dell'annuncio (sito, prezzi): chi li può modificare; il super-admin su tutte.
    func canEditListing(_ property: Property) -> Bool { isSuperAdmin || canEditSite(property) }
    var listingProperties: [Property] { properties.filter(canEditListing) }

    func appFieldsAccess(_ property: Property) -> AppFieldsAccess {
        if canManage(property) { return .direct }
        if isSuperAdmin { return .viaAdmin }
        return .readOnly
    }

    var canSeeManagementTabs: Bool { !managed.isEmpty || !listingProperties.isEmpty }

    var profileLabel: String {
        if isSuperAdmin { return "AMMINISTRATORE" }
        if !owned.isEmpty { return "PROPRIETARIO" }
        return "COLLABORATORE"
    }
}
