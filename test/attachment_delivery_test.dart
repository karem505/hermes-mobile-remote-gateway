import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/api.dart';
import 'package:hermes_mobile/store.dart';

class RecordingGateway extends Gateway {
  RecordingGateway() : super(HermesApi('http://localhost', '', ''));
  final calls = <({String method, Map<String, dynamic> params})>[];
  Future<dynamic> Function(String, Map<String, dynamic>)? handler;

  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> params = const {},
    Duration? timeout,
  ]) async {
    calls.add((method: method, params: Map.of(params)));
    if (handler != null) return handler!(method, params);
    return response(method, params);
  }

  dynamic response(String method, Map<String, dynamic> params) {
    if (method == 'file.attach') {
      return {
        'attached': true,
        'path': '/workspace/attachments/${params['name']}',
        'ref_text': '@file:`attachments/${params['name']}`',
      };
    }
    if (method == 'image.attach_bytes') {
      return {'attached': true, 'path': '/pending/${params['filename']}'};
    }
    if (method == 'session.steer') return {'status': 'queued'};
    if (method == 'session.active_list' || method == 'session.list') {
      return {'sessions': []};
    }
    return {'status': 'submitted'};
  }
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

  for (final action in ['send', 'steer']) {
    test(
      '$action delivers attachment-only payload and visible user cards',
      () async {
        store.running = action == 'steer';
        await store.attach('photo.png', [1]);
        await store.attach('notes.pdf', [2]);
        if (action == 'steer') {
          await store.steer('');
        } else {
          await store.send('');
        }
        final call = gw.calls.last;
        expect(
          call.method,
          action == 'steer' ? 'session.steer' : 'prompt.submit',
        );
        expect(
          call.params['text'],
          contains('@image:/workspace/attachments/photo.png'),
        );
        expect(
          call.params['text'],
          contains('@file:/workspace/attachments/notes.pdf'),
        );
        expect(call.params['text'], contains('vision_analyze'));
        if (action == 'steer') {
          expect(call.params['text'], contains('read_file'));
        }
        final user = store.items.where((i) => i.kind == 'user').single;
        expect(user.files, [
          '/workspace/attachments/photo.png',
          '/workspace/attachments/notes.pdf',
        ]);
        expect(store.attachments, isEmpty);
      },
    );
  }

  test(
    'queued attachment-only turns bind their own files, not later draft files',
    () async {
      store.running = true;
      await store.attach('first.png', [1]);
      await store.enqueue('');
      expect(store.queued.length, 1);
      expect(store.attachments, isEmpty);
      await store.attach('second.pdf', [2]);
      await store.enqueue('second');
      await store.attach('draft.png', [3]);
      store.items.add(ChatItem.assistant('partial'));
      gw.events.add({
        'type': 'message.complete',
        'session_id': 'session-a',
        'payload': {'text': 'completed'},
      });
      await Future<void>.delayed(Duration.zero);
      var submits = gw.calls.where((c) => c.method == 'prompt.submit').toList();
      expect(submits.length, 1);
      expect(submits[0].params['text'], contains('first.png'));
      expect(submits[0].params['text'], isNot(contains('second.pdf')));
      expect(submits[0].params['text'], isNot(contains('draft.png')));
      expect(store.items[0].text, 'completed');
      expect(store.items[1].kind, 'user');
      gw.events.add({
        'type': 'message.complete',
        'session_id': 'session-a',
        'payload': {'text': 'reply one'},
      });
      await Future<void>.delayed(Duration.zero);
      submits = gw.calls.where((c) => c.method == 'prompt.submit').toList();
      expect(submits.length, 2);
      expect(submits[1].params['text'], contains('second.pdf'));
      expect(submits[1].params['text'], isNot(contains('first.png')));
      expect(submits[1].params['text'], isNot(contains('draft.png')));
      expect(store.attachments.single.name, 'draft.png');
      expect(store.queued, isEmpty);
    },
  );

  test(
    'upload failure retains bytes and retries without dropping the draft',
    () async {
      gw.handler = (method, params) async => throw Exception('upload offline');
      await store.attach('retry.png', [4, 5]);
      expect(store.attachments.length, 1);
      expect(await store.send('keep'), isFalse);
      expect(store.attachments.length, 1);
      gw.handler = null;
      expect(await store.send('keep'), isTrue);
      expect(store.attachments, isEmpty);
      expect(store.items.where((i) => i.kind == 'user').single.files, [
        '/workspace/attachments/retry.png',
      ]);
    },
  );

  test(
    'in-flight send cannot reuse the same attachment for steer or queue',
    () async {
      await store.attach('once.png', [1]);
      final ack = Completer<dynamic>();
      gw.handler = (method, params) => ack.future;
      final sent = store.send('one');
      final duplicate = store.steer('duplicate');
      final queued = store.enqueue('duplicate');
      expect(gw.calls.where((c) => c.method != 'file.attach').length, 1);
      ack.complete({'status': 'submitted'});
      expect(await duplicate, isFalse);
      expect(await queued, isFalse);
      expect(await sent, isTrue);
    },
  );

  test(
    'completion before queue RPC acknowledgement cannot resend the same turn',
    () async {
      store.running = true;
      await store.enqueue('first');
      await store.enqueue('second');
      final ack = Completer<dynamic>();
      var submits = 0;
      gw.handler = (method, params) async {
        if (method == 'prompt.submit' && ++submits == 1) return ack.future;
        return gw.response(method, params);
      };
      void complete() => gw.events.add({
        'type': 'message.complete',
        'session_id': 'session-a',
        'payload': {},
      });
      complete();
      await Future<void>.delayed(Duration.zero);
      complete();
      await Future<void>.delayed(Duration.zero);
      expect(submits, 1);
      ack.complete({'status': 'submitted'});
      await Future<void>.delayed(Duration.zero);
      expect(
        gw.calls
            .where((c) => c.method == 'prompt.submit')
            .map((c) => c.params['text']),
        ['first', 'second'],
      );
    },
  );

  for (final action in ['send', 'steer']) {
    test(
      '$action failure retains attachments for retry without a phantom user row',
      () async {
        await store.attach('retain.pdf', [1]);
        gw.handler = (method, params) async => action == 'steer'
            ? {'status': 'rejected'}
            : throw Exception('offline');
        expect(
          await (action == 'steer'
              ? store.steer('retain')
              : store.send('retain')),
          isFalse,
        );
        expect(store.attachments.single.name, 'retain.pdf');
        expect(store.items.where((i) => i.kind == 'user'), isEmpty);
        gw.handler = null;
        expect(
          await (action == 'steer'
              ? store.steer('retain')
              : store.send('retain')),
          isTrue,
        );
        expect(store.items.where((i) => i.kind == 'user').length, 1);
      },
    );
  }

  test(
    'uploading draft refuses all actions without consuming text or files',
    () async {
      final upload = Completer<dynamic>();
      gw.handler = (method, params) => upload.future;
      final picked = store.attach('slow.png', [1]);
      expect(await store.send('caption'), isFalse);
      expect(await store.steer('caption'), isFalse);
      expect(await store.enqueue('caption'), isFalse);
      expect(store.attachments.length, 1);
      expect(store.queued, isEmpty);
      upload.complete({'attached': true, 'path': '/workspace/slow.png'});
      await picked;
    },
  );

  test('queued slash commands still use command dispatch', () async {
    store.running = true;
    await store.enqueue('/help');
    gw.events.add({
      'type': 'message.complete',
      'session_id': 'session-a',
      'payload': {},
    });
    await Future<void>.delayed(Duration.zero);
    expect(gw.calls.where((c) => c.method == 'slash.exec').length, 1);
    expect(gw.calls.where((c) => c.method == 'prompt.submit'), isEmpty);
  });

  test('late failed submit cannot stop a different selected session', () async {
    await store.attach('old.png', [1]);
    final ack = Completer<dynamic>();
    gw.handler = (method, params) => ack.future;
    final sent = store.send('old session');
    store.sid = 'session-b';
    store.running = true;
    ack.completeError(Exception('old connection failed'));
    expect(await sent, isFalse);
    expect(store.running, isTrue);
    expect(
      await store.send('new session'),
      isFalse,
      reason: 'old attachments cannot cross sessions',
    );
  });

  test('queued turn never drains into a different session', () async {
    store.running = true;
    await store.attach('old.pdf', [1]);
    await store.enqueue('old');
    store.sid = 'session-b';
    store.running = false;
    await store.retryQueue();
    expect(gw.calls.where((c) => c.method == 'prompt.submit'), isEmpty);
    expect(store.queued.single.sessionId, 'session-a');
  });

  test('quoted attachment paths survive transcript reload', () {
    final (text, files) = splitAttachments(
      'caption\n@image:`/workspace/my image.png`\n@file:"/workspace/my report.pdf"',
    );
    expect(text, 'caption');
    expect(files, ['/workspace/my image.png', '/workspace/my report.pdf']);
  });

  test(
    'picking an image stages bytes without arming session-wide image queue',
    () async {
      await store.attach('my image.png', [1, 2, 3]);
      expect(gw.calls.single.method, 'file.attach');
      expect(
        store.attachments.single.path,
        '/workspace/attachments/my image.png',
      );
      expect(
        store.attachments.single.ref,
        '@image:`/workspace/attachments/my image.png`',
      );
      await store.detach(store.attachments.single);
      expect(
        gw.calls.length,
        1,
        reason: 'detaching staged refs is local, not shared queue mutation',
      );
    },
  );
}
