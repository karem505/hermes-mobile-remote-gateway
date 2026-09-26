import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'design.dart';
import 'notify.dart';

class ChatItem {
  ChatItem.user(this.text) : kind = 'user', detail = '', done = true;
  ChatItem.assistant(this.text) : kind = 'assistant', detail = '', done = true;
  ChatItem.tool(this.text, {this.toolId, this.detail = '', this.done = true}) : kind = 'tool';
  ChatItem.notice(this.text) : kind = 'notice', detail = '', done = true;
  ChatItem.thinking(this.text) : kind = 'thinking', detail = '', done = false;

  final String kind;
  String text;
  List<String> files = const []; // attachment paths shown as cards under the text
  String? toolId;
  String detail;
  bool done;
  double? duration;
}

class ActiveSession {
  ActiveSession(this.id, this.key, this.title, this.status, this.model, this.lastActive);
  final String id; // live runtime id
  final String key; // durable id (matches SessionRow.id)
  final String title;
  final String status; // idle|starting|waiting|working|streaming|resuming
  final String model;
  final double lastActive;
  bool get busy => status != 'idle';
}

class SessionRow {
  SessionRow(this.id, this.title, this.source, this.startedAt, this.count);
  final String id;
  final String title;
  final String source;
  final double startedAt;
  final int count;
}

class CommandEntry {
  CommandEntry(this.name, this.description, this.group);
  final String name;
  final String description;
  final String group;
}

class ModelOption {
  ModelOption(this.provider, this.providerName, this.model);
  final String provider;
  final String providerName;
  final String model;
}

class Attachment {
  Attachment(this.name, this.isImage, {this.ref = '', this.path = '', this.sessionId, this.bytes = const []});
  final String? sessionId;
  List<int> bytes;
  String? error;
  final String name;
  final bool isImage;
  String ref; // explicit @image: or @file: reference
  String path; // absolute server path, also used by visible cards
  bool uploading = true;
}

class QueuedTurn {
  QueuedTurn(this.sessionId, this.text, List<Attachment> files) : files = List.unmodifiable(files);
  final String sessionId;
  final String text;
  final List<Attachment> files;
}

class PendingRequest {
  PendingRequest(this.id, this.method, this.params);
  final Object id;
  final String method;
  final Map<String, dynamic> params;
}

/// App state: session list, the one open chat, catalog, model options.
class HermesStore extends ChangeNotifier {
  HermesStore(this.gw) {
    _evSub = gw.events.stream.listen(_onEvent);
    _rqSub = gw.requests.stream.listen(_onRequest);
    gw.addListener(_onLink);
  }

  final Gateway gw;
  late final StreamSubscription _evSub;
  late final StreamSubscription _rqSub;

  List<SessionRow> sessions = [];
  List<ActiveSession> active = [];
  Timer? _activeTimer;

  ActiveSession? activeFor(String storedKey) {
    for (final a in active) {
      if (a.key == storedKey || a.id == storedKey) return a;
    }
    return null;
  }

  Future<void> refreshActive() async {
    if (!connected) return;
    try {
      final r = await gw.call('session.active_list', {if (sid != null) 'current_session_id': sid});
      active = [
        for (final a in (r['sessions'] as List? ?? const []))
          ActiveSession('${a['id']}', '${a['session_key'] ?? ''}', '${a['title'] ?? ''}', '${a['status'] ?? 'idle'}',
              '${a['model'] ?? ''}', (a['last_active'] as num?)?.toDouble() ?? 0)
      ]..sort((x, y) {
          if (x.busy != y.busy) return x.busy ? -1 : 1;
          return y.lastActive.compareTo(x.lastActive);
        });
      final mine = sid == null ? null : active.where((a) => a.id == sid).firstOrNull;
      if (mine != null && mine.busy && !running) running = true;
      notifyListeners();
    } catch (_) {}
  }
  bool loadingSessions = false;
  List<CommandEntry> commands = [];
  List<ModelOption> models = [];
  String currentModel = '';
  String currentProvider = '';

  String? sid; // live runtime id
  String? storedId; // durable id from session.list
  String title = '';
  final items = <ChatItem>[];
  bool running = false;
  bool opening = false;
  String statusText = '';
  Map<String, dynamic> info = {};
  PendingRequest? pending;
  String? toast;
  bool submitting = false;
  final queued = <QueuedTurn>[];
  final attachments = <Attachment>[]; // current composer draft

  bool get connected => gw.state == LinkState.connected;

  void _onLink() {
    if (gw.state == LinkState.connected) {
      refreshSessions();
      refreshActive();
      _activeTimer ??= Timer.periodic(const Duration(seconds: 4), (_) => refreshActive());
      if (commands.isEmpty) loadCatalog();
    }
    notifyListeners();
  }

  void _flash(String msg) {
    toast = msg;
    notifyListeners();
  }

  Future<void> refreshSessions() async {
    loadingSessions = true;
    notifyListeners();
    try {
      final r = await gw.call('session.list', {'limit': 200});
      sessions = [
        for (final s in (r['sessions'] as List))
          SessionRow(
            '${s['id']}',
            ((s['title'] as String?)?.trim().isNotEmpty ?? false)
                ? s['title'] as String
                : ((s['preview'] as String?)?.trim().isNotEmpty ?? false)
                    ? (s['preview'] as String).trim()
                    : 'جلسة بلا عنوان',
            '${s['source'] ?? ''}',
            (s['started_at'] as num?)?.toDouble() ?? 0,
            (s['message_count'] as num?)?.toInt() ?? 0,
          )
      ];
    } catch (e) {
      _flash('تعذر جلب الجلسات: $e');
    }
    loadingSessions = false;
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    try {
      final r = await gw.call('commands.catalog', {if (sid != null) 'session_id': sid});
      final out = <CommandEntry>[];
      for (final cat in (r['categories'] as List)) {
        for (final p in (cat['pairs'] as List)) {
          out.add(CommandEntry('${p[0]}', '${p[1]}', '${cat['name']}'));
        }
      }
      final skills = (r['skills'] as Map?) ?? {};
      final seen = out.map((e) => e.name).toSet();
      final skillNames = skills.keys.map((k) => '$k').toList()..sort();
      for (final k in skillNames) {
        if (!seen.contains(k)) out.add(CommandEntry(k, 'مهارة', 'المهارات'));
      }
      commands = out;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadModels() async {
    try {
      final r = await gw.call('model.options', {if (sid != null) 'session_id': sid});
      currentModel = '${r['model'] ?? ''}';
      currentProvider = '${r['provider'] ?? ''}';
      final out = <ModelOption>[];
      for (final p in (r['providers'] as List)) {
        if (p['authenticated'] == false) continue;
        for (final m in (p['models'] as List? ?? [])) {
          out.add(ModelOption('${p['slug']}', '${p['name'] ?? p['slug']}', '$m'));
        }
      }
      models = out;
      notifyListeners();
    } catch (e) {
      _flash('تعذر جلب النماذج: $e');
    }
  }

  void _applyInfo(Map<String, dynamic>? i) {
    if (i == null) return;
    info = {...info, ...i};
    if (i['model'] != null) currentModel = '${i['model']}';
    if (i['provider'] != null) currentProvider = '${i['provider']}';
    if (i['running'] is bool) running = i['running'] as bool;
    if ((i['title'] as String?)?.isNotEmpty ?? false) title = i['title'] as String;
  }

  void _loadMessages(List? msgs) {
    items.clear();
    for (final m in msgs ?? const []) {
      final role = m['role'];
      if (role == 'user') {
        final (body, files) = splitAttachments('${m['text'] ?? ''}');
        items.add(ChatItem.user(body)..files = files);
      } else if (role == 'assistant') {
        final t = '${m['text'] ?? ''}';
        if (t.trim().isNotEmpty) items.add(ChatItem.assistant(t));
      } else if (role == 'tool') {
        items.add(ChatItem.tool('${m['name']}', detail: '${m['context'] ?? ''}'));
      }
    }
  }

  Future<void> openSession(SessionRow row) async {
    opening = true;
    storedId = row.id;
    title = row.title;
    items.clear();
    pending = null;
    running = false;
    notifyListeners();
    try {
      final r = await gw.call('session.resume', {'session_id': row.id, 'source': 'mobile'}, const Duration(seconds: 120));
      sid = '${r['session_id']}';
      _loadMessages(r['messages'] as List?);
      _applyInfo((r['info'] as Map?)?.cast<String, dynamic>());
      if (r['running'] == true) running = true;
      for (final q in (r['open_requests'] as List? ?? const [])) {
        pending = PendingRequest(q['id'] as Object, '${q['method']}', Map<String, dynamic>.from(q['params'] as Map));
      }
      loadCatalog();
    } catch (e) {
      _flash('تعذر فتح الجلسة: $e');
    }
    opening = false;
    notifyListeners();
  }

  Future<void> newSession() async {
    opening = true;
    items.clear();
    pending = null;
    running = false;
    title = 'جلسة جديدة';
    notifyListeners();
    try {
      final r = await gw.call('session.create', {'source': 'mobile'});
      sid = '${r['session_id']}';
      storedId = r['stored_session_id'] as String?;
      _applyInfo((r['info'] as Map?)?.cast<String, dynamic>());
    } catch (e) {
      _flash('تعذر إنشاء جلسة: $e');
    }
    opening = false;
    notifyListeners();
  }

  Future<bool> send(String text) async {
    final t = text.trim();
    if (sid == null || (t.isEmpty && attachments.isEmpty)) return false;
    if (t.startsWith('/') && attachments.isEmpty) {
      await _slash(t);
      return true;
    }
    return _sendDraft(t, steer: false);
  }

  Future<bool> _sendDraft(String text, {required bool steer, bool queue = false}) async {
    final sessionId = sid;
    if (submitting || sessionId == null || (text.isEmpty && attachments.isEmpty)) return false;
    final selected = List<Attachment>.of(attachments);
    if (selected.any((a) => a.uploading)) {
      _flash('انتظر اكتمال رفع المرفقات');
      return false;
    }
    if (selected.any((a) => a.sessionId != sessionId)) {
      _flash('المرفقات تخص جلسة أخرى؛ احذفها وأرفقها هنا مجددًا');
      return false;
    }
    submitting = true;
    notifyListeners();
    var accepted = false;
    try {
      for (final a in selected.where((a) => a.error != null || a.ref.isEmpty)) {
        await _upload(a);
        if (a.error != null || a.ref.isEmpty) return false;
      }
      if (sid != sessionId || selected.any((a) => !attachments.contains(a))) return false;
      if (queue) {
        queued.add(QueuedTurn(sessionId, text, selected));
        accepted = true;
        _flash('في الطابور: ستُرسل بعد انتهاء الدور الحالي');
      } else {
        accepted = await _deliver(sessionId, text, selected, steer: steer);
      }
      if (accepted) attachments.removeWhere(selected.contains);
      return accepted;
    } finally {
      submitting = false;
      notifyListeners();
      if (accepted && !running) _drainQueue();
    }
  }

  Future<bool> _deliver(String sessionId, String text, List<Attachment> files, {bool steer = false}) async {
    final payload = [
      text,
      for (final a in files) a.ref,
      if (files.any((a) => a.isImage)) _imageHint,
      if (steer && files.any((a) => !a.isImage)) _fileHint,
    ].where((s) => s.isNotEmpty).join('\n\n');
    final item = ChatItem.user(text)..files = files.map((a) => a.path).toList();
    items.add(item);
    if (!steer) {
      running = true;
      statusText = 'يفكر...';
    }
    notifyListeners();
    try {
      final result = await gw.call(steer ? 'session.steer' : 'prompt.submit',
          {'session_id': sessionId, 'text': payload});
      if (steer && (result is! Map || result['status'] != 'queued')) throw 'لم يُقبل التوجيه';
      if (steer && sid == sessionId) _flash('تم التوجيه');
      return true;
    } catch (e) {
      items.remove(item);
      if (sid == sessionId) {
        if (!steer) running = false;
        _flash(steer ? 'تعذر التوجيه: $e' : 'تعذر الإرسال: $e');
      }
      return false;
    }
  }

  Future<void> _slash(String cmd) async {
    items.add(ChatItem.user(cmd));
    notifyListeners();
    final body = cmd.substring(1);
    final name = body.split(RegExp(r'\s+')).first;
    final arg = body.substring(name.length).trim();
    Map? r;
    try {
      r = await gw.call('slash.exec', {'session_id': sid, 'command': body}, const Duration(seconds: 120)) as Map?;
    } catch (_) {
      try {
        r = await gw.call('command.dispatch', {'session_id': sid, 'name': name, 'arg': arg}) as Map?;
      } catch (e) {
        items.add(ChatItem.notice('تعذر تنفيذ /$name: $e'));
        notifyListeners();
        return;
      }
    }
    final type = r?['type'];
    if ((type == 'send' || type == 'skill') && (r?['message'] as String?)?.isNotEmpty == true) {
      running = true;
      notifyListeners();
      await gw.call('prompt.submit', {
        'session_id': sid,
        'text': r!['message'],
        if (r['display'] != null) 'display_kind': null,
      }).catchError((_) => null);
    } else if (type == 'alias' && r?['target'] != null) {
      items.removeLast();
      notifyListeners();
      await _slash('/${r!['target']}');
      return;
    } else {
      final out = '${r?['output'] ?? r?['notice'] ?? ''}'.trim();
      items.add(ChatItem.notice(out.isEmpty ? '/$name: تم' : out));
    }
    if (name == 'model' || name == 'reasoning' || name == 'fast' || name == 'yolo') refreshInfo();
    notifyListeners();
  }

  Future<void> refreshInfo() async {
    if (sid == null) return;
    try {
      final r = await gw.call('session.status', {'session_id': sid});
      if (r is Map && r['info'] is Map) _applyInfo((r['info'] as Map).cast<String, dynamic>());
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> setConfig(String key, String value, {
    Future<bool> Function(String message)? confirm,
  }) async {
    final target = sid;
    if (target == null) return false;
    try {
      final params = <String, dynamic>{'session_id': target, 'key': key, 'value': value};
      var r = await gw.call('config.set', params);
      if (sid != target) return false;
      if (r is Map && r['confirm_required'] == true) {
        final message = '${r['confirm_message'] ?? r['warning'] ?? 'يتطلب تغيير النموذج تأكيدًا.'}';
        if (confirm == null) {
          _flash(message);
          return false;
        }
        final accepted = await confirm(message);
        if (!accepted || sid != target) return false;
        r = await gw.call('config.set', {...params, 'confirm_expensive_model': true});
        if (sid != target) return false;
        if (r is Map && r['confirm_required'] == true) {
          _flash('لم يقبل الخادم تأكيد التغيير. لم يتم تغيير النموذج.');
          return false;
        }
      }
      if (r is Map && r['info'] is Map) _applyInfo((r['info'] as Map).cast<String, dynamic>());
      if (key == 'model') {
        final parts = value.split(' --provider ');
        currentModel = parts.first;
        if (parts.length > 1) currentProvider = parts[1].trim();
      }
      if (key == 'fast') info['fast'] = value == 'fast';
      if (key == 'yolo') info['yolo'] = value == 'on';
      if (key == 'reasoning') info['reasoning_effort'] = value;
      if (r is Map && r['warning'] != null) _flash('${r['warning']}');
      notifyListeners();
      return true;
    } catch (e) {
      _flash('تعذر التغيير: $e');
      return false;
    }
  }

  Future<bool> enqueue(String text) => _sendDraft(text.trim(), steer: false, queue: true);

  void unqueue(int i) {
    if (i < 0 || i >= queued.length) return;
    queued.removeAt(i);
    notifyListeners();
  }

  /// Steer is text-only on the gateway. Explicit paths and reading instructions
  /// travel with it; accepted corrections render as user cards, not thinking.
  Future<bool> steer(String text) => _sendDraft(text.trim(), steer: true);

  Future<void> retryQueue() => _drainQueue();

  QueuedTurn? _draining;

  Future<void> _drainQueue() async {
    if (queued.isEmpty || sid == null || running || submitting || _draining != null) return;
    final next = queued.first;
    if (next.sessionId != sid) return;
    _draining = next;
    var accepted = false;
    try {
      if (next.files.isEmpty && next.text.startsWith('/')) {
        await _slash(next.text);
        accepted = true;
      } else {
        accepted = await _deliver(next.sessionId, next.text, next.files);
      }
      if (accepted) queued.remove(next);
    } finally {
      _draining = null;
      notifyListeners();
    }
    // A completion can arrive before the submit acknowledgement. Only now may
    // the next frozen turn drain; never re-submit the still-pending first one.
    if (accepted && !running) _drainQueue();
  }

  /// Stage bytes only; never arm the gateway's shared attached_images queue.
  /// Each outgoing turn carries its own explicit references instead.
  Future<void> attach(String name, List<int> bytes) async {
    final sessionId = sid;
    if (sessionId == null) return;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'bmp'}.contains(ext);
    final a = Attachment(name, isImage, sessionId: sessionId, bytes: List.of(bytes));
    attachments.add(a);
    await _upload(a);
  }

  Future<void> _upload(Attachment a) async {
    a.uploading = true;
    a.error = null;
    notifyListeners();
    try {
      final ext = a.name.split('.').last.toLowerCase();
      final r = await gw.call('file.attach', {
        'session_id': a.sessionId,
        'data_url': 'data:${_mimeOf(ext)};base64,${base64Encode(a.bytes)}',
        'name': a.name,
      }, const Duration(seconds: 120));
      if (r is! Map || r['attached'] == false) throw 'رُفض الملف';
      a.path = '${r['path'] ?? ''}';
      if (a.path.isEmpty) throw 'لم يُرجع الخادم مسار الملف';
      a.ref = '@${a.isImage ? 'image' : 'file'}:${_quoteRef(a.path)}';
      a.bytes = const [];
    } catch (e) {
      a.error = '$e';
      _flash('تعذر إرفاق ${a.name}: $e — أعد الإرسال للمحاولة');
    } finally {
      a.uploading = false;
      notifyListeners();
    }
  }

  Future<void> detach(Attachment a) async {
    attachments.remove(a);
    notifyListeners();
  }

  /// Release this client's hold on the session so another window (the
  /// desktop) can take it over; the stored conversation stays resumable.
  Future<void> closeSession() async {
    final id = sid;
    if (id == null) return;
    try {
      await gw.call('session.close', {'session_id': id});
      _flash('أُغلقت الجلسة على الجوال، ويمكن فتحها الآن من سطح المكتب');
    } catch (e) {
      _flash('تعذر إغلاق الجلسة: $e');
      return;
    }
    sid = null;
    storedId = null;
    items.clear();
    attachments.clear();
    queued.clear();
    pending = null;
    running = false;
    refreshActive();
    notifyListeners();
  }

  Future<void> interrupt() async {
    if (sid == null) return;
    await gw.call('session.interrupt', {'session_id': sid}).catchError((_) => null);
  }

  void answer(Object? result) {
    final p = pending;
    if (p == null) return;
    gw.respond(p.id, result);
    pending = null;
    notifyListeners();
  }

  void _onRequest(Map<String, dynamic> msg) {
    final method = '${msg['method']}';
    final params = Map<String, dynamic>.from(msg['params'] as Map? ?? {});
    if (method != 'approval' && method != 'clarify') {
      gw.respondError(msg['id'] as Object, 'غير مدعوم في تطبيق الجوال');
      return;
    }
    if (params['session_id'] != null && params['session_id'] != sid) return;
    pending = PendingRequest(msg['id'] as Object, method, params);
    H.attention();
    Notify.i.ask(
      title: title.isEmpty ? 'جلسة' : title,
      body: method.contains('approval') ? 'يحتاج إلى موافقتك لتنفيذ أمر' : 'لديه سؤال ينتظر إجابتك',
      session: storedId,
    );
    notifyListeners();
  }

  ChatItem? _streamTarget() {
    if (items.isNotEmpty && items.last.kind == 'assistant') return items.last;
    return null;
  }

  void _onEvent(Map<String, dynamic> e) {
    final type = '${e['type']}';
    final payload = (e['payload'] is Map) ? Map<String, dynamic>.from(e['payload'] as Map) : <String, dynamic>{};
    if (type == 'sessions.changed') {
      _debounceSessions();
      return;
    }
    if (type == 'client.reconnected') {
      final row = storedId;
      if (row != null) {
        openSession(SessionRow(row, title, '', 0, 0));
      }
      return;
    }
    if (type == 'request.cancel') {
      if (pending != null && '${payload['id']}' == '${pending!.id}') {
        pending = null;
        notifyListeners();
      }
      return;
    }
    if (sid == null || e['session_id'] != sid) return;
    switch (type) {
      case 'message.start':
        running = true;
        statusText = 'يفكر...';
        items.add(ChatItem.assistant(''));
      case 'reasoning.delta' || 'thinking.delta':
        running = true;
        statusText = 'يفكر...';
        final t = '${payload['text'] ?? ''}';
        final last = items.isNotEmpty ? items.last : null;
        if (last != null && last.kind == 'thinking' && !last.done) {
          last.text += t;
        } else {
          // keep an empty assistant placeholder after the thinking block
          if (last != null && last.kind == 'assistant' && last.text.trim().isEmpty) items.removeLast();
          items.add(ChatItem.thinking(t));
        }
      case 'reasoning.available':
        final t = '${payload['text'] ?? ''}';
        if (t.isNotEmpty && !items.any((i) => i.kind == 'thinking' && !i.done)) items.add(ChatItem.thinking(t)..done = true);
      case 'message.delta':
        _closeThinking();
        statusText = 'يكتب الرد...';
        final t = '${payload['text'] ?? ''}';
        final target = _streamTarget();
        if (target == null) {
          items.add(ChatItem.assistant(t));
        } else {
          target.text += t;
        }
      case 'message.complete':
        _closeThinking();
        running = false;
        refreshActive();
        statusText = '';
        final text = '${payload['text'] ?? ''}';
        final target = _streamTarget();
        if (target != null) {
          if (text.isNotEmpty) target.text = text;
          if (target.text.trim().isEmpty) items.removeLast();
        } else if (text.isNotEmpty) {
          items.add(ChatItem.assistant(text));
        }
        _debounceSessions();
        if (queued.isEmpty) {
          H.success();
          final last = items.lastWhere((i) => i.kind == 'assistant', orElse: () => ChatItem.assistant(''));
          Notify.i.done(title: title.isEmpty ? 'جلسة' : title, body: last.text, session: storedId);
        }
        _drainQueue();
      case 'tool.start':
        _closeThinking();
        statusText = 'ينفّذ ${payload['name'] ?? 'أداة'}...';
        final ctx = '${payload['context'] ?? payload['preview'] ?? ''}';
        final target = _streamTarget();
        if (target != null && target.text.trim().isEmpty) items.removeLast();
        items.add(ChatItem.tool('${payload['name']}', toolId: '${payload['tool_id']}', detail: ctx, done: false));
      case 'tool.complete':
        final id = '${payload['tool_id']}';
        for (final it in items.reversed) {
          if (it.kind == 'tool' && it.toolId == id) {
            it.done = true;
            it.duration = (payload['duration_s'] as num?)?.toDouble();
            final s = '${payload['summary'] ?? ''}';
            if (s.isNotEmpty && it.detail.isEmpty) it.detail = s;
            break;
          }
        }
      case 'status.update':
        statusText = '${payload['text'] ?? ''}';
      case 'session.info':
        _applyInfo(payload);
      case 'session.title':
        final t = '${payload['title'] ?? ''}';
        if (t.isNotEmpty) title = t;
      case 'error':
        _closeThinking();
        running = false;
        _drainQueue();
        final msg = '${payload['message'] ?? 'خطأ'}';
        items.add(ChatItem.notice(msg));
        H.error();
        Notify.i.done(title: title.isEmpty ? 'جلسة' : title, body: msg, session: storedId, failed: true);
      default:
        return;
    }
    notifyListeners();
  }

  void _closeThinking() {
    for (final it in items.reversed) {
      if (it.kind == 'thinking' && !it.done) it.done = true;
    }
  }

  Timer? _sessTimer;
  void _debounceSessions() {
    _sessTimer?.cancel();
    _sessTimer = Timer(const Duration(seconds: 2), refreshSessions);
  }

  @override
  void dispose() {
    _activeTimer?.cancel();
    _sessTimer?.cancel();
    _evSub.cancel();
    _rqSub.cancel();
    gw.removeListener(_onLink);
    super.dispose();
  }
}


const _imageHint = '[Examine the attached @image paths with vision_analyze using each path as image_url.]';
const _fileHint = '[Read the attached @file paths with read_file or the appropriate document tool.]';

String _quoteRef(String path) {
  if (!RegExp(r'''[\s\[\]`"']''').hasMatch(path)) return path;
  for (final quote in ['`', '"', "'"]) {
    if (!path.contains(quote)) return '$quote$path$quote';
  }
  throw 'اسم الملف يحتوي على علامات اقتباس غير مدعومة';
}

String _mimeOf(String ext) => switch (ext) {
      'pdf' => 'application/pdf',
      'txt' || 'md' || 'log' => 'text/plain',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip' => 'application/zip',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };


final _attachToken = RegExp(r'''@(?:image|file):(?:`([^`\n]+)`|"([^"\n]+)"|'([^'\n]+)'|(\S+))''');

/// `"look\n@image:/p/a.jpg"` -> `("look", ["/p/a.jpg"])`.
(String, List<String>) splitAttachments(String text) {
  final files = _attachToken.allMatches(text).map((m) => m[1] ?? m[2] ?? m[3] ?? m[4]!).toList();
  final body = text.replaceAll(_attachToken, '').replaceAll(_imageHint, '').replaceAll(_fileHint, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return (body, files);
}
