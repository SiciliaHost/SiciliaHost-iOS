import CryptoKit
import Foundation

/// Errori dell'archivio delle schede sul telefono.
enum GuestRecordStoreError: LocalizedError, Equatable {
    /// Il file non si decodifica: messo da parte (`.corrupt`) e contato come «schede non inviate».
    case corrupt
    /// Il file esiste ma non si legge (es. telefono appena acceso e mai sbloccato): lasciato com'è.
    case unreadable

    static let corruptMessage = "Archivio delle schede danneggiato"

    var errorDescription: String? {
        switch self {
        case .corrupt: return Self.corruptMessage
        case .unreadable: return "Schede non leggibili: sblocca il telefono e riprova"
        }
    }
}

/// Schede ospite del check-in, SOLO su questo telefono (porta di `GuestRecordStore.kt`): un file JSON per prenotazione in
/// `Application Support/guest_records/`. Il nome del file è un hash di casa + prenotazione (gli id iCal contengono caratteri
/// non ammessi nei nomi di file). La cartella è nel backup iCloud (cifrato da Apple); i file hanno la protezione
/// `completeUntilFirstUserAuthentication` (illeggibili solo prima del primo sblocco dopo l'accensione).
final class GuestRecordStore: @unchecked Sendable {
    static let shared = GuestRecordStore(directory: defaultDirectory)

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("guest_records", isDirectory: true)
    }

    // Un solo blocco per cartella, anche se le istanze sono più d'una. NSLock non è rientrante: ogni metodo pubblico lo
    // prende una volta e gli helper `…Locked` lo presuppongono.
    private final class LockRegistry: @unchecked Sendable {
        private let guardLock = NSLock()
        private var locks: [String: NSLock] = [:]

        func lock(for key: String) -> NSLock {
            guardLock.withLock {
                if let existing = locks[key] { return existing }
                let created = NSLock()
                locks[key] = created
                return created
            }
        }
    }

    private static let registry = LockRegistry()

    private static func lock(for directory: URL) -> NSLock {
        registry.lock(for: directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private let directory: URL
    private let newId: () -> String
    private let lock: NSLock
    private let fm = FileManager.default

    init(directory: URL, newId: @escaping () -> String = { UUID().uuidString }) {
        self.directory = directory
        self.newId = newId
        self.lock = Self.lock(for: directory)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func fileURL(_ propertyId: String, _ reservationId: String) -> URL {
        let hash = SHA256.hash(data: Data("\(propertyId)/\(reservationId)".utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }

    /// `nil` solo se il file non esiste. Se esiste ma non si decodifica lo mette da parte (.corrupt) e lancia.
    private func readLocked(_ url: URL) throws -> StoredCheckin? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GuestRecordStoreError.unreadable
        }
        do {
            return try JSONDecoder().decode(StoredCheckin.self, from: data)
        } catch {
            var aside = directory.appendingPathComponent(url.lastPathComponent + ".corrupt")
            if fm.fileExists(atPath: aside.path) {
                aside = directory.appendingPathComponent(url.lastPathComponent + "." + UUID().uuidString + ".corrupt")
            }
            try? fm.moveItem(at: url, to: aside)
            throw GuestRecordStoreError.corrupt
        }
    }

    /// Scrittura atomica (`.atomic` scrive in un file temporaneo univoco e lo sostituisce). Protezione «fino al primo
    /// sblocco» (come `filesDir` dell'Android): bloccare il telefono durante un invio non rende illeggibile l'esito.
    private func writeLocked(_ c: StoredCheckin) throws {
        let target = fileURL(c.propertyId, c.reservationId)
        if c.records.isEmpty {
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            return
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(c)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func filesLocked(_ suffix: String) -> [URL] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(suffix) }
    }

    /// Le prenotazioni leggibili e se qualche file non si è letto.
    private func allLocked() -> (items: [StoredCheckin], failures: Int) {
        var items: [StoredCheckin] = []
        var failures = 0
        for url in filesLocked(".json") {
            do {
                if let c = try readLocked(url) { items.append(c) }
            } catch {
                failures += 1
            }
        }
        return (items, failures)
    }

    func list(propertyId: String, reservationId: String) throws -> [GuestRecord] {
        try withLock { try readLocked(fileURL(propertyId, reservationId))?.records ?? [] }
    }

    func get(propertyId: String, reservationId: String) throws -> StoredCheckin? {
        try withLock { try readLocked(fileURL(propertyId, reservationId)) }
    }

    /// Aggiunge o sostituisce (stesso id) una scheda; ne assegna l'id se manca. `checkOut` 0 = tieni la data nota.
    @discardableResult
    func save(_ record: GuestRecord, checkOut: Int64) throws -> GuestRecord {
        try withLock {
            var saved = record
            if saved.id.trimmed.isEmpty { saved.id = newId() }
            let stored = try readLocked(fileURL(saved.propertyId, saved.reservationId))
            var records = stored?.records ?? []
            if let index = records.firstIndex(where: { $0.id == saved.id }) {
                records[index] = saved
            } else {
                records.append(saved)
            }
            let keptCheckOut = checkOut != 0 ? checkOut : (stored?.checkOut ?? 0)
            try writeLocked(StoredCheckin(propertyId: saved.propertyId, reservationId: saved.reservationId,
                                          checkOut: keptCheckOut, records: records))
            return saved
        }
    }

    func replaceAll(propertyId: String, reservationId: String, checkOut: Int64, records: [GuestRecord]) throws {
        try withLock {
            try writeLocked(StoredCheckin(propertyId: propertyId, reservationId: reservationId, checkOut: checkOut, records: records))
        }
    }

    func delete(propertyId: String, reservationId: String, id: String) throws {
        try withLock {
            guard var current = try readLocked(fileURL(propertyId, reservationId)) else { return }
            current.records.removeAll { $0.id == id }
            try writeLocked(current)
        }
    }

    func deleteReservation(propertyId: String, reservationId: String) throws {
        try withLock {
            let url = fileURL(propertyId, reservationId)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }

    /// Salta i file rovinati (messi da parte) o illeggibili; vedi `hasUnsent`.
    func all() -> [StoredCheckin] { withLock { allLocked().items } }

    /// Un file rovinato o illeggibile potrebbe contenere schede mai inviate: nel dubbio c'è qualcosa da inviare.
    func hasUnsent() -> Bool {
        withLock {
            let (items, failures) = allLocked()
            let unsent = items.contains { c in c.records.contains { !$0.schedInaSent } }
            return unsent || failures > 0 || !filesLocked(".corrupt").isEmpty
        }
    }

    /// Cancella le prenotazioni con tutte le schede inviate da più di 30 giorni. Restituisce quante.
    @discardableResult
    func purgeExpired(now: Int64) -> Int {
        withLock {
            let expired = allLocked().items.filter { SendPlan.isExpired($0, now: now) }
            for c in expired { try? fm.removeItem(at: fileURL(c.propertyId, c.reservationId)) }
            return expired.count
        }
    }

    func clear() throws {
        try withLock {
            if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        }
    }
}
