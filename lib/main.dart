import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background sync service (Android only for now)
  // iOS workmanager requires additional setup and may crash on some devices
  if (Platform.isAndroid) {
    try {
      await BackgroundSyncService.initialize();
    } catch (e) {
      print('BackgroundSync initialization failed: $e');
    }
  }

  runApp(const Dakar301App());
}

class Dakar301App extends StatelessWidget {
  const Dakar301App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAKAR 301',
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
