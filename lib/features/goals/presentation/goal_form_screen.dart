import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/validation.dart';
import '../goal_colors.dart';

class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key});

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  var _selectedColor = 0;
  String? _titleError;
  var _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _titleError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final description = _descriptionController.text.trim();
    try {
      await ref
          .read(goalRepositoryProvider)
          .insert(
            title: _titleController.text,
            description: description.isEmpty ? null : description,
            colorIndex: _selectedColor,
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
      ).showSnackBar(SnackBar(content: Text('Could not save goal: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New goal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const ValueKey('goal-title-field'),
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'What do you want to achieve?',
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
                key: const ValueKey('goal-description-field'),
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional notes about this goal',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text('Color', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < goalColorOptions.length; index++)
                    Tooltip(
                      message: goalColorLabels[index],
                      child: InkWell(
                        key: ValueKey('goal-color-$index'),
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _selectedColor = index),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: goalColorOptions[index],
                            shape: BoxShape.circle,
                            border: _selectedColor == index
                                ? Border.all(
                                    color: colorScheme.onSurface,
                                    width: 3,
                                  )
                                : null,
                          ),
                          child: _selectedColor == index
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 22,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('goal-save-button'),
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
