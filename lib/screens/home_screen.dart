import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import 'videos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String _statusMessage = '';
  bool _isConnected = false;
  int _queueCount = 0;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - check connection and process queue
      _checkConnectionAndProcessQueue();
    }
  }

  Future<void> _initialize() async {
    await _updateQueueCount();
    await _checkConnectionAndProcessQueue();

    // Check connectivity periodically
    _connectivityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnectionAndProcessQueue();
    });
  }

  Future<void> _updateQueueCount() async {
    final count = await QueueService.getQueueCount();
    if (mounted) {
      setState(() {
        _queueCount = count;
      });
    }
  }

  Future<void> _checkConnectionAndProcessQueue() async {
    final connected = await ApiService.checkConnection();

    if (mounted) {
      setState(() {
        _isConnected = connected;
        _statusMessage = connected ? 'Connecte au serveur' : 'Hors ligne';
      });
    }

    // If connected and has queue, process it
    if (connected && _queueCount > 0) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_queueCount == 0 || _isUploading) return;

    setState(() {
      _statusMessage = 'Envoi des fichiers en attente...';
    });

    final uploaded = await QueueService.processQueue();
    await _updateQueueCount();

    if (mounted) {
      setState(() {
        if (uploaded > 0) {
          _statusMessage = '$uploaded fichier(s) envoye(s)!';
        } else {
          _statusMessage = _isConnected ? 'Connecte au serveur' : 'Hors ligne';
        }
      });
    }
  }

  Future<void> _captureVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        await _handleFile(File(video.path), 'video');
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur camera';
      });
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo != null) {
        await _handleFile(File(photo.path), 'photo');
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur camera';
      });
    }
  }

  Future<void> _selectFromGallery() async {
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text('Choisir', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.white),
                title: const Text('Video', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.white),
                title: const Text('Photo', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
            ],
          ),
        ),
      );

      if (choice == 'video') {
        final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video != null) {
          await _handleFile(File(video.path), 'video');
        }
      } else if (choice == 'photo') {
        final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
        if (photo != null) {
          await _handleFile(File(photo.path), 'photo');
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur selection';
      });
    }
  }

  Future<void> _handleFile(File file, String type) async {
    if (_isConnected) {
      // Try direct upload
      setState(() {
        _isUploading = true;
        _statusMessage = 'Upload en cours...';
      });

      Map<String, dynamic>? result;
      if (type == 'video') {
        result = await ApiService.uploadVideo(file);
      } else {
        result = await ApiService.uploadPhoto(file);
      }

      setState(() {
        _isUploading = false;
      });

      if (result != null) {
        setState(() {
          _statusMessage = '${type == 'video' ? 'Video' : 'Photo'} envoyee!';
        });
      } else {
        // Upload failed - add to queue
        await _addToQueue(file, type);
      }
    } else {
      // No connection - add to queue
      await _addToQueue(file, type);
    }
  }

  Future<void> _addToQueue(File file, String type) async {
    await QueueService.addToQueue(file.path, type);
    await _updateQueueCount();

    setState(() {
      _statusMessage = 'Ajoute a la file ($_queueCount en attente)';
    });

    // Show snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${type == 'video' ? 'Video' : 'Photo'} ajoutee a la file d\'attente'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
          if (_queueCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_queueCount',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
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
                'Capture & Share',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 30),

              // Connection status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isConnected
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected ? Icons.wifi : Icons.wifi_off,
                      color: _isConnected ? Colors.green : Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),

              if (_queueCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '$_queueCount fichier(s) en attente',
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
                ),
              ],

              const SizedBox(height: 30),

              // Capture Video button
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _captureVideo,
                icon: const Icon(Icons.videocam, size: 24),
                label: const Text('Capturer Video', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe94560),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Capture Photo button
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _capturePhoto,
                icon: const Icon(Icons.camera_alt, size: 24),
                label: const Text('Prendre Photo', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4a90d9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Select from gallery button
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _selectFromGallery,
                icon: const Icon(Icons.photo_library, size: 22),
                label: const Text('Choisir de la Galerie', style: TextStyle(fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              const SizedBox(height: 24),

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

              const SizedBox(height: 16),

              // Refresh / Process queue button
              TextButton.icon(
                onPressed: () {
                  _checkConnectionAndProcessQueue();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_queueCount > 0 && _isConnected
                  ? 'Envoyer maintenant'
                  : 'Rafraichir'),
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
