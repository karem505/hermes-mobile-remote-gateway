import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/api.dart';
import 'package:hermes_mobile/bots.dart';
import 'package:hermes_mobile/design.dart';
import 'package:hermes_mobile/main.dart';
import 'package:hermes_mobile/store.dart';

Map<String, dynamic> _profile(String name, {String? title, String? shape, String color = '#336699', String? id, String? tip, String preview = '', double? last, bool hidden = false, bool pinned = false}) => {
      'name': name,
      'ui_meta': {
        'hermes-bots': {
          'title': ?title,
          'shape': ?shape,
          'color': color,
          if (hidden) 'hidden': true,
          if (pinned) 'pinned': true,
        }
      },
      if (id != null)
        'canonical_session': {'id': id, 'resolved_id': tip ?? id, 'root_title': 'Bot Chat', 'title': 'Bot Chat', 'preview': preview, 'last_active': last ?? 0},
    };

class _Api extends HermesApi {
  _Api() : super('http://localhost', '', '');
  final profiles = <String?>[];
  @override
  Future<List<Map<String, dynamic>>> sessionMessages(String storedId, {int limit = 300, String? profile}) async {
    profiles.add(profile);
    return [
      {'role': 'user', 'content': 'hi bot', 'display_kind': null},
      {'role': 'assistant', 'content': 'مرحبا يا كارم', 'display_kind': null},
    ];
  }
}

class _Gw extends Gateway {
  _Gw(_Api super.api, {this.canonical = const {}});
  final Map<String, Map<String, dynamic>> canonical; // profile -> session.list row
  final calls = <({String method, Map<String, dynamic> params})>[];
  List<Map<String, dynamic>> roster = [];
  @override
  Future<dynamic> call(String method, [Map<String, dynamic> params = const {}, Duration? timeout]) async {
    calls.add((method: method, params: Map.of(params)));
    switch (method) {
      case 'profiles.list':
        return {'profiles': roster};
      case 'session.list':
        final row = canonical[params['profile']];
        return {'sessions': row == null ? [] : [row]};
      case 'session.create':
        return {'session_id': 'rt-new', 'stored_session_id': 'stored-new'};
      case 'session.resume':
        return {'session_id': 'rt-${params['session_id']}', 'running': false, 'info': {'model': 'm'}};
      case 'session.active_list':
        return {'sessions': []};
      case 'commands.catalog':
        return {'categories': [], 'skills': {}};
      case 'process.list':
      case 'subagent.list':
        return {'processes': [], 'subagents': []};
    }
    return {'status': 'ok'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('roster parsing', () {
    test('title, color, shape and the canonical last message come from profiles.list', () {
      final bots = parseBots([
        _profile('aasec', title: 'AASEC', shape: 'pill', color: '#C0392B', id: 'c1', preview: 'wrote the brief', last: 1000),
        _profile('brand', title: 'التسويق والبراند', shape: 'cloud', id: 'c2', preview: 'newer', last: 2000),
        _profile('ghost', title: 'Hidden', hidden: true),
        _profile('top', title: 'Pinned', pinned: true, last: 1),
        {'name': 'plain'},
      ]);
      expect(bots.map((b) => b.name), ['top', 'brand', 'aasec', 'plain'], reason: 'pinned first, hidden dropped, newest next');
      final aasec = bots.firstWhere((b) => b.name == 'aasec');
      expect(aasec.title, 'AASEC');
      expect(aasec.shape, 'pill');
      expect(aasec.color, const Color(0xFFC0392B));
      expect(aasec.preview, 'wrote the brief');
      expect(aasec.lastActive, 1000);
      expect(bots.firstWhere((b) => b.name == 'plain').title, 'plain');
      expect(bots.firstWhere((b) => b.name == 'brand').title, 'التسويق والبراند');
    });

    test('delivery prefix is stripped and ages are compact', () {
      expect(botPreviewText('Message from 🤖 المدير (@hermes): مهمة تانية'), 'مهمة تانية');
      expect(botPreviewText("Message from agent 'finance': ok"), 'ok');
      expect(botPreviewText('  two\n lines  '), 'two lines');
      final now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
      expect(botAge(1000000 - 20, now: now), 'now');
      expect(botAge(1000000 - 600, now: now), '10m');
      expect(botAge(1000000 - 7200, now: now), '2h');
      expect(botAge(1000000 - 3 * 86400, now: now), '3d');
      expect(botAge(0, now: now), '');
    });
  });

  group('canonical Bot Chat resolution', () {
    BotInfo bot({String? canonicalId}) =>
        BotInfo(name: 'brand', title: 'Brand', color: Colors.orange, shape: 'cloud', canonicalId: canonicalId);

    test('asks the profile for the exact title, hidden rows included, and opens the lineage tip', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final chat = await resolveCanonicalChat((m, p) async {
        calls.add((m, p));
        return {
          'sessions': [
            {'id': 'root', 'resolved_id': 'tip', 'root_title': 'Bot Chat', 'title': 'whatever'}
          ]
        };
      }, bot(canonicalId: 'root'));
      expect(chat.registryId, 'root');
      expect(chat.openedId, 'tip');
      expect(calls.single.$1, 'session.list');
      expect(calls.single.$2, containsPair('profile', 'brand'));
      expect(calls.single.$2, containsPair('title', 'Bot Chat'));
      expect(calls.single.$2, containsPair('include_hidden', true));
    });

    test('a row only counts when its root title (or title) is exactly Bot Chat', () {
      expect(isCanonicalBotChatRow({'title': 'Bot Chat'}), isTrue);
      expect(isCanonicalBotChatRow({'root_title': 'Bot Chat', 'title': 'x'}), isTrue);
      expect(isCanonicalBotChatRow({'root_title': 'Other', 'title': 'Bot Chat'}), isFalse);
      expect(isCanonicalBotChatRow({'title': 'Bot Chat 2'}), isFalse);
    });

    test('a failed lookup fails closed and never mints a new chat', () async {
      final methods = <String>[];
      await expectLater(
        resolveCanonicalChat((m, p) async {
          methods.add(m);
          throw 'socket closed';
        }, bot()),
        throwsA(isA<StateError>()),
      );
      expect(methods, ['session.list']);
    });

    test('an empty answer is not trusted when the roster already knew a chat', () async {
      final methods = <String>[];
      await expectLater(
        resolveCanonicalChat((m, p) async {
          methods.add(m);
          return {'sessions': []};
        }, bot(canonicalId: 'known')),
        throwsA(isA<StateError>()),
      );
      expect(methods, ['session.list']);
    });

    test('a brand-new bot gets a hidden, immediately titled Bot Chat', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final chat = await resolveCanonicalChat((m, p) async {
        calls.add((m, p));
        if (m == 'session.list') return {'sessions': []};
        if (m == 'session.create') return {'session_id': 'rt', 'stored_session_id': 'st'};
        return {};
      }, bot());
      expect(chat.openedId, 'st');
      expect(calls.map((c) => c.$1), ['session.list', 'session.create', 'session.title']);
      expect(calls[1].$2, containsPair('profile', 'brand'));
      expect(calls[1].$2, containsPair('hidden', true));
      expect(calls[2].$2, {'session_id': 'rt', 'title': 'Bot Chat'});
    });

    test('losing the title race adopts the winner instead of forking', () async {
      var lists = 0;
      final chat = await resolveCanonicalChat((m, p) async {
        if (m == 'session.list') {
          lists++;
          return {
            'sessions': lists == 1
                ? []
                : [
                    {'id': 'winner', 'title': 'Bot Chat'}
                  ]
          };
        }
        if (m == 'session.create') return {'session_id': 'rt', 'stored_session_id': 'st'};
        throw 'title already in use';
      }, bot());
      expect(chat.openedId, 'winner');
    });
  });

  group('store', () {
    test('openBot resumes the canonical chat inside the bot profile and loads its transcript', () async {
      final api = _Api();
      final gw = _Gw(api, canonical: {
        'brand': {'id': 'root-b', 'resolved_id': 'tip-b', 'root_title': 'Bot Chat', 'title': 'Bot Chat'}
      });
      final store = HermesStore(gw);
      addTearDown(() {
        store.dispose();
        gw.close();
      });
      await store.openBot(BotInfo(name: 'brand', title: 'Brand Bot', color: Colors.orange, shape: 'cloud', canonicalId: 'root-b', resolvedId: 'tip-b'));
      final resume = gw.calls.firstWhere((c) => c.method == 'session.resume');
      expect(resume.params['session_id'], 'tip-b');
      expect(resume.params['profile'], 'brand');
      expect(api.profiles, ['brand']);
      expect(store.title, 'Brand Bot');
      expect(store.items.map((i) => i.text), ['hi bot', 'مرحبا يا كارم']);
      expect(store.sid, 'rt-tip-b');
      expect(store.openingBot, isNull);
    });
  });

  testWidgets('Bots tab lists avatars, titles, last message and age; tabs switch', (tester) async {
    final api = _Api();
    final gw = _Gw(api, canonical: {
      'aasec': {'id': 'root-a', 'resolved_id': 'tip-a', 'root_title': 'Bot Chat', 'title': 'Bot Chat'}
    });
    final nowS = DateTime.now().millisecondsSinceEpoch / 1000;
    gw.roster = [
      _profile('aasec', title: 'AASEC', shape: 'pill', color: '#C0392B', id: 'root-a', tip: 'tip-a', preview: 'Wrote the brief', last: nowS - 600),
      _profile('brand', title: 'التسويق والبراند', shape: 'cloud', id: 'c-b', preview: 'Message from 🤖 المدير (@hermes): مهمة جديدة', last: nowS - 7200),
    ];
    final store = HermesStore(gw);
    addTearDown(() {
      store.dispose();
      gw.close();
    });
    store.bots = parseBots(gw.roster);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionsDrawer(store: store, onLogout: () {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BotAvatar), findsNWidgets(2));
    expect(find.text('AASEC'), findsOneWidget);
    expect(find.text('التسويق والبراند'), findsOneWidget);
    expect(find.text('Wrote the brief'), findsOneWidget);
    expect(find.text('مهمة جديدة'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('Bots'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);

    await tester.tap(find.text('Sessions'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(BotAvatar), findsNothing);
    await tester.tap(find.text('Bots'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(BotAvatar), findsNWidgets(2));
  });

  testWidgets('every bot shape paints', (tester) async {
    for (final shape in ['circle', 'squircle', 'pill', 'triangle', 'hexagon', 'cloud', 'drop', 'blobatar:x']) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: BotAvatar(shape: shape, color: const Color(0xFF2C3E50))),
      ));
      expect(tester.takeException(), isNull, reason: shape);
    }
  });

  group('running vs idle', () {
    BotInfo b({double worker = 0}) => BotInfo(
        name: 'brand', title: 'Brand', color: Colors.orange, shape: 'cloud', canonicalId: 'root', resolvedId: 'tip', workerActiveAt: worker);

    test('busy live session or a fresh worker heartbeat means working', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
      expect(botIsWorking(b(), now: now), isFalse);
      expect(botIsWorking(b(), liveBusy: true, now: now), isTrue);
      expect(botIsWorking(b(worker: 1000000 - 60), now: now), isTrue);
      expect(botIsWorking(b(worker: 1000000 - 400), now: now), isFalse, reason: 'stale heartbeat');
      expect(botIsWorking(BotInfo(name: 'r', title: 'r', color: Colors.red, shape: 'circle', sessionActiveAt: 1000000 - 30), now: now), isTrue, reason: 'message 30 s ago');
      expect(botIsWorking(BotInfo(name: 'r', title: 'r', color: Colors.red, shape: 'circle', sessionActiveAt: 1000000 - 300), now: now), isFalse);
      final parsed = BotInfo.fromProfile({'name': 'x', 'worker_session': {'last_active': 123.5}});
      expect(parsed.workerActiveAt, 123.5);
    });

    test('store reads non-idle live sessions of the bot chat', () async {
      final gw = _Gw(_Api());
      final store = HermesStore(gw);
      addTearDown(() {
        store.dispose();
        gw.close();
      });
      store.bots = [b()];
      expect(store.botWorking(store.bots.single), isFalse);
      store.active = [ActiveSession('rt1', 'tip', 'Bot Chat', 'working', 'm', 1)];
      expect(store.botWorking(store.bots.single), isTrue);
      store.active = [ActiveSession('rt1', 'tip', 'Bot Chat', 'idle', 'm', 1)];
      expect(store.botWorking(store.bots.single), isFalse);
    });

    testWidgets('row shows Working… in accent for a running bot and Idle for the rest', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            BotRowTile(bot: b(), busy: true, onTap: () {}),
            BotRowTile(bot: BotInfo(name: 'idle', title: 'Idle Bot', color: Colors.teal, shape: 'circle'), busy: false, onTap: () {}),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Working…'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
      final working = tester.widget<Text>(find.text('Working…'));
      expect(working.style!.color, D.accent);
      expect(tester.widget<Text>(find.text('Idle')).style!.color, D.faint);
    });

    testWidgets('bot chat header shows the status of the open bot', (tester) async {
      final gw = _Gw(_Api());
      final store = HermesStore(gw);
      addTearDown(() {
        store.dispose();
        gw.close();
      });
      store.bots = [b()];
      store.storedId = 'tip';
      store.sid = 'rt1';
      store.title = 'Brand';
      Future<void> show() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: TopBar(store: store, onMenu: () {}))));
        await tester.pump(const Duration(milliseconds: 100));
      }

      await show();
      expect(find.byKey(const ValueKey('bot-header-status')), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
      store.active = [ActiveSession('rt1', 'tip', 'Bot Chat', 'streaming', 'm', 1)];
      await show();
      expect(find.text('Working…'), findsOneWidget);
    });
  });
}
