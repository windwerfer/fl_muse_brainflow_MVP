import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform; // ← this makes it desktop-safe

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../src/rust/muse_types.dart' as rust;
import '../src/rust/muse_parser.dart' as rust_parser;

class MuseBleService {
  static final MuseBleService instance = MuseBleService._();
  MuseBleService._();

  final _dataController = StreamController<rust.MuseProcessedData>.broadcast();
  Stream<rust.MuseProcessedData> get processedStream => _dataController.stream;

  final _museDevicesController =
      StreamController<List<BluetoothDevice>>.broadcast();
  Stream<List<BluetoothDevice>> get museDevicesStream =>
      _museDevicesController.stream;

  final List<BluetoothDevice> _museDevices = [];
  List<BluetoothDevice> get museDevices => _museDevices;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  StreamSubscription<List<ScanResult>>? _scanSub;
  final List<StreamSubscription> _charSubs = [];

  String _deviceName = 'Muse';
  int _channelIndex = 0;

  // ─────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;

    await _requestPermissions(); // now safe on Linux

    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      final museDevices = results
          .where((r) => r.device.platformName.toLowerCase().contains('muse'))
          .map((r) => r.device)
          .toList();

      _museDevices.clear();
      _museDevices.addAll(museDevices);
      _museDevicesController.add(List.from(_museDevices));
    });

    print('[SCAN] Starting continuous scan on ${Platform.operatingSystem}...');
    await FlutterBluePlus.startScan(
      timeout: null,
      removeIfGone: const Duration(seconds: 30),
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await stopScan();
    _connectedDevice = device;
    _deviceName = device.platformName;
    await _connect(device);
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
  }

  // ─────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      print('[PERM] Requesting Bluetooth + Location permissions...');
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    } else {
      print(
          '[PERM] Skipping permissions — desktop (${Platform.operatingSystem})');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    print('[SERVICE] Connecting to ${device.platformName}...');
    await device.connect(license: License.free, autoConnect: false);
    await device.requestMtu(512);

    final model = await rust_parser.getMuseModelFromName(name: _deviceName);
    print('Detected model: $model');
    await rust_parser.initMuseParser(model: model);

    final services = await device.discoverServices();
    BluetoothCharacteristic? controlChar;
    List<BluetoothCharacteristic> dataChars = [];

    for (final service in services) {
      final uuid = service.uuid.toString().toLowerCase();
      if (uuid.contains('fe8d') || uuid.contains('273e')) {
        for (final char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate)
            dataChars.add(char);
          if (char.properties.write || char.properties.writeWithoutResponse)
            controlChar = char;
        }
      }
    }

    if (controlChar != null) {
      await _sendCommand(controlChar, 'h');
      await _sendCommand(controlChar, 'p1035');
      await _sendCommand(controlChar, 'dc001');
      await Future.delayed(const Duration(milliseconds: 300));
      await _sendCommand(controlChar, 'dc001');
    }

    _channelIndex = 0;
    for (final char in dataChars) {
      final channelIdx = _channelIndex;
      await char.setNotifyValue(true);
      final sub = char.onValueReceived.listen((value) async {
        if (value.isNotEmpty) {
          final processed = await rust_parser.parseMusePacket(
              channel: channelIdx, data: value);
          for (final p in processed) _dataController.add(p);
        }
      });
      _charSubs.add(sub);
      _channelIndex++;
    }
    print('✅ $_deviceName connected & streaming (${_channelIndex} channels)');
  }

  Future<void> _sendCommand(BluetoothCharacteristic char, String cmd) async {
    await char.write(utf8.encode(cmd), withoutResponse: true);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  void disconnect() {
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    for (final sub in _charSubs) sub.cancel();
    _charSubs.clear();
    stopScan();
  }
}
