import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../brand/logo.dart';
import '../../brand/retro.dart';
import '../../controllers/touch_layout.dart';
import '../../emulation/native_bindings.dart';
import '../../settings/app_settings.dart';

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
    this.skin = ControlSkin.clasico,
  });

  /// Diseño de los botones (Ajustes > Controles táctiles).
  final ControlSkin skin;

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
            skin: widget.skin,
            consoleId: widget.consoleId,
          ),
        ),
      );
    });
  }
}

/// Dibuja los controles con el diseño elegido en Ajustes ([skin]). El mismo
/// dibujante sirve para todas las consolas, el editor de controles y la vista
/// previa de Ajustes. [selectedId] resalta un control en el editor.
class ControlsPainter extends CustomPainter {
  ControlsPainter({
    required this.regions,
    required this.mask,
    required this.opacity,
    required this.accent,
    this.selectedId,
    this.analog = Offset.zero,
    this.skin = ControlSkin.clasico,
    this.consoleId = '',
  });

  final List<ControlRegion> regions;
  final int mask;
  final double opacity;
  final Color accent;
  final String? selectedId;

  /// Posición del joystick (-1..1) para dibujar la palanca.
  final Offset analog;
  final ControlSkin skin;

  /// Para los colores de los botones en el diseño "Consola".
  final String consoleId;

  bool _pressed(int bit) => mask & (1 << bit) != 0;

  /// Opacidad relativa a la de fábrica (0.55): 1 = como siempre.
  double get _k => opacity / 0.55;
  double _a(double alpha) => (alpha * _k).clamp(0.0, 1.0);

  /// Opacidad de los diseños opacos (Consola, Pixel): más cubrientes.
  double get _solid => (opacity * 1.6).clamp(0.2, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
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
          _paintDpad(canvas, r);
        case ControlShape.circle:
          final pressed = _pressed(r.button!);
          final color = _buttonColor(r);
          final shift = _body(canvas, _round(r.rect, 0.36), pressed: pressed, color: color);
          final c = r.center + shift;
          if (r.label.startsWith('PS_')) {
            _psSymbol(canvas, r.label, c, r.size.width * 0.22);
          } else {
            _label(canvas, r.label, c, r.size.width * (r.label.length > 1 ? 0.30 : 0.38),
                _textColor(color));
          }
        case ControlShape.pill:
          final pressed = _pressed(r.button!);
          final radius = skin == ControlSkin.pixel ? 4.0 : r.size.height / 2;
          final path = Path()..addRRect(RRect.fromRectAndRadius(r.rect, Radius.circular(radius)));
          final shift = _body(canvas, path, pressed: pressed, color: _pillColor);
          _label(canvas, r.label, r.center + shift, r.size.height * 0.45, _textColor(_pillColor));
        case ControlShape.stick:
          final radius = r.size.width / 2;
          _body(canvas, _round(r.rect, 0.3), pressed: false, color: _padColor, flat: true);
          final knob = Rect.fromCircle(center: r.center + analog * radius * 0.55, radius: radius * 0.42);
          _body(canvas, _round(knob, 0.4), pressed: analog != Offset.zero, color: _pillColor);
      }
    }
  }

  /// Círculo inscrito en [rect]; en el diseño Pixel, un bloque redondeado
  /// ([pixelRadius] = fracción del radio).
  Path _round(Rect rect, double pixelRadius) => skin == ControlSkin.pixel
      ? (Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.width / 2 * pixelRadius))))
      : (Path()..addOval(rect));

  // --- Colores -------------------------------------------------------------

  static const _padColor = Color(0xFF2C2F36);
  static const _pillColor = Color(0xFF4A4F59);

  /// Color de cada botón en el diseño "Consola", inspirado en los mandos de
  /// cada sistema.
  Color _buttonColor(ControlRegion r) {
    if (r.label.startsWith('PS_')) return const Color(0xFF3A3E46);
    final l = r.label;
    return switch (consoleId) {
      'n64' => l.startsWith('C')
          ? const Color(0xFFF0C419)
          : (l == 'A' ? const Color(0xFF2F5FD0) : const Color(0xFF2E9E4F)),
      'snes' || 'nds' => switch (l) {
          'A' => const Color(0xFFD7373F),
          'B' => const Color(0xFFF2BE2C),
          'X' => const Color(0xFF3C5FD6),
          _ => const Color(0xFF2FA45A),
        },
      'genesis' => const Color(0xFF2A2B31),
      'nes' => const Color(0xFFD0312D),
      _ => const Color(0xFFB02A55), // Game Boy, GBC y GBA
    };
  }

  Color _textColor(Color button) => switch (skin) {
        ControlSkin.consola =>
          (button.computeLuminance() > 0.45 ? const Color(0xFF1A1A1A) : Colors.white)
              .withValues(alpha: _solid),
        ControlSkin.pixel => RetroPalette.text.withValues(alpha: _solid),
        ControlSkin.neon => Color.lerp(accent, Colors.white, 0.35)!.withValues(alpha: _a(0.95)),
        ControlSkin.minimalista => Colors.white.withValues(alpha: _a(0.75)),
        ControlSkin.clasico || ControlSkin.cristal => Colors.white.withValues(alpha: _a(0.9)),
      };

  // --- Cuerpo de un control ------------------------------------------------

  /// Dibuja la forma [path] con el diseño actual. Devuelve el desplazamiento
  /// del contenido (los botones con relieve bajan al pulsarlos).
  Offset _body(Canvas canvas, Path path,
      {required bool pressed, required Color color, bool flat = false}) {
    final bounds = path.getBounds();
    switch (skin) {
      case ControlSkin.clasico:
        canvas.drawPath(
            path,
            Paint()
              ..color = pressed
                  ? accent.withValues(alpha: _a(0.75))
                  : Colors.white.withValues(alpha: _a(0.16)));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white.withValues(alpha: _a(0.5)));
        return Offset.zero;

      case ControlSkin.minimalista:
        if (pressed) {
          canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: _a(0.28)));
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.white.withValues(alpha: _a(pressed ? 0.8 : 0.45)));
        return Offset.zero;

      case ControlSkin.neon:
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = pressed ? 7 : 4
              ..color = accent.withValues(alpha: _a(pressed ? 0.9 : 0.55))
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, pressed ? 9 : 6));
        canvas.drawPath(path, Paint()..color = accent.withValues(alpha: _a(pressed ? 0.5 : 0.08)));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Color.lerp(accent, Colors.white, 0.3)!.withValues(alpha: _a(0.95)));
        return Offset.zero;

      case ControlSkin.consola:
        final a = _solid;
        const depth = 3.0;
        final down = pressed && !flat ? const Offset(0, depth * 0.7) : Offset.zero;
        if (!flat) {
          // Lateral del botón, más oscuro: da el relieve.
          canvas.drawPath(path.shift(const Offset(0, depth)),
              Paint()..color = Color.lerp(color, Colors.black, 0.55)!.withValues(alpha: a));
        }
        final body = path.shift(down);
        final top = Color.lerp(color, Colors.white, pressed ? 0.0 : 0.22)!;
        final bottom = Color.lerp(color, Colors.black, pressed ? 0.35 : 0.12)!;
        canvas.drawPath(
          body,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top.withValues(alpha: a), bottom.withValues(alpha: a)],
            ).createShader(bounds.shift(down)),
        );
        canvas.drawPath(
            body,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = Colors.black.withValues(alpha: 0.45 * a));
        return down;

      case ControlSkin.pixel:
        final a = _solid;
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = RetroPalette.lineDark.withValues(alpha: a));
        canvas.drawPath(
            path,
            Paint()
              ..color = (pressed ? accent : RetroPalette.panel).withValues(alpha: a));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = (pressed ? Colors.white : RetroPalette.line).withValues(alpha: a));
        return Offset.zero;

      case ControlSkin.cristal:
        final tint = pressed ? accent : Colors.white;
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: _a(pressed ? 0.7 : 0.30)),
                tint.withValues(alpha: _a(pressed ? 0.45 : 0.06)),
              ],
            ).createShader(bounds),
        );
        // Reflejo en la mitad de arriba.
        canvas.save();
        canvas.clipPath(path);
        canvas.drawOval(
          Rect.fromLTWH(bounds.left + bounds.width * 0.12, bounds.top + bounds.height * 0.04,
              bounds.width * 0.76, bounds.height * 0.42),
          Paint()..color = Colors.white.withValues(alpha: _a(0.16)),
        );
        canvas.restore();
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3
              ..color = Colors.white.withValues(alpha: _a(0.65)));
        return Offset.zero;
    }
  }

  void _paintDpad(Canvas canvas, ControlRegion r) {
    final d = r.size.width;
    final arm = d / 3;
    final c = r.center;
    final corner = Radius.circular(skin == ControlSkin.pixel ? 0 : 8);
    final vertical = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: arm, height: d), corner));
    final horizontal = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: d, height: arm), corner));
    // Clásico: dos barras cruzadas, como siempre. Los demás: una sola silueta
    // (los bordes no se cruzan en el centro).
    final path = skin == ControlSkin.clasico
        ? (Path()
          ..addPath(vertical, Offset.zero)
          ..addPath(horizontal, Offset.zero))
        : Path.combine(PathOperation.union, vertical, horizontal);
    final shift = _body(canvas, path, pressed: false, color: _padColor);
    final pressed = Paint()
      ..color = switch (skin) {
        ControlSkin.consola => accent.withValues(alpha: 0.7 * _solid),
        ControlSkin.pixel => accent.withValues(alpha: _solid),
        ControlSkin.minimalista => Colors.white.withValues(alpha: _a(0.3)),
        ControlSkin.neon || ControlSkin.cristal => accent.withValues(alpha: _a(0.6)),
        ControlSkin.clasico => accent.withValues(alpha: _a(0.75)),
      };
    void dir(int bit, Offset offset) {
      if (!_pressed(bit)) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + shift + offset, width: arm, height: arm),
          Radius.circular(skin == ControlSkin.pixel ? 0 : 6),
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
    final alpha = skin == ControlSkin.consola || skin == ControlSkin.pixel ? _solid : _a(0.95);
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
        ..strokeWidth = s * (skin == ControlSkin.minimalista ? 0.18 : 0.28)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha),
    );
  }

  void _label(Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: skin == ControlSkin.minimalista ? FontWeight.w500 : FontWeight.w800,
          fontFamily: skin == ControlSkin.pixel ? brandFont : null,
        ),
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
      old.selectedId != selectedId ||
      old.skin != skin ||
      old.consoleId != consoleId;
}
