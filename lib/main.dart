import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const Dakar301App());
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String serverUrl = 'http://srv1028486.hstgr.cloud:3000';
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
  String _statusText = '';
  double _uploadProgress = 0;
  int _currentTab = 0;
  List<XFile> _selectedFiles = [];

  Future<void> _captureVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );
      if (video != null) {
        setState(() {
          _selectedFiles.add(video);
          _statusText = '${_selectedFiles.length} file(s) selected';
        });
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo != null) {
        setState(() {
          _selectedFiles.add(photo);
          _statusText = '${_selectedFiles.length} file(s) selected';
        });
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _selectFromGallery() async {
    try {
      final List<XFile> files = await _picker.pickMultipleMedia();
      if (files.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(files);
          _statusText = '${_selectedFiles.length} file(s) selected';
        });
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    int successCount = 0;

    for (int i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      setState(() {
        _statusText = 'Uploading ${i + 1}/${_selectedFiles.length}: ${file.name}';
        _uploadProgress = i / _selectedFiles.length;
      });

      try {
        final success = await _uploadSingleFile(file);
        if (success) successCount++;
      } catch (e) {
        print('Upload error: $e');
      }
    }

    setState(() {
      _isUploading = false;
      _uploadProgress = 0;
      _selectedFiles.clear();
      _statusText = '$successCount file(s) uploaded!';
    });

    _showSnackBar('$successCount file(s) uploaded!');
  }

  Future<bool> _uploadSingleFile(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      // Simple upload for small files
      if (fileSize < 10 * 1024 * 1024) {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/api/upload/simple'),
        );
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));

        final response = await request.send();
        return response.statusCode == 200;
      }

      // Chunked upload for larger files
      final chunkSize = 5 * 1024 * 1024;
      final totalChunks = (fileSize / chunkSize).ceil();

      // Init upload
      final initResponse = await http.post(
        Uri.parse('$serverUrl/api/upload/init'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'filename': file.name,
          'fileSize': fileSize,
          'totalChunks': totalChunks,
          'mimeType': 'application/octet-stream',
        }),
      );

      if (initResponse.statusCode != 200) return false;

      final initData = jsonDecode(initResponse.body);
      final uploadId = initData['uploadId'];

      // Upload chunks
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;
        final chunk = bytes.sublist(start, end);

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/api/upload/chunk'),
        );
        request.fields['uploadId'] = uploadId;
        request.fields['chunkIndex'] = i.toString();
        request.files.add(http.MultipartFile.fromBytes(
          'chunk',
          chunk,
          filename: 'chunk_$i',
        ));

        final response = await request.send();
        if (response.statusCode != 200) return false;

        setState(() {
          _uploadProgress = (i + 1) / totalChunks;
        });
      }

      // Complete upload
      final completeResponse = await http.post(
        Uri.parse('$serverUrl/api/upload/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uploadId': uploadId}),
      );

      return completeResponse.statusCode == 200;
    } catch (e) {
      print('Upload error: $e');
      return false;
    }
  }

  void _shareServerLink() {
    Share.share(
      'DAKAR 301 - View videos at: http://srv1028486.hstgr.cloud:3000',
      subject: 'DAKAR 301 Video Share',
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
      _statusText = '';
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF333355),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _currentTab == 0 ? _buildUploadPage() : _buildVideosPage(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        backgroundColor: const Color(0xFF252540),
        selectedItemColor: const Color(0xFF4361ee),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.upload), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Videos'),
        ],
      ),
    );
  }

  Widget _buildUploadPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Text('🎬', style: TextStyle(fontSize: 50)),
          const SizedBox(height: 10),
          const Text(
            'DAKAR 301',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Text(
            'Capture and share your moments',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 30),

          // Capture buttons
          Row(
            children: [
              Expanded(child: _buildButton('🎥 Video', const Color(0xFFe63946), _captureVideo)),
              const SizedBox(width: 12),
              Expanded(child: _buildButton('📷 Photo', const Color(0xFFf4a261), _capturePhoto)),
            ],
          ),
          const SizedBox(height: 12),
          _buildButton('📁 Gallery', const Color(0xFF4361ee), _selectFromGallery),
          const SizedBox(height: 16),

          // Selected files
          if (_selectedFiles.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252540),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedFiles.length} file(s) selected:',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedFiles.map((f) => Text(
                    '• ${f.name}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _selectedFiles.isEmpty ? null : _clearSelection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: _selectedFiles.isEmpty ? Colors.grey : Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildButton(
                  '⬆️ Upload',
                  const Color(0xFF22c55e),
                  _selectedFiles.isEmpty || _isUploading ? null : _uploadFiles,
                ),
              ),
            ],
          ),

          // Progress
          if (_isUploading) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: const Color(0xFF333355),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4361ee)),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_uploadProgress * 100).toInt()}%',
              style: const TextStyle(color: Color(0xFF4361ee), fontWeight: FontWeight.bold),
            ),
          ],

          // Status
          if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_statusText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],

          const SizedBox(height: 24),
          _buildButton('🌐 Share server link', const Color(0xFF9333ea), _shareServerLink),
        ],
      ),
    );
  }

  Widget _buildVideosPage() {
    return FutureBuilder<List<dynamic>>(
      future: _fetchVideos(),
      builder: (context, snapshot) {
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('📹', style: TextStyle(fontSize: 50)),
                const SizedBox(height: 10),
                const Text(
                  'Videos',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 30),

                if (snapshot.connectionState == ConnectionState.waiting)
                  const CircularProgressIndicator()
                else if (snapshot.hasError)
                  const Text('Connection error', style: TextStyle(color: Colors.red))
                else if (!snapshot.hasData || snapshot.data!.isEmpty)
                  const Text('No videos yet', style: TextStyle(color: Colors.grey))
                else
                  ...snapshot.data!.map((video) => _buildVideoCard(video)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<dynamic>> _fetchVideos() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/api/videos'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Fetch error: $e');
    }
    return [];
  }

  Widget _buildVideoCard(dynamic video) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252540),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF4361ee),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: Text('🎬', style: TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              video['name'] ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String text, Color color, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor: color.withOpacity(0.5),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
