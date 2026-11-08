"""Build the content archive and apply the small iPad runtime integration.

Run from any directory: python Remake/tools/prepare_ipad.py --assets PATH
The assets path is the portable release's LocalAssets directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"


def prepare(assets: Path) -> None:
    manifest = json.loads((assets / "content-manifest.json").read_text(encoding="utf-8-sig"))
    failures = []
    for entry in manifest["files"]:
        if not entry.get("critical"):
            continue
        path = assets / "converted" / entry["path"]
        if not path.is_file() or path.stat().st_size != entry["bytes"]:
            failures.append(entry["path"])
        elif hashlib.sha256(path.read_bytes()).hexdigest().lower() != entry["sha256"].lower():
            failures.append(entry["path"])
    if failures:
        raise RuntimeError(f"Invalid critical content: {failures}")
    for index in range(12):
        if not (assets / "converted" / "levels" / f"m{index:03}" / "level.json").is_file():
            raise RuntimeError(f"Missing mission {index}")
    archive_path = GAME / "mobile-content.zip"
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(assets.rglob("*")):
            if path.is_file():
                archive.write(path, "LocalAssets/" + path.relative_to(assets).as_posix())
    print(f"Verified 12 missions; content archive {archive_path.stat().st_size / 2**20:.1f} MiB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    prepare(parser.parse_args().assets.resolve())
