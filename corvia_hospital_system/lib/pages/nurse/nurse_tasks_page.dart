import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_controller_scope.dart';

class NurseTasksPage extends StatefulWidget {
  const NurseTasksPage({super.key, this.service, this.showAppBar = true});

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseTasksPage> createState() => _NurseTasksPageState();
}

class _NurseTasksPageState extends State<NurseTasksPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final NurseService _service = widget.service ?? NurseService();
  NurseWorkspace? _workspace;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isUpdating = false;

  String? _errorMessage;
  String _selectedFilter = 'Active';

  List<Map<String, dynamic>> _tasks = [];

  static const List<String> _filters = [
    'Active',
    'Pending',
    'In Progress',
    'Completed',
    'All',
  ];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final workspace = await _service.loadWorkspace();
      if (!mounted) return;
      _workspace = workspace;
      _tasks = workspace.tasks;

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  String _patientName(Map<String, dynamic> task) {
    final patientId = task['patient_id']?.toString();
    return patientId == null || patientId.isEmpty
        ? 'No patient linked'
        : _workspace!.patient(patientId).displayName;
  }

  String _normaliseStatus(dynamic value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        'pending';
  }

  List<Map<String, dynamic>> get _visibleTasks {
    final search = _searchController.text.trim().toLowerCase();

    return _tasks.where((task) {
      final status = _normaliseStatus(task['status']);

      final title = task['title']?.toString().toLowerCase() ?? '';

      final description = task['description']?.toString().toLowerCase() ?? '';

      final patient = _patientName(task).toLowerCase();

      final matchesSearch = search.isEmpty ||
          title.contains(search) ||
          description.contains(search) ||
          patient.contains(search);

      bool matchesFilter = true;

      switch (_selectedFilter) {
        case 'Active':
          matchesFilter = status == 'pending' || status == 'in_progress';
          break;
        case 'Pending':
          matchesFilter = status == 'pending';
          break;
        case 'In Progress':
          matchesFilter = status == 'in_progress';
          break;
        case 'Completed':
          matchesFilter = status == 'completed';
          break;
        case 'All':
          matchesFilter = true;
          break;
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _updateTaskStatus(
    Map<String, dynamic> task,
    String status, {
    String? completionNotes,
  }) async {
    if (_isUpdating) {
      return;
    }

    final taskId = task['id']?.toString();

    if (taskId == null) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final values = <String, dynamic>{
        'status': status,
        'updated_at': now,
      };

      if (status == 'in_progress') {
        values['started_at'] = now;
      }

      if (status == 'completed') {
        values['completed_at'] = now;
        values['completion_notes'] = completionNotes?.trim() ?? '';
      }

      await _supabase.from('nursing_tasks').update(values).eq('id', taskId)
          .eq('assigned_nurse_user_id', _workspace!.context.nurseUserId);

      await _loadTasks();

      _showMessage(
        status == 'completed' ? 'Task completed.' : 'Task status updated.',
      );
    } catch (error) {
      _showMessage(
        'Could not update task. $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _showCompleteDialog(Map<String, dynamic> task) async {
    // Null is cancellation; an empty string is a valid confirmed note.
    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => TextControllerScope(
        initialText: task['completion_notes']?.toString() ?? '',
        builder: (notesController) => AlertDialog(
          title: const Text('Complete Nursing Task'),
          content: TextField(
            controller: notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Completion Notes',
              hintText: 'What was completed or observed?',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(notesController.text),
              icon: const Icon(Icons.check),
              label: const Text('Complete'),
            ),
          ],
        ),
      ),
    );

    if (notes != null && mounted) {
      await _updateTaskStatus(task, 'completed', completionNotes: notes);
    }
  }

  Color _priorityColor(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'urgent':
        return CorviaColors.danger;
      case 'high':
        return CorviaColors.warning;
      case 'low':
        return CorviaColors.success;
      default:
        return CorviaColors.accent;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return CorviaColors.success;
      case 'in_progress':
        return CorviaColors.accent;
      case 'cancelled':
        return CorviaColors.danger;
      default:
        return CorviaColors.warning;
    }
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'No due date';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _visibleTasks;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text('Nursing Tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadTasks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ) : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: CorviaColors.accent,
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadTasks,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      _buildSummary(),
                      const SizedBox(
                        height: 16,
                      ),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search tasks or patients',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _filters.map(
                          (filter) {
                            return ChoiceChip(
                              label: Text(filter),
                              selected: _selectedFilter == filter,
                              selectedColor: CorviaColors.accent.withValues(
                                alpha: 0.14,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _selectedFilter = filter;
                                });
                              },
                            );
                          },
                        ).toList(),
                      ),
                      const SizedBox(
                        height: 18,
                      ),
                      if (visibleTasks.isEmpty)
                        _buildEmptyState()
                      else
                        ...visibleTasks.map(
                          _buildTaskCard,
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummary() {
    final active = _tasks.where((task) {
      final status = _normaliseStatus(task['status']);

      return status == 'pending' || status == 'in_progress';
    }).length;

    final completed = _tasks.where((task) {
      return _normaliseStatus(
            task['status'],
          ) ==
          'completed';
    }).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.task_alt,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$active active task(s)\n'
              '$completed completed task(s)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> task,
  ) {
    final status = _normaliseStatus(task['status']);

    final priority = task['priority']?.toString() ?? 'normal';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.assignment_outlined,
                color: _priorityColor(priority),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task['title']?.toString() ?? 'Nursing Task',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _patientName(task),
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: status.replaceAll('_', ' '),
                color: _statusColor(status),
              ),
            ],
          ),
          if ((task['description']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              task['description'].toString(),
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: 'Priority: $priority',
                color: _priorityColor(priority),
              ),
              _StatusPill(
                label: 'Due: ${_formatDateTime(task['due_at'])}',
                color: CorviaColors.accent,
              ),
            ],
          ),
          if (status == 'pending' || status == 'in_progress') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (status == 'pending')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUpdating
                          ? null
                          : () {
                              _updateTaskStatus(
                                task,
                                'in_progress',
                              );
                            },
                      icon: const Icon(
                        Icons.play_arrow,
                      ),
                      label: const Text(
                        'Start Task',
                      ),
                    ),
                  ),
                if (status == 'pending') const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUpdating
                        ? null
                        : () {
                            _showCompleteDialog(
                              task,
                            );
                          },
                    icon: const Icon(Icons.check),
                    label: const Text(
                      'Complete',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if ((task['completion_notes']?.toString().trim() ?? '')
              .isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Completion notes: '
              '${task['completion_notes']}',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.task_outlined,
            color: context.cTextMuted,
            size: 54,
          ),
          const SizedBox(height: 12),
          Text(
            'No nursing tasks found',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Tasks assigned by the hospital or doctor will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: CorviaColors.danger,
              size: 56,
            ),
            const SizedBox(height: 14),
            SelectableText(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _loadTasks,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
