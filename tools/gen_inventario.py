#!/usr/bin/env python3
"""Inventario Android -> iOS (docs/INVENTARIO.md).

  python tools/gen_inventario.py --check [--android ../Androidapp]
      Verifica (da usare a ogni fine fase e nell'audit finale di F11):
        * ogni file .kt dell'app Android (sorgenti e test) compare nell'inventario;
        * elenca le righe ancora `—` o `parziale` (la fase F11 chiude solo se non ne resta nessuna).
      Esce con codice 1 se manca un file; 2 se restano righe aperte (con --strict).

  python tools/gen_inventario.py --generate [--android ../Androidapp] [--force]
      Ricostruisce l'inventario da zero (CANCELLA stati e percorsi iOS: senza --force rifiuta se esiste già).
      Fallisce se un file Android non ha una fase assegnata nelle RULES.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "INVENTARIO.md")
PKG = ["java", "com", "example", "casevacanzeapp"]

# (prefisso relativo al package, fase). Il primo che combacia vince.
RULES = [
    ("data/repository/Assistant", "F13"),
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
    ("ui/messages/", "F12"),
    ("ui/assistant/", "F13"),
]

PHASE_TITLES = {
    "F1": "Livello dati completo", "F2": "Logica pura e utilità", "F3": "Accesso, shell, stile e navigazione",
    "F4": "Home", "F5": "Agenda, prenotazioni e prezzi", "F6": "Scorte", "F7": "Finanze", "F8": "Check-in Alloggiati",
    "F9": "Case, sito, posizione, membri e inviti", "F10": "Sfondo, notifiche e sincronizzazioni",
    "F11": "Rifinitura e rilascio", "F12": "Messaggi degli ospiti", "F13": "Assistente Cactus",
}

ROW = re.compile(r"^\| (🧪 )?`([^`]+)` \| (\d+) \|[^|]*\|\s*([^|]*?)\s*\|$")


def arg(name, default=None):
    if name in sys.argv:
        i = sys.argv.index(name)
        return sys.argv[i + 1] if i + 1 < len(sys.argv) else default
    return default


def android_files(android_root):
    """Ritorna [(kind, rel, righe)] per tutti i .kt di main e test."""
    found = []
    for kind in ("main", "test"):
        base = os.path.join(android_root, "app", "src", kind, *PKG)
        if not os.path.isdir(base):
            sys.exit(f"Cartella Android non trovata: {base} (usa --android <percorso della repo Androidapp>)")
        for dp, _, files in os.walk(base):
            for f in files:
                if f.endswith(".kt"):
                    full = os.path.join(dp, f)
                    rel = os.path.relpath(full, base).replace(os.sep, "/")
                    with open(full, encoding="utf-8", errors="ignore") as fh:
                        found.append((kind, rel, sum(1 for _ in fh)))
    return found


def phase_of(rel):
    for prefix, phase in RULES:
        if rel.startswith(prefix):
            return phase
    return None


def check(android_root):
    files = android_files(android_root)
    rows, open_rows = {}, []
    with open(OUT, encoding="utf-8") as fh:
        for ln in fh:
            m = ROW.match(ln.rstrip("\n"))
            if m:
                key = (("test" if m.group(1) else "main"), m.group(2))
                rows[key] = m.group(4)
                if m.group(4) == "—" or m.group(4).startswith("parziale"):
                    open_rows.append((key, m.group(4)))
    missing = [(k, r) for k, r, _ in files if (k, r) not in rows]
    stale = [k for k in rows if k not in {(a, b) for a, b, _ in files}]
    print(f"File Android: {len(files)} · righe nell'inventario: {len(rows)}")
    if missing:
        print("\nFILE ANDROID NON IN INVENTARIO (aggiungili a mano nella fase giusta):")
        for k, r in missing:
            print(f"  [{k}] {r}  -> fase {phase_of(r) or '??'}")
    if stale:
        print("\nRighe dell'inventario senza file Android corrispondente (file rimosso/rinominato?):")
        for k in stale:
            print(f"  {k}")
    print(f"\nRighe ancora aperte (— o parziale): {len(open_rows)}")
    by_phase = {}
    for (kind, rel), st in open_rows:
        by_phase.setdefault(phase_of(rel) or "??", []).append((rel, st))
    for phase in sorted(by_phase, key=lambda p: int(p[1:]) if p[1:].isdigit() else 99):
        print(f"  {phase}: {len(by_phase[phase])}")
    if missing:
        sys.exit(1)
    if open_rows and "--strict" in sys.argv:
        sys.exit(2)


def generate(android_root):
    if os.path.exists(OUT) and "--force" not in sys.argv:
        sys.exit("INVENTARIO.md esiste già: rigenerarlo cancella gli stati. Usa --force solo per ricostruirlo da zero.")
    rows, unassigned = [], []
    for kind, rel, lines in android_files(android_root):
        phase = phase_of(rel)
        if phase is None:
            unassigned.append((kind, rel))
        else:
            rows.append((phase, kind, rel, lines))
    if unassigned:
        sys.exit(f"FILE SENZA FASE: {unassigned}")
    rows.sort(key=lambda r: (int(r[0][1:]), r[1] != "main", r[2]))
    with open(OUT, "w", encoding="utf-8", newline="\n") as o:
        o.write("# Inventario Android → iOS\n\n")
        cur = None
        for phase, kind, rel, lines in rows:
            if phase != cur:
                cur = phase
                o.write(f"\n## {phase} — {PHASE_TITLES[phase]}\n\n| Android | Righe | iOS | Stato |\n|---|---|---|---|\n")
            o.write(f"| {'' if kind == 'main' else '🧪 '}`{rel}` | {lines} |  | — |\n")
    print(len(rows), "file assegnati")


if __name__ == "__main__":
    root = os.path.abspath(arg("--android", os.path.join(REPO, "..", "Androidapp")))
    if "--check" in sys.argv:
        check(root)
    elif "--generate" in sys.argv:
        generate(root)
    else:
        print(__doc__)
