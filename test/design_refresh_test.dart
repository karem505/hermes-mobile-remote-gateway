import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/design.dart';
import 'package:hermes_mobile/main.dart';
import 'package:hermes_mobile/store.dart';

import 'attachment_delivery_test.dart' show RecordingGateway;

Widget _host(HermesStore store, RecordingGateway gw) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Column(children: [
              Expanded(child: ChatView(store: store)),
              Composer(store: store, api: gw.api),
            ]),
          ),
        ),
      ),
    );

void main() {
  group('model names', () {
    test('short name drops vendor prefix and trailing date stamp', () {
      expect(dModelShort('deepseek-v4-1-flash-260910'), 'deepseek-v4-1-flash');
      expect(dModelShort('anthropic/claude-opus-5-5'), 'claude-opus-5-5');
      expect(dModelShort('gpt-6-20260801'), 'gpt-6');
      // Nothing to drop: the id is shown as is.
      expect(dModelShort('glm-5.2'), 'glm-5.2');
    });

    test('durations stay compact with Latin digits', () {
      expect(dSeconds(8), '8s');
      expect(dSeconds(64), '1m 04s');
    });
  });

  testWidgets('empty session offers suggestions that fill the composer without sending', (tester) async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(store, gw));
    await tester.pumpAndSettle();

    final chip = find.byType(DSuggestion).first;
    expect(chip.hitTestable(), findsOneWidget);
    final label = (tester.widget(chip) as DSuggestion).label;
    await tester.tap(chip);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, label);
    expect(gw.calls.where((c) => c.method == 'prompt.submit'), isEmpty);
    expect(store.draftRequest, isNull, reason: 'the draft is consumed once');
  });

  testWidgets('composer chip shows model and English Thinking level and opens the sheet', (tester) async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)
      ..sid = 'session-a'
      ..currentModel = 'deepseek-v4-1-flash-260910'
      ..info['reasoning_effort'] = 'max';
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(store, gw));
    await tester.pumpAndSettle();

    expect(find.text('deepseek-v4-1-flash').hitTestable(), findsOneWidget);
    expect(find.text('Max').hitTestable(), findsOneWidget);
    await tester.tap(find.byType(DModelChip));
    // The model list keeps a spinner while the fake gateway returns nothing.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ModelSheet), findsOneWidget);
    // The effort row is at the top of the sheet, labelled in English.
    expect(find.text('Thinking'), findsOneWidget);
  });

  testWidgets('on a 363dp phone the chip shows the whole model name and the level', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gw = RecordingGateway();
    final store = HermesStore(gw)
      ..sid = 'session-a'
      ..currentModel = 'deepseek-v4-1-flash-260910'
      ..info['reasoning_effort'] = 'xhigh';
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(store, gw));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final name = find.text('deepseek-v4-1-flash');
    expect(name.hitTestable(), findsOneWidget);
    expect(find.text('Extra high').hitTestable(), findsOneWidget);
    // Test fonts draw every glyph as a full em square, so truncation is checked
    // on the device; here the chip must get room for a two-line label.
    final chip = tester.getSize(find.byType(DModelChip));
    // ignore: avoid_print
    print('chip width on 363dp phone: ${chip.width}');
    expect(chip.width, greaterThan(120));
  });

  testWidgets('thinking block reports its duration once closed and expands on tap', (tester) async {
    final item = ChatItem.thinking('checking the server logs first')
      ..done = true
      ..seconds = 12;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MessageTile(item: item))));
    await tester.pumpAndSettle();

    expect(find.text('فكّر لمدة 12 ثانية'), findsOneWidget);
    await tester.tap(find.text('فكّر لمدة 12 ثانية'));
    await tester.pumpAndSettle();
    expect(find.text('checking the server logs first').hitTestable(), findsOneWidget);
  });

  testWidgets('finished tool step shows its duration and expands to its detail', (tester) async {
    final item = ChatItem.tool('terminal', toolId: 'id-1')
      ..detail = 'ls -la /srv'
      ..done = true
      ..duration = 3.2;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MessageTile(item: item))));
    await tester.pumpAndSettle();

    expect(find.text('terminal'), findsOneWidget);
    expect(find.text('3s'), findsOneWidget);
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('finished reply offers copy; a streaming one does not', (tester) async {
    final done = ChatItem.assistant('الإجابة النهائية')..done = true;
    final live = ChatItem.assistant('جارٍ الكتابة')..done = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Column(children: [MessageTile(item: done), MessageTile(item: live)])),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DActionRow), findsOneWidget);
  });

  test('late reasoning.available does not duplicate thinking or the reply', () async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    addTearDown(store.dispose);
    void ev(String type, [Map<String, dynamic> p = const {}]) =>
        gw.events.add({'type': type, 'session_id': 'session-a', 'payload': p});

    store.items.add(ChatItem.user('run uptime'));
    ev('message.start');
    ev('reasoning.delta', {'text': 'plan'});
    ev('tool.start', {'name': 'terminal', 'tool_id': 't1'});
    ev('tool.complete', {'tool_id': 't1', 'duration_s': 0.2});
    ev('reasoning.delta', {'text': 'answer now'});
    ev('message.delta', {'text': 'Up 9 days'});
    // Observed live order: the full reasoning arrives after the reply began.
    ev('reasoning.available', {'text': 'plan answer now'});
    ev('message.complete', {'text': 'Up 9 days, load 2.04'});
    await Future<void>.delayed(Duration.zero);

    final kinds = store.items.map((i) => i.kind).toList();
    expect(kinds.where((k) => k == 'assistant').length, 1, reason: '$kinds');
    expect(kinds.where((k) => k == 'thinking').length, 2, reason: '$kinds');
    expect(kinds.last, 'assistant');
    expect(store.items.last.text, 'Up 9 days, load 2.04');
  });

  test('reasoning.available alone still records the thinking before the reply', () async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    addTearDown(store.dispose);
    void ev(String type, [Map<String, dynamic> p = const {}]) =>
        gw.events.add({'type': type, 'session_id': 'session-a', 'payload': p});

    store.items.add(ChatItem.user('hi'));
    ev('message.start');
    ev('message.delta', {'text': 'Hello'});
    ev('reasoning.available', {'text': 'greet back'});
    ev('message.complete', {'text': 'Hello there'});
    await Future<void>.delayed(Duration.zero);

    expect(store.items.map((i) => i.kind).toList(), ['user', 'thinking', 'assistant']);
    expect(store.items.last.text, 'Hello there');
  });

  test('real event order: spinner thinking.delta never splits the reply', () async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    addTearDown(store.dispose);
    void ev(String type, [Map<String, dynamic> p = const {}]) =>
        gw.events.add({'type': type, 'session_id': 'session-a', 'payload': p});

    store.items.add(ChatItem.user('print pwd'));
    // Order captured from a live turn on the phone (types only).
    ev('message.start');
    ev('thinking.delta', {'text': '(o_o) pondering...'});
    ev('status.update', {'text': 'working'});
    ev('reasoning.delta', {'text': 'run pwd'});
    ev('tool.generating', {'name': 'terminal'});
    ev('thinking.delta', {'text': '(o_o) computing...'});
    ev('tool.start', {'name': 'terminal', 'tool_id': 't1'});
    ev('tool.complete', {'tool_id': 't1', 'duration_s': 0.1});
    ev('thinking.delta', {'text': '(o_o) musing...'});
    ev('reasoning.delta', {'text': 'answer'});
    ev('message.delta', {'text': 'The current '});
    ev('message.delta', {'text': 'directory is /srv'});
    ev('thinking.delta', {'text': '(o_o) synthesizing...'});
    ev('reasoning.available', {'text': 'run pwd answer'});
    ev('message.complete', {'text': 'The current directory is /srv'});
    await Future<void>.delayed(Duration.zero);

    final kinds = store.items.map((i) => i.kind).toList();
    expect(kinds, ['user', 'thinking', 'tool', 'thinking', 'assistant']);
    expect(store.items.last.text, 'The current directory is /srv');
    expect(store.items.where((i) => i.kind == 'thinking').every((i) => !i.text.contains('(o_o)')), isTrue);
  });

  testWidgets('code block: language header, copy action, LTR scrolling code', (tester) async {
    var copied = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: 320,
            child: DCodeBlock(language: 'bash', code: 'echo "a very long line that must scroll sideways instead of wrapping"\n', onCopy: () => copied++),
          ),
        ),
      ),
    ));
    expect(find.text('bash'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, 1);
    expect(tester.takeException(), isNull);
    final dir = tester.widget<Directionality>(find.ancestor(of: find.text('bash'), matching: find.byType(Directionality)).first);
    expect(dir.textDirection, TextDirection.ltr);
  });
}
