import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'connections.dart';

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => message;
}

class RpcError implements Exception {
  RpcError(this.code, this.message, [this.data]);
  final int code;
  final String message;

  /// Machine-readable error payload (``error.data``), e.g. ``{'reason': 'SESSION_NOT_OWNED'}``.
  final Object? data;

  /// ``error.data.reason`` when the server sent a structured refusal.
  String? get reason {
    final d = data;
    return d is Map && d['reason'] is String ? d['reason'] as String : null;
  }

  @override
  String toString() => message;
}

/// HTTP side of `hermes serve`: password login, WS tickets, transcription.
class HermesApi {
  HermesApi(this.baseUrl, this.user, this.pass, [this.cookie = '']);

  String baseUrl;
  String user;
  String pass;
  String cookie;

  /// Id of the saved gateway this session belongs to (see [Connections]).
  String? connId;

  static const _store = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 20);

  static Future<HermesApi?> load() async {
    final url = await _store.read(key: 'url');
    final user = await _store.read(key: 'user');
    final pass = await _store.read(key: 'pass');
    if (url == null || user == null || pass == null) return null;
    final a = HermesApi(url, user, pass, await _store.read(key: 'cookie') ?? '');
    try {
      final adopted = await Connections.instance.adoptLegacy();
      a.connId = adopted?.id ?? (await Connections.instance.active())?.id;
    } catch (_) {}
    return a;
  }

  Future<void> save() async {
    await _store.write(key: 'url', value: baseUrl);
    await _store.write(key: 'user', value: user);
    await _store.write(key: 'pass', value: pass);
    await _store.write(key: 'cookie', value: cookie);
    try {
      final s = Connections.instance;
      final prior = connId == null
          ? null
          : (await s.list()).where((c) => c.id == connId).firstOrNull;
      final c = Conn(
        id: connId ?? Connections.newId(),
        name: prior?.name ?? Connections.defaultName(baseUrl),
        url: baseUrl,
        user: user,
        pass: pass,
      );
      await s.upsert(c);
      await s.setActive(c.id);
      connId = c.id;
    } catch (_) {}
  }

  /// End this gateway's session: forget the login cookie, keep the saved
  /// gateways themselves.
  Future<void> logout() async {
    cookie = '';
    try {
      await _store.delete(key: 'cookie');
    } catch (_) {}
  }

  static Future<void> clear() => _store.deleteAll();

  static Future<bool> biometricEnabled() async => (await _store.read(key: 'bio')) == '1';
  static Future<void> setBiometric(bool on) => _store.write(key: 'bio', value: on ? '1' : '0');

  Map<String, String> get _headers => {'Cookie': cookie, 'Content-Type': 'application/json'};

  Future<void> login() async {
    final http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('$baseUrl/auth/password-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'provider': 'basic', 'username': user, 'password': pass}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw AuthError('انتهت مهلة الاتصال بالخادم. تأكد من تشغيل Tailscale على الجوال.');
    } on SocketException {
      throw AuthError('تعذر الوصول إلى الخادم. تأكد من العنوان ومن تشغيل Tailscale.');
    }
    if (r.statusCode == 401) throw AuthError('اسم المستخدم أو كلمة المرور غير صحيحة.');
    if (r.statusCode == 429) throw AuthError('محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة.');
    if (r.statusCode != 200) throw AuthError('تعذر تسجيل الدخول (رمز ${r.statusCode}).');
    final raw = r.headers['set-cookie'] ?? '';
    final re = RegExp(r'(hermes_session_\w+)=("[^"]*"|[^;,\s]*)');
    cookie = re.allMatches(raw).map((m) => '${m[1]}=${m[2]}').join('; ');
    if (cookie.isEmpty) throw AuthError('لم يُرجع الخادم جلسة دخول.');
    await _store.write(key: 'cookie', value: cookie);
  }

  Future<http.Response> _postAuthed(String path, Object body) async {
    var r = await http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    if (r.statusCode == 401 || r.statusCode == 403) {
      await login();
      r = await http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    }
    return r;
  }

  /// Fetch a file from the gateway host by absolute path (what `MEDIA:` points at).
  Future<List<int>> download(String path) async {
    Future<http.Response> get() => http
        .get(Uri.parse('$baseUrl/api/fs/download').replace(queryParameters: {'path': path}), headers: _headers)
        .timeout(const Duration(seconds: 120));
    var r = await get();
    if (r.statusCode == 401 || r.statusCode == 403) {
      await login();
      r = await get();
    }
    if (r.statusCode == 404) throw 'الملف غير موجود على الخادم';
    if (r.statusCode == 413) throw 'الملف أكبر من المسموح';
    if (r.statusCode != 200) throw 'تعذر التنزيل (رمز ${r.statusCode})';
    return r.bodyBytes;
  }

  Future<String> ticket() async {
    final r = await _postAuthed('/api/auth/ws-ticket', {});
    if (r.statusCode != 200) throw AuthError('تعذر الحصول على تذكرة الاتصال (${r.statusCode}).');
    return jsonDecode(r.body)['ticket'] as String;
  }

  Future<String> transcribe(List<int> bytes, String mime) async {
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final r = await _postAuthed('/api/audio/transcribe', {
      'data_url': dataUrl,
      'mime_type': mime,
    }).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('فشل التفريغ الصوتي (${r.statusCode})');
    return (jsonDecode(utf8.decode(r.bodyBytes))['transcript'] as String? ?? '').trim();
  }
}

enum LinkState { connecting, connected, offline }

/// JSON-RPC over `/api/ws` — the same wire Hermes Desktop speaks.
class Gateway extends ChangeNotifier {
  Gateway(this.api);

  final HermesApi api;
  WebSocket? _ws;
  int _n = 0;
  final _pending = <String, Completer<dynamic>>{};
  final _pendingTimers = <String, Timer>{};
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final requests = StreamController<Map<String, dynamic>>.broadcast();
  LinkState state = LinkState.offline;
  String? lastError;
  bool _closed = false;
  bool _disposed = false;
  int _retry = 0;
  final _random = Random();
  Timer? _retryTimer;
  bool _everConnected = false;
  Completer<void>? _connecting;
  Timer? _connectTimer;

  int _generation = 0;
  Future<void>? _healthCheck;
  bool _heartbeat = false;

  bool _current(int generation) => !_closed && generation == _generation;

  Future<void> connect() {
    if (_closed || state == LinkState.connected) return Future.value();
    if (_connecting != null) return _connecting!.future;
    _retryTimer?.cancel();
    _retryTimer = null;
    // Install the flight before notifying listeners (which may call connect).
    final done = Completer<void>();
    _connecting = done;
    final generation = ++_generation;
    state = LinkState.connecting;
    _connectTimer = Timer(const Duration(seconds: 15), () => _onDone(generation));
    notifyListeners();
    if (_current(generation)) unawaited(_open(generation));
    return done.future;
  }

  Future<void> _open(int generation) async {
    try {
      final ticket = await api.ticket();
      if (!_current(generation)) return;
      final url = Uri.parse('${api.baseUrl.replaceFirst(RegExp('^http'), 'ws')}/api/ws')
          .replace(queryParameters: {'ticket': ticket});
      final ws = await WebSocket.connect(url.toString());
      // A timed-out/closed attempt still owns its late socket, never the new one.
      if (!_current(generation)) {
        _retireSocket(ws);
        return;
      }
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      _connectTimer?.cancel();
      _connectTimer = Timer(const Duration(seconds: 15), () => _onDone(generation));
      ws.listen(
        (raw) {
          if (_current(generation) && identical(ws, _ws)) _onMessage(raw);
        },
        onDone: () => _onDone(generation),
        onError: (_) => _onDone(generation),
      );
    } catch (_) {
      // Network exceptions may include the ticket URL; never publish them.
      _onDone(generation);
    }
  }

  void _retireSocket(WebSocket ws) {
    ws.pingInterval = null;
    // Keep the guarded reader draining until onDone: cancelling it first stops
    // dart:io processing the close acknowledgement and leaks its close timer.
    unawaited(ws.close().then<void>((_) {}, onError: (Object error, StackTrace stack) {}));
  }

  void _finishConnect() {
    _connectTimer?.cancel();
    _connectTimer = null;
    final done = _connecting;
    _connecting = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _markReady() {
    if (state != LinkState.connecting) return;
    _finishConnect();
    _retry = 0;
    lastError = null;
    state = LinkState.connected;
    call('client.capabilities', {'server_requests': true}).catchError((_) => null);
    final reconnected = _everConnected;
    _everConnected = true;
    notifyListeners();
    if (!_closed && reconnected) events.add({'type': 'client.reconnected', 'session_id': '', 'payload': {}});
  }

  void _scheduleRetry() {
    if (_closed || state != LinkState.offline) return;
    _retryTimer?.cancel();
    final cap = [1000, 2000, 4000, 8000, 10000][_retry.clamp(0, 4)];
    _retry = (_retry + 1).clamp(0, 4);
    // Equal jitter: never spin, never leave a resumed device offline for 30s.
    final delay = Duration(milliseconds: cap ~/ 2 + _random.nextInt(cap ~/ 2 + 1));
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(connect());
    });
  }

  void retryNow() {
    _retry = 0;
    unawaited(connect());
  }

  /// Call on AppLifecycleState.resumed. Coalesces checks, bypasses retry backoff,
  /// and replaces a half-open socket without replaying any application RPC.
  /// Completion means the attempt settled; inspect [state] for its outcome.
  Future<void> ensureHealthy({Duration timeout = const Duration(seconds: 4)}) {
    if (_closed) return Future.value();
    if (_healthCheck != null) return _healthCheck!;
    return _healthCheck = _checkHealth(timeout).whenComplete(() => _healthCheck = null);
  }

  Future<void> _checkHealth(Duration timeout) async {
    if (state != LinkState.connected) {
      _retry = 0;
      await connect();
      return;
    }
    final generation = _generation;
    try {
      await call(_heartbeat ? 'gateway.ping' : 'ping', {}, timeout);
    } catch (_) {
      if (_closed) return;
      // A delayed probe failure belongs only to the socket it probed.
      if (_current(generation)) _onDone(generation);
      _retry = 0;
      await connect();
    }
  }

  void _onDone(int generation) {
    if (!_current(generation)) return;
    ++_generation;
    final ws = _ws;
    _ws = null;
    if (ws != null) _retireSocket(ws);
    _finishConnect();
    _rejectPending();
    lastError = 'تعذر الاتصال بالخادم. تأكد من الشبكة ومن تشغيل Tailscale.';
    if (state != LinkState.offline) {
      state = LinkState.offline;
      notifyListeners();
    }
    _scheduleRetry();
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final msg = decoded;
    final id = msg['id'];
    final method = msg['method'];
    if (method == null && id != null) {
      final error = msg['error'];
      if (error != null && (error is! Map || (error['code'] != null && error['code'] is! num))) return;
      final c = _pending.remove(id.toString());
      if (c == null) return;
      _pendingTimers.remove(id.toString())?.cancel();
      if (error is Map) {
        c.completeError(RpcError(
            (error['code'] as num?)?.toInt() ?? 0, '${error['message'] ?? 'خطأ'}', error['data']));
      } else {
        c.complete(msg['result']);
      }
      return;
    }
    if (method == 'event') {
      final p = msg['params'];
      if (p is! Map<String, dynamic>) return;
      if (p['type'] == 'gateway.ready') {
        final payload = p['payload'];
        _heartbeat = payload is Map && payload['heartbeat'] == true;
        _markReady();
      }
      if (!_closed) events.add(p);
      return;
    }
    if (method != null && id != null) requests.add(msg);
  }

  Future<dynamic> call(String method, [Map<String, dynamic> params = const {}, Duration? timeout]) {
    final ws = _ws;
    if (_closed || state != LinkState.connected || ws == null) {
      return Future.error(RpcError(-1, 'غير متصل بالخادم'));
    }
    final id = 'm${++_n}';
    final String frame;
    try {
      frame = jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    } catch (_) {
      return Future.error(RpcError(-3, 'تعذر ترميز الطلب'));
    }
    try {
      ws.add(frame);
    } catch (_) {
      if (identical(ws, _ws)) _onDone(_generation);
      return Future.error(RpcError(-1, 'انقطع الاتصال'));
    }
    final c = Completer<dynamic>();
    _pending[id] = c;
    _pendingTimers[id] = Timer(timeout ?? const Duration(seconds: 90), () {
      _pendingTimers.remove(id);
      _pending.remove(id);
      c.completeError(RpcError(-2, 'انتهت مهلة الطلب: $method'));
    });
    return c.future;
  }

  void _rejectPending() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(RpcError(-1, 'انقطع الاتصال'));
    }
    _pending.clear();
  }

  void respond(Object id, Object? result) {
    _ws?.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
  }

  void respondError(Object id, String message) {
    _ws?.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': 4001, 'message': message},
      }),
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _finishConnect();
    final ws = _ws;
    _ws = null;
    if (ws != null) _retireSocket(ws);
    state = LinkState.offline;
    _rejectPending();
    unawaited(events.close());
    unawaited(requests.close());
  }

  @override
  void dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    super.dispose();
  }
}
