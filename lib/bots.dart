import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

/// Bot View domain: the Hermes profiles ("bots"), how each one's canonical
/// Bot Chat is resolved, and the avatar/row widgets. Ported from the desktop
/// `hermes-bots` plugin (data.ts, canonical-chat.ts, avatar.tsx).

/// The one canonical title: (profile, "Bot Chat") IS a bot's forever-chat.
const kBotChatTitle = 'Bot Chat';

/// One `profiles.list` row reduced to what the Bot View shows.
class BotInfo {
  const BotInfo({
    required this.name,
    required this.title,
    required this.color,
    required this.shape,
    this.description = '',
    this.section = '',
    this.pinned = false,
    this.hidden = false,
    this.canonicalId,
    this.resolvedId,
    this.preview = '',
    this.lastActive = 0,
    this.workerActiveAt = 0,
    this.sessionActiveAt = 0,
  });

  /// Profile name (the RPC `profile` param).
  final String name;

  /// Display title (ui_meta['hermes-bots'].title, else display_name, else name).
  final String title;
  final Color color;
  final String shape;
  final String description;
  final String section;
  final bool pinned;
  final bool hidden;

  /// Roster `canonical_session`: durable id, lineage tip, last message, time.
  final String? canonicalId;
  final String? resolvedId;
  final String preview;

  /// Unix seconds; 0 when the bot has no chat yet.
  final double lastActive;

  /// Unix seconds of the freshest kanban/tool worker heartbeat (`worker_session.last_active`).
  final double workerActiveAt;

  /// Unix seconds of the bot's freshest message in its Bot Chat or newest visible session.
  final double sessionActiveAt;

  /// The stored id the chat is on screen under (lineage tip, else durable id).
  String? get openId => resolvedId ?? canonicalId;

  /// `ui_meta['hermes-bots']` + canonical session of a `profiles.list` row.
  factory BotInfo.fromProfile(Map p) {
    final name = '${p['name'] ?? ''}'.trim();
    final ui = p['ui_meta'];
    final meta = ui is Map && ui['hermes-bots'] is Map ? Map<String, dynamic>.from(ui['hermes-bots'] as Map) : <String, dynamic>{};
    final cs = p['canonical_session'] is Map ? p['canonical_session'] as Map : const {};
    String s(Object? v) => v == null ? '' : '$v'.trim();
    final display = s(p['display_name']);
    final title = s(meta['title']).isNotEmpty ? s(meta['title']) : (display.isNotEmpty ? display : name);
    final isPrimary = name.toLowerCase() == 'default' && meta['custom'] != true;
    final shape = isPrimary && s(meta['shape']).isEmpty ? 'squircle' : (s(meta['shape']).isEmpty ? defaultBotShape(name) : s(meta['shape']));
    return BotInfo(
      name: name,
      title: title,
      color: parseBotColor(s(meta['color']), name),
      shape: shape,
      description: s(meta['description']).isNotEmpty ? s(meta['description']) : s(p['description']),
      section: s(meta['sectionName']),
      pinned: meta['pinned'] == true,
      hidden: meta['hidden'] == true,
      canonicalId: s(cs['id']).isEmpty ? null : s(cs['id']),
      resolvedId: s(cs['resolved_id']).isEmpty ? null : s(cs['resolved_id']),
      preview: s(cs['preview']),
      lastActive: (cs['last_active'] as num?)?.toDouble() ?? 0,
      sessionActiveAt: math.max(((cs['last_active'] as num?)?.toDouble() ?? 0), (p['last_session'] is Map ? ((p['last_session'] as Map)['last_active'] as num?)?.toDouble() ?? 0 : 0)),
      workerActiveAt: p['worker_session'] is Map ? ((p['worker_session'] as Map)['last_active'] as num?)?.toDouble() ?? 0 : 0,
    );
  }
}

/// Roster as the desktop shows it: hidden bots are dropped, pinned first,
/// then most recently active.
List<BotInfo> parseBots(Object? profiles) {
  final out = <BotInfo>[
    for (final p in (profiles is List ? profiles : const []))
      if (p is Map && '${p['name'] ?? ''}'.trim().isNotEmpty) BotInfo.fromProfile(p),
  ].where((b) => !b.hidden).toList();
  final order = {for (var i = 0; i < out.length; i++) out[i].name: i};
  out.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final t = b.lastActive.compareTo(a.lastActive);
    return t != 0 ? t : order[a.name]!.compareTo(order[b.name]!);
  });
  return out;
}

/// The desktop's legacy flat shapes; a bot with no stored shape gets one from its name.
const _kShapes = ['circle', 'squircle', 'pill', 'triangle', 'hexagon', 'cloud', 'drop'];

String defaultBotShape(String name) {
  var hash = 0;
  for (final r in name.runes) {
    hash = (hash * 31 + r) & 0xFFFFFFFF;
  }
  return _kShapes[hash % _kShapes.length];
}

Color parseBotColor(String hex, String name) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (m != null) return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  // No picked color: a stable hue from the name, like the desktop's profileColor.
  var h = 0;
  for (final r in name.runes) {
    h = (h * 31 + r) & 0xFFFFFF;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.5).toColor();
}

/// A DM preview reads like a DM, not a delivery log line: drop the bot-to-bot prefix.
final _a2aPrefix = RegExp(r"^Message from (?:agent '[^']+'|🤖[^:]+):\s*", caseSensitive: false);

String botPreviewText(String preview) {
  final t = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.replaceFirst(_a2aPrefix, '').trim();
}

/// Compact age like the desktop roster: now / 5m / 3h / 2d.
String botAge(double ts, {DateTime? now}) {
  if (ts <= 0) return '';
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  final d = math.max(0, n - ts);
  if (d < 60) return 'now';
  if (d < 3600) return '${d ~/ 60}m';
  if (d < 86400) return '${d ~/ 3600}h';
  return '${d ~/ 86400}d';
}

// ── running / idle ─────────────────────────────────────────────────────────

/// Kanban/tool workers heartbeat at least every 60 s while running, so a stamp
/// older than this means finished or stalled (desktop `WORKER_ACTIVE_WINDOW_S`).
const kWorkerActiveWindowS = 150;

/// A bot whose last message landed this recently counts as active now
/// (desktop `ACTIVE_WINDOW_S`): a turn running in another backend process is
/// not in this gateway's live-session list, but every message it writes
/// refreshes the stamp.
const kRecentActiveWindowS = 90;

/// Is the bot busy with a turn right now? Same sources as the desktop plus the
/// gateway's live-session list: a live session of its Bot Chat that is not
/// idle ([liveBusy], from `session.active_list`), a worker heartbeat inside
/// the window, or a message written within [kRecentActiveWindowS].
bool botIsWorking(BotInfo bot, {bool liveBusy = false, DateTime? now}) {
  if (liveBusy) return true;
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  if (bot.workerActiveAt > 0 && n - bot.workerActiveAt < kWorkerActiveWindowS) return true;
  return bot.sessionActiveAt > 0 && n - bot.sessionActiveAt < kRecentActiveWindowS;
}

// ── canonical Bot Chat ─────────────────────────────────────────────────────

/// A resolved canonical chat: [registryId] names it, [openedId] (lineage tip)
/// is what actually gets opened.
class CanonicalChat {
  const CanonicalChat(this.registryId, this.openedId);
  final String registryId;
  final String openedId;
}

typedef BotRpc = Future<dynamic> Function(String method, Map<String, dynamic> params);

/// A `session.list` row IS the canonical registry row when its durable root
/// title (else its own title) is exactly "Bot Chat".
bool isCanonicalBotChatRow(Map row) {
  final root = '${row['root_title'] ?? ''}'.trim();
  final title = '${row['title'] ?? ''}'.trim();
  return root == kBotChatTitle || (root.isEmpty && title == kBotChatTitle);
}

/// THE identity lookup: the profile's session titled exactly "Bot Chat"
/// (hidden rows included). Fails CLOSED: an RPC failure, or an empty answer
/// when the roster already knew a chat, throws instead of reading as "no Bot
/// Chat exists" — that is the only way to fork a bot's forever chat.
Future<CanonicalChat?> findCanonicalChat(BotRpc rpc, BotInfo bot) async {
  final Object? res;
  try {
    res = await rpc('session.list', {
      'profile': bot.name,
      'title': kBotChatTitle,
      'limit': 200,
      'include_hidden': true,
    });
  } catch (e) {
    throw StateError("Could not check ${bot.title}'s Bot Chat registry ($e) — not starting a new chat");
  }
  final rows = res is Map && res['sessions'] is List ? res['sessions'] as List : const [];
  for (final r in rows) {
    if (r is Map && isCanonicalBotChatRow(r) && '${r['id'] ?? ''}'.isNotEmpty) {
      final id = '${r['id']}';
      final tip = '${r['resolved_id'] ?? ''}';
      return CanonicalChat(id, tip.isEmpty ? id : tip);
    }
  }
  if (bot.canonicalId != null) {
    throw StateError("Could not confirm ${bot.title}'s Bot Chat registry — not starting a new chat");
  }
  return null;
}

/// Open-or-create: the existing "Bot Chat" if the registry has one, else mint it
/// (hidden, titled right away so the registry has it before the first prompt).
Future<CanonicalChat> resolveCanonicalChat(BotRpc rpc, BotInfo bot) async {
  final existing = await findCanonicalChat(rpc, bot);
  if (existing != null) return existing;
  final res = await rpc('session.create', {
    'profile': bot.name,
    'title': kBotChatTitle,
    'hidden': true,
    'follow_profile_config': true,
    'source': 'mobile',
  });
  final stored = res is Map ? '${res['stored_session_id'] ?? ''}' : '';
  final runtime = res is Map ? '${res['session_id'] ?? ''}' : '';
  if (stored.isEmpty) throw StateError('The server did not create a chat for ${bot.title}');
  if (runtime.isNotEmpty) {
    try {
      await rpc('session.title', {'session_id': runtime, 'title': kBotChatTitle});
    } catch (e) {
      // Another writer took the canonical title first: adopt the winner, never fork.
      if (RegExp('already in use', caseSensitive: false).hasMatch('$e')) {
        final winner = await findCanonicalChat(rpc, BotInfo(name: bot.name, title: bot.title, color: bot.color, shape: bot.shape));
        if (winner != null) return winner;
      }
    }
  }
  return CanonicalChat(stored, stored);
}

// ── avatar ────────────────────────────────────────────────────────────────

bool _isDark(Color c) => (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255 < 110;

/// The desktop's face: a colored body (circle, squircle, pill, triangle,
/// hexagon, cloud, drop) with two eyes. Unknown shapes (blobatar etc.) fall
/// back to a soft squircle in the bot's color.
class BotAvatar extends StatelessWidget {
  const BotAvatar({super.key, required this.shape, required this.color, this.size = 44});
  final String shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: BotFacePainter(shape, color));
}

class BotFacePainter extends CustomPainter {
  BotFacePainter(this.shape, this.color);
  final String shape;
  final Color color;

  /// Body outline in a 40x40 box.
  static Path body(String shape) {
    switch (shape) {
      case 'circle':
        return Path()..addOval(const Rect.fromLTWH(3, 3, 34, 34));
      case 'pill':
        return Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 8, 34, 24), const Radius.circular(12)));
      case 'triangle':
        return Path()
          ..moveTo(20, 4)
          ..lineTo(36, 33)
          ..lineTo(4, 33)
          ..close();
      case 'hexagon':
        final p = Path();
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 3 * i - math.pi / 2;
          final x = 20 + 17 * math.cos(a), y = 20 + 17 * math.sin(a);
          i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
        }
        return p..close();
      case 'cloud':
        var p = Path()..addOval(const Rect.fromLTWH(4, 16, 17, 17));
        for (final r in const [Rect.fromLTWH(9, 7, 20, 20), Rect.fromLTWH(20, 14, 16, 19), Rect.fromLTWH(10, 20, 24, 13)]) {
          p = Path.combine(PathOperation.union, p, Path()..addOval(r));
        }
        return p;
      case 'drop':
        return Path()
          ..moveTo(20, 3)
          ..cubicTo(20, 3, 34, 17, 34, 25)
          ..arcToPoint(const Offset(6, 25), radius: const Radius.circular(14), clockwise: true)
          ..cubicTo(6, 17, 20, 3, 20, 3)
          ..close();
      case 'squircle':
      default:
        return Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 3, 34, 34), const Radius.circular(13)));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 40;
    canvas.save();
    canvas.scale(k);
    final fill = Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final path = body(shape);
    canvas.drawPath(path, fill);
    // Round the corners of the polygonal bodies.
    if (shape == 'triangle' || shape == 'hexagon') {
      canvas.drawPath(
          path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeJoin = StrokeJoin.round);
    }
    final dark = _isDark(color);
    final eye = Paint()..color = dark ? const Color(0xF2E8DCC3) : const Color(0xD9000000);
    final hl = Paint()..color = dark ? const Color(0x99000000) : const Color(0xD9FFFFFF);
    final y = shape == 'cloud' ? 23.0 : shape == 'triangle' ? 24.0 : shape == 'drop' ? 24.0 : 19.5;
    for (final x in const [14.8, 25.2]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4.4, height: 5), eye);
      canvas.drawCircle(Offset(x - 0.6, y - 1.0), 0.8, hl);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BotFacePainter old) => old.shape != shape || old.color != color;
}

/// "Working…" (breathing accent dot) or "Idle" (grey dot).
class BotStatus extends StatefulWidget {
  const BotStatus({super.key, required this.working});
  final bool working;
  @override
  State<BotStatus> createState() => _BotStatusState();
}

class _BotStatusState extends State<BotStatus> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.working) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(BotStatus old) {
    super.didUpdateWidget(old);
    if (widget.working && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.working && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.working;
    final dot = Container(width: 8, height: 8, decoration: BoxDecoration(color: w ? D.accent : D.faint, shape: BoxShape.circle));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        w ? FadeTransition(opacity: Tween(begin: 0.3, end: 1.0).animate(_c), child: dot) : dot,
        const SizedBox(width: 5),
        Text(w ? 'Working…' : 'Idle',
            key: ValueKey(w ? 'bot-working' : 'bot-idle'),
            style: txt(11.5, color: w ? D.accent : D.faint, weight: w ? FontWeight.w600 : FontWeight.w400, height: 1.3)),
      ]),
    );
  }
}

// ── list ──────────────────────────────────────────────────────────────────

/// One bot row: avatar, title, age; under it the last message.
class BotRowTile extends StatelessWidget {
  const BotRowTile({super.key, required this.bot, required this.onTap, this.selected = false, this.busy = false, this.opening = false});
  final BotInfo bot;
  final VoidCallback onTap;
  final bool selected;
  final bool busy;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final preview = botPreviewText(bot.preview);
    final age = botAge(bot.lastActive);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? D.surfaceTop.withValues(alpha: 0.55) : Colors.transparent,
        borderRadius: BorderRadius.circular(D.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(D.rMd),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                BotAvatar(shape: bot.shape, color: bot.color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(
                        child: Text(bot.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            textDirection: dDirOf(bot.title),
                            style: txt(14.5, weight: selected ? FontWeight.w700 : FontWeight.w600, height: 1.3)),
                      ),
                      const SizedBox(width: 8),
                      BotStatus(working: busy),
                      if (age.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(age, textDirection: dDirOf(age), style: txt(11.5, color: D.faint, height: 1.3)),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(preview.isEmpty ? 'No messages yet' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        textDirection: preview.isEmpty ? TextDirection.ltr : dDirOf(preview),
                        style: txt(12.5, color: D.muted, height: 1.35)),
                  ]),
                ),
                if (opening) ...[
                  const SizedBox(width: 10),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: D.accent)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty / loading / error states of the Bots tab.
class BotsEmpty extends StatelessWidget {
  const BotsEmpty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(child: Text(text, textDirection: dDirOf(text), textAlign: TextAlign.center, style: txt(13.5, color: D.muted))),
      );
}
