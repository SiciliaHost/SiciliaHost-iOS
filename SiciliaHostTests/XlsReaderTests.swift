import XCTest
@testable import SiciliaHost

/// Il lettore `.xls` è scritto a mano: qui si costruisce un file minimo (contenitore OLE2 + record BIFF8) con i casi
/// che contano — testo compresso e a 16 bit, stringa spezzata in un record CONTINUE, numeri NUMBER/RK/MULRK, stream
/// grande (catena di settori) — e si rilegge. Il test sul file reale di Booking è in `BookingTests.testRealExportIfProvided`.
final class XlsReaderTests: XCTestCase {
    // MARK: Costruzione del file

    enum Cell {
        case text(String)
        case number(Double)
    }

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
    private func le64(_ d: Double) -> [UInt8] { (0 ..< 8).map { UInt8((d.bitPattern >> UInt64(8 * $0)) & 0xFF) } }
    private func record(_ id: Int, _ data: [UInt8]) -> [UInt8] { le16(id) + le16(data.count) + data }

    /// Stringa BIFF8 dell'SST: lunghezza, flag (0 = 8 bit, 1 = 16 bit), caratteri.
    private func sstString(_ s: String) -> (bytes: [UInt8], charStart: Int, compressed: Bool) {
        let scalars = Array(s.unicodeScalars)
        let compressed = scalars.allSatisfy { $0.value < 256 }
        let header = le16(scalars.count) + [compressed ? 0 : 1]
        let chars: [UInt8] = compressed ? scalars.map { UInt8($0.value) } : Array(s.utf16).flatMap { le16(Int($0)) }
        return (header + chars, header.count, compressed)
    }

    /// Stream "Workbook": globals (BOUNDSHEET + SST, con la stringa più lunga spezzata in un CONTINUE) e un foglio.
    private func makeWorkbook(_ rows: [[Cell]], splitSst: Bool = true, padding: Int = 0) -> [UInt8] {
        // SST
        var unique: [String] = []
        for row in rows { for case .text(let t) in row where !unique.contains(t) { unique.append(t) } }
        let encoded = unique.map(sstString)
        var payload = le32(unique.count) + le32(unique.count)
        var starts: [Int] = []
        for e in encoded { starts.append(payload.count + e.charStart); payload += e.bytes }

        var sstRecords: [UInt8]
        if splitSst, let longest = unique.indices.filter({ encoded[$0].compressed && unique[$0].count >= 6 }).max(by: { unique[$0].count < unique[$1].count }) {
            let cut = starts[longest] + 3 // dopo 3 caratteri della stringa più lunga
            sstRecords = record(0x00FC, Array(payload[..<cut])) + record(0x003C, [0] + Array(payload[cut...])) // CONTINUE: riparte con il byte di flag
        } else {
            sstRecords = record(0x00FC, payload)
        }

        func globals(sheetOffset: Int) -> [UInt8] {
            record(0x0809, [UInt8](repeating: 0, count: 16))
                + record(0x0085, le32(sheetOffset) + [0, 0, 6] + Array("Sheet1".utf8))
                + sstRecords
                + record(0x000A, [])
        }
        let sheetOffset = globals(sheetOffset: 0).count

        // Foglio
        var sheet = record(0x0809, [UInt8](repeating: 0, count: 16))
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                switch cell {
                case .text(let t):
                    sheet += record(0x00FD, le16(r) + le16(c) + le16(0) + le32(unique.firstIndex(of: t)!))
                case .number(let d):
                    if d == d.rounded(), d >= 0, d < 536_870_911, c % 2 == 0 {
                        // RK intero: (valore << 2) | 2
                        sheet += record(0x027E, le16(r) + le16(c) + le16(0) + le32((Int(d) << 2) | 2))
                    } else {
                        sheet += record(0x0203, le16(r) + le16(c) + le16(0) + le64(d))
                    }
                }
            }
        }
        sheet += record(0x000A, [])
        // Dati oltre l'EOF del foglio (non devono essere letti) e riempimento per superare la soglia del mini-stream.
        var tail: [UInt8] = []
        if padding > 0 { tail = record(0x0FFF, [UInt8](repeating: 0xAB, count: padding)) }
        return globals(sheetOffset: sheetOffset) + sheet + tail
    }

    /// Contenitore OLE2 minimo: settore 0 = FAT, 1 = directory, dal 2 lo stream "Workbook".
    private func makeOle2(stream: [UInt8], cutoff: Int? = nil) -> Data {
        let ss = 512
        var data = stream
        while data.count % ss != 0 || data.isEmpty { data.append(0) }
        let streamSectors = data.count / ss
        precondition(streamSectors < 100, "una sola FAT basta per 127 settori")

        var header = [UInt8](repeating: 0, count: 512)
        func put(_ bytes: [UInt8], at o: Int) { for (i, b) in bytes.enumerated() { header[o + i] = b } }
        put([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], at: 0)
        put(le16(0x3E), at: 24); put(le16(3), at: 26); put(le16(0xFFFE), at: 28)
        put(le16(9), at: 30); put(le16(6), at: 32)
        put(le32(1), at: 44) // settori FAT
        put(le32(1), at: 48) // primo settore della directory
        // Soglia del mini-stream: a 0 tutti gli stream stanno nei settori normali (il costruttore non scrive mini-stream);
        // a 4096 ci si affida allo stream grande. Il percorso del mini-stream non è coperto da questi test.
        put(le32(cutoff ?? (stream.count >= 4096 ? 4096 : 0)), at: 56)
        put(le32(0xFFFF_FFFE), at: 60); put(le32(0), at: 64) // niente mini-FAT
        put(le32(0xFFFF_FFFE), at: 68); put(le32(0), at: 72) // niente DIFAT
        put(le32(0), at: 76) // il settore 0 è la FAT
        for i in 1 ..< 109 { put(le32(0xFFFF_FFFF), at: 76 + 4 * i) }

        var fat = [Int](repeating: 0xFFFF_FFFF, count: 128)
        fat[0] = 0xFFFF_FFFD // settore FAT
        fat[1] = 0xFFFF_FFFE // directory, fine catena
        for i in 0 ..< streamSectors { fat[2 + i] = i == streamSectors - 1 ? 0xFFFF_FFFE : 2 + i + 1 }
        let fatSector = fat.flatMap { le32($0) }

        func dirEntry(name: String, type: UInt8, start: Int, size: Int) -> [UInt8] {
            var e = [UInt8](repeating: 0, count: 128)
            let units = Array(name.utf16)
            for (i, u) in units.enumerated() { e[2 * i] = UInt8(u & 0xFF); e[2 * i + 1] = UInt8(u >> 8) }
            e[64] = UInt8(((units.count + 1) * 2) & 0xFF); e[65] = UInt8(((units.count + 1) * 2) >> 8)
            e[66] = type
            for (i, b) in le32(start).enumerated() { e[116 + i] = b }
            for (i, b) in le32(size).enumerated() { e[120 + i] = b }
            return e
        }
        var dir = dirEntry(name: "Root Entry", type: 5, start: 0xFFFF_FFFE, size: 0)
        dir += dirEntry(name: "Workbook", type: 2, start: 2, size: stream.count)
        dir += [UInt8](repeating: 0, count: 512 - dir.count)

        return Data(header + fatSector + dir + data)
    }

    private func read(_ rows: [[Cell]], splitSst: Bool = true, padding: Int = 0) throws -> [[String]] {
        try XlsReader.readRows(makeOle2(stream: makeWorkbook(rows, splitSst: splitSst, padding: padding)))
    }

    // MARK: Test

    func testReadsTextAndNumbers() throws {
        let rows: [[Cell]] = [
            [.text("Stato"), .text("N° di prenotazione"), .text("Prezzo")],
            [.text("ok"), .number(5_100_000_001), .text("968 EUR")],
            [.text("ok"), .number(12), .number(174.24)],
        ]
        let result = try read(rows)
        XCTAssertEqual(result[0], ["Stato", "N° di prenotazione", "Prezzo"])
        XCTAssertEqual(result[1], ["ok", "5100000001", "968 EUR"])
        XCTAssertEqual(result[2], ["ok", "12", "174.24"])
    }

    func testStringSplitAcrossContinueRecordIsReassembled() throws {
        let long = "Approximate time of arrival"
        let result = try read([[.text("ok"), .text(long), .text("fine")]], splitSst: true)
        XCTAssertEqual(result, [["ok", long, "fine"]])
        // Senza spezzatura lo stesso risultato.
        XCTAssertEqual(try read([[.text("ok"), .text(long), .text("fine")]], splitSst: false), result)
    }

    func testSixteenBitStringsAndTrimming() throws {
        let result = try read([[.text("Prezzo €"), .text("  spazi  "), .text("Zürich")]])
        XCTAssertEqual(result, [["Prezzo €", "spazi", "Zürich"]])
    }

    func testRowsWithoutCellsAreDroppedAndShortRowsStayShort() throws {
        // Come POI: le righe senza celle non esistono e la larghezza è quella dell'ultima cella della riga.
        let result = try read([[.text("a"), .text("b"), .text("c")], [.text("x")]])
        XCTAssertEqual(result, [["a", "b", "c"], ["x"]])
    }

    func testLargeStreamUsesTheRegularSectorChain() throws {
        // Con soglia 4096 e stream molto più grande si segue la catena di settori normale.
        let result = try read([[.text("ok"), .text("grande")]], padding: 6000)
        XCTAssertEqual(result, [["ok", "grande"]])
    }

    func testRejectsFilesThatAreNotOle2() {
        XCTAssertThrowsError(try XlsReader.readRows(Data("Stato;Prezzo\nok;1".utf8))) {
            XCTAssertEqual(($0 as? BookingImportError)?.message, "File Excel non valido o danneggiato")
        }
        XCTAssertThrowsError(try XlsReader.readRows(Data()))
    }

    func testEndToEndThroughTheBookingParser() throws {
        let rows: [[Cell]] = [
            [.text("Status"), .text("Book number"), .text("Guest name(s)"), .text("Check-in"), .text("Check-out"),
             .text("Price"), .text("Phone number"), .text("Booker country"), .text("Adults"), .text("Children")],
            [.text("ok"), .number(5_100_000_001), .text("Hans Muster"), .text("2026-01-16"), .text("2026-01-25"),
             .text("968 EUR"), .number(491_701_234_567), .text("de"), .number(4), .number(1)],
            [.text("cancelled"), .number(1), .text("Skip Me"), .text("2026-03-01"), .text("2026-03-03"),
             .text("100 EUR"), .text(""), .text("fr"), .number(1), .number(0)],
        ]
        let data = makeOle2(stream: makeWorkbook(rows))
        let result = try BookingExcelParser.parse(data: data, propertyId: "prop2", isManagedOnCommission: false)
        XCTAssertEqual(result.reservations.count, 1)
        XCTAssertEqual(result.cancelledRows, 1)
        XCTAssertEqual(result.reservations[0].icalUid, "booking-xls-5100000001")
        XCTAssertEqual(result.reservations[0].guestName, "Hans Muster")
        XCTAssertEqual(result.reservations[0].adults, 4)
        XCTAssertEqual(result.reservations[0].children, 1)
        XCTAssertEqual(result.contacts.map(\.phone), ["+491701234567"])
        XCTAssertEqual(result.contacts[0].country, "de")
    }
}
