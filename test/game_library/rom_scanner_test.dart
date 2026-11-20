import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/game_library/rom_scanner.dart';
import 'package:retrostation/storage/database.dart';

import '../support/test_env.dart';

void main() {
  test('detecta ROMs nuevos, ignora los ya conocidos y los duplicados', () async {
    final db = memoryDatabase();
    final paths = await tempPaths();
    addTearDown(() async {
      await db.close();
      await paths.root.delete(recursive: true);
    });

    File('test/fixtures/gba-tests/arm.gba').copySync(p.join(paths.roms.path, 'arm.gba'));
    File('test/fixtures/gba-tests/thumb.gba')
        .copySync(p.join(paths.roms.path, 'thumb.gba'));
    File(p.join(paths.roms.path, 'notas.txt')).writeAsStringSync('hola');

    final scanner = RomScanner(db, paths);
    final first = await scanner.scan();
    expect(first.added, hasLength(2));
    expect(first.rejected.single.reason, contains('Extensión'));

    final games = await db.select(db.games).get();
    expect(games.every((g) => g.status == GameStatus.installed), isTrue);
    expect(games.every((g) => g.sourceId == 'local'), isTrue);

    // Segunda pasada: nada nuevo.
    expect((await scanner.scan()).added, isEmpty);

    // Una copia con otro nombre es un duplicado (mismo SHA-1).
    File('test/fixtures/gba-tests/arm.gba')
        .copySync(p.join(paths.roms.path, 'arm (copia).gba'));
    final third = await scanner.scan();
    expect(third.added, isEmpty);
    expect(third.rejected.map((r) => r.reason), contains('Duplicado de un juego existente'));
  });
}
