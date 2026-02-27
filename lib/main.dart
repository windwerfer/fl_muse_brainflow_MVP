import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'screens/muse_chart_screen.dart';

// flutter_rust_bridge generated init
import 'src/rust/frb_generated.dart'; // ← this is the important line

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ←←← THIS IS THE MISSING LINE
  await RustLib.init(); // or RustLibFlMuseBrainflowMvp if you renamed it

  // Optional but nice for BLE on desktop
  FlutterBluePlus.setLogLevel(LogLevel.verbose);

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
