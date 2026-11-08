#!/bin/bash
# Fotografa le anteprime dell'app (SiciliaHost/App/UIPreview.swift) nel simulatore, in chiaro e in scuro.
# Uso: tools/ci_screenshots.sh <percorso SiciliaHost.app> <UDID del simulatore> <cartella di uscita>
set -uo pipefail
APP="$1"; UDID="$2"; OUT="$3"
BUNDLE="com.siciliahost.cactushost"
SCREENS="login intro loading onboarding home arrivals agenda inventory finance tour profile failed terms gallery"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  for screen in $SCREENS; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -UIPreview "$screen" || echo "avvio fallito: $screen"
    sleep 6
    xcrun simctl io "$UDID" screenshot "$OUT/${screen}-${mode}.png" || echo "screenshot fallito: $screen"
  done
done
ls -la "$OUT"
