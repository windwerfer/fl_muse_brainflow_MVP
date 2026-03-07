#!/usr/bin/env dart
// Run with: dart run tool/build.dart <command>

import 'dart:io';

void main(List<String> args) => _run(args.isEmpty ? ['help'] : args);

// Simple helper: "flutter run -d android" -> runs it and streams output
Future<void> x(String command, {String? cwd}) async {
  final parts = command.split(' ');
  final executable = parts.first;
  final arguments = parts.skip(1).toList();

  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: cwd,
    // These three lines are the magic:
    mode: ProcessStartMode
        .inheritStdio, // ← key line (new in Dart 2.19+ / Flutter recent)
    // or (older Dart compatibility):
    // runInShell: true,   // sometimes helps on Windows
  );

  // Just wait for it to finish – no need to read/write anything
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('Command failed with exit code $exitCode: $command');
  }
}

// Capture output
Future<String> out(String c, {String? cwd}) async {
  final p = c.split(' ');
  final r =
      await Process.run(p.first, p.skip(1).toList(), workingDirectory: cwd);
  return r.stdout.toString();
}

// Remove folder/file
Future<void> rm(String path) async {
  final d = Directory(path);
  if (await d.exists()) {
    await d.delete(recursive: true);
    print('  Removed: $path');
  }
}

// Remove files matching pattern
Future<void> rmGlob(String pattern) async {
  await for (final e in Directory.current.list()) {
    if (e is File && e.path.contains(pattern)) {
      await e.delete();
      print('  Removed: ${e.path}');
    }
  }
}

Future<void> _run(List<String> args) async {
  final cmd = args[0];

  switch (cmd) {
    // Shortcuts
    case 'a':
    case 'android':
      x('flutter run -d android');
      break;
    case 'ac':
    case 'android-clean':
      await clean();
      x('flutter pub get');
      x('flutter run -d android');
      break;
    case 'acc':
    case 'android-super-clean':
      await superClean();
      x('flutter_rust_bridge_codegen generate');
      x('flutter pub get');
      x('flutter run -d android');
      break;

    case 'l':
    case 'linux':
      x('flutter run -d linux');
      break;
    case 'lc':
    case 'linux-clean':
      await clean();
      x('flutter pub get');
      x('flutter run -d linux');
      break;
    case 'lcc':
    case 'linux-super-clean':
      await superClean();
      x('flutter_rust_bridge_codegen generate');
      x('flutter pub get');
      x('flutter run -d linux');
      break;

    case 'w':
    case 'windows':
      x('flutter run -d windows');
      break;
    case 'wc':
    case 'windows-clean':
      await clean();
      x('flutter pub get');
      x('flutter run -d windows');
      break;
    case 'wcc':
    case 'windows-super-clean':
      await superClean();
      x('flutter_rust_bridge_codegen generate');
      x('flutter pub get');
      x('flutter run -d windows');
      break;

    case 'clean':
      await clean();
      break;
    case 'super-clean':
      await superClean();
      break;

    case 'f':
      x('flutter_rust_bridge_codegen generate');
      break;
    case 'watch':
      x('flutter_rust_bridge_codegen generate --watch');
      break;
    case 'rebuild':
      await superClean();
      x('flutter_rust_bridge_codegen generate');
      x('flutter pub get');
      break;
    case 'doctor':
      await doctor();
      break;
    default:
      help();
  }
}

Future<void> clean() async {
  print('🧼 Running clean...');
  x('flutter clean');
  x('cargo clean -p rust_lib_fl_muse_brainflow_mvp', cwd: 'rust');
}

Future<void> superClean() async {
  print('🧼 SUPER DEEP CLEAN...');
  await rm('lib/src/rust');
  await rm('rust/src/frb_generated.rs');
  await rm('.dart_tool');
  await rm('build');
  await rmGlob('.flutter-plugins');
  await clean();
  x('flutter clean');
}

Future<void> doctor() async {
  print('🔍 Health Check\n========================================');
  print('Flutter & Android toolchain:');
  x('flutter doctor');

  print('\nRust & Tools:');
  try {
    print('  Rust       : ✅ ${(await out('rustc --version')).trim()}');
  } catch (_) {
    print('  Rust       : ❌');
  }
  try {
    print(
        '  FRB Codegen: ✅ ${(await out('flutter_rust_bridge_codegen --version')).trim()}');
  } catch (_) {
    print('  FRB Codegen: ❌');
  }
  try {
    print('  Java JDK   : ✅ ${(await out('java -version')).split('\n').first}');
  } catch (_) {
    print('  Java JDK   : ❌');
  }
  print(
      '  ANDROID_HOME: ${Platform.environment['ANDROID_HOME'] ?? "❌ Not set"}');

  // Check Android NDK
  print('\nAndroid NDK:');
  final ndkHome = Platform.environment['ANDROID_HOME'];
  if (ndkHome != null) {
    final ndkDir = Directory('$ndkHome/ndk');
    if (await ndkDir.exists()) {
      await for (final e in ndkDir.list()) {
        if (e is Directory) {
          print('  ✅ NDK ${e.path.split('/').last}');
        }
      }
    } else {
      print('  ❌ No NDK installed');
    }
  } else {
    print('  ❌ ANDROID_HOME not set');
  }

  // Check Rust Android targets
  print('\nRust Android Targets:');
  final targets = [
    'aarch64-linux-android',
    'armv7-linux-androideabi',
    'x86_64-linux-android',
    'i686-linux-android'
  ];
  final installed = (await out('rustup target list --installed'))
      .split('\n')
      .where((t) => t.contains('android'))
      .toList();
  for (final t in targets) {
    final isInstalled = installed.contains(t);
    final arch =
        t.replaceAll('-linux-androideabi', '').replaceAll('-linux-android', '');
    print('  ${isInstalled ? '✅' : '❌'} $arch (${t})');
  }

  // Summary: what can be built
  print('\n📱 Build Targets:');
  final canAndroid = installed.length >= 3 && ndkHome != null;
  print(
      '  Android     : ${canAndroid ? "✅ Ready" : "❌ Missing deps (need Rust Android targets + NDK)"}');
  print('  Linux       : ✅ Ready (desktop)');
  print('  Windows     : ✅ Ready (desktop)');
}

void help() => print('''
fl_muse_brainflow_MVP — Build Script
====================================
Usage: dart run tool/build.dart <cmd>

Commands:
  a/ac/acc       android (clean/super-clean)
  l/lc/lcc       linux   (clean/super-clean)
  w/wc/wcc       windows (clean/super-clean)
  clean          flutter + cargo clean
  super-clean    remove all generated
  f              regenerate FRB
  watch          watch for Rust changes
  rebuild        super-clean + generate + pub get
  doctor         health check
''');
