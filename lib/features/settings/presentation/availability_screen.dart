import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation.dart';
import '../../../data/database/app_database.dart';
import '../providers/settings_providers.dart';

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  Future<void> _addWindow(
    BuildContext context,
    int weekday,
    List<AvailabilityWindow> existingWindows,
  ) async {
    var startMinute = 18 * 60;
    var endMinute = 21 * 60;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickStart() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay(
                  hour: startMinute ~/ 60,
                  minute: startMinute % 60,
                ),
              );
              if (picked != null && dialogContext.mounted) {
                setDialogState(() {
                  startMinute = picked.hour * 60 + picked.minute;
                });
              }
            }

            Future<void> pickEnd() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay(
                  hour: endMinute ~/ 60,
                  minute: endMinute % 60,
                ),
              );
              if (picked != null && dialogContext.mounted) {
                setDialogState(() {
                  endMinute = picked.hour * 60 + picked.minute;
                });
              }
            }

            Future<void> save() async {
              try {
                ValidationRules.validateAvailabilityWindow(
                  weekday: weekday,
                  startMinute: startMinute,
                  endMinute: endMinute,
                );
                ValidationRules.validateAvailabilityOverlap(
                  weekday: weekday,
                  startMinute: startMinute,
                  endMinute: endMinute,
                  existing: [
                    for (final window in existingWindows)
                      (
                        weekday: window.weekday,
                        startMinute: window.startMinute,
                        endMinute: window.endMinute,
                      ),
                  ],
                );
              } on ValidationException catch (validationError) {
                setDialogState(() => error = validationError.message);
                return;
              }

              try {
                await ref
                    .read(availabilityRepositoryProvider)
                    .insert(
                      weekday: weekday,
                      startMinute: startMinute,
                      endMinute: endMinute,
                    );
              } on ValidationException catch (validationError) {
                if (dialogContext.mounted) {
                  setDialogState(() => error = validationError.message);
                }
                return;
              } on ConflictException catch (conflictError) {
                if (dialogContext.mounted) {
                  setDialogState(() => error = conflictError.message);
                }
                return;
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }

            return AlertDialog(
              title: Text('Add window - ${_dayName(weekday)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start'),
                    trailing: Text(_formatMinute(startMinute)),
                    onTap: pickStart,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End'),
                    trailing: Text(_formatMinute(endMinute)),
                    onTap: pickEnd,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        key: const ValueKey('window-error'),
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('save-window-button'),
                  onPressed: save,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteWindow(AvailabilityWindow window) async {
    try {
      await ref.read(availabilityRepositoryProvider).deleteOrArchive(window.id);
    } on NotFoundException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final availabilityAsync = ref.watch(availabilityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: availabilityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load availability.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (windows) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Add the weekly time ranges when StudyFlow may plan sessions.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (var weekday = 1; weekday <= 7; weekday++)
                _buildDayCard(
                  context,
                  weekday,
                  windows
                      .where((window) => window.weekday == weekday)
                      .toList(growable: false),
                  windows,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDayCard(
    BuildContext context,
    int weekday,
    List<AvailabilityWindow> dayWindows,
    List<AvailabilityWindow> allWindows,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text(
              _dayName(weekday),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: IconButton(
              key: ValueKey('add-window-$weekday'),
              tooltip: 'Add window',
              icon: const Icon(Icons.add),
              onPressed: () => _addWindow(context, weekday, allWindows),
            ),
          ),
          if (dayWindows.isEmpty)
            const ListTile(dense: true, title: Text('No windows'))
          else
            for (final window in dayWindows)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule),
                title: Text(
                  '${_formatMinute(window.startMinute)} - '
                  '${_formatMinute(window.endMinute)}',
                ),
                trailing: IconButton(
                  key: ValueKey('delete-window-${window.id}'),
                  tooltip: 'Delete window',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteWindow(window),
                ),
              ),
        ],
      ),
    );
  }
}

String _dayName(int weekday) => _dayNames[weekday - 1];

String _formatMinute(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, '0');
  final minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
