#!/bin/bash
# Libera spazio sull'iPad mini 1 (partizione di sistema quasi piena): elimina le app di serie che non servono e
# alcune risorse inutilizzate (lingue diverse da italiano e inglese, voci, dizionari, ramdisk di aggiornamento).
# CANCELLA soltanto: nessun processo o servizio di sistema viene disattivato. Per riavere i file serve un
# ripristino dal Finder. Restano: Impostazioni, Safari, Note, Cydia.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-all}"
"$HERE/ssh.sh" "MODE=$MODE bash -s" <<'REMOTE'
MODE=$MODE
ST=/var/SimulaFranz_stash
DD=/var/root/disabled-daemons
L=/System/Library/LinguisticData
LD=/System/Library/LaunchDaemons

# ---------- 1. app di serie da eliminare ----------
APPS="AppStore Camera Contacts FaceTime FindMyFriends FindMyiPhone Maps MobileCal MobileMail
MobileSMS MobileSlideShow MobileStore MobileTimer Music News Podcasts Reminders Tips Videos
iBooks iCloudDriveApp DemoApp"
APPS_SPACE="Game Center|Photo Booth|Feedback Assistant iOS"

# ---------- 2. risorse da spostare in /var ----------
ITEMS="
/System/Library/PreinstalledAssets/com_apple_MobileAsset_VoiceServices_CustomVoice.cpio
/System/Library/PreinstalledAssets/com_apple_MobileAsset_MobileAccessoryUpdate_haywire.cpio
/System/Library/PreinstalledAssets/com_apple_MobileAsset_VoiceTriggerAssets.cpio
/usr/standalone/update/ramdisk
/usr/share/mecabra
/usr/share/tokenizer/ja
/usr/share/tokenizer/ko
/usr/share/tokenizer/zh
/usr/include
$L/zh
"
for b in $L/RequiredAssets_*.bundle; do
  case "$b" in *_it.bundle|*_en.bundle) ;; *) ITEMS="$ITEMS $b";; esac
done


restore_stash() {
  for p in $ITEMS; do
    dst="$ST$p"
    if [ -L "$p" ] && [ -e "$dst" ]; then rm "$p"; mv "$dst" "$p"; echo "ripristinato: $p"; fi
  done
}
restore_daemons() {
  for f in $DD/*.plist; do [ -e "$f" ] && mv "$f" $LD/ && echo "riattivato: $(basename $f)"; done
}
case "$MODE" in
  --restore-stash)   restore_stash;   exit 0;;
  --restore-daemons) restore_daemons; exit 0;;
esac

echo "=== 1. app ==="
for a in $APPS; do
  if [ -d "/Applications/$a.app" ]; then rm -rf "/Applications/$a.app" && echo "eliminata: $a"; fi
done
IFS='|'; for a in $APPS_SPACE; do
  if [ -d "/Applications/$a.app" ]; then rm -rf "/Applications/$a.app" && echo "eliminata: $a"; fi
done; unset IFS
rm -rf /var/mobile/Library/Caches/com.apple.mobile.installation.plist 2>/dev/null

echo "=== 2. spazio ==="
# CANCELLAZIONE diretta (niente symlink verso /var: un'inizializzazione da Impostazioni
# svuota /var e lascerebbe link rotti che bloccano l'avvio — incidente 08/11/2026).
# Per riaverli serve un ripristino da Finder.
for p in $ITEMS; do
  [ -L "$p" ] && { echo "ATTENZIONE link rimasto: $p"; continue; }
  [ -e "$p" ] || continue
  rm -rf "$p" && echo "cancellato: $p"
done

echo "=== 3. OTA (solo file) ==="
for d in /var/MobileSoftwareUpdate/* /var/mobile/Library/Assets/com_apple_MobileAsset_SoftwareUpdate \
         /var/mobile/Library/Assets/com_apple_MobileAsset_SoftwareUpdateDocumentation; do
  [ -e "$d" ] && rm -rf "$d" && echo "cancellato: $d"
done
rm -rf /var/mobile/Library/Logs/CrashReporter/* /var/logs/* 2>/dev/null

echo "=== fine ==="
su mobile -c uicache
df -h / /private/var
REMOTE
