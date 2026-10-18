import Foundation

// Geometria pura per la posizione delle case: nessuna dipendenza da MapKit. Le costanti rispecchiano il server
// (functions/src/properties/geo.ts): il raggio pubblico è 300 m; l'editor tiene il centro dell'area a 50-250 m dal
// pin, più stretto della finestra 30-300 m accettata dal server, così gli arrotondamenti non fanno mai rifiutare
// un salvataggio valido.

struct LatLng: Equatable, Sendable {
    var lat: Double
    var lng: Double
}

let areaRadiusM = 300.0
let minAreaOffsetM = 50.0
let maxAreaOffsetM = 250.0
let defaultAreaOffsetM = 150.0

private let earthRadiusM = 6_371_000.0

// 2 * pi * R / 360: metri per grado di latitudine (coerente con l'Haversine del server).
private let metersPerDegree = 111_195.0

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

extension LatLng {
    /// Coordinate finite e nei limiti geografici (come `isLatLng` del server): NaN e infiniti non passano.
    var isValid: Bool {
        lat.isFinite && lng.isFinite && (-90.0 ... 90.0).contains(lat) && (-180.0 ... 180.0).contains(lng)
    }

    /// Sei decimali: ~0,1 m, abbastanza per il pin e stabile nel round-trip testo <-> numero. Un punto non valido
    /// resta invariato: arrotondare NaN darebbe 0 e sposterebbe il pin a (0, 0).
    func rounded() -> LatLng {
        // Math.round di Java: arrotonda i .5 verso +infinito.
        func round6(_ value: Double) -> Double { ((value * 1e6) + 0.5).rounded(.down) / 1e6 }
        return isValid ? LatLng(lat: round6(lat), lng: round6(lng)) : self
    }

    /// Questo punto traslato dello stesso vettore `from` → `to` (l'area segue il pin).
    func shifted(from: LatLng, to: LatLng) -> LatLng {
        LatLng(lat: lat + (to.lat - from.lat), lng: lng + (to.lng - from.lng))
    }
}

func distanceMeters(_ a: LatLng, _ b: LatLng) -> Double {
    let dLat = radians(b.lat - a.lat)
    let dLng = radians(b.lng - a.lng)
    let h = sin(dLat / 2) * sin(dLat / 2) + cos(radians(a.lat)) * cos(radians(b.lat)) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * earthRadiusM * asin(min(1.0, h.squareRoot()))
}

/// Punto a `eastM` metri a est e `northM` a nord di `origin` (piano locale: esatto sotto 1 km).
func offsetMeters(_ origin: LatLng, eastM: Double, northM: Double) -> LatLng {
    LatLng(
        lat: origin.lat + northM / metersPerDegree,
        lng: origin.lng + eastM / (metersPerDegree * cos(radians(origin.lat)))
    )
}

/// Vettore (est, nord) in metri da `from` a `to`.
private func vectorMeters(_ from: LatLng, _ to: LatLng) -> (east: Double, north: Double) {
    ((to.lng - from.lng) * metersPerDegree * cos(radians(from.lat)), (to.lat - from.lat) * metersPerDegree)
}

/// Centro dell'area a `offsetM` dal pin, nella direzione `bearingRad` (0 = nord, pi/2 = est).
func defaultAreaCenter(exact: LatLng, bearingRad: Double, offsetM: Double = defaultAreaOffsetM) -> LatLng {
    offsetMeters(exact, eastM: sin(bearingRad) * offsetM, northM: cos(bearingRad) * offsetM)
}

/// Porta `candidate` dentro `minAreaOffsetM`...`maxAreaOffsetM` da `exact`, mantenendo la direzione. Un candidato
/// sopra al pin (direzione indefinita) va a nord invece di dividere per zero. Se `exact` o `candidate` non sono
/// valide (NaN, infiniti, fuori range) restituisce `candidate` invariato: meglio un valore visibilmente sbagliato
/// che un calcolo che propaga NaN.
func clampAreaCenter(exact: LatLng, candidate: LatLng) -> LatLng {
    if !exact.isValid || !candidate.isValid { return candidate }
    let (east, north) = vectorMeters(exact, candidate)
    let d = (east * east + north * north).squareRoot()
    if (minAreaOffsetM ... maxAreaOffsetM).contains(d) { return candidate }
    let (ux, uy) = d < 1e-6 ? (0.0, 1.0) : (east / d, north / d)
    let target = min(max(d, minAreaOffsetM), maxAreaOffsetM)
    return offsetMeters(exact, eastM: ux * target, northM: uy * target)
}
