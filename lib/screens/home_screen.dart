import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/stage.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/stages_service.dart';
import '../services/background_sync_service.dart';
import 'videos_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessingQueue = false;
  String _statusMessage = '';
  bool _isConnected = false;
  int _queueCount = 0;
  int _uploadingCount = 0;  // Number of files currently uploading
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
    if (_queueCount == 0 || _isProcessingQueue) return;

    _isProcessingQueue = true;

    if (mounted) {
      setState(() {
        _uploadingCount = _queueCount;
        _statusMessage = 'Uploading $_uploadingCount file(s)...';
      });
    }

    // Process queue in background - this doesn't block the UI
    final uploaded = await QueueService.processQueue();
    await _updateQueueCount();

    _isProcessingQueue = false;

    if (mounted) {
      setState(() {
        _uploadingCount = 0;
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
    // Get capture date from file modification time (best approximation without EXIF library)
    DateTime? captureDate;
    try {
      final stat = await file.stat();
      captureDate = stat.modified;
    } catch (_) {}

    // Always add to queue first - this allows immediate capture of next video
    await _addToQueue(file, category, captureDate);

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${category.displayName} queued'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    // If connected, trigger background upload (non-blocking)
    if (_isConnected && !_isProcessingQueue) {
      // Don't await - let it run in background
      _processQueue();
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
    // Note: Upload is triggered by _handleFile() calling _processQueue()
    // BackgroundSyncService is only for offline/background scenarios
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
          onPressed: onPressed,  // Always enabled - upload is now in background
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
        title: const Text('Akeel Media'),
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
                  onPressed: () => _showCaptureOptions(MediaCategory.photos),  // Always enabled
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

              // Upload progress indicator (non-blocking)
              if (_isProcessingQueue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFe94560).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Color(0xFFe94560),
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Uploading $_uploadingCount file(s)...',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
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
