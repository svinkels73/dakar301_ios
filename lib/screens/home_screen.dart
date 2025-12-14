import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'videos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String _statusMessage = '';
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final connected = await ApiService.checkConnection();
    setState(() {
      _isConnected = connected;
      _statusMessage = connected ? 'Connecte au serveur' : 'Serveur non disponible';
    });
  }

  Future<void> _captureVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        await _uploadVideo(File(video.path));
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur camera: $e';
      });
    }
  }

  Future<void> _selectVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);

      if (video != null) {
        await _uploadVideo(File(video.path));
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur selection: $e';
      });
    }
  }

  Future<void> _uploadVideo(File videoFile) async {
    setState(() {
      _isUploading = true;
      _statusMessage = 'Upload en cours...';
    });

    final result = await ApiService.uploadVideo(videoFile);

    setState(() {
      _isUploading = false;
      if (result != null) {
        _statusMessage = 'Video uploadee avec succes!';
      } else {
        _statusMessage = 'Echec de l\'upload';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('DAKAR 301'),
        backgroundColor: const Color(0xFF16213e),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.video_library),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VideosScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'DAKAR 301',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Capture & Share Videos',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 40),

              // Connection status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected ? Icons.wifi : Icons.wifi_off,
                      color: _isConnected ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Capture button
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _captureVideo,
                icon: const Icon(Icons.videocam, size: 28),
                label: const Text('Capturer Video', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe94560),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Select from gallery button
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _selectVideo,
                icon: const Icon(Icons.photo_library, size: 24),
                label: const Text('Choisir de la Galerie', style: TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Upload indicator
              if (_isUploading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFFe94560)),
                    SizedBox(height: 10),
                    Text(
                      'Upload en cours...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),

              const SizedBox(height: 20),

              // Refresh connection button
              TextButton.icon(
                onPressed: _checkConnection,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Rafraichir connexion'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
