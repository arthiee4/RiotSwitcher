#!/usr/bin/env python3
"""RiotSwitcher release builder.

Exports the project with the custom lightweight Godot template, compresses
the executable with UPX and zips the result next to this script.

Usage:
    python build/build_release.py [version]

    python build/build_release.py 0.3.4

If no version is given on the command line, you will be prompted for it.
The zip is written as build/RiotSwitcher-<version>.zip.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths / configuration (edit here if your machine differs)
# --------------------------------------------------------------------------- #

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DIST_DIR = SCRIPT_DIR / "dist"

# Godot editor used to run the headless export (first match wins).
GODOT_EDITOR_CANDIDATES = [
    Path(r"C:\Users\arthi\AppData\Roaming\com.ryko.godothub\godot-versions\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"),
    Path(r"C:\Users\arthi\AppData\Roaming\com.ryko.godothub\godot-versions\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"),
    Path(r"C:\Users\arthi\AppData\Roaming\com.ryko.godothub\godot-versions\4.7.1-stable\Godot_v4.7.1-stable_win64_console.exe"),
]

# UPX used to shrink the final executable.
UPX_CANDIDATES = [
    Path(r"C:\Users\arthi\Projetos\GodotRep\godot\bin\upx.exe"),
]

EXPORT_PRESET = "Windows Desktop"
EXE_NAME = "RiotSwitcher.exe"
PCK_NAME = "RiotSwitcher.pck"

VERSION_PATTERN = re.compile(r"^[0-9][0-9A-Za-z._\-]*$")

# --------------------------------------------------------------------------- #


def log(message: str) -> None:
    print(f"[build] {message}")


def find_executable(candidates: list[Path], name: str, env_var: str, which_name: str) -> Path:
    env_path = os.environ.get(env_var, "")
    if env_path:
        candidates.insert(0, Path(env_path))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    fallback = shutil.which(which_name)
    if fallback:
        return Path(fallback)
    searched = "\n".join(f"  - {p}" for p in candidates)
    raise SystemExit(
        f"{name} was not found. Tried:\n{searched}\n"
        f"Fix the candidates list in this script or set the {env_var} environment variable."
    )


def ask_version() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1].lstrip("vV")

    try:
        version = input("Version (e.g. 0.3.4): ").strip()
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("No version given. Aborting.")

    return version.lstrip("vV")


def run(cmd: list[str], description: str) -> None:
    log(description)
    log("> " + " ".join(str(part) for part in cmd))
    result = subprocess.run(cmd, cwd=PROJECT_ROOT)
    if result.returncode != 0:
        raise SystemExit(f"{description} failed with exit code {result.returncode}.")


def main() -> None:
    version = ask_version()
    if not version or not VERSION_PATTERN.match(version):
        raise SystemExit(
            f"Invalid version '{version}'. Use a pattern like 0.3.4 (digits, dots, letters, dashes)."
        )

    godot = find_executable(GODOT_EDITOR_CANDIDATES, "Godot editor", "GODOT_EDITOR", "godot")
    upx = find_executable(UPX_CANDIDATES, "UPX", "UPX_PATH", "upx")

    zip_path = SCRIPT_DIR / f"RiotSwitcher-{version}.zip"
    exe_path = DIST_DIR / EXE_NAME
    pck_path = DIST_DIR / PCK_NAME

    log(f"Building RiotSwitcher-{version} ...")

    # 1. Clean staging folder
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True)

    # 2. Export with the custom template configured in export_presets.cfg
    run(
        [
            str(godot),
            "--headless",
            "--path",
            str(PROJECT_ROOT),
            "--export-release",
            EXPORT_PRESET,
            str(exe_path),
        ],
        "Exporting project (headless)...",
    )

    if not exe_path.is_file():
        raise SystemExit(f"Export did not produce '{exe_path}'.")

    # 3. Optimize the executable with UPX
    run([str(upx), "--best", str(exe_path)], "Compressing executable with UPX...")

    if not exe_path.is_file():
        raise SystemExit("UPX removed the executable unexpectedly. Aborting.")

    # 4. Zip the executable (+ data pack if the preset writes one) next to this script
    files_to_zip = [exe_path]
    if pck_path.is_file():
        files_to_zip.append(pck_path)
    else:
        log("No .pck found (pack is embedded in the executable).")

    log(f"Zipping to '{zip_path}' ...")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file_path in files_to_zip:
            archive.write(file_path, arcname=file_path.name)

    size_mb = zip_path.stat().st_size / (1024 * 1024)
    log(f"Done! {zip_path.name} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit("Build cancelled.")
