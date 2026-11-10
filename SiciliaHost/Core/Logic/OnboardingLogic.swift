import Foundation

/// Va mostrata la presentazione?
/// - Prima del login non si sa chi è l'utente: conta solo il telefono (`deviceSeen`).
/// - Dopo il login conta l'account: `accountSeen` nil = profilo non ancora letto (non mostrare ancora). Se è appena
///   stata vista su questo telefono (`shownThisRun`) non si ripete.
func shouldShowIntro(signedIn: Bool, deviceSeen: Bool, accountSeen: Bool?, shownThisRun: Bool) -> Bool {
    signedIn ? (accountSeen == false && !shownThisRun) : !deviceSeen
}

/// Gli elementi che il tour indica. Ognuno è registrato da `.tourTarget(...)`.
enum TourTarget: CaseIterable, Hashable {
    case navBar, homeReview, agendaPrices, scorteScan, finanzeBalance, caseBookingImport, profile
}

/// `tab` = il titolo della sezione da aprire prima del passo (nil = nessun cambio pagina).
struct TourStep: Equatable {
    let target: TourTarget
    let tab: String?
    let title: String
    let text: String
}

private let allTourSteps: [TourStep] = [
    TourStep(target: .navBar, tab: nil, title: "Le sezioni dell'app",
             text: "Da qui passi tra Home, Agenda, Scorte, Finanze e Case. Puoi anche scorrere di lato."),
    TourStep(target: .homeReview, tab: "Home", title: "Da completare",
             text: "Le prenotazioni arrivate da Airbnb, Booking o dal sito a cui manca l'importo finiscono qui: un tocco e le completi."),
    TourStep(target: .agendaPrices, tab: "Agenda", title: "Calendario e prezzi",
             text: "Vedi arrivi e partenze giorno per giorno. Con Modifica prezzi scegli le notti e cambi il prezzo sul sito."),
    TourStep(target: .scorteScan, tab: "Scorte", title: "Scorte con la fotocamera",
             text: "Inquadra il codice a barre di un prodotto per aggiungerlo. L'app ti avvisa quando sta per finire."),
    TourStep(target: .finanzeBalance, tab: "Finanze", title: "Le tue finanze",
             text: "Entrate nette già calcolate per piattaforma, spese e grafici del periodo."),
    TourStep(target: .caseBookingImport, tab: "Case", title: "Aggiorna da Booking",
             text: "Scarica da Booking il file \"Arrivi con recapiti\" e caricalo qui: prenotazioni, importi e finanze si aggiornano da soli."),
    TourStep(target: .profile, tab: "Home", title: "Impostazioni e guida",
             text: "Qui trovi i collaboratori e gli inviti, le notifiche e la privacy, e puoi rivedere questa guida quando vuoi."),
]

/// I passi per questo utente: si salta un passo il cui tab non c'è (permessi), l'import Booking se l'utente non gestisce
/// nessuna casa (la sezione Gestione è solo per chi gestisce) e i prezzi se nessuna casa ha un annuncio approvato
/// (`canEditPrices` falso: in Agenda il pulsante non c'è).
func tourSteps(visibleTabs: [String], canManageAHouse: Bool, canEditPrices: Bool) -> [TourStep] {
    allTourSteps.filter { step in
        (step.tab == nil || visibleTabs.contains(step.tab!))
            && (step.target != .caseBookingImport || canManageAHouse)
            && (step.target != .agendaPrices || canEditPrices)
    }
}
