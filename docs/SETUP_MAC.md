# Setup su Mac (primo build)

Prerequisiti: macOS recente, **Xcode 16+**, Homebrew. Per girare su iPhone reale/TestFlight serve l'Apple Developer Program.

```sh
git clone <repo> && cd SiciliaHost-iOS
git config core.hooksPath .githooks      # hook che esige l'aggiornamento di DIARIO.md
brew install xcodegen
xcodegen generate                         # crea SiciliaHost.xcodeproj da project.yml
open SiciliaHost.xcodeproj
```

1. **Firebase**: nella console del progetto `siciliahostmanager` aggiungi un'app iOS con il Bundle ID di
   `project.yml` (provvisorio `com.siciliahost.manager`: confermarlo prima di pubblicare), scarica
   `GoogleService-Info.plist` e mettilo in `SiciliaHost/Resources/`. Poi rilancia `xcodegen generate`.
2. Imposta il Team di firma in Xcode (Signing & Capabilities).
3. Compila (⌘B) e correggi gli errori: **il codice iniziale è stato scritto senza compilatore**. Annota nel DIARIO cosa hai corretto.
4. Test: ⌘U (`SiciliaHostTests`) oppure
   `xcodebuild test -scheme SiciliaHost -destination 'platform=iOS Simulator,name=iPhone 16'`.
5. Più avanti: capability *Sign in with Apple*, *Push Notifications* (+ chiave APNs in Firebase), *Background Modes*.

Se non hai un Mac: build in cloud con Xcode Cloud, Codemagic o GitHub Actions (runner `macos-latest`), partendo dallo stesso `project.yml`.
