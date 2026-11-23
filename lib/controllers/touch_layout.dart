import 'dart:math' as math;
import 'dart:ui';

import '../emulation/native_bindings.dart';

enum ControlShape { dpad, circle, pill, stick }

/// Una zona táctil: un botón o la cruceta completa.
class ControlRegion {
  const ControlRegion({
    required this.id,
    required this.shape,
    required this.center,
    required this.size,
    this.button,
    this.label = '',
  });

  /// Identificador estable ('dpad', 'a', 'b', 'l', 'r', 'start', 'select').
  final String id;
  final ControlShape shape;
  final Offset center;

  ControlRegion moved(Offset newCenter, Size newSize) => ControlRegion(
        id: id,
        shape: shape,
        center: newCenter,
        size: newSize,
        button: button,
        label: label,
      );

  /// Diámetro para círculos y cruceta; ancho/alto para botones alargados.
  final Size size;

  /// Bit del mando (null para la cruceta, que produce varios).
  final int? button;
  final String label;

  Rect get rect => Rect.fromCenter(center: center, width: size.width, height: size.height);

  /// Bits pulsados por un dedo en [point]. Las zonas son algo más grandes que
  /// el dibujo para tolerar toques imprecisos.
  int hit(Offset point) {
    switch (shape) {
      case ControlShape.dpad:
        final radius = size.width / 2;
        final d = point - center;
        if (d.distance > radius * 1.25 || d.distance < radius * 0.12) return 0;
        // Zona muerta por eje: permite diagonales (dos direcciones a la vez).
        final dead = radius * 0.32;
        var mask = 0;
        if (d.dy < -dead) mask |= 1 << RetroButton.up;
        if (d.dy > dead) mask |= 1 << RetroButton.down;
        if (d.dx < -dead) mask |= 1 << RetroButton.left;
        if (d.dx > dead) mask |= 1 << RetroButton.right;
        return mask;
      case ControlShape.circle:
        return (point - center).distance <= size.width / 2 * 1.2 ? 1 << button! : 0;
      case ControlShape.pill:
        return rect.inflate(math.min(size.height * 0.3, 12)).contains(point)
            ? 1 << button!
            : 0;
      case ControlShape.stick:
        return 0;  // analógico: ver [TouchLayout.analogFor]
    }
  }

  /// Joystick: vector normalizado (-1..1, y hacia abajo) de un dedo en
  /// [point], o null si está fuera. La zona es mayor que el dibujo para que el
  /// dedo pueda llegar al tope sin salirse.
  Offset? analog(Offset point) {
    if (shape != ControlShape.stick) return null;
    if ((point - center).distance > size.width / 2 * 1.6) return null;
    return stickVector(point);
  }

  /// Vector del joystick para un dedo en cualquier sitio: fuera de la rueda
  /// se queda al tope en la dirección del dedo (no se suelta al salirse).
  Offset stickVector(Offset point) {
    final v = (point - center) / (size.width / 2 * 0.75);
    return v.distance > 1 ? v / v.distance : v;
  }
}

/// Distribución de los controles de GBA dentro de un área.
///
/// - Vertical: el área es la franja inferior, bajo la imagen del juego.
/// - Horizontal: el área es toda la pantalla; los controles van en dos franjas
///   laterales de ancho [gutter] para no tapar nunca la imagen.
abstract final class TouchLayout {
  /// Ancho de cada franja lateral en horizontal si no se indica otro.
  static double defaultGutter(Size area) => area.width * 0.2;

  /// Controles de cada consola sobre la distribución base.
  static List<ControlRegion> forConsole(
    String consoleId,
    Size area, {
    required bool landscape,
    double scale = 1,
    double? gutter,
  }) {
    final base = gba(area, landscape: landscape, scale: scale, gutter: gutter);
    return switch (consoleId) {
      // Sin gatillos L/R.
      'gb' || 'gbc' || 'nes' => base.where((r) => r.id != 'l' && r.id != 'r').toList(),
      'snes' || 'nds' => _snesFaceButtons(base),
      // PlayStation: mismo rombo con ○ (A), ✕ (B), △ (X), □ (Y); L/R = L1/R1.
      'psx' => _snesFaceButtons(base, labels: psxLabels),
      'psp' => _psp(_snesFaceButtons(base, labels: psxLabels), area, landscape: landscape),
      // 3DS: rombo A/B/X/Y como en la consola y Circle Pad bajo la cruceta.
      '3ds' => _psp(_snesFaceButtons(base), area, landscape: landscape),
      'genesis' => _genesisFaceButtons(base),
      'n64' => _n64(base, area, landscape: landscape),
      _ => base,
    };
  }

  /// PSP: joystick analógico bajo la cruceta (que sube un poco); SELECT y
  /// START se apartan para dejarle sitio.
  static List<ControlRegion> _psp(List<ControlRegion> regions, Size area,
      {required bool landscape}) {
    final dpad = regions.firstWhere((r) => r.id == 'dpad');
    final s = dpad.size.width;
    final stick = ControlRegion(
      id: 'stick',
      shape: ControlShape.stick,
      center: dpad.center + Offset(0, s * 0.70),
      size: Size(s * 0.82, s * 0.82),
    );
    return [
      for (final r in regions)
        switch (r.id) {
          // Sube poco: arriba están L/R.
          'dpad' => r.moved(dpad.center - Offset(0, s * 0.25), r.size),
          // En horizontal, SELECT y START van abajo en el centro, bajo la imagen
          // (panorámica en PSP): las franjas laterales son del joystick y los botones.
          'select' when landscape => r.moved(
              Offset(area.width / 2 - r.size.width * 0.65, area.height - r.size.height / 2 - 12),
              r.size),
          'start' when landscape => r.moved(
              Offset(area.width / 2 + r.size.width * 0.65, area.height - r.size.height / 2 - 12),
              r.size),
          'select' => r.moved(Offset(area.width * 0.62, r.center.dy), r.size),
          'start' when !landscape => r.moved(Offset(area.width * 0.86, r.center.dy), r.size),
          _ => r,
        },
      stick,
    ];
  }

  /// Valor del joystick con todos los dedos (el primero que esté dentro).
  static Offset analogFor(Iterable<Offset> pointers, List<ControlRegion> regions) {
    for (final region in regions) {
      if (region.shape != ControlShape.stick) continue;
      for (final point in pointers) {
        if (region.analog(point) case final v?) return v;
      }
    }
    return Offset.zero;
  }

  /// Etiquetas especiales que el dibujante convierte en los símbolos de PlayStation.
  static const psxLabels = (a: 'PS_CIRCLE', b: 'PS_CROSS', x: 'PS_TRIANGLE', y: 'PS_SQUARE');

  /// SNES: A/B/X/Y en rombo (como el mando original) en el sitio de A/B.
  static List<ControlRegion> _snesFaceButtons(
    List<ControlRegion> base, {
    ({String a, String b, String x, String y}) labels = (a: 'A', b: 'B', x: 'X', y: 'Y'),
  }) {
    final a = base.firstWhere((r) => r.id == 'a');
    final b = base.firstWhere((r) => r.id == 'b');
    final center = Offset((a.center.dx + b.center.dx) / 2, (a.center.dy + b.center.dy) / 2);
    final d = a.size.width * 0.82;
    final r = d * 0.95;
    return [
      for (final region in base)
        if (region.id != 'a' && region.id != 'b') region,
      _face('a', RetroButton.a, labels.a, center + Offset(r, 0), d),
      _face('b', RetroButton.b, labels.b, center + Offset(0, r), d),
      _face('x', RetroButton.x, labels.x, center + Offset(0, -r), d),
      _face('y', RetroButton.y, labels.y, center + Offset(-r, 0), d),
    ];
  }

  /// Mega Drive: A, B y C en diagonal ascendente, sin L/R ni SELECT. En
  /// Genesis Plus GX, A = Y, B = B y C = A de libretro.
  static List<ControlRegion> _genesisFaceButtons(List<ControlRegion> base) {
    final a = base.firstWhere((r) => r.id == 'a');
    final b = base.firstWhere((r) => r.id == 'b');
    final center = Offset((a.center.dx + b.center.dx) / 2, (a.center.dy + b.center.dy) / 2);
    final d = a.size.width * 0.85;
    final step = d * 1.05;
    return [
      for (final region in base)
        if (!const {'a', 'b', 'l', 'r', 'select'}.contains(region.id)) region,
      _face('y', RetroButton.y, 'A', center + Offset(-step, step * 0.3), d),
      _face('b', RetroButton.b, 'B', center, d),
      _face('a', RetroButton.a, 'C', center + Offset(step, -step * 0.3), d),
    ];
  }

  /// Nintendo 64: joystick en el sitio de la cruceta (que sube), A y B
  /// grandes, los cuatro C en rombo, Z bajo la L y START en el centro.
  static List<ControlRegion> _n64(List<ControlRegion> base, Size area, {required bool landscape}) {
    final dpad = base.firstWhere((r) => r.id == 'dpad');
    final a = base.firstWhere((r) => r.id == 'a');
    final b = base.firstWhere((r) => r.id == 'b');
    final l = base.firstWhere((r) => r.id == 'l');
    final s = dpad.size.width;
    final d = a.size.width * 0.62;
    final cCenter = Offset(a.center.dx - d * 0.4, a.center.dy - d * 2.0);
    final r = d * 0.95;
    return [
      for (final region in base)
        if (!const {'dpad', 'select', 'a', 'b'}.contains(region.id)) region,
      ControlRegion(id: 'stick', shape: ControlShape.stick, center: dpad.center, size: Size(s, s)),
      dpad.moved(dpad.center + Offset(0, s * 0.85), dpad.size * 0.55),
      _face('a', RetroButton.b, 'A', a.center, a.size.width),
      _face('b', RetroButton.y, 'B', b.center, b.size.width),
      _face('cu', RetroButton.cUp, 'C▲', cCenter + Offset(0, -r), d),
      _face('cd', RetroButton.cDown, 'C▼', cCenter + Offset(0, r), d),
      _face('cl', RetroButton.cLeft, 'C◀', cCenter + Offset(-r, 0), d),
      _face('cr', RetroButton.cRight, 'C▶', cCenter + Offset(r, 0), d),
      ControlRegion(
        id: 'z',
        shape: ControlShape.pill,
        center: l.center + Offset(0, l.size.height * 1.6),
        size: l.size,
        button: RetroButton.l2,
        label: 'Z',
      ),
    ];
  }

  static ControlRegion _face(String id, int button, String label, Offset c, double d) =>
      ControlRegion(
        id: id,
        shape: ControlShape.circle,
        center: c,
        size: Size(d, d),
        button: button,
        label: label,
      );

  static List<ControlRegion> gba(
    Size area, {
    required bool landscape,
    double scale = 1,
    double? gutter,
  }) {
    final w = area.width;
    final h = area.height;
    if (landscape) {
      final g = gutter ?? defaultGutter(area);
      final unit = math.min(g, h * 0.5) * scale.clamp(0.7, 1.0);
      final dpad = unit * 0.85;
      final face = unit * 0.38;
      final shoulder = Size(g * 0.7, unit * 0.24);
      final pill = Size(g * 0.55, unit * 0.2);
      return [
        _pill(RetroButton.l, 'L', Offset(g / 2, shoulder.height / 2 + 12), shoulder),
        _pill(RetroButton.r, 'R', Offset(w - g / 2, shoulder.height / 2 + 12), shoulder),
        _dpad(Offset(g / 2, h * 0.53), dpad),
        _circle(RetroButton.a, 'A', Offset(w - g * 0.28, h * 0.47), face),
        _circle(RetroButton.b, 'B', Offset(w - g * 0.70, h * 0.62), face),
        _pill(RetroButton.select, 'SELECT', Offset(g / 2, h - pill.height / 2 - 12), pill),
        _pill(RetroButton.start, 'START', Offset(w - g / 2, h - pill.height / 2 - 12), pill),
      ];
    }
    final unit = math.min(w, h * 1.6) * scale;
    final dpad = unit * 0.40;
    final face = unit * 0.19;
    final pill = Size(unit * 0.22, unit * 0.085);
    final shoulder = Size(unit * 0.28, unit * 0.1);
    return [
      _pill(RetroButton.l, 'L', Offset(shoulder.width / 2 + 16, shoulder.height / 2 + 12), shoulder),
      _pill(RetroButton.r, 'R', Offset(w - shoulder.width / 2 - 16, shoulder.height / 2 + 12), shoulder),
      _dpad(Offset(dpad / 2 + w * 0.06, h * 0.48), dpad),
      _circle(RetroButton.a, 'A', Offset(w - face * 0.6 - w * 0.06, h * 0.40), face),
      _circle(RetroButton.b, 'B', Offset(w - face * 1.75 - w * 0.06, h * 0.56), face),
      _pill(RetroButton.select, 'SELECT', Offset(w / 2 - pill.width * 0.65, h - pill.height - 16), pill),
      _pill(RetroButton.start, 'START', Offset(w / 2 + pill.width * 0.65, h - pill.height - 16), pill),
    ];
  }

  /// Máscara combinada de todos los dedos.
  static int maskFor(Iterable<Offset> pointers, List<ControlRegion> regions) {
    var mask = 0;
    for (final point in pointers) {
      for (final region in regions) {
        mask |= region.hit(point);
      }
    }
    return mask;
  }

  /// Clave de personalización de un control. Los botones de cara de SNES
  /// (rombo A/B/X/Y) tienen su propio diseño: mover A en GBA no los deforma.
  static String overrideKey(String consoleId, String controlId) {
    // PSP tiene su propia distribución (joystick, cruceta más alta...): todos
    // sus controles se guardan aparte para no mover los de otras consolas.
    // La 3DS usa la misma distribución que la PSP, pero se guarda aparte.
    if (consoleId == 'psp' || consoleId == '3ds') return '$consoleId.$controlId';
    return const {'snes', 'psx', 'nds'}.contains(consoleId) && const {'a', 'b', 'x', 'y'}.contains(controlId)
        ? 'snes.$controlId'
        : controlId;
  }

  /// Aplica la personalización del usuario y mantiene cada control dentro del área.
  static List<ControlRegion> customize(
    List<ControlRegion> regions,
    Size area,
    Map<String, ControlOverride> overrides, {
    String consoleId = 'gba',
  }) =>
      [
        for (final r in regions)
          if (overrides[overrideKey(consoleId, r.id)] case final o?)
            _clamp(r.moved(
              r.center + Offset(o.dx * area.width, o.dy * area.height),
              r.size * o.scale,
            ), area)
          else
            r,
      ];

  static ControlRegion _clamp(ControlRegion r, Size area) {
    final hw = math.min(r.size.width / 2, area.width / 2);
    final hh = math.min(r.size.height / 2, area.height / 2);
    return r.moved(
      Offset(r.center.dx.clamp(hw, area.width - hw), r.center.dy.clamp(hh, area.height - hh)),
      r.size,
    );
  }

  static ControlRegion _dpad(Offset c, double d) =>
      ControlRegion(id: 'dpad', shape: ControlShape.dpad, center: c, size: Size(d, d));

  static ControlRegion _circle(int button, String label, Offset c, double d) =>
      ControlRegion(
        id: label.toLowerCase(),
        shape: ControlShape.circle,
        center: c,
        size: Size(d, d),
        button: button,
        label: label,
      );

  static ControlRegion _pill(int button, String label, Offset c, Size s) => ControlRegion(
      id: label.toLowerCase(), shape: ControlShape.pill, center: c, size: s, button: button, label: label);
}

/// Personalización de un control: desplazamiento relativo al área (fracciones
/// de ancho/alto, así sirve en cualquier tamaño de pantalla) y escala.
class ControlOverride {
  const ControlOverride({this.dx = 0, this.dy = 0, this.scale = 1});

  final double dx;
  final double dy;
  final double scale;

  ControlOverride copyWith({double? dx, double? dy, double? scale}) =>
      ControlOverride(dx: dx ?? this.dx, dy: dy ?? this.dy, scale: scale ?? this.scale);

  Map<String, double> toJson() => {'dx': dx, 'dy': dy, 's': scale};

  static ControlOverride fromJson(Map<String, dynamic> j) => ControlOverride(
        dx: ((j['dx'] as num?) ?? 0).toDouble().clamp(-1, 1),
        dy: ((j['dy'] as num?) ?? 0).toDouble().clamp(-1, 1),
        scale: ((j['s'] as num?) ?? 1).toDouble().clamp(0.5, 2),
      );
}
