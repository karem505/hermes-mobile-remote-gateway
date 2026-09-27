import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/design.dart';
import 'package:hermes_mobile/store.dart';

import 'attachment_delivery_test.dart' show RecordingGateway;

Map<String, dynamic> _proc(String id, String command, String status, {int? exit, String? tail}) => {
  'session_id': id,
  'command': command,
  'status': status,
  'exit_code': ?exit,
  'output_tail': ?tail,
};

/// Settle-free pump: the strip's live dot animates forever, so `pumpAndSettle`
/// would hang. A layout frame plus a generous duration covers both collapsibles.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingGateway gw;
  late HermesStore store;

  setUp(() {
    gw = RecordingGateway();
    store = HermesStore(gw)..sid = 'session-a';
  });
  tearDown(() {
    store.dispose();
    gw.close();
  });

  test('background processes hydrate from process.list with real state', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [
          _proc('p-run', 'npm run watch\nsecond line', 'running'),
          _proc('p-fail', 'pytest -q', 'exited', exit: 1, tail: 'AssertionError'),
        ],
      },
      _ => gw.response(method, params),
    };

    await store.refreshBackground();

    expect(store.background.length, 2);
    final run = store.background.firstWhere((b) => b.id == 'p-run');
    expect(run.state, BackgroundState.running);
    expect(run.title, 'npm run watch');
    expect(run.kind, 'process');
    final failed = store.background.firstWhere((b) => b.id == 'p-fail');
    expect(failed.state, BackgroundState.failed);
    expect(failed.exitCode, 1);
    expect(failed.detail, 'AssertionError');
    expect(store.runningBackground, 1);
  });

  test('a finished process clears itself while a failure lingers', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [
          _proc('p-ok', 'make build', 'exited', exit: 0),
          _proc('p-bad', 'deploy.sh', 'exited', exit: 2),
        ],
      },
      _ => gw.response(method, params),
    };
    store.backgroundLingerSuccess = const Duration(milliseconds: 80);
    store.backgroundLingerFailure = const Duration(milliseconds: 200);
    await store.refreshBackground();
    expect(store.background.length, 2);

    await Future<void>.delayed(store.backgroundLingerSuccess + const Duration(milliseconds: 60));
    expect(store.background.map((b) => b.id), isNot(contains('p-ok')));
    expect(store.background.map((b) => b.id), contains('p-bad'));

    await Future<void>.delayed(store.backgroundLingerFailure + const Duration(milliseconds: 60));
    expect(store.background, isEmpty);
  });

  test('terminal output streams into the matching row and unknown ids still appear', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [_proc('p-run', 'tail -f app.log', 'running', tail: 'boot\n')],
      },
      _ => gw.response(method, params),
    };
    await store.refreshBackground();

    gw.events.add({
      'type': 'agent.terminal.output',
      'session_id': 'session-a',
      'payload': {'process_id': 'p-run', 'chunk': 'line one\n'},
    });
    gw.events.add({
      'type': 'agent.terminal.output',
      'session_id': 'session-a',
      'payload': {'process_id': 'p-fresh', 'chunk': 'spawned\n'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(store.background.firstWhere((b) => b.id == 'p-run').detail, contains('line one'));
    final fresh = store.background.firstWhere((b) => b.id == 'p-fresh');
    expect(fresh.state, BackgroundState.running);
    expect(fresh.state, BackgroundState.running);

    gw.events.add({
      'type': 'terminal.close',
      'session_id': 'session-a',
      'payload': {'process_id': 'p-run'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(store.background.firstWhere((b) => b.id == 'p-run').state, isNot(BackgroundState.running));
  });

  test('output detail stays bounded for a noisy background process', () async {
    for (var i = 0; i < 400; i++) {
      gw.events.add({
        'type': 'agent.terminal.output',
        'session_id': 'session-a',
        'payload': {'process_id': 'p-noisy', 'chunk': 'chunk $i padded padding padding\n'},
      });
    }
    await Future<void>.delayed(Duration.zero);
    final detail = store.background.firstWhere((b) => b.id == 'p-noisy').detail;
    expect(detail.length, lessThanOrEqualTo(backgroundDetailLimit));
    expect(detail, contains('chunk 399'));
  });

  test('subagent lifecycle events drive running, tool and terminal rows', () async {
    gw.events.add({
      'type': 'subagent.start',
      'session_id': 'session-a',
      'payload': {
        'goal': 'Audit the payment service',
        'task_count': 2,
        'task_index': 0,
        'subagent_id': 'sub-1',
        'model': 'gpt-6-luna',
        'status': 'running',
      },
    });
    await Future<void>.delayed(Duration.zero);
    var row = store.background.firstWhere((b) => b.id == 'sub-1');
    expect(row.kind, 'subagent');
    expect(row.title, 'Audit the payment service');
    expect(row.state, BackgroundState.running);
    expect(row.model, 'gpt-6-luna');

    gw.events.add({
      'type': 'subagent.tool',
      'session_id': 'session-a',
      'payload': {
        'goal': 'Audit the payment service',
        'task_count': 2,
        'task_index': 0,
        'subagent_id': 'sub-1',
        'tool_name': 'terminal',
        'tool_count': 7,
      },
    });
    await Future<void>.delayed(Duration.zero);
    row = store.background.firstWhere((b) => b.id == 'sub-1');
    expect(row.subtitle, 'terminal');
    expect(row.toolCount, 7);

    gw.events.add({
      'type': 'subagent.complete',
      'session_id': 'session-a',
      'payload': {
        'goal': 'Audit the payment service',
        'task_count': 2,
        'task_index': 0,
        'subagent_id': 'sub-1',
        'status': 'failed',
        'summary': 'crashed',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(store.background.firstWhere((b) => b.id == 'sub-1').state, BackgroundState.failed);
    expect(store.runningBackground, 0);
  });

  test('subagent.list hydrates children that started before the app connected', () async {
    gw.handler = (method, params) async => switch (method) {
      'subagent.list' => {
        'subagents': [
          {
            'subagent_id': 'sub-9',
            'goal': 'Write the migration script',
            'model': 'gpt-6-luna',
            'status': 'running',
            'tool_count': 3,
            'last_tool': 'write_file',
          },
          {'subagent_id': 'sub-8', 'goal': 'Old task', 'status': 'completed'},
        ],
      },
      'process.list' => {'processes': const []},
      _ => gw.response(method, params),
    };

    await store.refreshBackground();

    final live = store.background.firstWhere((b) => b.id == 'sub-9');
    expect(live.subtitle, 'write_file');
    expect(live.toolCount, 3);
    expect(store.background.firstWhere((b) => b.id == 'sub-8').state, BackgroundState.done);
  });

  test('stopping a running process kills it on the server, then drops the row', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [_proc('p-run', 'npm run dev', 'running')],
      },
      'process.kill' => {'status': 'killed'},
      _ => gw.response(method, params),
    };
    await store.refreshBackground();
    await store.stopBackground('p-run');

    final kill = gw.calls.where((c) => c.method == 'process.kill').toList();
    expect(kill, hasLength(1));
    expect(kill.single.params['process_id'], 'p-run');
    expect(kill.single.params['session_id'], 'session-a');
    expect(store.background, isEmpty);
  });

  test('a failed kill keeps the row so the user can retry', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [_proc('p-run', 'npm run dev', 'running')],
      },
      'process.kill' => throw Exception('offline'),
      _ => gw.response(method, params),
    };
    await store.refreshBackground();
    await store.stopBackground('p-run');
    expect(store.background.map((b) => b.id), contains('p-run'));
  });

  test('stopping a live subagent interrupts it through the subagent RPC', () async {
    gw.handler = (method, params) async => switch (method) {
      'subagent.list' => {
        'subagents': [
          {'subagent_id': 'sub-3', 'goal': 'Long audit', 'status': 'running'},
        ],
      },
      'process.list' => {'processes': const []},
      'subagent.interrupt' => {'status': 'interrupted'},
      _ => gw.response(method, params),
    };
    await store.refreshBackground();
    await store.stopBackground('sub-3');

    final interrupt = gw.calls.where((c) => c.method == 'subagent.interrupt').toList();
    expect(interrupt, hasLength(1));
    expect(interrupt.single.params['session_id'], 'session-a');
    expect(interrupt.single.params['subagent_id'], 'sub-3');
    expect(store.background, isEmpty);
  });

  test('a finished background agent surfaces its answer before clearing', () async {
    gw.events.add({
      'type': 'background.complete',
      'session_id': 'session-a',
      'payload': {'task_id': 'bg-1', 'text': 'الشهادة انتهت بنجاح'},
    });
    await Future<void>.delayed(Duration.zero);

    final row = store.background.where((b) => b.id == 'bg-1').single;
    expect(row.state, BackgroundState.done);
    expect(row.detail, 'الشهادة انتهت بنجاح');
    expect(store.runningBackground, 0);
  });

  test('switching sessions drops the previous session background rows', () async {
    gw.handler = (method, params) async => switch (method) {
      'process.list' => {
        'processes': [_proc('p-run', 'npm run dev', 'running')],
      },
      'pong' => {'ok': true},
      _ => gw.response(method, params),
    };
    await store.refreshBackground();
    expect(store.background, isNotEmpty);

    store.sid = 'session-b';
    await Future<void>.delayed(Duration.zero);
    expect(store.background, isEmpty);
  });

  testWidgets('strip collapses by default, expands rows and keeps actions reachable', (tester) async {
    final stopped = <String>[];
    final dismissed = <String>[];
    final items = <BackgroundActivity>[
      BackgroundActivity(
        id: 'p-run',
        kind: 'process',
        title: 'npm run watch --port 3000 --verbose',
        state: BackgroundState.running,
      ),
      BackgroundActivity(
        id: 'sub-1',
        kind: 'subagent',
        title: 'Audit the payment service',
        subtitle: 'terminal',
        model: 'gpt-6-luna',
        toolCount: 7,
      ),
      BackgroundActivity(
        id: 'p-bad',
        kind: 'process',
        title: 'pytest -q',
        state: BackgroundState.failed,
        exitCode: 1,
        detail: 'AssertionError: expected 200 got 500',
      ),
    ];
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackgroundStrip(
            items: items,
            onStop: (id) async => stopped.add(id),
            onDismiss: dismissed.add,
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.textContaining('النشاط في الخلفية'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);
    expect(find.text('Audit the payment service'), findsNothing);

    await tester.tap(find.textContaining('النشاط في الخلفية'));
    await settle(tester);

    expect(find.text('Audit the payment service'), findsOneWidget);
    expect(find.textContaining('pytest -q'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((w) => w is DIconBtn && w.tooltip == 'إيقاف').first);
    await settle(tester);
    expect(stopped, ['p-run']);

    await tester.tap(find.byWidgetPredicate((w) => w is DIconBtn && w.tooltip == 'تجاهل').first);
    await settle(tester);
    expect(dismissed, ['p-bad']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded row reveals the captured output tail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackgroundStrip(
            items: [
              BackgroundActivity(
                id: 'p-bad',
                kind: 'process',
                title: 'deploy.sh',
                state: BackgroundState.failed,
                exitCode: 2,
                detail: 'connection refused on port 9131',
              ),
            ],
            onStop: (_) async {},
            onDismiss: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('النشاط في الخلفية'));
    await settle(tester);
    expect(find.textContaining('connection refused'), findsNothing);

    await tester.tap(find.textContaining('deploy.sh'));
    await settle(tester);
    expect(find.textContaining('connection refused'), findsOneWidget);
    expect(find.textContaining('رمز 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
