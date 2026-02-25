# =============================================================================
# fl_muse_brainflow_MVP — Clean & popular short commands
# =============================================================================

default:
    @just --list

# ── Short platform + clean combinations ─────────────────────────────────────
a:    android
ac:   android-clean
acc:  android-super-clean

l:    linux
lc:   linux-clean
lcc:  linux-super-clean

w:    windows
wc:   windows-clean
wcc:  windows-super-clean

# ── Platform targets ────────────────────────────────────────────────────────
android:
    @echo "🚀 Running on Android (real Muse)"
    flutter run

linux:
    @echo "🚀 Running on Linux desktop "
    flutter run -d linux

windows:
    @echo "🚀 Running on Windows desktop "
    flutter run -d windows

# ── Clean levels ────────────────────────────────────────────────────────────
clean:
    @echo "🧼 Normal clean..."
    flutter clean
    cd rust && cargo clean -p rust_lib_fl_muse_brainflow_mvp && cd ..

super-clean:
    @echo "🧼 SUPER DEEP CLEAN..."
    rm -rf lib/src/rust/ rust/src/frb_generated.rs .dart_tool/ build/ .flutter-plugins*
    cd rust && cargo clean -p rust_lib_fl_muse_brainflow_mvp && cd ..
    cd android && ./gradlew clean --quiet && cd ..
    flutter clean

# ── Clean + Run combinations ────────────────────────────────────────────────
android-clean:
    just clean
    flutter pub get
    just android

android-super-clean:
    just super-clean
    just f
    flutter pub get
    just android

linux-clean:
    just clean
    flutter pub get
    just linux

linux-super-clean:
    just super-clean
    just f
    flutter pub get
    just linux

# Windows clean recipes
windows-clean:
    just clean
    flutter pub get
    just windows

windows-super-clean:
    just super-clean
    just f
    flutter pub get
    just windows

# ── Other useful commands ───────────────────────────────────────────────────
f:
    @echo "🔄 Regenerating FRB bindings..."
    flutter_rust_bridge_codegen generate

watch:
    @echo "👀 Watching for Rust changes..."
    flutter_rust_bridge_codegen generate --watch

rebuild:
    just acc

# ── Health Check ────────────────────────────────────────────────────────────
doctor:
    @echo "🔍 fl_muse_brainflow_MVP Health Check"
    @echo "========================================\n"

    @echo "Flutter & Android toolchain:"
    @flutter doctor

    @echo "\nRust & Tools:"
    @printf "  Rust                  : "; rustc --version 2>/dev/null && echo "✅" || echo "❌ Not found"
    @printf "  FRB Codegen           : "; which flutter_rust_bridge_codegen >/dev/null 2>&1 && echo "✅" || echo "❌ Not installed"
    @printf "  Java JDK              : "; java -version 2>&1 | head -n 1 || echo "❌ Not found"
    @printf "  ANDROID_HOME          : "; [ -n "$ANDROID_HOME" ] && echo "✅" || echo "❌ Not set"

    @echo "\nPlatform Summary:"
    @echo "  Linux (mock mode)     : ✅ Always ready"
    @echo "  Windows (mock mode)   : ✅ Always ready"
    @printf "  Android (real Muse)   : "; [ -n "$ANDROID_HOME" ] && flutter doctor  --no-color 2>/dev/null | grep -q "\[✓\].*Android toolchain"  && echo "✅ Ready" || echo "⚠️  Needs attention (see above)"
