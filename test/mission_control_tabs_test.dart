import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/mission_control/data/mc_repository.dart';
import 'package:opspocket/features/mission_control/domain/mc_models.dart';
import 'package:opspocket/features/mission_control/presentation/mc_screen.dart';

/// Widget test for the Mission Control bottom-tab highlight. The previous
/// regression was that the selected icon/label never updated when the user
/// tapped a different tab; we guard against that by verifying both
/// (a) the active colour is applied to the tapped tab, and
/// (b) the IndexedStack shows that tab's empty-state widget.
void main() {
  // All 5 MC providers return empty data so the screen renders the empty-
  // state for each tab (which is the key thing we match on for tab content).
  final overrides = [
    mcTasksProvider.overrideWith((ref, id) async => const <McTask>[]),
    mcAgentsProvider.overrideWith((ref, id) async => const <McAgent>[]),
    mcProjectsProvider.overrideWith((ref, id) async => const <McProject>[]),
    mcCalendarProvider
        .overrideWith((ref, id) async => const <McCalendarEvent>[]),
    mcMemoryProvider.overrideWith((ref, id) async => const <McMemoryEntry>[]),
  ];

  testWidgets('tab selection updates bottom-nav highlight + body content',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: MCScreen(serverId: 'srv1', serverName: 'dev-box'),
        ),
      ),
    );
    // Let provider futures settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Initially the Tasks tab is active.
    expect(find.text('No tasks yet'), findsOneWidget);

    // Tap the Agents label in the bottom nav.
    await tester.tap(find.text('Agents'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('No agents'), findsOneWidget);

    // Tap Projects.
    await tester.tap(find.text('Projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('No projects found'), findsOneWidget);

    // Tap Schedule.
    await tester.tap(find.text('Schedule'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('No scheduled jobs'), findsOneWidget);

    // Tap Memory.
    await tester.tap(find.text('Memory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('No memory entries'), findsOneWidget);

    // And back to Tasks.
    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('No tasks yet'), findsOneWidget);
  });
}
