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

## Baseline Android (spec di riferimento)

Repo `../Androidapp`, branch **`feat/fold-finanze-selezioni`**, commit `379b5c5c51bf55e4f79bb4eb433cd3ba029bbd7e` (2026-10-18).
È una cima di una pila di branch non ancora mergiati (vedi memoria del progetto: prezzi-ospiti-promozioni, stile-vetro, ecc.).
**Domanda aperta per l'utente:** quale branch Android è la fonte di verità? Se la pila viene scartata, l'iOS avrebbe funzioni che nessuno usa.
Callable usate da iOS: tutte presenti nel codice del sito (branch `feat/condizioni-host`, `957b0a8`); **deploy non verificato**
(dettaglio in `docs/funzioni/F1.md`). `python tools/gen_inventario.py --check` confronta l'inventario con la repo Android.

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

- Piano completo in `docs/PIANO.md` (fasi F1–F11) e inventario di **tutti** i 211 file Kotlin in `docs/INVENTARIO.md`
  (`python tools/gen_inventario.py --check`: righe ancora aperte 131 su 211).
- **F1 (livello dati) e F2 (logica pura) scritte, MAI compilate.** Checklist funzioni in `docs/funzioni/F1.md` e `F2.md`.
  F2 comprende: finanze e statistiche, categorie di spesa, spese fisse, import Booking (CSV + lettore `.xls` OLE2/BIFF8 scritto a mano),
  piano di importazione, parte pura dell'iCal, geometria, Nominatim, annuncio Airbnb, import servizi, foto, MRZ, link d'invito.
- Presenti dall'avvio: login email/password, gate + `TabView` con 5 schede (segnaposto tranne Home che elenca le case).
- Da fare: F3–F11 (vedi piano). Nessuna schermata vera ancora.

## Prossimi passi (in ordine)

0. **[Mac, appena disponibile — binario G]** `brew install xcodegen && xcodegen generate`, `GoogleService-Info.plist` in
   `SiciliaHost/Resources/`, compilare, correggere gli errori, far girare i test. Provare anche il file reale:
   `TEST_RUNNER_BOOKING_XLS_FIXTURE="…/Androidapp/Arrivo con recapiti_ 2026-01-01 - 2026-07-30.xls" xcodebuild test …`
   (da verificare al primo build: `xcodebuild` inoltra al test solo le variabili col prefisso `TEST_RUNNER_`; in alternativa impostare
   `BOOKING_XLS_FIXTURE` nell'ambiente dello scheme, Test → Arguments. Senza, il test fa `XCTSkip` e sembra passato: controllare che non sia "skipped".
   Il file contiene dati personali di ospiti: NON committarlo). Annotare nel registro cosa si è corretto. Dopo F2 il codice non compilato è tanto (≈30 file).
1. **F3 — Accesso, shell, stile, navigazione** (46 file: login Apple/Google, MainScreen, onboarding, intro, tour, termini host,
   profilo, tema, layout adattivo). Prima scrivere `docs/funzioni/F3.md` rileggendo i 46 file Android.
2. Poi F4 (Home), F5 (Agenda/prezzi), F6 (Scorte), F7 (Finanze), F8 (Check-in), F9 (Case/sito), F10 (sfondo), F11 (rilascio).

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
- **Il campo Firestore delle prenotazioni si chiama `icalUid`** (non `iCalUid`): la mappatura di Firestore su
  Android abbassa le maiuscole iniziali e il sito legge `icalUid`. In Swift la proprietà è `icalUid`. Controllare
  casi simili (nomi con due maiuscole iniziali o prefisso `is`) prima di aggiungere campi: i booleani `isManagedOnCommission`
  e `isDepleted` hanno il nome reale con `is`.
- **Scritture esplicite con `NSNull`** (`Core/Models/FirestoreData.swift`): niente `Codable` per scrivere, perché omette i
  `nil` e nei merge non cancellerebbe il campo (l'Android scrive null). Letture: `Codable` tollerante (`Decoding.swift`).
- Il profilo utente si scrive con esattamente `id`, `email`, `fcmToken` (le regole accettano solo quelli).
- **Date sempre in UTC** (millisecondi, mezzanotti UTC) per mesi/settimane/periodi, come l'Android: `Core/Logic/TimeUtils.swift`.
  Mesi abbreviati italiani fissi ("gen"…"dic") invece dei dati del sistema, per non cambiare etichette con la versione di iOS.
- **Excel Booking `.xls`**: lettore OLE2/BIFF8 scritto a mano (`XlsReader.swift`), perché su iOS non c'è Apache POI. Alternativa
  scartata: elaborazione lato server (nuova Cloud Function nel repo del sito). Il CSV (stesse colonne) resta supportato.
  Limiti noti: primo foglio, niente formule, niente mini-stream (file < 4 KB), file reali > 4 KB validati solo in Python.
- **User-Agent OSM per iOS**: `SiciliaHostManager/1.0 (iOS; +https://siciliahost.com; info@siciliahost.com)` (`osmUserAgent`).
- Bundle ID **provvisorio**: `com.siciliahost.manager` (vedi "Da fare dall'utente").

## Risposte dell'utente (2026-10-18)

- **Baseline Android confermata**: `feat/fold-finanze-selezioni` (`379b5c5c`).
- **Cloud Functions**: l'utente conferma che esistono (deploy non verificato da me; controllare con `firebase functions:list` al primo test reale).
- **iPad: NO** → solo iPhone (`TARGETED_DEVICE_FAMILY: 1` in `project.yml`; nessun layout a due colonne/split da portare: gli ex layout "Fold/cerniera" di F3 sono `n/a`).
- **L'utente non ha né Mac né iPhone.** Compilazione: CI macOS su GitHub Actions (`.github/workflows/ios.yml`, non provato, non ancora spinto).
  Provare l'app su un dispositivo vero richiede un iPhone (anche in prestito, via TestFlight) o un Mac in affitto con simulatore; senza, si verifica
  solo con i test e con screenshot dal simulatore in CI.
- **Nome dell'app / Bundle ID**: in attesa di scelta (proposte nella chat del 2026-10-18).

## Da fare dall'utente (solo lui può)

- Una via per compilare: l'utente non ha un Mac → servizio in cloud (GitHub Actions macOS, Codemagic, Xcode Cloud). Serve creare la repo su GitHub (ok esplicito).
- Iscrizione all'**Apple Developer Program** (99 $/anno), necessaria per dispositivo reale, TestFlight e App Store.
- **Confermare il Bundle ID** (permanente una volta pubblicata l'app) e registrare l'app iOS nel progetto
  Firebase `siciliahostmanager`; scaricare `GoogleService-Info.plist`.
- Creare la chiave **APNs** e caricarla in Firebase (per le notifiche) e abilitare Sign in with Apple.
- Decidere se pubblicare la repo su GitHub (finora esiste solo in locale). Se sì, una CI macOS (`.github/workflows/ios.yml`, da scrivere e non provata) darebbe il primo build senza un Mac.
- Rispondere a: Bundle ID definitivo; **iPad sì/no**; quale branch Android è la baseline; se le Cloud Functions usate sono deployate.

## Registro (più recente in alto)

### 2026-10-18 — Claude Sonnet 5.5 — risposte dell'utente e CI
- Registrate le risposte (sezione "Risposte dell'utente"); `project.yml` ora solo iPhone; scritta la bozza `.github/workflows/ios.yml` (macOS + xcodegen +
  `xcodebuild test` su simulatore, più un job Linux per gli script Python). **Non provata né spinta**: la repo non è su GitHub (corretto un `mkdir -p build` mancante nel passo di test).
- Proposti nomi per l'app all'utente; in attesa della scelta prima di toccare `PRODUCT_BUNDLE_IDENTIFIER` e `CFBundleDisplayName`.

### 2026-10-18 — Claude Sonnet 5.5 — F2 (logica pura e utilità)
- Riletti per intero i 37 file Android di F2 (21 sorgenti + 16 test) e la parte pura di `ICalSyncWorker`; checklist in `docs/funzioni/F2.md`.
- Scritti in `SiciliaHost/Core/Logic/`: `TimeUtils`, `Finance` (calcolatore, categorie, periodi, statistiche, spese fisse, orfane),
  `BookingStats`, `FinanceInsights`, `BookingImport` (piano + parser CSV/righe), `XlsReader`, `ICalSync`, `GeoMath`, `ServiceImport`,
  `ListingImport` (Airbnb + Nominatim + User-Agent OSM), `Photos`, `IdentityParsers` (MRZ + link d'invito).
- Test: `FinanceTests`, `BookingTests`, `LogicTests`, `XlsReaderTests` (file `.xls` sintetico costruito nel test: OLE2 + SST con CONTINUE + NUMBER/RK).
  Il costruttore sintetico e l'algoritmo di lettura sono stati verificati in Python (`tools/xls_proto.py` e `tools/xls_builder_check.py`: `python tools/xls_proto.py "../Androidapp/Arrivo con recapiti_ 2026-01-01 - 2026-07-30.xls"`) sui 3 export reali
  di Booking presenti nella repo Android: 30/40/44 righe, 0 cancellate, paese `de`, motivo `Svago`, dispositivo `Computer`, commissione 174,24 — come il test Android.
- Differenze volute rispetto all'Android: `PhotoEncoder` riceve `Data` (ImageIO) e non un Uri; date inesistenti nel CSV (31/02) scartate; `safeErrorReason` ha anche la
  versione a due stringhe (`typeName`, `message`) per i test; l'ordine di parità dei suggerimenti sulle spese segue l'ordine delle categorie.
- **Non verificato**: nulla compilato né eseguito in Swift. Rischi al primo build: tuple con etichette nei test, `guard var (a, b) = …`, `String(decoding:as: UTF16.self)`
  (ho aggiunto `utf16LE`), concorrenza (`Sendable`), `UTType` in `Photos.swift`. Percorso mini-stream dell'`.xls` non coperto da test.
- Salvati in `tools/` i due script Python di verifica e corretta l'intestazione di `docs/funzioni/F2.md`.
- Fermo qui: prossima è F3, **ma serve prima una via per compilare** e quattro risposte dell'utente (Bundle ID, iPad, baseline Android, deploy delle Functions): vedi Da fare dall'utente.

### 2026-10-18 — Claude Sonnet 5.5 — piano completo + F1 (livello dati) [revisione dopo il controllo del consulente]
- Aggiunti: baseline Android (branch+commit), `tools/gen_inventario.py --check` (percorsi relativi, rileva file Android mancanti e righe aperte),
  righe `parziale→F<n>` con la fase che le chiude, `docs/funzioni/F1.md` (checklist funzioni), `.gitattributes` (LF forzato: l'hook
  `pre-commit` si romperebbe con CRLF su Windows), scheme di test in `project.yml`.
- Da verificare (non fatto): se il toolchain Swift per Windows si installa e compila gli XCTest dei file senza Firebase (vedi `PIANO.md`).

### 2026-10-18 — Claude Sonnet 5.5 — piano completo + F1 (livello dati)
- Creati `docs/PIANO.md` (11 fasi) e `docs/INVENTARIO.md` (211 file Kotlin = 154 sorgenti + 57 test, ciascuno con la sua
  fase; lo script `tools/gen_inventario.py` fallisce se un file non ha fase e non sovrascrive l'inventario esistente).
- Eseguita F1: riletti per intero i file Android del livello dati e portati: modelli (`SimpleModels`, `ListingStatus`,
  `PropertySiteContent`, `ServiceCatalog` con le 62 chiavi), `FirestoreService` completo (tutta `DatabaseRepository`,
  compresa la sincronizzazione iCal a lotti), servizi callable, `LookupService` (cache 30 giorni), `AccessSession`, `fanOut`,
  parser + messaggi d'errore. Test portati: `CallableParsersTests`, `ModelsTests`.
- Trovato e corretto un difetto del mio scheletro: il campo era `iCalUid`, ma su Firestore è `icalUid` (vedi Decisioni).
- Pezzi di file di fasi successive già portati perché servivano ai modelli: `isOnSiteTrack`/`canEditCalendarPrices`/`approvedIds`
  (da `SiteTrack.kt`), `HostRow` (da `CaseLogic.kt`), protocollo `InviteAPI` (da `InviteViewModel.kt`); l'inventario li marca "parziale".
- **Non verificato**: nulla è compilato né eseguito (niente Swift su Windows). Punti a rischio al primo build: concorrenza
  Swift (`Sendable` di `FirestoreService`/`fanOut`), API Firestore/Functions/Storage async (`putDataAsync`, `setData(_:merge:)`),
  inferenza dei letterali nei test dei parser.
- Fermo qui: prossima è F2.

### 2026-10-18 — Claude Sonnet 5.5 — avvio del progetto
- Analizzata l'app Android (154 file Kotlin, ~21.000 righe; 94 file di UI), letti modelli, `AccessScope`,
  navigazione, tab, `DatabaseRepository` e `HostFunctionsRepository`.
- Creata la repo `SiciliaHost-iOS` (git locale, branch `main`), con diario, regole per gli agenti
  (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`, `GEMINI.md`), hook `pre-commit` che esige l'aggiornamento del diario,
  `project.yml` XcodeGen, documenti in `docs/`.
- Scritti modelli, `AccessScope`, `AuthService`, `FirestoreService`, `MainViewModel`, gate + tab shell, login, test.
- **Non verificato**: niente è stato compilato né eseguito (Windows, nessun Swift). Aspettarsi errori al primo build.
- Mi sono fermato dopo lo scheletro: le 5 schede sono segnaposto. Prossimo passo: vedi "Prossimi passi" n.1.
