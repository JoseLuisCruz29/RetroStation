import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/controllers/touch_layout.dart';
import 'package:retrostation/engines/core_options.dart';
import 'package:retrostation/settings/app_settings.dart';

void main() {
  const area = Size(360, 420);

  test('mueve y escala un control y no toca los demás', () {
    final base = TouchLayout.gba(area, landscape: false);
    final custom = TouchLayout.customize(base, area, {
      'a': const ControlOverride(dx: -0.1, dy: 0.05, scale: 1.5),
    });
    final a0 = base.firstWhere((r) => r.id == 'a');
    final a1 = custom.firstWhere((r) => r.id == 'a');
    expect(a1.center.dx, closeTo(a0.center.dx - 36, 0.01));
    expect(a1.center.dy, closeTo(a0.center.dy + 21, 0.01));
    expect(a1.size.width, closeTo(a0.size.width * 1.5, 0.01));
    expect(custom.firstWhere((r) => r.id == 'b').center, base.firstWhere((r) => r.id == 'b').center);
  });

  test('mover A en GBA no deforma el rombo de SNES (y viceversa)', () {
    final snesBase = TouchLayout.forConsole('snes', area, landscape: false);
    final movedGba = TouchLayout.customize(snesBase, area,
        {'a': const ControlOverride(dy: -0.3)}, consoleId: 'snes');
    expect(movedGba.firstWhere((r) => r.id == 'a').center,
        snesBase.firstWhere((r) => r.id == 'a').center);

    final movedSnes = TouchLayout.customize(snesBase, area,
        {'snes.a': const ControlOverride(dx: -0.05)}, consoleId: 'snes');
    expect(movedSnes.firstWhere((r) => r.id == 'a').center.dx,
        lessThan(snesBase.firstWhere((r) => r.id == 'a').center.dx));

    // Los controles comunes (cruceta, L/R...) sí comparten diseño.
    final dpadMoved = TouchLayout.customize(snesBase, area,
        {'dpad': const ControlOverride(dx: 0.05)}, consoleId: 'snes');
    expect(dpadMoved.firstWhere((r) => r.id == 'dpad').center.dx,
        greaterThan(snesBase.firstWhere((r) => r.id == 'dpad').center.dx));
  });

  test('PSP tiene su propio diseño: se edita sin mover el de otras consolas', () {
    final pspBase = TouchLayout.forConsole('psp', area, landscape: false);
    // Un ajuste de GBA (sin prefijo) no afecta a PSP.
    final fromGba = TouchLayout.customize(pspBase, area,
        {'dpad': const ControlOverride(dx: 0.2), 'a': const ControlOverride(dy: -0.2)}, consoleId: 'psp');
    expect(fromGba.firstWhere((r) => r.id == 'dpad').center, pspBase.firstWhere((r) => r.id == 'dpad').center);
    expect(fromGba.firstWhere((r) => r.id == 'a').center, pspBase.firstWhere((r) => r.id == 'a').center);
    // El joystick de PSP se puede mover y escalar.
    final stickMoved = TouchLayout.customize(pspBase, area,
        {TouchLayout.overrideKey('psp', 'stick'): const ControlOverride(dx: 0.1, scale: 1.2)}, consoleId: 'psp');
    final s0 = pspBase.firstWhere((r) => r.id == 'stick');
    final s1 = stickMoved.firstWhere((r) => r.id == 'stick');
    expect(s1.center.dx, greaterThan(s0.center.dx));
    expect(s1.size.width, closeTo(s0.size.width * 1.2, 0.01));
  });

  test('un control arrastrado fuera del área se recoloca dentro', () {
    final custom = TouchLayout.customize(
      TouchLayout.gba(area, landscape: false),
      area,
      {'start': const ControlOverride(dx: 1, dy: 1)},
    );
    final start = custom.firstWhere((r) => r.id == 'start');
    expect((Offset.zero & area).contains(start.rect.bottomRight - const Offset(0.1, 0.1)), isTrue);
  });

  test('los identificadores son estables y únicos', () {
    final ids = TouchLayout.gba(area, landscape: false).map((r) => r.id).toList();
    expect(ids.toSet(), {'dpad', 'a', 'b', 'l', 'r', 'start', 'select'});
    expect(ids.toSet().length, ids.length);
  });

  test('el diseño personalizado se guarda y se recupera de los ajustes', () {
    const s = AppSettings(layoutLandscape: {'dpad': ControlOverride(dx: 0.2, dy: -0.1, scale: 1.2)});
    final back = AppSettings.fromMap(s.toMap());
    final o = back.layoutLandscape['dpad']!;
    expect(o.dx, closeTo(0.2, 1e-9));
    expect(o.dy, closeTo(-0.1, 1e-9));
    expect(o.scale, closeTo(1.2, 1e-9));
    expect(back.layoutPortrait, isEmpty);
    // Datos corruptos no rompen la app.
    expect(AppSettings.fromMap({'controls.layout.portrait': '{no json'}).layoutPortrait, isEmpty);
  });

  test('opciones de núcleo: solo se aplican valores válidos', () {
    final eff = CoreOptionsRepository.effective('gba', {
      'mgba_skip_bios': 'ON',
      'mgba_frameskip': '99', // valor no permitido
      'clave_desconocida': 'x',
    });
    expect(eff['mgba_skip_bios'], 'ON');
    // Un valor no permitido se sustituye por el predeterminado de la app.
    final frameskip = CoreOptions.forConsole('gba').firstWhere((o) => o.key == 'mgba_frameskip');
    expect(eff['mgba_frameskip'], frameskip.defaultValue);
    expect(eff.containsKey('clave_desconocida'), isFalse);
    expect(eff.length, CoreOptions.forConsole('gba').length);
    expect(CoreOptions.forConsole('psx'), isEmpty);
    for (final o in CoreOptions.forConsole('gba')) {
      expect(o.values.containsKey(o.defaultValue), isTrue, reason: o.key);
    }
  });
}
