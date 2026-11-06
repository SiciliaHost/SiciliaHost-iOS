import Foundation

/// Le ricevute di Alloggiati Web contengono i nomi degli ospiti (porta di `ReceiptFiles.kt`): un solo file,
/// `Caches/ricevute/ricevuta.pdf`, sovrascritto a ogni download e cancellato insieme alle schede (uscita, Profilo, account
/// eliminato) e all'apertura dell'app se più vecchio di un giorno (su iOS non c'è WorkManager).
enum ReceiptFiles {
    static let fileName = "ricevuta.pdf"
    static let maxAge: TimeInterval = 24 * 60 * 60

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ricevute", isDirectory: true)
    }

    /// Scrive la ricevuta (sostituendo quella di prima) e ne restituisce il percorso.
    static func write(_ pdf: Data, directory: URL = ReceiptFiles.directory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try pdf.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    static func clear(directory: URL = ReceiptFiles.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Cancella le ricevute più vecchie di `maxAge`.
    static func purgeOlderThan(_ maxAge: TimeInterval = ReceiptFiles.maxAge, now: Date = Date(),
                               directory: URL = ReceiptFiles.directory) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > maxAge { try? fm.removeItem(at: url) }
        }
    }
}

/// Pulizie all'apertura dell'app (al posto di `GuestRecordPurgeWorker`): schede inviate da più di 30 giorni, ricevute
/// più vecchie di un giorno, credenziali rimaste da un'installazione precedente.
enum CheckinHousekeeping {
    static func onAppStart(now: Date = Date()) {
        KeychainCredentialStore.clearIfFreshInstall()
        ReceiptFiles.purgeOlderThan(now: now)
        GuestRecordStore.shared.purgeExpired(now: Int64(now.timeIntervalSince1970 * 1000))
    }
}
