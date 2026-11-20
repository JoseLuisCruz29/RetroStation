import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../controllers/touch_layout.dart';
import '../../emulation/native_bindings.dart';

/// Controles táctiles multitáctiles. Cada dedo puede deslizarse entre botones
/// (p. ej. de B a A, o girar en la cruceta) y la máscara se recalcula siempre.
class TouchControls extends StatefulWidget {
  const TouchControls({
    super.key,
    required this.consoleId,
    required this.landscape,
    required this.opacity,
    required this.scale,
    required this.haptics,
    required this.onMaskChanged,
    this.onAnalogChanged,
    this.gutter,
    this.overrides = const {},
  });

  /// Personalización del usuario (editor de controles).
  final Map<String, ControlOverride> overrides;

  final String consoleId;
  final bool landscape;

  /// Ancho de las franjas laterales en horizontal.
  final double? gutter;
  final double opacity;
  final double scale;
  final bool haptics;
  final ValueChanged<int> onMaskChanged;

  /// Joystick analógico (PSP): vector -1..1 con y hacia abajo.
  final ValueChanged<Offset>? onAnalogChanged;

  @override
  State<TouchControls> createState() => _TouchControlsState();
}

class _TouchControlsState extends State<TouchControls> {
  final _pointers = <int, Offset>{};
  List<ControlRegion> _regions = const [];
  int _mask = 0;
  Offset _analog = Offset.zero;

  /// Dedo que empezó en el joystick: lo controla hasta que se levanta, aunque
  /// se arrastre fuera de la rueda, y no pulsa los botones por los que pase.
  int? _stickPointer;

  ControlRegion? get _stick =>
      _regions.where((r) => r.shape == ControlShape.stick).firstOrNull;

  void _down(int pointer, Offset position) {
    final stick = _stick;
    if (_stickPointer == null && stick != null && stick.analog(position) != null) {
      _stickPointer = pointer;
    }
    _pointers[pointer] = position;
    _update();
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (pointer == _stickPointer) _stickPointer = null;
    _update();
  }

  void _update() {
    final stick = _stick;
    final stickPos = _stickPointer == null ? null : _pointers[_stickPointer];
    final analog =
        stick != null && stickPos != null ? stick.stickVector(stickPos) : Offset.zero;
    if (analog != _analog) {
      _analog = analog;
      widget.onAnalogChanged?.call(analog);
      setState(() {});
    }
    final mask = TouchLayout.maskFor(
      [
        for (final e in _pointers.entries)
          if (e.key != _stickPointer) e.value,
      ],
      _regions,
    );
    if (mask == _mask) return;
    final newlyPressed = mask & ~_mask;
    _mask = mask;
    widget.onMaskChanged(mask);
    if (widget.haptics && newlyPressed != 0) HapticFeedback.lightImpact();
    setState(() {});
  }

  @override
  void dispose() {
    if (_mask != 0) widget.onMaskChanged(0);
    if (_analog != Offset.zero) widget.onAnalogChanged?.call(Offset.zero);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _regions = TouchLayout.customize(
        TouchLayout.forConsole(
          widget.consoleId,
          constraints.biggest,
          landscape: widget.landscape,
          scale: widget.scale,
          gutter: widget.gutter,
        ),
        constraints.biggest,
        widget.overrides,
        consoleId: widget.consoleId,
      );
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _down(e.pointer, e.localPosition),
        onPointerMove: (e) {
          _pointers[e.pointer] = e.localPosition;
          _update();
        },
        onPointerUp: (e) => _up(e.pointer),
        onPointerCancel: (e) => _up(e.pointer),
        child: CustomPaint(
          size: constraints.biggest,
          painter: ControlsPainter(
            regions: _regions,
            mask: _mask,
            analog: _analog,
            opacity: widget.opacity,
            accent: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    });
  }
}

/// Dibuja los controles. [selectedId] los resalta en el editor.
class ControlsPainter extends CustomPainter {
  ControlsPainter({
    required this.regions,
    required this.mask,
    required this.opacity,
    required this.accent,
    this.selectedId,
    this.analog = Offset.zero,
  });

  /// Posición del joystick (-1..1) para dibujar la palanca.

  final List<ControlRegion> regions;
  final int mask;
  final double opacity;
  final Color accent;
  final String? selectedId;
  final Offset analog;

  bool _pressed(int bit) => mask & (1 << bit) != 0;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = Colors.white.withValues(alpha: 0.16 * opacity / 0.55);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: (0.5 * opacity / 0.55).clamp(0, 1));
    final pressedFill = Paint()..color = accent.withValues(alpha: (0.75 * opacity / 0.55).clamp(0, 1));
    final textColor = Colors.white.withValues(alpha: (0.9 * opacity / 0.55).clamp(0, 1));

    for (final r in regions) {
      if (r.id == selectedId) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.rect.inflate(6), const Radius.circular(12)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = accent,
        );
      }
      switch (r.shape) {
        case ControlShape.dpad:
          _paintDpad(canvas, r, base, border, pressedFill);
        case ControlShape.circle:
          final pressed = _pressed(r.button!);
          canvas.drawCircle(r.center, r.size.width / 2, pressed ? pressedFill : base);
          canvas.drawCircle(r.center, r.size.width / 2, border);
          if (r.label.startsWith('PS_')) {
            _psSymbol(canvas, r.label, r.center, r.size.width * 0.22);
          } else {
            _label(canvas, r.label, r.center, r.size.width * 0.38, textColor);
          }
        case ControlShape.pill:
          final pressed = _pressed(r.button!);
          final rr = RRect.fromRectAndRadius(r.rect, Radius.circular(r.size.height / 2));
          canvas.drawRRect(rr, pressed ? pressedFill : base);
          canvas.drawRRect(rr, border);
          _label(canvas, r.label, r.center, r.size.height * 0.45, textColor);
        case ControlShape.stick:
          final radius = r.size.width / 2;
          canvas.drawCircle(r.center, radius, base);
          canvas.drawCircle(r.center, radius, border);
          final knob = r.center + analog * radius * 0.55;
          final active = analog != Offset.zero;
          canvas.drawCircle(knob, radius * 0.42, active ? pressedFill : base);
          canvas.drawCircle(knob, radius * 0.42, border);
      }
    }
  }

  void _paintDpad(Canvas canvas, ControlRegion r, Paint base, Paint border, Paint pressed) {
    final d = r.size.width;
    final arm = d / 3;
    final c = r.center;
    final cross = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: arm, height: d), const Radius.circular(8)))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: d, height: arm), const Radius.circular(8)));
    canvas.drawPath(cross, base);
    canvas.drawPath(cross, border);
    void dir(int bit, Offset offset) {
      if (!_pressed(bit)) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + offset, width: arm, height: arm),
          const Radius.circular(6),
        ),
        pressed,
      );
    }

    dir(RetroButton.up, Offset(0, -arm));
    dir(RetroButton.down, Offset(0, arm));
    dir(RetroButton.left, Offset(-arm, 0));
    dir(RetroButton.right, Offset(arm, 0));
  }

  /// Símbolos del mando de PlayStation con sus colores clásicos.
  void _psSymbol(Canvas canvas, String symbol, Offset c, double s) {
    final alpha = (0.95 * opacity / 0.55).clamp(0.0, 1.0);
    final (color, path) = switch (symbol) {
      'PS_CROSS' => (
          const Color(0xFF7CB2E8),
          Path()
            ..moveTo(c.dx - s, c.dy - s)
            ..lineTo(c.dx + s, c.dy + s)
            ..moveTo(c.dx + s, c.dy - s)
            ..lineTo(c.dx - s, c.dy + s),
        ),
      'PS_CIRCLE' => (const Color(0xFFFF6666), Path()..addOval(Rect.fromCircle(center: c, radius: s))),
      'PS_SQUARE' => (
          const Color(0xFFE59BD6),
          Path()..addRect(Rect.fromCenter(center: c, width: s * 1.8, height: s * 1.8)),
        ),
      _ => (
          const Color(0xFF40E2A0),
          Path()
            ..moveTo(c.dx, c.dy - s)
            ..lineTo(c.dx + s * 1.05, c.dy + s * 0.75)
            ..lineTo(c.dx - s * 1.05, c.dy + s * 0.75)
            ..close(),
        ),
    };
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.28
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha),
    );
  }

  void _label(Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(ControlsPainter old) =>
      old.mask != mask ||
      old.analog != analog ||
      old.opacity != opacity ||
      old.regions != regions ||
      old.accent != accent ||
      old.selectedId != selectedId;
}
