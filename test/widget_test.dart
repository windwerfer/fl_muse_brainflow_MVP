// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fl_muse_brainflow_mvp/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We need to wrap the app in a ProviderScope for Riverpod.
    await tester.pumpWidget(const ProviderScope(child: MuseStreamApp()));

    // Verify that the app title is present.
    expect(find.text('MuseStream'), findsOneWidget);

    // Verify that the connection button is present (initial state).
    expect(find.text('Connect Muse S'), findsOneWidget);
  });
}
