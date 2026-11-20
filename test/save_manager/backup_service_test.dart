import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/save_manager/backup_service.dart';
import 'package:retrostation/storage/database.dart';

import '../support/test_env.dart';

void main() {
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('exporta y restaura partidas y save states en otra instalación', () async {
    // Instalación A con una partida y un save state.
    final dbA = memoryDatabase();
    final pathsA = await tempPaths();
    addTearDown(() async {
      await dbA.close();
      await pathsA.root.delete(recursive: true);
    });
    final gameA = await dbA.into(dbA.games).insert(GamesCompanion.insert(
        title: 'Juego', consoleId: 'gba', status: GameStatus.installed, sha1: const Value(sha)));
    File(p.join(pathsA.saves.path, '$sha.srm')).writeAsBytesSync([1, 2, 3]);
    final stateDir = Directory(p.join(pathsA.states.path, sha))..createSync();
    File(p.join(stateDir.path, 'slot2.state')).writeAsBytesSync([9, 9]);
    File(p.join(stateDir.path, 'slot2.png')).writeAsBytesSync([0x89, 0x50]);
    File(p.join(stateDir.path, 'slot2.state.bak')).writeAsBytesSync([0]); // no se exporta
    await dbA.into(dbA.saveStates).insert(SaveStatesCompanion.insert(
        gameId: gameA, slot: 2, filePath: p.join(stateDir.path, 'slot2.state')));

    final (bytes, exported) = await BackupService(dbA, pathsA).export();
    expect(exported.saves, 1);
    expect(exported.states, 1);
    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();
    expect(names, {
      BackupService.manifestName,
      'saves/$sha.srm',
      'states/$sha/slot2.state',
      'states/$sha/slot2.png',
    });

    // Instalación B con el mismo juego (mismo SHA-1) pero sin partidas.
    final dbB = memoryDatabase();
    final pathsB = await tempPaths();
    addTearDown(() async {
      await dbB.close();
      await pathsB.root.delete(recursive: true);
    });
    final gameB = await dbB.into(dbB.games).insert(GamesCompanion.insert(
        title: 'Juego', consoleId: 'gba', status: GameStatus.installed, sha1: const Value(sha)));
    final zip = File(p.join(pathsB.root.path, 'copia.zip'))..writeAsBytesSync(bytes);

    final report = await BackupService(dbB, pathsB).import(zip.path);
    expect(report.saves, 1);
    expect(report.states, 1);
    expect(File(p.join(pathsB.saves.path, '$sha.srm')).readAsBytesSync(), [1, 2, 3]);
    final row = await dbB.select(dbB.saveStates).getSingle();
    expect(row.gameId, gameB);
    expect(row.slot, 2);
    expect(row.thumbnailPath, isNotNull);
  });

  test('una copia maliciosa no puede escribir fuera de saves/ y states/', () async {
    final db = memoryDatabase();
    final paths = await tempPaths();
    addTearDown(() async {
      await db.close();
      await paths.root.delete(recursive: true);
    });
    final archive = Archive()
      ..addFile(ArchiveFile.string(BackupService.manifestName, jsonEncode({'app': 'RetroStation', 'states': []})))
      ..addFile(ArchiveFile.bytes('../../evil.srm', [1]))
      ..addFile(ArchiveFile.bytes('saves/../../evil2.srm', [1]))
      ..addFile(ArchiveFile.bytes('roms/juego.gba', [1]))
      ..addFile(ArchiveFile.bytes('states/$sha/slot9.state', [1]));
    final zip = File(p.join(paths.root.path, 'mala.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final report = await BackupService(db, paths).import(zip.path);
    expect(report.saves, 0);
    expect(report.skipped, 4);
    expect(paths.roms.listSync(), isEmpty);
    expect(File(p.join(paths.root.parent.path, 'evil.srm')).existsSync(), isFalse);
  });

  test('rechaza archivos que no son copias de RetroStation', () async {
    final db = memoryDatabase();
    final paths = await tempPaths();
    addTearDown(() async {
      await db.close();
      await paths.root.delete(recursive: true);
    });
    final zip = File(p.join(paths.root.path, 'otro.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('a.txt', [1]))));
    expect(() => BackupService(db, paths).import(zip.path), throwsA(isA<FormatException>()));
  });
}
