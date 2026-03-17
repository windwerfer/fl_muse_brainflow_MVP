import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'screens/muse_chart_screen.dart';

// flutter_rust_bridge generated init
import 'src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

ExternalLibrary _getRustLibrary() {
  // 1. Try bundled location (standard for production/bundled builds)
  final executablePath = Platform.resolvedExecutable;
  final executableDir = File(executablePath).parent.path;
  final bundledPath = '$executableDir/lib/librust_lib_fl_muse_brainflow_mvp.so';

  print('System info:');
  print('  Executable: $executablePath');
  print('  Bundled path check: $bundledPath');

  if (File(bundledPath).existsSync()) {
    print('  Bundled library found. Attempting to open...');
    try {
      final lib = ExternalLibrary.open(bundledPath);
      print('  Successfully opened bundled library.');
      return lib;
    } catch (e) {
      print('  Failed to open bundled library: $e');
      // Continue to fallback
    }
  } else {
    print('  Bundled library NOT found at $bundledPath');
  }

  // 2. Fallback to local development paths
  final debugPath = 'rust/target/debug/librust_lib_fl_muse_brainflow_mvp.so';
  final releasePath =
      'rust/target/release/librust_lib_fl_muse_brainflow_mvp.so';

  String? libraryPath;

  if (Platform.isLinux) {
    if (File(debugPath).existsSync()) {
      libraryPath = debugPath;
    } else if (File(releasePath).existsSync()) {
      libraryPath = releasePath;
    }
  }

  if (libraryPath == null) {
    libraryPath = releasePath;
  }

  print('Loading development Rust library from: $libraryPath');

  // NOTE: If this fails with "libBoardController.so: cannot open shared object file" during development,
  // ensure that packages/brainflow/lib/linux is in your LD_LIBRARY_PATH:
  // export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(pwd)/packages/brainflow/lib/linux
  return ExternalLibrary.open(libraryPath);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RustLib.init(externalLibrary: _getRustLibrary());

  // Optional but nice for BLE on desktop
  FlutterBluePlus.setLogLevel(LogLevel.warning);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: const MuseChartScreen(),
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
      );
}
