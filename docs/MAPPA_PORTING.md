# Mappa di porting Android → iOS

Lo stato file per file sta in **`docs/INVENTARIO.md`** (unica fonte di verità: tutti i 211 file Kotlin, fase per fase).
Il piano delle fasi è in `docs/PIANO.md`. Qui resta solo la corrispondenza tra librerie e API.

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
