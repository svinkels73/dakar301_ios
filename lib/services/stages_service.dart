import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stage.dart';
import 'api_service.dart';

class StagesService {
  // Storage keys
  static const String _cacheKey = 'stages_config_cache';
  static const String _selectedRallyKey = 'selected_rally_id';
  static const String _closedRalliesKey = 'closed_rallies_local';
  static const String _localRalliesKey = 'local_rallies_configs';
  static const String _pendingChangesKey = 'pending_rally_changes';

  // In-memory cache
  static StagesConfig? _cachedConfig;
  static String? _selectedRallyId;
  static Set<String>? _closedRallies;
  static Map<String, StagesConfig>? _localRalliesCache;
  static List<PendingChange>? _pendingChanges;

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

  // ============ SELECTED RALLY ============

  static Future<String?> getSelectedRallyId() async {
    if (_selectedRallyId != null) return _selectedRallyId;

    final prefs = await SharedPreferences.getInstance();
    _selectedRallyId = prefs.getString(_selectedRallyKey);
    return _selectedRallyId;
  }

  // ============ AUTO-ACTIVATION BY DATE ============

  /// Check all rallies and auto-activate the one that matches today's date
  /// Returns the rally that was activated, or null if no change
  static Future<RallyInfo?> checkAndAutoActivateRally() async {
    final currentRallyId = await getSelectedRallyId();
    final rallies = await getVisibleRallies();

    if (rallies.isEmpty) return null;

    // Find a rally that should be active today
    RallyInfo? rallyToActivate;
    for (final rally in rallies) {
      if (rally.shouldAutoActivate()) {
        // If we already have this rally selected, no change needed
        if (rally.id == currentRallyId) {
          return null;
        }
        rallyToActivate = rally;
        break;
      }
    }

    // If found a rally to activate, switch to it
    if (rallyToActivate != null) {
      await switchRally(rallyToActivate.id);
      return rallyToActivate;
    }

    return null;
  }

  /// Check if auto-activation should run (useful for periodic checks)
  static Future<bool> shouldCheckAutoActivation() async {
    // Could add logic here to limit frequency of checks
    // For now, always return true
    return true;
  }

  // ============ STAGES CONFIG (for active rally) ============

  static Future<StagesConfig> getStagesConfig({bool forceRefresh = false}) async {
    if (_cachedConfig != null && !forceRefresh) {
      return _cachedConfig!;
    }

    final selectedRallyId = await getSelectedRallyId();

    // Try to fetch from server
    try {
      String url = '${ApiService.baseUrl}/stages';
      if (selectedRallyId != null) {
        url = '${ApiService.baseUrl}/rallies/$selectedRallyId';
      }

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final config = StagesConfig.fromJson(json.decode(response.body));
        _cachedConfig = config;
        await _saveToCache(config);
        if (selectedRallyId != null) {
          await _saveRallyConfigLocally(selectedRallyId, config);
        }
        return config;
      }
    } catch (e) {
      // Server not available
    }

    // Try local cache for selected rally
    if (selectedRallyId != null) {
      final localConfig = await _getRallyConfigFromLocal(selectedRallyId);
      if (localConfig != null) {
        _cachedConfig = localConfig;
        return localConfig;
      }
    }

    // Try general cache
    final cached = await _loadFromCache();
    if (cached != null) {
      _cachedConfig = cached;
      return cached;
    }

    _cachedConfig = defaultConfig;
    return defaultConfig;
  }

  static Future<Stage?> getCurrentStage() async {
    final config = await getStagesConfig();
    return config.getCurrentStage();
  }

  static Future<Stage?> getStageForDate(DateTime date) async {
    final config = await getStagesConfig();
    return config.getStageForDate(date);
  }

  // ============ GET CONFIG FOR ANY RALLY ============

  static Future<StagesConfig?> getRallyConfig(String rallyId) async {
    // Try server first
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/rallies/$rallyId'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final config = StagesConfig.fromJson(json.decode(response.body));
        await _saveRallyConfigLocally(rallyId, config);
        return config;
      }
    } catch (e) {
      // Server not available
    }

    // Fallback to local
    return await _getRallyConfigFromLocal(rallyId);
  }

  // ============ UPDATE STAGE (for any rally, offline support) ============

  static Future<bool> updateRallyStage(String rallyId, Stage stage) async {
    // Get current config for this rally
    StagesConfig? currentConfig = await getRallyConfig(rallyId);

    if (currentConfig == null) {
      // Rally not found anywhere
      return false;
    }

    // Update the stage in the config
    final updatedStages = <Stage>[];
    bool found = false;
    for (final s in currentConfig.stages) {
      if (s.id == stage.id) {
        updatedStages.add(stage);
        found = true;
      } else {
        updatedStages.add(s);
      }
    }
    if (!found) {
      updatedStages.add(stage);
    }

    // Sort stages by date (allows multiple stages on the same day)
    updatedStages.sort((a, b) {
      final dateCompare = a.startDate.compareTo(b.startDate);
      if (dateCompare != 0) return dateCompare;
      // If same date, sort by name
      return a.name.compareTo(b.name);
    });

    final updatedConfig = StagesConfig(
      rallyName: currentConfig.rallyName,
      stages: updatedStages,
    );

    // Try to save to server
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/rallies/$rallyId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updatedConfig.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await _saveRallyConfigLocally(rallyId, updatedConfig);
        // Update active config cache if this is the selected rally
        final selectedId = await getSelectedRallyId();
        if (selectedId == rallyId) {
          _cachedConfig = updatedConfig;
          await _saveToCache(updatedConfig);
        }
        return true;
      }
    } catch (e) {
      // Server not available - save locally and queue change
    }

    // Save locally and queue for sync
    await _saveRallyConfigLocally(rallyId, updatedConfig);
    await _addPendingChange(PendingChange(
      type: ChangeType.updateRally,
      rallyId: rallyId,
      data: updatedConfig.toJson(),
      timestamp: DateTime.now(),
    ));

    // Update active config cache if this is the selected rally
    final selectedId = await getSelectedRallyId();
    if (selectedId == rallyId) {
      _cachedConfig = updatedConfig;
      await _saveToCache(updatedConfig);
    }

    return true; // Saved locally
  }

  // Legacy method - now uses updateRallyStage
  static Future<bool> addStage(Stage stage) async {
    final selectedRallyId = await getSelectedRallyId();

    if (selectedRallyId != null) {
      return await updateRallyStage(selectedRallyId, stage);
    } else {
      // Default rally - try server
      try {
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/stages'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(stage.toJson()),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          await getStagesConfig(forceRefresh: true);
          return true;
        }
      } catch (e) {
        // Server not available
      }
      return false;
    }
  }

  static Future<bool> updateStagesConfig(StagesConfig config) async {
    final selectedRallyId = await getSelectedRallyId();

    if (selectedRallyId != null) {
      // Update via rally endpoint
      try {
        final response = await http.put(
          Uri.parse('${ApiService.baseUrl}/rallies/$selectedRallyId'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(config.toJson()),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          _cachedConfig = config;
          await _saveToCache(config);
          await _saveRallyConfigLocally(selectedRallyId, config);
          return true;
        }
      } catch (e) {
        // Save locally
      }

      // Save locally and queue
      await _saveRallyConfigLocally(selectedRallyId, config);
      await _addPendingChange(PendingChange(
        type: ChangeType.updateRally,
        rallyId: selectedRallyId,
        data: config.toJson(),
        timestamp: DateTime.now(),
      ));
      _cachedConfig = config;
      await _saveToCache(config);
      return true;
    } else {
      // Default rally
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
      } catch (e) {
        // Cannot update default rally offline
      }
      return false;
    }
  }

  static Future<bool> deleteStage(String stageId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/stages/$stageId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await getStagesConfig(forceRefresh: true);
        return true;
      }
    } catch (e) {
      // Cannot delete stage offline
    }
    return false;
  }

  // ============ RALLIES LIST ============

  static Future<List<RallyInfo>> getRallies() async {
    List<RallyInfo> serverRallies = [];

    // Try to fetch from server
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/rallies'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        serverRallies = data.map((r) => RallyInfo.fromJson(r as Map<String, dynamic>)).toList();

        // Save to local cache
        await _saveRalliesListLocally(serverRallies);
      }
    } catch (e) {
      // Server not available
    }

    // If we have server rallies, merge with local-only rallies
    if (serverRallies.isNotEmpty) {
      final localOnlyRallies = await _getLocalOnlyRallies(serverRallies);
      return [...serverRallies, ...localOnlyRallies];
    }

    // Return local rallies if server unavailable
    return await _getAllLocalRallies();
  }

  static Future<List<RallyInfo>> getVisibleRallies() async {
    final allRallies = await getRallies();
    final closed = await getClosedRallies();
    return allRallies.where((r) => !closed.contains(r.id)).toList();
  }

  // ============ CREATE RALLY (with offline support) ============

  static Future<bool> createRally(String rallyName, {List<Stage>? stages}) async {
    final rallyId = _generateRallyId(rallyName);

    // Sort stages by date if provided
    final sortedStages = stages != null ? List<Stage>.from(stages) : <Stage>[];
    if (sortedStages.isNotEmpty) {
      sortedStages.sort((a, b) {
        final dateCompare = a.startDate.compareTo(b.startDate);
        if (dateCompare != 0) return dateCompare;
        return a.name.compareTo(b.name);
      });
    }

    final config = StagesConfig(
      rallyName: rallyName,
      stages: sortedStages,
    );

    // Try server first
    try {
      final body = {
        'name': rallyName,
        if (sortedStages.isNotEmpty) 'stages': sortedStages.map((s) => s.toJson()).toList(),
      };

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/rallies'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Get the actual rally ID from server response if available
        try {
          final responseData = json.decode(response.body);
          final serverId = responseData['id'] ?? responseData['rallyId'] ?? rallyId;
          await _saveRallyConfigLocally(serverId, config);
        } catch (_) {
          await _saveRallyConfigLocally(rallyId, config);
        }
        return true;
      }
    } catch (e) {
      // Server not available - create locally
    }

    // Create locally and queue for sync
    await _saveRallyConfigLocally(rallyId, config);
    await _addPendingChange(PendingChange(
      type: ChangeType.createRally,
      rallyId: rallyId,
      data: {
        'name': rallyName,
        'config': config.toJson(),
      },
      timestamp: DateTime.now(),
    ));

    return true; // Created locally
  }

  static Future<bool> createRallyWithStages({
    required String rallyName,
    required DateTime firstRacingDay,
    required int numberOfStages,
    bool includePreRally = false,
    bool includePostRally = false,
  }) async {
    final stages = <Stage>[];

    // Pre-Rally (day before first racing day)
    if (includePreRally) {
      final preRallyDate = firstRacingDay.subtract(const Duration(days: 1));
      stages.add(Stage(
        id: 'pre_rally',
        name: 'Pre-Rally',
        startDate: preRallyDate,
        endDate: preRallyDate,
      ));
    }

    // Regular stages (start on first racing day)
    DateTime currentDate = firstRacingDay;
    for (int i = 1; i <= numberOfStages; i++) {
      final stageId = 'stage_${i.toString().padLeft(2, '0')}';
      final stageName = 'Stage $i';

      stages.add(Stage(
        id: stageId,
        name: stageName,
        startDate: currentDate,
        endDate: currentDate,
      ));
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Post-Rally stage (day after last racing day)
    if (includePostRally) {
      stages.add(Stage(
        id: 'post_rally',
        name: 'Post-Rally',
        startDate: currentDate,
        endDate: currentDate,
      ));
    }

    return await createRally(rallyName, stages: stages);
  }

  // ============ SWITCH RALLY ============

  static Future<bool> switchRally(String rallyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedRallyKey, rallyId);
      _selectedRallyId = rallyId;
      _cachedConfig = null;

      // Try to fetch from server
      try {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/rallies/$rallyId'),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final config = StagesConfig.fromJson(json.decode(response.body));
          _cachedConfig = config;
          await _saveToCache(config);
          await _saveRallyConfigLocally(rallyId, config);
          return true;
        }
      } catch (e) {
        // Server not available
      }

      // Try local config
      final localConfig = await _getRallyConfigFromLocal(rallyId);
      if (localConfig != null) {
        _cachedConfig = localConfig;
        await _saveToCache(localConfig);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // ============ DELETE RALLY ============

  static Future<bool> deleteRally(String rallyId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/rallies/$rallyId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await _removeRallyFromLocal(rallyId);
        return true;
      }
    } catch (e) {
      // If it's a local-only rally, just remove it
      final localRallies = await _getLocalRalliesMap();
      if (localRallies.containsKey(rallyId)) {
        await _removeRallyFromLocal(rallyId);
        // Also remove any pending changes for this rally
        await _removePendingChangesForRally(rallyId);
        return true;
      }
    }
    return false;
  }

  // ============ DUPLICATE RALLY ============

  static Future<bool> duplicateRally(String sourceRallyId, String newName, DateTime newStartDate) async {
    // Try server first
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

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (e) {
      // Server not available - duplicate locally
    }

    // Duplicate locally
    final sourceConfig = await getRallyConfig(sourceRallyId);
    if (sourceConfig == null) return false;

    // Calculate date offset
    final originalStart = sourceConfig.stages.isNotEmpty
        ? sourceConfig.stages.first.startDate
        : DateTime.now();
    final daysDiff = newStartDate.difference(originalStart).inDays;

    // Create new stages with adjusted dates
    final newStages = sourceConfig.stages.map((s) => Stage(
      id: s.id,
      name: s.name,
      startDate: s.startDate.add(Duration(days: daysDiff)),
      endDate: s.endDate.add(Duration(days: daysDiff)),
    )).toList();

    return await createRally(newName, stages: newStages);
  }

  // ============ CLOSED RALLIES (LOCAL ONLY) ============

  static Future<Set<String>> getClosedRallies() async {
    if (_closedRallies != null) return _closedRallies!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> closed = prefs.getStringList(_closedRalliesKey) ?? [];
      _closedRallies = closed.toSet();
      return _closedRallies!;
    } catch (e) {
      _closedRallies = {};
      return _closedRallies!;
    }
  }

  static Future<bool> closeRallyLocally(String rallyId) async {
    try {
      final closed = await getClosedRallies();
      closed.add(rallyId);
      _closedRallies = closed;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_closedRalliesKey, closed.toList());

      if (_selectedRallyId == rallyId) {
        await prefs.remove(_selectedRallyKey);
        _selectedRallyId = null;
        _cachedConfig = null;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> reopenRallyLocally(String rallyId) async {
    try {
      final closed = await getClosedRallies();
      closed.remove(rallyId);
      _closedRallies = closed;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_closedRalliesKey, closed.toList());

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<int> getClosedRalliesCount() async {
    final closed = await getClosedRallies();
    return closed.length;
  }

  static Future<bool> isRallyClosed(String rallyId) async {
    final closed = await getClosedRallies();
    return closed.contains(rallyId);
  }

  // ============ PENDING CHANGES SYNC ============

  static Future<int> getPendingChangesCount() async {
    final changes = await _getPendingChanges();
    return changes.length;
  }

  static Future<bool> hasPendingChanges() async {
    final count = await getPendingChangesCount();
    return count > 0;
  }

  static Future<SyncResult> syncPendingChanges() async {
    final changes = await _getPendingChanges();
    if (changes.isEmpty) {
      return SyncResult(synced: 0, failed: 0, remaining: 0);
    }

    int synced = 0;
    int failed = 0;
    final remainingChanges = <PendingChange>[];

    for (final change in changes) {
      bool success = false;

      try {
        switch (change.type) {
          case ChangeType.createRally:
            final name = change.data['name'] as String;
            final configData = change.data['config'] as Map<String, dynamic>;
            final stages = (configData['stages'] as List<dynamic>?)
                ?.map((s) => Stage.fromJson(s as Map<String, dynamic>))
                .toList();

            final response = await http.post(
              Uri.parse('${ApiService.baseUrl}/rallies'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'name': name,
                if (stages != null) 'stages': stages.map((s) => s.toJson()).toList(),
              }),
            ).timeout(const Duration(seconds: 10));

            success = response.statusCode == 200 || response.statusCode == 201;
            break;

          case ChangeType.updateRally:
            final response = await http.put(
              Uri.parse('${ApiService.baseUrl}/rallies/${change.rallyId}'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(change.data),
            ).timeout(const Duration(seconds: 10));

            success = response.statusCode == 200;
            break;

          case ChangeType.deleteRally:
            final response = await http.delete(
              Uri.parse('${ApiService.baseUrl}/rallies/${change.rallyId}'),
            ).timeout(const Duration(seconds: 10));

            success = response.statusCode == 200;
            break;
        }
      } catch (e) {
        success = false;
      }

      if (success) {
        synced++;
      } else {
        failed++;
        remainingChanges.add(change);
      }
    }

    // Save remaining changes
    await _savePendingChanges(remainingChanges);
    _pendingChanges = remainingChanges;

    return SyncResult(synced: synced, failed: failed, remaining: remainingChanges.length);
  }

  // ============ PRIVATE HELPERS ============

  static String _generateRallyId(String name) {
    final base = name.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    return '${base}_$timestamp';
  }

  static Future<void> _saveToCache(StagesConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(config.toJson()));
    } catch (e) {
      // Ignore
    }
  }

  static Future<StagesConfig?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        return StagesConfig.fromJson(json.decode(cached));
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  static Future<void> clearCache() async {
    _cachedConfig = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      // Ignore
    }
  }

  // Local rallies storage
  static Future<Map<String, StagesConfig>> _getLocalRalliesMap() async {
    if (_localRalliesCache != null) return _localRalliesCache!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_localRalliesKey);
      if (data != null) {
        final Map<String, dynamic> decoded = json.decode(data);
        _localRalliesCache = decoded.map((key, value) =>
            MapEntry(key, StagesConfig.fromJson(value as Map<String, dynamic>)));
        return _localRalliesCache!;
      }
    } catch (e) {
      // Ignore
    }

    _localRalliesCache = {};
    return _localRalliesCache!;
  }

  static Future<void> _saveRallyConfigLocally(String rallyId, StagesConfig config) async {
    try {
      final rallies = await _getLocalRalliesMap();
      rallies[rallyId] = config;
      _localRalliesCache = rallies;

      final prefs = await SharedPreferences.getInstance();
      final data = rallies.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_localRalliesKey, json.encode(data));
    } catch (e) {
      // Ignore
    }
  }

  static Future<StagesConfig?> _getRallyConfigFromLocal(String rallyId) async {
    final rallies = await _getLocalRalliesMap();
    return rallies[rallyId];
  }

  static Future<void> _removeRallyFromLocal(String rallyId) async {
    try {
      final rallies = await _getLocalRalliesMap();
      rallies.remove(rallyId);
      _localRalliesCache = rallies;

      final prefs = await SharedPreferences.getInstance();
      final data = rallies.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_localRalliesKey, json.encode(data));
    } catch (e) {
      // Ignore
    }
  }

  static Future<List<RallyInfo>> _getAllLocalRallies() async {
    final rallies = await _getLocalRalliesMap();
    return rallies.entries.map((e) => RallyInfo(
      id: e.key,
      name: e.value.rallyName,
      stagesCount: e.value.stages.length,
      startDate: e.value.stages.isNotEmpty ? e.value.stages.first.startDate : null,
      isLocal: true,
    )).toList();
  }

  static Future<List<RallyInfo>> _getLocalOnlyRallies(List<RallyInfo> serverRallies) async {
    final serverIds = serverRallies.map((r) => r.id).toSet();
    final allLocal = await _getAllLocalRallies();
    return allLocal.where((r) => !serverIds.contains(r.id)).toList();
  }

  static Future<void> _saveRalliesListLocally(List<RallyInfo> rallies) async {
    // We don't need to save the list separately since we have individual configs
    // But we could cache the list for faster access
  }

  // Pending changes
  static Future<List<PendingChange>> _getPendingChanges() async {
    if (_pendingChanges != null) return _pendingChanges!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_pendingChangesKey);
      if (data != null) {
        final List<dynamic> decoded = json.decode(data);
        _pendingChanges = decoded.map((e) => PendingChange.fromJson(e as Map<String, dynamic>)).toList();
        return _pendingChanges!;
      }
    } catch (e) {
      // Ignore
    }

    _pendingChanges = [];
    return _pendingChanges!;
  }

  static Future<void> _savePendingChanges(List<PendingChange> changes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = changes.map((c) => c.toJson()).toList();
      await prefs.setString(_pendingChangesKey, json.encode(data));
      _pendingChanges = changes;
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> _addPendingChange(PendingChange change) async {
    final changes = await _getPendingChanges();

    // Remove any existing change for the same rally and type
    changes.removeWhere((c) => c.rallyId == change.rallyId && c.type == change.type);
    changes.add(change);

    await _savePendingChanges(changes);
  }

  static Future<void> _removePendingChangesForRally(String rallyId) async {
    final changes = await _getPendingChanges();
    changes.removeWhere((c) => c.rallyId == rallyId);
    await _savePendingChanges(changes);
  }
}

// ============ DATA CLASSES ============

enum ChangeType {
  createRally,
  updateRally,
  deleteRally,
}

class PendingChange {
  final ChangeType type;
  final String rallyId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  PendingChange({
    required this.type,
    required this.rallyId,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'rallyId': rallyId,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PendingChange.fromJson(Map<String, dynamic> json) => PendingChange(
    type: ChangeType.values.firstWhere((e) => e.name == json['type']),
    rallyId: json['rallyId'] as String,
    data: json['data'] as Map<String, dynamic>,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

class SyncResult {
  final int synced;
  final int failed;
  final int remaining;

  SyncResult({required this.synced, required this.failed, required this.remaining});
}
