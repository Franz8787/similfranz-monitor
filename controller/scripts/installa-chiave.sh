#!/bin/bash
# UNA VOLTA SOLA per ogni dispositivo: copia la chiave SSH del computer sul dispositivo, così gli script non chiedono più password.
# La password di root la scrivi tu (sul Mac in una finestra, su Linux nel terminale): non resta scritta da nessuna parte.
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${SIMILFRANZ_PORT:-2226}"; KEY="${SIMILFRANZ_KEY:-$HOME/.ssh/similfranz_ipad}"
[ -f "$KEY.pub" ] || { echo "Manca la chiave: creala con  ssh-keygen -t rsa -f $KEY -N ''"; exit 1; }
UDID_OPT=(); [ -n "${SIMILFRANZ_UDID:-}" ] && UDID_OPT=(-u "$SIMILFRANZ_UDID")
pgrep -f "iproxy $PORT" >/dev/null || { iproxy "$PORT" 22 "${UDID_OPT[@]}" >/dev/null 2>&1 & sleep 1; }
SSH_OPT=(-p "$PORT" -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=2 -o UserKnownHostsFile="$HOME/.ssh/known_hosts_similfranz"
         -o StrictHostKeyChecking=accept-new -o HostKeyAlgorithms=+ssh-rsa -o ConnectTimeout=90 root@127.0.0.1)
if command -v osascript >/dev/null; then
  # Mac: la password si scrive in una finestra di macOS
  ASK="$(mktemp)"; trap 'rm -f "$ASK"' EXIT
  printf '%s\n' '#!/bin/bash' "exec osascript -e 'text returned of (display dialog \"Password di root del dispositivo:\" default answer \"\" with hidden answer with title \"similFranz\" buttons {\"Annulla\", \"OK\"} default button \"OK\")'" > "$ASK"
  chmod +x "$ASK"; export SSH_ASKPASS="$ASK" SSH_ASKPASS_REQUIRE=force DISPLAY=:0
else
  echo "Scrivi qui sotto la password di root del dispositivo (non compare mentre scrivi)."
fi
cat "$KEY.pub" | ssh "${SSH_OPT[@]}" \
  'mkdir -p /var/root/.ssh && cat >> /var/root/.ssh/authorized_keys && chmod 700 /var/root/.ssh && chmod 600 /var/root/.ssh/authorized_keys && echo "OK: chiave installata"'
