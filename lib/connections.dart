import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One saved gateway (server) the app can talk to.
class Conn {
  Conn({required this.id, required this.name, required this.url, required this.user, required this.pass});

  final String id;
  String name;
  String url;
  String user;
  String pass;

  Map<String, dynamic> indexEntry() => {
        'id': id,
        'name': name,
        'url': url,
        'user': user,
      };
}

/// Key-value seam: the app uses the platform keychain; widget tests inject a
/// plain in-memory implementation so no platform channel is needed.
abstract class ConnKv {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureConnKv implements ConnKv {
  const SecureConnKv();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) => _s.write(key: key, value: value);
}

class MemoryConnKv implements ConnKv {
  final Map<String, String?> m = {};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
  }
}

/// Saved gateways: one index list plus a password per entry, in the same
/// keychain the login already used. Storage failures never throw upward; the
/// worst case is an empty list.
class Connections {
  Connections(this.kv);

  /// Swap in tests via [Connections.instance] before pumping widgets.
  static Connections instance = Connections(const SecureConnKv());

  final ConnKv kv;

  static const _index = 'conn.index';
  static const _active = 'conn.active';
  static String _pk(String id, String f) => 'conn.$id.$f';

  static String newId() => 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Future<String?> activeId() async {
    try {
      return await kv.read(_active);
    } catch (_) {
      return null;
    }
  }

  Future<List<Conn>> list() async {
    try {
      final raw = await kv.read(_index);
      if (raw == null || raw.isEmpty) return [];
      final arr = jsonDecode(raw);
      if (arr is! List) return [];
      final out = <Conn>[];
      for (final e in arr) {
        if (e is! Map) continue;
        final id = '${e['id'] ?? ''}';
        if (id.isEmpty) continue;
        out.add(Conn(
          id: id,
          name: '${e['name'] ?? ''}',
          url: '${e['url'] ?? ''}',
          user: '${e['user'] ?? ''}',
          pass: await kv.read(_pk(id, 'pass')) ?? '',
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Conn> all) =>
      kv.write(_index, jsonEncode(all.map((c) => c.indexEntry()).toList()));

  Future<void> setActive(String id) async {
    try {
      await kv.write(_active, id);
    } catch (_) {}
  }

  Future<void> upsert(Conn c) async {
    try {
      final all = await list();
      final i = all.indexWhere((e) => e.id == c.id);
      if (i >= 0) {
        all[i] = c;
      } else {
        all.add(c);
      }
      await kv.write(_pk(c.id, 'pass'), c.pass);
      await _writeIndex(all);
    } catch (_) {}
  }

  Future<void> remove(String id) async {
    try {
      final all = await list();
      all.removeWhere((e) => e.id == id);
      await kv.write(_pk(id, 'pass'), null);
      await _writeIndex(all);
      if (await activeId() == id) {
        await kv.write(_active, all.isEmpty ? null : all.first.id);
      }
    } catch (_) {}
  }

  Future<Conn?> active() async {
    final id = await activeId();
    if (id == null) return null;
    for (final c in await list()) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Older app versions stored a single url/user/pass; adopt it as the first
  /// saved gateway so an upgrade keeps its login.
  Future<Conn?> adoptLegacy() async {
    try {
      if ((await list()).isNotEmpty) return null;
      final url = await kv.read('url');
      final user = await kv.read('user');
      final pass = await kv.read('pass');
      if (url == null || url.isEmpty || user == null || pass == null) return null;
      final c = Conn(id: newId(), name: defaultName(url), url: url, user: user, pass: pass);
      await upsert(c);
      await setActive(c.id);
      return c;
    } catch (_) {
      return null;
    }
  }

  /// `100.64.0.1:9131` (bare host) and `http://host` get the plain-HTTP
  /// default port; `https://…` without a port stays as-is (standard 443).
  static String normalizeUrl(String raw) {
    var base = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return base;
    if (!RegExp(r'^https?://').hasMatch(base)) base = 'http://$base';
    final uri = Uri.tryParse(base);
    if (uri == null) return base;
    if (!uri.hasPort && uri.scheme == 'http') base = '$base:9131';
    return base;
  }

  static String defaultName(String url) {
    final h = Uri.tryParse(url)?.host ?? '';
    return h.isEmpty ? 'بوابة' : h;
  }
}
