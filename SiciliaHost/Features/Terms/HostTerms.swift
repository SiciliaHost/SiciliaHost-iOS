import SwiftUI

/// Condizioni d'uso di SiciliaHost per gli host, accettate a ogni "Invia per approvazione".
///
/// `version` deve essere uguale a `HOST_TERMS_VERSION` nelle Functions del sito (`functions/src/listing/hostTerms.ts`):
/// il server rifiuta l'invio con una versione diversa e registra l'accettazione (utente, casa, versione, ora) in
/// `hostTermsAcceptances`. Cambiare il testo = cambiare la versione qui e là.
enum HostTerms {
    static let version = "v1-2026-10-17"

    static let title = "Condizioni d'uso per gli host"

    static let text = """
    1. Chi siamo e qual è il nostro ruolo
    SiciliaHost (siciliahost.com) è una piattaforma che mette in contatto gli host, che offrono in locazione turistica la propria casa, con gli ospiti che vogliono prenotarla. Agiamo solo come intermediario tecnico: non siamo proprietari, gestori o locatori delle case di terzi, non siamo parte del contratto di soggiorno tra host e ospite e non garantiamo che arrivino prenotazioni.

    2. L'app e il sito sono due cose distinte
    L'app è uno strumento di gestione (prenotazioni, check-in, scorte, finanze) e puoi usarla anche senza pubblicare la casa sul sito. Queste condizioni si applicano quando invii un annuncio per la pubblicazione su siciliahost.com.

    3. Cosa facciamo per te
    - Verifichiamo l'annuncio prima di pubblicarlo e, se serve, ti chiediamo correzioni indicando i motivi.
    - Pubblichiamo e traduciamo l'annuncio, mostriamo la disponibilità e i prezzi che imposti.
    - Raccogliamo le richieste di prenotazione e ti mettiamo in contatto con l'ospite.
    - Ti diamo l'app e il pannello web per gestire le prenotazioni ricevute, anche da altre piattaforme, e ti assistiamo scrivendo a info@siciliahost.com.
    - Mostriamo sulla mappa del sito il pin con la posizione della casa (o l'area approssimativa se non c'è il pin), mentre proteggiamo l'indirizzo civico completo: l'ospite lo vede solo dopo la prenotazione confermata.
    Ci impegniamo a farlo con diligenza, ma il servizio è fornito "così com'è": può avere interruzioni o errori.

    4. Beta gratuita e commissione
    Il sito è in fase beta: durante la beta non applichiamo nessuna commissione e la pubblicazione è gratuita. Al termine della beta potremo applicare una commissione del 5% (calcolata sull'importo del soggiorno, escluse imposte di soggiorno) sulle prenotazioni ricevute tramite siciliahost.com, senza canone né costi di pubblicazione. Ti avvisiamo con almeno 30 giorni di anticipo: la commissione vale solo per le prenotazioni fatte dopo l'entrata in vigore e puoi ritirare l'annuncio se non la accetti. Le prenotazioni che non passano dal sito non sono mai soggette a commissione.

    5. Pagamenti, caparra e cancellazioni
    I pagamenti sono gestiti direttamente da te con l'ospite tramite le coordinate che configuri nel pannello host (bonifico IBAN e/o PayPal.me): l'ospite ti versa direttamente la caparra del 30% entro 48 ore dall'accettazione o dalla prenotazione immediata, tu confermi l'incasso dal pannello ("Caparra ricevuta") e riscuoti il saldo al check-in o secondo gli accordi con l'ospite. Si applica la regola unica della piattaforma: cancellazione gratuita con rimborso integrale della caparra a tuo carico fino a 15 giorni prima del check-in; oltre tale termine la caparra resta a te. SiciliaHost non incassa, non detiene e non risponde delle somme dovute per il soggiorno, né di rimborsi, caparre o cancellazioni. Se in futuro introdurremo i pagamenti tramite la piattaforma, ti chiederemo di accettare le condizioni aggiornate.

    6. I tuoi impegni
    - Hai il diritto di locare la casa (proprietà, mandato o autorizzazione di chi ne ha titolo, condominio incluso) e sei in regola con le norme applicabili: codice identificativo (CIN), segnalazione di inizio attività, sicurezza degli impianti, assicurazioni, norme fiscali.
    - Le informazioni, le foto, i prezzi, le coordinate di pagamento e la disponibilità dell'annuncio sono veritieri e aggiornati; le foto sono tue o hai il diritto di usarle.
    - Onori le prenotazioni confermate e rimborsi tempestivamente la caparra in caso di cancellazione entro i 15 giorni; cancellare senza giusta causa può portare alla sospensione dell'annuncio.
    - Comunichi gli ospiti alla Questura (Alloggiati Web), riscuoti e versi l'imposta di soggiorno e rispetti ogni altro obbligo di legge: sono responsabilità tua.
    - Tratti i dati personali degli ospiti in qualità di autonomo titolare del trattamento solo per la prenotazione e gli obblighi di legge, nel rispetto del GDPR.
    - Dopo la beta, non aggiri la piattaforma per evitare la commissione sugli ospiti conosciuti tramite siciliahost.com.

    7. Contenuti
    Resti proprietario dei contenuti che carichi. Ci concedi una licenza non esclusiva, gratuita e limitata alla durata dell'annuncio per mostrarli, tradurli e promuoverli su siciliahost.com e nei nostri canali.

    8. Responsabilità
    Come intermediario, non rispondiamo dello stato della casa, di danni, furti, infortuni, comportamento degli ospiti o inadempimenti del soggiorno: rispondi tu come locatore. Ti impegni a tenerci indenni da richieste di terzi derivanti da tuoi inadempimenti o da informazioni false. Per quanto la legge consente, la nostra responsabilità verso di te è limitata alle commissioni ricevute da noi per la prenotazione in questione. Niente in queste condizioni esclude responsabilità che la legge non permette di escludere.

    9. Rifiuto, sospensione e recesso
    Possiamo rifiutare, sospendere o rimuovere un annuncio non conforme a queste condizioni o alla legge, o in caso di segnalazioni ripetute, indicandone i motivi. Puoi ritirare l'annuncio in qualsiasi momento dall'app o dal sito; le prenotazioni già confermate restano valide.

    10. Modifiche
    Possiamo aggiornare queste condizioni: ti chiederemo di accettare la nuova versione al prossimo invio di un annuncio, e le modifiche non cambiano le prenotazioni già confermate.

    11. Legge e foro
    Si applica la legge italiana. Per le controversie con host che agiscono per scopi professionali è competente in via esclusiva il Foro di Palermo. Restano salvi i diritti inderogabili e il foro obbligatorio del consumatore (art. 66-bis D.Lgs. 206/2005) per gli host che non agiscono nell'ambito di un'attività professionale.

    SiciliaHost — progetto di Alessandro Lo Verde, C.F. LVRLSN93P15G273F, Via Isidoro La Lumia, 7, 90139 Palermo — info@siciliahost.com

    Versione: \(version)
    """
}

/// Le condizioni d'uso prima di "Invia per approvazione": testo scorrevole, casella da spuntare, "Accetta e invia"
/// attivo solo con la spunta. `onAccept` invia con `HostTerms.version`. Si presenta come foglio.
struct HostTermsSheet: View {
    let onAccept: () -> Void
    let onDismiss: () -> Void
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HostTerms.title).appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)

            ScrollView {
                Text(HostTerms.text)
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(roundedShape(Radius.large).fill(Theme.surfaceContainerLow))

            Toggle(isOn: $accepted) {
                Text("Ho letto e accetto le condizioni d'uso di SiciliaHost")
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurface)
            }
            .toggleStyle(CheckboxToggleStyle())

            HStack {
                Spacer()
                Button("Annulla", action: onDismiss).buttonStyle(.appText)
                Button("Accetta e invia", action: onAccept).buttonStyle(.appPrimary).disabled(!accepted)
            }
        }
        .padding(20)
        .presentationDetents([.large])
        .presentationBackground(Theme.surfaceContainerHigh)
        .presentationCornerRadius(Radius.dialog)
    }
}

/// Casella da spuntare (su iOS un interruttore sarebbe fuorviante per un'accettazione).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(configuration.isOn ? Theme.primary : Theme.outline)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}
