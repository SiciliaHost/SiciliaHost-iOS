import Foundation

/// Il file delle finanze di UN utente (`Application Support/finance/<uid>/finance.json`). Scritture atomiche e
/// serializzate dall'actor. Un file illeggibile non fa crashare la schermata: si mette da parte come `finance.json.bad`
/// e si riparte vuoti (`wasCorrupt`). Il file è incluso nel backup di sistema.
actor FinanceStore {
    private let fileURL: URL
    private var cache: FinanceData?
    private(set) var wasCorrupt = false

    init(fileURL: URL) { self.fileURL = fileURL }

    /// UNA sola istanza per account e per cartella: cache e serializzazione vivono nell'istanza, quindi due `actor`
    /// sullo stesso file perderebbero scritture (la cache vecchia sovrascrive l'import appena fatto) e potrebbero
    /// interlacciarsi; un `wipe()` non svuoterebbe le altre cache. Una cartella per account: due account sullo
    /// stesso iPhone non si vedono. `base` serve solo ai test.
    static func forUser(_ uid: String, base: URL? = nil) -> FinanceStore {
        let root = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("finance/\(uid)/finance.json")
        return FinanceStoreRegistry.shared.store(for: url)
    }

    func read() -> FinanceData {
        if let cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    /// Legge, applica `transform`, salva e restituisce il nuovo stato. Se la scrittura fallisce l'errore sale e la cache resta com'era.
    @discardableResult
    func update(_ transform: (FinanceData) -> FinanceData) throws -> FinanceData {
        let next = transform(read())
        try write(next)
        cache = next
        return next
    }

    /// Cancella tutto (eliminazione dell'account).
    func wipe() {
        cache = FinanceData()
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(atPath: fileURL.path + ".bad")
    }

    private func load() -> FinanceData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return FinanceData() }
        do {
            return try JSONDecoder().decode(FinanceData.self, from: Data(contentsOf: fileURL))
        } catch {
            wasCorrupt = true
            let bad = URL(fileURLWithPath: fileURL.path + ".bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: fileURL, to: bad)
            return FinanceData()
        }
    }

    private func write(_ data: FinanceData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Registro delle istanze (una per file). Classe con lock e non un actor: `forUser` è sincrona.
final class FinanceStoreRegistry: @unchecked Sendable {
    static let shared = FinanceStoreRegistry()
    private let lock = NSLock()
    private var stores: [String: FinanceStore] = [:]

    func store(for url: URL) -> FinanceStore {
        lock.lock(); defer { lock.unlock() }
        if let existing = stores[url.path] { return existing }
        let made = FinanceStore(fileURL: url)
        stores[url.path] = made
        return made
    }
}
