import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_stream/src/rust/api.dart' as api;
import 'package:muse_stream/src/rust/frb_generated.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  debugPrint("--- APP STARTING ---");
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    debugPrint("Step 1: Initializing RustLib (FFI)...");
    await RustLib.init();
    debugPrint("Step 1 Success: RustLib initialized.");
  } catch (e, stack) {
    debugPrint("CRITICAL ERROR during RustLib.init(): $e");
    debugPrint("Stack trace: $stack");
  }

  try {
    debugPrint("Step 2: Initializing Logger...");
    await api.initLogger();
    debugPrint("Step 2 Success: Logger initialized.");
  } catch (e) {
    debugPrint("Error during api.initLogger(): $e");
  }

  debugPrint("Step 3: Running App UI...");
  runApp(const ProviderScope(child: MuseStreamApp()));
}

class MuseStreamApp extends StatelessWidget {
  const MuseStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MuseStream',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const MuseConnectionScreen(),
    );
  }
}

enum SignalQuality { good, fair, poor, none }

double calculateStdDev(List<double> data) {
  if (data.isEmpty) return 0;
  double mean = data.reduce((a, b) => a + b) / data.length;
  double sumSqDiff = data.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
  return Math.sqrt(sumSqDiff / data.length);
}

class MuseState {
  final api.ConnectionStatus status;
  final List<List<double>> eegData;
  final SignalQuality signalQuality;
  final String? errorMessage;

  MuseState({
    required this.status,
    this.eegData = const [],
    this.signalQuality = SignalQuality.none,
    this.errorMessage,
  });

  MuseState copyWith({
    api.ConnectionStatus? status,
    List<List<double>>? eegData,
    SignalQuality? signalQuality,
    String? errorMessage,
  }) {
    return MuseState(
      status: status ?? this.status,
      eegData: eegData ?? this.eegData,
      signalQuality: signalQuality ?? this.signalQuality,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class MuseStateNotifier extends StateNotifier<MuseState> {
  Timer? _timer;

  MuseStateNotifier() : super(MuseState(status: api.ConnectionStatus.disconnected));

  Future<void> connect() async {
    state = state.copyWith(status: api.ConnectionStatus.connecting, errorMessage: null);
    
    try {
      if (Platform.isAndroid) {
        // Request permissions
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();

        final scanStatus = statuses[Permission.bluetoothScan];
        final connectStatus = statuses[Permission.bluetoothConnect];
        final locationStatus = statuses[Permission.location];

        if (scanStatus?.isDenied == true || 
            connectStatus?.isDenied == true || 
            locationStatus?.isDenied == true) {
          state = state.copyWith(
            status: api.ConnectionStatus.error, 
            errorMessage: "Permissions denied. Please grant Bluetooth and Location permissions."
          );
          return;
        }

        if (scanStatus?.isPermanentlyDenied == true || 
            connectStatus?.isPermanentlyDenied == true || 
            locationStatus?.isPermanentlyDenied == true) {
          state = state.copyWith(
            status: api.ConnectionStatus.error, 
            errorMessage: "Permissions permanently denied. Please enable them in settings."
          );
          openAppSettings();
          return;
        }
      }

      await api.connectToMuse();
      state = state.copyWith(status: api.ConnectionStatus.connected);
      _startDataPolling();
    } catch (e) {
      state = state.copyWith(status: api.ConnectionStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> disconnect() async {
    _timer?.cancel();
    try {
      await api.disconnectMuse();
      state = state.copyWith(status: api.ConnectionStatus.disconnected);
    } catch (e) {
      state = state.copyWith(status: api.ConnectionStatus.error, errorMessage: e.toString());
    }
  }

  void _startDataPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (state.status != api.ConnectionStatus.connected) {
        timer.cancel();
        return;
      }
      try {
        final data = await api.getLatestData(numSamples: 256);
        
        SignalQuality quality = SignalQuality.none;
        if (data.data.isNotEmpty && data.data[0].isNotEmpty) {
          double stdDev = calculateStdDev(data.data[0]);
          // Simple heuristic for Muse S signal quality
          if (stdDev < 1.0 || stdDev > 200.0) {
            quality = SignalQuality.poor;
          } else if (stdDev < 50.0) {
            quality = SignalQuality.good;
          } else {
            quality = SignalQuality.fair;
          }
        }

        state = state.copyWith(eegData: data.data, signalQuality: quality);
      } catch (e) {
        debugPrint("Error fetching data: $e");
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final museProvider = StateNotifierProvider<MuseStateNotifier, MuseState>((ref) {
  return MuseStateNotifier();
});

class MuseConnectionScreen extends ConsumerWidget {
  const MuseConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muse = ref.watch(museProvider);
    final notifier = ref.read(museProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MuseStream'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(muse: muse),
            const SizedBox(height: 20),
            if (muse.status == api.ConnectionStatus.connected && muse.eegData.isNotEmpty)
              Expanded(
                child: _EegChart(data: muse.eegData[0]), // Show first channel
              )
            else
              const Expanded(
                child: Center(
                  child: Text("Waiting for data..."),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: muse.status == api.ConnectionStatus.connecting
                  ? null
                  : (muse.status == api.ConnectionStatus.connected
                      ? notifier.disconnect
                      : notifier.connect),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                muse.status == api.ConnectionStatus.connected ? "Disconnect" : "Connect Muse S",
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final MuseState muse;
  const _StatusCard({required this.muse});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    switch (muse.status) {
      case api.ConnectionStatus.disconnected:
        statusColor = Colors.grey;
        statusText = "Disconnected";
        break;
      case api.ConnectionStatus.connecting:
        statusColor = Colors.orange;
        statusText = "Connecting...";
        break;
      case api.ConnectionStatus.connected:
        statusColor = Colors.green;
        statusText = "Connected";
        break;
      case api.ConnectionStatus.error:
        statusColor = Colors.red;
        statusText = "Error";
        break;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            if (muse.status == api.ConnectionStatus.connected)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Signal Quality: "),
                    Text(
                      muse.signalQuality.name.toUpperCase(),
                      style: TextStyle(
                        color: _getSignalColor(muse.signalQuality),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (muse.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  muse.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getSignalColor(SignalQuality quality) {
    switch (quality) {
      case SignalQuality.good: return Colors.green;
      case SignalQuality.fair: return Colors.orange;
      case SignalQuality.poor: return Colors.red;
      case SignalQuality.none: return Colors.grey;
    }
  }
}

class _EegChart extends StatelessWidget {
  final List<double> data;
  const _EegChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text("Empty data"));

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
            isCurved: true,
            color: Colors.deepPurpleAccent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.deepPurpleAccent.withOpacity(0.1)),
          ),
        ],
      ),
    );
  }
}