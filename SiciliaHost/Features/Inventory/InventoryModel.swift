import Foundation
import Observation

/// Dati e azioni delle Scorte (lo stato che su Android sta dentro `InventoryScreen.kt`). Ogni modifica aggiorna subito
/// l'elenco in memoria e poi scrive su Firestore, come l'Android.
@MainActor
@Observable
final class InventoryModel {
    private(set) var items: [InventoryItem] = []
    private(set) var properties: [Property] = []
    /// Finché l'inventario non è caricato, una scansione farebbe sembrare nuovo un prodotto già registrato.
    private(set) var isLoading = true
    var message: String?

    // Scansione multipla in corso.
    private(set) var batchItemIds: [String] = []
    private(set) var batchScanCount = 0
    private(set) var batchLastMessage: String?
    @ObservationIgnored private var batchBusy = false

    private let db: FirestoreService?

    init(db: FirestoreService? = FirestoreService(), preview: (items: [InventoryItem], properties: [Property])? = nil) {
        self.db = db
        if let preview {
            items = preview.items
            properties = preview.properties
            isLoading = false
        }
    }

    func load(scope: AccessScope?) async {
        guard let db else { return }
        let operable = scope?.operable ?? []
        properties = operable
        defer { isLoading = false }
        do {
            items = try await db.getInventory(propertyIds: operable.map(\.id))
        } catch {
            message = "Caricamento delle scorte non riuscito. Controlla la connessione."
        }
    }

    func propertyName(_ id: String) -> String { properties.first { $0.id == id }?.name ?? id }

    // MARK: Modifiche

    private func replace(_ updated: InventoryItem) {
        items = items.map { $0.id == updated.id ? updated : $0 }
    }

    func save(_ updated: InventoryItem) {
        replace(updated)
        Task { try? await db?.updateInventoryItem(updated) }
    }

    func plus(_ item: InventoryItem) { save(InventoryLogic.plusOne(item)) }
    func minus(_ item: InventoryItem) { if let u = InventoryLogic.minusOne(item) { save(u) } }
    func reportDepleted(_ item: InventoryItem) { save(InventoryLogic.reportDepleted(item)) }

    func add(_ count: Int, to item: InventoryItem) {
        guard count > 0 else { return }
        save(InventoryLogic.adding(count, to: item))
        message = "Scorte aggiornate!"
    }

    func edit(_ updated: InventoryItem) {
        save(updated)
        if let code = updated.barcode, !updated.name.isEmpty {
            Task { await db?.saveProductToCache(barcode: code, name: updated.name) }
        }
        message = "Prodotto aggiornato!"
    }

    /// Crea un prodotto; il nome confermato diventa quello del codice per le scansioni future. Ritorna il salvato.
    func create(_ item: InventoryItem) async -> InventoryItem? {
        guard let db else { return nil }
        do {
            let saved = try await db.addInventoryItem(item)
            if let code = saved.barcode, !saved.name.isEmpty { await db.saveProductToCache(barcode: code, name: saved.name) }
            items.append(saved)
            message = "Prodotto aggiunto all'inventario!"
            return saved
        } catch {
            message = "Salvataggio non riuscito. Controlla la connessione."
            return nil
        }
    }

    /// Foto del prodotto: JPEG compresso (lato lungo 1600, qualità 0,7) su Storage, poi solo il campo `imageUrl`.
    func uploadPhoto(itemId: String, imageData: Data) async {
        guard let db else { return }
        guard let jpeg = try? PhotoEncoder.encodeJpeg(imageData, maxSide: 1600, quality: 0.7),
              let url = await db.uploadProductImage(itemId: itemId, jpeg: jpeg) else {
            message = "Errore durante il caricamento dell'immagine."
            return
        }
        do {
            try await db.updateInventoryImageUrl(itemId: itemId, imageUrl: url)
            items = items.map { item in
                guard item.id == itemId else { return item }
                var u = item
                u.imageUrl = url
                return u
            }
            message = "Immagine caricata correttamente!"
        } catch {
            message = "Errore durante il caricamento dell'immagine."
        }
    }

    // MARK: Nome dal codice a barre

    /// Nome di un codice: prima un'altra casa dell'utente, poi la cache condivisa, poi la ricerca online (che si salva
    /// in cache). Un nome trovato nell'inventario viene copiato anche in cache.
    func lookupName(_ code: String) async -> String? {
        if let known = InventoryLogic.knownName(barcode: code, in: items) {
            await db?.saveProductToCache(barcode: code, name: known)
            return known
        }
        if let cached = await db?.getCachedProductName(barcode: code) { return cached }
        let online = await ProductLookup.name(for: code)
        if let online { await db?.saveProductToCache(barcode: code, name: online) }
        return online
    }

    // MARK: Scansione multipla

    func startBatch() {
        batchItemIds = []
        batchScanCount = 0
        batchLastMessage = nil
        batchBusy = false
    }

    /// Ogni codice si salva subito: +1 se già presente nella casa, altrimenti nuovo prodotto a quantità 1. Dopo una lettura
    /// si aspetta 1,2 s prima della successiva (lo stesso codice resta inquadrato per più fotogrammi).
    func batchScanned(_ raw: String, propertyId: String) {
        guard !batchBusy else { return }
        batchBusy = true
        let code = normalizeBarcode(raw)
        Task {
            var resultId: String?
            if let existing = InventoryLogic.existing(barcode: code, propertyId: propertyId, in: items) {
                let updated = InventoryLogic.plusOne(existing)
                save(updated)
                batchLastMessage = "\(updated.name) — quantità: \(updated.quantity)"
                resultId = updated.id
            } else {
                let name = await lookupName(code) ?? "Prodotto \(code)"
                // Ricontrollo: la ricerca del nome richiede tempo e l'elenco può essere cambiato.
                if let now = InventoryLogic.existing(barcode: code, propertyId: propertyId, in: items) {
                    let updated = InventoryLogic.plusOne(now)
                    save(updated)
                    batchLastMessage = "\(updated.name) — quantità: \(updated.quantity)"
                    resultId = updated.id
                } else if let db {
                    let new = InventoryItem(propertyId: propertyId, name: name, barcode: code, quantity: 1,
                                            lowStockThreshold: 2, isDepleted: false)
                    if let saved = try? await db.addInventoryItem(new) {
                        items.append(saved)
                        batchLastMessage = "Aggiunto: \(saved.name)"
                        resultId = saved.id
                    } else {
                        batchLastMessage = "Salvataggio non riuscito"
                    }
                }
            }
            if let id = resultId, !batchItemIds.contains(id) { batchItemIds.append(id) }
            if resultId != nil { batchScanCount += 1 }
            try? await Task.sleep(for: .milliseconds(1200))
            batchLastMessage = nil
            batchBusy = false
        }
    }

    /// "Fine" del riepilogo: salva i nomi corretti (e li mette in cache per il codice).
    func finishBatch(editedNames: [String: String]) {
        for (id, newName) in editedNames {
            let trimmed = newName.trimmed
            guard let current = items.first(where: { $0.id == id }), !trimmed.isEmpty, trimmed != current.name else { continue }
            var updated = current
            updated.name = trimmed
            save(updated)
            if let code = current.barcode?.trimmed, !code.isEmpty {
                Task { await db?.saveProductToCache(barcode: normalizeBarcode(code), name: trimmed) }
            }
        }
        batchItemIds = []
    }
}
