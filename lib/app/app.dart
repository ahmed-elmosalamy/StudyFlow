import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _reconcile);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _reconcile() {
    if (!mounted) {
      return;
    }
    unawaited(
      ref.read(reconciliationServiceProvider).reconcile().catchError((
        Object error,
      ) {
        debugPrint('Reconciliation failed: $error');
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
