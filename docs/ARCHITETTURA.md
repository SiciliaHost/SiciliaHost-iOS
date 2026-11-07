# Architettura

- **SwiftUI, iOS 17+**, MVVM con `@Observable` (Observation framework). Nessuna libreria UI di terze parti.
- **Livelli**: `Core/Models` (struct `Codable` tolleranti) → `Core/Services` (Firebase) → `Features/<Schermata>`
  (`View` + `ViewModel`). `Core/Access/AccessScope` è logica pura (testabile senza Firebase).
- **Backend**: stesso progetto Firebase `siciliahostmanager` dell'Android e del sito. Nessun server nuovo.
- **Navigazione**: `RootView` sceglie Login/Gate in base a `AuthService.currentUser`; `MainTabView` ha una
  `NavigationStack` per scheda. Le schermate di dettaglio vanno spinte con `navigationDestination`.
- **Permessi**: ogni vista che mostra azioni deve passare da `AccessScope` (`canOperate`, `canManage`,
  `canFinance`, `canEditPrices`, `canEditSite`). Le firestore.rules restano l'autorità: la UI è solo cortesia.
- **Decoding**: i modelli leggono con `container.value(_, default)` / `container.optional(_)` (`Decoding.swift`),
  perché i documenti reali hanno campi mancanti o di tipo diverso (scritti da Android/sito/Functions).
- **Scritture**: `Property` solo con `appFields` + `merge: true`. Per gli altri modelli preferire dizionari
  espliciti o `setData(from:merge:)`, ricordando che `Codable` omette i campi `nil` (con merge non cancella).
- **Date**: epoch millisecondi `Int64` (come l'Android e il sito). Formati stringa: "yyyy-MM" (spese fisse),
  dd/MM/yyyy (Alloggiati).
- **Errori e testi**: in italiano, messaggi pensati per l'utente finale.
- **Finanze sul telefono** (`Core/Finance/`, come `data/finance` dell'Android): importi delle prenotazioni, commissioni,
  statistiche dell'Excel, spese, spese fisse e contatti dell'Excel stanno SOLO in un file JSON sull'iPhone del
  proprietario (`Application Support/finance/<uid>/finance.json`), mai su Firestore. JSON e non SwiftData (stessa
  ragione dell'Android e di Alloggiati). `FinanceStore` è un `actor` con UNA istanza per uid (`FinanceStoreRegistry`):
  due istanze sullo stesso file perderebbero scritture. Il file NON è escluso dal backup di sistema (backup voluto),
  protezione `.completeFileProtectionUntilFirstUserAuthentication`. `FinanceRepository` unisce prenotazioni del server e
  soldi del telefono (`joinMoney`) e riallinea (`reconcile`: orfani, importi del sito via `getSiteBookingAmounts`).
  «Importi da inserire» = prenotazioni senza lordo con `checkOut` negli ultimi 45 giorni o future (`pendingAmounts`).
  Finanze e import Excel Booking solo per l'OWNER della casa (`canFinance`, `isOwner`): i collaboratori non le vedono.
  L'import manda al server solo la parte condivisa (nome, ospiti, paese). All'eliminazione dell'account il file si
  cancella (`FinanceStore.wipe()`); il logout normale lo lascia.

## Contratto con il sito e l'Android
Leggere `../Androidapp/CLAUDE.md` (sezione "App ↔ Site"): chi possiede quali campi di `properties`, quali
collezioni sono solo-app/solo-sito, regole sulla privacy della posizione, callable da usare.
