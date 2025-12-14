import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://srv1028486.hstgr.cloud:3000';

  // Upload a video file
  static Future<Map<String, dynamic>?> uploadVideo(File videoFile, {String? title}) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);

      final fileName = videoFile.path.split('/').last;
      final videoTitle = title ?? fileName;

      request.fields['title'] = videoTitle;
      request.files.add(await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        filename: fileName,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Get list of videos
  static Future<List<Map<String, dynamic>>> getVideos() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/videos'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Delete a video
  static Future<bool> deleteVideo(String videoId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/videos/$videoId'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Check server connection
  static Future<bool> checkConnection() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
