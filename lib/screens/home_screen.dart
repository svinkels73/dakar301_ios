import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/stage.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/stages_service.dart';
// Android-only: Foreground service for Huawei/Xiaomi
import '../services/foreground_upload_service.dart' if (dart.library.io) '../services/foreground_upload_service.dart';
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
  bool _isConnected = false;
  int _queueCount = 0;
  int _uploadingCount = 0;
  Timer? _connectivityTimer;

  // Navigation
  int _currentIndex = 0;

  // Stage management
  Stage? _currentStage;
  List<Stage> _allStages = [];
  String _rallyName = 'Loading...';

  // Stats
  int _totalVideos = 0;
  int _totalPhotos = 0;
  int _totalSent = 0;

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
      // Keep current stage selection when returning from camera/gallery
      _loadCurrentStage(keepCurrentSelection: true);
    }
  }

  Future<void> _initialize() async {
    await _updateQueueCount();
    await _loadCurrentStage();
    await _loadStats();
    await _checkConnectionAndProcessQueue();

    _connectivityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnectionAndProcessQueue();
    });
  }

  Future<void> _loadCurrentStage({bool keepCurrentSelection = false}) async {
    final config = await StagesService.getStagesConfig();

    if (mounted) {
      setState(() {
        _allStages = config.stages;
        _rallyName = config.rallyName;

        // Only auto-select stage if not keeping current selection
        if (!keepCurrentSelection || _currentStage == null) {
          // Try to find current stage by date
          final stage = config.getCurrentStage();
          _currentStage = stage;
        } else {
          // Keep current selection but update reference from new list
          final existingId = _currentStage!.id;
          final updatedStage = config.stages.where((s) => s.id == existingId).firstOrNull;
          if (updatedStage != null) {
            _currentStage = updatedStage;
          }
        }
      });
    }
  }

  Future<void> _loadStats() async {
    // TODO: Implement real stats from server or local storage
    // For now, we'll show placeholder stats
    if (mounted) {
      setState(() {
        _totalVideos = 0;
        _totalPhotos = 0;
        _totalSent = 0;
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
      });
    }

    final uploaded = await QueueService.processQueue();
    await _updateQueueCount();

    _isProcessingQueue = false;

    if (mounted) {
      setState(() {
        _uploadingCount = 0;
        _totalSent += uploaded;
      });

      if (uploaded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('$uploaded file(s) uploaded!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _captureMedia(MediaCategory category, {bool fromGallery = false}) async {
    try {
      XFile? file;

      if (category.isPhoto) {
        file = await _picker.pickImage(
          source: fromGallery ? ImageSource.gallery : ImageSource.camera,
          imageQuality: 85,
        );
      } else {
        file = await _picker.pickVideo(
          source: fromGallery ? ImageSource.gallery : ImageSource.camera,
          maxDuration: const Duration(minutes: 10),
        );
      }

      if (file != null) {
        await _handleFile(File(file.path), category);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fromGallery ? 'Selection error' : 'Camera error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleFile(File file, MediaCategory category) async {
    DateTime? captureDate;
    try {
      final stat = await file.stat();
      captureDate = stat.modified;
    } catch (_) {}

    await _addToQueue(file, category, captureDate);

    // Update local stats
    if (mounted) {
      setState(() {
        if (category.isPhoto) {
          _totalPhotos++;
        } else {
          _totalVideos++;
        }
      });

      // Haptic feedback
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${category.displayName} added to queue',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2ecc71),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    if (_isConnected && !_isProcessingQueue) {
      _processQueue();
    }
  }

  Future<void> _addToQueue(File file, MediaCategory category, [DateTime? captureDate]) async {
    final stageId = _currentStage?.id ?? 'avant_rallye';
    final rallyId = await StagesService.getSelectedRallyId();

    await QueueService.addToQueueWithMetadata(
      file.path,
      category.isPhoto ? 'photo' : 'video',
      stageId,
      category.id,
      captureDate: captureDate,
      rallyId: rallyId,
    );
    await _updateQueueCount();

    // Android only: Start foreground service for reliable upload on Huawei/Xiaomi
    if (Platform.isAndroid) {
      await ForegroundUploadService.startUploadService();
    }
  }

  void _showStageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Stage',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addNewStage();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Stage'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFe94560),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _allStages.length,
                itemBuilder: (context, index) {
                  final stage = _allStages[index];
                  final isSelected = stage.id == _currentStage?.id;
                  final isToday = stage.containsDate(DateTime.now());
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? const Color(0xFFe94560) : Colors.white54,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stage.name,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFFe94560) : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFe94560),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy').format(stage.startDate),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      setState(() {
                        _currentStage = stage;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _addNewStage() async {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final result = await showDialog<Stage>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text('Add New Stage', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) {
                    // Auto-generate ID from name
                    final id = value.trim().toLowerCase()
                        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
                        .replaceAll(RegExp(r'\s+'), '_');
                    idController.text = id;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Stage Name',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText: 'e.g. Stage 6, Price Giving Ceremony',
                    hintStyle: TextStyle(color: Colors.white30),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFe94560)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idController,
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: 'Stage ID (folder name)',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText: 'e.g. stage_06',
                    hintStyle: TextStyle(color: Colors.white30),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFe94560)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFFe94560),
                              surface: Color(0xFF16213e),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      labelStyle: TextStyle(color: Colors.white60),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      suffixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                    ),
                    child: Text(
                      DateFormat('dd MMMM yyyy').format(selectedDate),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stage will be sorted by date automatically',
                          style: TextStyle(color: Colors.blue, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final id = idController.text.trim();
                if (name.isEmpty || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all fields'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, Stage(
                  id: id,
                  name: name,
                  startDate: selectedDate,
                  endDate: selectedDate,
                ));
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      // Add the stage via StagesService
      final success = await StagesService.addStage(result);

      if (success) {
        // Reload stages list without changing selection
        await _loadCurrentStage(keepCurrentSelection: true);

        // Now explicitly select the newly created stage
        setState(() {
          // Find the stage in the updated list by ID
          final newStage = _allStages.where((s) => s.id == result.id).firstOrNull;
          _currentStage = newStage ?? result;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stage "${result.name}" added and selected'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to add stage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildCaptureScreen() {
    return RefreshIndicator(
      onRefresh: () async {
        await _checkConnectionAndProcessQueue();
        await _loadCurrentStage(keepCurrentSelection: true);
        await _loadStats();
      },
      color: const Color(0xFFe94560),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Stage Card with selector
              GestureDetector(
                onTap: _showStageSelector,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFe94560),
                        const Color(0xFFe94560).withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFe94560).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _rallyName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isConnected ? 'Online' : 'Offline',
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _currentStage?.name ?? 'No stage selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentStage != null)
                            Text(
                              '${_currentStage!.startDate.day}/${_currentStage!.startDate.month}/${_currentStage!.startDate.year}',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                          const Text(
                            'Change',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Quick Stats Row
              Row(
                children: [
                  _buildStatCard(
                    icon: Icons.videocam,
                    value: '$_totalVideos',
                    label: 'Videos',
                    color: const Color(0xFF4a90d9),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.cloud_upload,
                    value: '$_totalSent',
                    label: 'Sent',
                    color: const Color(0xFF2ecc71),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.photo_camera,
                    value: '$_totalPhotos',
                    label: 'Photos',
                    color: const Color(0xFF9b59b6),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Queue status bar
              if (_queueCount > 0 || _isProcessingQueue)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isProcessingQueue
                        ? const Color(0xFF4a90d9).withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isProcessingQueue
                          ? const Color(0xFF4a90d9).withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_isProcessingQueue)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4a90d9),
                          ),
                        )
                      else
                        const Icon(Icons.schedule, color: Colors.orange, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isProcessingQueue
                              ? 'Uploading $_uploadingCount file(s)...'
                              : '$_queueCount file(s) pending',
                          style: TextStyle(
                            color: _isProcessingQueue
                                ? const Color(0xFF4a90d9)
                                : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!_isProcessingQueue && _isConnected)
                        TextButton(
                          onPressed: _processQueue,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),

              // Main Capture Button - VIDEO GENERAL (reduced size)
              _buildMainCaptureButton(
                label: 'VIDEO GENERAL',
                icon: Icons.videocam_rounded,
                color: const Color(0xFFe94560),
                category: MediaCategory.videoGeneral,
              ),

              const SizedBox(height: 12),

              // Video English & Arabic Buttons Row (larger)
              Row(
                children: [
                  Expanded(
                    child: _buildMediumCaptureButton(
                      label: 'VIDEO ENGLISH',
                      icon: Icons.videocam,
                      color: const Color(0xFF4a90d9),
                      category: MediaCategory.videoEnglish,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMediumCaptureButton(
                      label: 'VIDEO ARABIC',
                      icon: Icons.videocam,
                      color: const Color(0xFF2ecc71),
                      category: MediaCategory.videoArabic,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Photo Button
              _buildSecondaryCaptureButton(
                label: 'PHOTO',
                icon: Icons.photo_camera_rounded,
                color: const Color(0xFF9b59b6),
                category: MediaCategory.photos,
                fullWidth: true,
              ),

              const SizedBox(height: 20),

              // Tip text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.amber.withOpacity(0.7), size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Long press any button to select from gallery',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainCaptureButton({
    required String label,
    required IconData icon,
    required Color color,
    required MediaCategory category,
  }) {
    return GestureDetector(
      onTap: () => _captureMedia(category),
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _captureMedia(category, fromGallery: true);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Tap to record',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediumCaptureButton({
    required String label,
    required IconData icon,
    required Color color,
    required MediaCategory category,
  }) {
    return GestureDetector(
      onTap: () => _captureMedia(category),
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _captureMedia(category, fromGallery: true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.9), color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerUrlCard() {
    const serverUrl = 'http://srv1028486.hstgr.cloud:3000';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Server URL',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const Text(
                  serverUrl,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Color(0xFFe94560), size: 20),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: serverUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('URL copied to clipboard'),
                    ],
                  ),
                  backgroundColor: const Color(0xFF2ecc71),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            tooltip: 'Copy URL',
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Color(0xFF4a90d9), size: 20),
            onPressed: () {
              Share.share('View media at: $serverUrl');
            },
            tooltip: 'Share URL',
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryCaptureButton({
    required String label,
    required IconData icon,
    required Color color,
    required MediaCategory category,
    bool fullWidth = false,
  }) {
    return GestureDetector(
      onTap: () => _captureMedia(category),
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _captureMedia(category, fromGallery: true);
      },
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_filled, size: 28),
            SizedBox(width: 8),
            Text(
              'DANIA MEDIA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16213e),
        centerTitle: true,
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildCaptureScreen(),
          const VideosScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16213e),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.home_rounded,
                  label: 'Capture',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.folder_rounded,
                  label: 'Media',
                  index: 1,
                  badge: _queueCount > 0 ? _queueCount : null,
                ),
                _buildNavItem(
                  icon: Icons.tune_rounded,
                  label: 'Manage Rally',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    int? badge,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFe94560).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFFe94560) : Colors.white54,
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFe94560) : Colors.white54,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                right: -8,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
