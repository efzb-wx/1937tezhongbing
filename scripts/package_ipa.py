"""Package only a real ARM64 iPad app produced by Xcode; never fake an IPA."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

products, output = map(Path, sys.argv[1:])
apps = list(products.glob("*.app"))
if len(apps) != 1:
    raise RuntimeError(f"Expected one compiled app, found {apps}")
app = apps[0]
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
binary = app / info["CFBundleExecutable"]
architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True)
if "arm64" not in architectures.split():
    raise RuntimeError("Application is not built for ARM64 devices")
if 2 not in info.get("UIDeviceFamily", []):
    raise RuntimeError("Application does not support iPad")
if not list(app.rglob("*.pck")):
    raise RuntimeError("Godot content PCK is missing")
output.mkdir(parents=True, exist_ok=True)
ipa = output / "1937-iPad-unsigned.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(app.rglob("*")):
        if path.is_file():
            archive.write(path, "Payload/" + app.name + "/" + path.relative_to(app).as_posix())
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
ipa.with_suffix(".ipa.sha256").write_text(f"{digest}  {ipa.name}\n")
print(f"Packaged real ARM64 iPad application: {ipa} ({ipa.stat().st_size / 2**20:.1f} MiB)")
