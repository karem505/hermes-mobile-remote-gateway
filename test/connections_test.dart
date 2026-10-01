import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/connections.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeUrl', () {
    test('https without a port stays standard (no :9131)', () {
      expect(Connections.normalizeUrl('https://gateway.example.com'), 'https://gateway.example.com');
      expect(Connections.normalizeUrl('https://gateway.example.com/'), 'https://gateway.example.com');
    });

    test('http and bare hosts get the plain-HTTP default port', () {
      expect(Connections.normalizeUrl('10.0.0.5'), 'http://10.0.0.5:9131');
      expect(Connections.normalizeUrl('10.0.0.5:9131'), 'http://10.0.0.5:9131');
      expect(Connections.normalizeUrl('http://box.local'), 'http://box.local:9131');
    });

    test('explicit ports are kept for both schemes', () {
      expect(Connections.normalizeUrl('http://host:8080'), 'http://host:8080');
      expect(Connections.normalizeUrl('https://host:9131'), 'https://host:9131');
    });
  });

  group('Connections store', () {
    late Connections store;

    setUp(() {
      store = Connections(MemoryConnKv());
    });

    Conn mk(String id, String name, String url) =>
        Conn(id: id, name: name, url: url, user: 'karem', pass: 'pw-$id');

    test('upsert, list, active, remove round trip', () async {
      expect(await store.list(), isEmpty);
      await store.upsert(mk('a', 'الجهاز المحلي', 'http://10.0.0.5:9131'));
      await store.upsert(mk('b', 'الريموت', 'https://gateway.example.com'));
      await store.setActive('b');

      final list = await store.list();
      expect(list.length, 2);
      expect(list[0].name, 'الجهاز المحلي');
      expect(list[1].url, 'https://gateway.example.com');
      expect(await store.activeId(), 'b');
      expect((await store.active())?.name, 'الريموت');

      // Passwords stay per-entry.
      expect(list[0].pass, 'pw-a');
      expect(list[1].pass, 'pw-b');

      await store.remove('b');
      final after = await store.list();
      expect(after.length, 1);
      expect(after.single.id, 'a');
      // Removing the active entry hands active to the first survivor.
      expect(await store.activeId(), 'a');
    });

    test('upsert replaces in place, keeping position', () async {
      await store.upsert(mk('a', 'A', 'http://a:9131'));
      await store.upsert(mk('b', 'B', 'http://b:9131'));
      await store.upsert(Conn(id: 'a', name: 'A2', url: 'http://a2:9131', user: 'k', pass: 'n'));
      final list = await store.list();
      expect(list.length, 2);
      expect(list[0].name, 'A2');
      expect(list[0].pass, 'n');
      expect(list[1].name, 'B');
    });

    test('adoptLegacy migrates the old single-login keys once', () async {
      final kv = MemoryConnKv();
      kv.m['url'] = 'http://10.0.0.5:9131';
      kv.m['user'] = 'karem';
      kv.m['pass'] = 'secret';
      final s = Connections(kv);

      final adopted = await s.adoptLegacy();
      expect(adopted, isNotNull);
      expect(adopted!.url, 'http://10.0.0.5:9131');
      expect(adopted.pass, 'secret');
      expect(await s.activeId(), adopted.id);

      // Second call is a no-op: the index already exists.
      expect(await s.adoptLegacy(), isNull);
      expect((await s.list()).length, 1);
    });

    test('adoptLegacy does nothing when there is no legacy login', () async {
      final s = Connections(MemoryConnKv());
      expect(await s.adoptLegacy(), isNull);
      expect(await s.list(), isEmpty);
    });

    test('remove drops the password too', () async {
      final kv = MemoryConnKv();
      final s = Connections(kv);
      await s.upsert(mk('a', 'A', 'http://a:9131'));
      await s.remove('a');
      expect(kv.m.containsKey('conn.a.pass'), isFalse);
      expect(await s.list(), isEmpty);
    });
  });
}
