import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Logica pura

func movePhoto(_ photos: [String], from: Int, to: Int) -> [String] {
    guard from != to, photos.indices.contains(from), photos.indices.contains(to) else { return photos }
    var mutable = photos
    mutable.insert(mutable.remove(at: from), at: to)
    return mutable
}

func removePhoto(_ photos: [String], at index: Int) -> [String] {
    guard photos.indices.contains(index) else { return photos }
    var mutable = photos
    mutable.remove(at: index)
    return mutable
}

/// Dimensioni finali con il lato lungo limitato a `maxSide`, proporzioni invariate.
func scaledSize(width: Int, height: Int, maxSide: Int = 1600) -> (width: Int, height: Int) {
    let longest = max(width, height)
    if longest <= maxSide { return (width, height) }
    let scale = Double(maxSide) / Double(longest)
    // `roundToInt` di Kotlin: i .5 vanno verso l'alto.
    func round(_ v: Double) -> Int { max(Int((v + 0.5).rounded(.down)), 1) }
    return (round(Double(width) * scale), round(Double(height) * scale))
}

/// Potenza di 2 per la decodifica a basso consumo di memoria (come `inSampleSize` di Android): l'immagine decodificata
/// resta con il lato lungo >= `maxSide`. Su iOS la riduzione la fa ImageIO; resta per parità e per i test.
func sampleSizeFor(width: Int, height: Int, maxSide: Int = 1600) -> Int {
    var sample = 1
    while max(width, height) / (sample * 2) >= maxSide { sample *= 2 }
    return sample
}

/// Gradi di rotazione (senso orario) per raddrizzare un'immagine dato il valore EXIF ORIENTATION. Gli orientamenti
/// speculari (2, 4, 5, 7) non si gestiscono: restano a 0.
func exifRotationDegrees(_ orientation: Int) -> Int {
    switch orientation {
    case 3: return 180
    case 6: return 90
    case 8: return 270
    default: return 0
    }
}

// MARK: Codifica JPEG

enum PhotoEncoder {
    struct EncodingError: LocalizedError {
        var errorDescription: String? { "Impossibile leggere la foto" }
    }

    /// Decodifica la foto scelta, la riduce a lato lungo <= `maxSide` (applicando la rotazione EXIF) e la comprime in
    /// JPEG. Serve a foto della casa (qualità 0,8, 1600 px) e a foto prodotto delle scorte (qualità 0,7).
    static func encodeJpeg(_ imageData: Data, maxSide: Int = 1600, quality: Double = 0.8) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw EncodingError() }
        // Mai ingrandire: il lato massimo non supera quello dell'originale.
        let target = min(max(width, height), maxSide)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // applica l'orientazione EXIF
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw EncodingError() }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw EncodingError()
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodingError() }
        return output as Data
    }
}
