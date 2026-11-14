#!/bin/bash
# Compila SimulaFranz_Monitor per iPad (armv7, iOS >= 9.0) senza Xcode:
# Command Line Tools (clang + ld) + iPhoneOS9.3.sdk (theos/sdks, patch: scripts/setup-sdk.sh) + ldid.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SIMLAB_SDK:-$ROOT/../sdk/theos-sdks/iPhoneOS9.3.sdk}"
BUILD="$ROOT/build"
APP="$BUILD/SimulaFranz_Monitor.app"
MIN_IOS=9.0

die() { echo "ERRORE: $*" >&2; exit 1; }
[ -d "$SDK" ] || die "SDK non trovato in $SDK — eseguire scripts/setup-sdk.sh"
grep -q SIMLAB-PATCH "$SDK/usr/lib/system/libsystem_c.tbd" || die "SDK non patchato — eseguire scripts/setup-sdk.sh"
command -v xcrun >/dev/null || die "Command Line Tools assenti (xcode-select --install)"
command -v ldid >/dev/null || die "ldid assente (brew install ldid)"
for f in index.html style.css app.js body.svg; do [ -s "$ROOT/web-console/$f" ] || die "web-console/$f vuoto o mancante"; done

CFLAGS=(-target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc -Os -g0
        -Wall -Wno-unused-parameter -Werror=partial-availability -Werror=objc-method-access
        -Werror=incompatible-pointer-types -Werror=implicit-function-declaration -I"$ROOT/src")
FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore
            -framework AVFoundation -framework AudioToolbox -framework CoreFoundation
            -framework MultipeerConnectivity -framework CoreImage -lz)

# SF_PUBLIC=1 scripts/build.sh -> versione PUBBLICA: solo i layout originali di similFranz (ICU, extraH, DAE).
# Le repliche di dispositivi in commercio non vengono compilate né collegate, e i loro nomi non entrano nel binario.
if [ "${SF_PUBLIC:-1}" = "1" ]; then CFLAGS+=(-DSF_PUBLIC=1); echo "== versione PUBBLICA (senza i layout dei dispositivi in commercio)"; fi

rm -rf "$BUILD"; mkdir -p "$BUILD/obj" "$APP"
echo "== compilazione ($(xcrun clang --version | head -1))"
for f in "$ROOT"/src/*.m; do
  echo "   $(basename "$f")"
  xcrun clang "${CFLAGS[@]}" -c "$f" -o "$BUILD/obj/$(basename "${f%.m}").o"
done
echo "== link"
# l'avviso "linking in .tbd built for iOS Simulator" è dovuto al formato tbd v1 dello SDK 9.3 ed è innocuo
xcrun clang -target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc "${FRAMEWORKS[@]}" \
  "$BUILD"/obj/*.o -o "$APP/SimulaFranz_Monitor" 2>&1 | grep -v "built for iOS Simulator" || true
[ -f "$APP/SimulaFranz_Monitor" ] || die "link fallito"

echo "== aiutante di installazione (aggiornamenti dal telefono)"
xcrun clang -target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -Os -Wall -DPKG='"it.simulafranz.monitor"' \
  -DDEB='"/var/mobile/Library/Caches/similfranz-aggiornamento-monitor.deb"' -DLOG='"/var/mobile/Library/Caches/similfranz-aggiornamento-monitor.log"' \
  -DPROC='"SimulaFranz_Monitor"' -DSCHEME='"simulafranz-monitor://"' "$ROOT/helper/aggiorna.c" -o "$BUILD/similfranz-monitor-aggiorna" 2>&1 | grep -v "built for iOS Simulator" || true
ldid -S "$BUILD/similfranz-monitor-aggiorna"
echo "== bundle"
plutil -convert binary1 -o "$APP/Info.plist" "$ROOT/assets/Info.plist"
# la versione dell'app viene SOLO da "control" (la stessa che vede dpkg): così non possono divergere
APP_VERSION="$(sed -n 's/^Version: //p' "$ROOT/control")"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Info.plist"
# Repository delle versioni: quello da cui si compila (GitHub Actions: GITHUB_REPOSITORY; in locale: il remote "origin").
# Edizione: "privata" se l'app contiene layout aggiuntivi che il pacchetto pubblico non ha. Un monitor in edizione privata
# segue le versioni pubblicate (avviso + controller e Pocket da GitHub) ma rifiuta il pacchetto PUBBLICO del monitor,
# che gli toglierebbe quei layout: il monitor si aggiorna solo con un pacchetto della sua stessa edizione.
EDITION=pubblica
REPO_SLUG="${SF_UPDATE_REPO:-${GITHUB_REPOSITORY:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' || true)}}"
[ "$EDITION" = privata ] && [ -z "$REPO_SLUG" ] && REPO_SLUG="Franz8787/similfranz-monitor"
plutil -replace SFEdition -string "$EDITION" "$APP/Info.plist"
[ -n "$REPO_SLUG" ] && plutil -replace SFUpdateRepo -string "$REPO_SLUG" "$APP/Info.plist" && echo "   edizione $EDITION, versioni da: $REPO_SLUG"
printf 'APPL????' > "$APP/PkgInfo"
cp "$ROOT"/assets/*.png "$APP/"
cp -R "$ROOT/assets/Settings.bundle" "$APP/"
mkdir -p "$APP/web-console" && cp "$ROOT"/web-console/{index.html,style.css,app.js,body.svg} "$APP/web-console/"

echo "== firma ldid (fakesign per dispositivo con jailbreak, con gli entitlement del Wi-Fi in app)"
ldid -S"$ROOT/assets/entitlements.xml" "$APP/SimulaFranz_Monitor"

echo "== verifica"
file "$APP/SimulaFranz_Monitor"
lipo -info "$APP/SimulaFranz_Monitor"
otool -l "$APP/SimulaFranz_Monitor" | awk '/LC_VERSION_MIN_IPHONEOS/{f=1} f&&/version/{print "   iOS minimo:", $2; exit}'
lipo -info "$APP/SimulaFranz_Monitor" | grep -q "armv7" || die "binario non armv7"
lipo -info "$APP/SimulaFranz_Monitor" | grep -q "arm64" && die "binario contiene arm64 inatteso"
if [ "${SF_PUBLIC:-1}" = "1" ]; then
  echo "   versione pubblica: nessun nome commerciale nel binario"
fi
echo "OK: $APP"
