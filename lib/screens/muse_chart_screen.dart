import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/muse_ble_service.dart';
import '../src/rust/muse_types.dart' as rust;

class MuseChartScreen extends StatefulWidget {
  const MuseChartScreen({super.key});
  @override
  State<MuseChartScreen> createState() => _MuseChartScreenState();
}

class _MuseChartScreenState extends State<MuseChartScreen> {
  final _service = MuseBleService.instance;
  late StreamSubscription<rust.MuseProcessedData> _sub;
  late StreamSubscription<List<BluetoothDevice>> _devicesSub;

  final _scrollController = ScrollController();
  String _selectedSensor = 'AF7'; // TP9 (ch0) not present on this device
  double _battery = -1;
  int _signalQuality = 0;

  // <<< CHANGED: Rolling buffer for EEG channel data
  final List<double> _eegHistory = [];
  static const int _maxPoints = 512; // ~2 seconds at 256 Hz — buttery smooth

  // For non-EEG sensors: small rolling buffer (last ~1 second)
  final List<double> _otherSensorHistory = [];
  static const int _maxOtherPoints = 64; // ~1 second at lower sampling rates
  // >>>

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

  // <<< CHANGED: Properly handle all 12 samples per EEG packet + other sensors
  void _onData(rust.MuseProcessedData data) {
    if (!mounted) return;

    // print('[DART] _onData: packetTypes=${data.packetTypes}, eeg.len=${data.eeg.length}');

    setState(() {
      // Handle EEG packets - accumulate ALL 12 samples for rolling buffer
      if (data.packetTypes.contains(rust.MusePacketType.eeg) &&
          data.eeg.isNotEmpty) {
        final int chIdx = _eegChannels.indexOf(_selectedSensor);
        if (chIdx >= 0 && chIdx < data.eeg.length) {
          final List<double> newSamples = data.eeg[chIdx]; // 12 samples!
          if (newSamples.isNotEmpty) {
            // print('[DART] EEG $_selectedSensor ch$chIdx: ${newSamples.length} samples, first=${newSamples.first.toStringAsFixed(2)}');
          }

          for (final sample in newSamples) {
            _eegHistory.add(sample);
          }

          // Keep only the last N points (rolling window)
          if (_eegHistory.length > _maxPoints) {
            _eegHistory.removeRange(0, _eegHistory.length - _maxPoints);
          }
        }
      }

      // Handle other sensors (PPG, Accel, Gyro, etc.) - take latest value
      if (_selectedSensor == 'SpO2' && data.spo2 != null) {
        _otherSensorHistory.add(data.spo2!);
      } else if (_selectedSensor == 'Signal') {
        _otherSensorHistory.add(data.signalQuality);
      } else if (_selectedSensor == 'Mindfulness' && data.mindfulness != null) {
        _otherSensorHistory.add(data.mindfulness!);
      } else if (_selectedSensor == 'Restfulness' && data.restfulness != null) {
        _otherSensorHistory.add(data.restfulness!);
      } else if (_selectedSensor == 'Alpha' && data.alpha != null) {
        _otherSensorHistory.add(data.alpha!);
      } else if (_selectedSensor == 'Beta' && data.beta != null) {
        _otherSensorHistory.add(data.beta!);
      } else if (_selectedSensor == 'Gamma' && data.gamma != null) {
        _otherSensorHistory.add(data.gamma!);
      } else if (_selectedSensor == 'Delta' && data.delta != null) {
        _otherSensorHistory.add(data.delta!);
      } else if (_selectedSensor == 'Theta' && data.theta != null) {
        _otherSensorHistory.add(data.theta!);
      } else if (_selectedSensor.startsWith('Accel') &&
          data.packetTypes.contains(rust.MusePacketType.accel)) {
        const axisMap = {'X': 0, 'Y': 1, 'Z': 2};
        final idx = axisMap[_selectedSensor.split('_')[1]] ?? 0;
        _otherSensorHistory.add(data.accel[idx]);
      } else if (_selectedSensor.startsWith('Gyro') &&
          data.packetTypes.contains(rust.MusePacketType.gyro)) {
        const axisMap = {'X': 0, 'Y': 1, 'Z': 2};
        final idx = axisMap[_selectedSensor.split('_')[1]] ?? 0;
        _otherSensorHistory.add(data.gyro[idx]);
      } else if (_selectedSensor.startsWith('PPG')) {
        if (_selectedSensor == 'PPG_IR' && data.ppgIr.isNotEmpty) {
          _otherSensorHistory.add(data.ppgIr.last);
        } else if (_selectedSensor == 'PPG_RED' && data.ppgRed.isNotEmpty) {
          _otherSensorHistory.add(data.ppgRed.last);
        } else if (_selectedSensor == 'PPG_NIR' && data.ppgNir.isNotEmpty) {
          _otherSensorHistory.add(data.ppgNir.last);
        }
      }

      // Keep non-EEG history bounded
      if (_otherSensorHistory.length > _maxOtherPoints) {
        _otherSensorHistory.removeRange(
            0, _otherSensorHistory.length - _maxOtherPoints);
      }

      // Still update battery/SpO2/status from any packet type
      if (data.battery > 0) _battery = data.battery;
      _signalQuality = data.signalQuality.toInt();
    });
  }
  // >>>

  @override
  void initState() {
    super.initState();
    _sub = _service.processedStream.listen(_onData);
    _devicesSub = _service.museDevicesStream.listen((devices) {
      if (mounted) setState(() {});
    });
    _service.startScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await _service.connectToDevice(device);
    if (mounted) {
      setState(() {
        _eegHistory.clear();
      });
    }
  }

  List<String> get _availableSensors {
    final sensors = <String>[];
    sensors.addAll(_eegChannels);
    sensors.addAll(_ppgChannels);
    sensors.addAll(_otherSensors);
    return sensors;
  }

  // <<< CHANGED: Build chart spots from rolling history
  List<FlSpot> _buildChartSpots() {
    final List<FlSpot> spots = [];

    // Check if selected sensor is an EEG channel
    if (_eegChannels.contains(_selectedSensor)) {
      // Use EEG rolling buffer (12 samples per packet)
      for (int i = 0; i < _eegHistory.length; i++) {
        spots.add(FlSpot(i.toDouble(), _eegHistory[i]));
      }
    } else {
      // Use other sensor history
      for (int i = 0; i < _otherSensorHistory.length; i++) {
        spots.add(FlSpot(i.toDouble(), _otherSensorHistory[i]));
      }
    }

    return spots;
  }

  /// Returns [min, max] Y bounds for the current data, with a fallback.
  (double, double) _computeYRange() {
    final history = _eegChannels.contains(_selectedSensor)
        ? _eegHistory
        : _otherSensorHistory;

    if (history.isEmpty) {
      return _defaultYRange();
    }

    double lo = history.reduce((a, b) => a < b ? a : b);
    double hi = history.reduce((a, b) => a > b ? a : b);

    // Add 10% padding and ensure a minimum span of 10
    final span = (hi - lo).abs().clamp(10.0, double.infinity);
    final pad = span * 0.1;
    return (lo - pad, hi + pad);
  }

  (double, double) _defaultYRange() {
    if (_selectedSensor == 'SpO2') return (80, 100);
    if (_selectedSensor.startsWith('Accel') ||
        _selectedSensor.startsWith('Gyro')) return (-5, 5);
    return (-200, 200); // wide default for EEG μV
  }
  // >>>

  @override
  Widget build(BuildContext context) {
    final connectedDevice = _service.connectedDevice;
    return Scaffold(
      appBar: AppBar(
        title: Text(connectedDevice?.platformName ?? 'Muse Scanner'),
        actions: [
          if (connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _service.disconnect();
                setState(() {
                  _battery = -1;
                });
                _service.startScan();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (connectedDevice == null) _buildDeviceList(),
          _buildSensorDropdown(),
          Expanded(child: _buildChart()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    final devices = _service.museDevices;
    return Container(
      height: 100,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: devices.isEmpty
          ? const Center(child: Text('Scanning for Muse devices...'))
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
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
    final spots = _buildChartSpots();
    final (minY, maxY) = _computeYRange();
    final maxX = spots.isEmpty ? 256.0 : (spots.length - 1).toDouble();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
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
          Text('Signal: $_signalQuality',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 16),
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
    _devicesSub.cancel();
    _service.disconnect();
    super.dispose();
  }
}
