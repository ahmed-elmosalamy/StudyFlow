import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/validation.dart';
import '../../../data/database/tables.dart';
import '../providers/tasks_providers.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, required this.topicId});

  final String topicId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _estimateController = TextEditingController(text: '30');
  var _kind = TaskKind.study;
  var _priority = 1;
  DateTime? _deadline;
  String? _formError;
  var _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final estimate = int.parse(_estimateController.text.trim());
    try {
      await ref
          .read(taskRepositoryProvider)
          .insert(
            topicId: widget.topicId,
            title: _titleController.text,
            kind: _kind,
            priority: _priority,
            estimateMinutes: estimate,
            deadlineDate: _deadline == null ? null : _formatDate(_deadline!),
            // The repository requires a revision stage; 0 is the first stage.
            revisionStage: _kind == TaskKind.revision ? 0 : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = error.message;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save task: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New task')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const ValueKey('task-title-field'),
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'What will you do?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final title = value?.trim() ?? '';
                  if (title.isEmpty) {
                    return 'Title is required.';
                  }
                  if (title.length > 120) {
                    return 'Title must be 120 characters or fewer.';
                  }
                  return null;
                },
                onChanged: (_) {
                  if (_formError != null) {
                    setState(() => _formError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskKind>(
                key: const ValueKey('task-kind-field'),
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Kind',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: TaskKind.study, child: Text('Study')),
                  DropdownMenuItem(
                    value: TaskKind.revision,
                    child: Text('Revision'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _kind = value);
                  }
                },
              ),
              const SizedBox(height: 24),
              Text('Priority', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                key: const ValueKey('task-priority-field'),
                segments: const [
                  ButtonSegment(value: 0, label: Text('Low')),
                  ButtonSegment(value: 1, label: Text('Normal')),
                  ButtonSegment(value: 2, label: Text('High')),
                ],
                selected: {_priority},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _priority = selection.first);
                },
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('task-estimate-field'),
                controller: _estimateController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Estimate minutes',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final estimate = int.tryParse(value?.trim() ?? '');
                  if (estimate == null || estimate < 5 || estimate > 2400) {
                    return 'Estimate must be between 5 and 2400 minutes.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text('Deadline', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('task-deadline-button'),
                      onPressed: _pickDeadline,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _deadline == null
                            ? 'No deadline'
                            : _formatDate(_deadline!),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_deadline != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Clear deadline',
                      onPressed: () => setState(() => _deadline = null),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ],
              ),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _formError!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('task-save-button'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
