import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/main.dart';

void main() {
  testWidgets('public login does not ship a private server or username', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginPage(onDone: (_) {})));
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.length, 3);
    expect(fields.map((field) => field.controller!.text), everyElement(isEmpty));
  });
}
