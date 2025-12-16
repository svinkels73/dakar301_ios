import 'dart:io';
import 'package:flutter/services.dart';
import 'queue_service.dart';
import 'api_service.dart';

class IOSBackgroundService {
  static const MethodChannel _channel = MethodChannel('com.dakar301/background');
  static bool _initialized = false;

  /// Initialize the iOS background service
  static Future<void> initialize() async {
    if (!Platform.isIOS || _initialized) return;

    // Set up method call handler for when iOS triggers background fetch
    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
    print('IOSBackgroundService: Initialized');
  }

  /// Handle method calls from iOS native code
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'processQueue':
        return await _processQueueInBackground();
      case 'getQueueCount':
        return await QueueService.getQueueCount();
      default:
        throw PlatformException(
          code: 'UNSUPPORTED',
          message: 'Method ${call.method} not supported',
        );
    }
  }

  /// Process the upload queue in background
  static Future<bool> _processQueueInBackground() async {
    try {
      print('IOSBackgroundService: Processing queue in background');

      // Check if there are files to upload
      final queueCount = await QueueService.getQueueCount();
      if (queueCount == 0) {
        print('IOSBackgroundService: No files in queue');
        return false;
      }

      // Check if server is reachable
      final serverReachable = await ApiService.checkConnection();
      if (!serverReachable) {
        print('IOSBackgroundService: Server not reachable');
        return false;
      }

      // Process the queue
      print('IOSBackgroundService: Processing $queueCount files');
      final uploaded = await QueueService.processQueue();
      print('IOSBackgroundService: Uploaded $uploaded files');

      return uploaded > 0;
    } catch (e) {
      print('IOSBackgroundService: Error - $e');
      return false;
    }
  }

  /// Manually trigger a sync (can be called from Flutter code)
  static Future<int> triggerSync() async {
    if (!Platform.isIOS) return 0;

    try {
      final queueCount = await QueueService.getQueueCount();
      if (queueCount == 0) return 0;

      final serverReachable = await ApiService.checkConnection();
      if (!serverReachable) return 0;

      return await QueueService.processQueue();
    } catch (e) {
      print('IOSBackgroundService: Sync error - $e');
      return 0;
    }
  }
}
