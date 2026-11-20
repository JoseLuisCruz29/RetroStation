import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/emulation/emulator_session.dart';
import 'package:retrostation/engines/console.dart';
import 'package:retrostation/engines/console_registry.dart';
import 'package:retrostation/engines/core_options.dart';

void main() {
  final original = isArm32Process;
  tearDown(() => isArm32Process = original);

  test('en 64 bits la DS usa melonDS con sus opciones', () {
    isArm32Process = () => false;
    final nds = ConsoleRegistry.byId('nds')!;
    expect(nds.activeCore.library, 'libmelonds_libretro.so');
    final eff = CoreOptionsRepository.effective('nds', const {});
    expect(eff['melonds_touch_mode'], 'Touch');
    expect(eff.keys.where((k) => k.startsWith('desmume_')), isEmpty);
    expect(CoreOptions.forConsole('nds'), isEmpty);
  });

  test('en 32 bits la DS usa DeSmuME con JIT y salto de fotogramas', () {
    isArm32Process = () => true;
    final nds = ConsoleRegistry.byId('nds')!;
    expect(nds.activeCore.library, 'libdesmume2015_libretro.so');
    expect(nds.activeCore.license, 'GPL-2.0');
    final eff = CoreOptionsRepository.effective('nds', {'desmume_frameskip': '2'});
    expect(eff['desmume_cpu_mode'], 'jit');
    expect(eff['desmume_jit_block_size'], '100');
    expect(eff['desmume_pointer_type'], 'touch');
    expect(eff['desmume_frameskip'], '2');
    expect(eff['desmume_advanced_timing'], 'disabled');
    expect(eff.keys.where((k) => k.startsWith('melonds_')), isEmpty);
    // Las demás consolas no cambian de núcleo.
    expect(ConsoleRegistry.byId('gba')!.activeCore.library, 'libmgba_libretro.so');
  });

  group('partida de melonDS para DeSmuME', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rs_dsv'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('copia el .srm como .sav crudo y conserva el original', () async {
      final srm = File(p.join(dir.path, 'abc.srm'))..writeAsBytesSync([1, 2, 3, 4]);
      await EmulatorSession.migrateSaveForDesmume(
        saveDir: dir.path,
        romPath: '/roms/Pokemon Platino.nds',
        sramPath: srm.path,
      );
      expect(File(p.join(dir.path, 'Pokemon Platino.sav')).readAsBytesSync(), [1, 2, 3, 4]);
      expect(srm.existsSync(), isTrue);
    });

    test('no toca nada si DeSmuME ya tiene su partida', () async {
      final srm = File(p.join(dir.path, 'abc.srm'))..writeAsBytesSync([1, 2, 3, 4]);
      File(p.join(dir.path, 'juego.dsv')).writeAsBytesSync([9]);
      await EmulatorSession.migrateSaveForDesmume(
        saveDir: dir.path,
        romPath: '/roms/juego.nds',
        sramPath: srm.path,
      );
      expect(File(p.join(dir.path, 'juego.sav')).existsSync(), isFalse);
    });

    test('sin partida de melonDS no crea nada', () async {
      await EmulatorSession.migrateSaveForDesmume(
        saveDir: dir.path,
        romPath: '/roms/juego.nds',
        sramPath: p.join(dir.path, 'no_existe.srm'),
      );
      expect(dir.listSync(), isEmpty);
    });
  });
}
