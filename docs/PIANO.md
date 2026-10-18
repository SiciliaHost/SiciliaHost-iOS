# Piano di lavoro — parità completa con l'app Android

**Obiettivo:** ogni funzione dell'app Android esiste su iOS, in modo nativo. **Garanzia di completezza:**
`docs/INVENTARIO.md` elenca tutti i 211 file Kotlin (154 sorgenti + 57 test) e le risorse, ciascuno assegnato a
una fase. Una fase si chiude solo quando le sue righe non hanno più stato `—`. La fase F11 verifica che
in tutto l'inventario non resti nessun `—` (solo `n/a` motivati). Se l'Android guadagna file nuovi mentre
si lavora, aggiungerli a mano all'inventario (lo script `tools/gen_inventario.py` rifiuta di sovrascriverlo).

**Baseline:** le specifiche sono l'app Android al commit indicato in `docs/INVENTARIO.md`. Ogni fase produce `docs/funzioni/F<n>.md` (checklist funzioni per file, come `F1.md`) prima di scrivere codice.

**Regole valide in ogni fase**
1. All'inizio della fase rileggi **ogni file Android elencato** e scrivi nel DIARIO l'elenco delle funzioni
   che contiene (comportamenti, casi limite, messaggi di errore): è l'elenco da spuntare, non i soli titoli sotto.
2. Ogni logica pura portata si porta **con il suo test** (i 57 test Android sono la specifica).
3. Aggiorna `INVENTARIO.md` e `MAPPA_PORTING.md` e il DIARIO a fine lavoro. Mai dichiarare "fatto" ciò che non è stato compilato: stato `scritto` finché un Mac non lo costruisce.
4. Contratto dati col sito/Android: `../Androidapp/CLAUDE.md`. Non cambiare nomi o forma dei campi.

**Binario parallelo G — Compilazione (richiede un Mac o una CI macOS; non è detto che serva l'utente):** appena c'è un Mac/CI, ogni fase già "scritta" va compilata, i test eseguiti,
gli errori corretti. Finché G non parte il rischio si accumula: più si scrive senza compilare, più errori si ritrovano insieme.
Consiglio: far partire G dopo F1–F2. Alternativa da verificare PRIMA di affermarla: il toolchain Swift per Windows (swift.org / winget) potrebbe compilare ed eseguire gli XCTest dei file senza Firebase (modelli, AccessScope, CallableParsers, ListingStatus, ServiceCatalog, FanOut, LookupService, tutta F2) in un piccolo pacchetto SwiftPM; `accessState` e `describeHostError(code:message:)` oggi stanno in file che importano Firebase e andrebbero separati. Il bridging NSNumber/Bool differisce fuori da Apple: prenderebbe errori di sintassi/tipi, non di bridging. Non installare nulla senza chiedere all'utente.

| Fase | Contenuto | File |
|---|---|---|
| **F1** | Livello dati completo | 39 |
| **F2** | Logica pura e utilità | 37 |
| **F3** | Accesso, shell, stile, navigazione | 46 |
| **F4** | Home | 1 |
| **F5** | Agenda, prenotazioni, prezzi | 9 |
| **F6** | Scorte | 5 |
| **F7** | Finanze | 7 |
| **F8** | Check-in Alloggiati | 5 |
| **F9** | Case, sito, posizione, membri, inviti | 57 |
| **F10** | Sfondo, notifiche, sincronizzazioni | 5 |
| **F11** | Rifinitura e rilascio | risorse |

## F1 — Livello dati completo
Tutto ciò che parla con Firebase, senza interfaccia.
- **Modelli rimanenti**: `Contact`, `AlloggiatiCredentials`, `InviteGrant`, `ListingStatus`, `PromoEntry`, `PropertySiteContent` (e sotto-strutture del sito), `SeasonalRateEntry`, `ServiceCatalog` (catalogo servizi), e i tipi di risposta delle callable (`Invite`, `InvitePreview`, `MemberInfo`, `TransferResult`, `ElencoSchedineEsito`, `HostRow`, `LookupEntry`).
- **`FirestoreService` completo** (tutto `DatabaseRepository.kt`): profilo e flag onboarding (`introSeen`, `tourDone`), case (crea con membership, aggiorna con merge, tutte le case per l'admin), conteggi import Booking, credenziali Alloggiati (sotto-documento `private/alloggiati`), prenotazioni (aggiungi, merge, aggiorna, elimina con/senza spese, in revisione, per piattaforma, sync iCal a lotto), spese (aggiungi, imposta, elimina a lotti), spese ricorrenti, inventario (lista, aggiungi, aggiorna, immagine), cache prodotti per codice a barre, upload foto prodotto su Storage, token FCM, contatti a lotto, ospiti (lista, salva, elimina, segna inviato).
- **Servizi callable** (`FirebaseFunctions`): `HostFunctions` (inviti: crea/leggi/rifiuta/riscatta; membri: elenca/rimuovi/permessi; trasferimento proprietà e reclamo; Alloggiati: invio schedine, tabelle, ricevuta PDF; descrizione errori in italiano), `Listing` (submit/withdraw/startSitePublication/review/adminUpsert/listHosts), `Price` (tariffe stagionali, promozioni automatiche, sovrapprezzi ospiti), `SiteContent` (lettura case, `upsertProperty`, foto su Storage, errori).
- **`LookupService`** Alloggiati (tipi alloggiato, tipi documento, luoghi; cache su disco; filtro luoghi).
- **`AccessSession`** (cache per utente + invalidazione) e `AuthService` completo (registrazione, logout con pulizia di sessione/cache).
- Test: parser delle callable (`HostFunctionsParsersTest`, `ListingRepositoryParseTest`, `ParseSeasonalRatesTest`, `PriceRepositoryParseTest`), `FanOutTest`, `ListingStatusTest`, `PropertyTest`, `ServiceCatalogTest`, `AccessScope*Test`.

## F2 — Logica pura e utilità
Tutto `data/utils`, `data/mrz`, `data/invite`, con i test omonimi.
- Calcoli economici: `FinancialCalculator`, `FinanceStats`, `FinanceInsights`, `FinancePeriod`, `BookingStats`, `ExpenseCategory`, `RecurringExpenses`, `OrphanExpenses`, `DateRangeUtils`.
- Import Booking: `BookingExcelParser` (xls/xlsx — **decisione da prendere e scrivere nel diario**: libreria Swift per Excel vs. elaborazione server), `BookingImportPlan`.
- iCal: parser eventi + `buildSyncPlan` + eventi bloccati (porting dal `ICalSyncWorker`, solo la parte pura; il lavoro in sfondo è F10).
- Scraper annuncio Airbnb (`AirbnbListingScraper`), geocoding `NominatimClient` (+ User-Agent proprio: l'Android fu bloccato da OSM per l'UA), `GeoMath`, `ServiceImport` (testo incollato → servizi).
- Foto: `PhotoEncoder` (ridimensionamento + orientamento EXIF + JPEG), `PhotoLogic`.
- `MrzParser` + `MrzData` (documenti d'identità), `InviteLink` (formato codice/link invito).

## F3 — Accesso, shell, stile e navigazione
- **Login**: Accedi con **Apple** (obbligatorio), **Google** (+ uscita dall'account Google ricordato, `logout(context)` dell'Android; completa `AuthRepository`), email/password, errori in italiano, ripristino sessione all'avvio.
- **Shell**: `MainScreen` (barra schede, selettore casa, scorciatoie, pulsante profilo), `MainScreenViewModel`, `LoadErrorScreen`, `OnboardingScreen` (nessuna casa: crea casa o codice invito).
- **Presentazione e guida**: `Intro` (presentazione animata, `IntroLogic`, overlay), `Tour` guidato (`TourLogic/State/Overlay`, bersagli per scheda), `OnboardingController` (flag salvati sull'account), **Termini per gli host** (`HostTerms`, versione accettata, dialog).
- **Profilo** (`ProfileScreen`): dati account, ruolo, esci, rivedi intro/tour.
- **Tema e stile**: colori, tipografia, dimensioni, sfondo ambiente, vetro (materiali iOS), pulsanti, superfici, campi di selezione, movimento; modalità chiara/scura; **Dynamic Type** (equivale a `FontScale`/correzioni "large-font" dell'Android).
- **Layout adattivo** (`ui/adaptive`: Fold, cerniera, split, `LayoutMode`): su iOS equivale a size class / iPad; decidere se supportare iPad (nota nel diario). Le parti specifiche del Fold sono `n/a` con motivo.
- **Navigazione** (`Navigation`, `NavigationKeys`): tutte le destinazioni (Login, Main, Checkin, MrzScan, GuestForm, CheckinSend, EditReservation, Members, NewCaseWizard…) con transizioni; **deep link inviti** (Universal Link / URL scheme) e `PendingInvite`.

## F4 — Home (`DashboardScreen`)
Arrivi (oggi/prossimi) con scheda e anteprima dettaglio, prenotazioni **da completare** (`needsReview`, inserimento importo), accesso rapido al check-in e alla modifica prenotazione, filtro per casa, stati vuoti, aggiornamento (pull-to-refresh), riepilogo.

## F5 — Agenda, prenotazioni e prezzi
- **Calendario mensile** (`CalendarScreen`: griglia, giorni con arrivi/partenze, dettaglio giorno, scelta casa, `monthGridRows`).
- **Modifica/creazione prenotazione** (`ReservationEditScreen`): date, piattaforma, ospiti, importi, calcoli netti, eliminazione con/senza spese.
- **Editor prezzi** (`PriceEditor*`, `PriceSelection`, `GuestPricing`): tariffe stagionali per giorno/intervallo, selezione multipla, sovrapprezzi per numero ospiti, promozioni automatiche (crea/elenca/elimina), rispetto del permesso `PRICES` e dell'annuncio approvato.

## F6 — Scorte (`InventoryScreen`, 1.500 righe)
Elenco per casa/categoria, stato scorta (`StockStatus`: ok/basso/esaurito), aggiunta/modifica/elimina articolo, dettaglio (`InventoryItemDetailDialog`), foto prodotto (fotocamera/libreria → **comprimere/ridimensionare in JPEG ~q0.7 prima** di `uploadProductImage`, che riceve `Data`; → Storage), **scanner codici a barre** in tre modalità (singolo, a lotto, manuale; `normalizeBarcode`), riconoscimento nome prodotto con cache (`products_cache`) e ricerca online, riepilogo lotto, soglia scorta minima, segna esaurito.

## F7 — Finanze
Bilancio (ricavi, spese, saldo, lordo, netto proprietario), per casa, per mese, per piattaforma, grafici (`FinanceCharts` → Swift Charts), periodi (`FinancePeriod`), statistiche Booking (`BookingStats`: canali, occupazione, paesi, anticipo, dispositivi), suggerimenti (`FinanceInsights`), spese (aggiungi/modifica/elimina, categorie, legate a prenotazione), spese ricorrenti, prenotazioni con importo da completare, spese orfane, interruttore "in commissione" (solo admin), **import Excel Booking** con piano di importazione e conteggi, schermate di dettaglio, `FinanceView`, chiavi liste stabili (`FinanceListKeys`, la causa del crash visto su Android).

## F8 — Check-in Alloggiati
Elenco ospiti della prenotazione, **scanner MRZ** (fotocamera + Vision, inserimento manuale alternativo), modulo ospite (tipo alloggiato, anagrafica, luoghi con ricerca, documento), validazioni, salvataggio/modifica/eliminazione schede, **invio ad Alloggiati Web** (`CheckinSendScreen`: invio o solo verifica, esito per scheda, errori), ricevuta PDF (anteprima/condivisione), segna inviato.

## F9 — Case, sito, posizione, membri, inviti (57 file)
- **Tab Case**: elenco (`CasesScreen`, `CaseCard`, stato annuncio, filtro host per admin), dettaglio (`CaseDetailScreen`) con sezioni: Informazioni, Orari e regole, Gestione (credenziali Alloggiati, iCal, import Booking), Prezzi, Contenuti, Posizione, Info ospiti, Stato annuncio; bozza campi app (`AppFieldsDraft`, salvataggio con merge/`viaAdmin`).
- **Sito**: bozza e salvataggio (`SiteDraft`, `SiteDraftSaver`), foto (carica, ordina, elimina), traduzioni, **contenuti pagina** (servizi, regole strutturate, accesso, tariffe/spese, dintorni, trasporti, host; `ServicesEditor`, `PageContentEditor`), importazione da Airbnb.
- **Posizione**: mappa (MapKit), selettore posizione, area pubblica 30–300 m, ricerca indirizzo (Nominatim), marcatori, validazioni di privacy.
- **Pubblicazione**: invia/ritira/avvia pubblicazione, requisiti minimi, motivi di rifiuto, schermata **Host** dell'admin (approva/rifiuta annunci, `listHosts`, `adminUpsert`).
- **Creazione guidata** (`NewCaseWizard`: livello APP e SITE, passi, riprendi bozza, `WizardLogic`).
- **Membri e inviti**: elenco membri, rimozione, permessi FINANCE/PRICES/SITE, trasferimento proprietà, compositore invito (`InviteComposerDialog`), creazione/condivisione link, schermata di accettazione (`InviteScreen`).
- **Gestione casa** (`PropertyManagementViewModel`): credenziali Alloggiati, collegamenti iCal, ecc.

## F10 — Sfondo, notifiche e sincronizzazioni
Notifiche push (APNs + FCM, registrazione token, `MyFirebaseMessagingService`, notifiche locali `LocalNotifier`), **sincronizzazione iCal** Airbnb/Booking (BGTaskScheduler + a ogni apertura; iOS non garantisce l'orario, è un limite da scrivere nel diario), **promemoria mensile** per l'export Excel Booking.

## F11 — Rifinitura e rilascio
Icona e logo, testi/localizzazione, accessibilità (VoiceOver, Dynamic Type), modalità scura, iPad (se deciso), prestazioni, privacy (App Privacy, etichette dati, motivi di uso fotocamera/notifiche), schede App Store, TestFlight, revisione Apple. **Audit finale dell'inventario**: nessuna riga `—`, tutti i test portati e verdi, confronto funzionale schermata per schermata con l'app Android su dispositivo.
