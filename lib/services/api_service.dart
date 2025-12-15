import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/stage.dart';

class ApiService {
  static const String baseUrl = 'http://srv1028486.hstgr.cloud:3000';

  // Upload a file with stage and category
  static Future<Map<String, dynamic>?> uploadMedia(
    File file, {
    required String stage,
    required MediaCategory category,
    String? title,
    DateTime? captureDate,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);

      final fileName = file.path.split('/').last;
      final mediaTitle = title ?? fileName;

      request.fields['title'] = mediaTitle;
      request.fields['stage'] = stage;
      request.fields['category'] = category.id;
      request.fields['type'] = category.isPhoto ? 'photo' : 'video';

      // Send capture date for server-side stage classification
      if (captureDate != null) {
        request.fields['captureDate'] = captureDate.toIso8601String();
      }

      request.files.add(await http.MultipartFile.fromPath(
        category.isPhoto ? 'photo' : 'video',
        file.path,
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

  // Legacy upload video (for backward compatibility)
  static Future<Map<String, dynamic>?> uploadVideo(File videoFile, {String? title, String? stage, String? category, DateTime? captureDate}) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);

      final fileName = videoFile.path.split('/').last;
      final videoTitle = title ?? fileName;

      request.fields['title'] = videoTitle;
      request.fields['type'] = 'video';
      if (stage != null) request.fields['stage'] = stage;
      if (category != null) request.fields['category'] = category;
      if (captureDate != null) request.fields['captureDate'] = captureDate.toIso8601String();

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

  // Legacy upload photo (for backward compatibility)
  static Future<Map<String, dynamic>?> uploadPhoto(File photoFile, {String? title, String? stage, String? category, DateTime? captureDate}) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);

      final fileName = photoFile.path.split('/').last;
      final photoTitle = title ?? fileName;

      request.fields['title'] = photoTitle;
      request.fields['type'] = 'photo';
      if (stage != null) request.fields['stage'] = stage;
      if (category != null) request.fields['category'] = category;
      if (captureDate != null) request.fields['captureDate'] = captureDate.toIso8601String();

      request.files.add(await http.MultipartFile.fromPath(
        'photo',
        photoFile.path,
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
