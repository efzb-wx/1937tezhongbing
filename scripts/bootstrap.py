"""Prepare a reproducible macOS build without publishing game assets in Git."""
import os
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile


def extract_portable_assets(archive_path, destination):
    """Locate the asset root from ZIP entries, not platform glob semantics."""
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive_path) as archive:
        manifests = [name for name in archive.namelist()
                     if name.replace("\\", "/").endswith("LocalAssets/content-manifest.json")]
        if len(manifests) != 1:
            raise RuntimeError(f"Expected one content manifest in ZIP, found {manifests!r}")
        for entry in archive.infolist():
            normalized = entry.filename.replace("\\", "/")
            target = (destination / normalized).resolve()
            if not target.is_relative_to(destination):
                raise RuntimeError(f"Unsafe portable archive entry: {entry.filename}")
            # The Windows-produced release has an explicit sprite-frames/
            # entry with no external directory attributes. Preserve the ZIP
            # trailing-slash directory convention regardless of host/runtime.
            if normalized.endswith("/") or entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
        manifest = destination / manifests[0].replace("\\", "/")
    if not manifest.is_file():
        raise RuntimeError(f"Manifest missing after extraction: {manifest}")
    print("Located portable assets:", manifest.parent, flush=True)
    return manifest.parent

COMMIT = "7ddb75fa4b3425d6f1f5327a11dff728e4fbf56c"
GODOT = "4.7.2"
ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)


def download(url, path):
    print("Downloading", url, flush=True)
    with urllib.request.urlopen(url, timeout=180) as response, open(path, "wb") as target:
        shutil.copyfileobj(response, target)


subprocess.run(["git", "clone", "--filter=blob:none", "--no-checkout", "https://github.com/bigsinger/1937tezhongbing.git", "source"], check=True, env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"})
subprocess.run(["git", "-C", "source", "sparse-checkout", "set", "Remake"], check=True)
subprocess.run(["git", "-C", "source", "checkout", COMMIT], check=True, env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"})
shutil.copytree("port/Remake", "source/Remake", dirs_exist_ok=True)
download("https://github.com/bigsinger/1937tezhongbing/releases/download/archive-2026.08.10/1937-Remake-portable.zip", "portable.zip")
download("https://github.com/bigsinger/1937tezhongbing/releases/download/archive-2026.08.10/1937-Remake-portable.zip.sha256", "portable.zip.sha256")
expected_hash = Path("portable.zip.sha256").read_text(encoding="utf-8-sig").split()[0].lower()
if hashlib.sha256(Path("portable.zip").read_bytes()).hexdigest() != expected_hash:
    raise RuntimeError("Published portable release checksum mismatch")
assets = extract_portable_assets("portable.zip", "portable")
subprocess.run(["python3", "source/Remake/tools/integrate_ipad.py"], check=True)
subprocess.run(["python3", "source/Remake/tools/prepare_ipad.py", "--assets", str(assets)], check=True)
base = f"https://github.com/godotengine/godot/releases/download/{GODOT}-stable/"
download(base + f"Godot_v{GODOT}-stable_macos.universal.zip", "engine.zip")
Path("engine").mkdir(exist_ok=True)
subprocess.run(["ditto", "-xk", "engine.zip", "engine"], check=True)
executable = Path("engine/Godot.app/Contents/MacOS/Godot")
executable.chmod(0o755)
download(base + f"Godot_v{GODOT}-stable_export_templates.tpz", "templates.tpz")
templates = Path.home() / "Library/Application Support/Godot/export_templates" / f"{GODOT}.stable"
templates.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile("templates.tpz") as archive:
    with archive.open("templates/ios.zip") as src, (templates / "ios.zip").open("wb") as dst:
        shutil.copyfileobj(src, dst)
print("Cloud build dependencies ready", flush=True)
