import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/background_sync_service.dart';
import 'services/ios_background_service.dart';
import 'services/stages_service.dart';
import 'services/queue_service.dart';
// Android-only imports
import 'services/foreground_upload_service.dart' if (dart.library.io) 'services/foreground_upload_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize platform-specific background services
  try {
    if (Platform.isAndroid) {
      // Android: Use WorkManager + Foreground Service for Huawei/Xiaomi
      await BackgroundSyncService.initialize();
      await ForegroundUploadService.initialize();
      final queueCount = await QueueService.getQueueCount();
      if (queueCount > 0) {
        await ForegroundUploadService.startUploadService();
      }
    } else if (Platform.isIOS) {
      // iOS: Use native Background Fetch
      await IOSBackgroundService.initialize();
    }
  } catch (e) {
    // Background service initialization failed - app continues without it
  }

  // Check for auto-activation of rally based on date
  try {
    final activatedRally = await StagesService.checkAndAutoActivateRally();
    if (activatedRally != null) {
      // Rally was auto-activated - will show in UI
    }
  } catch (e) {
    // Auto-activation check failed - app continues normally
  }

  // Sync pending offline changes if connected
  try {
    await StagesService.syncPendingChanges();
  } catch (e) {
    // Sync failed - changes remain queued
  }

  runApp(const Dakar301App());
}

class Dakar301App extends StatelessWidget {
  const Dakar301App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dania Media',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
