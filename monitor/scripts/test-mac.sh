#!/bin/bash
# Compila ed esegue su macOS i test di logica (modello, waveform, allarmi, API).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/build/mac"; mkdir -p "$OUT"
SRC=(SimulationState WaveformEngine AlarmManager APIController SFControl SFScenarioStore SFSessionLog LocalHTTPServer SFLog SFUpdate)
FILES=(); for s in "${SRC[@]}"; do FILES+=("$ROOT/src/$s.m"); done
xcrun clang -fobjc-arc -Wall -Wno-unused-parameter -I"$ROOT/src" -framework Foundation -lz \
  "${FILES[@]}" "$ROOT/tests/run-tests.m" -o "$OUT/run-tests"
xcrun clang -fobjc-arc -Wall -Wno-unused-parameter -I"$ROOT/src" -framework Foundation -lz \
  "${FILES[@]}" "$ROOT/tests/mac-reference-server.m" -o "$OUT/mac-reference-server"
# client di prova del collegamento diretto (per usarlo serve l'iPad vero: build/mac/mac-peer-client <PIN>)
xcrun clang -fobjc-arc -Wall -framework Foundation -framework MultipeerConnectivity \
  "$ROOT/tests/mac-peer-client.m" -o "$OUT/mac-peer-client"
# monitor di prova con collegamento diretto, per provare l'app controller senza l'iPad monitor
xcrun clang -fobjc-arc -Wall -Wno-unused-parameter -I"$ROOT/src" -framework Foundation -framework MultipeerConnectivity -lz \
  "${FILES[@]}" "$ROOT/src/SFPeerLink.m" "$ROOT/tests/mac-peer-server.m" -o "$OUT/mac-peer-server"
"$OUT/run-tests"
