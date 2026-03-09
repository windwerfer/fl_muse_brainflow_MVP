#!/usr/bin/env python3

# ────────────────────────────────────────────────
#  Doctor – Health Check
# ────────────────────────────────────────────────

import os
import subprocess
from pathlib import Path


def ok_if_zero(cmd, name, version_arg="--version", cwd=None):
    try:
        out = subprocess.check_output(
            cmd + [version_arg], cwd=cwd, stderr=subprocess.STDOUT, text=True
        ).strip()
        first_line = out.splitlines()[0]
        print(f" {name:18} ✅ {first_line}")
        return True
    except Exception:
        print(f" {name:18} ❌")
        return False


def doctor():
    """Health check – tries to detect most common setup issues."""
    print("🔍 Doctor – Dependency Check")
    print("-" * 50)

    print("\nCore tools:")
    flutter_ok = ok_if_zero(["flutter"], "Flutter", "doctor")
    rustc_ok = ok_if_zero(["rustc"], "Rustc")
    cargo_ok = ok_if_zero(["cargo"], "Cargo")
    frb_ok = ok_if_zero(["flutter_rust_bridge_codegen"], "FRB-codegen")
    ndk_ok = ok_if_zero(["cargo", "ndk"], "cargo-ndk")  # ← this now works for you

    print("\nAndroid toolchain:")
    java_ok = ok_if_zero(["java"], "Java/JDK", "-version")

    # === Improved sdkmanager check (standard location) ===
    android_home = os.environ.get("ANDROID_HOME")
    sdkmanager_ok = False
    if android_home:
        sdk_path = (
            Path(android_home) / "cmdline-tools" / "latest" / "bin" / "sdkmanager"
        )
        if sdk_path.is_file():
            try:
                out = subprocess.check_output(
                    [str(sdk_path), "--version"], stderr=subprocess.STDOUT, text=True
                ).strip()
                print(f" sdkmanager        ✅ {out.splitlines()[0]}")
                sdkmanager_ok = True
            except:
                print(" sdkmanager        ⚠️ found but --version failed")
        else:
            print(
                " sdkmanager        ⚠️ not in cmdline-tools/latest/bin (may still work)"
            )
    else:
        print(" ANDROID_HOME      ❌ not set")

    # ANDROID_HOME + NDK folder
    ndk_found = False
    if android_home:
        ndk_path = Path(android_home) / "ndk"
        ndk_found = ndk_path.exists() and any(
            (ndk_path / v).is_dir() for v in os.listdir(ndk_path)
        )
        print(f" ANDROID_HOME      ✅ {android_home}")
        print(f" NDK folder        {'✅' if ndk_found else '❌'}")
    else:
        print(" ANDROID_HOME      ❌ not set")

    # Rust Android targets
    print("\nRust Android targets:")
    try:
        targets = subprocess.check_output(
            ["rustup", "target", "list", "--installed"], text=True
        ).splitlines()
        android_targets = [t.strip() for t in targets if "android" in t]
        count = len(android_targets)
        print(f" {count} found {'✅' if count >= 3 else '⚠️'}")
        if count > 0:
            print(
                "   " + ", ".join(android_targets[:3]) + (" ..." if count > 3 else "")
            )
    except:
        print(" ❌ (rustup not working?)")

    # Android licenses
    print("\nAndroid licenses:")
    try:
        fd_out = subprocess.check_output(["flutter", "doctor", "-v"], text=True)
        has_issue = any(
            phrase in fd_out.lower()
            for phrase in ["licenses not accepted", "no licenses accepted"]
        )
        print(
            f" {'✅ accepted' if not has_issue else '❌ need acceptance (run: flutter doctor --android-licenses)'}"
        )
    except:
        print(" ⚠️ flutter doctor failed")

    # Final summary
    print("\n" + "=" * 50)
    print("Quick summary:")
    critical_ok = all(
        [
            flutter_ok,
            rustc_ok,
            cargo_ok,
            frb_ok,
            ndk_ok,
            java_ok,
            sdkmanager_ok,
            ndk_found,
        ]
    )
    android_basic = bool(android_home and ndk_found and count >= 2 and sdkmanager_ok)

    print(
        f" Desktop builds     : {'✅ looks ready' if flutter_ok and rustc_ok and cargo_ok else '⚠️ check above'}"
    )
    print(
        f" Android builds     : {'✅ probably ready' if android_basic else '❌ missing key pieces'}"
    )
    print(
        f" Critical tools     : {'none ✅' if critical_ok else 'some ❌ – see above'}"
    )
    print("\nTip: Run 'flutter doctor -v' for the full official report.")


def main():
    print("to run the doctor script: python3 build.py doctor")


if __name__ == "__main__":
    main()
