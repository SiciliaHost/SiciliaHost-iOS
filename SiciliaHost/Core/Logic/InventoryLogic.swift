import Foundation

// Logica pura delle Scorte (`ui/inventory/StockStatus.kt` e le parti pure di `InventoryScreen.kt`).

/// Stato di una scorta: colore ed etichetta in riga e nel dettaglio. Giallo = da rifornire, rosso = esaurito, verde = ok.
enum StockStatus: Equatable {
    case ok, low, depleted

    var label: String {
        switch self {
        case .depleted: return "ESAURITO"
        case .low: return "SOTTO SOGLIA"
        case .ok: return "SCORTA OK"
        }
    }
}

/// Il flag `isDepleted` vince sulla quantità; altrimenti quantità <= soglia è "bassa".
func stockStatus(_ item: InventoryItem) -> StockStatus {
    if item.isDepleted { return .depleted }
    if item.quantity <= item.lowStockThreshold { return .low }
    return .ok
}

/// Normalizza un codice a barre scansionato o digitato: lo stesso UPC-A può essere letto a 12 cifre o come EAN-13 con
/// lo zero davanti; senza questa regola un prodotto già registrato sembrerebbe nuovo.
func normalizeBarcode(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count == 12 && trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) { return "0" + trimmed }
    return trimmed
}

enum InventoryLogic {
    static let allCategories = "Tutte"
    static let categories = ["Consumabili", "Pulizia", "Biancheria", "Altro"]
    static var filterCategories: [String] { [allCategories] + categories }

    /// Filtri dell'elenco: casa (nil = tutte), categoria ("Tutte" = tutte), ricerca nel nome senza maiuscole.
    static func filter(_ items: [InventoryItem], propertyId: String?, category: String, search: String) -> [InventoryItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            (propertyId == nil || item.propertyId == propertyId)
                && (category == allCategories || item.category == category)
                && (query.isEmpty || item.name.range(of: query, options: .caseInsensitive) != nil)
        }
    }

    /// Lo stesso prodotto (codice normalizzato) già registrato in quella casa.
    static func existing(barcode: String, propertyId: String, in items: [InventoryItem]) -> InventoryItem? {
        items.first { $0.propertyId == propertyId && $0.barcode.map(normalizeBarcode) == barcode }
    }

    /// Un nome già dato a quel codice in un'altra casa dell'utente (vale più della ricerca online).
    static func knownName(barcode: String, in items: [InventoryItem]) -> String? {
        items.first { $0.barcode.map(normalizeBarcode) == barcode && !$0.name.trimmed.isEmpty }?.name
    }

    // Transizioni della quantità, come i pulsanti dell'Android.

    static func plusOne(_ item: InventoryItem) -> InventoryItem {
        var u = item
        u.quantity += 1
        u.isDepleted = false
        return u
    }

    /// nil se la quantità è già zero (il pulsante non fa nulla).
    static func minusOne(_ item: InventoryItem) -> InventoryItem? {
        guard item.quantity > 0 else { return nil }
        var u = item
        u.quantity -= 1
        u.isDepleted = u.quantity == 0
        return u
    }

    static func reportDepleted(_ item: InventoryItem) -> InventoryItem {
        var u = item
        u.quantity = 0
        u.isDepleted = true
        return u
    }

    static func adding(_ count: Int, to item: InventoryItem) -> InventoryItem {
        var u = item
        u.quantity += count
        u.isDepleted = false
        return u
    }

    /// Quantità impostata nel riepilogo della scansione multipla (mai sotto zero).
    static func settingQuantity(_ quantity: Int, of item: InventoryItem) -> InventoryItem {
        var u = item
        u.quantity = max(quantity, 0)
        u.isDepleted = quantity <= 0
        return u
    }

    /// Modifica manuale: quantità o soglia non numeriche restano quelle di prima; codice vuoto = nessun codice.
    static func edited(
        _ item: InventoryItem, name: String, barcode: String, category: String, quantity: String, threshold: String
    ) -> InventoryItem {
        var u = item
        let qty = Int(quantity.trimmed) ?? item.quantity
        u.name = name.trimmed
        u.barcode = barcode.trimmed.isEmpty ? nil : normalizeBarcode(barcode)
        u.quantity = qty
        u.lowStockThreshold = Int(threshold.trimmed) ?? item.lowStockThreshold
        u.isDepleted = qty <= 0
        u.category = category
        return u
    }

    /// Nuovo prodotto (aggiunta manuale o dopo una scansione). Quantità non numerica = 1, soglia = 2.
    static func newItem(
        propertyId: String, name: String, barcode: String?, category: String, quantity: String, threshold: String = "2"
    ) -> InventoryItem {
        let qty = Int(quantity.trimmed) ?? 1
        let code = barcode?.trimmed
        return InventoryItem(
            propertyId: propertyId,
            name: name.trimmed,
            barcode: (code?.isEmpty ?? true) ? nil : normalizeBarcode(code!),
            quantity: qty,
            lowStockThreshold: Int(threshold.trimmed) ?? 2,
            isDepleted: qty <= 0,
            category: category
        )
    }

    /// Nome della risposta di Open Food Facts / Open Products Facts (`status == 1` e `product.product_name` non vuoto).
    static func productName(fromOpenFactsJson data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["status"] as? NSNumber)?.intValue == 1,
              let product = json["product"] as? [String: Any],
              let name = (product["product_name"] as? String)?.trimmed, !name.isEmpty
        else { return nil }
        return name
    }
}

/// Nome di un prodotto dal codice a barre: prima il catalogo alimentare, poi quello dei prodotti non alimentari (pulizia,
/// casa…). Servizi liberi senza chiave; si identifica con lo stesso User-Agent usato per OpenStreetMap.
enum ProductLookup {
    static func name(for barcode: String) async -> String? {
        for host in ["world.openfoodfacts.org", "world.openproductsfacts.org"] {
            if let name = await name(host: host, barcode: barcode) { return name }
        }
        return nil
    }

    private static func name(host: String, barcode: String) async -> String? {
        let code = barcode.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? barcode
        guard let url = URL(string: "https://\(host)/api/v2/product/\(code).json?fields=product_name") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(osmUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return InventoryLogic.productName(fromOpenFactsJson: data)
    }
}
