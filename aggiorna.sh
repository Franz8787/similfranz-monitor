#!/bin/bash
# Installa (o aggiorna) un'app similFranz all'ULTIMA VERSIONE PUBBLICATA su GitHub, senza compilare nulla.
# Uso:  ./aggiorna.sh monitor            (iPad del monitor collegato con il cavo)
#       ./aggiorna.sh controller         (secondo iPad, la regia)
#       ./aggiorna.sh pocket             (iPod touch 5)
#       ./aggiorna.sh monitor utente/repo   (le versioni di un altro repository, per esempio una copia del progetto)
# Con più dispositivi collegati: SIMILFRANZ_UDID=<udid> ./aggiorna.sh …   (l'UDID lo leggi con idevice_id -l)
# Serve per la PRIMA installazione: da lì in poi gli aggiornamenti arrivano dalla console web del monitor
# (pannello Monitor › Aggiornamento delle app) e il monitor li passa a controller e iPod.
# La prima volta su un dispositivo crea la chiave SSH (se manca) e chiede UNA volta la password di root.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "ERRORE: $*" >&2; exit 1; }
APP="${1:-}"; case "$APP" in monitor|controller|pocket) ;; *) die "uso: ./aggiorna.sh monitor|controller|pocket [utente/repository]";; esac
REPO="${2:-$(git -C "$HERE" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' || true)}"
[ -n "$REPO" ] || REPO="Franz8787/similfranz-monitor"
# strumenti e dispositivo: errori chiari prima di scaricare qualsiasi cosa
for t in iproxy idevice_id curl python3 ssh; do
  command -v "$t" >/dev/null || die "manca $t. Mac: brew install libimobiledevice   Linux: sudo apt install libimobiledevice-utils usbmuxd"
done
N="$(idevice_id -l 2>/dev/null | grep -c . || true)"
[ "$N" -gt 0 ] || die "nessun dispositivo collegato: collega il cavo, sblocca lo schermo e, se compare, tocca «Autorizza»"
[ "$N" -eq 1 ] || [ -n "${SIMILFRANZ_UDID:-}" ] || die "sono collegati $N dispositivi: lascia collegato solo quello da installare (oppure SIMILFRANZ_UDID=<udid>, da idevice_id -l)"
KEY="${SIMILFRANZ_KEY:-$HOME/.ssh/similfranz_ipad}"
[ -f "$KEY" ] || { mkdir -p "$HOME/.ssh"; ssh-keygen -q -t rsa -f "$KEY" -N "" && echo "== creata la chiave $KEY"; }
if ! "$HERE/$APP/scripts/ssh.sh" true 2>/dev/null; then
  echo "== prima volta su questo dispositivo: installo la chiave (ti chiedo la password di root, una volta sola)"
  "$HERE/$APP/scripts/installa-chiave.sh" || die "chiave non installata: password giusta? OpenSSH installato da Cydia? (docs/02-installazione.md)"
fi
echo "== ultima versione pubblicata su $REPO"
JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" || die "nessuna versione pubblicata su github.com/$REPO (o internet assente)"
read -r TAG URL < <(python3 -c 'import json,sys; r=json.load(sys.stdin); p="it.simulafranz."+sys.argv[1]+"_"; d=[a["browser_download_url"] for a in r.get("assets",[]) if a["name"].startswith(p) and a["name"].endswith(".deb")]; print(r["tag_name"], d[0] if d else "")' "$APP" <<<"$JSON")
[ -n "$URL" ] || die "la versione $TAG non contiene il pacchetto di $APP"
mkdir -p "$HERE/$APP/dist"; DEB="$HERE/$APP/dist/$(basename "$URL")"
echo "== scarico $(basename "$URL")"
curl -fsSL "$URL" -o "$DEB" || die "download non riuscito"
touch "$DEB"                                       # install.sh prende il .deb più recente in dist/
"$HERE/$APP/scripts/install.sh"
echo "OK: $APP aggiornato a $TAG"
