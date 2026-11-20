import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/game_library/game_repository.dart';
import 'package:retrostation/game_library/rom_importer.dart';
import 'package:retrostation/storage/app_paths.dart';
import 'package:retrostation/storage/database.dart';

import '../support/test_env.dart';

void main() {
  late AppDatabase db;
  late AppPaths paths;
  late Directory incoming;
  late RomImporter importer;
  final arm = File('test/fixtures/gba-tests/arm.gba').readAsBytesSync();
  final thumb = File('test/fixtures/gba-tests/thumb.gba').readAsBytesSync();

  setUp(() async {
    db = memoryDatabase();
    paths = await tempPaths();
    incoming = Directory.systemTemp.createTempSync('rs_incoming_');
    importer = RomImporter(db, paths);
  });

  tearDown(() async {
    await db.close();
    await paths.root.delete(recursive: true);
    await incoming.delete(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final path = p.join(incoming.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  String zip(String name, Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((n, b) => archive.addFile(ArchiveFile.bytes(n, b)));
    return write(name, ZipEncoder().encode(archive));
  }

  List<String> romsOnDisk() =>
      paths.roms.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()..sort();

  test('importa un ROM suelto y lo registra como local', () async {
    final report = await importer.importFiles([write('Mi juego.gba', arm)]);
    expect(report.added, hasLength(1));
    final game = (await db.select(db.games).get()).single;
    expect(game.title, 'Mi juego');
    expect(game.sourceId, 'local');
    expect(romsOnDisk(), ['Mi juego.gba']);
  });

  test('extrae solo los ROMs de un ZIP e ignora el resto', () async {
    final report = await importer.importFiles([
      zip('pack.zip', {'juegos/arm.gba': arm, 'thumb.gba': thumb, 'leeme.txt': [1, 2, 3]}),
    ]);
    expect(report.added, hasLength(2));
    expect(romsOnDisk(), ['arm.gba', 'thumb.gba']);
  });

  test('zip-slip: una entrada con ../ no puede escribir fuera de roms/', () async {
    final report = await importer.importFiles([
      zip('malicioso.zip', {'../../../evil.gba': arm}),
    ]);
    expect(report.added, hasLength(1));
    expect(romsOnDisk(), ['evil.gba']);
    expect(File(p.join(paths.root.path, 'evil.gba')).existsSync(), isFalse);
    expect(File(p.join(paths.root.parent.path, 'evil.gba')).existsSync(), isFalse);
  });

  test('rechaza duplicados, ROMs falsos, ZIP dañados y ZIP sin ROMs', () async {
    await importer.importFiles([write('arm.gba', arm)]);
    final report = await importer.importFiles([
      write('copia.gba', arm),
      write('falso.gba', List.filled(4096, 0x41)),
      write('roto.zip', [0x50, 0x4B, 0x03, 0x04, 1, 2, 3]),
      zip('vacio.zip', {'leeme.txt': [1]}),
      write('programa.exe', [0x4D, 0x5A]),
    ]);
    expect(report.added, isEmpty);
    final reasons = {for (final (name, reason) in report.rejected) name: reason};
    expect(reasons['copia.gba'], 'Ya está en tu biblioteca');
    expect(reasons['falso.gba'], contains('Cabecera'));
    expect(reasons['roto.zip'], anyOf(contains('dañado'), contains('ZIP')));
    expect(reasons['vacio.zip'], contains('no contiene ROMs'));
    // Un .exe de Windows ("MZ") no es un programa de PlayStation.
    expect(reasons['programa.exe'], contains('PS-X EXE'));
    // Ningún resto en disco: solo el original.
    expect(romsOnDisk(), ['arm.gba']);
  });

  test('nombres repetidos con distinto contenido no se sobrescriben', () async {
    await importer.importFiles([write('juego.gba', arm)]);
    final other = Directory.systemTemp.createTempSync('rs_other_');
    addTearDown(() => other.delete(recursive: true));
    final path = p.join(other.path, 'juego.gba');
    File(path).writeAsBytesSync(thumb);
    final report = await importer.importFiles([path]);
    expect(report.added, hasLength(1));
    expect(romsOnDisk(), ['juego (2).gba', 'juego.gba']);
  });

  group('PlayStation', () {
    // Pista de datos mínima: 16 sectores de 2352 bytes.
    final bin = List.filled(2352 * 16, 7);
    const cue = 'FILE "Juego (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n';

    test('un .cue con su .bin se importa junto en su propia carpeta', () async {
      final report = await importer.importFiles([
        write('Juego.cue', utf8.encode(cue)),
        write('Juego (Track 1).bin', bin),
      ]);
      expect(report.added, hasLength(1), reason: '${report.rejected}');
      final game = (await db.select(db.games).get()).single;
      expect(game.consoleId, 'psx');
      expect(p.basename(p.dirname(game.romPath!)), 'Juego');
      expect(File(p.join(p.dirname(game.romPath!), 'Juego (Track 1).bin')).existsSync(), isTrue);
      expect(game.fileSize, cue.length + bin.length);
    });

    test('un .cue sin sus pistas se rechaza y no deja nada', () async {
      final report = await importer.importFiles([write('Solo.cue', utf8.encode(cue))]);
      expect(report.added, isEmpty);
      expect(report.rejected.single.$2, contains('Falta'));
      expect(paths.roms.listSync(), isEmpty);
    });

    test('un .bin suelto se rechaza con un motivo claro', () async {
      final report = await importer.importFiles([write('pista.bin', bin)]);
      expect(report.rejected.single.$2, contains('sin su .cue'));
    });

    test('un .cue no puede referenciar archivos fuera de su carpeta', () async {
      final evil = 'FILE "../../secreto.bin" BINARY\n';
      final report = await importer.importFiles([write('Malo.cue', utf8.encode(evil))]);
      expect(report.added, isEmpty);
      expect(paths.roms.listSync(), isEmpty);
    });

    test('el programa PS-X EXE de prueba se acepta', () async {
      final exe = File('test/fixtures/psx/retrostation-gpu-test.exe').readAsBytesSync();
      final report = await importer.importFiles([write('gpu-test.exe', exe)]);
      expect(report.added, hasLength(1));
      expect((await db.select(db.games).get()).single.consoleId, 'psx');
    });

    test('borrar un juego de varias pistas elimina su carpeta', () async {
      await importer.importFiles([
        write('Disco.cue', utf8.encode(cue)),
        write('Juego (Track 1).bin', bin),
      ]);
      final game = (await db.select(db.games).get()).single;
      await GameRepository(db).delete(game, paths, deleteSaves: true);
      expect(Directory(p.dirname(game.romPath!)).existsSync(), isFalse);
    });
  });

  group('attachDownload (descargas)', () {
    Future<int> pending() => db.into(db.games).insert(GamesCompanion.insert(
          title: 'Pendiente',
          consoleId: 'gba',
          status: GameStatus.downloading,
        ));

    test('completa el juego pendiente con el ROM descargado (también en ZIP)', () async {
      final id = await pending();
      final error = await importer.attachDownload(id, zip('descarga.zip', {'juego.gba': arm}));
      expect(error, isNull);
      final game = await (db.select(db.games)..where((g) => g.id.equals(id))).getSingle();
      expect(game.status, GameStatus.installed);
      expect(game.romPath, endsWith('juego.gba'));
      expect(game.sha1, hasLength(40));
    });

    test('rechaza un hash que no coincide y no deja archivos', () async {
      final id = await pending();
      final error = await importer.attachDownload(id, write('x.gba', arm), expectedSha1: '0' * 40);
      expect(error, contains('hash'));
      expect(romsOnDisk(), isEmpty);
    });

    test('rechaza descargas corruptas o que ya tienes', () async {
      await importer.importFiles([write('arm.gba', arm)]);
      final id = await pending();
      expect(await importer.attachDownload(id, write('dup.gba', arm)), contains('Ya tienes'));
      expect(await importer.attachDownload(id, write('roto.gba', List.filled(512, 7))), isNotNull);
      expect(romsOnDisk(), ['arm.gba']);
    });
  });

  group('juegos grandes (límite 10 GB)', () {
    /// CHD de PlayStation de [mb] MB: cabecera real y el resto a cero (el
    /// archivo es disperso, no ocupa disco de verdad).
    String bigChd(String name, int mb) {
      final path = p.join(incoming.path, name);
      final raf = File(path).openSync(mode: FileMode.write);
      raf.writeFromSync(ascii.encode('MComprHD'));
      raf.setPositionSync(mb * 1024 * 1024 - 1);
      raf.writeByteSync(0);
      raf.closeSync();
      return path;
    }

    test('acepta un archivo de 100 MB (antes el límite era 64 MB)', () async {
      final report = await importer.importFiles([bigChd('Disco grande.chd', 100)]);
      expect(report.rejected, isEmpty);
      final game = (await db.select(db.games).get()).single;
      expect(game.fileSize, 100 * 1024 * 1024);
    });

    test('sin moveSources el original se queda donde estaba', () async {
      final src = bigChd('original.chd', 2);
      await importer.importFiles([src]);
      expect(File(src).existsSync(), isTrue);
    });

    test('con moveSources la copia temporal se mueve (no ocupa el doble)', () async {
      final src = bigChd('temporal.chd', 2);
      final report = await importer.importFiles([src], moveSources: true);
      expect(report.added, hasLength(1));
      expect(File(src).existsSync(), isFalse);
      expect(romsOnDisk(), ['temporal.chd']);
    });

    test('ZIP extraído por bloques a disco; entradas con el mismo nombre no se pisan',
        () async {
      final report = await importer.importFiles([
        zip('pack.zip', {'a/arm.gba': arm, 'b/thumb.gba': thumb, 'c/arm.gba': thumb}),
      ]);
      // 'c/arm.gba' tiene el mismo contenido que 'b/thumb.gba': duplicado.
      expect(report.added, hasLength(2));
      expect(romsOnDisk(), ['arm.gba', 'thumb.gba']);
      // La carpeta temporal de extracción no queda en disco.
      expect(Directory(p.join(paths.root.path, '.import_tmp')).existsSync(), isFalse);
    });

    test('el ZIP del que se importa no se borra', () async {
      final src = zip('mio.zip', {'arm.gba': arm});
      await importer.importFiles([src]);
      expect(File(src).existsSync(), isTrue);
    });
  });

  test('sanitizeFileName elimina rutas y caracteres peligrosos', () {
    expect(sanitizeFileName('../../a/b\\c.gba'), 'c.gba');
    expect(sanitizeFileName('a:b*c?.gba'), 'a_b_c_.gba');
    expect(sanitizeFileName('..'), 'rom');
  });
}
