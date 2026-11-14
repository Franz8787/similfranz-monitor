#!/bin/bash
# Comando come root sull'iPad controller via USB (iproxy + chiave SSH).
# Uso: scripts/ssh.sh 'comando'        (senza argomenti: shell interattiva)
# Con più iPad collegati: SIMILFRANZ_UDID=<udid> (lo leggi con idevice_id -l)
PORT="${SIMILFRANZ_PORT:-2226}"; KEY="${SIMILFRANZ_KEY:-$HOME/.ssh/similfranz_ipad}"
UDID_OPT=(); [ -n "${SIMILFRANZ_UDID:-}" ] && UDID_OPT=(-u "$SIMILFRANZ_UDID")
pgrep -f "iproxy $PORT" >/dev/null || { iproxy "$PORT" 22 "${UDID_OPT[@]}" >/dev/null 2>&1 & sleep 1; }
exec ssh -p "$PORT" -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile="$HOME/.ssh/known_hosts_similfranz" \
  -o StrictHostKeyChecking=accept-new -o HostKeyAlgorithms=+ssh-rsa -o ConnectTimeout=20 root@127.0.0.1 "$@"
