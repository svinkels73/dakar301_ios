import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/queue_service.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup background fetch handler
  _setupBackgroundChannel();

  runApp(const Dakar301App());
}

void _setupBackgroundChannel() {
  const channel = MethodChannel('com.dakar301/background');

  channel.setMethodCallHandler((call) async {
    if (call.method == 'processQueue') {
      // Process the upload queue in background
      try {
        final connected = await ApiService.checkConnection();
        if (!connected) return false;

        final uploaded = await QueueService.processQueue();
        return uploaded > 0;
      } catch (e) {
        return false;
      }
    }
    return false;
  });
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
