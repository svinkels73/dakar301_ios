import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stage.dart';
import '../services/stages_service.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isConnected = false;
  StagesConfig? _config;
  List<RallyInfo> _rallies = [];
  String _errorMessage = '';
  int _closedRalliesCount = 0;
  int _pendingChangesCount = 0;
  String? _editingRallyId; // Rally being edited (null = active rally)
  StagesConfig? _editingRallyConfig; // Config of rally being edited

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final connected = await ApiService.checkConnection();
    final config = await StagesService.getStagesConfig(forceRefresh: connected);
    final closedCount = await StagesService.getClosedRalliesCount();
    final pendingCount = await StagesService.getPendingChangesCount();

    // Always load rallies (includes local-only rallies when offline)
    List<RallyInfo> rallies = await StagesService.getVisibleRallies();

    // If we're editing a specific rally, load its config
    StagesConfig? editingConfig;
    if (_editingRallyId != null) {
      editingConfig = await StagesService.getRallyConfig(_editingRallyId!);
    }

    setState(() {
      _isConnected = connected;
      _config = config;
      _rallies = rallies;
      _closedRalliesCount = closedCount;
      _pendingChangesCount = pendingCount;
      _editingRallyConfig = editingConfig;
      _isLoading = false;
    });
  }

  Future<void> _syncFromServer() async {
    setState(() {
      _isSyncing = true;
      _errorMessage = '';
    });

    final connected = await ApiService.checkConnection();
    if (!connected) {
      setState(() {
        _isSyncing = false;
        _errorMessage = 'Server not reachable';
      });
      return;
    }

    // First, sync any pending changes TO the server
    final syncResult = await StagesService.syncPendingChanges();

    // Then refresh FROM the server
    final config = await StagesService.getStagesConfig(forceRefresh: true);
    final pendingCount = await StagesService.getPendingChangesCount();

    setState(() {
      _isConnected = true;
      _config = config;
      _pendingChangesCount = pendingCount;
      _isSyncing = false;
    });

    if (mounted) {
      String message = 'Synchronized with server';
      if (syncResult.synced > 0) {
        message = '${syncResult.synced} change(s) synced to server';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _editRallyStages(RallyInfo rally) async {
    // Load the rally's config for editing
    setState(() => _isLoading = true);

    final config = await StagesService.getRallyConfig(rally.id);

    if (config == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load rally configuration';
      });
      return;
    }

    setState(() {
      _editingRallyId = rally.id;
      _editingRallyConfig = config;
      _isLoading = false;
    });
  }

  void _stopEditingRally() {
    setState(() {
      _editingRallyId = null;
      _editingRallyConfig = null;
    });
  }

  Future<void> _editStageForRally(String rallyId, Stage stage) async {
    final result = await showDialog<Stage>(
      context: context,
      builder: (context) => StageEditDialog(isNew: false, stage: stage),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      final success = await StagesService.updateRallyStage(rallyId, result);

      if (success) {
        await _loadConfig();
        if (mounted) {
          final savedLocally = !_isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(savedLocally
                  ? 'Stage saved locally (will sync when connected)'
                  : 'Stage "${result.name}" updated'),
              backgroundColor: savedLocally ? Colors.orange : Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to update stage.';
        });
      }
    }
  }

  Future<void> _addStage() async {
    final result = await showDialog<Stage>(
      context: context,
      builder: (context) => const StageEditDialog(isNew: true),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      final success = await StagesService.addStage(result);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stage "${result.name}" added'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to add stage. Check server connection.';
        });
      }
    }
  }

  Future<void> _editStage(Stage stage) async {
    final result = await showDialog<Stage>(
      context: context,
      builder: (context) => StageEditDialog(isNew: false, stage: stage),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      final success = await StagesService.addStage(result);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stage "${result.name}" updated'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to update stage.';
        });
      }
    }
  }

  Future<void> _createNewRally() async {
    final nameController = TextEditingController();
    DateTime startDate = DateTime.now();
    int numberOfStages = 10;
    bool includePreRally = true;
    int preRallyDays = 2;
    bool includePostRally = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Generate preview stages
          List<Map<String, dynamic>> previewStages = [];
          DateTime currentDate = startDate;

          // Pre-Rally days
          if (includePreRally) {
            for (int i = 1; i <= preRallyDays; i++) {
              previewStages.add({
                'id': 'pre_rally_$i',
                'name': preRallyDays == 1 ? 'Pre-Rally' : 'Pre-Rally Day $i',
                'date': currentDate,
                'isSpecial': true,
              });
              currentDate = currentDate.add(const Duration(days: 1));
            }
          }

          // Regular stages
          for (int i = 1; i <= numberOfStages; i++) {
            previewStages.add({
              'id': 'stage_${i.toString().padLeft(2, '0')}',
              'name': 'Stage $i',
              'date': currentDate,
              'isSpecial': false,
            });
            currentDate = currentDate.add(const Duration(days: 1));
          }

          // Post-Rally (day after last stage)
          if (includePostRally) {
            previewStages.add({
              'id': 'post_rally',
              'name': 'Post-Rally',
              'date': currentDate,
              'isSpecial': true,
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF16213e),
            title: const Text('Create New Rally', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Rally Name',
                      labelStyle: TextStyle(color: Colors.white60),
                      hintText: 'e.g. Dakar 2026, Baja 2025',
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
                        initialDate: startDate,
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
                        setDialogState(() => startDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start Date',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        suffixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                      ),
                      child: Text(
                        DateFormat('dd MMMM yyyy').format(startDate),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Number of stages with +/- buttons
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Number of stages',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white),
                              onPressed: numberOfStages > 1
                                  ? () => setDialogState(() => numberOfStages--)
                                  : null,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                            Container(
                              width: 50,
                              alignment: Alignment.center,
                              child: Text(
                                '$numberOfStages',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white),
                              onPressed: numberOfStages < 30
                                  ? () => setDialogState(() => numberOfStages++)
                                  : null,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Pre-Rally and Post-Rally options
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pre-Rally',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Verifications, shakedown...',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: includePreRally,
                              onChanged: (value) => setDialogState(() => includePreRally = value),
                              activeColor: const Color(0xFFe94560),
                            ),
                          ],
                        ),
                        // Pre-Rally days selector
                        if (includePreRally)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Text(
                                  'Days: ',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                ),
                                const Spacer(),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: preRallyDays > 1
                                            ? () => setDialogState(() => preRallyDays--)
                                            : null,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Icon(
                                            Icons.remove,
                                            size: 16,
                                            color: preRallyDays > 1 ? Colors.orange : Colors.white24,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 30,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$preRallyDays',
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: preRallyDays < 7
                                            ? () => setDialogState(() => preRallyDays++)
                                            : null,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Icon(
                                            Icons.add,
                                            size: 16,
                                            color: preRallyDays < 7 ? Colors.orange : Colors.white24,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(color: Colors.white24, height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Post-Rally',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Prize ceremony, interviews...',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: includePostRally,
                              onChanged: (value) => setDialogState(() => includePostRally = value),
                              activeColor: const Color(0xFFe94560),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Preview section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preview:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: SingleChildScrollView(
                            child: Column(
                              children: previewStages.map((stage) {
                                final isSpecial = stage['isSpecial'] == true;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Text(
                                        isSpecial ? '★ ' : '• ',
                                        style: TextStyle(
                                          color: isSpecial ? Colors.orange : const Color(0xFFe94560),
                                        ),
                                      ),
                                      Text(
                                        stage['name'],
                                        style: TextStyle(
                                          color: isSpecial ? Colors.orange : Colors.white70,
                                          fontSize: 12,
                                          fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      const Text(' - ', style: TextStyle(color: Colors.white38)),
                                      Text(
                                        DateFormat('dd/MM/yyyy').format(stage['date']),
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
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
                            'You can edit stage names and dates after creation.',
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
                onPressed: () => Navigator.pop(context, {
                  'name': nameController.text,
                  'startDate': startDate,
                  'numberOfStages': numberOfStages,
                  'includePreRally': includePreRally,
                  'preRallyDays': preRallyDays,
                  'includePostRally': includePostRally,
                }),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result['name'].toString().isNotEmpty) {
      setState(() => _isLoading = true);

      final success = await StagesService.createRallyWithStages(
        rallyName: result['name'],
        startDate: result['startDate'],
        numberOfStages: result['numberOfStages'],
        includePreRally: result['includePreRally'] ?? false,
        preRallyDays: result['preRallyDays'] ?? 1,
        includePostRally: result['includePostRally'] ?? false,
      );

      if (success) {
        await _loadConfig();
        if (mounted) {
          // Count total stages including pre/post
          int totalStages = result['numberOfStages'] as int;
          if (result['includePreRally'] == true) totalStages += (result['preRallyDays'] as int?) ?? 1;
          if (result['includePostRally'] == true) totalStages++;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rally "${result['name']}" created with $totalStages stages'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to create rally. Check server connection.';
        });
      }
    }
  }

  Future<void> _switchRally(RallyInfo rally) async {
    if (rally.name == _config?.rallyName) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Switch Rally', style: TextStyle(color: Colors.white)),
        content: Text(
          'Switch to "${rally.name}"?\n\nThis will change the active rally for capturing media.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      final success = await StagesService.switchRally(rally.id);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to "${rally.name}"'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to switch rally';
        });
      }
    }
  }

  Future<void> _closeRally(RallyInfo rally) async {
    if (rally.name == _config?.rallyName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot close the active rally. Switch to another rally first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Close Rally?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Close "${rally.name}" on this device?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Data on the server will NOT be deleted.',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This rally will be hidden on this device only.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      final success = await StagesService.closeRallyLocally(rally.id);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rally "${rally.name}" closed on this device'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to close rally';
        });
      }
    }
  }

  Future<void> _manageClosedRallies() async {
    final allRallies = await StagesService.getRallies();
    final closedIds = await StagesService.getClosedRallies();

    final closedRallies = allRallies.where((r) => closedIds.contains(r.id)).toList();

    if (closedRallies.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No closed rallies on this device'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16213e),
            title: const Text('Closed Rallies', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: closedRallies.length,
                itemBuilder: (context, index) {
                  final rally = closedRallies[index];
                  return Card(
                    color: const Color(0xFF1a1a2e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rally.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${rally.stagesCount} stages',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await StagesService.reopenRallyLocally(rally.id);
                                  Navigator.pop(dialogContext);
                                  await _loadConfig();
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('Rally "${rally.name}" reopened'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Reopen'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _confirmDeleteRally(rally, dialogContext),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteRally(RallyInfo rally, BuildContext dialogContext) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete Rally?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete "${rally.name}" from server?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.photo_library, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Media files will NOT be deleted.',
                      style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rally configuration (stages) will be deleted from the server.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.pop(dialogContext); // Close the manage dialog
      setState(() => _isLoading = true);

      // First remove from closed list
      await StagesService.reopenRallyLocally(rally.id);

      // Then delete from server
      final success = await StagesService.deleteRally(rally.id);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rally "${rally.name}" deleted (media preserved)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to delete rally from server';
        });
      }
    }
  }

  void _showRallyOptions(RallyInfo rally) {
    final isActive = rally.name == _config?.rallyName;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                rally.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Edit Stages option (works offline)
            ListTile(
              leading: const Icon(Icons.edit_calendar, color: Color(0xFFe94560)),
              title: const Text('Edit Stages', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                rally.isLocal ? 'Edit stages (local rally)' : 'View and edit stage names/dates',
                style: const TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                _editRallyStages(rally);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('Activate', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Set as active rally', style: TextStyle(color: Colors.white54)),
              enabled: !isActive,
              onTap: isActive
                  ? null
                  : () {
                      Navigator.pop(context);
                      _switchRally(rally);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blue),
              title: const Text('Duplicate', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Create a copy for future event', style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _duplicateRally(rally);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off, color: Colors.orange),
              title: const Text('Close', style: TextStyle(color: Colors.orange)),
              subtitle: Text(
                isActive ? 'Cannot close active rally' : 'Hide on this device (server data preserved)',
                style: const TextStyle(color: Colors.white54),
              ),
              enabled: !isActive,
              onTap: isActive
                  ? null
                  : () {
                      Navigator.pop(context);
                      _closeRally(rally);
                    },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicateRally(RallyInfo rally) async {
    final nameController = TextEditingController(text: '${rally.name} (copy)');
    DateTime startDate = rally.startDate ?? DateTime.now();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text('Duplicate Rally', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'New Rally Name',
                    labelStyle: TextStyle(color: Colors.white60),
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
                      initialDate: startDate,
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
                      setDialogState(() => startDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'New Start Date',
                      labelStyle: TextStyle(color: Colors.white60),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      suffixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                    ),
                    child: Text(
                      DateFormat('dd MMMM yyyy').format(startDate),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.copy, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All ${rally.stagesCount} stages will be copied with adjusted dates.',
                          style: const TextStyle(color: Colors.green, fontSize: 12),
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
              onPressed: () => Navigator.pop(context, {
                'name': nameController.text,
                'startDate': startDate,
              }),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
              child: const Text('Duplicate'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'].toString().isNotEmpty) {
      setState(() => _isLoading = true);

      final success = await StagesService.duplicateRally(rally.id, result['name'], result['startDate']);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rally "${result['name']}" created'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to duplicate rally';
        });
      }
    }
  }

  Future<void> _editRallyName() async {
    final controller = TextEditingController(text: _config?.rallyName ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Edit Rally Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Rally Name',
            labelStyle: TextStyle(color: Colors.white60),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFe94560)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && _config != null) {
      final newConfig = StagesConfig(
        rallyName: result,
        stages: _config!.stages,
      );

      setState(() => _isLoading = true);
      final success = await StagesService.updateStagesConfig(newConfig);

      if (success) {
        await _loadConfig();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to update rally name';
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF16213e),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncFromServer,
            tooltip: 'Sync from server',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Connection status with pending changes indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: _isConnected
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _isConnected ? Colors.green : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected ? 'Connected to server' : 'Offline mode',
                        style: TextStyle(
                          color: _isConnected ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (_pendingChangesCount > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$_pendingChangesCount pending',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Error message
                if (_errorMessage.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.red.withOpacity(0.2),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Rallies section (show even offline with local rallies)
                if (_rallies.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.flag, color: Colors.white54, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'RALLIES',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _createNewRally,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFe94560),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _rallies.length,
                      itemBuilder: (context, index) {
                        final rally = _rallies[index];
                        final isActive = rally.name == _config?.rallyName;

                        return GestureDetector(
                          onTap: () => _switchRally(rally),
                          onLongPress: () => _showRallyOptions(rally),
                          child: Container(
                            width: 140,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFe94560).withOpacity(0.3)
                                  : const Color(0xFF16213e),
                              borderRadius: BorderRadius.circular(12),
                              border: isActive
                                  ? Border.all(color: const Color(0xFFe94560), width: 2)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        rally.name,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (rally.isLocal)
                                      const Tooltip(
                                        message: 'Local only - not synced',
                                        child: Icon(Icons.phone_android, color: Colors.orange, size: 14),
                                      ),
                                    if (isActive)
                                      const Icon(Icons.check_circle, color: Color(0xFFe94560), size: 16),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${rally.stagesCount} stages',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    if (rally.isLocal) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LOCAL',
                                          style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Closed rallies link
                  if (_closedRalliesCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: _manageClosedRallies,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.visibility_off, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Closed rallies on this device: $_closedRalliesCount',
                                style: const TextStyle(color: Colors.orange, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Manage',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const Divider(color: Colors.white24),
                ],

                // Rally info (active rally or editing rally)
                if (_editingRallyId != null && _editingRallyConfig != null)
                  // Editing a specific rally's stages
                  Container(
                    color: Colors.blue.withOpacity(0.1),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: _stopEditingRally,
                          tooltip: 'Back to active rally',
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _editingRallyConfig!.rallyName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'EDITING',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${_editingRallyConfig!.stages.length} stages',
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_config != null)
                  // Active rally info
                  InkWell(
                    onTap: _editRallyName,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _config!.rallyName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFe94560),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${_config!.stages.length} stages',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit, color: Colors.white54, size: 20),
                        ],
                      ),
                    ),
                  ),

                const Divider(color: Colors.white24),

                // Stages list (for editing rally or active rally)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // Determine which config to display
                      final displayConfig = _editingRallyId != null ? _editingRallyConfig : _config;
                      final isEditingOther = _editingRallyId != null;

                      if (displayConfig == null || displayConfig.stages.isEmpty) {
                        return const Center(
                          child: Text(
                            'No stages configured',
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      return ReorderableListView.builder(
                        itemCount: displayConfig.stages.length,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onReorder: (oldIndex, newIndex) {
                          // TODO: Implement reorder
                        },
                        itemBuilder: (context, index) {
                          final stage = displayConfig.stages[index];
                            final isCurrent = stage.containsDate(DateTime.now());
                            final isMultiDay = stage.startDate != stage.endDate;

                            return Card(
                              key: ValueKey(stage.id),
                              color: isCurrent
                                  ? const Color(0xFFe94560).withOpacity(0.3)
                                  : const Color(0xFF16213e),
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFFe94560)
                                        : Colors.white24,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  stage.name,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      isMultiDay
                                          ? '${_formatDate(stage.startDate)} - ${_formatDate(stage.endDate)}'
                                          : _formatDate(stage.startDate),
                                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                                    ),
                                    if (isMultiDay) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${stage.endDate.difference(stage.startDate).inDays + 1} days',
                                          style: const TextStyle(color: Colors.blue, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCurrent && !isEditingOther)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFe94560),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'TODAY',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.white54),
                                      onPressed: () {
                                        if (isEditingOther) {
                                          _editStageForRally(_editingRallyId!, stage);
                                        } else {
                                          _editStage(stage);
                                        }
                                      },
                                      tooltip: 'Edit stage',
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  if (isEditingOther) {
                                    _editStageForRally(_editingRallyId!, stage);
                                  } else {
                                    _editStage(stage);
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                ),

                // Add stage button
                if (_isConnected)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addStage,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Stage'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFe94560),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class StageEditDialog extends StatefulWidget {
  final bool isNew;
  final Stage? stage;

  const StageEditDialog({super.key, required this.isNew, this.stage});

  @override
  State<StageEditDialog> createState() => _StageEditDialogState();
}

class _StageEditDialogState extends State<StageEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _idController;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.stage?.name ?? '');
    _idController = TextEditingController(text: widget.stage?.id ?? '');
    _startDate = widget.stage?.startDate ?? DateTime.now();
    _endDate = widget.stage?.endDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _autoGenerateId() {
    if (widget.isNew) {
      final name = _nameController.text.trim().toLowerCase();
      final id = name
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      _idController.text = id;
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
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
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
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
      setState(() => _endDate = picked);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final id = _idController.text.trim();

    if (name.isEmpty || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final stage = Stage(
      id: id,
      name: name,
      startDate: _startDate,
      endDate: _endDate,
    );

    Navigator.pop(context, stage);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16213e),
      title: Text(
        widget.isNew ? 'Add Stage' : 'Edit Stage',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              onChanged: (_) => _autoGenerateId(),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Stage Name',
                labelStyle: TextStyle(color: Colors.white60),
                hintText: 'e.g. Etape 13 - Shubaytah',
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
              controller: _idController,
              enabled: widget.isNew,
              style: TextStyle(color: widget.isNew ? Colors.white : Colors.white54),
              decoration: InputDecoration(
                labelText: 'Stage ID (folder name)',
                labelStyle: const TextStyle(color: Colors.white60),
                hintText: 'e.g. etape_13',
                hintStyle: const TextStyle(color: Colors.white30),
                helperText: widget.isNew ? null : 'ID cannot be changed',
                helperStyle: const TextStyle(color: Colors.orange),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                disabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white10),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFe94560)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Start Date
            InkWell(
              onTap: _selectStartDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Start Date',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  suffixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                ),
                child: Text(
                  DateFormat('dd MMMM yyyy').format(_startDate),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // End Date
            InkWell(
              onTap: _selectEndDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'End Date',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  suffixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                ),
                child: Text(
                  DateFormat('dd MMMM yyyy').format(_endDate),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),

            if (_startDate != _endDate) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Multi-day stage: ${_endDate.difference(_startDate).inDays + 1} days',
                      style: const TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFe94560),
          ),
          child: Text(widget.isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
