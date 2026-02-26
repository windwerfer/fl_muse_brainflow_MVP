import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/muse_ble_service.dart';
import 'src/rust/muse_types.dart' as rust;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: const MuseChartScreen(),
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
      );
}

class MuseChartScreen extends StatefulWidget {
  const MuseChartScreen({super.key});
  @override
  State<MuseChartScreen> createState() => _MuseChartScreenState();
}

class _MuseChartScreenState extends State<MuseChartScreen> {
  final _service = MuseBleService.instance;
  final List<rust.MuseProcessedData> _history = [];
  late StreamSubscription<rust.MuseProcessedData> _sub;

  final _scrollController = ScrollController();
  List<BluetoothDevice> _devices = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;
  String _selectedSensor = 'TP9';
  double _battery = -1;

  static const List<String> _eegChannels = [
    'TP9',
    'AF7',
    'AF8',
    'TP10',
    'RightAUX',
    'FPz',
    'AUX_L'
  ];
  static const List<String> _ppgChannels = ['PPG_IR', 'PPG_RED', 'PPG_NIR'];
  static const List<String> _otherSensors = [
    'SpO2',
    'Signal',
    'Mindfulness',
    'Restfulness',
    'Alpha',
    'Beta',
    'Gamma',
    'Delta',
    'Theta',
    'Accel_X',
    'Accel_Y',
    'Accel_Z',
    'Gyro_X',
    'Gyro_Y',
    'Gyro_Z'
  ];
  void _onData(rust.MuseProcessedData data) {
    if (mounted) {
      setState(() {
        _history.add(data);
        if (_history.length > 256) {
          _history.removeAt(0);
        }
        _battery = data.battery;
      });
    }
  }

  // New: listen to Bluetooth adapter so we auto-start when BT turns on
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _sub = _service.processedStream.listen(_onData);

    // Debug: show Bluetooth state changes
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      print('[BLE] Adapter state changed → $state');
      if (state == BluetoothAdapterState.on) {
        _startScan();
      }
    });

    FlutterBluePlus.setLogLevel(LogLevel.verbose); // ← remove after debugging
    _startScan();
  }

  // ─────────────────────────────────────────────────────────────
  // FIXED scanning — rock-solid, no flicker, follows 2026 best practice
  // ─────────────────────────────────────────────────────────────
  void _startScan() async {
    if (_isScanning) return;
    _isScanning = true;

    print('[SCAN] Stopping previous scan...');
    await FlutterBluePlus.stopScan();

    // Subscribe FIRST (important!)
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      print('[SCAN] Live results → ${results.length} devices');
      // Optional: print all devices for debugging (remove later)
      // for (final r in results) {
      //   print('   • ${r.device.platformName} (${r.device.remoteId.str})');
      // }

      final museDevices = results
          .where((r) => r.device.platformName.toLowerCase().contains('muse'))
          .map((r) => r.device)
          .toList();

      if (mounted) {
        setState(() => _devices = museDevices);
      }
    });

    print('[SCAN] Starting continuous scan...');
    await FlutterBluePlus.startScan(
      timeout: null,
      removeIfGone:
          const Duration(seconds: 30), // Muse disappears cleanly after 15 s
      continuousUpdates: true, // REQUIRED for removeIfGone
      androidScanMode:
          AndroidScanMode.lowLatency, // better range/speed on Android
    );
    print('[SCAN] Scan started successfully (continuous mode)');
  }

  // Stop scan before connecting to avoid BLE conflicts
  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    _scanSub?.cancel();

    await _service.startScanAndConnect();
    setState(() {
      _connectedDevice = device;
      _history.clear();
    });
  }

  List<String> get _availableSensors {
    final sensors = <String>[];
    sensors.addAll(_eegChannels);
    sensors.addAll(_ppgChannels);
    sensors.addAll(_otherSensors);
    return sensors;
  }

  List<double> _getSensorData() {
    return _history.map((data) {
      if (_selectedSensor == 'SpO2') {
        return data.spo2 ?? 0;
      } else if (_selectedSensor == 'Signal') {
        return data.signalQuality;
      } else if (_selectedSensor == 'Mindfulness') {
        return data.mindfulness ?? 0;
      } else if (_selectedSensor == 'Restfulness') {
        return data.restfulness ?? 0;
      } else if (_selectedSensor == 'Alpha') {
        return data.alpha ?? 0;
      } else if (_selectedSensor == 'Beta') {
        return data.beta ?? 0;
      } else if (_selectedSensor == 'Gamma') {
        return data.gamma ?? 0;
      } else if (_selectedSensor == 'Delta') {
        return data.delta ?? 0;
      } else if (_selectedSensor == 'Theta') {
        return data.theta ?? 0;
      } else if (_selectedSensor.startsWith('Accel')) {
        final idx = int.tryParse(_selectedSensor.split('_')[1]) ?? 0;
        return data.accel[idx];
      } else if (_selectedSensor.startsWith('Gyro')) {
        final idx = int.tryParse(_selectedSensor.split('_')[1]) ?? 0;
        return data.gyro[idx];
      } else if (_selectedSensor.startsWith('PPG')) {
        final idx = _selectedSensor == 'PPG_IR'
            ? 0
            : (_selectedSensor == 'PPG_RED' ? 1 : 2);
        if (idx < data.ppgIr.length && data.ppgIr.isNotEmpty) {
          return idx == 0
              ? data.ppgIr.last
              : (idx == 1 ? data.ppgRed.last : data.ppgNir.last);
        }
        return 0.0;
      } else {
        final chIdx = _eegChannels.indexOf(_selectedSensor);
        if (chIdx >= 0 &&
            chIdx < data.eeg.length &&
            data.eeg[chIdx].isNotEmpty) {
          return data.eeg[chIdx].last;
        }
        return 0.0;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_connectedDevice?.platformName ?? 'Muse Scanner'),
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _service.disconnect();
                setState(() {
                  _connectedDevice = null;
                  _battery = -1;
                });
                _startScan();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_connectedDevice == null) _buildDeviceList(),
          _buildSensorDropdown(),
          Expanded(child: _buildChart()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Container(
      height: 100,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _devices.isEmpty
          ? const Center(child: Text('Scanning for Muse devices...'))
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.bluetooth, size: 20),
                    title: Text(device.platformName.isEmpty
                        ? 'Unknown Muse'
                        : device.platformName),
                    subtitle: Text(device.remoteId.str),
                    onTap: () => _connectToDevice(device),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildSensorDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButton<String>(
        value: _selectedSensor,
        isExpanded: true,
        items: _availableSensors
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) => setState(() => _selectedSensor = v!),
      ),
    );
  }

  Widget _buildChart() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 256,
          minY: _selectedSensor == 'SpO2'
              ? 80
              : _selectedSensor.startsWith('Accel') ||
                      _selectedSensor.startsWith('Gyro')
                  ? -5
                  : -100,
          maxY: _selectedSensor == 'SpO2'
              ? 100
              : _selectedSensor.startsWith('Accel') ||
                      _selectedSensor.startsWith('Gyro')
                  ? 5
                  : 100,
          lineBarsData: [
            LineChartBarData(
              spots: _getSensorData()
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                  .toList(),
              color: Colors.cyan,
              isCurved: true,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: true),
          gridData: const FlGridData(show: true),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Battery: ${_battery >= 0 ? '${_battery.toInt()}%' : '--%'}',
              style: TextStyle(
                  color: _battery >= 0
                      ? (_battery > 20 ? Colors.green : Colors.red)
                      : Colors.grey)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sub.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    _service.disconnect();
    super.dispose();
  }
}
