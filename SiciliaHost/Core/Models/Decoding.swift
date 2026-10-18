import Foundation

// I documenti Firestore scritti dall'app Android (e dal sito) possono non avere un campo o averlo di
// tipo inatteso: i modelli leggono in modo tollerante, come faceva `toObject()` su Android
// (campi mancanti = valore di default, campi sconosciuti ignorati).
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
