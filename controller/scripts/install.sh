#!/bin/bash
# Installa sull'iPad controller l'ultimo pacchetto in dist/ (via USB) e apre l'app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/scripts"
DEB="$(ls -t "$ROOT"/dist/it.simulafranz.controller_*_iphoneos-arm.deb 2>/dev/null | head -1)"
[ -f "$DEB" ] || { echo "ERRORE: nessun .deb in dist/ (scaricalo dalle Releases oppure: scripts/build.sh && scripts/package.sh)" >&2; exit 1; }
"$S/ssh.sh" true || { echo "ERRORE: l'iPad non risponde. È collegato e sbloccato? Hai installato la chiave con scripts/installa-chiave.sh?" >&2; exit 1; }
"$S/ssh.sh" 'cat > /var/root/similfranz.deb' < "$DEB"
"$S/ssh.sh" 'killall SimilFranz_Controller 2>/dev/null; dpkg -i /var/root/similfranz.deb >/dev/null && rm -f /var/root/similfranz.deb && dpkg -s it.simulafranz.controller | grep -E "^(Status|Version)"; cd /; su mobile -c "uiopen simulafranz-controller://" 2>/dev/null; true'
echo "OK: installato $(basename "$DEB")"
