import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/store.dart';
import 'attachment_delivery_test.dart' show RecordingGateway;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final decision in ['accept', 'cancel', 'session-changed']) {
    test('model confirmation $decision binds approval to original session', () async {
      final gw = RecordingGateway();
      final store = HermesStore(gw)..sid = 'session-a';
      final consent = Completer<bool>();
      String? warning;
      gw.handler = (method, params) async => method == 'config.set'
          ? {'confirm_required': params['confirm_expensive_model'] != true,
             'confirm_message': 'Large context warning'} : {};
      try {
        final result = store.setConfig('model', 'new-model --provider example', confirm: (message) {
          warning = message;
          return consent.future;
        });
        await Future<void>.delayed(Duration.zero);
        expect(warning, 'Large context warning');
        expect(gw.calls.where((c) => c.method == 'config.set').length, 1);
        if (decision == 'session-changed') store.sid = 'session-b';
        consent.complete(decision != 'cancel');
        expect(await result, decision == 'accept');
        final calls = gw.calls.where((c) => c.method == 'config.set').toList();
        expect(calls.length, decision == 'accept' ? 2 : 1);
        if (decision == 'accept') {
          expect(calls.last.params['confirm_expensive_model'], true);
          expect(calls.last.params['session_id'], 'session-a');
          expect(store.currentModel, 'new-model');
        }
      } finally { store.dispose(); gw.close(); }
    });
  }
  test('model confirmation must never be silently accepted', () async {
    final gw = RecordingGateway();
    final store = HermesStore(gw)..sid = 'session-a';
    gw.handler = (method, params) async => method == 'config.set'
        ? {'confirm_required': params['confirm_expensive_model'] != true,
           'confirm_message': 'Large context switch warning'} : {};
    try {
      expect(await store.setConfig('model', 'expensive'), false);
      expect(gw.calls.where((c) => c.method == 'config.set').length, 1);
      expect(gw.calls.any((c) => c.params['confirm_expensive_model'] == true), false);
    } finally { store.dispose(); gw.close(); }
  });
}
