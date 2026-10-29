import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation.dart';
import '../../../data/database/app_database.dart';
import '../providers/settings_providers.dart';

class PlanningLimitsScreen extends ConsumerStatefulWidget {
  const PlanningLimitsScreen({super.key});

  @override
  ConsumerState<PlanningLimitsScreen> createState() =>
      _PlanningLimitsScreenState();
}

class _PlanningLimitsScreenState extends ConsumerState<PlanningLimitsScreen> {
  final _dailyLimitController = TextEditingController();
  final _blockLengthController = TextEditingController();
  final _minSessionController = TextEditingController();
  final _breakController = TextEditingController();
  var _initialized = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _dailyLimitController.dispose();
    _blockLengthController.dispose();
    _minSessionController.dispose();
    _breakController.dispose();
    super.dispose();
  }

  void _initialize(AppSetting settings) {
    if (_initialized) {
      return;
    }
    _dailyLimitController.text = '${settings.dailyLimitMinutes}';
    _blockLengthController.text = '${settings.blockLengthMinutes}';
    _minSessionController.text = '${settings.minSessionMinutes}';
    _breakController.text = '${settings.breakMinutes}';
    _initialized = true;
  }

  Future<void> _save(AppSetting settings) async {
    FocusScope.of(context).unfocus();
    final dailyLimit = int.tryParse(_dailyLimitController.text.trim());
    final blockLength = int.tryParse(_blockLengthController.text.trim());
    final minSession = int.tryParse(_minSessionController.text.trim());
    final breakMinutes = int.tryParse(_breakController.text.trim());
    if (dailyLimit == null ||
        blockLength == null ||
        minSession == null ||
        breakMinutes == null) {
      setState(() => _error = 'Enter whole numbers for all limits.');
      return;
    }
    try {
      ValidationRules.validateDailyLimitMinutes(dailyLimit);
      ValidationRules.validateBlockLengthMinutes(blockLength);
      ValidationRules.validateMinSessionMinutes(
        minSessionMinutes: minSession,
        blockLengthMinutes: blockLength,
      );
      ValidationRules.validateBreakMinutes(breakMinutes);
    } on ValidationException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .update(
            settings.copyWith(
              dailyLimitMinutes: dailyLimit,
              blockLengthMinutes: blockLength,
              minSessionMinutes: minSession,
              breakMinutes: breakMinutes,
            ),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Planning limits saved.')));
    } on ValidationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Planning Limits')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load settings.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (settings) {
          _initialize(settings);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'These limits apply to every automatic plan.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _LimitField(
                fieldKey: const ValueKey('daily-limit-field'),
                controller: _dailyLimitController,
                label: 'Daily Limit (minutes)',
                helperText:
                    'Maximum study minutes planned per day (15 to 720).',
              ),
              _LimitField(
                fieldKey: const ValueKey('block-length-field'),
                controller: _blockLengthController,
                label: 'Block Length (minutes)',
                helperText: 'Longest single study block (15 to 120).',
              ),
              _LimitField(
                fieldKey: const ValueKey('min-session-field'),
                controller: _minSessionController,
                label: 'Minimum Session (minutes)',
                helperText:
                    'Shortest non-final session. At most half the block '
                    'length.',
              ),
              _LimitField(
                fieldKey: const ValueKey('break-length-field'),
                controller: _breakController,
                label: 'Break Length (minutes)',
                helperText:
                    'Rest between sessions (0 to 30). Not counted in the '
                    'daily limit.',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('planning-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('planning-save-button'),
                onPressed: _saving ? null : () => _save(settings),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LimitField extends StatelessWidget {
  const _LimitField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.helperText,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
