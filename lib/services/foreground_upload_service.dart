import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'queue_service.dart';
import 'api_service.dart';

// This service is Android-only for Huawei/Xiaomi devices that kill background tasks

// The callback function should always be a top-level function.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(UploadTaskHandler());
}

class UploadTaskHandler extends TaskHandler {
  int _uploadedCount = 0;
  int _totalCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('ForegroundUpload: Task started');
    _uploadedCount = 0;
    _totalCount = await QueueService.getQueueCount();

    if (_totalCount > 0) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Uploading media...',
        notificationText: '0/$_totalCount files uploaded',
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      if (!hasConnection) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Waiting for network...',
          notificationText: 'Will upload when connected',
        );
        return;
      }

      // Check queue
      final queueCount = await QueueService.getQueueCount();
      if (queueCount == 0) {
        // All done, stop the service
        FlutterForegroundTask.updateService(
          notificationTitle: 'Upload complete',
          notificationText: 'All media uploaded successfully',
        );
        await Future.delayed(const Duration(seconds: 2));
        await FlutterForegroundTask.stopService();
        return;
      }

      // Update notification
      _totalCount = queueCount + _uploadedCount;
      FlutterForegroundTask.updateService(
        notificationTitle: 'Uploading media...',
        notificationText: '$_uploadedCount/$_totalCount files uploaded',
      );

      // Check server
      final serverReachable = await ApiService.checkConnection();
      if (!serverReachable) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Server unreachable',
          notificationText: 'Retrying...',
        );
        return;
      }

      // Process queue
      final uploaded = await QueueService.processQueue();
      _uploadedCount += uploaded;

      // Check if done
      final remainingCount = await QueueService.getQueueCount();
      if (remainingCount == 0) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Upload complete',
          notificationText: '$_uploadedCount files uploaded successfully',
        );
        await Future.delayed(const Duration(seconds: 2));
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      print('ForegroundUpload: Error - $e');
      FlutterForegroundTask.updateService(
        notificationTitle: 'Upload error',
        notificationText: 'Retrying...',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('ForegroundUpload: Task destroyed');
  }

  @override
  void onReceiveData(Object data) {
    print('ForegroundUpload: Received data - $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    // Called when the notification is pressed
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // Called when the notification is dismissed (if allowed)
  }
}

class ForegroundUploadService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    // Only run on Android
    if (!Platform.isAndroid) return;
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dania_media_upload',
        channelName: 'Media Upload',
        channelDescription: 'Notification for media upload progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Every 5 seconds
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
    print('ForegroundUpload: Initialized');
  }

  static Future<bool> startUploadService() async {
    // Only run on Android
    if (!Platform.isAndroid) return false;

    await initialize();

    // Check if already running
    if (await FlutterForegroundTask.isRunningService) {
      print('ForegroundUpload: Service already running');
      return true;
    }

    // Check if there are files to upload
    final queueCount = await QueueService.getQueueCount();
    if (queueCount == 0) {
      print('ForegroundUpload: No files in queue');
      return false;
    }

    // Request permissions if needed
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check battery optimization (important for Huawei/Xiaomi)
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // Start the service
    await FlutterForegroundTask.startService(
      notificationTitle: 'Preparing upload...',
      notificationText: '$queueCount files pending',
      callback: startCallback,
    );

    final isRunning = await FlutterForegroundTask.isRunningService;
    print('ForegroundUpload: Service started = $isRunning');
    return isRunning;
  }

  static Future<void> stopUploadService() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      print('ForegroundUpload: Service stopped');
    }
  }

  static Future<bool> isServiceRunning() async {
    if (!Platform.isAndroid) return false;
    return await FlutterForegroundTask.isRunningService;
  }

  // Request battery optimization exemption (important for Huawei)
  static Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    }
    return true;
  }
}
