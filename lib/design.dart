import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tb;

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'background.dart';
import 'glass.dart';

/// Design tokens: a warm, Claude-Code-flavoured dark surface with soft depth.
class D {
  // Surface ladder: each step is one even notch brighter, so layering reads
  // as depth without heavy borders or shadows.
  static const bg = Color(0xFF141210);
  static const surface = Color(0xFF1C1917);
  static const surfaceHi = Color(0xFF262220);
  static const surfaceTop = Color(0xFF312C29);
  static const border = Color(0xFF3A3431);
  // Hairlines are translucent warm white: always a touch lighter than
  // whatever they sit on, so one token works on bg, cards and chips.
  static const borderSoft = Color(0x14F3EEEA);
  static const hairline = Color(0x1FF3EEEA);
  static const fg = Color(0xFFF3EEEA);
  static const muted = Color(0xFFA49D96);
  static const faint = Color(0xFF7A726C); // tertiary: section labels, counts, timestamps
  static const onAccent = Color(0xFFFFF7F3);
  static const accent = Color(0xFFD97757);
  static const accentDim = Color(0xFF9A5540);
  static const accentWash = Color(0xFF2E211C);
  static const ok = Color(0xFF8FAE84);
  static const danger = Color(0xFFC8564B);
  static const info = Color(0xFFB9A48A); // waiting / queued: warm, not alarming

  /// Your own messages: a quiet raised fill, so coral stays reserved for
  /// actions (send, selected, live) instead of every line you typed.
  static const bubble = Color(0xFF282422);
  static const rail = Color(0xFF3A3431);

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
    BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const lift = [
    BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, 14)),
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

/// Flat control with liquid press physics: the jelly stretch, touch glow and
/// spring of a glass button, without a second lens. Used for every control
/// that already sits on a glass surface (glass inside glass is avoided).
Widget dGlassTap({
  required Widget child,
  required VoidCallback? onTap,
  required ShapeBorder clip,
  LiquidShape shape = const LiquidOval(),
  Hx haptic = Hx.light,
  String label = '',
  double? width,
  double? height,
  double press = 0.95,
}) {
  return GlassButton.custom(
    onTap: onTap == null
        ? () {}
        : () {
            H.fire(haptic);
            onTap();
          },
    enabled: onTap != null,
    style: GlassButtonStyle.transparent,
    shape: shape,
    width: width,
    height: height,
    label: label,
    interactionScale: press,
    stretch: 0.35,
    child: label.isEmpty ? child : ExcludeSemantics(child: child),
  );
}

LiquidShape _pill(double h) => LiquidRoundedSuperellipse(borderRadius: h / 2);

/// Rounded elevated surface: the one container used by every card-like surface.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.color = D.surface,
    this.radius = D.rMd,
    this.shadow = const [],
    this.border = D.borderSoft,
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
    final level = GlassScopeInfo.of(context);
    final fg = !enabled
        ? D.faint
        : switch (kind) {
            DBtnKind.fill => D.onAccent,
            DBtnKind.outline => D.fg,
            DBtnKind.ghost => D.muted,
            DBtnKind.danger => D.onAccent,
          };
    final h = dense ? 32.0 : 44.0;
    final hx = haptic ?? (kind == DBtnKind.fill ? Hx.medium : Hx.light);
    final content = Container(
      constraints: BoxConstraints(minHeight: h),
      padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18, vertical: dense ? 6 : 10),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ic(icon!, size: dense ? 14 : 16, color: fg),
        if (icon != null) const SizedBox(width: 6),
        Flexible(child: Text(label, textAlign: TextAlign.center, style: txt(dense ? 12.5 : 14, color: fg, weight: FontWeight.w600))),
      ]),
    );
    return LayoutBuilder(builder: (context, box) {
      final w = box.hasTightWidth ? box.maxWidth : null;
      // On the page: the button is its own drop of glass (coral for the
      // primary action, warm smoke for the rest).
      if (level == GlassLevel.none && kind != DBtnKind.ghost) {
        return GlassButton.custom(
          onTap: enabled
              ? () {
                  H.fire(hx);
                  onPressed!();
                }
              : () {},
          enabled: enabled,
          useOwnLayer: true,
          width: w,
          shape: _pill(h),
          label: label,
          settings: !enabled
              ? G.control()
              : switch (kind) {
                  DBtnKind.fill => G.accent(),
                  DBtnKind.danger => G.accent(body: D.danger),
                  _ => G.control(),
                },
          child: ExcludeSemantics(child: content),
        );
      }
      // On a glass surface: a solid fill with liquid press physics.
      return dGlassTap(
        onTap: onPressed,
        haptic: hx,
        width: w,
        label: label,
        shape: _pill(h),
        clip: const StadiumBorder(),
        child: AnimatedContainer(
          duration: D.tIn,
          curve: D.ease,
          width: w,
          decoration: BoxDecoration(
            color: switch (kind) {
              DBtnKind.fill => enabled ? D.accent : D.surfaceHi,
              DBtnKind.outline => D.surfaceHi.withValues(alpha: 0.7),
              DBtnKind.ghost => Colors.transparent,
              DBtnKind.danger => enabled ? D.danger : D.surfaceHi,
            },
            borderRadius: BorderRadius.circular(D.rPill),
            border: kind == DBtnKind.outline ? Border.all(color: D.hairline) : null,
          ),
          child: content,
        ),
      );
    });
  }
}

enum DBtnKind { fill, outline, ghost, danger }

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
    final level = GlassScopeInfo.of(context);
    final enabled = onPressed != null;
    final fg = primary ? D.onAccent : (active ? D.accent : (tint ?? D.fg));
    final hx = haptic ?? (primary ? Hx.medium : Hx.light);
    final glyph = Center(
      child: DSwap(
        id: '${icon.hashCode}-$enabled',
        child: ic(icon, size: size * 0.45, color: enabled ? fg : D.faint),
      ),
    );
    final label = tooltip ?? '';
    Widget b;
    if (level == GlassLevel.surface || (level == GlassLevel.layer && primary)) {
      // On a glass surface: solid disc, liquid physics.
      final bg = primary
          ? (active ? D.danger : D.accent)
          : (active ? D.accentWash : D.surfaceHi.withValues(alpha: 0.72));
      b = dGlassTap(
        onTap: onPressed,
        haptic: hx,
        width: size,
        height: size,
        label: label,
        clip: const CircleBorder(),
        child: AnimatedContainer(
          duration: D.tIn,
          curve: D.ease,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: enabled ? bg : D.surfaceHi.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: glyph,
        ),
      );
    } else {
      // On the page (own drop) or in a shared layer (blends with siblings).
      b = GlassButton.custom(
        onTap: enabled
            ? () {
                H.fire(hx);
                onPressed!();
              }
            : () {},
        enabled: enabled,
        width: size,
        height: size,
        label: label,
        useOwnLayer: level == GlassLevel.none,
        settings: level == GlassLevel.none
            ? (primary
                ? G.accent(body: active ? D.danger : D.accent)
                : G.control(body: active ? D.accentWash : D.surfaceHi))
            : null,
        child: glyph,
      );
    }
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
    return dGlassTap(
      onTap: onTap,
      haptic: Hx.select,
      shape: _pill(32),
      clip: const StadiumBorder(),
      child: AnimatedContainer(
        duration: D.tIn,
        curve: D.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? D.accentWash : D.surfaceHi.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(D.rPill),
          border: Border.all(color: active ? D.accentDim.withValues(alpha: 0.6) : D.hairline),
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
    );
  }
}

/// Text field surface: rounded, soft-shadowed, no harsh border.
class DInput extends StatelessWidget {
  const DInput({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  });

  final Widget child;
  final EdgeInsets pad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: pad,
      constraints: const BoxConstraints(minHeight: 44),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: D.bg.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.hairline),
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
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
      child: Row(children: [
        Expanded(
          child: Text(title, style: txt(12, color: D.faint, weight: FontWeight.w600, height: 1.3)),
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
        child: DGlass(
          radius: 28,
          premium: true,
          tint: G.panelTint,
          pad: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _noticeColor(kind).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(child: ic(_noticeIcon(kind), size: 19, color: _noticeColor(kind))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Semantics(namesRoute: true, header: true,
                child: Text(title, style: txt(17, weight: FontWeight.w700, height: 1.35)))),
              DIconBtn(icon: tb.X.new, size: 36, tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).maybePop()),
            ]),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(
              child: SelectableText(body, style: txt(13.5, color: D.muted, height: 1.65)))),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              // Stacked, full width, decision first: long Arabic labels never
              // wrap mid-button and there is no left/right ambiguity in RTL.
              for (final (i, a) in actions.reversed.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: a),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

/// Non-blocking feedback, used by copy, uploads, configuration and errors.
class DFeedback {
  static VoidCallback? _dismiss;

  static void show(BuildContext context, String message, {DNoticeKind? kind}) {
    final tone = kind ?? (message.startsWith('تعذر') || message.startsWith('فشل')
        ? DNoticeKind.error : message.startsWith('تم ') ? DNoticeKind.success : DNoticeKind.info);
    _dismiss?.call();
    _dismiss = null;
    // A floating glass toast at the top, clear of the composer and keyboard.
    try {
      _dismiss = GlassToast.show(
        context,
        message: message,
        icon: ic(_noticeIcon(tone), size: 18, color: _noticeColor(tone)),
        type: switch (tone) {
          DNoticeKind.error => GlassToastType.error,
          DNoticeKind.success => GlassToastType.success,
          _ => GlassToastType.info,
        },
        position: GlassToastPosition.top,
        duration: Duration(seconds: tone == DNoticeKind.error ? 7 : 3),
        settings: G.surface(tint: G.panelTint, body: D.surfaceTop),
      );
    } catch (_) {
      // No overlay (e.g. called during teardown): nothing to show.
    }
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
        // Glass cannot be faded (its backdrop pass renders fully or not at
        // all), so surfaces materialize: they settle in from slightly
        // oversized while the content sharpens, and dissolve on the way out.
        transitionBuilder: (w, a) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(a),
          child: GlassMaterializeTransition(
            animation: a,
            alignment: alignment,
            scaleFrom: 1.05,
            contentSigma: 6,
            child: w,
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

/// Fenced code in an answer: a header with the language and a copy action,
/// then the code, always LTR and horizontally scrollable so long lines never
/// wrap mid-token.
class DCodeBlock extends StatelessWidget {
  const DCodeBlock({super.key, required this.language, required this.code, required this.onCopy});
  final String language;
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final lang = language.trim().isEmpty ? 'code' : language.trim();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF100E0D),
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 4, 2),
            decoration: const BoxDecoration(
              color: D.surface,
              border: Border(bottom: BorderSide(color: D.borderSoft)),
            ),
            child: Row(children: [
              Expanded(child: Text(lang, style: txt(11.5, color: D.faint, weight: FontWeight.w600, height: 1.2))),
              Tooltip(
                message: 'نسخ',
                child: DPress(
                  onTap: onCopy,
                  haptic: Hx.select,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCopy,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ic(tb.Copy.new, size: 14, color: D.muted),
                        const SizedBox(width: 5),
                        Text('Copy', style: txt(11.5, color: D.muted, weight: FontWeight.w500, height: 1.2)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SelectableText(
              code.trimRight(),
              style: txt(12.5, color: D.fg, height: 1.55).copyWith(fontFamily: 'monospace'),
            ),
          ),
        ]),
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
    final none = idx < 0; // server default: no level highlighted
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GlassSegmentedControl(
        segments: [for (final l in labels) GlassSegment(label: l)],
        selectedIndex: none ? 0 : idx,
        onSegmentSelected: (i) {
          H.fire(Hx.select);
          onChanged(options[i]);
        },
        height: 42,
        useOwnLayer: true,
        backgroundColor: D.bg.withValues(alpha: 0.55),
        indicatorColor: none ? Colors.transparent : D.surfaceTop.withValues(alpha: 0.9),
        settings: G.control(body: D.bg, tint: 0.5),
        glowColor: D.accent.withValues(alpha: 0.25),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        selectedTextStyle: txt(12.5, color: none ? D.muted : D.fg, weight: none ? FontWeight.w500 : FontWeight.w700),
        unselectedTextStyle: txt(12.5, color: D.muted, weight: FontWeight.w500),
      ),
    );
  }
}

/// Live background work for the open session, shown above the composer:
/// `terminal(background=true)` processes, delegated subagents and `/background`
/// side agents. Collapsed to a one-line summary until the user opens it, so a
/// long job stays visible without stealing the transcript.
/// One line of agent work inside the transcript: a tool call, a thinking block
/// or a background job. Leading icon, label, quiet detail, trailing state.
/// Tapping expands the body when there is one; the row never becomes a card.
class DStepRow extends StatelessWidget {
  const DStepRow({
    super.key,
    required this.icon,
    required this.label,
    this.detail = '',
    this.trailing,
    this.open = false,
    this.onTap,
    this.body,
    this.tone = D.muted,
    this.labelDirection,
  });

  final IconCtor icon;
  final String label;
  final String detail;
  final Widget? trailing;
  final bool open;
  final VoidCallback? onTap;
  final Widget? body;
  final Color tone;
  final TextDirection? labelDirection;

  @override
  Widget build(BuildContext context) {
    final expandable = body != null && onTap != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(D.rSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(D.rSm),
          onTap: onTap == null
              ? null
              : () {
                  H.fire(Hx.select);
                  onTap!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(children: [
                ic(icon, size: 15, color: tone),
                const SizedBox(width: 9),
                Flexible(
                  flex: 0,
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: labelDirection ?? dDirOf(label),
                      style: txt(12.5, color: D.fg, weight: FontWeight.w500)),
                ),
                if (detail.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: detail.isEmpty
                      ? const SizedBox.shrink()
                      : Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dDirOf(detail),
                          style: txt(12, color: D.muted)),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                if (expandable) ...[
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: open ? D.tIn : D.tOut,
                    curve: open ? D.ease : D.easeIn,
                    child: ic(tb.ChevronDown.new, size: 14),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
      if (body != null)
        DCollapse(
          open: open,
          child: Container(
            margin: const EdgeInsetsDirectional.only(start: 9, top: 2, bottom: 6),
            padding: const EdgeInsetsDirectional.only(start: 14),
            decoration: const BoxDecoration(
              border: BorderDirectional(start: BorderSide(color: D.rail, width: 1)),
            ),
            child: body,
          ),
        ),
    ]);
  }
}

/// Seconds since [from], refreshed every second while mounted: the live
/// counter on a running step.
class DElapsed extends StatefulWidget {
  const DElapsed({super.key, required this.from, this.style});
  final DateTime from;
  final TextStyle? style;
  @override
  State<DElapsed> createState() => _DElapsedState();
}

class _DElapsedState extends State<DElapsed> {
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DateTime.now().difference(widget.from).inSeconds;
    return Text(dSeconds(s), textDirection: TextDirection.ltr, style: widget.style ?? txt(11, color: D.muted));
  }
}

/// Compact duration, always Latin digits: 8s, 1m 04s.
String dSeconds(num s) {
  final n = s.round();
  if (n < 60) return '${n}s';
  return '${n ~/ 60}m ${(n % 60).toString().padLeft(2, '0')}s';
}

/// Quiet row of icon actions under an assistant reply (copy, and more later).
class DActionRow extends StatelessWidget {
  const DActionRow({super.key, required this.actions, this.textDirection});
  final List<(IconCtor, String, VoidCallback)> actions;
  /// Follows the reply it belongs to, so the actions sit under the text's
  /// starting edge (left for an English answer, right for Arabic).
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final row = Transform.translate(
      offset: const Offset(0, -6),
      child: Row(children: [
        for (final (icon, label, onTap) in actions)
          Tooltip(
            message: label,
            child: dGlassTap(
              onTap: onTap,
              label: label,
              width: 40,
              height: 40,
              clip: const CircleBorder(),
              child: SizedBox(width: 40, height: 40, child: Center(child: ic(icon, size: 16, color: D.faint))),
            ),
          ),
      ]),
    );
    return textDirection == null ? row : Directionality(textDirection: textDirection!, child: row);
  }
}

/// Short model name for chips and rows: drops the vendor prefix and a trailing
/// date stamp. The full identifier stays visible in the picker's second line.
String dModelShort(String id) {
  var s = id.contains('/') ? id.split('/').last : id;
  s = s.replaceFirst(RegExp(r'[-_]?(20\d{6}|\d{6,8})$'), '');
  return s.isEmpty ? id : s;
}

/// The one composer control for the model and its Thinking level:
/// "deepseek-v4-1-flash · Max". English, LTR, opens the model sheet.
class DModelChip extends StatelessWidget {
  const DModelChip({super.key, required this.model, required this.effort, this.onTap});
  final String model;
  final String effort;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = model.isEmpty ? 'Model' : dModelShort(model);
    return dGlassTap(
      onTap: onTap,
      haptic: Hx.select,
      shape: _pill(40),
      clip: const StadiumBorder(),
      child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: D.surfaceHi.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(D.rPill),
              border: Border.all(color: D.hairline),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              // Wide: one line "name · level". Narrow (most phones once attach,
              // commands, voice and send take their share): name over level.
              // Very narrow (steer controls showing, large text): level only.
              child: LayoutBuilder(builder: (context, box) {
                final brain = ic(tb.Brain.new, size: 13, color: effort == 'Default' ? D.muted : D.accent);
                final level = Text(effort,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: txt(12.5, color: D.muted, weight: FontWeight.w500, height: 1.2));
                if (box.maxWidth >= 230) {
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: txt(12.5, weight: FontWeight.w600, height: 1.2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('·', style: txt(12.5, color: D.muted, height: 1.2)),
                    ),
                    brain,
                    const SizedBox(width: 4),
                    level,
                    const SizedBox(width: 2),
                    ic(tb.ChevronDown.new, size: 13),
                  ]);
                }
                if (box.maxWidth >= 96) {
                  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: txt(12, weight: FontWeight.w600, height: 1.15)),
                    const SizedBox(height: 1),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ic(tb.Brain.new, size: 11, color: effort == 'Default' ? D.muted : D.accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(effort,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: txt(10.5, color: D.muted, weight: FontWeight.w500, height: 1.15)),
                      ),
                    ]),
                  ]);
                }
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  brain,
                  const SizedBox(width: 4),
                  Flexible(child: level),
                ]);
              }),
            ),
          ),
    );
  }
}

/// Suggestion chip on the empty state: tapping fills the composer, never sends.
class DSuggestion extends StatelessWidget {
  const DSuggestion({super.key, required this.icon, required this.label, required this.onTap});
  final IconCtor icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Floats on the empty page: each suggestion is its own drop of glass.
    return GlassButton.custom(
      onTap: () {
        H.fire(Hx.select);
        onTap();
      },
      useOwnLayer: true,
      label: label,
      shape: const LiquidRoundedSuperellipse(borderRadius: D.rLg),
      settings: G.control(tint: 0.5),
      alignment: AlignmentDirectional.centerStart.resolve(Directionality.of(context)),
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ic(icon, size: 16, color: D.accent),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: txt(13.5, height: 1.35))),
          ]),
        ),
      ),
    );
  }
}

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
    return DGlass(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      radius: D.rLg,
      tint: G.cardTint,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DPress(
          scale: 0.985,
          child: InkWell(
            borderRadius: BorderRadius.circular(D.rLg),
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
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Text('$live قيد التشغيل', style: txt(11.5, color: D.accent)),
                )
              else if (items.any((i) => i.state == BackgroundState.failed))
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Text('يوجد فشل', style: txt(11.5, color: D.danger)),
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

  /// Leading state glyph: spinner while running, check when done, x on failure.
  Widget get _glyph => switch (item.state) {
        BackgroundState.running => const SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: D.accent)),
        BackgroundState.done => ic(tb.CircleCheck.new, size: 16, color: D.ok),
        BackgroundState.failed => ic(tb.CircleX.new, size: 16, color: D.danger),
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
          color: D.surfaceHi.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(D.rSm),
        ),
        child: Column(children: [
          DPress(
            scale: 0.99,
            child: InkWell(
              borderRadius: BorderRadius.circular(D.rSm),
              onTap: hasDetail ? onToggle : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
              child: Row(children: [
                SizedBox(width: 18, child: Center(child: _glyph)),
                const SizedBox(width: 10),
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
                    Row(children: [
                      ic(_icon, size: 12, color: _tone),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dDirOf(_meta),
                          style: txt(11, color: item.state == BackgroundState.failed ? D.danger : D.muted),
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(width: 6),
                if (item.running)
                  DIconBtn(
                    icon: tb.PlayerStop.new,
                    size: 36,
                    tooltip: 'إيقاف',
                    tint: D.danger,
                    onPressed: onStop,
                  )
                else
                  DIconBtn(
                    icon: tb.X.new,
                    size: 36,
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
