# DIARIO DI LAVORO — SiciliaHost iOS

> **REGOLA PER OGNI AGENTE (Claude, Codex, Qwen, Gemini, umani): leggi questo file PRIMA di fare
> qualsiasi cosa e aggiornalo PRIMA di chiudere la sessione o fare commit.** Il diario è l'unica
> memoria condivisa tra le sessioni: se non lo aggiorni, il prossimo agente rifà il lavoro o
> rompe quello che hai fatto. L'hook `.githooks/pre-commit` rifiuta i commit che non toccano
> questo file (scappatoia consapevole: `SKIP_DIARIO=1 git commit ...`).

## Come si aggiorna

1. Aggiorna **Stato attuale** e **Prossimi passi** in modo che riflettano il mondo *dopo* il tuo lavoro.
2. Aggiungi una voce **in cima** al **Registro** (la più recente per prima): data `AAAA-MM-GG`, chi sei
   (modello/agente), cosa hai fatto, cosa NON hai verificato, dove ti sei fermato.
3. Decisioni che non si ricavano dal codice → **Decisioni**. Cose che solo l'utente può fare → **Da fare dall'utente**.
4. Sii onesto: scrivi "non compilato" / "non provato su dispositivo" se è così. Mai "funziona" senza prova.

---

## Il progetto in breve

Riscrittura **nativa iOS (SwiftUI)** dell'app Android `CaseVacanzeApp` (back office per gestori di
case vacanza: prenotazioni, scorte, finanze, check-in Alloggiati Web, contenuti del sito).
Sorgente di verità funzionale: la repo Android in `../Androidapp` (Kotlin + Compose) e il suo
`CLAUDE.md`, che descrive il contratto con il sito (`../Siciliahost.it`). **Stesso progetto Firebase
`siciliahostmanager`**: Firestore, Auth, Storage, Functions sono condivisi; l'app iOS NON ha un
backend suo. Lingua dell'interfaccia: italiano. Documenti utili: `docs/ARCHITETTURA.md`,
`docs/MAPPA_PORTING.md` (cosa dell'Android è già portato), `docs/SETUP_MAC.md`.

**Vincolo d'ambiente importante:** finora si è lavorato da **Windows senza Swift né Xcode**. Il codice
scritto qui **non è mai stato compilato**. Il primo compito su un Mac è `xcodegen generate`, compilare
e correggere gli errori (vedi Prossimi passi).

## Stato attuale

- Repo creata, scheletro SwiftUI scritto, **mai compilato** (nessun Mac/Xcode a disposizione).
- Presenti: modelli Firestore (Property, Reservation, Expense, RecurringExpense, InventoryItem,
  GuestRecord, Contact, User), `AccessScope` (porting 1:1 dei permessi), servizio Auth (email/password),
  servizio Firestore (proprietà, prenotazioni, spese, scorte, ospiti), `MainGate` + `TabView` con le
  5 schede come segnaposto, schermata di login, test unitari per permessi e schede visibili.
- NON presenti: tutte le schermate vere, login Google/Apple, notifiche push, scanner MRZ/barcode,
  mappe, import Excel Booking, sincronizzazione iCal, Cloud Functions client, tema/stile "vetro".

## Prossimi passi (in ordine)

1. **[Mac] Primo build**: `brew install xcodegen && xcodegen generate`, aprire `SiciliaHost.xcodeproj`,
   mettere `GoogleService-Info.plist` in `SiciliaHost/Resources/`, compilare, correggere gli errori
   di sintassi/API, far girare `SiciliaHostTests`. Annotare nel registro tutto ciò che si è dovuto correggere.
2. Login: aggiungere **Accedi con Apple** (obbligatorio da App Store se c'è il login Google) e Google Sign-In.
3. **Home** (prenotazioni di oggi / da completare / check-in) — sorgente: `Androidapp/.../ui/dashboard`.
4. **Agenda/Calendario** + modifica prenotazione — `ui/calendar`, `ui/reservation`.
5. **Scorte** (inventario + scanner codici a barre con VisionKit `DataScannerViewController`) — `ui/inventory`.
6. **Finanze** — `ui/finance` (+ `data/utils/BookingStats`, `RecurringExpenses`).
7. **Check-in Alloggiati** (scanner MRZ con Vision/AVFoundation, callable `submitAlloggiati`) — `ui/checkin`, `data/mrz`, `data/alloggiati`.
8. **Case** (scheda casa, contenuti sito via callable `upsertProperty`, posizione/mappa MapKit, inviti, membri) — `ui/cases`, `ui/site`, `ui/members`, `ui/invite`.
9. Notifiche push (APNs + FCM), sincronizzazione iCal, import Excel Booking, tema, icona, TestFlight.

## Decisioni prese

- **SwiftUI + iOS 17+** (`@Observable`, `NavigationStack`), architettura MVVM semplice, nessuna libreria UI esterna.
- **XcodeGen** (`project.yml`) invece di un `.xcodeproj` versionato: si lavora anche da Windows senza
  Xcode, e il progetto si rigenera sul Mac. Il `.xcodeproj` è in `.gitignore`.
- **Firebase iOS SDK via Swift Package Manager** (Auth, Firestore, Functions, Storage, Messaging).
- **Stesso backend e stesso contratto dati dell'Android**: non cambiare forma/nome dei campi (vedi
  `Androidapp/CLAUDE.md`, sezione "Who owns what"). In particolare: `properties` si scrive SEMPRE con
  `setData(..., merge: true)` e solo i campi dell'app (`Property.appFields`); i campi del sito solo via callable `upsertProperty`.
  Le date di `Reservation` sono epoch millisecondi (`Int64`), non `Timestamp`.
- Super-admin = email verificata `aleloverde@gmail.com` (come in `firestore.rules`).
- Bundle ID **provvisorio**: `com.siciliahost.manager` (vedi "Da fare dall'utente").

## Da fare dall'utente (solo lui può)

- Fornire/usare un **Mac con Xcode 16+** (o un servizio di build in cloud: Xcode Cloud, Codemagic, GitHub Actions macOS).
- Iscrizione all'**Apple Developer Program** (99 $/anno), necessaria per dispositivo reale, TestFlight e App Store.
- **Confermare il Bundle ID** (permanente una volta pubblicata l'app) e registrare l'app iOS nel progetto
  Firebase `siciliahostmanager`; scaricare `GoogleService-Info.plist`.
- Creare la chiave **APNs** e caricarla in Firebase (per le notifiche) e abilitare Sign in with Apple.
- Decidere se pubblicare la repo su GitHub (finora esiste solo in locale).

## Registro (più recente in alto)

### 2026-10-18 — Claude Sonnet 5.5 — avvio del progetto
- Analizzata l'app Android (154 file Kotlin, ~21.000 righe; 94 file di UI), letti modelli, `AccessScope`,
  navigazione, tab, `DatabaseRepository` e `HostFunctionsRepository`.
- Creata la repo `SiciliaHost-iOS` (git locale, branch `main`), con diario, regole per gli agenti
  (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`, `GEMINI.md`), hook `pre-commit` che esige l'aggiornamento del diario,
  `project.yml` XcodeGen, documenti in `docs/`.
- Scritti modelli, `AccessScope`, `AuthService`, `FirestoreService`, `MainViewModel`, gate + tab shell, login, test.
- **Non verificato**: niente è stato compilato né eseguito (Windows, nessun Swift). Aspettarsi errori al primo build.
- Mi sono fermato dopo lo scheletro: le 5 schede sono segnaposto. Prossimo passo: vedi "Prossimi passi" n.1.
