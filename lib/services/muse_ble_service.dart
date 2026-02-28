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

  StreamSubscription<List<ScanResult>>? _scanSub;
  final List<StreamSubscription> _charSubs = [];
  Timer? _batteryTimer;

  // Track last seen timestamps for Linux (removeIfGone not supported on Linux)
  final Map<String, DateTime> _deviceLastSeen = {};

  String _deviceName = 'Muse';
  int _channelIndex = 0;
  BluetoothCharacteristic? _controlChar;

  Future<void> startScan() async {
    if (FlutterBluePlus.isScanningNow) return;

    await _requestPermissions();

    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    // For Linux: use manual device tracking since removeIfGone isn't supported
    // For Android/iOS: use built-in removeIfGone feature
    final bool isMobile = Platform.isAndroid || Platform.isIOS;

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      final now = DateTime.now();

      // Linux: manually track device last seen times
      if (!isMobile) {
        // Update timestamps for all seen devices
        for (final r in results) {
          _deviceLastSeen[r.device.remoteId.str] = now;
        }
        // Remove devices not seen in 30 seconds
        _deviceLastSeen
            .removeWhere((id, time) => now.difference(time).inSeconds > 30);
      }

      // Filter to Muse devices, optionally also filter by last seen on Linux
      var museResults = results
          .where((r) => r.device.platformName.toLowerCase().contains('muse'));

      // Linux: only include devices we've seen recently
      if (!isMobile) {
        museResults = museResults
            .where((r) => _deviceLastSeen.containsKey(r.device.remoteId.str));
      }

      final museDevices = museResults.map((r) => r.device).toList();

      _museDevices.clear();
      _museDevices.addAll(museDevices);
      _museDevicesController.add(List.from(_museDevices));
    });

    print('[SCAN] Starting continuous scan on ${Platform.operatingSystem}...');

    // Build scan arguments based on platform
    // - Android/iOS: use removeIfGone (built-in)
    // - Linux: skip removeIfGone (not supported), we do manual filtering above
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: isMobile ? const Duration(seconds: 15) : null,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await stopScan();
    _connectedDevice = device;
    _deviceName = device.platformName;

    print('🔌 [SERVICE] Starting full connection to ${device.platformName}');

    try {
      await _connect(device);
      print('✅ [SERVICE] Full connection + streaming setup COMPLETED');
    } catch (e, st) {
      print('❌ [SERVICE] Connection FAILED: $e');
      print('   Stack: $st');
      _connectedDevice = null;
      rethrow;
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _batteryTimer?.cancel();
    // Clear device tracking on Linux
    _deviceLastSeen.clear();
  }

  void disconnect() {
    _batteryTimer?.cancel();
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    for (final sub in _charSubs) sub.cancel();
    _charSubs.clear();
    stopScan();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      print('[PERM] Requesting Bluetooth + Location permissions...');
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse
      ].request();
    } else {
      print('[PERM] Skipping permissions — desktop');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    print('[CONNECT] 1. Connecting...');
    await device.connect(
        timeout: const Duration(seconds: 25),
        license: License.free,
        autoConnect: false);
    print('[CONNECT] 2. ✅ Connected');

    print('[CONNECT] 5. Detecting model...');
    var model = await rust_parser.getMuseModelFromName(name: _deviceName);
    if (model == rust.MuseModel.unknown) {
      model = rust.MuseModel.museS;
      print('[CONNECT] 6. Forcing model to MuseS');
    } else {
      print('[CONNECT] 6. Model detected: $model');
    }
    await rust_parser.initMuseParser(model: model);
    print('[CONNECT] 7. Parser initialized');

    final services = await device.discoverServices();
    print('[CONNECT] 8. Found ${services.length} services');

    BluetoothCharacteristic? controlChar;
    List<BluetoothCharacteristic> dataChars = [];

    for (final service in services) {
      final uuid = service.uuid.toString().toLowerCase();
      if (uuid.contains('fe8d') || uuid.contains('273e')) {
        for (final char in service.characteristics) {
          final cUuid = char.uuid.toString().toLowerCase();
          if (char.properties.notify || char.properties.indicate) {
            dataChars.add(char);
            print('[CONNECT] 11. Data char: $cUuid');
          }
          if (char.properties.write || char.properties.writeWithoutResponse) {
            controlChar = char;
            print('[CONNECT] 12. Control char: $cUuid');
          }
        }
      }
    }

    _controlChar = controlChar;

    if (controlChar != null) {
      print(
          '[CONNECT] 13. Sending exact BrainFlow startup sequence from muse.cpp...');

      var res = await _sendCommand(controlChar, 'h');
      if (!res) {
        print('[CONNECT] FAILED: command "h" failed, aborting sequence');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      res = await _sendCommand(controlChar, 'v1');
      if (!res) {
        print('[CONNECT] FAILED: command "v1" failed, aborting sequence');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      res = await _sendCommand(controlChar, 'p21');
      if (!res) {
        print('[CONNECT] FAILED: command "p21" failed, aborting sequence');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      res = await _sendCommand(controlChar, 'd');
      if (!res) {
        print('[CONNECT] FAILED: command "d" failed, aborting sequence');
        return;
      }
      print('[CONNECT] 14. Startup sequence sent (h → v1 → p21 → d)');
    }

    print(
        '[CONNECT] 15. Subscribing to ${dataChars.length} data characteristics...');
    _channelIndex = 0;
    for (final char in dataChars) {
      final channelIdx = _channelIndex;
      final success = await char.setNotifyValue(true);
      print('[CONNECT] 16. Subscribed to ch $channelIdx → success: $success');

      final sub = char.onValueReceived.listen((value) async {
        print(
            '[DATA] ← ch $channelIdx | ${value.length} bytes | hex: ${value.take(20).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        if (value.isNotEmpty) {
          final processed = await rust_parser.parseMusePacket(
              channel: channelIdx, data: value);
          print('[DATA] Parser returned ${processed.length} packets');
          for (final p in processed) {
            _dataController.add(p);
            print('[DATA] Emitted → battery=${p.battery.toStringAsFixed(0)}%');
          }
        }
      });
      _charSubs.add(sub);
      _channelIndex++;
    }

    print('[CONNECT] 17. Waiting 8 seconds for Muse to start streaming...');
    await Future.delayed(const Duration(seconds: 8));

    _batteryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_controlChar != null) {
        print('[BATTERY] Sending status command "s"...');
        await _sendCommand(_controlChar!, 's');
      }
    });

    print(
        '🎉 [CONNECT] SUCCESS — MuseS-6235 should now be streaming live data!');
  }

  Future<bool> _sendCommand(BluetoothCharacteristic char, String cmd) async {
    try {
      final len = cmd.length;
      final formatted = List<int>.filled(len + 2, 0);
      formatted[0] = len + 1;
      for (var i = 0; i < len; i++) {
        formatted[i + 1] = cmd.codeUnitAt(i);
      }
      formatted[len + 1] = 10;
      await char.write(formatted, withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 80));
      return true;
    } catch (e) {
      print('[COMMAND] Failed "$cmd": $e');
      return false;
    }
  }
}
