import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'media_player_screen.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  List<Map<String, dynamic>> _allMedia = [];
  bool _isLoading = true;

  // Navigation path: [rallyId, stageId, category]
  List<String> _currentPath = [];

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
    });

    final media = await ApiService.getAllMedia();

    setState(() {
      _allMedia = media;
      _isLoading = false;
    });
  }

  // Get filtered media based on current path
  List<Map<String, dynamic>> get _filteredMedia {
    var filtered = _allMedia;

    if (_currentPath.isNotEmpty) {
      filtered = filtered.where((m) => m['rallyId'] == _currentPath[0]).toList();
    }
    if (_currentPath.length >= 2) {
      filtered = filtered.where((m) => m['stage'] == _currentPath[1]).toList();
    }
    if (_currentPath.length >= 3) {
      filtered = filtered.where((m) => m['category'] == _currentPath[2]).toList();
    }

    return filtered;
  }

  // Navigate into a folder
  void _enterFolder(String name) {
    setState(() {
      _currentPath.add(name);
    });
  }

  // Navigate back to a specific level
  void _navigateTo(int level) {
    setState(() {
      if (level < 0) {
        _currentPath = [];
      } else {
        _currentPath = _currentPath.sublist(0, level + 1);
      }
    });
  }

  // Delete media
  Future<void> _deleteMedia(String mediaId, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete this $type?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ApiService.deleteMedia(mediaId);
      if (success) {
        _loadMedia();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$type deleted')),
          );
        }
      }
    }
  }

  // Share media
  void _shareMedia(Map<String, dynamic> media) {
    final url = 'http://srv1028486.hstgr.cloud:3000${media['url'] ?? ''}';
    final title = media['originalName'] ?? media['filename'] ?? 'Media DAKAR 301';
    Share.share('$title\n$url');
  }

  // Open in browser
  Future<void> _openInBrowser(Map<String, dynamic> media) async {
    final url = 'http://srv1028486.hstgr.cloud:3000${media['url'] ?? ''}';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Open media player
  void _openMediaPlayer(Map<String, dynamic> media) {
    final url = 'http://srv1028486.hstgr.cloud:3000${media['url'] ?? ''}';
    final title = media['originalName'] ?? media['filename'] ?? 'Media';
    final type = media['type'] ?? 'video';
    final size = _formatSize(media['size']);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaPlayerScreen(
          url: url,
          title: title,
          type: type,
          size: size,
        ),
      ),
    );
  }

  // Format file size
  String _formatSize(dynamic bytes) {
    if (bytes == null) return '';
    final size = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Media Catalog'),
        backgroundColor: const Color(0xFF16213e),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMedia,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFe94560)),
            )
          : Column(
              children: [
                // Server URL Card
                _buildServerUrlCard(),
                // Breadcrumb navigation
                _buildBreadcrumb(),
                // Content
                Expanded(child: _buildContent()),
              ],
            ),
    );
  }

  // Server URL sharing card
  Widget _buildServerUrlCard() {
    const serverUrl = 'http://srv1028486.hstgr.cloud:3000';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4a90d9).withOpacity(0.2),
            const Color(0xFF16213e),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4a90d9).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4a90d9).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.language, color: Color(0xFF4a90d9), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share this link to view media',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 2),
                const Text(
                  serverUrl,
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Color(0xFF4a90d9), size: 22),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: serverUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('URL copied!'),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFFe94560), size: 22),
            onPressed: () {
              Share.share('View our rally media at:\n$serverUrl');
            },
            tooltip: 'Share URL',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // Build breadcrumb navigation
  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF16213e).withOpacity(0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Home button
            GestureDetector(
              onTap: () => _navigateTo(-1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _currentPath.isEmpty
                      ? const Color(0xFFe94560).withOpacity(0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.home, size: 16, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      'Rallies',
                      style: TextStyle(
                        color: _currentPath.isEmpty ? Colors.white : const Color(0xFF4a90d9),
                        fontWeight: _currentPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Path items
            ..._currentPath.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == _currentPath.length - 1;

              return Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.chevron_right, size: 16, color: Colors.white38),
                  ),
                  GestureDetector(
                    onTap: isLast ? null : () => _navigateTo(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLast
                            ? const Color(0xFFe94560).withOpacity(0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatPathItem(item),
                        style: TextStyle(
                          color: isLast ? Colors.white : const Color(0xFF4a90d9),
                          fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatPathItem(String item) {
    // Format category names nicely
    switch (item) {
      case 'video_english':
        return 'Video English';
      case 'video_arabic':
        return 'Video Arabic';
      case 'video_general':
        return 'Video General';
      case 'photos':
        return 'Photos';
      default:
        return item;
    }
  }

  // Build content based on current path level
  Widget _buildContent() {
    if (_currentPath.isEmpty) {
      return _buildRalliesList();
    } else if (_currentPath.length == 1) {
      return _buildStagesList();
    } else if (_currentPath.length == 2) {
      return _buildStageContent();
    } else {
      return _buildMediaList(_filteredMedia);
    }
  }

  // Build rallies list
  Widget _buildRalliesList() {
    final rallies = _allMedia
        .map((m) => m['rallyId'] as String?)
        .where((r) => r != null)
        .toSet()
        .toList();

    if (rallies.isEmpty) {
      return _buildEmptyState('No rallies yet', Icons.flag_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rallies.length,
      itemBuilder: (context, index) {
        final rally = rallies[index]!;
        final count = _allMedia.where((m) => m['rallyId'] == rally).length;

        return _buildFolderCard(
          name: rally,
          icon: Icons.flag,
          color: const Color(0xFFe94560),
          count: count,
          onTap: () => _enterFolder(rally),
        );
      },
    );
  }

  // Build stages list
  Widget _buildStagesList() {
    final stageMedia = _allMedia.where((m) => m['rallyId'] == _currentPath[0]).toList();
    final stages = stageMedia
        .map((m) => m['stage'] as String?)
        .where((s) => s != null)
        .toSet()
        .toList();

    if (stages.isEmpty) {
      return _buildEmptyState('No stages yet', Icons.folder_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stages.length,
      itemBuilder: (context, index) {
        final stage = stages[index]!;
        final count = stageMedia.where((m) => m['stage'] == stage).length;

        return _buildFolderCard(
          name: stage,
          icon: Icons.folder,
          color: const Color(0xFFf39c12),
          count: count,
          onTap: () => _enterFolder(stage),
        );
      },
    );
  }

  // Build stage content (categories + video_general)
  Widget _buildStageContent() {
    final stageMedia = _allMedia.where((m) =>
        m['rallyId'] == _currentPath[0] && m['stage'] == _currentPath[1]).toList();

    // Categories with files
    final categories = ['video_english', 'video_arabic', 'photos'];
    final categoryFolders = categories.where((cat) =>
        stageMedia.any((m) => m['category'] == cat)).toList();

    // Video general files
    final videoGeneralFiles = stageMedia.where((m) => m['category'] == 'video_general').toList();

    if (categoryFolders.isEmpty && videoGeneralFiles.isEmpty) {
      return _buildEmptyState('No files in this stage', Icons.folder_outlined);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Category folders
        ...categoryFolders.map((cat) {
          final count = stageMedia.where((m) => m['category'] == cat).length;
          IconData icon;
          Color color;

          switch (cat) {
            case 'video_english':
              icon = Icons.videocam;
              color = const Color(0xFF4a90d9);
              break;
            case 'video_arabic':
              icon = Icons.videocam;
              color = const Color(0xFF2ecc71);
              break;
            case 'photos':
              icon = Icons.photo_camera;
              color = const Color(0xFF9b59b6);
              break;
            default:
              icon = Icons.folder;
              color = Colors.grey;
          }

          return _buildFolderCard(
            name: _formatPathItem(cat),
            icon: icon,
            color: color,
            count: count,
            onTap: () => _enterFolder(cat),
          );
        }),

        // Video General section
        if (videoGeneralFiles.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: Color(0xFFe94560), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Video General (${videoGeneralFiles.length})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ...videoGeneralFiles.map((media) => _buildMediaCard(media)),
        ],
      ],
    );
  }

  // Build media list
  Widget _buildMediaList(List<Map<String, dynamic>> mediaList) {
    if (mediaList.isEmpty) {
      return _buildEmptyState('No files', Icons.folder_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: mediaList.length,
      itemBuilder: (context, index) => _buildMediaCard(mediaList[index]),
    );
  }

  // Build folder card
  Widget _buildFolderCard({
    required String name,
    required IconData icon,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF16213e),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count file${count != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  // Build media card
  Widget _buildMediaCard(Map<String, dynamic> media) {
    final title = media['originalName'] ?? media['filename'] ?? 'Untitled';
    final type = media['type'] ?? 'video';
    final size = _formatSize(media['size']);
    final mediaId = media['id']?.toString() ?? '';
    final isVideo = type == 'video';

    return Card(
      color: const Color(0xFF16213e),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openMediaPlayer(media),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail with play button
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: (isVideo ? const Color(0xFFe94560) : const Color(0xFF9b59b6))
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVideo ? Icons.play_circle_fill : Icons.photo,
                  color: isVideo ? const Color(0xFFe94560) : const Color(0xFF9b59b6),
                  size: 36,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isVideo ? const Color(0xFFe94560) : const Color(0xFF9b59b6))
                                .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type.toUpperCase(),
                            style: TextStyle(
                              color: isVideo ? const Color(0xFFe94560) : const Color(0xFF9b59b6),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          size,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.open_in_browser, color: Colors.white54, size: 20),
                    onPressed: () => _openInBrowser(media),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Open in browser',
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white54, size: 20),
                    onPressed: () => _shareMedia(media),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Share',
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => _deleteMedia(mediaId, type),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build empty state
  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white30),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loadMedia,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
