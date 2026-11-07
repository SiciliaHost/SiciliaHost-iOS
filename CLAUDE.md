# CLAUDE.md

App iOS nativa (SwiftUI) di SiciliaHost: riscrittura dell'app Android in `../Androidapp`.

## OBBLIGATORIO a ogni sessione
1. **Leggi `DIARIO.md` per primo**: stato, prossimi passi, decisioni, cosa non è verificato.
2. **Aggiorna `DIARIO.md` prima di finire e prima di ogni commit** (Stato attuale, Prossimi passi, nuova voce in cima al Registro). L'hook `.githooks/pre-commit` rifiuta i commit senza diario. Dopo un `git clone` nuovo: `git config core.hooksPath .githooks`.
3. Dì sempre onestamente cosa hai compilato/provato e cosa no. Da Windows non esiste Swift: il codice scritto lì è non compilato finché un Mac non lo costruisce.

## Regole di progetto
- Rispondi all'utente in italiano; interfaccia dell'app in italiano.
- Backend = stesso Firebase `siciliahostmanager` dell'Android. Il contratto dati è in `../Androidapp/CLAUDE.md` ("Who owns what"): non cambiare nomi/forma dei campi, scrivi `properties` solo con merge e solo i campi dell'app.
- Piano a fasi: `docs/PIANO.md`. Stato di ogni file Android (211, nessuno escluso): `docs/INVENTARIO.md` — aggiornalo a ogni file portato (colonne iOS e Stato). Corrispondenza librerie: `docs/MAPPA_PORTING.md`.
- Architettura: `docs/ARCHITETTURA.md`. Setup Mac: `docs/SETUP_MAC.md`.
- **Finanze e contatti dell'Excel solo sul telefono del proprietario** (`Core/Finance/`, file JSON per uid): mai scrivere su Firestore `grossAmount`, `netAmountOwner`, `netAmountAdmin`, `commissionAmount`, `bookedAt`, `travelPurpose`, `bookingDevice`, `needsReview`, né `expenses`, `recurring_expenses`, `contacts`. Dettagli in `docs/ARCHITETTURA.md`.
- Non avviare emulatori/dispositivi né fare deploy senza richiesta esplicita. Non fare push/pubblicare senza che l'utente lo chieda.
