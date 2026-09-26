import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/api.dart';

/// Actual HTTP tickets + WebSocket upgrades; no mocked socket implementation.
class LocalGateway {
  late HttpServer server;
  final sockets = <WebSocket>[];
  final messages = <Map<String, dynamic>>[];
  int tickets = 0;
  int upgrades = 0;
  Completer<void>? ticketGate;
  Completer<void>? upgradeGate;
  bool autoReady = true;
  bool answerPing = true;
  bool rejectTickets = false;
  bool stopping = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/api/auth/ws-ticket') {
        tickets++;
        await ticketGate?.future;
        request.response.statusCode = rejectTickets ? 503 : 200;
        request.response.write(jsonEncode({'ticket': 'local-test-ticket'}));
        await request.response.close();
        return;
      }
      upgrades++;
      await upgradeGate?.future;
      if (stopping) {
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final msg = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
        messages.add(msg);
        final method = msg['method'];
        if (!stopping &&
            socket.readyState == WebSocket.open &&
            (method == 'client.capabilities' || (answerPing && (method == 'gateway.ping' || method == 'ping')))) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': msg['id'],
              'result': {'ok': true},
            }),
          );
        }
      });
      if (autoReady) ready(socket);
    });
  }

  HermesApi get api => HermesApi('http://127.0.0.1:${server.port}', 'test', 'test', 'test-session');

  void ready(WebSocket socket) => socket.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': 'gateway.ready',
        'payload': {'heartbeat': true},
      },
    }),
  );

  Future<void> stop() async {
    stopping = true;
    if (ticketGate case final gate? when !gate.isCompleted) gate.complete();
    if (upgradeGate case final gate? when !gate.isCompleted) gate.complete();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await server.close(force: true);
  }
}

Future<void> eventually(bool Function() predicate, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Condition not met before $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class CloseDuringEncoding {
  CloseDuringEncoding(this.gateway);
  final Gateway gateway;
  Object? toJson() {
    gateway.close();
    return null;
  }
}

class CapturedTimer implements Timer {
  CapturedTimer(this.duration, this.callback, this.inner);
  final Duration duration;
  final void Function() callback;
  final Timer inner;
  void fire() {
    if (!isActive) return;
    inner.cancel();
    callback();
  }

  @override
  bool get isActive => inner.isActive;
  @override
  int get tick => inner.tick;
  @override
  void cancel() => inner.cancel();
}

void main() {
  late LocalGateway server;
  late Gateway gateway;

  setUp(() async {
    server = LocalGateway();
    await server.start();
    gateway = Gateway(server.api);
  });
  tearDown(() async {
    gateway.close();
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  for (final stage in ['ticket', 'upgrade', 'ready']) {
    test('close cancels $stage flight and ignores late completion', () async {
      if (stage == 'ticket') server.ticketGate = Completer<void>();
      if (stage == 'upgrade') server.upgradeGate = Completer<void>();
      if (stage == 'ready') server.autoReady = false;
      var completed = false;
      var notificationsAfterClose = 0;
      final flight = gateway.connect().then((_) => completed = true);
      await eventually(
        () => switch (stage) {
          'ready' => server.sockets.isNotEmpty,
          'upgrade' => server.upgrades > 0,
          _ => server.tickets > 0,
        },
      );
      gateway.close();
      gateway.addListener(() => notificationsAfterClose++);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(completed, isTrue, reason: 'close must settle connect without waiting for network');
      expect(gateway.state, LinkState.offline);
      server.ticketGate?.complete();
      server.upgradeGate?.complete();
      await flight;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(gateway.state, LinkState.offline);
      expect(notificationsAfterClose, 0);
      expect(server.sockets.where((s) => s.readyState == WebSocket.open), isEmpty);
      if (stage == 'ticket') expect(server.sockets, isEmpty);
      await gateway.connect();
      gateway.retryNow();
      expect(server.tickets, 1);
    });
  }

  test('close rejects pending RPC and cancels its deadline timer', () async {
    await gateway.connect();
    await eventually(() => server.messages.any((m) => m['method'] == 'client.capabilities'));
    final timers = <Timer>[];
    final rpc = runZoned(
      () => gateway.call('session.send', {'text': 'send once'}, const Duration(seconds: 12)),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
    final rejected = expectLater(rpc, throwsA(isA<RpcError>().having((e) => e.code, 'code', -1)));
    await eventually(() => server.messages.any((m) => m['method'] == 'session.send'));
    gateway.close();
    await rejected.timeout(const Duration(milliseconds: 300));
    expect(timers, isNotEmpty);
    expect(timers.every((timer) => !timer.isActive), isTrue);
  });

  test('dispose cancels a late connect and closes event streams', () async {
    server.ticketGate = Completer<void>();
    var eventsDone = false;
    var requestsDone = false;
    gateway.events.stream.listen((_) {}, onDone: () => eventsDone = true);
    gateway.requests.stream.listen((_) {}, onDone: () => requestsDone = true);
    final flight = gateway.connect();
    await eventually(() => server.tickets == 1);
    gateway.dispose();
    await flight.timeout(const Duration(milliseconds: 300));
    server.ticketGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(gateway.state, LinkState.offline);
    expect(server.sockets, isEmpty);
    expect(eventsDone && requestsDone, isTrue);
  });

  test('resume probes a healthy socket once without replacing it', () async {
    await gateway.connect();
    await Future.wait([gateway.ensureHealthy(), gateway.ensureHealthy(), gateway.ensureHealthy()]);
    expect(server.messages.where((m) => m['method'] == 'gateway.ping'), hasLength(1));
    expect(server.tickets, 1);
    expect(gateway.state, LinkState.connected);
  });

  test('resume replaces unresponsive socket and never replays a side-effect RPC', () async {
    await gateway.connect();
    final received = <Map<String, dynamic>>[];
    final sub = gateway.events.stream.listen(received.add);
    addTearDown(sub.cancel);
    final rpc = gateway.call('session.send', {'text': 'only once'});
    final rejected = expectLater(rpc, throwsA(isA<RpcError>().having((e) => e.code, 'code', -1)));
    await eventually(() => server.messages.any((m) => m['method'] == 'session.send'));
    server.answerPing = false;
    await Future.wait([
      gateway.ensureHealthy(timeout: const Duration(milliseconds: 60)),
      gateway.ensureHealthy(timeout: const Duration(milliseconds: 60)),
    ]);
    await rejected;
    await eventually(() => received.any((e) => e['type'] == 'client.reconnected'));
    expect(server.tickets, 2);
    expect(server.messages.where((m) => m['method'] == 'session.send'), hasLength(1));
    expect(received.where((e) => e['type'] == 'client.reconnected'), hasLength(1));
    server.answerPing = true;
    await gateway.ensureHealthy();
    expect(gateway.state, LinkState.connected, reason: 'old onDone must not clear the new socket');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(server.tickets, 2, reason: 'no orphan retry timer from the old socket');
  });

  test('resume while offline skips backoff and joins any connect flight', () async {
    server.rejectTickets = true;
    await gateway.connect();
    expect(gateway.state, LinkState.offline);
    server.rejectTickets = false;
    server.ticketGate = Completer<void>();
    final resumed = gateway.ensureHealthy();
    final joined = gateway.ensureHealthy();
    await eventually(() => server.tickets == 2);
    server.ticketGate!.complete();
    await Future.wait([resumed, joined]);
    expect(gateway.state, LinkState.connected);
    expect(server.tickets, 2);
  });

  test('automatic retries use bounded exponential jitter and stop on close', () async {
    server.rejectTickets = true;
    final timers = <CapturedTimer>[];
    await runZoned(
      gateway.connect,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = CapturedTimer(
            duration,
            zone.bindCallback(callback),
            parent.createTimer(zone, duration, callback),
          );
          timers.add(timer);
          return timer;
        },
      ),
    );
    final delays = <int>[];
    for (var attempt = 0; attempt < 8; attempt++) {
      await eventually(() => gateway.state == LinkState.offline && server.tickets == attempt + 1);
      final retry = timers.last;
      expect(retry.isActive, isTrue);
      final ms = retry.duration.inMilliseconds;
      delays.add(ms);
      final cap = [1000, 2000, 4000, 8000, 10000, 10000, 10000, 10000][attempt];
      expect(ms, inInclusiveRange(cap ~/ 2, cap));
      if (attempt < 7) retry.fire();
    }
    expect(delays.any((ms) => ms % 1000 != 0), isTrue, reason: 'retry delays must be jittered, not lock-step seconds');
    gateway.close();
    expect(timers.every((t) => !t.isActive), isTrue);
    timers.last.fire();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(server.tickets, 8);
  });

  test('application RPC cannot leave the socket before gateway.ready', () async {
    server.autoReady = false;
    final flight = gateway.connect();
    await eventually(() => server.sockets.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await expectLater(
      gateway.call('session.send', {}, const Duration(milliseconds: 40)),
      throwsA(isA<RpcError>().having((e) => e.code, 'code', -1)),
    );
    expect(server.messages.where((m) => m['method'] == 'session.send'), isEmpty);
    server.ready(server.sockets.single);
    await flight;
  });

  test('malformed frames are ignored without breaking the next RPC', () async {
    await gateway.connect();
    final socket = server.sockets.single;
    for (final frame in <Object>[
      'not-json',
      '[]',
      'null',
      [1, 2, 3],
      jsonEncode({'method': 'event', 'params': null}),
      jsonEncode({'method': 'event', 'params': []}),
    ]) {
      socket.add(frame);
    }
    await gateway.ensureHealthy();
    expect(gateway.state, LinkState.connected);
    expect(server.tickets, 1);
  });

  test('unencodable RPC fails asynchronously without leaking pending work', () async {
    await gateway.connect();
    Future<dynamic>? result;
    expect(() => result = gateway.call('session.send', {'invalid': Object()}), returnsNormally);
    await expectLater(result!, throwsA(isA<RpcError>().having((e) => e.code, 'code', -3)));
    await gateway.ensureHealthy();
    expect(server.messages.where((m) => m['method'] == 'session.send'), isEmpty);
    gateway.close();
  });

  test('timed-out upgrade completing after replacement cannot steal its socket', () async {
    final heldUpgrade = Completer<void>();
    server.upgradeGate = heldUpgrade;
    final timers = <CapturedTimer>[];
    final first = runZoned(
      gateway.connect,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = CapturedTimer(
            duration,
            zone.bindCallback(callback),
            parent.createTimer(zone, duration, callback),
          );
          timers.add(timer);
          return timer;
        },
      ),
    );
    await eventually(() => server.upgrades == 1);
    timers.firstWhere((t) => t.duration == const Duration(seconds: 15)).fire();
    await first;
    expect(gateway.state, LinkState.offline);
    server.upgradeGate = null;
    await gateway.connect();
    final replacement = server.sockets.single;
    heldUpgrade.complete();
    await eventually(() => server.sockets.length == 2 && server.sockets.last.readyState == WebSocket.closed);
    expect(replacement.readyState, WebSocket.open);
    await gateway.ensureHealthy();
    expect(gateway.state, LinkState.connected);
    expect(server.tickets, 2);
  });

  test('missing gateway.ready expires, closes its socket, and settles connect', () async {
    server.autoReady = false;
    final timers = <CapturedTimer>[];
    final flight = runZoned(
      gateway.connect,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = CapturedTimer(
            duration,
            zone.bindCallback(callback),
            parent.createTimer(zone, duration, callback),
          );
          timers.add(timer);
          return timer;
        },
      ),
    );
    await eventually(() => server.sockets.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    timers.lastWhere((t) => t.isActive && t.duration == const Duration(seconds: 15)).fire();
    await flight;
    await eventually(() => server.sockets.single.readyState == WebSocket.closed);
    expect(gateway.state, LinkState.offline);
    expect(gateway.lastError, isNotNull);
    gateway.close();

    expect(timers.every((t) => !t.isActive), isTrue);
  });

  test('RPC timeout does not replay and late reply cannot complete another call', () async {
    await gateway.connect();
    final timedOut = gateway.call('session.send', {'text': 'once'}, const Duration(milliseconds: 30));
    await expectLater(timedOut, throwsA(isA<RpcError>().having((e) => e.code, 'code', -2)));
    final original = server.messages.singleWhere((m) => m['method'] == 'session.send');
    server.sockets.single.add(jsonEncode({'id': original['id'], 'result': 'late'}));
    await gateway.ensureHealthy();
    expect(gateway.state, LinkState.connected);
    expect(server.messages.where((m) => m['method'] == 'session.send'), hasLength(1));
  });

  test('dispose during a health check does not reconnect', () async {
    await gateway.connect();
    server.answerPing = false;
    final health = gateway.ensureHealthy();
    await eventually(() => server.messages.any((m) => m['method'] == 'gateway.ping'));
    gateway.dispose();
    await health.timeout(const Duration(milliseconds: 300));
    await gateway.ensureHealthy();
    expect(server.tickets, 1);
    expect(gateway.state, LinkState.offline);
  });

  test('socket closing during send rejects the RPC asynchronously', () async {
    await gateway.connect();
    Future<dynamic>? rpc;
    expect(() => rpc = gateway.call('session.send', {'value': CloseDuringEncoding(gateway)}), returnsNormally);
    await expectLater(rpc!, throwsA(isA<RpcError>().having((e) => e.code, 'code', -1)));
    expect(gateway.state, LinkState.offline);
    expect(server.messages.where((m) => m['method'] == 'session.send'), isEmpty);
  });

  test('reentrant offline listener reconnect does not leave an orphan retry', () async {
    server.rejectTickets = true;
    final timers = <CapturedTimer>[];
    var retried = false;
    gateway.addListener(() {
      if (gateway.state == LinkState.offline && !retried) {
        retried = true;
        server.rejectTickets = false;
        unawaited(gateway.connect());
      }
    });
    await runZoned(
      gateway.connect,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = CapturedTimer(
            duration,
            zone.bindCallback(callback),
            parent.createTimer(zone, duration, callback),
          );
          timers.add(timer);
          return timer;
        },
      ),
    );
    await eventually(() => gateway.state == LinkState.connected);
    expect(timers.where((t) => t.isActive && t.duration < const Duration(seconds: 10)), isEmpty);
    expect(server.tickets, 2);
  });

  test('malformed RPC errors cannot orphan a pending reply', () async {
    await gateway.connect();
    final pending = gateway.call('session.list');
    await eventually(() => server.messages.any((m) => m['method'] == 'session.list'));
    final id = server.messages.singleWhere((m) => m['method'] == 'session.list')['id'];
    final socket = server.sockets.single;
    socket.add(jsonEncode({'id': id, 'error': 'invalid'}));
    socket.add(
      jsonEncode({
        'id': id,
        'error': {'code': 'invalid'},
      }),
    );
    socket.add(
      jsonEncode({
        'id': id,
        'result': {'sessions': []},
      }),
    );
    await expectLater(pending.timeout(const Duration(milliseconds: 300)), completion({'sessions': []}));
  });

  test('connected and connect completion wait for gateway.ready', () async {
    server.autoReady = false;
    var completed = false;
    final flight = gateway.connect().then((_) => completed = true);
    await eventually(() => server.sockets.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.state, LinkState.connecting);
    expect(completed, isFalse);
    server.ready(server.sockets.single);
    await flight;
    expect(gateway.state, LinkState.connected);
    await eventually(() => server.messages.any((m) => m['method'] == 'client.capabilities'));
  });

  test('concurrent connect and retryNow share one ticket and socket', () async {
    server.ticketGate = Completer<void>();
    final first = gateway.connect();
    final second = gateway.connect();
    gateway.retryNow();
    await eventually(() => server.tickets > 0);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    server.ticketGate!.complete();
    await Future.wait([first, second]);
    expect(server.tickets, 1);
    expect(server.sockets, hasLength(1));
    await gateway.connect();
    gateway.retryNow();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(server.tickets, 1, reason: 'Connecting a healthy socket must be a no-op');
  });
}
