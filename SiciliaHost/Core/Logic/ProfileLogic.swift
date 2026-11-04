import Foundation

// Logica pura del Profilo (`DisplayName.kt`, `HouseAccessLogic.kt`, `PrivacyContent.kt`, `LegalLinks.kt`).

// MARK: Nome visualizzato

let displayNameMax = 40

/// Spazi ai bordi tolti e interni ridotti a uno solo (a capo e tabulazioni compresi).
func cleanDisplayName(_ input: String) -> String {
    input.trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

/// Messaggio d'errore, o nil se `input` è un nome valido dopo la pulizia.
func validateDisplayName(_ input: String) -> String? {
    let name = cleanDisplayName(input)
    if name.isEmpty { return "Inserisci un nome" }
    if name.count > displayNameMax { return "Al massimo \(displayNameMax) caratteri" }
    if name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return "Caratteri non validi" }
    return nil
}

// MARK: Le mie case

/// Una casa nell'elenco "Le mie case" del profilo. `permissionsText` solo per i collaboratori.
struct HouseRow: Equatable, Identifiable, Sendable {
    let propertyId: String
    let name: String
    let roleLabel: String
    let permissionsText: String?
    var id: String { propertyId }
}

func houseRoleLabel(_ scope: AccessScope, _ property: Property) -> String {
    switch scope.roleIn(property) {
    case .owner: return "Proprietario"
    case .collaborator: return "Collaboratore"
    case nil: return scope.isSuperAdmin ? "Amministratore" : "Accesso limitato"
    }
}

func permissionsSummary(_ permissions: Set<PropertyPermission>) -> String {
    if permissions.isEmpty { return "Nessun permesso aggiuntivo" }
    return PropertyPermission.allCases.filter(permissions.contains).map(\.label).joined(separator: ", ")
}

/// Le case dell'utente: prima quelle di cui è proprietario, poi per nome.
func houseRows(_ scope: AccessScope) -> [HouseRow] {
    scope.properties
        .filter { scope.canOperate($0) || scope.canEditListing($0) }
        .sorted { a, b in
            let oa = scope.isOwner(a), ob = scope.isOwner(b)
            if oa != ob { return oa }
            return a.name.lowercased() < b.name.lowercased()
        }
        .map { property in
            let collaborator = scope.roleIn(property) == .collaborator
            return HouseRow(
                propertyId: property.id,
                name: property.name.trimmed.isEmpty ? "Casa senza nome" : property.name,
                roleLabel: houseRoleLabel(scope, property),
                permissionsText: collaborator ? permissionsSummary(property.permissionsOf(scope.uid)) : nil
            )
        }
}

/// Il server permette l'uscita solo a un collaboratore: il proprietario prima trasferisce la casa.
func canLeaveHouse(_ scope: AccessScope, _ property: Property) -> Bool { scope.roleIn(property) == .collaborator }

func canManageMembers(_ scope: AccessScope, _ property: Property) -> Bool { scope.isOwner(property) }

// MARK: Privacy

struct PrivacySection: Equatable, Sendable {
    let title: String
    let body: String
}

/// Cosa SiciliaHost fa davvero per proteggere i dati. Ogni frase corrisponde a una regola o a un comportamento verificabile
/// nel codice (firestore.rules, Functions): se si cambia il comportamento, si cambia il testo. Su iPhone l'accesso include
/// anche Apple (`apple.com` ammesso dalle regole), quindi la prima voce lo dice.
let privacySections: [PrivacySection] = [
    PrivacySection(title: "Il tuo accesso", body: "Entri con il tuo account Google o con Apple."),
    PrivacySection(
        title: "Chi vede i tuoi dati",
        body: "I dati di una casa sono visibili ai suoi membri e agli amministratori di SiciliaHost. Le regole del database rifiutano l'accesso ai dati di case di cui non fai parte. Un collaboratore può gestire prenotazioni, inventario e dati degli ospiti (documenti compresi) della casa; il proprietario può concedergli in più Finanze, Prezzi e calendario e Contenuti del sito."
    ),
    PrivacySection(
        title: "Credenziali Alloggiati",
        body: "Utente, password e chiave del servizio Alloggiati Web stanno in un'area riservata al proprietario della casa. L'invio delle schedine parte dai nostri server: i collaboratori possono inviare, ma non leggere le credenziali."
    ),
    PrivacySection(
        title: "Dati degli ospiti",
        body: "I dati dei documenti servono per il check-in con la Questura (Alloggiati Web). Nel pannello web il numero del documento è mostrato mascherato."
    ),
    PrivacySection(
        title: "Posizione delle case",
        body: "Se la casa ha un pin sulla mappa, sul sito compare il punto esatto (mai l'indirizzo); senza pin si vede solo un'area di circa 300 metri di raggio. L'indirizzo preciso lo vedono i membri della casa e gli ospiti con prenotazione confermata."
    ),
    PrivacySection(title: "Pagamenti", body: "I pagamenti dal sito passano da Stripe. Questa app non vede né conserva i dati delle carte."),
    PrivacySection(
        title: "Notifiche",
        body: "Per inviarti le notifiche salviamo nel tuo profilo un identificativo del dispositivo (token). Puoi disattivare le notifiche in qualsiasi momento dalle impostazioni del telefono."
    ),
    PrivacySection(title: "I tuoi diritti", body: "Per chiedere accesso, correzione o cancellazione dei tuoi dati scrivi a info@siciliahost.com."),
]

/// Pagine legali del sito: il testo legale vive solo lì, l'app le apre nel browser.
enum LegalLinks {
    static let privacy = URL(string: "https://siciliahost.com/it/privacy")!
    static let terms = URL(string: "https://siciliahost.com/it/termini")!
}
