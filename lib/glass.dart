import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'design.dart';

/// Liquid Glass layer of the design system, tuned for mid-range Android GPUs.
///
/// Glass is reserved for the control layer that floats over content (top bar,
/// composer, cards over the transcript, drawer, sheets, dialogs). Content
/// stays solid. Every surface is tinted with the existing warm tokens, so the
/// palette is unchanged.
///
/// Rendering budget (120 Hz leaves ~8 ms per frame):
/// - Bars and cards over the transcript: one shared, grouped backdrop blur
///   (`BackdropGroup` reads the backdrop once for all of them) plus a static
///   specular rim. No refraction shader per surface.
/// - Large panels (drawer, sheet, dialog): no live blur; a dense warm tint and
///   the same rim. A full-screen blur re-renders on every animation frame.
/// - Controls on glass: no backdrop of their own, only tint and spring physics.
class G {
  static const double chromeTint = 0.66; // bars over the transcript (blurred)
  static const double panelTint = 0.95; // drawer, dialogs, sheets (no blur)
  static const double cardTint = 0.74; // floating cards (blurred)

  static const double blurSigma = 14;
}

/// Where a control is rendered, so it picks the right glass treatment.
/// - [GlassLevel.none]: on the plain page.
/// - [GlassLevel.layer]: kept for compatibility (treated like none).
/// - [GlassLevel.surface]: already on a glass surface; renders flat.
enum GlassLevel { none, layer, surface }

class GlassScopeInfo extends InheritedWidget {
  const GlassScopeInfo({super.key, required this.level, required super.child});
  final GlassLevel level;

  static GlassLevel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScopeInfo>()?.level ?? GlassLevel.none;

  @override
  bool updateShouldNotify(GlassScopeInfo old) => old.level != level;
}

/// Shares one backdrop read between every blurred glass surface below it.
class DGlassRoot extends StatelessWidget {
  const DGlassRoot({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(child: child);
}

/// A floating glass surface: the one container used by every glass panel.
class DGlass extends StatelessWidget {
  const DGlass({
    super.key,
    required this.child,
    this.radius = D.rLg,
    this.pad = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.tint = G.chromeTint,
    this.body = D.surface,
    this.premium = false,
    this.panel = false,
    this.width,
    this.height,
    this.hairline = true,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry pad;
  final EdgeInsetsGeometry margin;
  final double tint;
  final Color body;

  /// Kept for call-site compatibility; no extra cost.
  final bool premium;

  /// Large surface (drawer, sheet, dialog, page card): no live blur.
  final bool panel;
  final double? width;
  final double? height;
  final bool hairline;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final level = GlassScopeInfo.of(context);
    final inner = GlassScopeInfo(level: GlassLevel.surface, child: Padding(padding: pad, child: child));
    final r = BorderRadius.circular(radius);
    // Nested glass renders as a quiet raised fill instead of a second lens.
    if (level == GlassLevel.surface) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: D.surfaceHi.withValues(alpha: 0.55),
          borderRadius: r,
          border: hairline ? Border.all(color: D.borderSoft) : null,
        ),
        child: inner,
      );
    }
    final a = panel ? G.panelTint : tint;
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        // Lit from the top: a touch brighter at the top edge, settling into
        // the body colour, so the surface reads as a curved pane.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(body, D.surfaceTop, 0.55)!.withValues(alpha: a),
            body.withValues(alpha: a),
          ],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: hairline ? _Rim(radius) : null,
        child: inner,
      ),
    );
    if (!panel) {
      surface = ClipRRect(
        borderRadius: r,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: G.blurSigma, sigmaY: G.blurSigma, tileMode: TileMode.mirror),
          child: surface,
        ),
      );
    }
    return Padding(
      padding: margin,
      child: Container(
        width: width,
        height: height,
        decoration: shadow
            ? BoxDecoration(borderRadius: r, boxShadow: const [
                BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 6)),
              ])
            : null,
        child: surface,
      ),
    );
  }
}

/// Specular rim: a bright hairline on the lit top edge fading to a faint one
/// at the bottom, plus a soft inner highlight band. Static paint, no shader.
class _Rim extends CustomPainter {
  const _Rim(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rad = radius.clamp(0.0, size.shortestSide / 2);
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(rad));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x40FFF3EA), Color(0x0FFFF3EA), Color(0x1AFFF3EA)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    final band = Rect.fromLTWH(0, 0, size.width, (size.height * 0.45).clamp(0.0, 36.0));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x10FFFFFF), Color(0x00FFFFFF)],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius;
}

/// Kept for compatibility: its children simply render as regular glass.
class DGlassGroup extends StatelessWidget {
  const DGlassGroup({super.key, required this.child, this.tint = G.chromeTint, this.premium = false});
  final Widget child;
  final double tint;
  final bool premium;

  @override
  Widget build(BuildContext context) => child;
}

/// Glass body for a control that floats on the page by itself: tint, rim and
/// shadow, no backdrop read of its own.
class DGlassPill extends StatelessWidget {
  const DGlassPill({
    super.key,
    required this.child,
    this.radius = D.rPill,
    this.body = D.surfaceHi,
    this.tint = 0.8,
    this.width,
    this.height,
  });
  final Widget child;
  final double radius;
  final Color body;
  final double tint;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(body, Colors.white, 0.10)!.withValues(alpha: tint),
            body.withValues(alpha: tint),
          ],
        ),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: CustomPaint(foregroundPainter: _Rim(radius), child: child),
    );
  }
}

/// Warm ambient backdrop. Glass needs something to show: a faint coral glow
/// near the top and a sand glow near the bottom, on the same dark base colour.
class DAmbient extends StatelessWidget {
  const DAmbient({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _AmbientPainter()))),
      child,
    ]);
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = D.bg);
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(
            Rect.fromCircle(center: c, radius: r),
          ),
      );
    }

    final w = size.width, h = size.height;
    glow(Offset(w * 0.92, h * 0.04), w * 0.95, D.accent.withValues(alpha: 0.13));
    glow(Offset(w * 0.05, h * 0.58), w * 0.80, D.info.withValues(alpha: 0.06));
    glow(Offset(w * 0.70, h * 1.02), w * 0.90, D.accentDim.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reports the laid-out size of [child] after each layout pass. Used to pad
/// the transcript by the height of the glass bars floating over it.
class DMeasure extends SingleChildRenderObjectWidget {
  const DMeasure({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMeasure).onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last || _scheduled) return;
    // One callback per frame at most, carrying the latest size.
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize || size == _last) return;
      _last = size;
      onSize(size);
    });
  }
}

/// Glass entrance/exit: settles in from slightly oversized while fading up,
/// dissolves on the way out. Transforms and opacity only, so it is cheap.
Widget dMaterialize(Animation<double> a, Widget child,
    {Alignment alignment = Alignment.center, double scaleFrom = 1.04}) {
  return FadeTransition(
    opacity: a,
    child: ScaleTransition(
      alignment: alignment,
      scale: Tween(begin: scaleFrom, end: 1.0).animate(a),
      child: child,
    ),
  );
}

Widget glassSwitch(Widget child, Animation<double> a) => dMaterialize(a, child);
