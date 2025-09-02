import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'attendance.db');
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE,
            password TEXT,
            role TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE sections (
            id TEXT PRIMARY KEY,
            code TEXT UNIQUE,
            name TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE students (
            id TEXT PRIMARY KEY,
            reg_no TEXT UNIQUE,
            name TEXT,
            gender TEXT,
            quota TEXT,
            section_id TEXT,
            FOREIGN KEY(section_id) REFERENCES sections(id)
          );
        ''');
        await db.execute('''
          CREATE TABLE attendance_records (
            id TEXT PRIMARY KEY,
            student_id TEXT,
            section_id TEXT,
            date TEXT,
            slot TEXT,
            status TEXT, -- Present/Absent
            time TEXT,
            source TEXT, -- advisor/coordinator
            created_at TEXT,
            synced INTEGER DEFAULT 0
          );
        ''');

        // Seed users
        await db.insert('users', {
          'id': 'u1', 'username': 'advisor1', 'password': 'pass123', 'role': 'advisor'
        });
        await db.insert('users', {
          'id': 'u2', 'username': 'coord1', 'password': 'pass123', 'role': 'coordinator'
        });
        await db.insert('users', {
          'id': 'u3', 'username': 'hod1', 'password': 'pass123', 'role': 'hod'
        });

        // Seed sections
        await db.insert('sections', {'id': 's1', 'code': 'CS-P', 'name': 'Computer Science - P'});
        await db.insert('sections', {'id': 's2', 'code': 'CSE-O', 'name': 'CSE - O'});
        await db.insert('sections', {'id': 's3', 'code': 'CSE-Q', 'name': 'CSE - Q'});

        // Seed 10 students per section
        Future<void> seedTen(String sectionId, String prefix) async {
          for (int i = 1; i <= 10; i++) {
            final sid = '${sectionId}_$i';
            await db.insert('students', {
              'id': sid,
              'reg_no': '$prefix${i.toString().padLeft(3, '0')}',
              'name': 'Student $prefix$i',
              'gender': (i % 2 == 0) ? 'F' : 'M',
              'quota': (i % 3 == 0) ? 'MQ' : 'GQ',
              'section_id': sectionId,
            });
          }
        }

        await seedTen('s1', '24CS-P-');
        await seedTen('s2', '24CSE-O-');
        await seedTen('s3', '24CSE-Q-');
      },
    );
  }

  // Dummy Auth
  Future<Map<String, dynamic>?> auth(String username, String password, String role) async {
    final db = await database;
    final res = await db.query(
      'users',
      where: 'username=? AND password=? AND role=?',
      whereArgs: [username, password, role],
      limit: 1,
    );
    return res.isEmpty ? null : res.first;
  }

  Future<List<Map<String, dynamic>>> getSections() async {
    final db = await database;
    return db.query('sections', orderBy: 'code ASC');
  }

  Future<List<Map<String, dynamic>>> getStudentsBySectionCode(String code) async {
    final db = await database;
    final s = await db.query('sections', where: 'code=?', whereArgs: [code], limit: 1);
    if (s.isEmpty) return [];
    final sectionId = s.first['id'] as String;
    return db.query('students', where: 'section_id=?', whereArgs: [sectionId], orderBy: 'reg_no ASC');
  }

  /// ✅ Always overwrite attendance for the same (studentId + date + slot).
  Future<void> upsertAttendance({
    required String studentId,
    required String sectionCode,
    required String date,
    required String slot,
    required String status, // Present/Absent
    required String time,
    required String source, // advisor/coordinator
  }) async {
    final db = await database;

    // Find sectionId
    final s = await db.query('sections', where: 'code=?', whereArgs: [sectionCode], limit: 1);
    if (s.isEmpty) return;
    final sectionId = s.first['id'] as String;

    // ✅ Unique key per (studentId + date + slot)
    final id = '$studentId|$date|$slot';
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'attendance_records',
      {
        'id': id,
        'student_id': studentId,
        'section_id': sectionId,
        'date': date,
        'slot': slot,
        'status': status,
        'time': time,
        'source': source,
        'created_at': now,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAttendanceForSectionByDate(String sectionCode, String date) async {
    final db = await database;
    final s = await db.query('sections', where: 'code=?', whereArgs: [sectionCode], limit: 1);
    if (s.isEmpty) return [];
    final sectionId = s.first['id'] as String;
    final sql = '''
      SELECT st.name, st.reg_no, ar.slot, ar.status, ar.time
      FROM attendance_records ar
      INNER JOIN students st ON st.id = ar.student_id
      WHERE ar.section_id=? AND ar.date=?
      ORDER BY st.reg_no ASC, ar.slot ASC;
    ''';
    return db.rawQuery(sql, [sectionId, date]);
  }

  Future<Map<String, dynamic>> getSectionSummary(String sectionCode, String date) async {
    final rows = await getAttendanceForSectionByDate(sectionCode, date);
    final total = rows.length;
    final present = rows.where((r) => (r['status'] as String) == 'Present').length;
    final absent = total - present;
    final percent = total == 0 ? 0.0 : (present * 100.0 / total);
    return {
      'total': total,
      'present': present,
      'absent': absent,
      'percent': percent,
    };
  }

  /// ✅ Clear attendance (for testing)
  Future<void> clearAttendance() async {
    final db = await database;
    await db.delete('attendance_records');
  }
}