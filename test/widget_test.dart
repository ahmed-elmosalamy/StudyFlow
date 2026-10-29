import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/app.dart';

void main() {
  testWidgets('app shell navigates across tabs and settings', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StudyFlowApp()));
    await tester.pump();

    expect(
      find.text('Today screen — arrives in a later milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Goals');
    expect(
      find.text('Goals screen — arrives in a later milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Schedule');
    expect(
      find.text('Schedule screen — arrives in a later milestone.'),
      findsOneWidget,
    );

    await _tapTab(tester, 'Progress');
    expect(
      find.text('Progress screen — arrives in a later milestone.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Settings screen — arrives in a later milestone.'),
      findsOneWidget,
    );
  });
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
}
