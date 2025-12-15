import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class QueueItem {
  final String id;
  final String filePath;
  final String fileType;
  final String title;
  final DateTime createdAt;
  final String? stage;
  final String? category;

  QueueItem({
    required this.id,
    required this.filePath,
    required this.fileType,
    required this.title,
    required this.createdAt,
    this.stage,
    this.category,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileType': fileType,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'stage': stage,
    'category': category,
  };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'],
    filePath: json['filePath'],
    fileType: json['fileType'],
    title: json['title'],
    createdAt: DateTime.parse(json['createdAt']),
    stage: json['stage'],
    category: json['category'],
  );
}

class QueueService {
  static const String _queueKey = 'upload_queue';

  // Get queue directory
  static Future<Directory> _getQueueDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory('${appDir.path}/queue');
    if (!await queueDir.exists()) {
      await queueDir.create(recursive: true);
    }
    return queueDir;
  }

  // Save queue to SharedPreferences
  static Future<void> _saveQueue(List<QueueItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = queue.map((item) => item.toJson()).toList();
    await prefs.setString(_queueKey, jsonEncode(jsonList));
  }

  // Load queue from SharedPreferences
  static Future<List<QueueItem>> getQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_queueKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => QueueItem.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // Get queue count
  static Future<int> getQueueCount() async {
    final queue = await getQueue();
    return queue.length;
  }

  // Add file to queue (legacy)
  static Future<void> addToQueue(String filePath, String fileType, {String? title}) async {
    await addToQueueWithMetadata(filePath, fileType, null, null, title: title);
  }

  // Add file to queue with stage and category metadata
  static Future<void> addToQueueWithMetadata(
    String filePath,
    String fileType,
    String? stage,
    String? category, {
    String? title,
  }) async {
    try {
      final queueDir = await _getQueueDir();
      final fileName = filePath.split('/').last;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final newPath = '${queueDir.path}/${id}_$fileName';

      // Copy file to queue directory
      await File(filePath).copy(newPath);

      // Add to queue list
      final queue = await getQueue();
      queue.add(QueueItem(
        id: id,
        filePath: newPath,
        fileType: fileType,
        title: title ?? fileName,
        createdAt: DateTime.now(),
        stage: stage,
        category: category,
      ));

      await _saveQueue(queue);
    } catch (e) {
      // Silently fail
    }
  }

  // Remove item from queue
  static Future<void> removeFromQueue(String id) async {
    final queue = await getQueue();
    final item = queue.firstWhere((i) => i.id == id, orElse: () => throw Exception('Not found'));

    // Delete file
    try {
      await File(item.filePath).delete();
    } catch (_) {}

    // Remove from list
    queue.removeWhere((i) => i.id == id);
    await _saveQueue(queue);
  }

  // Process queue - upload all pending files
  static Future<int> processQueue() async {
    final queue = await getQueue();
    if (queue.isEmpty) return 0;

    int successCount = 0;

    for (final item in queue) {
      final file = File(item.filePath);
      if (!await file.exists()) {
        await removeFromQueue(item.id);
        continue;
      }

      Map<String, dynamic>? result;
      if (item.fileType == 'video') {
        result = await ApiService.uploadVideo(
          file,
          title: item.title,
          stage: item.stage,
          category: item.category,
        );
      } else {
        result = await ApiService.uploadPhoto(
          file,
          title: item.title,
          stage: item.stage,
          category: item.category,
        );
      }

      if (result != null) {
        await removeFromQueue(item.id);
        successCount++;
      }
    }

    return successCount;
  }

  // Check if server is reachable
  static Future<bool> isServerReachable() async {
    return await ApiService.checkConnection();
  }
}
