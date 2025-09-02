import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'db_helper.dart';

class CoordinatorHomePage extends StatefulWidget {
  final String username;
  const CoordinatorHomePage({super.key, required this.username});

  @override
  State<CoordinatorHomePage> createState() => _CoordinatorHomePageState();
}

class _CoordinatorHomePageState extends State<CoordinatorHomePage> {
  bool advertising = false;
  int connectedCount = 0;

  final Strategy strategy = Strategy.P2P_STAR;
  final String serviceId = 'com.attendance_cit.app';
  final String deviceName = 'Coordinator-${DateTime.now().millisecondsSinceEpoch}';

  final df = DateFormat('yyyy-MM-dd');
  String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _startSession() async {
    try {
      await Permission.location.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothAdvertise.request();
      await Permission.nearbyWifiDevices.request();

      await Nearby().stopDiscovery();
      await Nearby().stopAdvertising();

      final ok = await Nearby().startAdvertising(
        deviceName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endid, payload) async {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                final text = String.fromCharCodes(payload.bytes!);
                await _handlePayload(text);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Received attendance from $endid')),
                  );
                }
              }
            },
            onPayloadTransferUpdate: (endid, upd) {
              // Optional: you can inspect upd.status / upd.bytesTransferred
            },
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() => connectedCount += 1);
          }
        },
        onDisconnected: (id) {
          setState(() => connectedCount = (connectedCount > 0) ? connectedCount - 1 : 0);
        },
      );

      setState(() => advertising = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start advertising')),
        );
      }
    } catch (e) {
      setState(() => advertising = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _stopSession() async {
    await Nearby().stopAdvertising();
    setState(() {
      advertising = false;
      connectedCount = 0;
    });
  }

  // Parse and store
  Future<void> _handlePayload(String text) async {
    // Expect JSON with keys: type, Section, Date, Slot, Records:[{StudentID,Name,RegNo,Status,Time}]
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      if (map['type'] != 'ATT_DATA') return;

      final sectionCode = map['Section'] as String;
      final dateStr = map['Date'] as String;
      final slotStr = map['Slot'] as String;
      final List records = map['Records'] as List;

      // Upsert each student record (replace for same student+date)
      for (final r in records) {
        await DBHelper().upsertAttendance(
          studentId: r['StudentID'] as String,
          sectionCode: sectionCode,
          date: dateStr,
          slot: slotStr,
          status: r['Status'] as String,
          time: r['Time'] as String,
          source: 'coordinator',
        );
      }

      if (mounted) setState(() {}); // refresh list pages if open
    } catch (_) {
      // Ignore malformed payloads
    }
  }

  void _openSection(String code) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CoordinatorSectionDetailPage(sectionCode: code, date: date),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sections = const ['CS-P', 'CSE-O', 'CSE-Q'];
    return Scaffold(
      appBar: AppBar(title: const Text('Coordinator')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text('Date: $date')),
                ElevatedButton(
                  onPressed: advertising ? _stopSession : _startSession,
                  child: Text(advertising ? 'Stop Session' : 'Start Session'),
                ),
                const SizedBox(width: 12),
                Text('Connected: $connectedCount'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: sections.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                title: Text(sections[i]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSection(sections[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoordinatorSectionDetailPage extends StatefulWidget {
  final String sectionCode;
  final String date;
  const CoordinatorSectionDetailPage({super.key, required this.sectionCode, required this.date});

  @override
  State<CoordinatorSectionDetailPage> createState() => _CoordinatorSectionDetailPageState();
}

class _CoordinatorSectionDetailPageState extends State<CoordinatorSectionDetailPage> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> summary = {'total': 0, 'present': 0, 'absent': 0, 'percent': 0.0};

  Future<void> _load() async {
    rows = await DBHelper().getAttendanceForSectionByDate(widget.sectionCode, widget.date);
    summary = await DBHelper().getSectionSummary(widget.sectionCode, widget.date);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.sectionCode} – ${widget.date}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _StatBox(label: 'Total', value: '${summary['total']}'),
                const SizedBox(width: 8),
                _StatBox(label: 'Present', value: '${summary['present']}'),
                const SizedBox(width: 8),
                _StatBox(label: 'Absent', value: '${summary['absent']}'),
                const SizedBox(width: 8),
                _StatBox(label: 'Percent', value: '${(summary['percent'] as double).toStringAsFixed(1)}%'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No data yet'))
                : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return ListTile(
                    title: Text(r['name'] ?? ''),
                    subtitle: Text(r['reg_no'] ?? ''),
                    trailing: Text(
                      r['status'] ?? '',
                      style: TextStyle(
                        color: (r['status'] == 'Present') ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}