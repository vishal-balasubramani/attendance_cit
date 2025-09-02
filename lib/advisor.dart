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
  bool loading = true;
  bool discovering = false;

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
    // Default all Present
    final map = <String, String>{};
    for (var s in list) {
      map[s['id'] as String] = 'Present';
    }
    setState(() {
      students = list;
      status = map;
      loading = false;
    });
  }

  Future<void> _markAll(String newStatus) async {
    final map = <String, String>{};
    for (var s in students) {
      map[s['id'] as String] = newStatus;
    }
    setState(() => status = map);
  }

  // Save locally so advisor device also has a record (and to support “retry send” UX if you add it later)
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attendance sent to Coordinator')),
                    );
                    Navigator.pop(context); // end session for Advisor
                  }
                }
              },
              onDisconnected: (id) {},
            );
          }
        },
        onEndpointLost: (id) {},
      );

      // Add a discovery timeout so it doesn’t hang forever
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
                return ListTile(
                  title: Text('${s['name']}'),
                  subtitle: Text('${s['reg_no']}'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (st == 'Absent') ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        status[id] = (st == 'Present') ? 'Absent' : 'Present';
                      });
                    },
                    child: Text(st == 'Present' ? 'PRESENT' : 'ABSENT'),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: discovering ? null : _submitToCoordinator,
                icon: const Icon(Icons.send),
                label: Text(discovering ? 'Sending…' : 'Submit Attendance'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
            ),
          ),
        ],
      ),

    );
  }
}