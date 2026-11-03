import XCTest
@testable import SiciliaHost

// Le schermate Android del check-in non hanno test: questi coprono la logica estratta in `CheckinLogic` (validazione
// come `GuestFormScreen.kt`, esiti per indice come `CheckinSendScreen.kt`, schede da inviare come `CheckinViewModel.kt`).
final class CheckinTests: XCTestCase {
    private let luoghi = [
        LookupEntry(code: "100000100", description: "ITALIA"),
        LookupEntry(code: "100000216", description: "GERMANIA"),
    ]

    private func validForeigner() -> GuestFormValues {
        var v = GuestFormValues()
        v.tipoAlloggiato = "16"
        v.cognome = "MUSTER"
        v.nome = "HANS"
        v.dataNascita = "01/02/1980"
        v.cittadinanzaCode = "100000216"
        v.statoNascitaCode = "100000216"
        v.tipoDocumentoCode = "PASOR"
        v.numeroDocumento = "C01X00T47"
        v.luogoRilascioCode = "100000216"
        return v
    }

    func testItalianIsRecognisedFromTheCitizenshipDescription() {
        XCTAssertTrue(CheckinLogic.isItalian(cittadinanzaCode: "100000100", luoghi: luoghi))
        XCTAssertFalse(CheckinLogic.isItalian(cittadinanzaCode: "100000216", luoghi: luoghi))
        XCTAssertFalse(CheckinLogic.isItalian(cittadinanzaCode: "", luoghi: luoghi))
        XCTAssertFalse(CheckinLogic.isItalian(cittadinanzaCode: "999", luoghi: luoghi))
    }

    func testValidationRequiresEveryFieldAndBirthPlaceOnlyForItalians() {
        var v = validForeigner()
        XCTAssertTrue(CheckinLogic.isValid(v, isItalian: false))
        XCTAssertFalse(CheckinLogic.isValid(v, isItalian: true)) // manca comune/provincia
        v.comuneNascitaCode = "408082053"
        v.provinciaNascita = "PA"
        XCTAssertTrue(CheckinLogic.isValid(v, isItalian: true))
        v.provinciaNascita = "P"
        XCTAssertFalse(CheckinLogic.isValid(v, isItalian: true))

        var short = validForeigner()
        short.dataNascita = "1/2/1980"
        XCTAssertFalse(CheckinLogic.isValid(short, isItalian: false))
        var blank = validForeigner()
        blank.numeroDocumento = "   "
        XCTAssertFalse(CheckinLogic.isValid(blank, isItalian: false))
    }

    func testInitialValuesPreferTheExistingRecordThenTheMrz() {
        let mrz = MrzData(cognome: "ROSSI", nome: "MARIO", sesso: "1", dataNascita: "03/04/1975", numeroDocumento: "CA0000000",
                          tipoDocumento: "ID", issuingCountryIso: "ITA", statoNascitaIso: "ITA", cittadinanzaIso: "ITA",
                          checkDigitsValid: true)
        let fromMrz = CheckinLogic.initialValues(existing: nil, mrz: mrz)
        XCTAssertEqual(fromMrz.cognome, "ROSSI")
        XCTAssertEqual(fromMrz.numeroDocumento, "CA0000000")
        XCTAssertEqual(fromMrz.tipoAlloggiato, "")

        let existing = GuestRecord(id: "g1", cognome: "BIANCHI", nome: "ANNA", sesso: "2", comuneNascitaCode: "408082053")
        let fromRecord = CheckinLogic.initialValues(existing: existing, mrz: mrz)
        XCTAssertEqual(fromRecord.cognome, "BIANCHI")
        XCTAssertEqual(fromRecord.sesso, "2")
        XCTAssertEqual(fromRecord.comuneNascitaCode, "408082053")

        XCTAssertEqual(CheckinLogic.initialValues(existing: nil, mrz: nil).sesso, "1")
    }

    func testRecordKeepsTheSendStateAndDropsBirthPlaceForForeigners() {
        var v = validForeigner()
        v.cognome = " MUSTER "
        v.comuneNascitaCode = "408082053"
        v.provinciaNascita = "PA"
        let existing = GuestRecord(id: "g1", reservationId: "old", schedInaSent: true, sendTimestamp: 123,
                                   sendError: "Esito incerto")
        let r = CheckinLogic.record(from: v, isItalian: false, existing: existing, reservationId: "r1", propertyId: "p1")
        XCTAssertEqual(r.id, "g1")
        XCTAssertEqual(r.reservationId, "r1")
        XCTAssertEqual(r.propertyId, "p1")
        XCTAssertEqual(r.cognome, "MUSTER")
        XCTAssertNil(r.comuneNascitaCode)
        XCTAssertNil(r.provinciaNascita)
        XCTAssertTrue(r.schedInaSent)
        XCTAssertEqual(r.sendTimestamp, 123)
        XCTAssertEqual(r.sendError, "Esito incerto")

        let created = CheckinLogic.record(from: v, isItalian: true, existing: nil, reservationId: "r1", propertyId: "p1")
        XCTAssertEqual(created.id, "")
        XCTAssertEqual(created.comuneNascitaCode, "408082053")
        XCTAssertFalse(created.schedInaSent)
    }

    func testEsitoIsMatchedByIndexAmongPendingRecordsOnly() {
        let sent = GuestRecord(id: "a", schedInaSent: true)
        let first = GuestRecord(id: "b")
        let second = GuestRecord(id: "c")
        let records = [sent, first, second]
        let ok = EsitoSingolo(esito: true, errorCod: "", errorDes: "", erroreDettaglio: "")
        let ko = EsitoSingolo(esito: false, errorCod: "E", errorDes: "x", erroreDettaglio: "Data errata")
        let result = ElencoSchedineEsito(schedineValide: 1, dettaglio: [ok, ko])

        XCTAssertEqual(CheckinLogic.pending(records).map(\.id), ["b", "c"])
        XCTAssertNil(CheckinLogic.esito(for: sent, records: records, result: result))
        XCTAssertEqual(CheckinLogic.esito(for: first, records: records, result: result), ok)
        XCTAssertEqual(CheckinLogic.esito(for: second, records: records, result: result), ko)
        XCTAssertNil(CheckinLogic.esito(for: second, records: records, result: nil))
        XCTAssertFalse(CheckinLogic.allOk(result))
        XCTAssertTrue(CheckinLogic.allOk(ElencoSchedineEsito(schedineValide: 1, dettaglio: [ok])))
        XCTAssertFalse(CheckinLogic.allOk(nil))
    }

    func testInputSanitizers() {
        XCTAssertEqual(CheckinLogic.sanitizeDate("01/02/1980xx99"), "01/02/1980")
        XCTAssertEqual(CheckinLogic.sanitizeDate("0a1"), "01")
        XCTAssertEqual(CheckinLogic.sanitizeProvince("pal"), "PA")
    }

    func testHeaderTitle() {
        XCTAssertEqual(CheckinLogic.headerTitle(nil), "Check-in")
        let r = Reservation(guestName: nil, checkIn: utcMillis(year: 2026, month: 8, day: 10, hour: 12),
                            checkOut: utcMillis(year: 2026, month: 8, day: 13, hour: 12))
        XCTAssertEqual(CheckinLogic.headerTitle(r), "Check-in · 10/08/2026 → 13/08/2026")
    }
}
