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
  (`python tools/gen_inventario.py --check`: righe ancora aperte 88 su 211).
- **F1 (livello dati), F2 (logica pura) e F3 (accesso/stile/navigazione): COMPILANO in CI e i 156 test passano (2026-10-18)** — prima si diceva "mai compilate". Checklist funzioni in `docs/funzioni/F1.md` e `F2.md`.
  F2 comprende: finanze e statistiche, categorie di spesa, spese fisse, import Booking (CSV + lettore `.xls` OLE2/BIFF8 scritto a mano),
  piano di importazione, parte pura dell'iCal, geometria, Nominatim, annuncio Airbnb, import servizi, foto, MRZ, link d'invito.
- **F3 scritta** (`docs/funzioni/F3.md`; restano aperte solo 2 righe `parziale`, che finiscono in F9/F10): palette identica all'Android (chiaro/scuro), tipografia compatta, sfondo ambiente, vetro, pulsanti, card,
  barra di navigazione a pillola, icona/logo, **login Google**, gate di accesso, onboarding, presentazione a 6 pagine, tour guidato, profilo, condizioni host, stack di navigazione con tutte le destinazioni (segnaposto per quelle di F8/F9), link d'invito. Le 5 sezioni sono segnaposto tranne Home (elenca le case + pulsante profilo).
- Da fare: F3–F11 (vedi piano). Nessuna schermata vera ancora.

## Prossimi passi (in ordine)

0. **[Mac, appena disponibile — binario G]** `brew install xcodegen && xcodegen generate`, `GoogleService-Info.plist` in
   `SiciliaHost/Resources/`, compilare, correggere gli errori, far girare i test. Provare anche il file reale:
   `TEST_RUNNER_BOOKING_XLS_FIXTURE="…/Androidapp/Arrivo con recapiti_ 2026-01-01 - 2026-07-30.xls" xcodebuild test …`
   (da verificare al primo build: `xcodebuild` inoltra al test solo le variabili col prefisso `TEST_RUNNER_`; in alternativa impostare
   `BOOKING_XLS_FIXTURE` nell'ambiente dello scheme, Test → Arguments. Senza, il test fa `XCTSkip` e sembra passato: controllare che non sia "skipped".
   Il file contiene dati personali di ospiti: NON committarlo). Annotare nel registro cosa si è corretto. Dopo F2 il codice non compilato è tanto (≈30 file).
1. **F4 — Home** (`ui/dashboard`: arrivi, da completare, check-in), poi F5 (Agenda/prezzi), F6 (Scorte), F7 (Finanze), F8 (Check-in), F9 (Case…). Prima di ogni fase scrivere `docs/funzioni/F<n>.md`.
2. **Deployare le regole/Functions con `apple.com`** (a cura dell'utente, vedi sopra) prima di provare l'accesso con Apple; poi F11 (eliminazione account, ecc.).

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
- **Accesso Google + Apple (niente email)**: firestore.rules, storage.rules e `functions/src/auth/propertyAccess.ts` accettano come host solo `sign_in_provider == 'google.com'`; un account email/password verrebbe rifiutato da Firestore, Storage e Functions (per questo l'iOS non ha il login con email); Apple è stato aggiunto sui branch `feat/apple-signin-host` (non deployati).
- Navigazione: un solo `NavigationStack(path:)` con l'enum `Route` (`Features/Navigation/Router.swift`); la schermata principale è la radice, le altre si impilano; le sezioni sono un `TabView` in stile pagina con la barra di vetro sopra. Il tour usa le preferenze di layout (`.tourTarget`) per sapere dove sono gli elementi.
- Bundle ID: `com.siciliahost.manager` (scelto dall'utente il 2026-10-18; nome app «SiciliaHost Manager»).

## Risposte dell'utente (2026-10-18)

- **Baseline Android confermata**: `feat/fold-finanze-selezioni` (`379b5c5c`).
- **Cloud Functions**: l'utente conferma che esistono (deploy non verificato da me; controllare con `firebase functions:list` al primo test reale).
- **iPad: NO** → solo iPhone (`TARGETED_DEVICE_FAMILY: 1` in `project.yml`; nessun layout a due colonne/split da portare: gli ex layout "Fold/cerniera" di F3 sono `n/a`).
- **L'utente non ha né Mac né iPhone.** Compilazione: CI macOS su GitHub Actions (bozza in `docs/ci/ios.yml` da copiare in `.github/workflows/`, non provata).
  Provare l'app su un dispositivo vero richiede un iPhone (anche in prestito, via TestFlight) o un Mac in affitto con simulatore; senza, si verifica
  solo con i test e con screenshot dal simulatore in CI.
- **Nome dell'app / Bundle ID**: in attesa di scelta (proposte nella chat del 2026-10-18).

## Accesso con Apple (deciso 2026-10-18: opzione A, backend pronto ma NON deployato)

- Il backend condiviso ammetteva solo `google.com`. L'utente ha autorizzato la modifica delle regole: preparata su **branch `feat/apple-signin-host`** in `Androidapp` (commit `26195b2`: `firestore.rules`, `storage.rules`, `rules-tests`
  con nuovi test, `CLAUDE.md`) e nel sito (commit `1acede3`: `functions/src/auth/propertyAccess.ts` + test). `isHost()` ora ammette `google.com` e `apple.com`; **il super-admin resta solo Google**; gli account `password` del sito restano esclusi
  (NON è stata aggiunta l'email: riaprirebbe il buco chiuso con B1, perché ogni account del sito diventerebbe host). Test: 53 test delle regole passano in locale (emulatore), `propertyAccess.test.ts` 22 verdi.
- **NON deployato né spinto.** Ordine di rilascio (CLAUDE.md Android): Functions (`firebase deploy --only functions --project siciliahostmanager` dal branch del sito che contiene tutto ciò che è già in produzione, poi `curl` su tutte le funzioni), poi
  `firebase deploy --only firestore:rules,storage --project siciliahostmanager` dall'Androidapp. I due branch partono dai branch di lavoro attuali (Androidapp `feat/fold-finanze-selezioni`, sito `feat/condizioni-host`): portarli sul ramo da cui si fa il deploy.
- iOS: `LoginView` ha "Accedi con Apple" (`SignInWithAppleButton` + nonce SHA-256, `AuthService.signInWithApple`) e l'entitlement `com.apple.developer.applesignin`. **Finché le regole non sono deployate, l'accesso con Apple funziona ma le richieste a Firestore vengono rifiutate.**
- Da ricordare per F11: l'App Store (5.1.1(v)) chiede che un'app che permette di creare un account permetta anche di **eliminarlo** dall'app: da prevedere (Profilo → Elimina account, con Cloud Function che cancella i dati).

## Da fare dall'utente (solo lui può)

- Una via per compilare: l'utente non ha un Mac → servizio in cloud (GitHub Actions macOS, Codemagic, Xcode Cloud). Serve creare la repo su GitHub (ok esplicito).
- Iscrizione all'**Apple Developer Program** (99 $/anno), necessaria per dispositivo reale, TestFlight e App Store.
- **Confermare il Bundle ID** (permanente una volta pubblicata l'app) e registrare l'app iOS nel progetto
  Firebase `siciliahostmanager`; scaricare `GoogleService-Info.plist`.
- Creare la chiave **APNs** e caricarla in Firebase (per le notifiche) e abilitare Sign in with Apple.
- Decidere se pubblicare la repo su GitHub (finora esiste solo in locale). Se sì, una CI macOS (`.github/workflows/ios.yml`, da scrivere e non provata) darebbe il primo build senza un Mac.
- ~~Registrare l'app iOS in Firebase e `GoogleService-Info.plist`~~ — FATTO (2026-10-18). Resta la chiave APNs per le notifiche (F10).
- Per i link d'invito `https://siciliahost.com/invito/CODICE` sull'iPhone: servire `https://siciliahost.com/.well-known/apple-app-site-association` dal sito (repo Siciliahost.it, come già si fa con `assetlinks.json` per Android) con l'ID dell'app (Team ID + Bundle ID).

## Registro (più recente in alto)

### 2026-10-18 — Claude Sonnet 5.5 — prima revisione visiva (screenshot del run 39132251981)
- Visti: accesso, presentazione, home, tour, galleria (palette, tipografia, pulsanti, card). **Fedeli al marchio e all'Android**: gradiente verde del login con logo e pulsanti bianchi, sfondo ambiente a macchie, card con filo di luce, barra a pillola di vetro con indicatore verde, presentazione con disco di vetro e tessere, tour con buco e alone.
- Difetto trovato: in scuro la scritta nera del logo sparisce → aggiunta la variante `LogoDark` (scritta chiara, cactus uguale) scelta da `BrandLogo` in base al tema (vale anche per il login, che è sempre scuro: lì la scritta ora è chiara, a differenza dell'Android).
- Ancora da guardare: onboarding, profilo, errore, condizioni, versioni scure di intro/tour.

### 2026-10-18 — Claude Sonnet 5.5 — screenshot dell'interfaccia in CI
- `SiciliaHost/App/UIPreview.swift`: anteprime con dati inventati (solo build di debug, argomento di avvio `-UIPreview <login|intro|onboarding|home|tour|profile|failed|terms|gallery>`). `tools/ci_screenshots.sh` le fotografa nel simulatore in chiaro e in scuro; il workflow le carica come artefatto `ios-screenshots` (`gh run download <id> -n ios-screenshots -D <cartella>`).
- Obiettivo: controllare il rispetto del marchio e dell'Android senza un dispositivo. Aggiornare l'elenco `SCREENS` dello script quando si aggiungono schermate.

### 2026-10-18 — Claude Sonnet 5.5 — accesso con Apple (regole, Functions, app)
- Su richiesta esplicita dell'utente ("modifica tu le regole storage e firebase") preparate le modifiche: vedi la sezione "Accesso con Apple". Solo Google+Apple, NON email (motivo: B1). Nessun deploy, nessun push dei repo Androidapp/sito.
- iOS: pulsante e flusso "Accedi con Apple" + test del nonce. CI di riferimento: run 39131106371 (156 test verdi) era prima di questa modifica.

### 2026-10-18 — Claude Sonnet 5.5 — configurazione Firebase iOS
- L'utente ha registrato l'app iOS in Firebase (`siciliahostmanager`, Bundle ID `com.siciliahost.manager`, app id `1:246601493975:ios:caacdcd5857b61675b6f92`) e messo `GoogleService-Info.plist` nella radice: spostato in `SiciliaHost/Resources/` (è tracciato in git come il `google-services.json` dell'Android: sono chiavi client, non segreti; privata la repo). `GOOGLE_REVERSED_CLIENT_ID` in `project.yml` impostato dal plist. Il frammento di codice che la console Firebase mostra (AppDelegate con `FirebaseApp.configure()`) NON serve: `SiciliaHostApp` configura Firebase da sé quando il plist c'è.
- Mancano ancora: abilitare il provider Google per l'app iOS (già attivo per il progetto), l'`apple-app-site-association` sul sito, la chiave APNs (notifiche, F10).

### 2026-10-18 — Claude Sonnet 5.5 — CI attivata e primi errori di compilazione
- **RISULTATO (run 39130771414, 2026-10-18): il progetto COMPILA e i test passano — 156 test eseguiti, 0 falliti, 1 saltato** (il test sul file `.xls` reale, perché `BOOKING_XLS_FIXTURE` non c'è in CI). F1+F2+F3 sono quindi `compilato` + testate (logica); l'interfaccia non è ancora stata VISTA a schermo. Resta da fare: screenshot dal simulatore in CI per controllare lo stile.
- Primo build in CI: XcodeGen e download dei pacchetti OK; primo errore reale del compilatore: `AuthService.deinit` toccava una proprietà isolata al main actor (corretto con `AuthListenerBox`). Si procede a cicli: push → `gh run watch` → `gh run view --log-failed` → correzioni.
- L'utente ha concesso lo scope `workflow` a `gh`: la bozza `docs/ci/ios.yml` è stata copiata in `.github/workflows/ios.yml` (resta anche in `docs/ci/` come riferimento). Il push su `main` fa partire il primo build: leggerne il log (`gh run list`, `gh run view --log-failed`) e correggere gli errori di compilazione prima di scrivere altro codice.

### 2026-10-18 — Claude Sonnet 5.5 — F3 parte 2 (accesso, onboarding, navigazione, tour)
- Riletti `MainScreen`, `Navigation`, intro, onboarding, profilo, termini, tour, `MainScreenViewModel`, `LoginViewModel`, `MainActivity`.
- Scritti: login Google (`AuthService.signInWithGoogle`, uscita dall'account Google), `RootView` con presentazione sopra a tutto e `onOpenURL` (ritorno Google + link d'invito → `PendingInvite`),
  `MainViewModel` completo (trasferimenti in sospeso con timeout di 5 s, ricarica dopo invito), `OnboardingView`, `ProfileView`, `HostTerms` + foglio di accettazione, `IntroScreen/IntroOverlay`
  (6 pagine, parallax con `scrollTransition`), `TourOverlay` (velo con buco, alone che pulsa, fumetto di vetro; posizioni via preferenze di layout), `Router` (`Route`, `AppRouter`, segnaposto),
  `CompactTopBar`, limite del Dynamic Type. `project.yml`: pacchetto GoogleSignIn, schemi URL, entitlement dei link universali.
- Test: `OnboardingTests` (presentazione, tour, `PendingInvite`, tipografia, colori di marca).
- Vicolo cieco noto: "Ho un codice invito" salva il codice in `PendingInvite` ma la schermata di accettazione è F9; nel frattempo l'onboarding mostra un messaggio (`MainGateView`).
- **Scoperto**: il backend ammette solo accessi Google → niente login email; Apple richiede una decisione (sezione sopra).
- **Non verificato**: nulla compilato. Rischi: `scrollPosition(id:)` + `scrollTransition`, `anchorPreference`/`overlayPreferenceValue` attraverso un `TabView` in stile pagina, `info:`/`entitlements:` di XcodeGen con
  `GENERATE_INFOPLIST_FILE`, Canvas con riempimento pari-dispari, `sensoryFeedback(condition:)`. `GoogleService-Info.plist` e `REVERSED_CLIENT_ID` mancano: l'accesso Google non funzionerà finché non ci sono.

### 2026-10-18 — Claude Sonnet 5.5 — pubblicazione GitHub + stile di marca (F3, parte 1)
- Repo privata creata: `github.com/SiciliaHost/SiciliaHost-iOS`. Il push era rifiutato perché il token di `gh` non ha lo scope `workflow`: il file della CI è stato
  spostato in `docs/ci/ios.yml` (anche nella cronologia) così il codice è su GitHub. **Per attivare la CI**: l'utente esegue `! gh auth refresh -h github.com -s workflow`,
  poi si copia `docs/ci/ios.yml` in `.github/workflows/ios.yml` e si fa push.
- Cronologia riscritta prima del push per togliere dati reali di un ospite copiati dai test Android (sostituiti con dati inventati).
- Stile: porting di `theme/*` e `ui/style/*` + barra di navigazione a pillola + login nello stile Android + icona e logo (vedi `docs/funzioni/F3.md`). I file `ui/adaptive/*` sono `n/a` (solo iPhone).
- **Non verificato**: nulla compilato né visto a schermo. Rischi: API `symbolEffect`, `sensoryFeedback(condition:)`, `safeAreaPadding`, page-style `TabView` con `NavigationStack`, materiali sfocati
  (`.ultraThinMaterial`) sopra lo sfondo ambiente; resa dei colori dinamici. Appena c'è la CI, guardare gli screenshot del simulatore.

### 2026-10-18 — Claude Sonnet 5.5 — risposte dell'utente e CI
- Registrate le risposte (sezione "Risposte dell'utente"); `project.yml` ora solo iPhone; scritta la bozza `.github/workflows/ios.yml` (macOS + xcodegen +
  `xcodebuild test` su simulatore, più un job Linux per gli script Python). **Non provata né spinta**: la repo non è su GitHub (corretto un `mkdir -p build` mancante nel passo di test).
- **Nome scelto dall'utente: «SiciliaHost Manager»**, Bundle ID `com.siciliahost.manager` (nome mostrato impostato in `project.yml`). L'utente ha autorizzato la pubblicazione su GitHub (repo privata).
- Tolti dai test i dati reali di un ospite (nome, telefono, n. prenotazione) copiati dai test Android: sostituiti con dati inventati (Hans Muster, 5100000001, +491701234567) anche nella cronologia git, prima del push. **Non usare mai dati reali di ospiti in test, fixture o documenti.**

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
