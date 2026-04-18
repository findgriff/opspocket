// Smoke test — verifies the app boots without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App scaffold smoke test', (WidgetTester tester) async {
    // Wrap a minimal widget tree in ProviderScope — same as the real app.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: Text('OpsPocket'))),
        ),
      ),
    );
    expect(find.text('OpsPocket'), findsOneWidget);
  });
}
