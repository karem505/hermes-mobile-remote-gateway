import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/store.dart';

import 'attachment_delivery_test.dart' show RecordingGateway;

/// 回归：一次回复只能渲染一遍。
/// 症状（桌面版与手机都遇到过）：流式的那份留在屏幕上，message.complete 又追加一整份，
/// 于是同一段文字出现两次。
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

  void ev(String type, [Map<String, dynamic> payload = const {}]) {
    gw.events.add({'type': type, 'session_id': 'session-a', 'payload': payload});
  }

  test('streamed reply followed by a tool row is settled, not appended twice', () async {
    store.items.add(ChatItem.user('run it'));
    ev('message.start');
    ev('message.delta', {'text': 'Hello'});
    ev('tool.start', {'name': 'terminal'});      // 关键：气泡不再是 items.last
    ev('tool.end', {'name': 'terminal'});
    ev('message.complete', {'text': 'Hello world'});
    await Future<void>.delayed(Duration.zero);

    final replies = store.items.where((i) => i.kind == 'assistant').toList();
    expect(replies.length, 1, reason: '流式 + 收尾不能变成两条助手气泡');
    expect(replies.single.text, 'Hello world');
  });

  test('a second turn still gets its own bubble', () async {
    store.items.add(ChatItem.user('one'));
    ev('message.start');
    ev('message.delta', {'text': 'first'});
    ev('message.complete', {'text': 'first'});
    await Future<void>.delayed(Duration.zero);
    store.items.add(ChatItem.user('two'));
    ev('message.start');
    ev('message.delta', {'text': 'second'});
    ev('message.complete', {'text': 'second'});
    await Future<void>.delayed(Duration.zero);

    final replies = store.items.where((i) => i.kind == 'assistant').toList();
    expect(replies.map((r) => r.text).toList(), ['first', 'second']);
  });
}
