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

- Piano completo in `docs/PIANO.md` (fasi F1–F11) e inventario di **tutti** i 211 file Kotlin in `docs/INVENTARIO.md`.
- **F1 (livello dati) scritta, MAI compilata**: tutti i modelli, `FirestoreService` completo, servizi callable
  (host/inviti/membri/Alloggiati, annunci, prezzi, contenuti sito), Lookup Alloggiati, `AccessSession`, FanOut,
  parser delle risposte e messaggi d'errore, con i test portati da Android. Resta fuori solo il login Google/Apple (F3).
- Presenti dall'avvio: login email/password, gate + `TabView` con 5 schede (segnaposto tranne Home che elenca le case).
- Da fare: F2–F11 (vedi piano). Nessuna schermata vera ancora.

## Prossimi passi (in ordine)

0. **[Mac, appena disponibile — binario G]** `brew install xcodegen && xcodegen generate`, `GoogleService-Info.plist` in
   `SiciliaHost/Resources/`, compilare, correggere gli errori, far girare i test. Annotare nel registro cosa si è corretto.
   Più si scrive senza compilare più errori si accumulano: farlo dopo F2 al più tardi.
1. **F2 — Logica pura e utilità** (`data/utils`, `data/mrz`, `data/invite` + test omonimi). Vedi `docs/PIANO.md`.
   Decisione da prendere lì: libreria per leggere gli Excel di Booking (xls/xlsx) o elaborazione lato server.
2. F3 login Google/Apple + shell + stile, poi F4…F11 come da piano.

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
- Bundle ID **provvisorio**: `com.siciliahost.manager` (vedi "Da fare dall'utente").

## Da fare dall'utente (solo lui può)

- Fornire/usare un **Mac con Xcode 16+** (o un servizio di build in cloud: Xcode Cloud, Codemagic, GitHub Actions macOS).
- Iscrizione all'**Apple Developer Program** (99 $/anno), necessaria per dispositivo reale, TestFlight e App Store.
- **Confermare il Bundle ID** (permanente una volta pubblicata l'app) e registrare l'app iOS nel progetto
  Firebase `siciliahostmanager`; scaricare `GoogleService-Info.plist`.
- Creare la chiave **APNs** e caricarla in Firebase (per le notifiche) e abilitare Sign in with Apple.
- Decidere se pubblicare la repo su GitHub (finora esiste solo in locale).

## Registro (più recente in alto)

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
