import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/design.dart';
import 'package:hermes_mobile/main.dart';
import 'package:hermes_mobile/store.dart';

import 'attachment_delivery_test.dart' show RecordingGateway;

void main() {
  for (final action in ['send', 'steer', 'queue']) {
    testWidgets(
      '$action accepts attachment-only draft and displays its cards',
      (tester) async {
        final gw = RecordingGateway();
        final store = HermesStore(gw)
          ..sid = 'session-a'
          ..running = action != 'send';
        addTearDown(store.dispose);
        await store.attach('photo.png', [1]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: store,
                builder: (context, _) => Column(
                  children: [
                    for (final item in store.items) MessageTile(item: item),
                    Composer(store: store, api: gw.api),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = action == 'send'
            ? find.byWidgetPredicate((w) => w is DIconBtn && w.primary)
            : find.text(action == 'steer' ? 'توجيه' : 'إلى الطابور');
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(store.attachments, isEmpty);
        expect(find.text('photo.png'), findsOneWidget);
        expect(find.byType(MediaCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed queued attachment stays visible and can be retried', (
    tester,
  ) async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)
      ..sid = 'session-a'
      ..running = true;
    addTearDown(store.dispose);
    await store.attach('queued.pdf', [1]);
    await store.enqueue('');
    gw.handler = (method, params) async => method == 'prompt.submit'
        ? throw Exception('offline')
        : gw.response(method, params);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Composer(store: store, api: gw.api),
          ),
        ),
      ),
    );
    gw.events.add({
      'type': 'message.complete',
      'session_id': 'session-a',
      'payload': {},
    });
    await tester.pumpAndSettle();
    expect(store.queued.length, 1);
    expect(find.text('queued.pdf'), findsOneWidget);
    expect(find.byTooltip('إعادة إرسال الطابور').hitTestable(), findsOneWidget);
    gw.handler = null;
    await tester.tap(find.byTooltip('إعادة إرسال الطابور'));
    await tester.pumpAndSettle();
    expect(store.queued, isEmpty);
    expect(store.items.where((i) => i.kind == 'user').single.files, [
      '/workspace/attachments/queued.pdf',
    ]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed send keeps text and attachment in composer', (
    tester,
  ) async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    addTearDown(store.dispose);
    await store.attach('photo.png', [1]);
    gw.handler = (method, params) async => throw Exception('offline');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Composer(store: store, api: gw.api),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'احتفظ بالنص');
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is DIconBtn && w.primary));
    await tester.pumpAndSettle();
    expect(find.text('احتفظ بالنص'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(store.items.where((i) => i.kind == 'user'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 360.0, 400.0]) {
    testWidgets('RTL Extra high controls stay inside composer at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gw = RecordingGateway();
      final api = gw.api;
      final store = HermesStore(gw)
        ..sid = 'session-a'
        ..info['reasoning_effort'] = 'xhigh'
        ..running = true;
      await store.attach('queued.pdf', [1]);
      await store.enqueue('رسالة في الطابور');
      await store.attach('draft.png', [2]);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(store: store, api: api),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'توجيه مع مرفقات');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('توجيه').hitTestable(), findsOneWidget);
      expect(find.text('إلى الطابور').hitTestable(), findsOneWidget);
      // The model chip keeps the English Thinking level visible even when narrow.
      expect(find.text('Extra high').hitTestable(), findsOneWidget);
      expect(find.text('queued.pdf'), findsOneWidget);
      expect(find.text('draft.png'), findsOneWidget);
      final card = find
          .descendant(of: find.byType(Composer), matching: find.byType(DCard))
          .last;
      final bounds = tester.getRect(card);
      for (final control
          in find
              .descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (w) => w is DIconBtn || w is DChip || w is DBtn,
                ),
              )
              .evaluate()) {
        final rect = tester.getRect(find.byWidget(control.widget));
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.right, lessThanOrEqualTo(bounds.right));
        expect(rect.top, greaterThanOrEqualTo(bounds.top));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
