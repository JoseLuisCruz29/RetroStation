import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';

class BackupReport {
  const BackupReport({required this.saves, required this.states, required this.skipped});

  final int saves;
  final int states;
  final int skipped;
}

/// Copias de seguridad de partidas: SRAM (`saves/<sha1>.srm`) y save states
/// (`states/<sha1>/slotN.state|png`) en un ZIP con un manifiesto.
///
/// Al restaurar solo se aceptan rutas con ese formato exacto (no se puede
/// escribir fuera de `saves/` y `states/`), nada se ejecuta y los archivos se
/// escriben de forma atómica. Los save states se vinculan a los juegos de la
/// biblioteca por su SHA-1.
class BackupService {
  BackupService(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;

  static const manifestName = 'retrostation-backup.json';
  static final _savePath = RegExp(r'^saves/([0-9a-f]{40})\.srm$');
  static final _statePath = RegExp(r'^states/([0-9a-f]{40})/slot([1-6])\.(state|png)$');

  /// Crea el ZIP en memoria.
  Future<(Uint8List, BackupReport)> export() async {
    final games = {for (final g in await _db.select(_db.games).get()) g.id: g};
    final states = await _db.select(_db.saveStates).get();
    final manifestStates = [
      for (final s in states)
        if (games[s.gameId]?.sha1 case final sha1?)
          {'sha1': sha1, 'slot': s.slot, 'createdAt': s.createdAt.toIso8601String()},
    ];
    final manifest = jsonEncode({
      'app': 'RetroStation',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'states': manifestStates,
    });
    return compute(_buildZip, (
      savesDir: _paths.saves.path,
      statesDir: _paths.states.path,
      manifest: manifest,
    ));
  }

  /// Restaura un ZIP creado por [export].
  Future<BackupReport> import(String zipPath) async {
    final result = await compute(_extract, (
      zipPath: zipPath,
      savesDir: _paths.saves.path,
      statesDir: _paths.states.path,
    ));
    // Vincula los save states a los juegos presentes (por SHA-1).
    final bySha1 = {
      for (final g in await _db.select(_db.games).get())
        if (g.sha1 != null) g.sha1!: g.id,
    };
    var linked = 0;
    for (final s in result.manifestStates) {
      final gameId = bySha1[s.sha1];
      final statePath = p.join(_paths.states.path, s.sha1, 'slot${s.slot}.state');
      if (gameId == null || !File(statePath).existsSync()) continue;
      final thumb = p.join(_paths.states.path, s.sha1, 'slot${s.slot}.png');
      await _db.into(_db.saveStates).insert(
            SaveStatesCompanion.insert(
              gameId: gameId,
              slot: s.slot,
              filePath: statePath,
              thumbnailPath: Value(File(thumb).existsSync() ? thumb : null),
              createdAt: Value(s.createdAt),
            ),
            mode: InsertMode.insertOrReplace,
          );
      linked++;
    }
    return BackupReport(saves: result.saves, states: linked, skipped: result.skipped);
  }
}

(Uint8List, BackupReport) _buildZip(
    ({String savesDir, String statesDir, String manifest}) a) {
  final archive = Archive();
  archive.addFile(ArchiveFile.string(BackupService.manifestName, a.manifest));
  var saves = 0;
  var states = 0;
  final savesDir = Directory(a.savesDir);
  if (savesDir.existsSync()) {
    for (final f in savesDir.listSync().whereType<File>()) {
      final name = 'saves/${p.basename(f.path)}';
      if (!BackupService._savePath.hasMatch(name)) continue;
      archive.addFile(ArchiveFile.bytes(name, f.readAsBytesSync()));
      saves++;
    }
  }
  final statesDir = Directory(a.statesDir);
  if (statesDir.existsSync()) {
    for (final f in statesDir.listSync(recursive: true).whereType<File>()) {
      final rel = p.relative(f.path, from: a.statesDir).replaceAll('\\', '/');
      final name = 'states/$rel';
      if (!BackupService._statePath.hasMatch(name)) continue; // ignora .bak/.tmp
      archive.addFile(ArchiveFile.bytes(name, f.readAsBytesSync()));
      if (name.endsWith('.state')) states++;
    }
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  return (bytes, BackupReport(saves: saves, states: states, skipped: 0));
}

typedef _ManifestState = ({String sha1, int slot, DateTime createdAt});

({int saves, int skipped, List<_ManifestState> manifestStates}) _extract(
    ({String zipPath, String savesDir, String statesDir}) a) {
  final archive = ZipDecoder().decodeBytes(File(a.zipPath).readAsBytesSync());
  final manifestFile = archive.findFile(BackupService.manifestName);
  if (manifestFile == null) {
    throw const FormatException('No es una copia de seguridad de RetroStation');
  }
  final manifest = jsonDecode(utf8.decode(manifestFile.readBytes()!)) as Map<String, dynamic>;
  if (manifest['app'] != 'RetroStation') {
    throw const FormatException('No es una copia de seguridad de RetroStation');
  }
  var saves = 0;
  var skipped = 0;
  for (final entry in archive.files) {
    if (!entry.isFile || entry.name == BackupService.manifestName) continue;
    final name = entry.name.replaceAll('\\', '/');
    final save = BackupService._savePath.firstMatch(name);
    final state = BackupService._statePath.firstMatch(name);
    final String target;
    if (save != null) {
      target = p.join(a.savesDir, '${save.group(1)}.srm');
    } else if (state != null) {
      target = p.join(a.statesDir, state.group(1)!, 'slot${state.group(2)}.${state.group(3)}');
    } else {
      skipped++; // ruta no permitida: se ignora
      continue;
    }
    if (entry.size > 64 * 1024 * 1024) {
      skipped++;
      continue;
    }
    final data = entry.readBytes();
    if (data == null) {
      skipped++;
      continue;
    }
    Directory(p.dirname(target)).createSync(recursive: true);
    final tmp = File('$target.tmp')..writeAsBytesSync(data, flush: true);
    tmp.renameSync(target);
    if (save != null) saves++;
  }
  final states = <_ManifestState>[
    for (final s in (manifest['states'] as List? ?? const []))
      if (s is Map &&
          s['sha1'] is String &&
          RegExp(r'^[0-9a-f]{40}$').hasMatch(s['sha1'] as String) &&
          s['slot'] is int &&
          (s['slot'] as int) >= 1 &&
          (s['slot'] as int) <= 6)
        (
          sha1: s['sha1'] as String,
          slot: s['slot'] as int,
          createdAt: DateTime.tryParse(s['createdAt'] as String? ?? '') ?? DateTime.now(),
        ),
  ];
  return (saves: saves, skipped: skipped, manifestStates: states);
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider), ref.watch(appPathsProvider)),
);
