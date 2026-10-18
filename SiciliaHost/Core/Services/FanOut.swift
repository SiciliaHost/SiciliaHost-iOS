import Foundation

/// Una query per casa, in parallelo, risultati uniti nell'ordine degli id. Le firestore.rules accettano solo
/// query vincolate a una casa (`propertyId == X`): una query unica sulla collezione verrebbe rifiutata per
/// intero. Se una query fallisce, fallisce tutto (meglio un errore visibile che un elenco silenziosamente incompleto).
func fanOut<T: Sendable>(
    _ propertyIds: [String],
    fetch: @escaping @Sendable (String) async throws -> [T]
) async throws -> [T] {
    try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
        for (index, id) in propertyIds.enumerated() {
            group.addTask { (index, try await fetch(id)) }
        }
        var chunks = [[T]](repeating: [], count: propertyIds.count)
        for try await (index, items) in group { chunks[index] = items }
        return chunks.flatMap { $0 }
    }
}
