# MuseStream Project Documentation

## Project Overview
MuseStream is a minimal EEG biofeedback application designed to connect to the Muse S headset via Bluetooth Low Energy. The project focuses on real-time raw EEG data streaming and visualization.

## Technical Stack
- **Framework:** Flutter (Material 3)
- **Native Logic:** Rust with `flutter_rust_bridge` v2 (v2.11.1)
- **EEG Engine:** BrainFlow v5.20.1 (Prebuilt shared libraries)
- **State Management:** Riverpod

## Project Structure
- `lib/`: Flutter source code.
  - `src/rust/`: Generated Dart bindings for Rust logic.
- `rust/`: Application-specific Rust logic and BrainFlow bridging.
- `packages/brainflow/`: Master source for the BrainFlow SDK.
  - `lib/`: Platform-specific shared libraries (`linux/`, `windows/`, `android/`). **Single source of truth for binaries.**
  - `src/`: Rust bindings for BrainFlow.
- `linux/`, `windows/`, `android/`: Platform-specific build scripts (CMake/Gradle) configured to source binaries directly from `packages/brainflow/lib/`.

## Key Design Choices & Logic
1. **Centralized Binaries:** All native libraries are stored in `packages/brainflow/lib` organized by platform. Build scripts (CMake, Cargo, Gradle) are configured to source from here to avoid redundancy and Git symlink issues.
2. **Battery Sensor:** **DISABLED.** Reverted the `get_battery_level` API as it caused internal BrainFlow errors with the Muse S `DefaultPreset`. Battery monitoring is currently out of scope for stability.
3. **Signal Quality:** Implemented in Flutter based on the standard deviation of raw EEG samples.
   - **Good:** 1.0 - 50.0 μV
   - **Fair:** 50.0 - 100.0 μV
   - **Poor:** < 1.0 or > 200.0 μV
4. **Polling:** 10Hz polling for UI updates (256 samples per request).

## Development & Build Commands
- **Regenerate Bridge:** To regenerate the Rust bindings, run `flutter_rust_bridge_codegen generate` from the project root. Do NOT use `flutter pub run flutter_rust_bridge_codegen` as `flutter_rust_bridge_codegen` is a Rust crate.
- **Build Rust Only:** `cd rust && cargo build`
- **Run App (Linux):** `flutter run -d linux`
- **Build Android:** `flutter build apk` (Ensure permissions are granted)

## Android Permissions
- **Bluetooth:** `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` (Android 12+)
- **Location:** `ACCESS_FINE_LOCATION` (Android 6-11, and 12+ if scanning)
- Permissions are requested at runtime in `MuseStateNotifier.connect()`.

## Current API Surface (Rust)
- `connect_to_muse(mac_address: Option<String>)`: Initializes `BoardShim` (Board ID 39), prepares session, and starts stream.
- `disconnect_muse()`: Stops stream and releases session.
- `get_connection_status()`: Returns `ConnectionStatus` enum.
- `get_latest_data(num_samples: i32)`: Returns `EegData` (channels and raw samples).
- `init_logger()`: Initializes `env_logger` using `try_init()` for safety.

## Maintenance
**CRITICAL:** Update this file regularly after making significant design choices or architectural changes to ensure project alignment and help the agent remember context across sessions.