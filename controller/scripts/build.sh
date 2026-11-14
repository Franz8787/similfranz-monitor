#!/bin/bash
# Compila similFranz Controller per iPad (armv7, iOS >= 9.0) senza Xcode:
# Command Line Tools (clang + ld) + iPhoneOS9.3.sdk patchato (condiviso con il Monitor) + ldid.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SIMLAB_SDK:-$ROOT/../sdk/theos-sdks/iPhoneOS9.3.sdk}"
BUILD="$ROOT/build"; APP="$BUILD/SimilFranz_Controller.app"; MIN_IOS=9.0
die() { echo "ERRORE: $*" >&2; exit 1; }
[ -d "$SDK" ] || die "SDK non trovato in $SDK"
command -v ldid >/dev/null || die "ldid assente (brew install ldid)"
[ -f "$ROOT/assets/AppIcon76x76.png" ] || "$ROOT/scripts/make-assets.sh"
CFLAGS=(-target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc -Os -g0
        -Wall -Wno-unused-parameter -Werror=partial-availability -Werror=objc-method-access
        -Werror=incompatible-pointer-types -Werror=implicit-function-declaration -I"$ROOT/src")
FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore
            -framework AVFoundation -framework AudioToolbox -framework CoreFoundation -framework MultipeerConnectivity -lz)
rm -rf "$BUILD/obj" "$APP"; mkdir -p "$BUILD/obj" "$APP"
echo "== compilazione ($(xcrun clang --version | head -1))"
for f in "$ROOT"/src/*.m; do echo "   $(basename "$f")"; xcrun clang "${CFLAGS[@]}" -c "$f" -o "$BUILD/obj/$(basename "${f%.m}").o"; done
echo "== link"
xcrun clang -target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc "${FRAMEWORKS[@]}" "$BUILD"/obj/*.o -o "$APP/SimilFranz_Controller" 2>&1 | grep -v "built for iOS Simulator" || true
[ -f "$APP/SimilFranz_Controller" ] || die "link fallito"
echo "== aiutante di installazione (aggiornamenti dal monitor)"
xcrun clang -target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -Os -Wall -DPKG='"it.simulafranz.controller"' \
  -DDEB='"/var/mobile/Library/Caches/similfranz-aggiornamento-controller.deb"' -DLOG='"/var/mobile/Library/Caches/similfranz-aggiornamento-controller.log"' \
  -DPROC='"SimilFranz_Controller"' -DSCHEME='"simulafranz-controller://"' "$ROOT/helper/aggiorna.c" -o "$BUILD/similfranz-controller-aggiorna" 2>&1 | grep -v "built for iOS Simulator" || true
ldid -S "$BUILD/similfranz-controller-aggiorna"
echo "== bundle"
plutil -convert binary1 -o "$APP/Info.plist" "$ROOT/assets/Info.plist"
# la versione dell'app viene SOLO da "control" (la stessa che vede dpkg): così non possono divergere
APP_VERSION="$(sed -n 's/^Version: //p' "$ROOT/control")"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"
cp "$ROOT"/assets/*.png "$APP/"
echo "== firma ldid"
ldid -S "$APP/SimilFranz_Controller"
lipo -info "$APP/SimilFranz_Controller" | grep -q armv7 || die "binario non armv7"
echo "OK: $APP"
