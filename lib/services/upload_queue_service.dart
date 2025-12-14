import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'api_service.dart';

class UploadQueueService {
  static Database? _database;
  static const String _tableName = 'upload_queue';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/dakar301_queue.db';

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            title TEXT,
            created_at TEXT NOT NULL,
            status TEXT DEFAULT 'pending'
          )
        ''');
      },
    );
  }

  // Add a file to the upload queue
  static Future<int> addToQueue(String filePath, String fileType, {String? title}) async {
    final db = await database;

    // Copy file to app documents directory for persistence
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = filePath.split('/').last;
    final newPath = '${appDir.path}/queue/$fileName';

    // Create queue directory if it doesn't exist
    final queueDir = Directory('${appDir.path}/queue');
    if (!await queueDir.exists()) {
      await queueDir.create(recursive: true);
    }

    // Copy file
    await File(filePath).copy(newPath);

    return await db.insert(_tableName, {
      'file_path': newPath,
      'file_type': fileType,
      'title': title ?? fileName,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  // Get all pending uploads
  static Future<List<Map<String, dynamic>>> getPendingUploads() async {
    final db = await database;
    return await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  // Get queue count
  static Future<int> getQueueCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE status = ?',
      ['pending'],
    );
    return result.first['count'] as int;
  }

  // Mark upload as completed
  static Future<void> markAsCompleted(int id) async {
    final db = await database;

    // Get file path before deleting
    final records = await db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    if (records.isNotEmpty) {
      final filePath = records.first['file_path'] as String;
      // Delete the queued file
      try {
        await File(filePath).delete();
      } catch (_) {}
    }

    // Remove from database
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  // Mark upload as failed
  static Future<void> markAsFailed(int id) async {
    final db = await database;
    await db.update(
      _tableName,
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Process the upload queue
  static Future<int> processQueue() async {
    final pending = await getPendingUploads();
    int successCount = 0;

    for (final item in pending) {
      final id = item['id'] as int;
      final filePath = item['file_path'] as String;
      final fileType = item['file_type'] as String;
      final title = item['title'] as String?;

      final file = File(filePath);
      if (!await file.exists()) {
        await markAsCompleted(id); // Remove if file doesn't exist
        continue;
      }

      Map<String, dynamic>? result;
      if (fileType == 'video') {
        result = await ApiService.uploadVideo(file, title: title);
      } else {
        result = await ApiService.uploadPhoto(file, title: title);
      }

      if (result != null) {
        await markAsCompleted(id);
        successCount++;
      }
    }

    return successCount;
  }
}
