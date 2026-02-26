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
  final List<rust.MuseProcessedData> _history = [];
  late StreamSubscription<rust.MuseProcessedData> _sub;
  late StreamSubscription<List<BluetoothDevice>> _devicesSub;

  final _scrollController = ScrollController();
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
        _history.clear();
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
    _devicesSub.cancel();
    _service.disconnect();
    super.dispose();
  }
}
