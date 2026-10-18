import Foundation

// Lettore minimo del vecchio formato Excel `.xls` (contenitore OLE2 + record BIFF8), scritto a mano perché su iOS
// non esiste una libreria adatta (Apache POI su Android). Legge SOLO il primo foglio e solo i valori di testo e
// numerici: basta per l'export "Arrivi con recapiti" di Booking. Algoritmo validato in Python sui tre export reali
// (30/40/44 righe) prima del porting; i test di questo file usano un file sintetico.
//
// Riferimenti: [MS-CFB] (Compound File Binary) e [MS-XLS] (BIFF8: BOUNDSHEET, SST, LABELSST, NUMBER, RK, MULRK, LABEL).

private let xlsCorrupted = BookingImportError(message: "File Excel non valido o danneggiato")

private func u16(_ b: [UInt8], _ o: Int) -> Int {
    o >= 0 && o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0
}

private func u32(_ b: [UInt8], _ o: Int) -> Int {
    o >= 0 && o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0
}

/// Testo UTF-16 little-endian da una sequenza di byte (coppie low/high).
private func utf16LE<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
    let b = Array(bytes)
    let units = stride(from: 0, to: b.count - 1, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
    return String(decoding: units, as: UTF16.self)
}

private func f64(_ b: [UInt8], _ o: Int) -> Double {
    guard o >= 0 && o + 8 <= b.count else { return 0 }
    var bits: UInt64 = 0
    for i in 0 ..< 8 { bits |= UInt64(b[o + i]) << UInt64(8 * i) }
    return Double(bitPattern: bits)
}

// MARK: Contenitore OLE2

/// Contenitore "Compound File Binary": settori, FAT, directory e mini-stream.
struct Ole2File {
    private static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let endOfChain = 0xFFFF_FFF0 // i valori da qui in su sono marcatori (libero, fine catena, FAT…)

    private let data: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private var fat: [Int] = []
    private var miniFat: [Int] = []
    private var miniStream: [UInt8] = []
    private var entries: [(name: String, type: Int, start: Int, size: Int)] = []

    init(_ bytes: [UInt8]) throws {
        guard bytes.count >= 512, Array(bytes.prefix(8)) == Ole2File.signature else { throw xlsCorrupted }
        data = bytes
        let sectorShift = u16(bytes, 30), miniShift = u16(bytes, 32)
        guard (7 ... 16).contains(sectorShift), (3 ... 12).contains(miniShift) else { throw xlsCorrupted }
        sectorSize = 1 << sectorShift
        miniSectorSize = 1 << miniShift
        miniCutoff = u32(bytes, 56)
        let fatSectors = u32(bytes, 44), firstDir = u32(bytes, 48)
        let firstMiniFat = u32(bytes, 60), miniFatSectors = u32(bytes, 64)
        let firstDifat = u32(bytes, 68), difatSectors = u32(bytes, 72)

        // Elenco dei settori della FAT: 109 voci nell'intestazione + eventuali settori DIFAT.
        var fatSectorIds = (0 ..< 109).map { u32(bytes, 76 + 4 * $0) }
        var difat = firstDifat
        for _ in 0 ..< min(difatSectors, 4096) where difat < Ole2File.endOfChain {
            let offset = (difat + 1) * sectorSize
            for i in 0 ..< (sectorSize / 4 - 1) { fatSectorIds.append(u32(bytes, offset + 4 * i)) }
            difat = u32(bytes, offset + sectorSize - 4)
        }
        for sid in fatSectorIds.prefix(fatSectors) where sid < Ole2File.endOfChain {
            let offset = (sid + 1) * sectorSize
            guard offset + sectorSize <= bytes.count else { throw xlsCorrupted }
            fat += (0 ..< sectorSize / 4).map { u32(bytes, offset + 4 * $0) }
        }

        let dir = chain(firstDir)
        for i in 0 ..< dir.count / 128 {
            let e = Array(dir[i * 128 ..< (i + 1) * 128])
            let nameBytes = max(u16(e, 64) - 2, 0)
            let name = utf16LE(e[0 ..< min(nameBytes, 64)])
            entries.append((name: name, type: Int(e[66]), start: u32(e, 116), size: u32(e, 120)))
        }
        guard let root = entries.first else { throw xlsCorrupted }
        if root.start < Ole2File.endOfChain { miniStream = Array(chain(root.start).prefix(root.size)) }
        if miniFatSectors > 0 {
            let mf = chain(firstMiniFat)
            miniFat = (0 ..< mf.count / 4).map { u32(mf, 4 * $0) }
        }
    }

    /// Concatena i settori della catena che parte da `start` (protetto da cicli e da file troncati).
    private func chain(_ start: Int) -> [UInt8] {
        var out: [UInt8] = []
        var seen = Set<Int>()
        var sid = start
        while sid < Ole2File.endOfChain && !seen.contains(sid) && sid < fat.count {
            seen.insert(sid)
            let offset = (sid + 1) * sectorSize
            guard offset + sectorSize <= data.count else { break }
            out += data[offset ..< offset + sectorSize]
            sid = fat[sid]
        }
        return out
    }

    private func miniChain(_ start: Int, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var seen = Set<Int>()
        var sid = start
        while sid < Ole2File.endOfChain && !seen.contains(sid) && sid < miniFat.count {
            seen.insert(sid)
            let from = sid * miniSectorSize
            guard from + miniSectorSize <= miniStream.count else { break }
            out += miniStream[from ..< from + miniSectorSize]
            sid = miniFat[sid]
        }
        return Array(out.prefix(size))
    }

    /// Il contenuto del primo stream con uno dei nomi indicati (es. "Workbook").
    func stream(named names: Set<String>) throws -> [UInt8] {
        guard let entry = entries.first(where: { $0.type == 2 && names.contains($0.name) }) else { throw xlsCorrupted }
        return entry.size >= miniCutoff
            ? Array(chain(entry.start).prefix(entry.size))
            : miniChain(entry.start, size: entry.size)
    }
}

// MARK: Record BIFF8

enum XlsReader {
    private struct Record {
        let id: Int
        let data: [UInt8]
    }

    /// Legge i record a partire da `offset` finché i dati finiscono.
    private static func records(_ b: [UInt8], from offset: Int = 0) -> [Record] {
        var out: [Record] = []
        var o = offset
        while o + 4 <= b.count {
            let id = u16(b, o), length = u16(b, o + 2)
            let end = min(o + 4 + length, b.count)
            out.append(Record(id: id, data: Array(b[(o + 4) ..< end])))
            o += 4 + length
        }
        return out
    }

    /// Righe del primo foglio del file `.xls` come testo (come `readXlsRows` dell'Android).
    static func readRows(_ data: Data) throws -> [[String]] {
        let workbook = try Ole2File([UInt8](data)).stream(named: ["Workbook", "Book"])
        return try readWorkbookRows(workbook)
    }

    /// Righe del primo foglio, dallo stream "Workbook" già estratto dal contenitore.
    static func readWorkbookRows(_ wb: [UInt8]) throws -> [[String]] {
        let all = records(wb)
        var sst: [String] = []
        var sheetOffset: Int?
        for (i, rec) in all.enumerated() {
            if rec.id == 0x0085, sheetOffset == nil { // BOUNDSHEET: posizione del BOF del foglio
                sheetOffset = u32(rec.data, 0)
            } else if rec.id == 0x00FC { // SST + eventuali CONTINUE
                var chunks = [rec.data]
                for next in all[(i + 1)...] {
                    guard next.id == 0x003C else { break }
                    chunks.append(next.data)
                }
                sst = parseSst(chunks)
            }
        }
        guard let sheetOffset, sheetOffset < wb.count else { throw xlsCorrupted }

        var cells: [Int: [Int: String]] = [:]
        func put(_ r: Int, _ c: Int, _ text: String) { cells[r, default: [:]][c] = text }

        var seenBof = false
        sheet: for rec in records(wb, from: sheetOffset) {
            let d = rec.data
            switch rec.id {
            case 0x0809: // BOF: il primo apre il foglio, un secondo è un'altra sotto-sezione
                if seenBof { break sheet }
                seenBof = true
            case 0x000A: // EOF
                break sheet
            case 0x00FD: // LABELSST: riga, colonna, formato, indice nell'SST
                let i = u32(d, 6)
                put(u16(d, 0), u16(d, 2), i < sst.count ? sst[i].trimmed : "")
            case 0x0203: // NUMBER
                put(u16(d, 0), u16(d, 2), numberText(f64(d, 6)))
            case 0x027E: // RK
                put(u16(d, 0), u16(d, 2), numberText(rkValue(u32(d, 6))))
            case 0x00BD: // MULRK: più celle RK consecutive sulla stessa riga
                let row = u16(d, 0), firstCol = u16(d, 2)
                for k in 0 ..< max((d.count - 6) / 6, 0) {
                    put(row, firstCol + k, numberText(rkValue(u32(d, 4 + 6 * k + 2))))
                }
            case 0x0204: // LABEL (testo diretto)
                guard d.count > 8 else { continue }
                let length = u16(d, 6)
                let text: String
                if d[8] & 1 == 1 {
                    text = utf16LE(d[9 ..< min(9 + 2 * length, d.count)])
                } else {
                    text = String(d[9 ..< min(9 + length, d.count)].map { Character(Unicode.Scalar($0)) })
                }
                put(u16(d, 0), u16(d, 2), text.trimmed)
            default:
                break
            }
        }

        // Solo le righe che hanno almeno una cella (come POI); la lunghezza è l'ultima colonna + 1.
        return cells.keys.sorted().map { r in
            let row = cells[r]!
            let width = (row.keys.max() ?? -1) + 1
            return (0 ..< width).map { row[$0] ?? "" }
        }
    }

    /// Intero senza ".0" se il numero è intero (come `cellText` dell'Android), altrimenti la rappresentazione decimale.
    private static func numberText(_ d: Double) -> String {
        if d == d.rounded(.down) && d.isFinite && abs(d) < 9.2e18 { return String(Int64(d)) }
        return "\(d)"
    }

    /// Valore di un campo RK: intero a 30 bit oppure i 30 bit alti di un double; bit 0 = diviso 100.
    private static func rkValue(_ v: Int) -> Double {
        let n: Double
        if v & 2 != 0 {
            n = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: v)) >> 2)
        } else {
            n = Double(bitPattern: UInt64(v & 0xFFFF_FFFC) << 32)
        }
        return v & 1 != 0 ? n / 100 : n
    }

    // MARK: SST (tabella delle stringhe condivise)

    private struct Cursor {
        let chunks: [[UInt8]]
        var chunk = 0
        var pos = 0

        init(_ chunks: [[UInt8]]) { self.chunks = chunks }

        var left: Int { chunk < chunks.count ? chunks[chunk].count - pos : 0 }

        mutating func nextChunk() { chunk += 1; pos = 0 }

        /// Legge `n` byte attraversando i confini dei record CONTINUE; nil se i dati finiscono.
        mutating func take(_ n: Int) -> [UInt8]? {
            var out: [UInt8] = []
            var remaining = n
            while remaining > 0 {
                if left == 0 {
                    nextChunk()
                    if chunk >= chunks.count { return nil }
                    continue
                }
                let k = min(remaining, left)
                out += chunks[chunk][pos ..< pos + k]
                pos += k
                remaining -= k
            }
            return out
        }
    }

    /// Stringhe dell'SST. Le stringhe possono continuare in un record CONTINUE, che ripete all'inizio un byte di flag
    /// (bit 0 = caratteri a 16 bit). Dati troncati: si restituisce ciò che è stato letto.
    private static func parseSst(_ chunks: [[UInt8]]) -> [String] {
        var c = Cursor(chunks)
        guard c.take(4) != nil, let uniqueBytes = c.take(4) else { return [] }
        let unique = u32(uniqueBytes, 0)
        var out: [String] = []
        for _ in 0 ..< unique {
            guard let head = c.take(3) else { break }
            let cch = u16(head, 0)
            let flags = Int(head[2])
            var wide = flags & 1 != 0
            let hasExt = flags & 4 != 0, hasRich = flags & 8 != 0
            var runs = 0, extLength = 0
            if hasRich { guard let r = c.take(2) else { break }; runs = u16(r, 0) }
            if hasExt { guard let e = c.take(4) else { break }; extLength = u32(e, 0) }

            var text = ""
            var remaining = cch
            var truncated = false
            while remaining > 0 {
                if c.left == 0 {
                    c.nextChunk()
                    guard let f = c.take(1) else { truncated = true; break }
                    wide = f[0] & 1 != 0
                }
                let available = c.left / (wide ? 2 : 1)
                let k = min(remaining, available)
                guard k > 0, let raw = c.take(k * (wide ? 2 : 1)) else { truncated = true; break }
                if wide {
                    text += utf16LE(raw)
                } else {
                    text += String(raw.map { Character(Unicode.Scalar($0)) }) // Latin-1: i byte sono i primi 256 codepoint
                }
                remaining -= k
            }
            if truncated { break }
            _ = c.take(4 * runs + extLength)
            out.append(text)
        }
        return out
    }
}
