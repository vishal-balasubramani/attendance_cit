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
    // Expect JSON with keys: type, Section, Date, Slot, Records:[{StudentID,Name,RegNo,Status,ODStatus,Time}]
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
          odStatus: r['ODStatus'] as String? ?? 'Normal',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CumulativeReportPage(date: date),
                ));
              },
              icon: const Icon(Icons.assessment),
              label: const Text('CUMULATIVE REPORT'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
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

class CumulativeReportPage extends StatefulWidget {
  final String date;
  const CumulativeReportPage({super.key, required this.date});

  @override
  State<CumulativeReportPage> createState() => _CumulativeReportPageState();
}

class _CumulativeReportPageState extends State<CumulativeReportPage> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> summary = {'total': 0, 'present': 0, 'absent': 0, 'od': 0, 'percent': 0.0, 'sectionBreakdown': {}};

  Future<void> _load() async {
    rows = await DBHelper().getCumulativeAttendanceByDate(widget.date);
    summary = await DBHelper().getCumulativeSummary(widget.date);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _getDisplayStatus(Map<String, dynamic> record) {
    final status = record['status'] as String? ?? 'Present';
    final odStatus = record['od_status'] as String? ?? 'Normal';

    if (status == 'Absent') {
      return 'Absent';
    } else if (odStatus == 'OD') {
      return 'OD';
    } else {
      return 'Present';
    }
  }

  Color _getStatusColor(String displayStatus) {
    switch (displayStatus) {
      case 'Present':
        return Colors.green;
      case 'Absent':
        return Colors.red;
      case 'OD':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionBreakdown = summary['sectionBreakdown'] as Map<String, Map<String, int>>? ?? {};

    return Scaffold(
      appBar: AppBar(title: Text('Cumulative Report – ${widget.date}')),
      body: Column(
        children: [
          // Overall Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'All Sections Combined',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatBox(label: 'Total', value: '${summary['total']}'),
                    const SizedBox(width: 8),
                    _StatBox(label: 'Present', value: '${summary['present']}'),
                    const SizedBox(width: 8),
                    _StatBox(label: 'Absent', value: '${summary['absent']}'),
                    const SizedBox(width: 8),
                    _StatBox(label: 'OD', value: '${summary['od']}'),
                    const SizedBox(width: 8),
                    _StatBox(label: 'Percent', value: '${(summary['percent'] as double).toStringAsFixed(1)}%'),
                  ],
                ),
              ],
            ),
          ),

          // Section-wise breakdown
          if (sectionBreakdown.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Section-wise Breakdown:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...sectionBreakdown.entries.map((entry) {
                    final sectionCode = entry.key;
                    final data = entry.value;
                    final sectionPercent = data['total']! == 0 ? 0.0 : (data['present']! * 100.0 / data['total']!);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              sectionCode,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(child: Text('T: ${data['total']}')),
                          Expanded(child: Text('P: ${data['present']}')),
                          Expanded(child: Text('A: ${data['absent']}')),
                          Expanded(child: Text('OD: ${data['od']}')),
                          Expanded(child: Text('${sectionPercent.toStringAsFixed(1)}%')),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(height: 1),

          // Detailed student list
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No attendance data yet'))
                : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final displayStatus = _getDisplayStatus(r);
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r['section_code'] ?? '',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(r['name'] ?? ''),
                    subtitle: Text(r['reg_no'] ?? ''),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(displayStatus).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _getStatusColor(displayStatus), width: 1),
                      ),
                      child: Text(
                        displayStatus,
                        style: TextStyle(
                          color: _getStatusColor(displayStatus),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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

class CoordinatorSectionDetailPage extends StatefulWidget {
  final String sectionCode;
  final String date;
  const CoordinatorSectionDetailPage({super.key, required this.sectionCode, required this.date});

  @override
  State<CoordinatorSectionDetailPage> createState() => _CoordinatorSectionDetailPageState();
}

class _CoordinatorSectionDetailPageState extends State<CoordinatorSectionDetailPage> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> summary = {'total': 0, 'present': 0, 'absent': 0, 'od': 0, 'percent': 0.0};

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

  String _getDisplayStatus(Map<String, dynamic> record) {
    final status = record['status'] as String? ?? 'Present';
    final odStatus = record['od_status'] as String? ?? 'Normal';

    if (status == 'Absent') {
      return 'Absent';
    } else if (odStatus == 'OD') {
      return 'OD';
    } else {
      return 'Present';
    }
  }

  Color _getStatusColor(String displayStatus) {
    switch (displayStatus) {
      case 'Present':
        return Colors.green;
      case 'Absent':
        return Colors.red;
      case 'OD':
        return Colors.blue;
      default:
        return Colors.grey;
    }
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
                _StatBox(label: 'OD', value: '${summary['od']}'),
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
                  final displayStatus = _getDisplayStatus(r);
                  return ListTile(
                    title: Text(r['name'] ?? ''),
                    subtitle: Text(r['reg_no'] ?? ''),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(displayStatus).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _getStatusColor(displayStatus), width: 1),
                      ),
                      child: Text(
                        displayStatus,
                        style: TextStyle(
                          color: _getStatusColor(displayStatus),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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