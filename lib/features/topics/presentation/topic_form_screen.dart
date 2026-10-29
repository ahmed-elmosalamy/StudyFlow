import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation.dart';
import '../../../data/database/tables.dart';
import '../providers/topics_providers.dart';

class TopicFormScreen extends ConsumerStatefulWidget {
  const TopicFormScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<TopicFormScreen> createState() => _TopicFormScreenState();
}

class _TopicFormScreenState extends ConsumerState<TopicFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  var _status = TopicStatus.not_started;
  String? _titleError;
  var _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _titleError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final notes = _notesController.text.trim();
    try {
      await ref
          .read(topicRepositoryProvider)
          .insert(
            subjectId: widget.subjectId,
            title: _titleController.text,
            notes: notes.isEmpty ? null : notes,
            status: _status,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _titleError = error.message;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save topic: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New topic')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const ValueKey('topic-title-field'),
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'What will you learn?',
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
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
              if (_titleError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _titleError!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('topic-notes-field'),
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional notes about this topic',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<TopicStatus>(
                key: const ValueKey('topic-status-field'),
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: TopicStatus.not_started,
                    child: Text('Not started'),
                  ),
                  DropdownMenuItem(
                    value: TopicStatus.learning,
                    child: Text('Learning'),
                  ),
                  DropdownMenuItem(
                    value: TopicStatus.learned,
                    child: Text('Learned'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _status = value);
                  }
                },
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('topic-save-button'),
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
