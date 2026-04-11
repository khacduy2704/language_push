// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:push_language/main.dart';

void main() {
  testWidgets('Bottom navigation switches tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('World'), findsWidgets);
    expect(find.text('Setting Screen'), findsNothing);

    await tester.tap(find.byIcon(Icons.home));
    await tester.pump();
    expect(find.text('Home Screen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    expect(find.text('Setting Screen'), findsOneWidget);
  });
}


