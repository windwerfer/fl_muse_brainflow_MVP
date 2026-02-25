import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../src/rust/muse_types.dart' as rust;
import '../src/rust/muse_parser.dart' as rust_parser;

class MuseBleService {
  static final MuseBleService instance = MuseBleService._();
  MuseBleService._();

  final _dataController = StreamController<rust.MuseProcessedData>.broadcast();
  Stream<rust.MuseProcessedData> get processedStream => _dataController.stream;

  BluetoothDevice? _device;
  StreamSubscription? _scanSub;
  final List<StreamSubscription> _charSubs = [];
  String _deviceName = 'Muse';
  int _channelIndex = 0;

  Future<void> startScanAndConnect() async {
    await _requestPermissions();

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        if (result.device.platformName.toLowerCase().contains('muse')) {
          FlutterBluePlus.stopScan();
          _deviceName = result.device.platformName;
          await _connect(result.device);
          break;
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse
    ].request();
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false);
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
          if (char.properties.notify || char.properties.indicate) {
            dataChars.add(char);
          }
          if (char.properties.write || char.properties.writeWithoutResponse) {
            controlChar = char;
          }
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
            channel: channelIdx,
            data: value,
          );
          for (final p in processed) {
            _dataController.add(p);
          }
        }
      });
      _charSubs.add(sub);
      _channelIndex++;
    }

    print('✅ $_deviceName connected & streaming (ch: $_channelIndex)');
  }

  Future<void> _sendCommand(BluetoothCharacteristic char, String cmd) async {
    await char.write(utf8.encode(cmd), withoutResponse: true);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  void disconnect() {
    _device?.disconnect();
    for (final sub in _charSubs) {
      sub.cancel();
    }
    _charSubs.clear();
    _scanSub?.cancel();
  }
}
