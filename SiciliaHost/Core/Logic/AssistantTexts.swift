import Foundation

/// Testi dell'assistente Cactus per l'applicazione iOS.
public enum AssistantTexts {
    public static let title = "Assistente"
    public static let welcome = "Ciao! Posso aiutarti con prenotazioni, disponibilità e scorte delle tue case. Scrivimi o premi il microfono."
    public static let thinking = "L'assistente sta scrivendo…"

    // MARK: - Schermata di Cactus (Overlay con Avatar e Neon)
    public static let overlayTitle = "Cactus, l'assistente"
    public static let thinkingState = "Cactus sta pensando…"
    public static let showConversation = "Mostra la conversazione"
    public static let hideConversation = "Nascondi la conversazione"
    public static let conversationEmpty = "Non c'è ancora nessun messaggio."
    public static let bubbleTapHint = "Tocca per leggere tutto"
    public static let bubbleAskPrefix = "Tu: "
    public static let bubbleAnswerPrefix = "Cactus: "
    public static let listening = "Ti ascolto…"
    public static let micDenied = "Senza il permesso del microfono non posso ascoltarti: puoi scrivere il messaggio, oppure riprovare."
    public static let micBlocked = "Il microfono è bloccato: consentilo dalle impostazioni dell'app."
    public static let micSettings = "Apri le impostazioni"
    public static let micRationaleTitle = "Serve il microfono"
    public static let micRationaleBody = "Per dettare i messaggi l'assistente usa il microfono del telefono. L'audio lo elabora il servizio vocale di Apple: a SiciliaHost arriva solo il testo."
    public static let micRationaleContinue = "Continua"
    public static let micRationaleCancel = "Non ora"
    public static let micFailed = "Il riconoscimento vocale non ha funzionato. Riprova o scrivi il messaggio."
    public static let listenUnsupported = "Il riconoscimento vocale non è disponibile su questo dispositivo: scrivi il messaggio."
    public static let inputLabel = "Scrivi all'assistente"
    public static let send = "Invia"
    public static let newChat = "Nuova chat"
    public static let close = "Chiudi"
    public static let voiceOn = "Attiva la voce"
    public static let voiceOff = "Disattiva la voce"
    public static let micStart = "Parla"
    public static let micStop = "Smetti di ascoltare"
    public static let showKeyboard = "Scrivi con la tastiera"
    public static let openAssistant = "Apri l'assistente"
    public static let confirm = "Conferma"
    public static let decline = "Annulla"
    public static let busy = "Un attimo…"
    public static let done = "Fatto."
    public static let declined = "Annullata."
    public static let doneWith = "Fatto: "
    public static let undo = "Annulla la modifica"
    public static let undoing = "Annullo…"
    public static let undoneWith = "Annullato: "
    public static let unsavedDraft = "Hai modifiche non salvate in questa pagina: non ho aperto la sezione per non perderle."
    public static let stopped = "Fermato prima di salvare: non ho cambiato nulla."

    // MARK: - Tabella «Cosa cambia»
    public static let changesCaption = "Cosa cambia"
    public static let changesField = "Campo"
    public static let changesBeforeAfter = "Prima → dopo"
    public static let changesBefore = "Prima"
    public static let changesAfter = "Dopo"
    public static let changesNew = "Nuovo"
    public static let changesRemoved = "Rimosso"
    public static let changesShowAll = "Mostra tutto"
    public static let changesShowLess = "Mostra meno"

    // MARK: - Messa in Scena dal Vivo (Live Staging)
    public static let liveWorking = "Cactus sta lavorando…"
    public static let liveStop = "Ferma"
    public static let liveStopHint = "Ferma il lavoro di Cactus"
    public static let liveStopping = "Mi fermo dopo questo passo…"
    public static let liveFinished = "Ho finito: ecco cosa è cambiato"
    public static let liveSaving = "Salvo le modifiche"
    public static let liveUndoing = "Annullo le modifiche"
    public static let liveRemovedValue = "Tolto"

    public static func liveOpen(section: LiveSection, house: String) -> String {
        switch section {
        case .overview: return "Apro la panoramica"
        case .prices: return "Apro i prezzi di \(house)"
        case .conditions: return "Apro le condizioni di \(house)"
        case .texts: return "Apro i testi di \(house)"
        case .services: return "Apro i servizi di \(house)"
        case .guestInfo: return "Apro le informazioni per gli ospiti di \(house)"
        case .calendar: return "Apro il calendario di \(house)"
        case .finance: return "Apro le finanze di \(house)"
        case .inventory: return "Apro le scorte di \(house)"
        }
    }

    public static func liveWrite(section: LiveSection) -> String {
        switch section {
        case .overview: return "Scrivo le modifiche"
        case .prices: return "Scrivo i prezzi"
        case .conditions: return "Scrivo le condizioni"
        case .texts: return "Scrivo i testi"
        case .services: return "Scrivo i servizi"
        case .guestInfo: return "Scrivo le informazioni per gli ospiti"
        case .calendar: return "Scrivo sul calendario"
        case .finance: return "Scrivo le finanze"
        case .inventory: return "Aggiorno le scorte"
        }
    }

    public static func proposalReason(_ reason: String) -> String {
        return "Perché: \(reason)"
    }

    public static func undoErrorText(_ error: ChatError) -> String {
        switch error {
        case .stale: return "Non posso annullare: nel frattempo il valore è stato cambiato."
        case .undoExpired: return "Sono passati più di 10 minuti: non si può più annullare da qui."
        case .notUndoable: return "Questa modifica non si può annullare da qui."
        case .partial: return "L'annullamento è stato applicato solo in parte e non sono riuscito a riportarlo com'era: controlla i valori nella pagina e correggili a mano."
        case .already: return "Questa modifica è già stata annullata."
        default: return "Non sono riuscito ad annullare. Riprova."
        }
    }

    public static let houseNone = "Nessuna (tutte)"
    public static let houseUnnamed = "Casa senza nome"
    public static let houseLabel = "Casa:"
    public static let houseMenu = "Scegli la casa di cui parlare con Cactus"

    // MARK: - Widget
    public static let widgetConfirm = "Conferma"
    public static let widgetNotChosen = "Non scelto"
    public static let datesChoose = "Scegli le date"
    public static let datesConfirm = "Conferma le date"
    public static let datesCancel = "Annulla"
    public static let datesPickEnd = "Ora scegli l'ultimo giorno."
    public static let datesInvalidRange = "L'intervallo comprende giorni non disponibili."
    public static let amountEuro = "Importo"
    public static let amountQuantity = "Quantità"
    public static let amountDecrease = "Diminuisci"
    public static let amountIncrease = "Aumenta"
    public static let proposalGroup = "Modifiche proposte"
    public static let declineSelected = "Annulla le selezionate"

    public static func proposalSelect(_ summary: String) -> String {
        return "Includi: \(summary)"
    }

    public static func confirmSelected(_ count: Int) -> String {
        return "Conferma le selezionate (\(count))"
    }

    public static func showConversationPending(_ count: Int) -> String {
        return "Mostra la conversazione (\(count) in attesa)"
    }

    public static func amountError(_ error: AmountError, min: Double?, max: Double?) -> String {
        switch error {
        case .empty: return "Scrivi un valore."
        case .format: return "Usa solo cifre, con la virgola o il punto."
        case .decimals: return "Al massimo due decimali."
        case .min: return "Il valore minimo è \(formatAmountNumber(min ?? 0.0, language: "it", fixed: false))."
        case .max: return "Il valore massimo è \(formatAmountNumber(max ?? amountHardMax, language: "it", fixed: false))."
        }
    }

    public static func houseSet(_ name: String) -> String {
        return "Casa impostata: \(name)"
    }

    public static func remaining(_ count: Int) -> String {
        return "Messaggi rimasti oggi: \(count)"
    }

    public static func errorText(_ error: ChatError) -> String {
        switch error {
        case .disabled: return "L'assistente non è ancora disponibile per il tuo account."
        case .notHost: return "L'assistente è riservato agli host registrati."
        case .model: return "L'assistente non riesce a rispondere ora. Riprova tra poco."
        case .quota: return "Hai raggiunto il limite di messaggi di oggi. Riprova domani."
        case .full: return "Questa conversazione è troppo lunga: premi «Nuova chat»."
        case .expired: return "La proposta è scaduta: chiedila di nuovo all'assistente."
        case .already: return "Questa proposta è già stata gestita."
        case .executeFailed: return "Non è stato possibile eseguire la modifica."
        case .stale: return "È cambiato da quando l'ho preparato: chiedimelo di nuovo."
        case .undoExpired: return "Sono passati più di 10 minuti: non si può più annullare da qui."
        case .notUndoable: return "Questa modifica non si può annullare da qui."
        case .partial: return "L'annullamento è stato applicato solo in parte e non sono riuscito a riportarlo com'era: controlla i valori nella pagina e correggili a mano."
        case .denied: return "Non hai i permessi per usare l'assistente."
        case .consent: return "Serve il tuo consenso per usare l'assistente."
        case .termsVersion: return "L'informativa è stata aggiornata: riprova ad accettare."
        case .notFound: return "Proposta non trovata: chiedila di nuovo all'assistente."
        case .tooLong: return "Il messaggio è troppo lungo: accorcialo."
        case .generic: return "Qualcosa è andato storto. Riprova."
        }
    }

    // MARK: - Consenso Privacy
    public static let consentTitle = "Prima di cominciare"
    public static let consentIntro = "L'assistente ti aiuta a consultare e gestire le tue case su SiciliaHost. Leggi come funziona e come trattiamo i tuoi dati."
    public static let consentPoints: [(String, String)] = [
        ("Cos'è.", "Un assistente automatico basato su un modello di intelligenza artificiale. Può sbagliare: controlla sempre le informazioni importanti."),
        ("Quali dati usa.", "I messaggi che scrivi o detti e i dati delle tue case che l'assistente consulta per risponderti: prenotazioni con nome dell'ospite e date, disponibilità, scorte. Non vede importi, spese o dati finanziari: restano solo sul tuo telefono. Non legge i documenti d'identità degli ospiti, le credenziali Alloggiati, i recapiti degli ospiti né le tue email."),
        ("A chi vanno.", "Questi dati sono inviati al fornitore del modello di intelligenza artificiale che usiamo, solo per generare la risposta. Il fornitore agisce per nostro conto come responsabile del trattamento. I dettagli sono nell'informativa privacy."),
        ("La voce.", "Se usi il microfono, il riconoscimento e la lettura ad alta voce sono fatti dal servizio vocale del tuo dispositivo (per esempio Apple), secondo le sue regole. A SiciliaHost arriva solo il testo e non registriamo l'audio."),
        ("Nessuna cronologia.", "Non conserviamo uno storico: la conversazione viene cancellata quando premi «Nuova chat» o quando chiudi, e ogni eventuale residuo si elimina da solo entro 3 giorni."),
        ("Le modifiche le decidi tu.", "L'assistente non cambia nulla da solo: prepara una proposta e la esegue solo se premi «Conferma»."),
        ("Limiti.", "C'è un numero massimo di messaggi al giorno e l'assistente risponde solo su temi di SiciliaHost."),
        ("I tuoi diritti.", "Puoi smettere di usare l'assistente quando vuoi e scrivere a info@siciliahost.com per accedere ai tuoi dati, correggerli o farli cancellare; puoi anche rivolgerti al Garante per la protezione dei dati personali.")
    ]
    public static let consentPrivacy = "Leggi l'informativa privacy"
    public static let consentAccept = "Accetto e continuo"
    public static let consentDecline = "Non ora"
    public static let consentFailed = "Non sono riuscito a salvare il consenso. Riprova."
}
