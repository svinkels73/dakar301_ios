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

    setState(() {
      _isConnected = connected;
      _config = config;
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
      builder: (context) => const AddStageDialog(),
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

  Future<void> _deleteStage(Stage stage) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete Stage', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${stage.name}"?',
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

                // Rally info
                if (_config != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _config!.rallyName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${_config!.stages.length} stages',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),

                // Stages list
                Expanded(
                  child: _config == null || _config!.stages.isEmpty
                      ? const Center(
                          child: Text(
                            'No stages configured',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _config!.stages.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final stage = _config!.stages[index];
                            final isCurrent = stage.containsDate(DateTime.now());

                            return Card(
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
                                    fontWeight:
                                        isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  stage.startDate == stage.endDate
                                      ? _formatDate(stage.startDate)
                                      : '${_formatDate(stage.startDate)} - ${_formatDate(stage.endDate)}',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                trailing: isCurrent
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
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
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white54,
                                        ),
                                        onPressed: () => _deleteStage(stage),
                                      ),
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

class AddStageDialog extends StatefulWidget {
  const AddStageDialog({super.key});

  @override
  State<AddStageDialog> createState() => _AddStageDialogState();
}

class _AddStageDialogState extends State<AddStageDialog> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _autoGenerateId() {
    final name = _nameController.text.trim().toLowerCase();
    final id = name
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    _idController.text = id;
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
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
      title: const Text('Add Stage', style: TextStyle(color: Colors.white)),
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
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Stage ID',
                labelStyle: TextStyle(color: Colors.white60),
                hintText: 'e.g. etape_13',
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
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectStartDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start Date',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(_startDate),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _selectEndDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'End Date',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(_endDate),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
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
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFe94560),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
