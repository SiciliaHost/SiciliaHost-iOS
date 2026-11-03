import FirebaseFunctions
import Foundation
import Observation
import WebKit

// Import di un annuncio nella creazione guidata (`ListingFetcher.kt`, `ImportRepository.kt`, `ImportViewModel.kt`): il
// telefono scarica le pagine, le callable le interpretano. Nessun log: URL, HTML ed errori contengono dati dell'host o
// dell'annuncio.

// MARK: Download delle pagine

enum FetchResult {
    case html(String)
    /// Testo breve per l'host.
    case failed(String)
}

/// Blocca i reindirizzamenti automatici: ogni salto si controlla (https, host Airbnb) prima di seguirlo.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}

private let airbnbUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
private let airbnbMaxHops = 3
private let tooBigAirbnb = "La pagina di Airbnb è troppo grande"

/// Airbnb risponde a una GET normale con tutta la pagina (200, circa 500 KB).
func fetchAirbnbHtml(_ url: String) async -> FetchResult {
    guard isHttpsUrl(url), var current = URL(string: url) else { return .failed("Il link di Airbnb non è valido") }
    let delegate = NoRedirects()
    do {
        for hop in 0 ... airbnbMaxHops {
            guard isSafeAirbnbUrl(current) else { return .failed("Il link ha portato fuori da Airbnb") }
            var request = URLRequest(url: current, timeoutInterval: 25)
            request.setValue(airbnbUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("it-IT,it;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else { return .failed("Non riesco a raggiungere Airbnb") }
            let code = http.statusCode
            if (300 ... 399).contains(code) {
                guard let location = http.value(forHTTPHeaderField: "Location") else {
                    return .failed("Airbnb non ha risposto (codice \(code))")
                }
                if hop == airbnbMaxHops { return .failed("Troppi reindirizzamenti da Airbnb") }
                guard let next = resolveRedirect(current, location) else { return .failed("Il link ha portato fuori da Airbnb") }
                current = next
                continue
            }
            if code != 200 { return .failed("Airbnb non ha risposto (codice \(code))") }
            if http.expectedContentLength > Int64(maxHtmlChars) * 4 { return .failed(tooBigAirbnb) }
            var buffer = CappedBuffer(maxBytes: maxHtmlChars * 4)
            var chunk = Data()
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 64 * 1024 {
                    guard buffer.append(chunk) else { return .failed(tooBigAirbnb) }
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            guard buffer.append(chunk) else { return .failed(tooBigAirbnb) }
            let html = String(decoding: buffer.data, as: UTF8.self)
            return html.count > maxHtmlChars ? .failed(tooBigAirbnb) : .html(html)
        }
        return .failed("Troppi reindirizzamenti da Airbnb")
    } catch {
        return .failed("Non riesco a raggiungere Airbnb")
    }
}

/// Booking risponde a un download normale con una sfida JavaScript (AWS WAF): serve un vero browser. Si carica la
/// pagina in una WKWebView nascosta e si aspetta che compaia la cache dati. NON PROVATO su un iPhone (come sull'Android):
/// è il punto da verificare per primo.
@MainActor
func fetchBookingHtml(_ url: String) async -> FetchResult {
    guard isHttpsUrl(url), let target = URL(string: url) else { return .failed("Il link di Booking non è valido") }
    let configuration = WKWebViewConfiguration()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    defer { webView.stopLoading() }
    webView.load(URLRequest(url: target))

    let deadline = Date().addingTimeInterval(30)
    var ready = false
    while Date() < deadline && !Task.isCancelled {
        if await evaluate(webView, "document.querySelector('script[data-capla-store-data]') !== null") as? Bool == true {
            ready = true
            break
        }
        try? await Task.sleep(for: .seconds(1))
    }
    guard ready else { return .failed("Booking non si è aperto: prova con Airbnb o compila a mano") }
    guard let html = await evaluate(webView, "document.documentElement.outerHTML") as? String, !html.isEmpty,
          looksLikeBookingData(html) else {
        return .failed("Booking non ha dato i dati dell'annuncio")
    }
    return html.count > maxHtmlChars ? .failed("La pagina di Booking è troppo grande") : .html(html)
}

/// Esegue uno script nella pagina: nil se fallisce (pagina non ancora pronta, sfida in corso).
@MainActor
private func evaluate(_ webView: WKWebView, _ script: String) async -> Any? {
    await withCheckedContinuation { continuation in
        webView.evaluateJavaScript(script) { value, _ in continuation.resume(returning: value) }
    }
}

// MARK: Callable

/// Una pagina già scaricata dal telefono, pronta da interpretare.
struct ImportSource {
    let portal: Portal
    let url: String
    let html: String
}

struct ImportService {
    private let functions = Functions.functions()

    struct InvalidResponse: LocalizedError {
        var errorDescription: String? { "Risposta dell'import non valida" }
    }

    /// Registra la dichiarazione di proprietà (chi, quando, quali link) e restituisce l'annuncio unito.
    func importListing(_ sources: [ImportSource]) async throws -> ListingImport {
        let payload: [String: Any] = [
            "sources": sources.map { ["portal": $0.portal.wire, "url": $0.url, "html": $0.html] },
            "declaration": ["confirmed": true, "termsVersion": ownershipTextVersion] as [String: Any],
        ]
        let callable = functions.httpsCallable("importListing")
        callable.timeoutInterval = 70
        let result = try await callable.call(payload)
        guard let parsed = parseListingImport(result.data) else { throw InvalidResponse() }
        return parsed
    }

    /// Un lotto di foto (massimo 6 per chiamata): si richiama con `nextOffset` finché è nil.
    func importPhotos(propertyId: String, importId: String, offset: Int) async throws -> PhotoBatch {
        let callable = functions.httpsCallable("importListingPhotos")
        callable.timeoutInterval = 130
        let result = try await callable.call(["propertyId": propertyId, "importId": importId, "offset": offset] as [String: Any])
        guard let parsed = parsePhotoBatch(result.data) else { throw InvalidResponse() }
        return parsed
    }
}

// MARK: Stato

enum PortalStatus { case waiting, downloading, ok, failed }

enum ImportUi {
    case idle
    /// Una voce per link inserito: l'icona del portale si accende da sola quando la pagina arriva.
    case running([Portal: PortalStatus])
    case done(ListingImport, [Portal: PortalStatus])
    case failed(String, [Portal: PortalStatus])

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var result: ListingImport? {
        if case let .done(result, _) = self { return result }
        return nil
    }
}

enum PhotoUi: Equatable {
    case idle
    case running(done: Int, total: Int)
    case done(saved: Int, failed: Int)
    case failed(message: String, saved: Int)
}

/// Il wizard deve applicare l'import adesso? Solo a import finito e mai già applicato.
func shouldApplyImport(_ ui: ImportUi, applied: AppliedImport?) -> Bool { ui.result != nil && applied == nil }

/// Orchestra l'import (`ImportViewModel.kt`): tiene anche il risultato e la patch da scrivere sulla casa quando esiste.
@MainActor
@Observable
final class ImportModel {
    private(set) var ui: ImportUi = .idle
    private(set) var photoUi: PhotoUi = .idle
    /// L'import già applicato alle bozze (una volta sola).
    private(set) var applied: AppliedImport?
    private(set) var importId: String?
    private(set) var photoTotal = 0

    /// Servizi, regole e tipo di check-in: si scrivono sulla casa appena esiste, poi `clearSitePatch`.
    private(set) var pendingPatch: [String: Any] = [:]
    @ObservationIgnored private var progress: PhotoProgress?
    @ObservationIgnored private var failedPhotos = 0

    private let service = ImportService()
    private let siteRepo = SiteContentService()

    /// `links` = i link già puliti (`cleanListingUrl`) per portale; vuota = niente da fare.
    func start(links: [Portal: String]) async {
        guard !links.isEmpty, !ui.isRunning else { return }
        var status = Dictionary(uniqueKeysWithValues: links.keys.map { ($0, PortalStatus.downloading) })
        ui = .running(status)
        var fetched: [(Portal, String, FetchResult)] = []
        await withTaskGroup(of: (Portal, String, FetchResult).self) { group in
            for (portal, url) in links {
                group.addTask {
                    switch portal {
                    case .airbnb: return (portal, url, await fetchAirbnbHtml(url))
                    case .booking: return (portal, url, await fetchBookingHtml(url))
                    }
                }
            }
            for await item in group {
                if case .html = item.2 { status[item.0] = .ok } else { status[item.0] = .failed }
                await self.showRunning(status)
                fetched.append(item)
            }
        }
        let sources: [ImportSource] = fetched.compactMap { portal, url, result in
            if case let .html(html) = result { return ImportSource(portal: portal, url: url, html: html) }
            return nil
        }
        guard !sources.isEmpty else {
            let why = fetched.compactMap { item -> String? in
                if case let .failed(reason) = item.2 { return reason }
                return nil
            }.first ?? "Import non riuscito"
            ui = .failed("\(why). Puoi compilare a mano.", status)
            return
        }
        do {
            let result = try await service.importListing(sources)
            importId = result.importId
            photoTotal = result.draft.photos.count
            ui = .done(result, status)
        } catch {
            ui = .failed(describeImportError(error), status)
        }
    }

    private func showRunning(_ status: [Portal: PortalStatus]) { ui = .running(status) }

    /// Il wizard ha applicato l'import alle bozze: si tiene la patch da scrivere alla creazione della casa.
    func markApplied(_ a: AppliedImport) {
        applied = a
        pendingPatch = a.sitePatch
    }

    /// Da chiamare solo a scrittura riuscita: se fallisce, al prossimo «Avanti» si riprova.
    func clearSitePatch() { pendingPatch = [:] }

    func reset() {
        ui = .idle
        photoUi = .idle
        applied = nil
        importId = nil
        photoTotal = 0
        pendingPatch = [:]
        progress = nil
        failedPhotos = 0
    }

    /// Scarica le foto a lotti e le aggiunge all'elenco della casa. `existing` = le foto già sulla casa: conta solo alla
    /// PRIMA chiamata (fissa la base); le ripartenze usano base e offset già tenuti. `onProgress` a ogni lotto scritto.
    func importPhotos(propertyId: String, existing: [String], onProgress: @escaping () async -> Void) async {
        guard let id = importId, photoTotal > 0 else { return }
        switch photoUi {
        case .running, .done: return
        default: break
        }
        var p = progress ?? PhotoProgress(base: existing)
        progress = p
        photoUi = .running(done: p.offset, total: photoTotal)
        do {
            while true {
                if !p.finished {
                    let batch = try await service.importPhotos(propertyId: propertyId, importId: id, offset: p.offset)
                    failedPhotos += batch.failedCount
                    // Il lotto si conta subito: se la scrittura sotto fallisce, «Riprova» non lo riscarica.
                    p = p.afterBatch(batch.stored, next: batch.nextOffset)
                    progress = p
                }
                if p.unwritten {
                    try await siteRepo.upsert(propertyId: propertyId, patch: ["photos": p.photos()])
                    p = p.written()
                    progress = p
                    await onProgress()
                }
                photoUi = .running(done: p.finished ? photoTotal : p.offset, total: photoTotal)
                if p.finished { break }
            }
            photoUi = .done(saved: p.saved.count, failed: failedPhotos)
        } catch {
            photoUi = .failed(message: describeImportError(error), saved: p.saved.count)
        }
    }

    /// «Riprova» dopo un errore delle foto: riparte dal lotto che non è andato.
    func retryPhotos(propertyId: String, existing: [String], onProgress: @escaping () async -> Void) async {
        if case .failed = photoUi { photoUi = .idle }
        await importPhotos(propertyId: propertyId, existing: existing, onProgress: onProgress)
    }
}
