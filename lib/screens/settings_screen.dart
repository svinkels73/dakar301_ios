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

    List<RallyInfo> rallies = [];
    if (connected) {
      rallies = await StagesService.getRallies();
    }

    setState(() {
      _isConnected = connected;
      _config = config;
      _rallies = rallies;
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

    final config = await StagesService.getStagesConfig(forceRefresh: true);

    setState(() {
      _isConnected = true;
      _config = config;
      _isSyncing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stages synchronized from server'),
          backgroundColor: Colors.green,
        ),
      );
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

  Future<void> _deleteStage(Stage stage) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete Stage', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${stage.name}"?\n\nFiles already uploaded will be preserved.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      final success = await StagesService.deleteStage(stage.id);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stage "${stage.name}" deleted'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to delete stage';
        });
      }
    }
  }

  Future<void> _createNewRally() async {
    final nameController = TextEditingController();
    DateTime startDate = DateTime.now();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text('Create New Rally', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Rally Name',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText: 'e.g. Baja 2025, Africa Eco Race 2026',
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'An empty rally will be created. You can add stages later.',
                          style: TextStyle(color: Colors.blue, fontSize: 12),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'].toString().isNotEmpty) {
      setState(() => _isLoading = true);

      final success = await StagesService.createRally(result['name']);

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

  Future<void> _deleteRally(RallyInfo rally) async {
    if (rally.name == _config?.rallyName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete the active rally'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete Rally', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${rally.name}"?\n\n'
          'Warning: This will delete all stages configuration for this rally. '
          'Files already uploaded will NOT be deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      final success = await StagesService.deleteRally(rally.id);

      if (success) {
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rally "${rally.name}" deleted'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to delete rally';
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
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              subtitle: Text(
                isActive ? 'Cannot delete active rally' : 'Remove this rally',
                style: const TextStyle(color: Colors.white54),
              ),
              enabled: !isActive,
              onTap: isActive
                  ? null
                  : () {
                      Navigator.pop(context);
                      _deleteRally(rally);
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
                // Connection status
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

                // Rallies section (if we have multiple rallies or connected)
                if (_isConnected && _rallies.isNotEmpty) ...[
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
                                    if (isActive)
                                      const Icon(Icons.check_circle, color: Color(0xFFe94560), size: 16),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${rally.stagesCount} stages',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white24),
                ],

                // Rally info (active rally)
                if (_config != null)
                  InkWell(
                    onTap: _isConnected ? _editRallyName : null,
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
                                    Text(
                                      _config!.rallyName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
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
                          if (_isConnected)
                            const Icon(Icons.edit, color: Colors.white54, size: 20),
                        ],
                      ),
                    ),
                  ),

                const Divider(color: Colors.white24),

                // Stages list
                Expanded(
                  child: _config == null || _config!.stages.isEmpty
                      ? const Center(
                          child: Text(
                            'No stages configured',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ReorderableListView.builder(
                          itemCount: _config!.stages.length,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onReorder: (oldIndex, newIndex) {
                            // TODO: Implement reorder
                          },
                          itemBuilder: (context, index) {
                            final stage = _config!.stages[index];
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
                                trailing: isCurrent
                                    ? Container(
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
                                      )
                                    : _isConnected
                                        ? PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, color: Colors.white54),
                                            color: const Color(0xFF16213e),
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                _editStage(stage);
                                              } else if (value == 'delete') {
                                                _deleteStage(stage);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit, color: Colors.white70, size: 20),
                                                    SizedBox(width: 8),
                                                    Text('Edit', style: TextStyle(color: Colors.white)),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete, color: Colors.red, size: 20),
                                                    SizedBox(width: 8),
                                                    Text('Delete', style: TextStyle(color: Colors.red)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          )
                                        : null,
                                onTap: _isConnected ? () => _editStage(stage) : null,
                              ),
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
