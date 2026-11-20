import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';
import 'rom_inspector.dart';

class ScanResult {
  const ScanResult({required this.added, required this.rejected});

  final List<String> added;
  final List<RejectedRom> rejected;
}

/// Detecta automáticamente los ROMs que hay en la carpeta privada `roms/` y
/// que todavía no están en la biblioteca. Valida cabecera y calcula el SHA-1
/// en un isolate para no bloquear la interfaz.
class RomScanner {
  RomScanner(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;

  Future<ScanResult> scan() async {
    final known = {
      for (final g in await _db.select(_db.games).get())
        if (g.romPath != null) g.romPath!,
    };
    final knownHashes = {
      for (final g in await _db.select(_db.games).get())
        if (g.sha1 != null) g.sha1!,
    };
    final inspections =
        await compute(_inspectNewFiles, (dir: _paths.roms.path, known: known));

    final added = <String>[];
    final rejected = <RejectedRom>[];
    for (final result in inspections) {
      switch (result) {
        case RejectedRom():
          rejected.add(result);
        case ValidRom():
          if (!_paths.contains(result.path)) {
            rejected.add(RejectedRom(result.path, 'Ruta fuera del almacenamiento'));
          } else if (knownHashes.contains(result.sha1)) {
            rejected.add(RejectedRom(result.path, 'Duplicado de un juego existente'));
          } else {
            await _db.into(_db.games).insert(GamesCompanion.insert(
                  title: result.title,
                  consoleId: result.consoleId,
                  status: GameStatus.installed,
                  romPath: Value(result.path),
                  sha1: Value(result.sha1),
                  fileSize: Value(result.size),
                  sourceId: const Value('local'),
                ));
            knownHashes.add(result.sha1);
            added.add(result.title);
          }
      }
    }
    return ScanResult(added: added, rejected: rejected);
  }
}

/// Se ejecuta en otro isolate: solo recibe datos enviables.
List<RomInspection> _inspectNewFiles(({String dir, Set<String> known}) args) {
  final root = Directory(args.dir);
  if (!root.existsSync()) return const [];
  return [
    for (final entity in root.listSync(followLinks: false))
      if (entity is File &&
          !entity.path.endsWith('.tmp') &&
          !args.known.contains(entity.path))
        RomInspector.inspect(entity.path),
  ];
}

final romScannerProvider = Provider<RomScanner>(
  (ref) => RomScanner(ref.watch(databaseProvider), ref.watch(appPathsProvider)),
);
