import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:push_language/widgets/setting_row.dart';

void main() {
  testWidgets('SettingRow renders content and handles tap',
      (WidgetTester tester) async {
    int tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingRow(
            icon: Icons.language,
            label: 'Language',
            value: 'English',
            onTap: () => tapCount++,
          ),
        ),
      ),
    );

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(tapCount, 1);
  });
}


