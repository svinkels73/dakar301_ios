import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/background_sync_service.dart';
import 'services/ios_background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize platform-specific background services
  try {
    if (Platform.isAndroid) {
      await BackgroundSyncService.initialize();
    } else if (Platform.isIOS) {
      await IOSBackgroundService.initialize();
    }
  } catch (e) {
    print('Background service initialization failed: $e');
  }

  runApp(const Dakar301App());
}

class Dakar301App extends StatelessWidget {
  const Dakar301App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akeel Media',
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
