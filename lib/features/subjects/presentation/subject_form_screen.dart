import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation.dart';
import '../providers/subjects_providers.dart';

class SubjectFormScreen extends ConsumerStatefulWidget {
  const SubjectFormScreen({super.key, required this.goalId});

  final String goalId;

  @override
  ConsumerState<SubjectFormScreen> createState() => _SubjectFormScreenState();
}

class _SubjectFormScreenState extends ConsumerState<SubjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
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
          .read(subjectRepositoryProvider)
          .insert(
            goalId: widget.goalId,
            title: _titleController.text,
            notes: notes.isEmpty ? null : notes,
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
      ).showSnackBar(SnackBar(content: Text('Could not save subject: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New subject')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const ValueKey('subject-title-field'),
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'What area will you study?',
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
                key: const ValueKey('subject-notes-field'),
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional notes about this subject',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('subject-save-button'),
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
