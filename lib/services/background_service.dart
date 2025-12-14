import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'upload_queue_service.dart';

const String uploadTaskName = 'dakar301_upload_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == uploadTaskName) {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false; // No network, try again later
      }

      // Process the upload queue
      try {
        await UploadQueueService.processQueue();
        return true;
      } catch (e) {
        return false;
      }
    }
    return true;
  });
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> scheduleUploadTask() async {
    // Schedule a one-off task to run soon
    await Workmanager().registerOneOffTask(
      'upload_${DateTime.now().millisecondsSinceEpoch}',
      uploadTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(seconds: 10),
    );
  }

  static Future<void> schedulePeriodicUploadCheck() async {
    // Schedule periodic check every 15 minutes (minimum on iOS)
    await Workmanager().registerPeriodicTask(
      'periodic_upload_check',
      uploadTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}
