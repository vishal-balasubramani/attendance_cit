import 'package:flutter/material.dart';
import 'advisor.dart';
import 'coordinator.dart';
import 'db_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm up DB
  await DBHelper().database;

  // 🔥 Clear attendance table at startup (for testing only)
  await DBHelper().clearAttendance();

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Attendance',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const RolePickerPage(),
    );
  }
}

class RolePickerPage extends StatelessWidget {
  const RolePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('College Attendance'),
        actions: [
          IconButton(
            tooltip: "Clear attendance (testing)",
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              await DBHelper().clearAttendance();
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Attendance table cleared ✅")),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.school, size: 72, color: Colors.blue),
            const SizedBox(height: 24),
            const Text('Select Role',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _roleBtn(context, 'Advisor', Icons.person, 'advisor'),
            const SizedBox(height: 12),
            _roleBtn(context, 'Coordinator', Icons.group, 'coordinator'),
            const SizedBox(height: 12),
            _roleBtn(context, 'HOD (view only)', Icons.badge, 'hod'),
          ],
        ),
      ),
    );
  }

  Widget _roleBtn(BuildContext ctx, String text, IconData icon, String role) {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => LoginPage(role: role)),
        );
      },
      icon: Icon(icon),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final String role; // advisor/coordinator/hod
  const LoginPage({super.key, required this.role});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userC = TextEditingController();
  final passC = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    final row = await DBHelper().auth(
      userC.text.trim(),
      passC.text.trim(),
      widget.role == 'hod' ? 'hod' : widget.role,
    );
    setState(() {
      loading = false;
    });
    if (row == null) {
      setState(() => error = 'Invalid credentials for role ${widget.role}');
      return;
    }

    if (widget.role == 'advisor') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => AdvisorHomePage(username: row['username'])),
      );
    } else if (widget.role == 'coordinator') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => CoordinatorHomePage(username: row['username'])),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HodPlaceholderPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Login – ${widget.role.toUpperCase()}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
                controller: userC,
                decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 12),
            TextField(
              controller: passC,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: loading ? null : _login,
              child: Text(loading ? 'Signing in…' : 'Login'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class HodPlaceholderPage extends StatelessWidget {
  const HodPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HOD – Coming Soon')),
      body: const Center(
        child: Text(
          'HOD read-only dashboards (today + past dates)\n'
              'will reuse the same SQLite data.\n'
              'For demo, use Coordinator view.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}