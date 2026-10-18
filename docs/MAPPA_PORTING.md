# Mappa di porting Android → iOS

Percorsi Android relativi a `../Androidapp/app/src/main/java/com/example/casevacanzeapp/`.
**Aggiorna la colonna Stato ogni volta che porti qualcosa** (e il DIARIO).
Stati: `—` non iniziato · `scritto` scritto ma mai compilato · `compilato` · `provato` (su simulatore/dispositivo).

## Dati e logica

| Android | iOS | Stato |
|---|---|---|
| `data/model/Property.kt`, `PropertyRole`, `PropertyPermission` | `Core/Models/Property.swift` | scritto |
| `data/model/Reservation.kt` | `Core/Models/Reservation.swift` | scritto |
| `Expense`, `RecurringExpense`, `InventoryItem`, `GuestRecord`, `User` | `Core/Models/OtherModels.swift` | scritto |
| `Contact`, `InviteGrant`, `ListingStatus`, `PromoEntry`, `PropertySiteContent`, `SeasonalRateEntry`, `ServiceCatalog`, `AlloggiatiCredentials` | — | — |
| `data/access/AccessScope.kt` | `Core/Access/AccessScope.swift` | scritto (+ test) |
| `data/access/AccessSession.kt` | `MainViewModel.load()` (niente cache globale per ora) | scritto |
| `data/repository/AuthRepository.kt` | `Core/Services/AuthService.swift` (solo email/password) | scritto |
| `data/repository/DatabaseRepository.kt` | `Core/Services/FirestoreService.swift` (solo letture: case, prenotazioni, spese, scorte, ospiti) | parziale |
| scritture (prenotazioni, spese, scorte, ospiti, contatti), `syncIcalReservationsBatch`, prodotti/Storage | — | — |
| `data/repository/HostFunctionsRepository.kt` (callable: inviti, membri, Alloggiati…) | — (FirebaseFunctions) | — |
| `ListingRepository`, `PriceRepository`, `SiteContentRepository` (callable sito/prezzi) | — | — |
| `data/utils/*` (BookingExcelParser, BookingStats, GeoMath, RecurringExpenses, ServiceImport) | — | — |
| `data/mrz`, `data/alloggiati`, `data/invite` | — | — |
| `sync/*`, `services/*` (WorkManager, FCM) | — (BGTaskScheduler / APNs) | — |

## Schermate

| Android | iOS | Stato |
|---|---|---|
| `Navigation.kt`, `NavigationKeys.kt` | `App/RootView.swift` + `NavigationStack` per scheda | scritto (solo login → gate) |
| `ui/login` | `Features/Login/LoginView.swift` (no Google/Apple) | scritto |
| `ui/main` (MainGate, MainTabs, AccessState) | `Features/Main/*` | scritto |
| `ui/main/OnboardingScreen.kt`, `ui/wizard` | — | — |
| `ui/dashboard` (Home) | `Features/Home/HomeView.swift` (solo elenco case) | segnaposto |
| `ui/calendar`, `ui/reservation` (Agenda) | — | — |
| `ui/inventory` (Scorte + scanner barcode) | — | — |
| `ui/finance` | — | — |
| `ui/checkin` (+ MRZ) | — | — |
| `ui/cases`, `ui/property`, `ui/site`, `ui/members`, `ui/invite`, `ui/profile`, `ui/terms`, `ui/tour`, `ui/intro` | — | — |
| `ui/style`, `theme`, `ui/adaptive` (stile vetro, Fold) | — (iOS: materiali nativi, Dynamic Type) | — |

## Librerie

| Android | iOS |
|---|---|
| Compose + Material3 | SwiftUI nativo |
| Navigation3 | `NavigationStack` / `TabView` |
| Firebase BoM (Auth, Firestore, Functions, Storage, Messaging) | firebase-ios-sdk via SPM |
| CameraX + ML Kit barcode | VisionKit `DataScannerViewController` |
| ML Kit text recognition (MRZ) | Vision `VNRecognizeTextRequest` |
| osmdroid | MapKit (o MapLibre se servono le tile OSM) |
| Coil | `AsyncImage` |
| Apache POI (Excel Booking) | da decidere (CoreXLSX, o parsing server-side) |
| WorkManager | `BGTaskScheduler` |
| Google Sign-In | Sign in with Apple + GoogleSignIn-iOS |
