import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/api.dart';
import 'package:hermes_mobile/store.dart';

class FakeApi extends HermesApi {
  FakeApi() : super('http://localhost', '', '');
  final transcripts = <String, List<Map<String, dynamic>>>{};
  int fetches = 0;
  bool fail = false;

  @override
  Future<List<Map<String, dynamic>>> sessionMessages(String storedId, {int limit = 300}) async {
    fetches++;
    if (fail) throw 'no route';
    return transcripts[storedId] ?? [];
  }
}

class SwitchGateway extends Gateway {
  SwitchGateway(FakeApi super.api);
  final calls = <({String method, Map<String, dynamic> params})>[];
  final resumeGates = <String, Completer<void>>{};
  final running = <String, bool>{};
  final inflight = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> active = [];
  List<Map<String, dynamic>> fullMessages = [];

  @override
  Future<dynamic> call(String method, [Map<String, dynamic> params = const {}, Duration? timeout]) async {
    calls.add((method: method, params: Map.of(params)));
    if (method == 'session.resume') {
      final id = '${params['session_id']}';
      final gate = resumeGates[id];
      if (gate != null) await gate.future;
      return {
        'session_id': 'rt-$id',
        'running': running[id] ?? false,
        if (inflight[id] != null) 'inflight': inflight[id],
        'info': {'model': 'm1'},
        if (params['omit_messages'] != true) 'messages': fullMessages,
      };
    }
    if (method == 'session.active_list') return {'sessions': active};
    if (method == 'session.list') return {'sessions': []};
    if (method == 'commands.catalog') return {'categories': [], 'skills': {}};
    if (method == 'process.list' || method == 'subagent.list') return {'processes': [], 'subagents': []};
    return {'status': 'submitted'};
  }
}

Map<String, dynamic> _row(String role, Object? content, {String? kind, Object? toolCalls, String? toolCallId, String? toolName, Map? meta}) => {
      'role': role,
      'content': content,
      'display_kind': kind,
      'tool_calls': toolCalls,
      'tool_call_id': toolCallId,
      'tool_name': toolName,
      'display_metadata': meta,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeApi api;
  late SwitchGateway gw;
  late HermesStore store;

  setUp(() {
    api = FakeApi();
    gw = SwitchGateway(api);
    store = HermesStore(gw);
  });
  tearDown(() {
    store.dispose();
    gw.close();
  });

  test('opening a session asks the gateway for no transcript and reads it over REST', () async {
    api.transcripts['A'] = [_row('user', 'hi'), _row('assistant', 'hello')];
    await store.openSession(SessionRow('A', 'Session A', '', 0, 2));
    final resume = gw.calls.firstWhere((c) => c.method == 'session.resume');
    expect(resume.params['omit_messages'], isTrue);
    expect(store.sid, 'rt-A');
    expect(store.items.map((i) => '${i.kind}:${i.text}'), ['user:hi', 'assistant:hello']);
    expect(store.opening, isFalse);
  });

  test('a serve without the REST transcript falls back to the full resume', () async {
    api.fail = true;
    gw.fullMessages = [
      {'role': 'user', 'text': 'old'},
      {'role': 'assistant', 'text': 'reply'},
    ];
    await store.openSession(SessionRow('A', 'A', '', 0, 2));
    expect(store.items.map((i) => i.text), ['old', 'reply']);
  });

  test('switching back paints the cached chat at once, without the loading state', () async {
    api.transcripts['A'] = [_row('user', 'a1'), _row('assistant', 'a2')];
    api.transcripts['B'] = [_row('user', 'b1')];
    await store.openSession(SessionRow('A', 'A', '', 0, 2));
    await store.openSession(SessionRow('B', 'B', '', 0, 1));
    final gate = Completer<void>();
    gw.resumeGates['A'] = gate;
    final f = store.openSession(SessionRow('A', 'A', '', 0, 2));
    await Future<void>.delayed(Duration.zero);
    expect(store.opening, isFalse, reason: 'cached view must not show the spinner');
    expect(store.refreshing, isTrue);
    expect(store.items.map((i) => i.text), ['a1', 'a2']);
    expect(store.sid, 'rt-A');
    gate.complete();
    await f;
    expect(store.refreshing, isFalse);
    expect(store.items.map((i) => i.text), ['a1', 'a2']);
  });

  test('a fast second switch wins over a slow first one', () async {
    api.transcripts['A'] = [_row('user', 'from A')];
    api.transcripts['B'] = [_row('user', 'from B')];
    final gate = Completer<void>();
    gw.resumeGates['A'] = gate;
    final slow = store.openSession(SessionRow('A', 'A', '', 0, 1));
    await store.openSession(SessionRow('B', 'B', '', 0, 1));
    gate.complete();
    await slow;
    expect(store.storedId, 'B');
    expect(store.sid, 'rt-B');
    expect(store.items.map((i) => i.text), ['from B']);
  });

  test('a running session resumes with its in-flight turn and keeps streaming', () async {
    api.transcripts['A'] = [_row('user', 'earlier'), _row('assistant', 'done')];
    gw.running['A'] = true;
    gw.inflight['A'] = {'user': 'count to 5', 'assistant': '1\n2', 'streaming': true};
    await store.openSession(SessionRow('A', 'A', '', 0, 2));
    expect(store.running, isTrue);
    expect(store.items.map((i) => i.text), ['earlier', 'done', 'count to 5', '1\n2']);
    gw.events.add({'type': 'message.delta', 'session_id': 'rt-A', 'payload': {'text': '\n3'}});
    await Future<void>.delayed(Duration.zero);
    expect(store.items.last.text, '1\n2\n3');
    gw.events.add({'type': 'message.complete', 'session_id': 'rt-A', 'payload': {'text': '1\n2\n3'}});
    await Future<void>.delayed(Duration.zero);
    expect(store.running, isFalse);
  });

  test('events that arrive while the session loads are applied after it', () async {
    api.transcripts['A'] = [_row('user', 'go')];
    gw.running['A'] = true;
    final gate = Completer<void>();
    gw.resumeGates['A'] = gate;
    final f = store.openSession(SessionRow('A', 'A', '', 0, 1));
    await Future<void>.delayed(Duration.zero);
    // Arrives after the resume snapshot was taken (the snapshot clears held frames
    // only up to its own reply); the gate holds the reply, so this is pre-snapshot.
    gate.complete();
    await f;
    gw.events.add({'type': 'message.delta', 'session_id': 'rt-A', 'payload': {'text': 'late'}});
    await Future<void>.delayed(Duration.zero);
    expect(store.items.last.text, 'late');
  });

  test('a background session that finishes is not restored as running', () async {
    api.transcripts['A'] = [_row('user', 'go')];
    gw.running['A'] = true;
    await store.openSession(SessionRow('A', 'A', '', 0, 1));
    expect(store.running, isTrue);
    gw.running['A'] = false;
    await store.openSession(SessionRow('B', 'B', '', 0, 0));
    gw.events.add({'type': 'message.complete', 'session_id': 'rt-A', 'payload': {'text': 'ok'}});
    await Future<void>.delayed(Duration.zero);
    final gate = Completer<void>();
    gw.resumeGates['A'] = gate;
    final f = store.openSession(SessionRow('A', 'A', '', 0, 1));
    await Future<void>.delayed(Duration.zero);
    expect(store.running, isFalse, reason: 'cached view was marked done by the background event');
    gate.complete();
    await f;
  });

  group('running reconciliation with the active list', () {
    late DateTime now;
    setUp(() async {
      now = DateTime(2026, 1, 1, 12);
      store.clock = () => now;
      gw.state = LinkState.connected;
      api.transcripts['A'] = [_row('user', 'go')];
      gw.running['A'] = true;
      await store.openSession(SessionRow('A', 'A', '', 0, 1));
      gw.calls.clear();
    });

    test('a stale running chat is cleared after two quiet idle polls', () async {
      expect(store.running, isTrue);
      gw.active = [
        {'id': 'rt-A', 'session_key': 'A', 'status': 'idle'}
      ];
      now = now.add(const Duration(seconds: 30));
      await store.refreshActive();
      expect(store.running, isTrue, reason: 'one idle poll is not enough');
      now = now.add(const Duration(seconds: 4));
      await store.refreshActive();
      expect(store.running, isFalse);
    });

    test('idle polls never cut a reply that is still streaming', () async {
      gw.active = [
        {'id': 'rt-A', 'session_key': 'A', 'status': 'idle'}
      ];
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(seconds: 4));
        gw.events.add({'type': 'message.delta', 'session_id': 'rt-A', 'payload': {'text': 'x'}});
        await Future<void>.delayed(Duration.zero);
        await store.refreshActive();
      }
      expect(store.running, isTrue);
    });

    test('a busy poll right after the turn ended does not pin the chat as running', () async {
      gw.events.add({'type': 'message.complete', 'session_id': 'rt-A', 'payload': {'text': 'ok'}});
      await Future<void>.delayed(Duration.zero);
      expect(store.running, isFalse);
      gw.active = [
        {'id': 'rt-A', 'session_key': 'A', 'status': 'working'}
      ];
      now = now.add(const Duration(seconds: 1));
      await store.refreshActive();
      now = now.add(const Duration(seconds: 1));
      await store.refreshActive();
      expect(store.running, isFalse);
    });

    test('a turn started elsewhere shows as running after two busy polls', () async {
      gw.events.add({'type': 'message.complete', 'session_id': 'rt-A', 'payload': {'text': 'ok'}});
      await Future<void>.delayed(Duration.zero);
      gw.active = [
        {'id': 'rt-A', 'session_key': 'A', 'status': 'working'}
      ];
      now = now.add(const Duration(seconds: 20));
      await store.refreshActive();
      expect(store.running, isFalse);
      now = now.add(const Duration(seconds: 4));
      await store.refreshActive();
      expect(store.running, isTrue);
    });

    test('the "starting" status of an agent being built is not a running turn', () async {
      gw.events.add({'type': 'message.complete', 'session_id': 'rt-A', 'payload': {'text': 'ok'}});
      await Future<void>.delayed(Duration.zero);
      gw.active = [
        {'id': 'rt-A', 'session_key': 'A', 'status': 'starting'}
      ];
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(seconds: 10));
        await store.refreshActive();
      }
      expect(store.running, isFalse);
    });
  });

  group('REST transcript projection', () {
    test('tool rows take their name and argument preview from the assistant call', () {
      final items = chatItemsFromRest([
        _row('user', 'list files'),
        _row('assistant', '', toolCalls: [
          {
            'id': 'c1',
            'function': {'name': 'terminal', 'arguments': '{"command": "ls -la /tmp"}'}
          }
        ]),
        _row('tool', '{"output": "..."}', toolCallId: 'c1', toolName: 'terminal'),
        _row('assistant', 'Here they are'),
      ]);
      expect(items.map((i) => i.kind), ['user', 'tool', 'assistant']);
      expect(items[1].text, 'terminal');
      expect(items[1].detail, 'ls -la /tmp');
    });

    test('hidden scaffolding never renders as a user bubble', () {
      final items = chatItemsFromRest([
        _row('user', '[System: The active model changed]', kind: 'model_switch'),
        _row('user', '[System note: Your previous turn was interrupted', kind: 'auto_continue'),
        _row('user', '[CONTEXT COMPACTION] ...', kind: 'hidden'),
        _row('assistant', '', kind: 'hidden'),
        {..._row('user', '[CONTEXT COMPACTION] ...'), 'display_content': 'summary'},
        _row('user', 'real question'),
      ]);
      expect(items.map((i) => i.text), ['real question']);
    });

    test('skill invocations and steers show what the user typed', () {
      final items = chatItemsFromRest([
        _row('user',
            '[IMPORTANT: The user has invoked the "work" skill, indicating they want you to follow its instructions. The full skill content is loaded below.]\n\nbody\n\nThe user has provided the following instruction alongside the skill invocation: fix the leak'),
        _row('user', '[OUT-OF-BAND USER MESSAGE — a direct message]\nstop and check logs\n[/OUT-OF-BAND USER MESSAGE]', kind: 'steer'),
      ]);
      expect(items.map((i) => i.text), ['/work fix the leak', 'stop and check logs']);
    });

    test('background completions become notices; failed turns are notices', () {
      final items = chatItemsFromRest([
        _row('user', '[IMPORTANT: Background process ...', kind: 'process_complete', meta: {'display_text': 'Background Process Finished: npm test'}),
        _row('assistant', 'Your request was not processed.', kind: 'failed_turn'),
      ]);
      expect(items.map((i) => '${i.kind}:${i.text}'),
          ['notice:Background Process Finished: npm test', 'notice:Your request was not processed.']);
    });

    test('multipart tool content is read as text', () {
      final items = chatItemsFromRest([
        _row('user', [
          {'type': 'text', 'text': 'look at this'}
        ]),
      ]);
      expect(items.single.text, 'look at this');
    });
  });
}
