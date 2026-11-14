#!/bin/bash
# Installa sull'iPod (similFranz Pocket) l'ultimo pacchetto in dist/ (via USB) e apre l'app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/scripts"
DEB="$(ls -t "$ROOT"/dist/it.simulafranz.pocket_*_iphoneos-arm.deb 2>/dev/null | head -1)"
[ -f "$DEB" ] || { echo "ERRORE: nessun .deb in dist/ (scaricalo dalle Releases oppure: scripts/build.sh && scripts/package.sh)" >&2; exit 1; }
"$S/ssh.sh" true || { echo "ERRORE: l'iPod non risponde. È collegato e sbloccato? Hai installato la chiave con scripts/installa-chiave.sh?" >&2; exit 1; }
"$S/ssh.sh" 'cat > /var/root/similfranz.deb' < "$DEB"
"$S/ssh.sh" 'killall SimilFranz_Pocket 2>/dev/null; dpkg -i /var/root/similfranz.deb >/dev/null && rm -f /var/root/similfranz.deb && dpkg -s it.simulafranz.pocket | grep -E "^(Status|Version)"; cd /; su mobile -c "uiopen simulafranz-pocket://" 2>/dev/null; true'
echo "OK: installato $(basename "$DEB")"
