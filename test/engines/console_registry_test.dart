import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/engines/console.dart';
import 'package:retrostation/engines/console_registry.dart';

void main() {
  test('ids únicos', () {
    final ids = ConsoleRegistry.all.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('cada extensión pertenece a una sola consola', () {
    final exts = ConsoleRegistry.all.expand((c) => c.extensions).toList();
    expect(exts.toSet().length, exts.length);
  });

  test('byExtension normaliza punto y mayúsculas', () {
    expect(ConsoleRegistry.byExtension('.GBA')?.id, 'gba');
    expect(ConsoleRegistry.byExtension('sfc')?.id, 'snes');
    // .exe = PS-X EXE (se valida la cabecera; un .exe de Windows se rechaza).
    expect(ConsoleRegistry.byExtension('exe')?.id, 'psx');
    expect(ConsoleRegistry.byExtension('dll'), isNull);
  });

  test('núcleos disponibles: mGBA para GBA/GB/GBC y FCEUmm para NES', () {
    for (final id in ['gba', 'gb', 'gbc']) {
      final c = ConsoleRegistry.byId(id)!;
      expect(c.coreLibrary, 'libmgba_libretro.so', reason: id);
      expect(c.status, CoreStatus.available);
    }
    expect(ConsoleRegistry.byId('nes')!.coreLibrary, 'libfceumm_libretro.so');
    expect(ConsoleRegistry.byId('snes')!.coreLibrary, 'libsnes9x_libretro.so');
    expect(ConsoleRegistry.byId('psx')!.coreLibrary, 'libpcsx_rearmed_libretro.so');
    expect(ConsoleRegistry.byId('nds')!.coreLibrary, 'libmelonds_libretro.so');
    expect(ConsoleRegistry.byId('genesis')!.coreLibrary, 'libgenesis_plus_gx_libretro.so');
    expect(ConsoleRegistry.byId('n64')!.coreLibrary, 'libmupen64plus_next_libretro.so');
    // GBA, GB, GBC, NES, SNES, Mega Drive, N64, PS1, NDS y PSP.
    expect(ConsoleRegistry.availableCount, 10);
  });

  test('toda consola disponible declara su biblioteca nativa', () {
    for (final c in ConsoleRegistry.all) {
      if (c.status == CoreStatus.available) expect(c.coreLibrary, isNotNull);
      // Lo que no está disponible explica por qué.
      if (c.status == CoreStatus.unavailable) expect(c.note, isNotNull);
    }
  });
}
