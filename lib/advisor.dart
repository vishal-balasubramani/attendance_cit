import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'db_helper.dart';

class AdvisorHomePage extends StatefulWidget {
  final String username;
  const AdvisorHomePage({super.key, required this.username});

  @override
  State<AdvisorHomePage> createState() => _AdvisorHomePageState();
}

class _AdvisorHomePageState extends State<AdvisorHomePage> {
  late Future<List<Map<String, dynamic>>> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = DBHelper().getSections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advisor – Sections')),
      body: FutureBuilder(
        future: _sectionsFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final sections = snap.data as List<Map<String, dynamic>>;
          return ListView.separated(
            itemCount: sections.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = sections[i];
              return ListTile(
                title: Text(s['code']),
                subtitle: Text(s['name']),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AdvisorMarkPage(sectionCode: s['code']),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}

class AdvisorReportPage extends StatefulWidget {
  final String sectionCode;
  final String date;
  const AdvisorReportPage({super.key, required this.sectionCode, required this.date});

  @override
  State<AdvisorReportPage> createState() => _AdvisorReportPageState();
}

class _AdvisorReportPageState extends State<AdvisorReportPage> {
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
      appBar: AppBar(
        title: Text('Report – ${widget.sectionCode}'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'Close Report',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Attendance Report',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Section: ${widget.sectionCode} | Date: ${widget.date}',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No data available'))
                : ListView.separated(
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Sections'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                ),
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
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class AdvisorMarkPage extends StatefulWidget {
  final String sectionCode;
  const AdvisorMarkPage({super.key, required this.sectionCode});

  @override
  State<AdvisorMarkPage> createState() => _AdvisorMarkPageState();
}

class _AdvisorMarkPageState extends State<AdvisorMarkPage> {
  final df = DateFormat('yyyy-MM-dd');
  String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String slot = 'FN';
  List<Map<String, dynamic>> students = [];
  Map<String, String> status = {}; // studentId -> Present/Absent
  Map<String, String> odStatus = {}; // studentId -> Normal/OD
  bool loading = true;
  bool discovering = false;
  bool attendanceSubmitted = false; // Track if attendance has been submitted

  // Nearby
  final Strategy strategy = Strategy.P2P_STAR;
  final String serviceId = 'com.attendance_cit.app';
  Timer? _discoverTimeout;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    final list = await DBHelper().getStudentsBySectionCode(widget.sectionCode);
    // Default all Present and Normal (not OD)
    final statusMap = <String, String>{};
    final odStatusMap = <String, String>{};
    for (var s in list) {
      statusMap[s['id'] as String] = 'Present';
      odStatusMap[s['id'] as String] = 'Normal';
    }
    setState(() {
      students = list;
      status = statusMap;
      odStatus = odStatusMap;
      loading = false;
    });
  }

  Future<void> _markAll(String newStatus) async {
    final statusMap = <String, String>{};
    final odStatusMap = <String, String>{};
    for (var s in students) {
      statusMap[s['id'] as String] = newStatus;
      // Reset OD status when marking all
      odStatusMap[s['id'] as String] = 'Normal';
    }
    setState(() {
      status = statusMap;
      odStatus = odStatusMap;
    });
  }

  // Save locally so advisor device also has a record (and to support "retry send" UX if you add it later)
  Future<void> _saveLocally() async {
    final nowIso = DateTime.now().toIso8601String();
    for (var s in students) {
      final id = s['id'] as String;
      await DBHelper().upsertAttendance(
        studentId: id,
        sectionCode: widget.sectionCode,
        date: date,
        slot: slot,
        status: status[id] ?? 'Present',
        odStatus: odStatus[id] ?? 'Normal',
        time: nowIso,
        source: 'advisor',
      );
    }
  }

  Future<void> _submitToCoordinator() async {
    // 1) Save to local DB (ensures local truth is updated)
    await _saveLocally();

    // 2) Build payload (JSON; robust & easy to parse)
    final records = students.map((s) {
      final id = s['id'] as String;
      return {
        'StudentID': id,
        'Name': s['name'],
        'RegNo': s['reg_no'],
        'Status': status[id] ?? 'Present',
        'ODStatus': odStatus[id] ?? 'Normal',
        'Time': DateTime.now().toIso8601String(),
      };
    }).toList();

    final payload = jsonEncode({
      'type': 'ATT_DATA',
      'Section': widget.sectionCode,
      'Date': date,
      'Slot': slot,
      'Records': records,
    });

    // 3) Nearby send: discover a Coordinator advertising and send once
    try {
      setState(() => discovering = true);

      // Ask permissions (no-op if already granted)
      await Permission.location.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothAdvertise.request();
      await Permission.nearbyWifiDevices.request();

      // Stop any running sessions
      await Nearby().stopDiscovery();
      await Nearby().stopAdvertising();

      bool started = await Nearby().startDiscovery(
        'Advisor-${DateTime.now().millisecondsSinceEpoch}',
        strategy,
        serviceId: serviceId,
        onEndpointFound: (id, name, serviceIdFound) async {
          // We only connect to Coordinator* names
          if (name.startsWith('Coordinator')) {
            // Immediately request connection
            await Nearby().requestConnection(
              'Advisor',
              id,
              onConnectionInitiated: (id, info) async {
                await Nearby().acceptConnection(
                  id,
                  onPayLoadRecieved: (endid, pl) {}, // not expecting responses
                  onPayloadTransferUpdate: (endid, upd) {}, // could add progress
                );
              },
              onConnectionResult: (id, status) async {
                if (status == Status.CONNECTED) {
                  final bytes = Uint8List.fromList(payload.codeUnits);
                  await Nearby().sendBytesPayload(id, bytes);
                  // Optional: small delay then disconnect & stop discovery
                  await Future.delayed(const Duration(milliseconds: 300));
                  await Nearby().disconnectFromEndpoint(id);
                  await Nearby().stopDiscovery();
                  if (mounted) {
                    setState(() => attendanceSubmitted = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attendance sent to Coordinator')),
                    );
                    // Don't pop immediately - let user view report first
                  }
                }
              },
              onDisconnected: (id) {},
            );
          }
        },
        onEndpointLost: (id) {},
      );

      // Add a discovery timeout so it doesn't hang forever
      _discoverTimeout?.cancel();
      _discoverTimeout = Timer(const Duration(seconds: 20), () async {
        if (mounted && discovering) {
          await Nearby().stopDiscovery();
          setState(() => discovering = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No Coordinator found. Make sure session is started.')),
          );
        }
      });

      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Discovery failed. Try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    } finally {
      // When we succeed we already stopped discovery above.
      if (mounted) setState(() => discovering = false);
      _discoverTimeout?.cancel();
    }
  }

  @override
  void dispose() {
    _discoverTimeout?.cancel();
    Nearby().stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text('Mark – ${widget.sectionCode}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text('Date: $date')),
                DropdownButton<String>(
                  value: slot,
                  items: const [
                    DropdownMenuItem(value: 'FN', child: Text('FN')),
                    DropdownMenuItem(value: 'AN', child: Text('AN')),
                  ],
                  onChanged: (v) => setState(() => slot = v!),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ElevatedButton(onPressed: () => _markAll('Present'), child: const Text('Mark All Present')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _markAll('Absent'),
                  child: const Text('Mark All Absent'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: students.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = students[i];
                final id = s['id'] as String;
                final st = status[id] ?? 'Present';
                final od = odStatus[id] ?? 'Normal';
                final isAbsent = st == 'Absent';

                return ListTile(
                  title: Text('${s['name']}'),
                  subtitle: Text('${s['reg_no']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // OD Button - only visible when not absent
                      if (!isAbsent) ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (od == 'OD') ? Colors.blue : Colors.grey[300],
                            foregroundColor: (od == 'OD') ? Colors.white : Colors.black87,
                            minimumSize: const Size(50, 36),
                          ),
                          onPressed: () {
                            setState(() {
                              odStatus[id] = (od == 'Normal') ? 'OD' : 'Normal';
                            });
                          },
                          child: const Text('OD'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Present/Absent Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (st == 'Absent') ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 36),
                        ),
                        onPressed: () {
                          setState(() {
                            status[id] = (st == 'Present') ? 'Absent' : 'Present';
                            // Reset OD status when marking as absent
                            if (status[id] == 'Absent') {
                              odStatus[id] = 'Normal';
                            }
                          });
                        },
                        child: Text(st == 'Present' ? 'PRESENT' : 'ABSENT'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: discovering ? null : _submitToCoordinator,
                    icon: const Icon(Icons.send),
                    label: Text(discovering ? 'Sending…' : 'Submit Attendance'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  ),
                  if (attendanceSubmitted) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AdvisorReportPage(
                            sectionCode: widget.sectionCode,
                            date: date,
                          ),
                        ));
                      },
                      icon: const Icon(Icons.analytics),
                      label: const Text('View Report'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}