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

  List<BluetoothDevice> _devices = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  BluetoothDevice? _connectedDevice;
  String _selectedSensor = 'TP9';
  int _expectedPacketNum = 0;
  int _missedPackets = 0;
  int _receivedPackets = 0;

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

  @override
  void initState() {
    super.initState();
    _sub = _service.processedStream.listen(_onData);
    _startScan();
  }

  void _onData(rust.MuseProcessedData data) {
    setState(() {
      _history.add(data);
      if (_history.length > 256) _history.removeAt(0);

      final pkgNum = _receivedPackets % 256;
      if (_expectedPacketNum > 0 && pkgNum != _expectedPacketNum) {
        _missedPackets++;
      }
      _expectedPacketNum = (_receivedPackets + 1) % 256;
      _receivedPackets++;
    });
  }

  void _startScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _devices = results
            .where((r) => r.device.platformName.toLowerCase().contains('muse'))
            .map((r) => r.device)
            .toList();
      });
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _scanSub?.cancel();
    await _service.startScanAndConnect();
    setState(() {
      _connectedDevice = device;
      _history.clear();
      _receivedPackets = 0;
      _missedPackets = 0;
    });
  }

  String get _signalQuality {
    if (_receivedPackets < 10) return 'waiting...';
    final lossPercent = (_missedPackets / _receivedPackets) * 100;
    if (lossPercent < 5) return 'good';
    if (lossPercent < 15) return 'medium';
    return 'poor';
  }

  Color get _signalColor {
    switch (_signalQuality) {
      case 'good':
        return Colors.green;
      case 'medium':
        return Colors.yellow;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
  void dispose() {
    _sub.cancel();
    _scanSub?.cancel();
    _service.disconnect();
    super.dispose();
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
                setState(() => _connectedDevice = null);
                _startScan();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_connectedDevice == null)
            _buildDeviceList()
          else
            _buildConnectedView(),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Expanded(
      child: _devices.isEmpty
          ? const Center(child: Text('Scanning for Muse devices...'))
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.platformName.isEmpty
                      ? 'Unknown Muse'
                      : device.platformName),
                  subtitle: Text(device.remoteId.str),
                  onTap: () => _connectToDevice(device),
                );
              },
            ),
    );
  }

  Widget _buildConnectedView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedSensor,
                  isExpanded: true,
                  items: _availableSensors
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSensor = v!),
                ),
              ),
            ],
          ),
        ),
        _buildSignalQuality(),
        Expanded(
          child: Padding(
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
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildSignalQuality() {
    final quality = _signalQuality;
    final color = _signalColor;
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('/',
              style: TextStyle(
                  color: Colors.red[300],
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          Text('‾‾',
              style: TextStyle(
                  color: Colors.yellow[300],
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          Text('\\',
              style: TextStyle(
                  color: Colors.green[300],
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Text(quality,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Signal: ${_signalQuality.toUpperCase()}',
              style: TextStyle(color: _signalColor)),
          Text(
              'Packets: $_receivedPackets${_missedPackets > 0 ? ' (+$_missedPackets lost)' : ''}'),
          Text('Battery: --%', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
