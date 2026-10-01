import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/api.dart';
import 'package:hermes_mobile/store.dart';

import 'attachment_delivery_test.dart' show RecordingGateway;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingGateway gw;
  late HermesStore store;

  setUp(() {
    gw = RecordingGateway();
    store = HermesStore(gw)..sid = 'session-a';
  });

  tearDown(() => store.dispose());

  testWidgets('a refused send raises the pull offer instead of a bare error', (tester) async {
    gw.handler = (method, params) async {
      if (method == 'prompt.submit') {
        throw RpcError(4090, 'This chat is open in another Hermes window/terminal.',
            {'reason': 'SESSION_NOT_OWNED'});
      }
      return gw.response(method, params);
    };

    final accepted = await store.send('مرحبا');

    expect(accepted, isFalse);
    expect(store.running, isFalse);
    expect(store.items, isEmpty); // the optimistic bubble was rolled back
    expect(store.pendingPull, isNotNull);
    expect(store.pendingPull!.text, 'مرحبا');
    expect(store.pendingPull!.sessionId, 'session-a');
    expect(store.pullError, isNull);
  });

  testWidgets('accepting the pull takes over, then resends the same draft', (tester) async {
    var submits = 0;
    gw.handler = (method, params) async {
      if (method == 'prompt.submit') {
        submits += 1;
        if (submits == 1) {
          throw RpcError(4090, 'This chat is open in another Hermes window/terminal.',
              {'reason': 'SESSION_NOT_OWNED'});
        }
        return {'status': 'submitted'};
      }
      if (method == 'session.takeover') {
        expect(params['session_id'], 'session-a');
        return {'status': 'released', 'holder_surface': 'desktop'};
      }
      return gw.response(method, params);
    };

    await store.send('مرحبا');
    await store.acceptPull();

    expect([for (final c in gw.calls) c.method], ['prompt.submit', 'session.takeover', 'prompt.submit']);
    expect(store.pendingPull, isNull);
    expect(store.pullError, isNull);
    expect(store.toast, 'تم سحب الجلسة من سطح المكتب إلى الجوال');
    expect([for (final i in store.items) i.text], contains('مرحبا'));
  });

  testWidgets('a busy holder keeps the offer up with its reason', (tester) async {
    gw.handler = (method, params) async {
      if (method == 'prompt.submit') {
        throw RpcError(4090, 'This chat is open in another Hermes window/terminal.',
            {'reason': 'SESSION_NOT_OWNED'});
      }
      if (method == 'session.takeover') {
        throw RpcError(4090, 'still running on another device',
            {'reason': 'TAKEOVER_BUSY', 'holder_surface': 'desktop'});
      }
      return gw.response(method, params);
    };

    await store.send('مرحبا');
    await store.acceptPull();

    expect(store.pendingPull, isNotNull); // retryable
    expect(store.pulling, isFalse);
    expect(store.pullError, contains('سطح المكتب'));
    expect(store.pullError, contains('أوقف الدور'));
  });

  testWidgets('dismissing the offer clears it and shows no error', (tester) async {
    gw.handler = (method, params) async {
      if (method == 'prompt.submit') {
        throw RpcError(4090, 'open in another Hermes window', {'reason': 'SESSION_NOT_OWNED'});
      }
      return gw.response(method, params);
    };

    await store.send('مرحبا');
    store.dismissPull();

    expect(store.pendingPull, isNull);
    expect(store.pullError, isNull);
  });

  testWidgets('a capacity refusal stays a plain error (no pull offer)', (tester) async {
    gw.handler = (method, params) async {
      if (method == 'prompt.submit') {
        throw RpcError(4090, 'concurrent session limit reached', {'reason': 'SESSION_CAP'});
      }
      return gw.response(method, params);
    };

    final accepted = await store.send('مرحبا');

    expect(accepted, isFalse);
    expect(store.pendingPull, isNull);
    expect(store.toast, contains('تعذر الإرسال'));
  });
}
