import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String type; // 'video' or 'photo'
  final String? size;

  const MediaPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.type,
    this.size,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  bool _isPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _initializeVideo();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _videoController!.initialize();
      _videoController!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _videoController!.value.isPlaying;
          });
        }
      });
      _videoController!.play();
      setState(() {
        _isLoading = false;
        _isPlaying = true;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _shareMedia() {
    Share.share('${widget.title}\n${widget.url}');
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareMedia,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFe94560)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Failed to load media',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                if (widget.type == 'video') {
                  _initializeVideo();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFe94560),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (widget.type == 'video') {
      return _buildVideoPlayer();
    } else {
      return _buildImageViewer();
    }
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(
        child: Text('Video player not initialized', style: TextStyle(color: Colors.white)),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_videoController!),
                  // Play/Pause overlay
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Controls
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Progress bar
              ValueListenableBuilder(
                valueListenable: _videoController!,
                builder: (context, VideoPlayerValue value, child) {
                  final position = value.position;
                  final duration = value.duration;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFe94560),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: const Color(0xFFe94560),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: position.inMilliseconds.toDouble(),
                          max: duration.inMilliseconds.toDouble(),
                          onChanged: (value) {
                            _videoController!.seekTo(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () {
                      final position = _videoController!.value.position;
                      _videoController!.seekTo(position - const Duration(seconds: 10));
                    },
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      color: const Color(0xFFe94560),
                      size: 48,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () {
                      final position = _videoController!.value.position;
                      _videoController!.seekTo(position + const Duration(seconds: 10));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: const Color(0xFFe94560),
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(loadingProgress.cumulativeBytesLoaded / 1024).toStringAsFixed(0)} KB',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
