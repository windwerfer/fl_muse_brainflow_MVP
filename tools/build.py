#!/usr/bin/env python3
"""
Simple Flutter+Rust build helper
Usage: python build.py <command>
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

from doctor import doctor  # import doctor script

# ────────────────────────────────────────────────
#  Constants & Helpers
# ────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RUST_DIR = PROJECT_ROOT / "rust"
ANDROID_DIR = PROJECT_ROOT / "android"

ANDROID_ABIS = ["arm64-v8a", "armeabi-v7a", "x86_64"]


def run(cmd, cwd=None, check=True):
    cwd = cwd or PROJECT_ROOT
    print(f"→ {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        check=check,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )
    return result


def capture(cmd, cwd=None):
    result = subprocess.run(
        cmd, cwd=cwd or PROJECT_ROOT, capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def rm(path):
    path = Path(path)
    if path.exists():
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink()
        print(f"Removed: {path}")


def clean():
    print("🧼 Clean...")
    run(["flutter", "clean"])
    run(["cargo", "clean", "-p", "rust_lib_fl_muse_brainflow_mvp"], cwd=RUST_DIR)


def super_clean():
    print("🧼 Full Clean...")
    rm(PROJECT_ROOT / "lib/src/rust")
    rm(RUST_DIR / "src/frb_generated.rs")
    rm(PROJECT_ROOT / ".dart_tool")
    rm(PROJECT_ROOT / "build")
    for p in PROJECT_ROOT.glob(".flutter-plugins*"):
        rm(p)
    run(["flutter", "clean"])
    run(["cargo", "clean", "-p", "rust_lib_fl_muse_brainflow_mvp"], cwd=RUST_DIR)


def full_clean():
    print("🧼 Full Clean...")
    rm(PROJECT_ROOT / "lib/src/rust")
    rm(RUST_DIR / "src/frb_generated.rs")
    rm(PROJECT_ROOT / ".dart_tool")
    rm(PROJECT_ROOT / "build")
    for p in PROJECT_ROOT.glob(".flutter-plugins*"):
        rm(p)
    run(["flutter", "clean"])
    run(["cargo", "clean"], cwd=RUST_DIR)


# ────────────────────────────────────────────────
#  Build Commands
# ────────────────────────────────────────────────


def build_rust(mode="debug"):
    print(f"🦀 Rust ({mode})...")
    args = ["cargo", "build"]
    if mode == "release":
        args += ["--release"]
    run(args, cwd=RUST_DIR)


def build_rust_android(profile="debug"):
    print(f"🦀 Rust Android ({profile})...")
    profile_flag = ["--release"] if profile == "release" else []
    for abi in ANDROID_ABIS:
        run(
            [
                "cargo",
                "ndk",
                "-t",
                abi,
                *profile_flag,
                "-o",
                "../android/app/src/main/jniLibs",
                "build",
            ],
            cwd=RUST_DIR,
        )
    print("Android Rust libs done.")


def regenerate_frb():
    run(["flutter_rust_bridge_codegen", "generate"])


def build_cargo():
    run(["cargo", "build"], cwd=RUST_DIR)


def _run_flutter(device):
    run(["flutter", "run", "-d", device])


def _build_clean_run(clean_fn, build_fn, device):
    clean_fn()
    regenerate_frb()
    build_fn()
    run(["flutter", "pub", "get"])
    _run_flutter(device)


def _build_and_run(build_fn, device):
    build_fn()
    _run_flutter(device)


def _clean_build_run(clean_fn, device):
    clean_fn()
    run(["flutter", "pub", "get"])
    _run_flutter(device)


def help_text():
    print("""
Commands:
  a                   → build & run Android
  ac                  → clean + Android
  acc                 → clean + regen FRB + Android
  accc                → full cargo clean + regen FRB + Android

  l                   → build & run Linux
  lc                  → clean + Linux
  lcc                 → clean + regen FRB + Linux
  lccc                → full cargo clean + regen FRB + Linux

  w                   → run Windows
  wc                  → clean + Windows
  wcc                 → clean + regen FRB + Windows
  wccc                → full cargo clean + regen FRB + Windows

  clean               → flutter + cargo clean (package)
  super-clean         → deep clean (full cargo)
  f                   → regenerate FRB
  c                   → cargo build (see rust build errors)
  doctor              → health check
  help                → this help
""")


COMMANDS = {
    "a": lambda: _build_and_run(build_rust_android, "android"),
    "ac": lambda: _clean_build_run(clean, "android"),
    "acc": lambda: _build_clean_run(super_clean, build_rust_android, "android"),
    "accc": lambda: _build_clean_run(full_clean, build_rust_android, "android"),
    "l": lambda: _build_and_run(build_rust, "linux"),
    "lc": lambda: _clean_build_run(clean, "linux"),
    "lcc": lambda: _build_clean_run(super_clean, build_rust, "linux"),
    "lccc": lambda: _build_clean_run(full_clean, build_rust, "linux"),
    "w": lambda: _run_flutter("windows"),
    "wc": lambda: _clean_build_run(clean, "windows"),
    "wcc": lambda: _build_clean_run(super_clean, build_rust, "windows"),
    "wccc": lambda: _build_clean_run(full_clean, build_rust, "windows"),
    "clean": clean,
    "super-clean": super_clean,
    "full_clean": full_clean,
    "f": regenerate_frb,
    "c": build_cargo,
    "doctor": doctor,
    "help": help_text,
}


def main():
    if len(sys.argv) < 2:
        help_text()
        return

    cmd = sys.argv[1].lower()
    if cmd not in COMMANDS:
        print(f"Unknown: {cmd}\n")
        help_text()
        sys.exit(1)

    try:
        COMMANDS[cmd]()
    except subprocess.CalledProcessError as e:
        print(f"Failed: {' '.join(e.cmd)} (code {e.returncode})")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
