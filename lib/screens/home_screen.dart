import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/stage.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/stages_service.dart';
import 'videos_screen.dart';
import 'settings_screen.dart';

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

  // Stage management
  Stage? _currentStage;
  String _currentStageName = 'Loading...';

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
      _checkConnectionAndProcessQueue();
      _loadCurrentStage();
    }
  }

  Future<void> _initialize() async {
    await _updateQueueCount();
    await _loadCurrentStage();
    await _checkConnectionAndProcessQueue();

    _connectivityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnectionAndProcessQueue();
    });
  }

  Future<void> _loadCurrentStage() async {
    final stage = await StagesService.getCurrentStage();
    if (mounted) {
      setState(() {
        _currentStage = stage;
        _currentStageName = stage?.name ?? 'No stage today';
      });
    }
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
        _statusMessage = connected ? 'Connected' : 'Offline';
      });
    }

    if (connected && _queueCount > 0) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_queueCount == 0 || _isUploading) return;

    setState(() {
      _statusMessage = 'Sending queued files...';
    });

    final uploaded = await QueueService.processQueue();
    await _updateQueueCount();

    if (mounted) {
      setState(() {
        if (uploaded > 0) {
          _statusMessage = '$uploaded file(s) sent!';
        } else {
          _statusMessage = _isConnected ? 'Connected' : 'Offline';
        }
      });
    }
  }

  Future<void> _captureMedia(MediaCategory category) async {
    try {
      XFile? file;

      if (category.isPhoto) {
        file = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
      } else {
        file = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 10),
        );
      }

      if (file != null) {
        await _handleFile(File(file.path), category);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Camera error';
      });
    }
  }

  Future<void> _selectFromGallery(MediaCategory category) async {
    try {
      XFile? file;

      if (category.isPhoto) {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      }

      if (file != null) {
        await _handleFile(File(file.path), category);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Selection error';
      });
    }
  }

  Future<void> _handleFile(File file, MediaCategory category) async {
    final stageId = _currentStage?.id ?? 'avant_rallye';

    // Get capture date from file modification time (best approximation without EXIF library)
    DateTime? captureDate;
    try {
      final stat = await file.stat();
      captureDate = stat.modified;
    } catch (_) {}

    if (_isConnected) {
      setState(() {
        _isUploading = true;
        _statusMessage = 'Uploading ${category.displayName}...';
      });

      final result = await ApiService.uploadMedia(
        file,
        stage: stageId,
        category: category,
        captureDate: captureDate,
      );

      setState(() {
        _isUploading = false;
      });

      if (result != null) {
        setState(() {
          _statusMessage = '${category.displayName} sent!';
        });
        _showSuccessSnackbar(category);
      } else {
        await _addToQueue(file, category, captureDate);
      }
    } else {
      await _addToQueue(file, category, captureDate);
    }
  }

  Future<void> _addToQueue(File file, MediaCategory category, [DateTime? captureDate]) async {
    final stageId = _currentStage?.id ?? 'avant_rallye';

    // Store with stage, category, and capture date info
    await QueueService.addToQueueWithMetadata(
      file.path,
      category.isPhoto ? 'photo' : 'video',
      stageId,
      category.id,
      captureDate: captureDate,
    );
    await _updateQueueCount();

    setState(() {
      _statusMessage = 'Added to queue ($_queueCount pending)';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${category.displayName} added to queue'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSuccessSnackbar(MediaCategory category) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('${category.displayName} uploaded to ${_currentStage?.name ?? "server"}'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCaptureOptions(MediaCategory category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              category.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                category.isPhoto ? Icons.camera_alt : Icons.videocam,
                color: Colors.white,
              ),
              title: Text(
                category.isPhoto ? 'Take Photo' : 'Record Video',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _captureMedia(category);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _selectFromGallery(category);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: _isUploading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
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
              padding: const EdgeInsets.only(right: 4),
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              // Reload stage after returning from settings
              _loadCurrentStage();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Current Stage Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFe94560).withOpacity(0.8),
                      const Color(0xFF16213e),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Current Stage',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentStageName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_currentStage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_currentStage!.startDate.day}/${_currentStage!.startDate.month}/${_currentStage!.startDate.year}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
                const SizedBox(height: 8),
                Text(
                  '$_queueCount file(s) pending',
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
                ),
              ],

              const SizedBox(height: 24),

              // Title
              const Text(
                'Capture Media',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Video Buttons Row
              Row(
                children: [
                  _buildCaptureButton(
                    label: 'Video\nGeneral',
                    icon: Icons.videocam,
                    color: const Color(0xFFe94560),
                    onPressed: () => _showCaptureOptions(MediaCategory.videoGeneral),
                  ),
                  _buildCaptureButton(
                    label: 'Video\nEnglish',
                    icon: Icons.videocam,
                    color: const Color(0xFF4a90d9),
                    onPressed: () => _showCaptureOptions(MediaCategory.videoEnglish),
                  ),
                  _buildCaptureButton(
                    label: 'Video\nArabic',
                    icon: Icons.videocam,
                    color: const Color(0xFF2ecc71),
                    onPressed: () => _showCaptureOptions(MediaCategory.videoArabic),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Photo Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUploading
                      ? null
                      : () => _showCaptureOptions(MediaCategory.photos),
                  icon: const Icon(Icons.camera_alt, size: 24),
                  label: const Text('Take Photo', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9b59b6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      'Uploading...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Refresh button
              TextButton.icon(
                onPressed: () {
                  _checkConnectionAndProcessQueue();
                  _loadCurrentStage();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_queueCount > 0 && _isConnected ? 'Send now' : 'Refresh'),
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
