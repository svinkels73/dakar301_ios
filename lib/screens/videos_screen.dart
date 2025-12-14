import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
    });

    final videos = await ApiService.getVideos();

    setState(() {
      _videos = videos;
      _isLoading = false;
    });
  }

  Future<void> _deleteVideo(String videoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Supprimer', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Voulez-vous vraiment supprimer cette video?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ApiService.deleteVideo(videoId);
      if (success) {
        _loadVideos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video supprimee')),
          );
        }
      }
    }
  }

  void _shareVideo(Map<String, dynamic> video) {
    final url = video['url'] ?? '';
    final title = video['title'] ?? 'Video DAKAR 301';
    Share.share('$title\n$url');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Mes Videos'),
        backgroundColor: const Color(0xFF16213e),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVideos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFe94560)),
            )
          : _videos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.video_library_outlined,
                        size: 80,
                        color: Colors.white30,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Aucune video',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _loadVideos,
                        child: const Text('Rafraichir'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadVideos,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      final video = _videos[index];
                      return _buildVideoCard(video);
                    },
                  ),
                ),
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    final title = video['title'] ?? 'Sans titre';
    final date = video['createdAt'] ?? video['date'] ?? '';
    final videoId = video['id']?.toString() ?? video['_id']?.toString() ?? '';

    return Card(
      color: const Color(0xFF16213e),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFe94560).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.play_circle_fill,
            color: Color(0xFFe94560),
            size: 36,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          date,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white54),
              onPressed: () => _shareVideo(video),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteVideo(videoId),
            ),
          ],
        ),
      ),
    );
  }
}
