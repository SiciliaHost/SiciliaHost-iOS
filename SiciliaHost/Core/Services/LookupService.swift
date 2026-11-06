import Foundation

/// Tabelle di codifica Alloggiati (tipi, documenti, luoghi), in cache sul telefono per 30 giorni. Il download (`fetchTable`)
/// va direttamente al servizio della Polizia con le credenziali del portachiavi di questo telefono (vedi `CheckinModel`).
/// Sono tabelle pubbliche uguali per tutte le case, quindi la cache non dipende dalla casa.
actor LookupService {
    private let ttl: TimeInterval = 30 * 24 * 3600
    private let directory: URL
    private let fetchTable: @Sendable (_ tipo: String) async throws -> String

    init(directory: URL? = nil, fetchTable: @escaping @Sendable (_ tipo: String) async throws -> String) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("alloggiati", isDirectory: true)
        self.fetchTable = fetchTable
    }

    func tipiAlloggiato() async -> [LookupEntry] { await getOrFetch(file: "tipi_alloggiato.csv", tipo: "Tipi_Alloggiato") }
    func tipiDocumento() async -> [LookupEntry] { await getOrFetch(file: "tipi_documento.csv", tipo: "Tipi_Documento") }
    func luoghi() async -> [LookupEntry] { await getOrFetch(file: "luoghi.csv", tipo: "Luoghi") }

    private func getOrFetch(file: String, tipo: String) async -> [LookupEntry] {
        let url = directory.appendingPathComponent(file)
        let fm = FileManager.default
        let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        let isStale = modified.map { Date().timeIntervalSince($0) > ttl } ?? true
        if isStale {
            // Se il download fallisce si usa la copia vecchia (se c'è): meglio tabelle scadute che nessuna.
            if let csv = try? await fetchTable(tipo), !csv.trimmed.isEmpty {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Self.parseCsv(text)
    }

    /// Righe `codice;descrizione` dopo l'intestazione; le righe senza due campi si scartano.
    static func parseCsv(_ csv: String) -> [LookupEntry] {
        csv.components(separatedBy: .newlines)
            .dropFirst() // intestazione
            .filter { !$0.trimmed.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: ";")
                guard parts.count >= 2 else { return nil }
                return LookupEntry(code: parts[0].trimmed, description: parts[1].trimmed)
            }
    }

    /// Ricerca dei luoghi per nome: serve almeno 2 caratteri, al massimo 30 risultati.
    static func filterLuoghi(_ list: [LookupEntry], query: String) -> [LookupEntry] {
        if query.count < 2 { return [] }
        return Array(list.filter { $0.description.range(of: query, options: .caseInsensitive) != nil }.prefix(30))
    }
}
