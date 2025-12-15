import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stage.dart';
import 'api_service.dart';

class StagesService {
  static const String _cacheKey = 'stages_config_cache';
  static StagesConfig? _cachedConfig;

  // Default configuration for offline use
  static StagesConfig get defaultConfig => StagesConfig(
    rallyName: 'Dakar 2026',
    stages: [
      Stage(id: 'avant_rallye', name: 'Avant Rallye', startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 2)),
      Stage(id: 'prologue', name: 'Prologue', startDate: DateTime(2026, 1, 3), endDate: DateTime(2026, 1, 3)),
      Stage(id: 'etape_01', name: 'Etape 1 - Bisha', startDate: DateTime(2026, 1, 4), endDate: DateTime(2026, 1, 4)),
      Stage(id: 'etape_02', name: 'Etape 2 - Bisha Loop', startDate: DateTime(2026, 1, 5), endDate: DateTime(2026, 1, 5)),
      Stage(id: 'etape_03', name: 'Etape 3 - Bisha > Al Henakiyah', startDate: DateTime(2026, 1, 6), endDate: DateTime(2026, 1, 6)),
      Stage(id: 'etape_04', name: 'Etape 4 - Al Henakiyah > AlUla', startDate: DateTime(2026, 1, 7), endDate: DateTime(2026, 1, 7)),
      Stage(id: 'etape_05', name: 'Etape 5 - AlUla > Hail', startDate: DateTime(2026, 1, 8), endDate: DateTime(2026, 1, 8)),
      Stage(id: 'etape_06', name: 'Etape 6 - Hail > Al Duwadimi', startDate: DateTime(2026, 1, 9), endDate: DateTime(2026, 1, 9)),
      Stage(id: 'repos', name: 'Journee de Repos', startDate: DateTime(2026, 1, 10), endDate: DateTime(2026, 1, 10)),
      Stage(id: 'etape_07', name: 'Etape 7 - Al Duwadimi > Riyadh', startDate: DateTime(2026, 1, 11), endDate: DateTime(2026, 1, 11)),
      Stage(id: 'etape_08', name: 'Etape 8 - Riyadh 48h Chrono', startDate: DateTime(2026, 1, 12), endDate: DateTime(2026, 1, 13)),
      Stage(id: 'etape_09', name: 'Etape 9 - Riyadh > Haradh', startDate: DateTime(2026, 1, 14), endDate: DateTime(2026, 1, 14)),
      Stage(id: 'etape_10', name: 'Etape 10 - Haradh > Shaybah', startDate: DateTime(2026, 1, 15), endDate: DateTime(2026, 1, 15)),
      Stage(id: 'etape_11', name: 'Etape 11 - Shaybah > Shaybah', startDate: DateTime(2026, 1, 16), endDate: DateTime(2026, 1, 16)),
      Stage(id: 'etape_12', name: 'Etape 12 - Shaybah > Shubaytah', startDate: DateTime(2026, 1, 17), endDate: DateTime(2026, 1, 17)),
      Stage(id: 'apres_rallye', name: 'Apres Rallye', startDate: DateTime(2026, 1, 18), endDate: DateTime(2026, 1, 20)),
    ],
  );

  // Get stages configuration from server or cache
  static Future<StagesConfig> getStagesConfig({bool forceRefresh = false}) async {
    // Return cached if available and not forcing refresh
    if (_cachedConfig != null && !forceRefresh) {
      return _cachedConfig!;
    }

    // Try to fetch from server
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stages'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final config = StagesConfig.fromJson(json.decode(response.body));
        _cachedConfig = config;
        await _saveToCache(config);
        return config;
      }
    } catch (e) {
      // Server not available, try cache
    }

    // Try to load from cache
    final cached = await _loadFromCache();
    if (cached != null) {
      _cachedConfig = cached;
      return cached;
    }

    // Return default config
    _cachedConfig = defaultConfig;
    return defaultConfig;
  }

  // Get current stage based on today's date
  static Future<Stage?> getCurrentStage() async {
    final config = await getStagesConfig();
    return config.getCurrentStage();
  }

  // Get stage for a specific date
  static Future<Stage?> getStageForDate(DateTime date) async {
    final config = await getStagesConfig();
    return config.getStageForDate(date);
  }

  // Update stages configuration on server
  static Future<bool> updateStagesConfig(StagesConfig config) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/stages'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _cachedConfig = config;
        await _saveToCache(config);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Add a single stage
  static Future<bool> addStage(Stage stage) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stages'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(stage.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Refresh cache
        await getStagesConfig(forceRefresh: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Delete a stage
  static Future<bool> deleteStage(String stageId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/stages/$stageId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Refresh cache
        await getStagesConfig(forceRefresh: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Save to local cache
  static Future<void> _saveToCache(StagesConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(config.toJson()));
    } catch (e) {
      // Ignore cache errors
    }
  }

  // Load from local cache
  static Future<StagesConfig?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        return StagesConfig.fromJson(json.decode(cached));
      }
    } catch (e) {
      // Ignore cache errors
    }
    return null;
  }

  // Clear cache
  static Future<void> clearCache() async {
    _cachedConfig = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      // Ignore
    }
  }

  // Get list of all rallies
  static Future<List<RallyInfo>> getRallies() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/rallies'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((r) => RallyInfo.fromJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // Server not available
    }
    return [];
  }

  // Create a new rally
  static Future<bool> createRally(String rallyName, {List<Stage>? stages}) async {
    try {
      final body = {
        'name': rallyName,
        if (stages != null) 'stages': stages.map((s) => s.toJson()).toList(),
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rallies'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  // Switch to a different rally
  static Future<bool> switchRally(String rallyId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rallies/$rallyId/activate'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Refresh cache with new rally data
        await getStagesConfig(forceRefresh: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Delete a rally
  static Future<bool> deleteRally(String rallyId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/rallies/$rallyId'),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Duplicate an existing rally with new name and dates
  static Future<bool> duplicateRally(String sourceRallyId, String newName, DateTime newStartDate) async {
    try {
      final body = {
        'name': newName,
        'startDate': newStartDate.toIso8601String().split('T')[0],
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rallies/$sourceRallyId/duplicate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
