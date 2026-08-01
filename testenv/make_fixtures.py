#!/usr/bin/env python3
"""Generate a local fixture tree that mimics the slashdiablo.net file server.

Serves the same layout the launcher expects:

    <root>/news.json
    <root>/available_mods_1.1.0.json
    <root>/slashdiablo-patches/<mod>_<version>/manifest.json
    <root>/slashdiablo-patches/<mod>_<version>/<file>

Point the launcher at it with SLASHDIABLO_FILES_ADDRESS (see testenv/README.md).
"""

import argparse
import datetime
import json
import pathlib
import shutil
import urllib.request
import zipfile
import zlib

HERE = pathlib.Path(__file__).resolve().parent
FILES = HERE / "files"
PATCHES = FILES / "slashdiablo-patches"
GAME_DIR = HERE / "d2"

# Files d2gl ships that belong in the Diablo II directory. ddraw.dll is
# deliberately excluded on 1.14d, which dropped software rendering.
D2GL_FILES = [
    "ddraw.dll",
    "glide3x.dll",
    "d2gl.mpq",
    "LICENSE.md",
    "THIRD_PARTY_LICENSES.md",
]


def crc32(path):
    """CRC32 in the same form the launcher's hashCRC32 produces (8 hex chars)."""
    digest = 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest = zlib.crc32(chunk, digest)
    return format(digest & 0xFFFFFFFF, "08x")


def manifest_for(directory):
    """Build a manifest.json describing every file in directory."""
    files = []
    for path in sorted(directory.iterdir()):
        if path.name == "manifest.json" or not path.is_file():
            continue
        stat = path.stat()
        modified = datetime.datetime.fromtimestamp(
            stat.st_mtime, datetime.timezone.utc
        )
        files.append(
            {
                "name": path.name,
                "crc": crc32(path),
                "last_modified": modified.isoformat(),
                "content_length": stat.st_size,
                "ignore_crc": False,
                "deprecated": False,
            }
        )
    return {"files": files}


def write_manifest(directory):
    manifest = manifest_for(directory)
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def add_d2gl(version, archive):
    """Unpack a real D2GL release zip into a mod directory and manifest it."""
    target = PATCHES / f"d2gl_{version}"
    target.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(archive) as zf:
        available = set(zf.namelist())
        missing = [name for name in D2GL_FILES if name not in available]
        if missing:
            raise SystemExit(
                f"{archive} is missing expected D2GL files: {', '.join(missing)}"
            )
        for name in D2GL_FILES:
            with zf.open(name) as src, open(target / name, "wb") as dst:
                shutil.copyfileobj(src, dst)

    manifest = write_manifest(target)
    print(f"  d2gl_{version}: {len(manifest['files'])} files")
    return target


def add_stub_mod(name, version, filenames):
    """Create a small placeholder mod so patch flows can be exercised offline."""
    target = PATCHES / f"{name}_{version}"
    target.mkdir(parents=True, exist_ok=True)
    for filename in filenames:
        (target / filename).write_bytes(
            f"stub {name} {version} {filename}\n".encode()
        )
    manifest = write_manifest(target)
    print(f"  {name}_{version}: {len(manifest['files'])} files (stubs)")


def make_game_dir():
    """A stand-in Diablo II install for the launcher to patch against."""
    GAME_DIR.mkdir(parents=True, exist_ok=True)
    for exe in ("Game.exe", "Diablo II.exe"):
        path = GAME_DIR / exe
        if not path.exists():
            path.write_bytes(b"stub " + exe.encode() + b"\n")
    print(f"  game dir: {GAME_DIR}")


def upstream_mods():
    """Mod versions as production advertises them, so the reset paths that walk
    every known version see the same list the real launcher does."""
    url = "https://slashdiablo.net/files/available_mods_1.1.0.json"
    request = urllib.request.Request(
        url, headers={"User-Agent": "slashdiablo-launcher-testenv"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except Exception as err:  # noqa: BLE001 - offline is not fatal
        print(f"  warning: could not read {url} ({err}); using a minimal list")
        return {"hd": [], "maphack": []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--d2gl-zip",
        type=pathlib.Path,
        help="path to a D2GL release zip; if given, it is unpacked as a real mod",
    )
    parser.add_argument("--d2gl-version", default="1.3.3")
    args = parser.parse_args()

    PATCHES.mkdir(parents=True, exist_ok=True)

    print("building fixtures:")

    # Only the mod under development is served locally. hd and maphack are
    # deliberately absent so serve.py proxies them to production: a stub file
    # here would be downloaded straight over a real, working install.
    mods = upstream_mods()
    mods["d2gl"] = [args.d2gl_version]

    if args.d2gl_zip:
        add_d2gl(args.d2gl_version, args.d2gl_zip)
    else:
        add_stub_mod(
            "d2gl", args.d2gl_version, ["glide3x.dll", "ddraw.dll", "d2gl.mpq"]
        )
        print("  warning: d2gl files are stubs; pass --d2gl-zip for real ones")

    (FILES / "available_mods_1.1.0.json").write_text(json.dumps(mods, indent=2) + "\n")

    (FILES / "news.json").write_text(
        json.dumps(
            [
                {
                    "title": "LOCAL TEST ENVIRONMENT",
                    "text": "This news item is served from the local fixture server.",
                    "date": "1 January",
                    "year": "2026",
                }
            ],
            indent=2,
        )
        + "\n"
    )

    make_game_dir()
    print(f"\nfixtures ready under {FILES}")


if __name__ == "__main__":
    main()
