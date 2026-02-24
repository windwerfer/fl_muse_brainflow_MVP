import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'services/muse_ble_service.dart';
import 'src/rust/frb_generated.dart'
    as rust; // ← relative from lib/ (most common)

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

  @override
  void initState() {
    super.initState();
    _sub = _service.processedStream.listen((data) {
      setState(() {
        _history.add(data);
        if (_history.length > 400) _history.removeAt(0);
      });
    });
    _service.startScanAndConnect();
  }

  @override
  void dispose() {
    _sub.cancel();
    _service.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Muse S Live — 7ch EEG + SpO2')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'SpO2: ${_history.isNotEmpty && _history.last.spo2 != null ? _history.last.spo2!.toStringAsFixed(1) : "---"} %',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: _history.length.toDouble(),
                  minY: -80,
                  maxY: 80,
                  lineBarsData: List.generate(7, (ch) {
                    final spots = _history.asMap().entries.map((e) {
                      final idx = e.key.toDouble();
                      final channelData = e.value.eeg;
                      final val = (ch < channelData.length &&
                              channelData[ch].isNotEmpty)
                          ? channelData[ch].last
                          : 0.0;
                      return FlSpot(idx, val.clamp(-80, 80));
                    }).toList();
                    return LineChartBarData(
                      spots: spots,
                      color: Colors.primaries[ch],
                      isCurved: true,
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                    );
                  }),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: true),
                  gridData: const FlGridData(show: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
