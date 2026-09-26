import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/design.dart';

void main() {
  testWidgets('long RTL popup keeps decision buttons on screen at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 560), textScaler: TextScaler.linear(1.3)),
      child: Directionality(textDirection: TextDirection.rtl,
        child: Scaffold(body: DDialog(title: 'تأكيد تغيير النموذج',
          body: List.filled(30, 'هذه رسالة تحذير طويلة عن سعة السياق وتكلفة تغيير النموذج.').join('\n'),
          actions: [DBtn(label: 'إلغاء', onPressed: () {}), DBtn(label: 'تغيير النموذج', onPressed: () {})],
        )),
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('تغيير النموذج')).bottom, lessThan(560));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
