import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class StudyFlowApp extends ConsumerStatefulWidget {
  const StudyFlowApp({super.key});

  @override
  ConsumerState<StudyFlowApp> createState() => _StudyFlowAppState();
}

class _StudyFlowAppState extends ConsumerState<StudyFlowApp> {
  late final _router = buildRouter();
  late final AppLifecycleListener _lifecycleListener;
  var _firstFrameRendered = false;
  var _reconcileInFlight = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _reconcile);
    WidgetsBinding.instance.addPostFrameCallback(_onFirstFrame);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _onFirstFrame(Duration _) {
    _firstFrameRendered = true;
    _bootLog('first frame rendered');
    _reconcile();
  }

  void _reconcile() {
    if (!mounted || !_firstFrameRendered || _reconcileInFlight) {
      return;
    }
    _reconcileInFlight = true;
    _bootLog('reconcile started');
    final stopwatch = Stopwatch()..start();
    unawaited(
      ref
          .read(reconciliationServiceProvider)
          .reconcile()
          .then((_) {
            _bootLog(
              'reconcile finished in ${stopwatch.elapsedMilliseconds}ms',
            );
          })
          .catchError((Object error) {
            debugPrint('Reconciliation failed: $error');
          })
          .whenComplete(() {
            _reconcileInFlight = false;
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'StudyFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

void _bootLog(String message) {
  if (kDebugMode) {
    debugPrint('[boot] $message');
  }
}
