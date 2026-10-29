import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/validation.dart';
import '../providers/timer_provider.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key, required this.sessionId});

  final String sessionId;

  Future<void> _leave(BuildContext context, TimerState? timer) async {
    if (timer != null && timer.isRunning) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Leave focus?'),
          content: const Text('The timer keeps running while you are away.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (leave != true) {
        return;
      }
    }
    if (context.mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerAsync = ref.watch(timerControllerProvider(sessionId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus'),
        actions: [
          TextButton(
            onPressed: () => _leave(context, timerAsync.value),
            child: const Text('Leave'),
          ),
        ],
      ),
      body: timerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load the session.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (timer) => _FocusBody(sessionId: sessionId, timer: timer),
      ),
    );
  }
}

class _FocusBody extends ConsumerStatefulWidget {
  const _FocusBody({required this.sessionId, required this.timer});

  final String sessionId;
  final TimerState timer;

  @override
  ConsumerState<_FocusBody> createState() => _FocusBodyState();
}

class _FocusBodyState extends ConsumerState<_FocusBody> {
  var _busy = false;

  TimerController get _controller =>
      ref.read(timerControllerProvider(widget.sessionId).notifier);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on ValidationException catch (error) {
      _showMessage(error.message);
    } on ConflictException catch (error) {
      _showMessage(error.message);
    } on NotFoundException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finish() async {
    final elapsed = widget.timer.elapsedSeconds(ref.read(clockProvider).now);
    final suggested = math.max(1, (elapsed / 60).round());
    final minutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FinishSessionSheet(initialMinutes: suggested),
    );
    if (minutes == null) {
      return;
    }
    await _run(() async {
      await _controller.finish(minutes);
      if (!mounted) {
        return;
      }
      _showMessage('Session completed.');
      context.pop();
    });
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard session?'),
        content: const Text(
          'The session will be marked as cancelled and its time will not be '
          'counted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep studying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _run(() async {
      await _controller.discard();
      if (!mounted) {
        return;
      }
      _showMessage('Session discarded.');
      context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timer = widget.timer;
    final elapsed = timer.elapsedSeconds(ref.watch(clockProvider).now);
    final remaining = timer.plannedMinutes * 60 - elapsed;
    final overtime = remaining < 0;
    final shown = overtime ? -remaining : remaining;
    final timerText =
        '${(shown ~/ 60).toString().padLeft(2, '0')}:'
        '${(shown % 60).toString().padLeft(2, '0')}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              timer.taskTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${timer.plannedMinutes} min planned',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              overtime ? '-$timerText' : timerText,
              key: const ValueKey('focus-timer'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 72,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: overtime ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overtime ? 'Overtime' : 'Elapsed ${elapsed ~/ 60} min',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: overtime ? theme.colorScheme.error : null,
              ),
            ),
            const Spacer(),
            _primaryControl(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy || !timer.hasStarted ? null : _finish,
              icon: const Icon(Icons.check),
              label: const Text('Finish'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy ? null : _discard,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryControl() {
    if (!widget.timer.hasStarted) {
      return FilledButton.icon(
        key: const ValueKey('focus-start-button'),
        onPressed: _busy ? null : () => _run(_controller.start),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      );
    }
    if (widget.timer.isRunning) {
      return FilledButton.icon(
        key: const ValueKey('focus-pause-button'),
        onPressed: _busy ? null : () => _run(_controller.pause),
        icon: const Icon(Icons.pause),
        label: const Text('Pause'),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('focus-resume-button'),
      onPressed: _busy ? null : () => _run(_controller.resume),
      icon: const Icon(Icons.play_arrow),
      label: const Text('Resume'),
    );
  }
}

class _FinishSessionSheet extends StatefulWidget {
  const _FinishSessionSheet({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_FinishSessionSheet> createState() => _FinishSessionSheetState();
}

class _FinishSessionSheetState extends State<_FinishSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minutesController;

  @override
  void initState() {
    super.initState();
    _minutesController = TextEditingController(
      text: '${widget.initialMinutes}',
    );
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(int.parse(_minutesController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Finish session',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _minutesController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual minutes',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final minutes = int.tryParse(value?.trim() ?? '');
                if (minutes == null || minutes < 1) {
                  return 'Enter at least 1 minute.';
                }
                if (minutes > 1440) {
                  return 'Enter 1440 minutes or less.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('Finish')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
