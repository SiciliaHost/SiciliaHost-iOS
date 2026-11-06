import Foundation

// Logica pura del check-in Alloggiati (`ui/checkin/*.kt`): niente SwiftUI né Firebase, così si testa.

/// Valori del modulo ospite (`GuestFormScreen.kt`): codici delle tabelle Alloggiati, date `gg/mm/aaaa`, sesso "1"/"2".
struct GuestFormValues: Equatable {
    var tipoAlloggiato = ""
    var cognome = ""
    var nome = ""
    var sesso = "1"
    var dataNascita = ""
    var cittadinanzaCode = ""
    var statoNascitaCode = ""
    var comuneNascitaCode = ""
    var provinciaNascita = ""
    var tipoDocumentoCode = ""
    var numeroDocumento = ""
    var luogoRilascioCode = ""
}

enum CheckinLogic {
    /// Titolo della schermata: "Nome · gg/mm/aaaa → gg/mm/aaaa" (o "Check-in" senza prenotazione).
    static func headerTitle(_ reservation: Reservation?) -> String {
        guard let r = reservation else { return "Check-in" }
        return "\(r.guestName ?? "Check-in") · \(dayMonthYearText(r.checkIn)) → \(dayMonthYearText(r.checkOut))"
    }

    /// Valori iniziali del modulo: la scheda esistente vince, poi i dati letti dal MRZ, poi i predefiniti (sesso "1").
    static func initialValues(existing: GuestRecord?, mrz: MrzData?) -> GuestFormValues {
        var v = GuestFormValues()
        if let e = existing {
            v.tipoAlloggiato = e.tipoAlloggiato
            v.cognome = e.cognome
            v.nome = e.nome
            v.sesso = e.sesso.isEmpty ? "1" : e.sesso
            v.dataNascita = e.dataNascita
            v.cittadinanzaCode = e.cittadinanzaCode
            v.statoNascitaCode = e.statoNascitaCode
            v.comuneNascitaCode = e.comuneNascitaCode ?? ""
            v.provinciaNascita = e.provinciaNascita ?? ""
            v.tipoDocumentoCode = e.tipoDocumentoCode
            v.numeroDocumento = e.numeroDocumento
            v.luogoRilascioCode = e.luogoRilascioCode
        } else if let m = mrz {
            v.cognome = m.cognome
            v.nome = m.nome
            v.sesso = m.sesso.isEmpty ? "1" : m.sesso
            v.dataNascita = m.dataNascita
            v.numeroDocumento = m.numeroDocumento
        }
        return v
    }

    /// Cittadinanza italiana: la descrizione del luogo scelto contiene "ITAL" (come l'Android). Solo allora servono comune
    /// e provincia di nascita.
    static func isItalian(cittadinanzaCode: String, luoghi: [LookupEntry]) -> Bool {
        guard !cittadinanzaCode.isEmpty else { return false }
        return luoghi.first { $0.code == cittadinanzaCode }?.description.range(of: "ITAL", options: .caseInsensitive) != nil
    }

    static func isValid(_ v: GuestFormValues, isItalian: Bool) -> Bool {
        let base = !v.tipoAlloggiato.trimmed.isEmpty && !v.cognome.trimmed.isEmpty && !v.nome.trimmed.isEmpty
            && v.dataNascita.count == 10
            && !v.cittadinanzaCode.trimmed.isEmpty && !v.statoNascitaCode.trimmed.isEmpty
            && !v.tipoDocumentoCode.trimmed.isEmpty && !v.numeroDocumento.trimmed.isEmpty
            && !v.luogoRilascioCode.trimmed.isEmpty
        return base && (!isItalian || (!v.comuneNascitaCode.trimmed.isEmpty && v.provinciaNascita.count == 2))
    }

    /// La scheda da salvare. Comune e provincia solo per gli italiani. Modificando una scheda esistente si conserva lo stato
    /// d'invio; `CheckinModel.save` lo rilegge comunque dal disco (come `saveGuestRecord` dell'Android dal 2026-11-06) e
    /// rifiuta le schede già inviate o in invio.
    static func record(
        from v: GuestFormValues, isItalian: Bool, existing: GuestRecord?, reservationId: String, propertyId: String
    ) -> GuestRecord {
        var r = existing ?? GuestRecord()
        r.reservationId = reservationId
        r.propertyId = propertyId
        r.tipoAlloggiato = v.tipoAlloggiato
        r.cognome = v.cognome.trimmed
        r.nome = v.nome.trimmed
        r.sesso = v.sesso
        r.dataNascita = v.dataNascita
        r.comuneNascitaCode = isItalian ? v.comuneNascitaCode : nil
        r.provinciaNascita = isItalian ? v.provinciaNascita : nil
        r.statoNascitaCode = v.statoNascitaCode
        r.cittadinanzaCode = v.cittadinanzaCode
        r.tipoDocumentoCode = v.tipoDocumentoCode
        r.numeroDocumento = v.numeroDocumento.trimmed
        r.luogoRilascioCode = v.luogoRilascioCode
        return r
    }

    /// Le schede ancora da inviare: quelle già accettate non si rimandano (l'invio ha successo parziale, rimandare tutto
    /// duplicherebbe le righe già acquisite).
    static func pending(_ records: [GuestRecord]) -> [GuestRecord] { records.filter { !$0.schedInaSent } }

    /// Esito di una scheda: il dettaglio della risposta è indicizzato solo sulle schede non ancora inviate.
    static func esito(for record: GuestRecord, records: [GuestRecord], result: ElencoSchedineEsito?) -> EsitoSingolo? {
        guard let result, let index = pending(records).firstIndex(where: { $0.id == record.id }),
              index < result.dettaglio.count else { return nil }
        return result.dettaglio[index]
    }

    static func allOk(_ result: ElencoSchedineEsito?) -> Bool {
        guard let result else { return false }
        return result.dettaglio.allSatisfy(\.esito)
    }

    /// Data di nascita digitata: solo cifre e "/", massimo 10 caratteri.
    static func sanitizeDate(_ text: String) -> String {
        String(text.filter { $0.isASCII && ($0.isNumber || $0 == "/") }.prefix(10))
    }

    /// Sigla della provincia: maiuscola, 2 caratteri.
    static func sanitizeProvince(_ text: String) -> String { String(text.uppercased().prefix(2)) }
}

/// "gg/mm/aaaa" nel fuso del telefono.
func dayMonthYearText(_ millis: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "dd/MM/yyyy"
    return f.string(from: dateFromMillis(millis))
}
