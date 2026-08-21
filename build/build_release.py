#!/usr/bin/env python3
"""RiotSwitcher release builder.

Exports the project with the custom lightweight Godot template, compresses
the executable with UPX and zips the result next to this script.

Usage:
    python build/build_release.py [version]

    python build/build_release.py 0.3.4

If no version is given on the command line, you will be prompted for it.
The zip is written as build/RiotSwitcher-<version>.zip.

The Godot editor and UPX are located automatically:
  - Godot: GodotHub installs, the official "Programs\\Godot" folder, the
    PATH, the GODOT_EDITOR environment variable or the EXTRA_GODOT_PATHS
    list below. The editor must match the version required by project.godot.
  - UPX: the PATH, the UPX_PATH environment variable, the EXTRA_UPX_PATHS
    list below, or the bin folder next to the custom Godot template.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# --------------------------------------------------------------------------- #
# Configuration (only touch this if the automatic discovery fails)
# --------------------------------------------------------------------------- #

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DIST_DIR = SCRIPT_DIR / "dist"

# Optional explicit paths (empty by default; discovery is automatic).
EXTRA_GODOT_PATHS = []  # e.g. [Path(r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe")]
EXTRA_UPX_PATHS = []  # e.g. [Path(r"D:\Tools\upx.exe")]

EXPORT_PRESET = "Windows Desktop"
EXE_NAME = "RiotSwitcher.exe"
PCK_NAME = "RiotSwitcher.pck"

VERSION_PATTERN = re.compile(r"^[0-9][0-9A-Za-z._\-]*$")
GODOT_EXE_PATTERN = re.compile(r"godot[^\\/]*?(\d+)\.(\d+)(?:\.(\d+))?[^\\/]*\.exe$", re.IGNORECASE)
VERSION_DIR_PATTERN = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?")
PROJECT_FEATURE_PATTERN = re.compile(r'features=PackedStringArray\("(\d+)\.(\d+)"')

# --------------------------------------------------------------------------- #


def log(message: str) -> None:
    print(f"[build] {message}")


def _project_required_version() -> tuple[int, int]:
    """Major.minor version the project requires (from project.godot)."""
    project_file = PROJECT_ROOT / "project.godot"
    if not project_file.is_file():
        return (0, 0)
    text = project_file.read_text(encoding="utf-8", errors="replace")
    match = PROJECT_FEATURE_PATTERN.search(text)
    if match:
        return (int(match.group(1)), int(match.group(2)))
    return (0, 0)


def _version_tuple_from_path(path: Path) -> tuple[int, int, int] | None:
    """Extracts (major, minor, patch) from a Godot exe/folder name, if any."""
    match = GODOT_EXE_PATTERN.search(path.name)
    if match:
        return (int(match.group(1)), int(match.group(2)), int(match.group(3) or 0))
    match = VERSION_DIR_PATTERN.search(path.parent.name)
    if match:
        return (int(match.group(1)), int(match.group(2)), int(match.group(3) or 0))
    return None


def _discover_godot_editors() -> list[tuple[Path, tuple[int, int, int]]]:
    """Collects every Godot editor executable found on this machine."""
    candidates: list[Path] = list(EXTRA_GODOT_PATHS)

    env_editor = os.environ.get("GODOT_EDITOR", "")
    if env_editor:
        candidates.append(Path(env_editor))

    search_dirs = [
        Path(os.environ.get("APPDATA", "")) / "com.ryko.godothub" / "godot-versions",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Godot",
        Path(os.environ.get("ProgramFiles", "")) / "Godot",
    ]
    for directory in search_dirs:
        if not directory.is_dir():
            continue
        for exe in directory.rglob("*.exe"):
            candidates.append(exe)

    for which_name in ("godot", "godot4", "Godot"):
        found = shutil.which(which_name)
        if found:
            candidates.append(Path(found))

    discovered: dict[Path, tuple[int, int, int]] = {}
    for candidate in candidates:
        if not candidate.is_file() or "godot" not in candidate.name.lower():
            continue
        version = _version_tuple_from_path(candidate)
        if version:
            discovered[candidate.resolve()] = version
    return sorted(discovered.items(), key=lambda item: item[1])


def find_godot_editor() -> Path:
    required = _project_required_version()
    editors = _discover_godot_editors()
    if not editors:
        raise SystemExit(
            "No Godot editor was found. Install Godot (any 4.x editor) or set the\n"
            "GODOT_EDITOR environment variable / EXTRA_GODOT_PATHS in this script."
        )

    matching = [item for item in editors if item[1][:2] == required] if required != (0, 0) else []
    pool = matching if matching else editors

    def is_console(item: tuple[Path, tuple[int, int, int]]) -> int:
        return 1 if "_console" in item[0].name.lower() else 0

    best_path, best_version = max(pool, key=lambda item: (item[1], is_console(item)))

    if required != (0, 0) and not matching:
        log(
            f"Warning: no Godot {required[0]}.{required[1]} editor found; "
            f"using the newest available ({best_version[0]}.{best_version[1]}.{best_version[2]})."
        )
    log(f"Using Godot editor: {best_path}")
    return best_path


def find_upx() -> Path:
    candidates: list[Path] = list(EXTRA_UPX_PATHS)

    env_upx = os.environ.get("UPX_PATH", "")
    if env_upx:
        candidates.append(Path(env_upx))

    in_path = shutil.which("upx")
    if in_path:
        candidates.append(Path(in_path))

    # Fallback: UPX usually lives next to the custom Godot template.
    candidates.append(Path.home() / "Projetos" / "GodotRep" / "godot" / "bin" / "upx.exe")

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    searched = "\n".join(f"  - {p}" for p in candidates)
    raise SystemExit(
        f"UPX was not found. Install it or point to it with the UPX_PATH\n"
        f"environment variable / EXTRA_UPX_PATHS in this script. Tried:\n{searched}"
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

    godot = find_godot_editor()
    upx = find_upx()

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
