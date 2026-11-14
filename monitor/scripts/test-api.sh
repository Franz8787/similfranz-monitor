#!/bin/bash
# Test HTTP reali dell API SimulaFranz_Monitor con curl.
# Uso:
#   scripts/test-api.sh                         -> avvia il server di riferimento su Mac (solo test)
#   scripts/test-api.sh http://192.168.4.X:8080 -> prova l'app VERA sull'iPad (chiede il PIN)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-}"; PIN="${SF_PIN:-}"; PID=""
if [ -z "$BASE" ]; then
  "$ROOT/scripts/test-mac.sh" >/dev/null || { echo "build test fallita"; exit 1; }
  PIN=654321; BASE=http://127.0.0.1:18090
  "$ROOT/build/mac/mac-reference-server" 18090 $PIN "$ROOT/web-console" >/dev/null & PID=$!
  trap 'kill $PID 2>/dev/null' EXIT; sleep 0.5
  echo "Target: server di riferimento su Mac (NON è l'iPad)"
else
  [ -n "$PIN" ] || { read -rsp "PIN mostrato sull'iPad: " PIN; echo; }
  echo "Target: $BASE"
fi
pass=0; fail=0
t() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (atteso $2, ottenuto $3)"; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$@"; }
H=(-H "X-SimulaFranz-Token: $PIN"); J=(-H "Content-Type: application/json")

t "GET /api/v1/health senza auth"          200 "$(code "$BASE/api/v1/health")"
t "GET / console Web"                      200 "$(code "$BASE/")"
t "GET /app.js"                            200 "$(code "$BASE/app.js")"
t "GET /api/v1/state senza token"          401 "$(code "$BASE/api/v1/state")"
t "GET /api/v1/state con token"            200 "$(code "${H[@]}" "$BASE/api/v1/state")"
t "POST FC 80->120"                        200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_heart_rate","value":120}' "$BASE/api/v1/command")"
HR=$(curl -s "${H[@]}" "$BASE/api/v1/state" | python3 -c 'import json,sys;print(json.load(sys.stdin)["state"]["heart_rate_bpm"])')
t "stato riflette FC 120"                  120 "$HR"
t "POST ritmo VF"                          200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_rhythm","value":"vf"}' "$BASE/api/v1/command")"
PULSE=$(curl -s "${H[@]}" "$BASE/api/v1/state" | python3 -c 'import json,sys;s=json.load(sys.stdin)["state"];print(s["pulse_present"], s["spo2_displayed"])')
t "VF: senza polso, SpO2 non mostrata"     "False None" "$PULSE"
t "POST sonda SpO2 scollegata"             200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_sensor","value":{"sensor":"spo2","connected":false}}' "$BASE/api/v1/command")"
t "POST ART collegata"                     200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_sensor","value":{"sensor":"art","connected":true}}' "$BASE/api/v1/command")"
t "POST limiti di allarme"                 200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_alarm_limits","value":{"hr_low":45,"hr_high":130}}' "$BASE/api/v1/command")"
t "POST limiti incoerenti"                 400 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_alarm_limits","value":{"hr_low":140}}' "$BASE/api/v1/command")"
t "POST ripristino limiti"                 200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"reset_alarm_limits"}' "$BASE/api/v1/command")"
t "POST reset_scenario"                    200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"reset_scenario"}' "$BASE/api/v1/command")"
t "POST defib manuale"                     200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"defib_mode","value":"manual"}' "$BASE/api/v1/command")"
t "POST config defib non valida"           400 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_defib_config","value":{"capture_threshold_ma":999}}' "$BASE/api/v1/command")"
t "POST temperatura 38.5"                  200 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_temperature","value":38.5}' "$BASE/api/v1/command")"
DEF=$(curl -s "${H[@]}" "$BASE/api/v1/state" | python3 -c 'import json,sys;s=json.load(sys.stdin)["state"];print(s["defib"]["mode"], s["temperature_c"])')
t "stato: defib manuale, 38.5 °C"          "manual 38.5" "$DEF"
t "POST NIBP start"                        200 "$(code "${H[@]}" -X POST "$BASE/api/v1/nibp/start")"
t "JSON malformato"                        400 "$(code "${H[@]}" "${J[@]}" -d '{oops' "$BASE/api/v1/command")"
t "valore fuori range"                     400 "$(code "${H[@]}" "${J[@]}" -d '{"command":"set_spo2","value":150}' "$BASE/api/v1/command")"
t "payload > 16 KB"                        413 "$(head -c 20000 /dev/zero | tr '\0' 'a' | CFFIXED_USER_HOME=/tmp curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "${J[@]}" --data-binary @- "$BASE/api/v1/command")"
t "path inesistente"                       404 "$(code "$BASE/etc/passwd")"
# client lento: invia mezza richiesta e tace -> il server chiude con 408 entro ~5 s
SLOW=$(python3 - "$BASE" <<'PY'
import socket, sys, urllib.parse
u = urllib.parse.urlparse(sys.argv[1]); s = socket.create_connection((u.hostname, u.port), timeout=10)
s.sendall(b"GET /api/v1/health HTTP/1.1\r\nHost: x\r\n"); print(s.recv(100).split(b" ")[1].decode())
PY
)
t "client lento -> timeout"                408 "$SLOW"
# 20 richieste in parallelo: il server deve restare in piedi
PIDS=(); for i in $(seq 1 20); do curl -s -o /dev/null --max-time 8 "$BASE/api/v1/health" & PIDS+=($!); done
wait "${PIDS[@]}"   # solo i curl, non il server di riferimento
t "server vivo dopo 20 richieste parallele" 200 "$(code "$BASE/api/v1/health")"
# forza bruta (ultimo, perché blocca l'IP per 30 s)
for i in 1 2 3 4 5; do code -H "X-SimulaFranz-Token: sbagliato" "$BASE/api/v1/state" >/dev/null; done
t "blocco dopo 5 PIN errati"               429 "$(code "${H[@]}" "$BASE/api/v1/state")"
echo; echo "Test HTTP superati: $pass   falliti: $fail"
[ $fail -eq 0 ]
