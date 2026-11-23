import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app/ui_sound.dart';

/// Estilo "RetroStation OS": paneles con marco doble, fondo de circuitos en
/// movimiento, líneas de barrido CRT e iconos de consola en pixel art.
abstract final class RetroPalette {
  static const bg = Color(0xFF0B161E);
  static const bg2 = Color(0xFF10212C);
  static const panel = Color(0xFF1B3040);
  static const panel2 = Color(0xFF22394B);
  static const panelHi = Color(0xFF2A4559);
  static const line = Color(0xFF5F8193); // marco claro
  static const lineDark = Color(0xFF0A141B); // contorno exterior
  static const circuit = Color(0xFF224556);
  static const text = Color(0xFFE9F3F7);
  static const muted = Color(0xFF9DB6C3);
  static const power = Color(0xFFEC7A2F);
  static const screen = Color(0xFF0D1A22); // fondo de las "pantallas" de las tarjetas
}

/// Decoración de panel: degradado, borde claro de 3 px y contorno oscuro,
/// como un menú de consola. [highlight] usa el color del cursor y un brillo.
BoxDecoration retroFrame({Color? highlight, double radius = 10, bool raised = true}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [RetroPalette.panel2, RetroPalette.panel],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: highlight ?? RetroPalette.line, width: 3),
      boxShadow: [
        const BoxShadow(color: RetroPalette.lineDark, spreadRadius: 2),
        if (raised) const BoxShadow(color: Color(0x59000000), offset: Offset(0, 4), spreadRadius: 2),
        if (highlight != null)
          BoxShadow(color: highlight.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1),
      ],
    );

/// "Pantalla" interior de una tarjeta (donde va la portada o el icono).
BoxDecoration retroScreen({double radius = 6}) => BoxDecoration(
      color: RetroPalette.screen,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: RetroPalette.lineDark, width: 3),
    );

/// Panel con marco. Si es pulsable, se resalta con el color del cursor al
/// tocarlo (respuesta inmediata, como el cursor de un menú de consola).
class RetroPanel extends StatefulWidget {
  const RetroPanel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(8),
    this.radius = 10,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;

  @override
  State<RetroPanel> createState() => _RetroPanelState();
}

class _RetroPanelState extends State<RetroPanel> {
  bool _down = false;
  bool _focused = false; // con el mando o el teclado (Tab, flechas)

  void _activate() {
    UiSound.play(Sfx.click);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final lit = _down || _focused || widget.selected;
    final still = MediaQuery.disableAnimationsOf(context);
    final panel = AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 110),
      decoration: retroFrame(highlight: lit ? accent : null, radius: widget.radius),
      padding: widget.padding,
      child: widget.child,
    );
    if (widget.onTap == null) return panel;
    return AnimatedSlide(
      offset: Offset(0, lit && !still ? -0.012 : 0),
      duration: const Duration(milliseconds: 110),
      // Se puede elegir con el mando o el teclado: resaltado al enfocarlo y
      // se activa con A / Intro / Espacio.
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: _activate,
          child: Semantics(button: true, child: panel),
        ),
      ),
    );
  }
}

/// Fondo animado: cuadrícula y pistas de circuito que se desplazan despacio
/// en diagonal, con una viñeta suave. Se detiene con "Reducir animaciones".
/// Con [amoled] (Ajustes > Fondo > Negro AMOLED) la base es negro puro y las
/// pistas, más tenues.
class RetroBackground extends StatefulWidget {
  const RetroBackground({super.key, this.animate = true, this.amoled = false});

  final bool animate;
  final bool amoled;

  @override
  State<RetroBackground> createState() => _RetroBackgroundState();
}

class _RetroBackgroundState extends State<RetroBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 40));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _drift.repeat();
  }

  @override
  void didUpdateWidget(RetroBackground old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_drift.isAnimating) _drift.repeat();
    if (!widget.animate) _drift.stop();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  // ClipRect: el patrón se dibuja desde fuera del borde para que el
  // desplazamiento sea continuo; sin recorte invadía el menú lateral.
  Widget build(BuildContext context) => ClipRect(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _CircuitPainter(_drift, amoled: widget.amoled),
            size: Size.infinite,
          ),
        ),
      );
}

class _CircuitPainter extends CustomPainter {
  _CircuitPainter(this.drift, {required this.amoled}) : super(repaint: drift);

  final Animation<double> drift;
  final bool amoled;

  static const _tile = 160.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = amoled ? const Color(0xFF000000) : RetroPalette.bg);
    final shift = drift.value * _tile;
    final grid = Paint()
      ..color = amoled ? const Color(0xFF071015) : RetroPalette.bg2
      ..strokeWidth = 2;
    final gShift = shift % 40;
    for (var x = gShift - 40; x < size.width + 40; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = gShift - 40; y < size.height + 40; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final trace = Paint()
      ..color = amoled ? const Color(0xFF102830) : RetroPalette.circuit
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final node = Paint()..color = trace.color;
    // Pistas de una baldosa de 160 px (las mismas que en RetroStation OS).
    final path = Path()
      ..moveTo(0, 40)
      ..lineTo(40, 40)
      ..lineTo(60, 60)
      ..lineTo(100, 60)
      ..moveTo(100, 60)
      ..lineTo(100, 100)
      ..lineTo(160, 100)
      ..moveTo(20, 160)
      ..lineTo(20, 120)
      ..lineTo(40, 100)
      ..lineTo(60, 100)
      ..moveTo(80, 0)
      ..lineTo(80, 30)
      ..moveTo(120, 160)
      ..lineTo(120, 130)
      ..lineTo(140, 110)
      ..moveTo(0, 120)
      ..lineTo(20, 120);
    final nodes = [const Offset(97, 57), const Offset(77, 27), const Offset(57, 97), const Offset(137, 107)];
    final t = shift % _tile;
    for (var ox = t - _tile; ox < size.width; ox += _tile) {
      for (var oy = t - _tile; oy < size.height; oy += _tile) {
        canvas.save();
        canvas.translate(ox, oy);
        canvas.drawPath(path, trace);
        for (final n in nodes) {
          canvas.drawRect(n & const Size(7, 7), node);
        }
        canvas.restore();
      }
    }
    // Viñeta
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CircuitPainter old) => old.amoled != amoled;
}

/// Líneas de barrido CRT muy suaves encima de la interfaz (no reciben toques).
class Scanlines extends StatelessWidget {
  const Scanlines({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ScanlinePainter(MediaQuery.devicePixelRatioOf(context)),
            size: Size.infinite,
          ),
        ),
      );
}

/// Una línea de un solo píxel físico cada 3 puntos: textura de CRT que no
/// corta las letras (con líneas más gruesas el texto parecía roto).
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter(this.dpr);

  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x1A000000);
    final h = 1 / dpr;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.dpr != dpr;
}

/// Icono en pixel art de cada consola (silueta genérica del aparato, sin
/// logotipos). Lienzo lógico de 64 x 48 "píxeles", escalado sin suavizado.
class ConsoleArt extends StatelessWidget {
  const ConsoleArt(this.consoleId, {super.key, this.background = true});

  final String consoleId;

  /// Si pinta el fondo oscuro de "pantalla" o se deja transparente.
  final bool background;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ConsoleArtPainter(consoleId, background),
        child: const SizedBox.expand(),
      );
}

class _ConsoleArtPainter extends CustomPainter {
  _ConsoleArtPainter(this.id, this.background);

  final String id;
  final bool background;

  /// Rectángulos (x, y, ancho, alto, color) de cada consola.
  static const Map<String, List<(int, int, int, int, int)>> _art = {
    'nes': [
      (10, 18, 44, 18, 0xFFC9C9C9), (10, 30, 44, 6, 0xFF3A3A3A), (16, 20, 20, 6, 0xFF8C8C8C),
      (40, 32, 4, 2, 0xFFDD3333), (46, 32, 4, 2, 0xFF777777), (38, 8, 16, 7, 0xFFC9C9C9),
      (40, 10, 3, 3, 0xFF222222), (48, 11, 2, 2, 0xFFDD3333), (51, 11, 2, 2, 0xFFDD3333),
    ],
    'snes': [
      (10, 18, 44, 18, 0xFFCFCFD6), (14, 22, 16, 8, 0xFF9F9FB0), (40, 24, 3, 3, 0xFF7D5BD1),
      (45, 24, 3, 3, 0xFF7D5BD1), (38, 6, 18, 8, 0xFFCFCFD6), (40, 8, 3, 3, 0xFF444444),
      (49, 7, 2, 2, 0xFF7D5BD1), (52, 9, 2, 2, 0xFFB6A5EF),
    ],
    'psx': [
      (10, 12, 40, 26, 0xFFC7C9CC), (18, 15, 20, 18, 0xFFB0B3B7), (22, 19, 12, 10, 0xFF9DA1A6),
      (42, 32, 4, 3, 0xFF666666), (46, 30, 14, 8, 0xFF9EA2A7), (48, 32, 3, 3, 0xFF444444),
      (55, 32, 2, 2, 0xFF4FC3F7),
    ],
    'gba': [
      (8, 14, 48, 22, 0xFF6C4BD6), (22, 17, 20, 15, 0xFF202020), (24, 19, 16, 11, 0xFF8FDC8F),
      (12, 22, 6, 2, 0xFF222222), (14, 20, 2, 6, 0xFF222222), (47, 21, 3, 3, 0xFF222222),
      (51, 24, 3, 3, 0xFF222222),
    ],
    'gb': [
      (20, 4, 24, 40, 0xFFC8C4BC), (23, 7, 18, 15, 0xFF5A5A66), (25, 9, 14, 11, 0xFF9BBC0F),
      (23, 28, 6, 2, 0xFF2A2A2A), (25, 26, 2, 6, 0xFF2A2A2A), (35, 29, 3, 3, 0xFF9C2B5C),
      (39, 27, 3, 3, 0xFF9C2B5C), (28, 37, 3, 1, 0xFF7A7A7A), (33, 37, 3, 1, 0xFF7A7A7A),
    ],
    'gbc': [
      (20, 4, 24, 40, 0xFF8E5BD6), (23, 7, 18, 15, 0xFF2A2A2A), (25, 9, 14, 11, 0xFF7FC8F0),
      (23, 28, 6, 2, 0xFF222222), (25, 26, 2, 6, 0xFF222222), (35, 29, 3, 3, 0xFF222222),
      (39, 27, 3, 3, 0xFF222222), (28, 37, 3, 1, 0xFF4A2F7A), (33, 37, 3, 1, 0xFF4A2F7A),
    ],
    'nds': [
      (16, 6, 32, 18, 0xFFD0D3D8), (20, 8, 24, 14, 0xFF202020), (22, 10, 20, 10, 0xFF7FB6E8),
      (16, 26, 32, 18, 0xFFC4C7CC), (22, 28, 20, 12, 0xFF202020), (24, 30, 16, 8, 0xFFE8E8B0),
    ],
    // Consola negra con la ranura arriba y el círculo central; mando de 3 botones.
    'genesis': [
      (8, 18, 38, 18, 0xFF30303A), (18, 15, 16, 4, 0xFF18181D), (16, 21, 20, 12, 0xFF44444F),
      (20, 23, 12, 8, 0xFF62626F), (40, 30, 3, 2, 0xFFDD3333), (10, 32, 6, 2, 0xFF55555F),
      (42, 6, 18, 10, 0xFF30303A), (44, 9, 4, 4, 0xFF6E6E7A), (51, 11, 2, 2, 0xFFBBBBC4),
      (54, 10, 2, 2, 0xFFBBBBC4), (57, 9, 2, 2, 0xFFBBBBC4),
    ],
    // Consola gris oscura con cartucho; mando de tres brazos con A, B y C.
    'n64': [
      (8, 22, 38, 14, 0xFF3A3A42), (13, 18, 28, 6, 0xFF46464F), (20, 13, 14, 7, 0xFF2A2A30),
      (22, 14, 10, 3, 0xFF6B6B78), (14, 30, 5, 2, 0xFF8A8A94), (35, 30, 5, 2, 0xFF8A8A94),
      (42, 6, 18, 7, 0xFF55555F), (42, 13, 4, 5, 0xFF55555F), (49, 13, 4, 6, 0xFF55555F),
      (56, 13, 4, 5, 0xFF55555F), (50, 14, 2, 2, 0xFF1E1E22), (44, 8, 3, 3, 0xFF1E1E22),
      (54, 9, 2, 2, 0xFF22C55E), (56, 7, 2, 2, 0xFF3B82F6), (58, 10, 2, 2, 0xFFFACC15),
    ],
    '3ds': [
      (14, 4, 36, 20, 0xFFC62828), (17, 6, 30, 16, 0xFF202020), (19, 8, 26, 12, 0xFF6FB7F0),
      (14, 25, 36, 20, 0xFFB71C1C), (22, 27, 20, 14, 0xFF202020), (24, 29, 16, 10, 0xFFE8E8B0),
      (16, 28, 4, 4, 0xFF8A8A94), (17, 35, 3, 1, 0xFF333333), (18, 34, 1, 3, 0xFF333333),
      (45, 30, 2, 2, 0xFFEEEEEE), (43, 32, 2, 2, 0xFFEEEEEE), (47, 32, 2, 2, 0xFFEEEEEE),
      (45, 34, 2, 2, 0xFFEEEEEE),
    ],
    'psp': [
      (6, 16, 52, 18, 0xFF1F1F24), (18, 18, 28, 14, 0xFF000000), (20, 20, 24, 10, 0xFF3A7BD5),
      (10, 22, 4, 4, 0xFF666666), (50, 21, 2, 2, 0xFFCCCCCC), (52, 24, 2, 2, 0xFFCCCCCC),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (background) canvas.drawRect(Offset.zero & size, Paint()..color = RetroPalette.screen);
    final rects = _art[id];
    if (rects == null) return;
    // Las consolas ocupan el centro del lienzo de 64 x 48: se recorta a esa
    // zona para que el icono llene el hueco. Sin suavizado, sigue nítido.
    const cx = 4.0, cy = 4.0, cw = 56.0, ch = 40.0;
    final s = math.min(size.width / cw, size.height / ch);
    canvas.translate(-cx * s + (size.width - cw * s) / 2, -cy * s + (size.height - ch * s) / 2);
    const ox = 0.0, oy = 0.0;
    final p = Paint()..isAntiAlias = false;
    for (final (x, y, w, h, c) in rects) {
      p.color = Color(c);
      canvas.drawRect(Rect.fromLTWH(ox + x * s, oy + y * s, w * s, h * s), p);
    }
  }

  @override
  bool shouldRepaint(_ConsoleArtPainter old) => old.id != id || old.background != background;
}
