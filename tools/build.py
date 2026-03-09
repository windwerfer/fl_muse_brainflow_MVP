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
from doctor import doctor       # import doctor script

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
    print("🧼 SUPER CLEAN...")
    rm(PROJECT_ROOT / "lib/src/rust")
    rm(RUST_DIR / "src/frb_generated.rs")
    rm(PROJECT_ROOT / ".dart_tool")
    rm(PROJECT_ROOT / "build")
    # .flutter-plugins* usually safe to skip or rm if exists
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



def help_text():
    print("""
Commands:
  a                  → build & run Android
  ac                 → clean + Android
  acc                → super clean + Android

  l                  → build & run Linux
  lc                 → clean + Linux
  lcc                → super clean + Linux

  w                  → run Windows
  wc                 → clean + Windows
  wcc                → super clean + Windows

  clean                      → flutter + cargo clean
  super-clean                → deep clean
  f                          → regenerate FRB
  doctor                     → health check
  help                       → this help
""")


COMMANDS = {
    "a": lambda: (build_rust_android(), run(["flutter", "run", "-d", "android"])),
    "ac": lambda: (
        clean(),
        build_rust_android(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "android"]),
    ),
    "acc": lambda: (
        super_clean(),
        regenerate_frb(),
        build_rust_android(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "android"]),
    ),
    "l": lambda: (build_rust(), run(["flutter", "run", "-d", "linux"])),
    "lc": lambda: (
        clean(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "linux"]),
    ),
    "lcc": lambda: (
        super_clean(),
        regenerate_frb(),
        build_rust(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "linux"]),
    ),
    "w": lambda: run(["flutter", "run", "-d", "windows"]),
    "wc": lambda: (
        clean(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "windows"]),
    ),
    "wcc": lambda: (
        super_clean(),
        regenerate_frb(),
        build_rust(),
        run(["flutter", "pub", "get"]),
        run(["flutter", "run", "-d", "windows"]),
    ),
    "clean": clean,
    "super-clean": super_clean,
    "f": regenerate_frb,
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
