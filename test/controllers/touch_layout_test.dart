import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/controllers/touch_layout.dart';
import 'package:retrostation/emulation/native_bindings.dart';

int bit(int b) => 1 << b;

void main() {
  for (final landscape in [false, true]) {
    // Teléfono de 800x360 dp en horizontal; franja inferior típica en vertical.
    final area = landscape ? const Size(800, 360) : const Size(360, 420);
    final regions = TouchLayout.gba(area, landscape: landscape);
    ControlRegion find(int? button, [ControlShape? shape]) => regions.firstWhere(
        (r) => shape != null ? r.shape == shape : r.button == button);
    final mode = landscape ? 'horizontal' : 'vertical';

    if (landscape) {
      test('horizontal: ningún control invade la zona central de la imagen', () {
        final g = TouchLayout.defaultGutter(area);
        final game = Rect.fromLTRB(g, 0, area.width - g, area.height);
        for (final r in regions) {
          expect(r.rect.overlaps(game), isFalse, reason: '${r.label} tapa la imagen');
        }
      });
    }

    test('$mode: todos los controles caben en el área y no se solapan', () {
      final bounds = Offset.zero & area;
      for (final r in regions) {
        expect(bounds.contains(r.rect.topLeft) && bounds.contains(r.rect.bottomRight), isTrue,
            reason: '${r.label} fuera del área: ${r.rect}');
      }
      for (var i = 0; i < regions.length; i++) {
        for (var j = i + 1; j < regions.length; j++) {
          expect(regions[i].rect.overlaps(regions[j].rect), isFalse,
              reason: '${regions[i].label} se solapa con ${regions[j].label}');
        }
      }
    });

    test('$mode: cada botón responde en su centro', () {
      for (final b in [RetroButton.a, RetroButton.b, RetroButton.l, RetroButton.r,
                       RetroButton.start, RetroButton.select]) {
        expect(TouchLayout.maskFor([find(b).center], regions), bit(b));
      }
    });

    test('$mode: cruceta con diagonales y zona muerta central', () {
      final dpad = find(null, ControlShape.dpad);
      final r = dpad.size.width / 2;
      final c = dpad.center;
      expect(TouchLayout.maskFor([c + Offset(0, -r * 0.8)], regions), bit(RetroButton.up));
      expect(TouchLayout.maskFor([c + Offset(r * 0.8, 0)], regions), bit(RetroButton.right));
      expect(TouchLayout.maskFor([c + Offset(-r * 0.6, r * 0.6)], regions),
          bit(RetroButton.left) | bit(RetroButton.down));
      expect(TouchLayout.maskFor([c], regions), 0);
    });

    test('$mode: varios dedos a la vez se combinan', () {
      final dpad = find(null, ControlShape.dpad);
      final mask = TouchLayout.maskFor([
        dpad.center + Offset(dpad.size.width * 0.4, 0),
        find(RetroButton.a).center,
        find(RetroButton.b).center,
      ], regions);
      expect(mask, bit(RetroButton.right) | bit(RetroButton.a) | bit(RetroButton.b));
    });
  }

  for (final landscape in [false, true]) {
    test('SNES ${landscape ? 'horizontal' : 'vertical'}: A/B/X/Y en rombo, sin solapes y dentro', () {
      final area = landscape ? const Size(800, 360) : const Size(360, 420);
      final regions = TouchLayout.forConsole('snes', area, landscape: landscape);
      expect(regions.map((r) => r.id).toSet(),
          {'dpad', 'a', 'b', 'x', 'y', 'l', 'r', 'start', 'select'});
      final bounds = Offset.zero & area;
      for (final r in regions) {
        expect(bounds.contains(r.rect.topLeft) && bounds.contains(r.rect.bottomRight), isTrue,
            reason: '${r.id} fuera del área');
      }
      bool overlap(ControlRegion p, ControlRegion q) {
        if (p.shape == ControlShape.circle && q.shape == ControlShape.circle) {
          // Círculos: lo que cuenta es la distancia entre centros.
          return (p.center - q.center).distance < (p.size.width + q.size.width) / 2;
        }
        return p.rect.overlaps(q.rect);
      }

      for (var i = 0; i < regions.length; i++) {
        for (var j = i + 1; j < regions.length; j++) {
          expect(overlap(regions[i], regions[j]), isFalse,
              reason: '${regions[i].id} se solapa con ${regions[j].id}');
        }
      }
      final byId = {for (final r in regions) r.id: r};
      // Entre A y B (diagonal del rombo) un toque no pulsa los dos a la vez.
      final between = (byId['a']!.center + byId['b']!.center) / 2;
      final both = bit(RetroButton.a) | bit(RetroButton.b);
      expect(TouchLayout.maskFor([between], regions) & both, isNot(both));
      expect(byId['x']!.center.dy, lessThan(byId['b']!.center.dy)); // X arriba, B abajo
      expect(byId['y']!.center.dx, lessThan(byId['a']!.center.dx)); // Y izquierda, A derecha
      expect(TouchLayout.maskFor([byId['x']!.center], regions), bit(RetroButton.x));
      expect(TouchLayout.maskFor([byId['y']!.center], regions), bit(RetroButton.y));
    });
  }

  test('GB, GBC y NES no tienen gatillos L/R', () {
    for (final c in ['gb', 'gbc', 'nes']) {
      final ids = TouchLayout.forConsole(c, const Size(360, 420), landscape: false).map((r) => r.id);
      expect(ids, isNot(contains('l')));
      expect(ids, isNot(contains('r')));
    }
  });

  test('el tamaño escala los controles', () {
    final small = TouchLayout.gba(const Size(360, 420), landscape: false, scale: 0.7);
    final big = TouchLayout.gba(const Size(360, 420), landscape: false, scale: 1.3);
    expect(big.first.size.width, greaterThan(small.first.size.width));
  });

  test('un toque fuera de los controles no pulsa nada', () {
    final regions = TouchLayout.gba(const Size(360, 420), landscape: false);
    // Centro superior: entre L y R, lejos de la cruceta y de A/B.
    expect(TouchLayout.maskFor([const Offset(180, 30)], regions), 0);
  });
}
