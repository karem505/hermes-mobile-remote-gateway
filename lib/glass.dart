import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'design.dart';

/// Liquid Glass layer of the design system.
///
/// Glass is reserved for the control layer that floats over content (top bar,
/// composer, sheets, dialogs, drawer, menus, toasts). Content itself (message
/// bubbles, code, rows inside a list) stays solid and readable. Every glass
/// surface is tinted with the existing warm tokens, so the palette is the same
/// as the solid design; glass only adds depth, refraction and motion.
class G {
  /// How strongly a surface keeps its warm body colour. Higher reads calmer
  /// and keeps text legible; lower lets more of the backdrop through.
  static const double chromeTint = 0.62; // bars that sit over the transcript
  static const double panelTint = 0.80; // drawer, dialogs, sheets (dense text)
  static const double cardTint = 0.70; // floating cards (queue, approvals)

  static LiquidGlassSettings surface({double tint = chromeTint, Color body = D.surface, double thickness = 22}) =>
      LiquidGlassSettings(
        glassColor: body.withValues(alpha: tint),
        thickness: thickness,
        blur: 12,
        saturation: 1.25,
        lightIntensity: 0.55,
        lightAngle: 0.8,
        ambientStrength: 0.12,
        chromaticAberration: 0.006,
        refractiveIndex: 1.18,
        glowIntensity: 0.6,
      );

  /// Raised controls (round buttons, chips) when they float on their own.
  static LiquidGlassSettings control({Color body = D.surfaceHi, double tint = 0.55}) =>
      surface(tint: tint, body: body, thickness: 18);

  /// Coral primary action (send, confirm): accent body, a touch more opaque so
  /// the brand colour reads exactly as before.
  static LiquidGlassSettings accent({Color body = D.accent}) =>
      surface(tint: 0.88, body: body, thickness: 20);

  static GlassThemeData theme() => GlassThemeData.simple(
        blur: 12,
        thickness: 22,
        quality: GlassQuality.standard,
        saturation: 1.25,
        lightIntensity: 0.55,
      );
}

/// Where a control is rendered, so it picks the right glass mode:
/// - [GlassLevel.none]: on the plain page, it becomes its own glass drop.
/// - [GlassLevel.layer]: siblings share one liquid layer (they blend together
///   when they move close, like the top bar buttons).
/// - [GlassLevel.surface]: already sitting on a glass surface. Glass inside
///   glass is an anti-pattern, so it renders flat with the glass physics only.
enum GlassLevel { none, layer, surface }

class GlassScopeInfo extends InheritedWidget {
  const GlassScopeInfo({super.key, required this.level, required super.child});
  final GlassLevel level;

  static GlassLevel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScopeInfo>()?.level ?? GlassLevel.none;

  @override
  bool updateShouldNotify(GlassScopeInfo old) => old.level != level;
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
    this.width,
    this.height,
    this.hairline = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry pad;
  final EdgeInsetsGeometry margin;
  final double tint;
  final Color body;
  final bool premium;
  final double? width;
  final double? height;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final level = GlassScopeInfo.of(context);
    final inner = GlassScopeInfo(level: GlassLevel.surface, child: Padding(padding: pad, child: child));
    // Nested glass renders as a quiet raised fill instead of a second lens.
    if (level == GlassLevel.surface) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: D.surfaceHi.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(radius),
          border: hairline ? Border.all(color: D.borderSoft) : null,
        ),
        child: inner,
      );
    }
    final shape = LiquidRoundedSuperellipse(
      borderRadius: radius,
      side: hairline ? const BorderSide(color: D.hairline, width: 0.8) : BorderSide.none,
    );
    return Padding(
      padding: margin,
      child: GlassContainer(
        width: width,
        height: height,
        shape: shape,
        useOwnLayer: level != GlassLevel.layer,
        settings: level == GlassLevel.layer ? null : G.surface(tint: tint, body: body),
        quality: premium ? GlassQuality.premium : GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: inner,
      ),
    );
  }
}

/// Several glass controls that share one liquid layer, so they refract the
/// same backdrop and blend into each other when they come close.
class DGlassGroup extends StatelessWidget {
  const DGlassGroup({super.key, required this.child, this.tint = G.chromeTint, this.premium = true});
  final Widget child;
  final double tint;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    if (GlassScopeInfo.of(context) == GlassLevel.surface) return child;
    return AdaptiveLiquidGlassLayer(
      settings: G.surface(tint: tint),
      quality: premium ? GlassQuality.premium : GlassQuality.standard,
      child: GlassScopeInfo(level: GlassLevel.layer, child: child),
    );
  }
}

/// Warm ambient backdrop. Glass needs something to refract: a faint coral glow
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

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

/// Glass entrance/exit for a surface that appears in place: the glass settles
/// in from slightly oversized while its content sharpens (iOS 26 materialize).
Widget glassSwitch(Widget child, Animation<double> a) => GlassMaterializeTransition(
      animation: a,
      scaleFrom: 1.06,
      contentSigma: 6,
      child: child,
    );
