import CryptoKit
import Foundation

/// Nonce per "Accedi con Apple": una stringa casuale (`random`) resta in memoria, ad Apple si manda il suo hash SHA-256
/// (`sha256`), a Firebase la stringa originale: così Firebase può verificare che il token sia nato da questa richiesta.
enum AppleNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "Impossibile generare numeri casuali")
            for byte in bytes where remaining > 0 && Int(byte) < charset.count * (256 / charset.count) {
                // Scarta i valori che renderebbero la scelta non uniforme.
                result.append(charset[Int(byte) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
