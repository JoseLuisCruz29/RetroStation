import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/game_library/rom_inspector.dart';

const _fixtures = 'test/fixtures/gba-tests';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('rs_rom_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  for (final name in ['arm.gba', 'thumb.gba', 'memory.gba', 'bios.gba']) {
    test('acepta el ROM real $name', () {
      final result = RomInspector.inspect(p.join(_fixtures, name));
      expect(result, isA<ValidRom>(), reason: (result as dynamic).toString());
      final rom = result as ValidRom;
      expect(rom.consoleId, 'gba');
      expect(rom.sha1, hasLength(40));
      expect(rom.title, p.basenameWithoutExtension(name));
    });
  }

  test('rechaza un ROM con la cabecera alterada', () {
    final bytes = File(p.join(_fixtures, 'arm.gba')).readAsBytesSync();
    bytes[0xA0] ^= 0xFF; // cambia el título sin recalcular el checksum
    final path = p.join(tmp.path, 'roto.gba');
    File(path).writeAsBytesSync(bytes);
    final result = RomInspector.inspect(path);
    expect(result, isA<RejectedRom>());
    expect((result as RejectedRom).reason, contains('Checksum'));
  });

  test('rechaza archivos demasiado pequeños y extensiones desconocidas', () {
    final small = p.join(tmp.path, 'x.gba');
    File(small).writeAsBytesSync(Uint8List(16));
    expect(RomInspector.inspect(small), isA<RejectedRom>());

    final dll = p.join(tmp.path, 'virus.dll');
    File(dll).writeAsBytesSync(Uint8List(1024));
    expect(
      (RomInspector.inspect(dll) as RejectedRom).reason,
      contains('Extensión'),
    );
    // Un ejecutable de Windows con extensión .exe tampoco pasa (no es PS-X EXE).
    final exe = p.join(tmp.path, 'virus.exe');
    File(exe).writeAsBytesSync([0x4D, 0x5A, ...Uint8List(4096)]);
    expect((RomInspector.inspect(exe) as RejectedRom).reason, contains('PS-X EXE'));
  });

  test('rechaza un archivo cualquiera renombrado a .gba', () {
    final path = p.join(tmp.path, 'foto.gba');
    File(path).writeAsBytesSync(Uint8List(4096)..fillRange(0, 4096, 0x41));
    expect(RomInspector.inspect(path), isA<RejectedRom>());
  });

  test('Mega Drive: acepta "SEGA" en la cabecera y rechaza otros archivos', () {
    final rom = Uint8List(0x20000);
    rom.setAll(0x100, 'SEGA MEGA DRIVE '.codeUnits);
    final good = File(p.join(tmp.path, 'Juego (USA).md'))..writeAsBytesSync(rom);
    final result = RomInspector.inspect(good.path);
    expect(result, isA<ValidRom>(), reason: result.toString());
    expect((result as ValidRom).consoleId, 'genesis');
    expect(result.title, 'Juego (USA)');

    final bad = File(p.join(tmp.path, 'falso.gen'))..writeAsBytesSync(Uint8List(0x20000));
    expect(RomInspector.inspect(bad.path), isA<RejectedRom>());
    // .smd (entrelazado): solo se comprueba el tamaño.
    final smd = File(p.join(tmp.path, 'otro.smd'))..writeAsBytesSync(Uint8List(0x20200));
    expect(RomInspector.inspect(smd.path), isA<ValidRom>());
  });

  test('SNES: acepta ROMs reales (con y sin cabecera de copiadora) y rechaza falsos', () {
    for (final name in ['inidisp_brightness_delay.sfc', 'hdma-2100-glitch.sfc']) {
      final r = RomInspector.inspect(p.join('test/fixtures/snes-test-roms', name));
      expect(r, isA<ValidRom>(), reason: name);
      expect((r as ValidRom).consoleId, 'snes');
    }
    // Mismo ROM con 512 bytes de cabecera de copiadora delante.
    final raw = File('test/fixtures/snes-test-roms/hdma-2100-glitch.sfc').readAsBytesSync();
    final smc = p.join(tmp.path, 'copiadora.smc');
    File(smc).writeAsBytesSync([...List.filled(512, 0), ...raw]);
    expect(RomInspector.inspect(smc), isA<ValidRom>());

    final fake = p.join(tmp.path, 'falso.sfc');
    File(fake).writeAsBytesSync(Uint8List(0x10000));
    expect((RomInspector.inspect(fake) as RejectedRom).reason, contains('SNES'));
  });

  test('Nintendo DS: CRC de cabecera con un .nds real y uno alterado', () {
    final real = RomInspector.inspect('test/fixtures/nds/GodMode9i.nds');
    expect(real, isA<ValidRom>());
    expect((real as ValidRom).consoleId, 'nds');

    final bytes = File('test/fixtures/nds/GodMode9i.nds').readAsBytesSync();
    bytes[0x00] ^= 0xFF; // título alterado sin recalcular el CRC
    final bad = p.join(tmp.path, 'alterado.nds');
    File(bad).writeAsBytesSync(bytes);
    expect((RomInspector.inspect(bad) as RejectedRom).reason, contains('CRC'));
  });

  test('una ISO de PSP demasiado pequeña se rechaza con su motivo', () {
    final path = p.join(tmp.path, 'juego.iso');
    File(path).writeAsBytesSync(Uint8List(1024));
    expect(
      (RomInspector.inspect(path) as RejectedRom).reason,
      contains('demasiado pequeño'),
    );
  });

  test('Game Boy: checksum de cabecera y detección de GBC', () {
    Uint8List gbRom({required int cgbFlag}) {
      final b = Uint8List(0x8000);
      final title = 'PRUEBA'.codeUnits;
      b.setRange(0x134, 0x134 + title.length, title);
      b[0x143] = cgbFlag;
      var x = 0;
      for (var i = 0x134; i <= 0x14C; i++) {
        x = (x - b[i] - 1) & 0xFF;
      }
      b[0x14D] = x;
      return b;
    }

    final gb = p.join(tmp.path, 'mono.gb');
    File(gb).writeAsBytesSync(gbRom(cgbFlag: 0));
    expect((RomInspector.inspect(gb) as ValidRom).consoleId, 'gb');

    // Juego de GBC aunque tenga extensión .gb: manda la cabecera.
    final gbc = p.join(tmp.path, 'color.gb');
    File(gbc).writeAsBytesSync(gbRom(cgbFlag: 0xC0));
    expect((RomInspector.inspect(gbc) as ValidRom).consoleId, 'gbc');

    final broken = gbRom(cgbFlag: 0)..[0x14D] ^= 0xFF;
    final bad = p.join(tmp.path, 'roto.gb');
    File(bad).writeAsBytesSync(broken);
    expect((RomInspector.inspect(bad) as RejectedRom).reason, contains('Checksum'));
  });

  test('NES: cabecera iNES y tamaño coherente', () {
    Uint8List nes({int prgBanks = 2, int chrBanks = 1, int? length}) {
      final size = length ?? 16 + prgBanks * 16384 + chrBanks * 8192;
      return Uint8List(size)
        ..setRange(0, 4, [0x4E, 0x45, 0x53, 0x1A])
        ..[4] = prgBanks
        ..[5] = chrBanks;
    }

    final ok = p.join(tmp.path, 'juego.nes');
    File(ok).writeAsBytesSync(nes());
    expect(RomInspector.inspect(ok), isA<ValidRom>());

    final cut = p.join(tmp.path, 'cortado.nes');
    File(cut).writeAsBytesSync(nes(length: 20000));
    expect((RomInspector.inspect(cut) as RejectedRom).reason, contains('más pequeño'));

    final fake = p.join(tmp.path, 'falso.nes');
    File(fake).writeAsBytesSync(Uint8List(40000));
    expect((RomInspector.inspect(fake) as RejectedRom).reason, contains('iNES'));
  });
}
