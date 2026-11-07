import Foundation

/// Sincronizzazione di un calendario iCal (Airbnb/Booking) con le prenotazioni (`ICalSyncWorker.doWork` dell'Android).
/// Scarica il feed, calcola il piano con `ICalSync.buildSyncPlan` (parte pura, con gli echi Booking) e lo scrive.
struct ICalSyncService {
    private let db = FirestoreService()
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// Lancia `ServiceError` con un motivo sicuro da mostrare (mai l'URL: i link iCal contengono un token segreto).
    func sync(propertyId: String, url: String, platform: String) async throws {
        do {
            let text = try await download(url)
            let events = ICalSync.parseEvents(text)

            let now = millisFromDate(Date())
            // Tutte le piattaforme: per Booking servono anche Airbnb e MANUAL (riconoscere gli echi).
            let future = try await db.getReservations(propertyIds: [propertyId]).filter { $0.checkOut > now }
            let plan = ICalSync.buildSyncPlan(
                events: events, propertyId: propertyId, platform: platform,
                existingFutureReservations: future.filter { $0.platform == platform },
                otherFutureReservations: future.filter { $0.platform != platform },
                now: now
            )

            if !plan.toUpsert.isEmpty { _ = try await db.syncIcalReservationsBatch(plan.toUpsert) }
            // Solo la prenotazione condivisa: spese e importi rimasti sul telefono li ripulisce `FinanceRepository` (orfani).
            for reservation in plan.toDelete {
                try await db.deleteReservation(reservation.id)
            }
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError(message: ICalSync.safeErrorReason(error))
        }
    }

    /// Sincronizza i calendari configurati di una casa; ritorna i fallimenti come «AIRBNB: motivo».
    func syncProperty(_ property: Property) async -> [String] {
        var failed: [String] = []
        for (platform, url) in Self.feeds(of: property) {
            do {
                try await sync(propertyId: property.id, url: url, platform: platform)
            } catch {
                failed.append("\(platform): \(error.localizedDescription)")
            }
        }
        return failed
    }

    /// I feed configurati di una casa, nell'ordine Airbnb → Booking.
    static func feeds(of property: Property) -> [(platform: String, url: String)] {
        [("AIRBNB", property.icalUrlAirbnb), ("BOOKING", property.icalUrlBooking)].compactMap { platform, url in
            let clean = (url ?? "").trimmed
            return clean.isEmpty ? nil : (platform, clean)
        }
    }

    private func download(_ url: String) async throws -> String {
        guard let feedURL = URL(string: url), feedURL.scheme?.lowercased() == "https" else {
            throw ServiceError(message: "L'URL iCal deve iniziare con https://")
        }
        let (data, response) = try await session.data(for: URLRequest(url: feedURL, timeoutInterval: 30))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError(message: "Risposta HTTP \(http.statusCode)")
        }
        let text = String(decoding: data, as: UTF8.self)
        // Una risposta non-iCal (URL morto, pagina di errore HTML) non deve mai essere letta come "calendario vuoto".
        guard ICalSync.isValidFeed(text) else { throw ServiceError(message: "Risposta non è un calendario iCal valido") }
        return text
    }
}
