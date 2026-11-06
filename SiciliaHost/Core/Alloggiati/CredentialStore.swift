import Foundation
import Security

/// Credenziali Alloggiati di questo telefono, una voce per casa (porta di `CredentialStore.kt`).
protocol CredentialStore: Sendable {
    func get(_ propertyId: String) -> AlloggiatiCredentials?
    func put(_ propertyId: String, _ credentials: AlloggiatiCredentials) throws
    func remove(_ propertyId: String)
    func clear()
}

struct CredentialStoreError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Credenziali non salvate su questo telefono (\(status))" }
}

/// Nel portachiavi, `AfterFirstUnlockThisDeviceOnly`: non migrano su un altro iPhone né nei backup; dopo un cambio di
/// telefono si reinseriscono. Nessun gruppo d'accesso (l'entitlement `keychain-access-groups` è stato tolto).
struct KeychainCredentialStore: CredentialStore {
    static let service = "com.siciliahost.cactushost.alloggiati"
    private static let installFlag = "alloggiatiKeychainInstalled"

    private func query(_ propertyId: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: propertyId]
    }

    /// Si cancella la voce solo se è certo che non si potrà più leggere (dati non decodificabili); un errore passeggero
    /// (portachiavi momentaneamente non disponibile...) lascia i dati e restituisce nil.
    func get(_ propertyId: String) -> AlloggiatiCredentials? {
        var q = query(propertyId)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        guard let data = out as? Data, let decoded = try? JSONDecoder().decode(AlloggiatiCredentials.self, from: data) else {
            remove(propertyId)
            return nil
        }
        return decoded
    }

    func put(_ propertyId: String, _ credentials: AlloggiatiCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(propertyId) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(propertyId)
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
    }

    func remove(_ propertyId: String) {
        SecItemDelete(query(propertyId) as CFDictionary)
    }

    func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service] as CFDictionary)
    }

    /// Su iOS il portachiavi sopravvive alla disinstallazione dell'app (le preferenze Android no): alla prima apertura
    /// dopo un'installazione si svuota, così un altro account non eredita le credenziali di prima.
    static func clearIfFreshInstall(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installFlag) else { return }
        KeychainCredentialStore().clear()
        defaults.set(true, forKey: installFlag)
    }
}
