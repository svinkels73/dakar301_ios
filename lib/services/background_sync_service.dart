import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'queue_service.dart';
import 'api_service.dart';

// Task names
const String backgroundSyncTask = "backgroundSyncTask";
const String periodicSyncTask = "periodicSyncTask";

// This must be a top-level function (not a class method)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('BackgroundSync: Task $task started');

      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      if (!hasConnection) {
        print('BackgroundSync: No network connection, skipping');
        return true; // Return true to mark task as completed, will retry later
      }

      // Check if server is reachable
      final serverReachable = await ApiService.checkConnection();
      if (!serverReachable) {
        print('BackgroundSync: Server not reachable, skipping');
        return true;
      }

      // Process the upload queue
      final queueCount = await QueueService.getQueueCount();
      if (queueCount == 0) {
        print('BackgroundSync: No files in queue');
        return true;
      }

      print('BackgroundSync: Processing $queueCount files');
      final uploaded = await QueueService.processQueue();
      print('BackgroundSync: Uploaded $uploaded files');

      // Save last sync time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_background_sync', DateTime.now().toIso8601String());

      return true;
    } catch (e) {
      print('BackgroundSync: Error - $e');
      return false; // Return false to indicate failure, will retry
    }
  });
}

class BackgroundSyncService {
  static bool _initialized = false;

  // Initialize the background sync service
  static Future<void> initialize() async {
    if (_initialized) return;

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );

    _initialized = true;
    print('BackgroundSync: Initialized');

    // Register periodic task (runs every 15 minutes minimum on Android)
    await registerPeriodicSync();

    // Listen for connectivity changes
    _setupConnectivityListener();
  }

  // Register periodic background sync
  static Future<void> registerPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      periodicSyncTask,
      periodicSyncTask,
      frequency: const Duration(minutes: 15), // Minimum is 15 minutes on Android
      constraints: Constraints(
        networkType: NetworkType.connected, // Only run when connected
        requiresBatteryNotLow: true, // Don't run on low battery
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    print('BackgroundSync: Periodic sync registered');
  }

  // Trigger immediate sync when network becomes available
  static Future<void> triggerImmediateSync() async {
    // Check if there are files to upload
    final queueCount = await QueueService.getQueueCount();
    if (queueCount == 0) return;

    await Workmanager().registerOneOffTask(
      '${backgroundSyncTask}_${DateTime.now().millisecondsSinceEpoch}',
      backgroundSyncTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    print('BackgroundSync: Immediate sync triggered');
  }

  // Setup connectivity listener to trigger sync when network comes back
  static void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      final hasConnection = results.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      if (hasConnection) {
        print('BackgroundSync: Network available, checking queue');
        final queueCount = await QueueService.getQueueCount();
        if (queueCount > 0) {
          print('BackgroundSync: $queueCount files pending, triggering sync');
          await triggerImmediateSync();
        }
      }
    });
  }

  // Cancel all background tasks
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
    print('BackgroundSync: All tasks cancelled');
  }

  // Get last sync time
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString('last_background_sync');
    if (lastSync != null) {
      return DateTime.tryParse(lastSync);
    }
    return null;
  }
}
