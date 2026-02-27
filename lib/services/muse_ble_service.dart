import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

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

  // ===================================================================
  // PUBLIC API
  // ===================================================================

  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;

    await _requestPermissions();

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

    print(
        '🔌 [SERVICE] Starting full connection to ${device.platformName} (${device.remoteId})');

    try {
      await _connect(device);
      print(
          '✅ [SERVICE] Full connection + streaming setup COMPLETED successfully');
    } catch (e, st) {
      print('❌ [SERVICE] Connection FAILED: $e');
      print('   Stack: $st');
      _connectedDevice = null; // important: reset so UI shows list again
      rethrow;
    }
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
  }

  void disconnect() {
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    for (final sub in _charSubs) sub.cancel();
    _charSubs.clear();
    stopScan();
  }

  // ===================================================================
  // PRIVATE HELPERS
  // ===================================================================

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
    print('[CONNECT] 1. Connecting to device (15s timeout)...');
    await device.connect(
      timeout: const Duration(seconds: 45),
      license: License.free,
      autoConnect: false,
    );
    print('[CONNECT] 2. ✅ Connected');

    print('[CONNECT] 3. Requesting MTU...');
    if (Platform.isAndroid) {
      await device.requestMtu(512);
      print('[CONNECT] 4. MTU requested');
    } else {
      print('[CONNECT] 4. Skipping MTU request (Linux/desktop - not needed)');
    }

    print('[CONNECT] 5. Detecting model...');
    final model = await rust_parser.getMuseModelFromName(name: _deviceName);
    print('[CONNECT] 6. Model detected: $model');
    await rust_parser.initMuseParser(model: model);
    print('[CONNECT] 7. Parser initialized');

    print('[CONNECT] 8. Discovering services...');
    final services = await device.discoverServices();
    print('[CONNECT] 9. Found ${services.length} services');

    BluetoothCharacteristic? controlChar;
    List<BluetoothCharacteristic> dataChars = [];

    for (final service in services) {
      final uuid = service.uuid.toString().toLowerCase();
      if (uuid.contains('fe8d') || uuid.contains('273e')) {
        print('[CONNECT] 10. Muse service found: $uuid');
        for (final char in service.characteristics) {
          final cUuid = char.uuid.toString().toLowerCase();
          if (char.properties.notify || char.properties.indicate) {
            dataChars.add(char);
            print('[CONNECT] 11. Data characteristic: $cUuid');
          }
          if (char.properties.write || char.properties.writeWithoutResponse) {
            controlChar = char;
            print('[CONNECT] 12. Control characteristic: $cUuid');
          }
        }
      }
    }

    if (controlChar != null) {
      print('[CONNECT] 13. Sending initialization commands...');
      await _sendCommand(controlChar, 'h');
      await _sendCommand(controlChar, 'p1035');
      await _sendCommand(controlChar, 'dc001');
      await Future.delayed(const Duration(milliseconds: 400));
      await _sendCommand(controlChar, 'dc001');
      print('[CONNECT] 14. Commands sent');
    } else {
      print('[CONNECT] WARNING: No control characteristic found!');
    }

    print(
        '[CONNECT] 15. Subscribing to ${dataChars.length} data characteristics...');
    _channelIndex = 0;
    for (final char in dataChars) {
      final channelIdx = _channelIndex;
      await char.setNotifyValue(true);
      print('[CONNECT] 16. Subscribed to channel $channelIdx');

      final sub = char.onValueReceived.listen((value) async {
        print('[DATA] ← Received ${value.length} bytes on ch $channelIdx');
        if (value.isNotEmpty) {
          final processed = await rust_parser.parseMusePacket(
            channel: channelIdx,
            data: value,
          );
          print('[DATA] Parser returned ${processed.length} packets');
          for (final p in processed) {
            _dataController.add(p);
          }
        }
      });
      _charSubs.add(sub);
      _channelIndex++;
    }

    print('🎉 [CONNECT] SUCCESS — $_deviceName is now streaming!');
  }

  Future<void> _sendCommand(BluetoothCharacteristic char, String cmd) async {
    try {
      await char.write(utf8.encode(cmd), withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      print('[COMMAND] Failed to send "$cmd": $e');
    }
  }
}
