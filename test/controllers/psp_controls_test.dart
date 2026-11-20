import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold, SizedBox;
import 'package:path/path.dart' as p;
import 'package:retrostation/controllers/touch_layout.dart';
import 'package:retrostation/engines/console_registry.dart';
import 'package:retrostation/game_library/rom_inspector.dart';
import 'package:retrostation/presentation/player/touch_controls.dart';

/// Solapamiento real: círculo con círculo por distancia; lo demás por caja
/// (la cruceta y el joystick son redondos: se usa su círculo inscrito).
bool _overlap(ControlRegion a, ControlRegion b) {
  bool round(ControlRegion r) => r.shape != ControlShape.pill;
  if (round(a) && round(b)) {
    return (a.center - b.center).distance < a.size.width / 2 + b.size.width / 2;
  }
  return a.rect.overlaps(b.rect);
}

void main() {
  group('controles de PSP', () {
    for (final landscape in [false, true]) {
      final area = landscape ? const Size(780, 360) : const Size(360, 330);
      test('joystick, cruceta y botones sin solaparse (${landscape ? 'horizontal' : 'vertical'})', () {
        final regions = TouchLayout.forConsole('psp', area, landscape: landscape);
        final ids = regions.map((r) => r.id).toList();
        expect(ids, containsAll(['stick', 'dpad', 'a', 'b', 'x', 'y', 'l', 'r', 'start', 'select']));
        expect(ids.toSet().length, ids.length, reason: 'identificadores únicos');
        // Ningún control tapa a otro (en horizontal, SELECT tapaba ✕).
        for (var i = 0; i < regions.length; i++) {
          for (var j = i + 1; j < regions.length; j++) {
            expect(_overlap(regions[i], regions[j]), isFalse,
                reason: '${regions[i].id} tapa ${regions[j].id}');
          }
        }
        for (final r in regions) {
          expect(Offset.zero & area, predicate<Rect>((a) => a.inflate(1).contains(r.rect.center)),
              reason: '${r.id} fuera del área');
        }
      });
    }

    test('el joystick da un vector normalizado y cero al soltar', () {
      final regions = TouchLayout.forConsole('psp', const Size(360, 330), landscape: false);
      final stick = regions.firstWhere((r) => r.id == 'stick');
      final radius = stick.size.width / 2;
      expect(TouchLayout.analogFor([], regions), Offset.zero);
      final right = TouchLayout.analogFor([stick.center + Offset(radius, 0)], regions);
      expect(right.dx, closeTo(1, 1e-9));
      expect(right.dy, closeTo(0, 1e-9));
      final half = TouchLayout.analogFor([stick.center + Offset(0, -radius * 0.375)], regions);
      expect(half.dy, closeTo(-0.5, 1e-9));
      // El joystick no produce botones.
      expect(TouchLayout.maskFor([stick.center], regions), 0);
    });

    testWidgets('arrastrar el dedo fuera de la rueda no suelta el joystick', (tester) async {
      const area = Size(360, 330);
      final analog = <Offset>[];
      final masks = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: area.width,
            height: area.height,
            child: TouchControls(
              consoleId: 'psp',
              landscape: false,
              opacity: 0.55,
              scale: 1,
              haptics: false,
              onMaskChanged: masks.add,
              onAnalogChanged: analog.add,
            ),
          ),
        ),
      ));
      final regions = TouchLayout.forConsole('psp', area, landscape: false);
      final stick = regions.firstWhere((r) => r.id == 'stick');
      final dpad = regions.firstWhere((r) => r.id == 'dpad');
      final origin = tester.getTopLeft(find.byType(TouchControls));

      final gesture = await tester.startGesture(origin + stick.center);
      // Hacia arriba, cruzando la cruceta, y muy lejos de la rueda.
      await gesture.moveTo(origin + dpad.center);
      await tester.pump();
      expect(analog.last.distance, closeTo(1, 1e-9), reason: 'sigue al tope fuera de la rueda');
      expect(analog.last.dy, lessThan(0), reason: 'en la dirección del dedo');
      expect(masks.where((m) => m != 0), isEmpty, reason: 'no pulsa la cruceta al pasar');

      await gesture.up();
      await tester.pump();
      expect(analog.last, Offset.zero, reason: 'al levantar el dedo vuelve al centro');
    });

    test('las demás consolas no tienen joystick', () {
      for (final id in ['gba', 'nds', 'psx', 'snes']) {
        final regions = TouchLayout.forConsole(id, const Size(360, 330), landscape: false);
        expect(regions.where((r) => r.shape == ControlShape.stick), isEmpty, reason: id);
      }
    });
  });

  group('imágenes de PSP', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rs_psp'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, Uint8List bytes) => File(p.join(dir.path, name))..writeAsBytesSync(bytes);

    test('acepta una ISO 9660 y la asigna a PSP', () {
      final data = Uint8List(0x9000);
      data.setAll(0x8001, 'CD001'.codeUnits);
      final r = RomInspector.inspect(write('Juego (Europa).iso', data).path);
      expect(r, isA<ValidRom>());
      expect((r as ValidRom).consoleId, 'psp');
      expect(ConsoleRegistry.byId('psp')!.activeCore.library, 'libppsspp_libretro.so');
    });

    test('acepta un CSO por su cabecera', () {
      final data = Uint8List(64)..setAll(0, 'CISO'.codeUnits);
      expect(RomInspector.inspect(write('juego.cso', data).path), isA<ValidRom>());
    });

    test('rechaza archivos que no son imágenes de disco', () {
      expect(RomInspector.inspect(write('falso.iso', Uint8List(0x9000)).path), isA<RejectedRom>());
      expect(RomInspector.inspect(write('falso.cso', Uint8List(64)).path), isA<RejectedRom>());
      expect(RomInspector.inspect(write('corto.iso', Uint8List(100)).path), isA<RejectedRom>());
    });
  });
}
