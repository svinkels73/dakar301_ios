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
  final DateTime? captureDate; // Date when media was captured (from EXIF/metadata)
  final String? rallyId; // Rally ID for device-specific rally selection

  QueueItem({
    required this.id,
    required this.filePath,
    required this.fileType,
    required this.title,
    required this.createdAt,
    this.stage,
    this.category,
    this.captureDate,
    this.rallyId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileType': fileType,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'stage': stage,
    'category': category,
    'captureDate': captureDate?.toIso8601String(),
    'rallyId': rallyId,
  };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'],
    filePath: json['filePath'],
    fileType: json['fileType'],
    title: json['title'],
    createdAt: DateTime.parse(json['createdAt']),
    stage: json['stage'],
    category: json['category'],
    captureDate: json['captureDate'] != null ? DateTime.tryParse(json['captureDate']) : null,
    rallyId: json['rallyId'],
  );
}

class QueueService {
  static const String _queueKey = 'upload_queue';
  static bool _isProcessing = false; // Lock to prevent concurrent processing

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

  // Add file to queue with stage, category, and rally metadata
  static Future<void> addToQueueWithMetadata(
    String filePath,
    String fileType,
    String? stage,
    String? category, {
    String? title,
    DateTime? captureDate,
    String? rallyId,
  }) async {
    try {
      final queueDir = await _getQueueDir();
      final fileName = filePath.split('/').last;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final newPath = '${queueDir.path}/${id}_$fileName';

      // Copy file to queue directory
      await File(filePath).copy(newPath);

      // Get capture date from file modification time if not provided
      DateTime? mediaCaptureDate = captureDate;
      if (mediaCaptureDate == null) {
        try {
          final file = File(filePath);
          final stat = await file.stat();
          // Use file modification time as capture date fallback
          mediaCaptureDate = stat.modified;
        } catch (_) {}
      }

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
        captureDate: mediaCaptureDate,
        rallyId: rallyId,
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
    // Prevent concurrent processing (causes duplicates)
    if (_isProcessing) {
      return 0;
    }
    _isProcessing = true;

    try {
      final queue = await getQueue();
      if (queue.isEmpty) {
        _isProcessing = false;
        return 0;
      }

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
            captureDate: item.captureDate,
            rallyId: item.rallyId,
          );
        } else {
          result = await ApiService.uploadPhoto(
            file,
            title: item.title,
            stage: item.stage,
            category: item.category,
            captureDate: item.captureDate,
            rallyId: item.rallyId,
          );
        }

        if (result != null) {
          await removeFromQueue(item.id);
          successCount++;
        }
      }

      return successCount;
    } finally {
      _isProcessing = false;
    }
  }

  // Check if server is reachable
  static Future<bool> isServerReachable() async {
    return await ApiService.checkConnection();
  }
}
