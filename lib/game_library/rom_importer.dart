import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engines/console_registry.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';
import 'rom_inspector.dart';

class ImportReport {
  ImportReport({required this.added, required this.rejected});

  /// Ids de los juegos añadidos a la biblioteca.
  final List<int> added;

  /// Archivos descartados con su motivo (nombre visible, motivo).
  final List<(String, String)> rejected;
}

/// Importa ROMs elegidos por el usuario (o descargados) al almacenamiento
/// privado. Admite archivos sueltos y ZIP. Medidas de seguridad:
/// - Solo se aceptan extensiones de consolas conocidas y cabeceras válidas.
/// - De un ZIP solo se usa el nombre base de cada entrada (sin rutas): no hay
///   forma de escribir fuera de `roms/` (protección zip-slip).
/// - Límites de tamaño por entrada y totales (protección contra zip bombs).
/// - Nada se ejecuta: los archivos solo se leen y copian.
/// - Duplicados (mismo SHA-1) se descartan.
class RomImporter {
  RomImporter(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;

  /// Límite por archivo (y por contenido total de un ZIP): 10 GB.
  static const maxRomBytes = RomInspector.maxImportSize;

  /// [moveSources]: los archivos de origen son copias temporales (selector de
  /// archivos, descargas): se mueven en lugar de copiarse, para no necesitar
  /// el doble de espacio con juegos grandes.
  Future<ImportReport> importFiles(
    List<String> sources, {
    String sourceId = 'local',
    String? sourceUrl,
    bool moveSources = false,
  }) async {
    final staged = await compute(
      _stageFiles,
      (sources: sources, romsDir: _paths.roms.path, move: moveSources),
    );
    final added = <int>[];
    final rejected = <(String, String)>[...staged.rejected];
    final known = {
      for (final g in await _db.select(_db.games).get())
        if (g.sha1 != null) g.sha1!,
    };
    for (final rom in staged.valid) {
      if (known.contains(rom.sha1) || !_paths.contains(rom.path)) {
        discardStagedRom(rom.path, _paths.roms.path);
        rejected.add((p.basename(rom.path), 'Ya está en tu biblioteca'));
        continue;
      }
      final id = await _db.into(_db.games).insert(GamesCompanion.insert(
            title: rom.title,
            consoleId: rom.consoleId,
            status: GameStatus.installed,
            romPath: Value(rom.path),
            sha1: Value(rom.sha1),
            fileSize: Value(rom.size),
            sourceId: Value(sourceId),
            sourceUrl: Value(sourceUrl),
          ));
      known.add(rom.sha1);
      added.add(id);
    }
    return ImportReport(added: added, rejected: rejected);
  }

  /// Completa un juego "pendiente" con el archivo descargado: valida (y
  /// extrae si es ZIP), comprueba el hash esperado si la fuente lo publicó y
  /// marca el juego como instalado. Devuelve null si todo fue bien o el motivo
  /// del rechazo (en ese caso no queda ningún archivo en `roms/`).
  Future<String?> attachDownload(int gameId, String downloadedPath, {String? expectedSha1}) async {
    if (expectedSha1 != null) {
      final actual = await compute(_sha1OfFile, downloadedPath);
      if (actual != expectedSha1.toLowerCase()) {
        return 'El archivo descargado no coincide con el hash publicado (posible corrupción)';
      }
    }
    final staged = await compute(
      _stageFiles,
      // La descarga es un archivo temporal: se mueve, no se copia.
      (sources: [downloadedPath], romsDir: _paths.roms.path, move: true),
    );
    if (staged.valid.isEmpty) {
      return staged.rejected.isEmpty ? 'El archivo no contiene un ROM válido' : staged.rejected.first.$2;
    }
    final known = {
      for (final g in await _db.select(_db.games).get())
        if (g.sha1 != null && g.id != gameId) g.sha1!,
    };
    final rom = staged.valid.first;
    // Si un ZIP trae varios ROMs, se usa el primero; el resto se descarta.
    for (final extra in staged.valid.skip(1)) {
      discardStagedRom(extra.path, _paths.roms.path);
    }
    if (known.contains(rom.sha1)) {
      discardStagedRom(rom.path, _paths.roms.path);
      return 'Ya tienes este juego en la biblioteca';
    }
    await (_db.update(_db.games)..where((g) => g.id.equals(gameId))).write(GamesCompanion(
      status: const Value(GameStatus.installed),
      romPath: Value(rom.path),
      sha1: Value(rom.sha1),
      fileSize: Value(rom.size),
      consoleId: Value(rom.consoleId),
    ));
    return null;
  }
}

String _sha1OfFile(String path) => RomInspector.sha1OfFile(path);

/// Borra un ROM descartado. Los discos de varias pistas viven en su propia
/// carpeta dentro de `roms/`: se borra la carpeta entera.
void discardStagedRom(String romPath, String romsDir) {
  final dir = p.dirname(romPath);
  if (p.equals(dir, romsDir)) {
    final f = File(romPath);
    if (f.existsSync()) f.deleteSync();
  } else if (p.isWithin(romsDir, dir)) {
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}

typedef _Staged = ({List<ValidRom> valid, List<(String, String)> rejected});

/// Un archivo a importar, siempre en disco: los ZIP se extraen por bloques a
/// una carpeta temporal (nunca se cargan enteros en memoria).
class _Input {
  _Input(this.name, this.path, {required this.movable}) : size = File(path).lengthSync();

  final String name;
  final String path;

  /// Copia temporal (extraída de un ZIP, del selector o de una descarga):
  /// se mueve en lugar de copiarse.
  final bool movable;
  final int size;

  String get ext => p.extension(name).toLowerCase();

  void writeTo(String target) {
    if (movable) {
      try {
        File(path).renameSync(target); // instantáneo en la misma partición
        return;
      } on FileSystemException {
        // Otra partición: se copia.
      }
    }
    File(path).copySync(target); // copia por bloques
  }

  String readText() => File(path).readAsStringSync(encoding: latin1);
}

/// Mensaje legible para un error de disco (sobre todo, falta de espacio).
String _diskError(FileSystemException e) {
  final code = e.osError?.errorCode;
  if (code == 28) return 'No hay espacio suficiente en el teléfono'; // ENOSPC
  return e.osError?.message ?? e.message;
}

/// Se ejecuta en un isolate: copia/extrae a `roms/` y valida cada archivo.
_Staged _stageFiles(({List<String> sources, String romsDir, bool move}) args) {
  final valid = <ValidRom>[];
  final rejected = <(String, String)>[];
  Directory(args.romsDir).createSync(recursive: true);
  // Carpeta temporal en la misma partición que `roms/`: lo extraído se mueve
  // a su sitio sin volver a copiarse. Se borra siempre al terminar.
  final extractDir = Directory(p.join(p.dirname(args.romsDir), '.import_tmp'))
    ..createSync(recursive: true);
  try {
    return _stage(args, valid, rejected, extractDir.createTempSync('zip_').path);
  } finally {
    try {
      extractDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Se reintenta en la siguiente importación.
    }
  }
}

_Staged _stage(
  ({List<String> sources, String romsDir, bool move}) args,
  List<ValidRom> valid,
  List<(String, String)> rejected,
  String tmpDir,
) {
  const max = RomImporter.maxRomBytes;

  // 1. Reunir entradas (archivos sueltos y contenido de ZIP).
  final inputs = <_Input>[];
  for (final source in args.sources) {
    final displayName = p.basename(source);
    try {
      final file = File(source);
      if (p.extension(source).toLowerCase() != '.zip') {
        inputs.add(_Input(sanitizeFileName(displayName), source, movable: args.move));
        continue;
      }
      if (file.lengthSync() > max) {
        rejected.add((displayName, 'ZIP demasiado grande (máx. 10 GB)'));
        continue;
      }
      final stream = InputFileStream(source);
      try {
        final archive = ZipDecoder().decodeStream(stream);
        var total = 0;
        var found = false;
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final entryName = sanitizeFileName(entry.name);
          final ext = p.extension(entryName).toLowerCase();
          if (ConsoleRegistry.byExtension(ext) == null && ext != '.bin') continue;
          found = true;
          if (entry.size > max) {
            rejected.add((entryName, 'Entrada del ZIP mayor de 10 GB'));
            continue;
          }
          total += entry.size;
          if (total > max) {
            rejected.add((displayName, 'El ZIP descomprimido supera los 10 GB'));
            break;
          }
          // Cada entrada a su propia subcarpeta: dos entradas con el mismo
          // nombre en carpetas distintas del ZIP no se pisan.
          final dir = Directory(p.join(tmpDir, '${inputs.length}'))..createSync();
          final target = p.join(dir.path, entryName);
          final out = OutputFileStream(target);
          try {
            entry.writeContent(out);
          } finally {
            out.closeSync();
          }
          // El tamaño declarado en el ZIP puede mentir: se comprueba el real.
          final written = File(target).lengthSync();
          if (written > max || written == 0) {
            File(target).deleteSync();
            rejected.add((entryName, written == 0 ? 'Entrada del ZIP dañada' : 'Entrada mayor de 10 GB'));
            continue;
          }
          inputs.add(_Input(entryName, target, movable: true));
        }
        if (!found) rejected.add((displayName, 'El ZIP no contiene ROMs compatibles'));
      } finally {
        stream.closeSync();
      }
    } on ArchiveException {
      rejected.add((displayName, 'ZIP dañado'));
    } on FormatException {
      rejected.add((displayName, 'Archivo dañado o formato no válido'));
    } on FileSystemException catch (e) {
      rejected.add((displayName, 'No se pudo leer: ${_diskError(e)}'));
    }
  }

  void inspect(String target, String displayName) {
    final result = RomInspector.inspect(target);
    switch (result) {
      case ValidRom():
        valid.add(result);
      case RejectedRom(:final reason):
        discardStagedRom(target, args.romsDir);
        rejected.add((displayName, reason));
    }
  }

  // 2. Discos .cue: el .cue y sus pistas van juntos a una carpeta propia.
  final consumed = <_Input>{};
  for (final cue in inputs.where((i) => i.ext == '.cue')) {
    consumed.add(cue);
    try {
      final tracks = RomInspector.cueTrackFiles(cue.readText());
      final files = <_Input>[];
      String? missing;
      for (final t in tracks) {
        final match = inputs.where((i) => i.name.toLowerCase() == t.toLowerCase()).firstOrNull;
        if (match == null) {
          missing = t;
          break;
        }
        files.add(match);
      }
      if (tracks.isEmpty || missing != null) {
        rejected.add((
          cue.name,
          tracks.isEmpty
              ? 'El .cue no hace referencia a ningún archivo'
              : 'Falta "$missing": selecciona el .cue junto con todas sus pistas .bin',
        ));
        continue;
      }
      final dir = uniqueDir(args.romsDir, p.basenameWithoutExtension(cue.name));
      Directory(dir).createSync();
      cue.writeTo(p.join(dir, cue.name));
      for (final (i, f) in files.indexed) {
        consumed.add(f);
        // Se respeta el nombre que espera el .cue (puede diferir en mayúsculas).
        f.writeTo(p.join(dir, tracks[i]));
      }
      inspect(p.join(dir, cue.name), cue.name);
    } on FileSystemException catch (e) {
      rejected.add((cue.name, 'No se pudo copiar: ${_diskError(e)}'));
    }
  }

  // 3. El resto: un archivo, un juego.
  for (final input in inputs.where((i) => !consumed.contains(i))) {
    if (input.ext == '.bin') {
      rejected.add((input.name, 'Pista .bin sin su .cue: selecciona también el .cue'));
      continue;
    }
    if (ConsoleRegistry.byExtension(input.ext) == null) {
      rejected.add((input.name, 'No es un ROM de una consola compatible'));
      continue;
    }
    if (input.size > max) {
      rejected.add((input.name, 'Archivo mayor de 10 GB'));
      continue;
    }
    try {
      final target = uniquePath(args.romsDir, input.name);
      input.writeTo(target);
      inspect(target, input.name);
    } on FileSystemException catch (e) {
      rejected.add((input.name, 'No se pudo copiar: ${_diskError(e)}'));
    }
  }
  return (valid: valid, rejected: rejected);
}

/// Carpeta libre en [dir] para un disco ("juego (2)" si ya existe).
String uniqueDir(String dir, String name) {
  final safe = sanitizeFileName(name);
  var candidate = p.join(dir, safe);
  var i = 2;
  while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
    candidate = p.join(dir, '$safe ($i)');
    i++;
  }
  return candidate;
}

/// Nombre seguro: solo el nombre base, sin caracteres de control ni separadores.
String sanitizeFileName(String name) {
  final base = p.basename(name.replaceAll('\\', '/'));
  final clean = base.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_').trim();
  if (clean.isEmpty || clean == '.' || clean == '..') return 'rom';
  return clean;
}

/// Ruta libre en [dir] para [name] ("juego (2).gba" si ya existe).
String uniquePath(String dir, String name) {
  var candidate = p.join(dir, name);
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var i = 2;
  while (File(candidate).existsSync()) {
    candidate = p.join(dir, '$stem ($i)$ext');
    i++;
  }
  return candidate;
}

final romImporterProvider = Provider<RomImporter>(
  (ref) => RomImporter(ref.watch(databaseProvider), ref.watch(appPathsProvider)),
);
