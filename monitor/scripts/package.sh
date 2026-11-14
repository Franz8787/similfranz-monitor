#!/bin/bash
# Crea il pacchetto rootful dist/it.simulafranz.monitor_<ver>_iphoneos-arm.deb
# (app in /Applications, proprietario root:wheel). Non richiede dpkg sul Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SimulaFranz_Monitor.app"
[ -x "$APP/SimulaFranz_Monitor" ] || { echo "ERRORE: eseguire prima scripts/build.sh" >&2; exit 1; }
mkdir -p "$ROOT/dist"
python3 - "$ROOT" <<'PY'
import io, os, sys, tarfile, time, gzip
root = sys.argv[1]
app = os.path.join(root, "build", "SimulaFranz_Monitor.app")
control = open(os.path.join(root, "control")).read().strip() + "\n"
fields = dict(l.split(": ", 1) for l in control.splitlines() if ": " in l)
# dimensione installata (KB) per Cydia
size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(app) for f in fs) // 1024 + 1
control += f"Installed-Size: {size}\n"
now = int(time.time())

def tar_gz(add):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        add(t)
    return gzip.compress(buf.getvalue(), 9, mtime=now)

def info(name, mode, size=0, isdir=False):
    ti = tarfile.TarInfo(name); ti.mode = mode; ti.size = size; ti.mtime = now
    ti.uid = ti.gid = 0; ti.uname = "root"; ti.gname = "wheel"
    if isdir: ti.type = tarfile.DIRTYPE
    return ti

POSTINST = """#!/bin/sh
# aggiorna la cache delle icone di SpringBoard (uicache va eseguito come mobile su iOS 9)
if [ -x /usr/bin/uicache ]; then su mobile -c /usr/bin/uicache || /usr/bin/uicache || true; fi
exit 0
"""
POSTRM = POSTINST

def add_control(t):
    for name, data, mode in [("./control", control, 0o644), ("./postinst", POSTINST, 0o755), ("./postrm", POSTRM, 0o755)]:
        b = data.encode(); t.addfile(info(name, mode, len(b)), io.BytesIO(b))

def add_data(t):
    for d in ["./", "./Applications/"]:
        t.addfile(info(d, 0o755, isdir=True))
    # aiutante di installazione: setuid root (installa SOLO il pacchetto del monitor, da un percorso fisso)
    helper = os.path.join(root, "build", "similfranz-monitor-aggiorna")
    for d in ["./usr/", "./usr/libexec/"]: t.addfile(info(d, 0o755, isdir=True))
    with open(helper, "rb") as fh: t.addfile(info("./usr/libexec/similfranz-monitor-aggiorna", 0o4755, os.path.getsize(helper)), fh)
    base = "./Applications/SimulaFranz_Monitor.app"
    for dirpath, dirs, files in os.walk(app):
        dirs.sort()
        rel = os.path.relpath(dirpath, app)
        dest = base if rel == "." else f"{base}/{rel}"
        t.addfile(info(dest + "/", 0o755, isdir=True))
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            mode = 0o755 if f == "SimulaFranz_Monitor" and rel == "." else 0o644
            with open(p, "rb") as fh:
                t.addfile(info(f"{dest}/{f}", mode, os.path.getsize(p)), fh)

members = [("debian-binary", b"2.0\n"), ("control.tar.gz", tar_gz(add_control)), ("data.tar.gz", tar_gz(add_data))]
out = io.BytesIO(); out.write(b"!<arch>\n")
for name, data in members:   # formato ar comune (nomi brevi, senza '/'), letto da dpkg e da ar BSD
    hdr = f"{name:<16}{now:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode()
    assert len(hdr) == 60
    out.write(hdr); out.write(data)
    if len(data) % 2: out.write(b"\n")
path = os.path.join(root, "dist", f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb")
open(path, "wb").write(out.getvalue())
print(path)
PY
