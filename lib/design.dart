import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tb;

import 'background.dart';

/// Design tokens: a warm, Claude-Code-flavoured dark surface with soft depth.
class D {
  static const bg = Color(0xFF141210);
  static const surface = Color(0xFF1E1B19);
  static const surfaceHi = Color(0xFF272322);
  static const border = Color(0xFF312D2A);
  static const borderSoft = Color(0xFF272322);
  static const fg = Color(0xFFF3EEEA);
  static const muted = Color(0xFFA49D96);
  static const accent = Color(0xFFD97757);
  static const accentDim = Color(0xFF9A5540);
  static const accentWash = Color(0xFF2E211C);
  static const ok = Color(0xFF8FAE84);
  static const danger = Color(0xFFC8564B);

  // Motion: fast in, quicker out, one smooth-out curve for every surface.
  static const tIn = Duration(milliseconds: 260);
  static const tOut = Duration(milliseconds: 160);
  static const tSheetIn = Duration(milliseconds: 380);
  static const tSheetOut = Duration(milliseconds: 220);
  static const tPress = Duration(milliseconds: 110);
  static const tRelease = Duration(milliseconds: 320);
  static const ease = Cubic(0.22, 1, 0.36, 1); // smooth decelerate: every open / move
  static const easeIn = Cubic(0.4, 0, 1, 1); // accelerate away: every close
  static const spring = Cubic(0.34, 1.36, 0.64, 1); // tiny overshoot: selection pill, press release

  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 20.0;
  static const rPill = 999.0;

  static const soft = [
    BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
  static const lift = [
    BoxShadow(color: Color(0x8A000000), blurRadius: 26, offset: Offset(0, 12)),
  ];
}

/// Haptic weight matched to what the control does.
enum Hx { none, select, light, medium, heavy }

class H {
  static void fire(Hx h) {
    switch (h) {
      case Hx.none:
        return;
      case Hx.select:
        HapticFeedback.selectionClick();
      case Hx.light:
        HapticFeedback.lightImpact();
      case Hx.medium:
        HapticFeedback.mediumImpact();
      case Hx.heavy:
        HapticFeedback.heavyImpact();
    }
  }

  /// Turn finished: two soft taps.
  static Future<void> success() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    HapticFeedback.mediumImpact();
  }

  /// Something failed: a firm double knock.
  static Future<void> error() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 110));
    HapticFeedback.heavyImpact();
  }

  /// Needs your attention (approval / question).
  static Future<void> attention() async {
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 140));
    HapticFeedback.mediumImpact();
  }
}


/// Whether a value (command, path, tool name, Arabic copy) should lay out LTR.
/// Shared with the chat surface so mixed-direction rows behave the same.
TextDirection dDirOf(String s) {
  for (final r in s.runes) {
    if (r >= 0x0600 && r <= 0x06FF) return TextDirection.rtl;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

typedef IconCtor = Widget Function({Color? color, double? width, double? height});

Widget ic(IconCtor f, {double size = 18, Color color = D.muted, double? w}) =>
    f(color: color, width: w ?? size, height: w ?? size);

TextStyle txt(double size, {Color color = D.fg, FontWeight weight = FontWeight.w400, double height = 1.5}) =>
    TextStyle(color: color, fontSize: size, fontWeight: weight, height: height);

/// Rounded elevated surface: the one container used by every card-like surface.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.color = D.surface,
    this.radius = D.rMd,
    this.shadow = D.soft,
    this.border,
    this.width,
  });

  final Widget child;
  final EdgeInsets pad;
  final EdgeInsets margin;
  final Color color;
  final double radius;
  final List<BoxShadow> shadow;
  final Color? border;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: pad,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );
  }
}

/// Pill button: filled accent, outline, or quiet ghost.
class DBtn extends StatelessWidget {
  const DBtn({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = DBtnKind.fill,
    this.dense = false,
    this.haptic,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconCtor? icon;
  final DBtnKind kind;
  final bool dense;
  final Hx? haptic;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = !enabled
        ? D.muted
        : switch (kind) {
            DBtnKind.fill => const Color(0xFFFFF7F3),
            DBtnKind.outline => D.fg,
            DBtnKind.ghost => D.muted,
          };
    return DPress(
      onTap: onPressed,
      scale: 0.96,
      haptic: haptic ?? (kind == DBtnKind.fill ? Hx.medium : Hx.light),
      child: AnimatedContainer(
      duration: D.tIn,
      curve: D.ease,
      decoration: BoxDecoration(
        color: switch (kind) {
          DBtnKind.fill => enabled ? D.accent : D.surfaceHi,
          DBtnKind.outline => Colors.transparent,
          DBtnKind.ghost => Colors.transparent,
        },
        borderRadius: BorderRadius.circular(D.rPill),
        boxShadow: kind == DBtnKind.fill && enabled ? D.soft : const [],
      ),
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(D.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rPill),
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: dense ? 7 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(D.rPill),
            border: kind == DBtnKind.outline ? Border.all(color: D.border) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ic(icon!, size: dense ? 14 : 16, color: fg),
            if (icon != null) const SizedBox(width: 6),
            Flexible(child: Text(label, textAlign: TextAlign.center, style: txt(dense ? 12.5 : 14, color: fg, weight: FontWeight.w600))),
          ]),
        ),
      ),
      ),
      ),
    );
  }
}

enum DBtnKind { fill, outline, ghost }

/// Round icon button: quiet by default, accent-tinted with a soft glow.
class DIconBtn extends StatelessWidget {
  const DIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.active = false,
    this.size = 40,
    this.tint,
    this.tooltip,
    this.haptic,
  });

  final IconCtor icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool active;
  final double size;
  final Color? tint;
  final String? tooltip;
  final Hx? haptic;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? (active ? D.danger : D.accent) : (active ? D.accentWash : D.surfaceHi);
    final fg = primary ? const Color(0xFFFFF7F3) : (active ? D.accent : (tint ?? D.fg));
    final b = DPress(
      onTap: onPressed,
      scale: 0.88,
      haptic: haptic ?? (primary ? Hx.medium : Hx.light),
      child: AnimatedContainer(
        duration: D.tIn,
        curve: D.ease,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onPressed == null ? D.surfaceHi.withValues(alpha: 0.5) : bg,
          shape: BoxShape.circle,
          boxShadow: primary && onPressed != null ? D.soft : const [],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: DSwap(
                id: '${icon.hashCode}-${onPressed == null}',
                child: ic(icon, size: size * 0.45, color: onPressed == null ? D.border : fg),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// Labelled chip: the model picker and thinking level both use it.
class DChip extends StatelessWidget {
  const DChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.active = false,
    this.trailing,
    this.ltr = false,
  });

  final String label;
  final IconCtor? icon;
  final VoidCallback? onTap;
  final bool active;
  final IconCtor? trailing;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return DPress(
      onTap: onTap,
      scale: 0.95,
      haptic: Hx.select,
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(D.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: D.tIn,
          curve: D.ease,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? D.accentWash : D.surfaceHi,
            borderRadius: BorderRadius.circular(D.rPill),
            border: Border.all(color: active ? D.accentDim : D.borderSoft),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ic(icon!, size: 14, color: active ? D.accent : D.muted),
        if (icon != null) const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: AnimatedSize(
                duration: D.tIn,
                curve: D.ease,
                alignment: AlignmentDirectional.centerStart,
                child: DTextSwap(
                  label,
                  textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                  style: txt(12.5, color: D.fg, weight: FontWeight.w600),
                ),
              ),
            ),
            if (trailing != null) const SizedBox(width: 4),
            if (trailing != null) ic(trailing!, size: 13, color: D.muted),
          ]),
        ),
      ),
      ),
    );
  }
}

/// Text field surface: rounded, soft-shadowed, no harsh border.
class DInput extends StatelessWidget {
  const DInput({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget child;
  final EdgeInsets pad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: D.bg,
        borderRadius: BorderRadius.circular(D.rSm),
        border: Border.all(color: D.borderSoft),
      ),
      child: child,
    );
  }
}

/// Section header inside the sidebar.
class DSection extends StatelessWidget {
  const DSection(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
      child: Row(children: [
        Expanded(
          child: Text(title.toUpperCase(),
              style: txt(11, color: D.muted, weight: FontWeight.w700)),
        ),
        ?trailing,
      ]),
    );
  }
}


enum DNoticeKind { info, success, warning, error }

Color _noticeColor(DNoticeKind kind) => switch (kind) {
  DNoticeKind.success => D.ok,
  DNoticeKind.error => D.danger,
  DNoticeKind.warning => D.accent,
  DNoticeKind.info => D.muted,
};
IconCtor _noticeIcon(DNoticeKind kind) => switch (kind) {
  DNoticeKind.success => tb.CircleCheck.new,
  DNoticeKind.error => tb.AlertCircle.new,
  DNoticeKind.warning => tb.AlertTriangle.new,
  DNoticeKind.info => tb.InfoCircle.new,
};

/// Shared popup: scrollable content, fixed decisions, RTL and large-text safe.
class DDialog extends StatelessWidget {
  const DDialog({super.key, required this.title, required this.body,
    required this.actions, this.kind = DNoticeKind.info});
  final String title;
  final String body;
  final List<Widget> actions;
  final DNoticeKind kind;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: D.surface,
            borderRadius: BorderRadius.circular(24), boxShadow: D.lift),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 4),
                child: ic(_noticeIcon(kind), size: 22, color: _noticeColor(kind))),
              const SizedBox(width: 10),
              Expanded(child: Semantics(namesRoute: true, header: true,
                child: Text(title, style: txt(17, weight: FontWeight.w700)))),
              IconButton(tooltip: 'إغلاق', visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: ic(tb.X.new, size: 18), onPressed: () => Navigator.of(context).maybePop()),
            ]),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(
              child: SelectableText(body, style: txt(13.5, color: D.muted, height: 1.65)))),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 10, alignment: WrapAlignment.end, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Non-blocking feedback, used by copy, uploads, configuration and errors.
class DFeedback {
  static void show(BuildContext context, String message, {DNoticeKind? kind}) {
    final tone = kind ?? (message.startsWith('تعذر') || message.startsWith('فشل')
        ? DNoticeKind.error : message.startsWith('تم ') ? DNoticeKind.success : DNoticeKind.info);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: D.surfaceHi,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      duration: Duration(seconds: tone == DNoticeKind.error ? 7 : 4),
      showCloseIcon: true, closeIconColor: D.muted,
      content: Semantics(liveRegion: true, child: Row(children: [
        ic(_noticeIcon(tone), size: 21, color: _noticeColor(tone)),
        const SizedBox(width: 10),
        Expanded(child: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis,
          style: txt(13, height: 1.5))),
      ])),
    ));
  }
}


/// Show/hide a surface with a height tween plus fade, lift and slight scale,
/// anchored to its bottom edge (menus and chips grow out of the composer).
class DReveal extends StatelessWidget {
  const DReveal({super.key, required this.show, required this.child, this.alignment = Alignment.bottomCenter});

  final bool show;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: show ? D.tIn : D.tOut,
      reverseDuration: D.tOut,
      curve: show ? D.ease : D.easeIn,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: D.tIn,
        reverseDuration: D.tOut,
        switchInCurve: D.ease,
        switchOutCurve: D.easeIn,
        transitionBuilder: (w, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(a),
              alignment: alignment,
              child: w,
            ),
          ),
        ),
        child: show ? KeyedSubtree(key: const ValueKey('on'), child: child) : const SizedBox(key: ValueKey('off'), width: double.infinity),
      ),
    );
  }
}


/// Press feedback: shrinks quickly on touch, springs back on release.
class DPress extends StatefulWidget {
  const DPress({super.key, required this.child, this.onTap, this.scale = 0.94, this.haptic = Hx.light});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Hx haptic;
  @override
  State<DPress> createState() => _DPressState();
}

class _DPressState extends State<DPress> {
  bool down = false;
  Offset? _at;

  void _set(bool v) {
    if (widget.onTap == null || down == v) return;
    setState(() => down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _at = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_at != null && (e.position - _at!).distance > 18) {
          _at = null;
          _set(false);
        }
      },
      onPointerUp: (e) {
        if (_at != null && widget.onTap != null) H.fire(widget.haptic);
        _at = null;
        _set(false);
      },
      onPointerCancel: (_) {
        _at = null;
        _set(false);
      },
      child: AnimatedScale(
        scale: down ? widget.scale : 1,
        duration: down ? D.tPress : D.tRelease,
        curve: down ? Curves.easeOut : D.spring,
        child: widget.child,
      ),
    );
  }
}

/// Swap between two widgets in the same slot: cross-fade + scale + slight turn.
class DSwap extends StatelessWidget {
  const DSwap({super.key, required this.child, required this.id, this.turn = true});
  final Widget child;
  final Object id;
  final bool turn;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: D.tIn,
      reverseDuration: D.tOut,
      switchInCurve: D.ease,
      switchOutCurve: D.easeIn,
      transitionBuilder: (w, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(a),
          child: turn ? RotationTransition(turns: Tween(begin: -0.12, end: 0.0).animate(a), child: w) : w,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(id), child: child),
    );
  }
}

/// Text that changes in place: old value drops out, new one rises in.
class DTextSwap extends StatelessWidget {
  const DTextSwap(this.text, {super.key, required this.style, this.textDirection, this.maxLines = 1});
  final String text;
  final TextStyle style;
  final TextDirection? textDirection;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: D.tIn,
      reverseDuration: D.tOut,
      switchInCurve: D.ease,
      switchOutCurve: D.easeIn,
      layoutBuilder: (cur, prev) => Stack(alignment: AlignmentDirectional.centerStart, children: [...prev, ?cur]),
      transitionBuilder: (w, a) {
        final entering = w.key == ValueKey(text);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: Offset(0, entering ? 0.45 : -0.45), end: Offset.zero).animate(a),
            child: w,
          ),
        );
      },
      child: Text(text,
          key: ValueKey(text),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textDirection: textDirection,
          style: style),
    );
  }
}

/// Collapsible body: height tween + fade, smooth open, quicker close.
class DCollapse extends StatelessWidget {
  const DCollapse({super.key, required this.open, required this.child});
  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: open ? D.tIn : D.tOut,
      curve: open ? D.ease : D.easeIn,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: open ? D.tIn : D.tOut,
        curve: open ? D.ease : D.easeIn,
        child: open ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// Segmented control whose highlight pill slides between options.
class DSegmented extends StatelessWidget {
  const DSegmented({super.key, required this.options, required this.labels, required this.value, required this.onChanged});
  final List<String> options;
  final List<String> labels;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final idx = options.indexOf(value);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: D.bg, borderRadius: BorderRadius.circular(D.rPill)),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: D.spring,
              left: (idx < 0 ? 0 : idx) * w,
              top: 0,
              bottom: 0,
              width: w,
              child: AnimatedOpacity(
                opacity: idx < 0 ? 0 : 1,
                duration: D.tIn,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: D.accent,
                    borderRadius: BorderRadius.circular(D.rPill),
                    boxShadow: D.soft,
                  ),
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < options.length; i++)
                Expanded(
                  child: DPress(
                    onTap: () => onChanged(options[i]),
                    scale: 0.92,
                    haptic: Hx.select,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(options[i]),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: D.tIn,
                          curve: D.ease,
                          style: txt(12,
                              color: i == idx ? Colors.white : D.muted,
                              weight: i == idx ? FontWeight.w700 : FontWeight.w500),
                          child: Text(labels[i], maxLines: 1),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

/// Live background work for the open session, shown above the composer:
/// `terminal(background=true)` processes, delegated subagents and `/background`
/// side agents. Collapsed to a one-line summary until the user opens it, so a
/// long job stays visible without stealing the transcript.
class BackgroundStrip extends StatefulWidget {
  const BackgroundStrip({
    super.key,
    required this.items,
    required this.onStop,
    required this.onDismiss,
  });

  final List<BackgroundActivity> items;
  final Future<void> Function(String id) onStop;
  final void Function(String id) onDismiss;

  @override
  State<BackgroundStrip> createState() => _BackgroundStripState();
}

class _BackgroundStripState extends State<BackgroundStrip> {
  bool open = false;
  final detail = <String>{};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final live = items.where((i) => i.running).length;
    return DCard(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      pad: EdgeInsets.zero,
      radius: D.rMd,
      border: D.borderSoft,
      shadow: D.soft,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DPress(
          scale: 0.985,
          child: InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            child: Row(children: [
              if (live > 0)
                const _Pulse()
              else
                ic(tb.ActivityHeartbeat.new, size: 15, color: D.ok),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'النشاط في الخلفية (${items.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: txt(12.5, weight: FontWeight.w600),
                ),
              ),
              if (live > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('$live قيد التشغيل', style: txt(11.5, color: D.accent)),
                ),
              const SizedBox(width: 4),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: D.tIn,
                  curve: D.ease,
                  child: ic(tb.ChevronDown.new, size: 16),
                ),
              ]),
            ),
          ),
        ),
        DCollapse(
          open: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(children: [
              for (final item in items)
                _BackgroundRow(
                  item: item,
                  open: detail.contains(item.id),
                  onToggle: () => setState(
                    () => detail.contains(item.id) ? detail.remove(item.id) : detail.add(item.id),
                  ),
                  onStop: () => widget.onStop(item.id),
                  onDismiss: () => widget.onDismiss(item.id),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({
    required this.item,
    required this.open,
    required this.onToggle,
    required this.onStop,
    required this.onDismiss,
  });

  final BackgroundActivity item;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final VoidCallback onDismiss;

  String get _status => switch (item.state) {
        BackgroundState.running => item.kind == 'subagent' ? 'يعمل الآن' : 'قيد التشغيل',
        BackgroundState.done => 'انتهى',
        BackgroundState.failed => item.exitCode == null ? 'فشل' : 'فشل (رمز ${item.exitCode})',
      };

  Color get _tone => switch (item.state) {
        BackgroundState.running => D.accent,
        BackgroundState.done => D.ok,
        BackgroundState.failed => D.danger,
      };

  IconCtor get _icon => switch (item.kind) {
        'subagent' => tb.BinaryTree.new,
        'agent' => tb.Robot.new,
        _ => tb.Terminal2.new,
      };

  String get _meta => [
        _status,
        if (item.subtitle.isNotEmpty && item.running) item.subtitle,
        if (item.model != null && item.model!.isNotEmpty) item.model!,
        if (item.toolCount != null && item.toolCount! > 0) 'أدوات: ${item.toolCount}',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final hasDetail = item.detail.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        decoration: BoxDecoration(
          color: D.surfaceHi.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(D.rSm),
        ),
        child: Column(children: [
          DPress(
            scale: 0.99,
            child: InkWell(
              onTap: hasDetail ? onToggle : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(children: [
                ic(_icon, size: 15, color: _tone),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dDirOf(item.title),
                      style: txt(12.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dDirOf(_meta),
                      style: txt(11, color: item.state == BackgroundState.failed ? D.danger : D.muted),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                if (item.running)
                  DIconBtn(
                    icon: tb.PlayerStop.new,
                    size: 30,
                    tooltip: 'إيقاف',
                    tint: D.danger,
                    onPressed: onStop,
                  )
                else
                  DIconBtn(
                    icon: tb.X.new,
                    size: 30,
                    tooltip: 'تجاهل',
                    onPressed: onDismiss,
                  ),
                ]),
              ),
            ),
          ),
          DCollapse(
            open: open && hasDetail,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: D.bg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(D.rSm),
                  border: Border.all(color: D.borderSoft),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    item.detail.trim(),
                    textDirection: dDirOf(item.detail),
                    style: txt(11.5, color: D.muted, height: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Small breathing dot: a running background job still reads as alive when the
/// transcript itself is idle.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: const BoxDecoration(color: D.accent, shape: BoxShape.circle),
      ),
    );
  }
}
