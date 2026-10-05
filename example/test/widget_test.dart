import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_moja_mreza_example/main.dart';

void main() {
  testWidgets('Početni ekran nudi uvoz', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    expect(find.text('Uvezi s Moje mreže'), findsOneWidget);
  });
}
