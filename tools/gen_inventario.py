"""Genera docs/INVENTARIO.md: ogni file Kotlin (main + test) dell'app Android assegnato a una fase.
Fallisce se un file non ha una fase, così nessuna funzione resta fuori dal piano."""
import os, re, sys
THIS = os.path.dirname(os.path.abspath(__file__))

ROOT = r"C:\Users\Aless\desktop\progetti\siciliahost\Androidapp\app\src"
OUT = r"C:\Users\Aless\desktop\progetti\siciliahost\SiciliaHost-iOS\docs\INVENTARIO.md"
BASE = "java/com/example/casevacanzeapp/"

# (prefisso relativo al package, fase). Il primo che combacia vince: mettere i più specifici prima.
RULES = [
    ("data/model/", "F1"), ("data/repository/", "F1"), ("data/access/", "F1"), ("data/alloggiati/", "F1"),
    ("data/invite/", "F2"), ("data/mrz/", "F2"), ("data/utils/", "F2"),
    ("sync/", "F10"), ("services/", "F10"),
    ("theme/", "F3"), ("ui/style/", "F3"), ("ui/adaptive/", "F3"), ("ui/common/", "F3"),
    ("ui/login/", "F3"), ("ui/main/", "F3"), ("ui/intro/", "F3"), ("ui/tour/", "F3"),
    ("ui/terms/", "F3"), ("ui/profile/", "F3"),
    ("MainActivity", "F3"), ("Navigation", "F3"),
    ("ui/dashboard/", "F4"),
    ("ui/calendar/", "F5"), ("ui/reservation/", "F5"),
    ("ui/inventory/", "F6"),
    ("ui/finance/", "F7"),
    ("ui/checkin/", "F8"),
    ("ui/cases/", "F9"), ("ui/site/", "F9"), ("ui/wizard/", "F9"), ("ui/members/", "F9"),
    ("ui/invite/", "F9"), ("ui/property/", "F9"),
]

def phase_of(rel):
    for prefix, phase in RULES:
        if rel.startswith(prefix):
            return phase
    return None

# File già portati (anche solo "scritto", mai compilato). Chiave: percorso relativo main.
DONE = {
    "data/model/Property.kt": ("Core/Models/Property.swift", "scritto"),
    "data/model/PropertyRole.kt": ("Core/Models/Property.swift", "scritto"),
    "data/model/PropertyPermission.kt": ("Core/Models/Property.swift", "scritto"),
    "data/model/Reservation.kt": ("Core/Models/Reservation.swift", "scritto"),
    "data/model/Expense.kt": ("Core/Models/OtherModels.swift", "scritto"),
    "data/model/RecurringExpense.kt": ("Core/Models/OtherModels.swift", "scritto"),
    "data/model/InventoryItem.kt": ("Core/Models/OtherModels.swift", "scritto"),
    "data/model/GuestRecord.kt": ("Core/Models/OtherModels.swift", "scritto"),
    "data/model/User.kt": ("Core/Models/OtherModels.swift", "scritto"),
    "data/access/AccessScope.kt": ("Core/Access/AccessScope.swift", "scritto+test"),
    "ui/main/AccessState.kt": ("Features/Main/MainViewModel.swift", "scritto+test"),
    "ui/main/MainTabs.kt": ("Features/Main/MainTab.swift", "scritto+test"),
    "ui/main/MainGate.kt": ("Features/Main/MainGateView.swift", "parziale"),
    "ui/login/LoginScreen.kt": ("Features/Login/LoginView.swift", "parziale (solo email)"),
    "data/repository/AuthRepository.kt": ("Core/Services/AuthService.swift", "parziale (solo email)"),
    "data/repository/DatabaseRepository.kt": ("Core/Services/FirestoreService.swift", "parziale (letture)"),
}
DONE_TESTS = {
    "data/access/AccessScopeTest.kt": ("SiciliaHostTests/AccessScopeTests.swift", "scritto"),
    "data/access/SuperAdminTest.kt": ("SiciliaHostTests/AccessScopeTests.swift", "scritto"),
    "ui/main/AccessStateTest.kt": ("SiciliaHostTests/AccessScopeTests.swift", "scritto"),
    "ui/main/MainTabsTest.kt": ("SiciliaHostTests/AccessScopeTests.swift", "scritto"),
}

PHASE_TITLES = {
    "F1": "Livello dati completo", "F2": "Logica pura e utilità", "F3": "Accesso, shell, stile e navigazione",
    "F4": "Home", "F5": "Agenda, prenotazioni e prezzi", "F6": "Scorte", "F7": "Finanze", "F8": "Check-in Alloggiati",
    "F9": "Case, sito, posizione, membri e inviti", "F10": "Sfondo, notifiche e sincronizzazioni",
    "F11": "Rifinitura e rilascio",
}

if os.path.exists(OUT) and "--force" not in sys.argv:
    print("INVENTARIO.md esiste già: rigenerarlo cancella gli stati. Usa --force solo per ricostruirlo da zero."); sys.exit(2)
rows, missing = [], []
for kind, sub in (("main", "main"), ("test", "test")):
    base = os.path.join(ROOT, sub, *BASE.rstrip("/").split("/"))
    for dp, _, files in os.walk(base):
        for f in files:
            if not f.endswith(".kt"):
                continue
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, base).replace(os.sep, "/")
            phase = phase_of(rel)
            if phase is None:
                missing.append((kind, rel)); continue
            lines = sum(1 for _ in open(full, encoding="utf-8", errors="ignore"))
            table = DONE if kind == "main" else DONE_TESTS
            target, status = table.get(rel, ("", "—"))
            rows.append((phase, kind, rel, lines, target, status))

if missing:
    print("FILE SENZA FASE:", missing); sys.exit(1)

# Risorse e voci non-Kotlin
EXTRA = [
    ("F11", "res", "drawable/logo_transparent.png, ic_launcher_*, mipmap-*", "Icona app (AppIcon) e logo", "—"),
    ("F11", "res", "drawable/ic_map_pin.xml, ic_map_eye.xml, ic_map_area_handle_bg.xml", "Marcatori mappa (usati da F9)", "—"),
    ("F11", "res", "values/strings.xml, themes.xml", "Testi e tema: Localizable / asset catalog", "—"),
    ("F11", "res", "xml/file_provider_paths.xml", "Condivisione file (ricevuta Alloggiati, ecc.): ShareLink / UIActivityViewController", "—"),
    ("F11", "res", "xml/backup_rules.xml, data_extraction_rules.xml", "Niente da portare (backup iOS gestito dal sistema)", "n/a"),
    ("F10", "manifest", "POST_NOTIFICATIONS, FirebaseMessagingService", "Notifiche push (APNs + FCM)", "—"),
    ("F8", "manifest", "CAMERA", "NSCameraUsageDescription (già in project.yml)", "scritto"),
]

rows.sort(key=lambda r: (int(r[0][1:]), r[1] != "main", r[2]))
with open(OUT, "w", encoding="utf-8", newline="\n") as o:
    o.write("# Inventario Android → iOS (generato)\n\n")
    o.write("Ogni file Kotlin dell'app Android (sorgenti e test) con la fase che lo porta. **Nessun file è fuori dal piano**: ")
    o.write("lo script di generazione fallisce se un file non ha fase. Aggiorna le colonne *iOS* e *Stato* man mano che porti; ")
    o.write("la fase F11 chiude solo se non resta nessuna riga con stato `—` (le uniche eccezioni ammesse sono `n/a` con motivo scritto qui).\n\n")
    o.write("Stati: `—` da fare · `scritto` scritto ma mai compilato · `compilato` · `provato` (simulatore/dispositivo) · `n/a` non serve su iOS (motivo in nota).\n\n")
    o.write(f"Totale: {len(rows)} file Kotlin ({sum(1 for r in rows if r[1]=='main')} sorgenti, {sum(1 for r in rows if r[1]=='test')} test).\n")
    cur = None
    for phase, kind, rel, lines, target, status in rows:
        if phase != cur:
            cur = phase
            o.write(f"\n## {phase} — {PHASE_TITLES[phase]}\n\n| Android | Righe | iOS | Stato |\n|---|---|---|---|\n")
        tag = "" if kind == "main" else "🧪 "
        o.write(f"| {tag}`{rel}` | {lines} | {target and '`'+target+'`'} | {status} |\n")
    o.write("\n## Risorse e manifest\n\n| Fase | Voce | Cosa | Stato |\n|---|---|---|---|\n")
    for phase, kind, name, what, status in EXTRA:
        o.write(f"| {phase} | `{name}` | {what} | {status} |\n")
print(len(rows), "file assegnati")
from collections import Counter
print(sorted(Counter(r[0] for r in rows).items(), key=lambda x: int(x[0][1:])))
