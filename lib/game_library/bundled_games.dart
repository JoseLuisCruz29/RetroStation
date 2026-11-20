import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../engines/console.dart';
import '../engines/console_registry.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import 'rom_importer.dart';

/// Datos opcionales de un juego incluido (de `assets/bundled/bundled.json`).
class BundledInfo {
  const BundledInfo({
    required this.file,
    this.title,
    this.cover,
    this.developer,
    this.license,
    this.source,
    this.page,
  });

  factory BundledInfo.fromJson(Map<String, dynamic> j) => BundledInfo(
        file: j['file'] as String,
        title: j['title'] as String?,
        cover: j['cover'] as String?,
        developer: j['developer'] as String?,
        license: j['license'] as String?,
        source: j['source'] as String?,
        page: j['page'] as String?,
      );

  final String file;
  final String? title;
  final String? cover;
  final String? developer;
  final String? license;
  final String? source;
  final String? page;
}

/// Juegos incluidos en el APK: todo lo que haya en `assets/bundled/` con una
/// extensión de consola compatible se añade a la biblioteca en el primer
/// arranque. Se validan igual que una importación normal (cabecera, tamaño,
/// duplicados).
///
/// Cada archivo se instala una sola vez: si el usuario lo borra, no vuelve a
/// aparecer. Si una versión nueva del APK trae archivos nuevos, se añaden esos.
class BundledGamesInstaller {
  BundledGamesInstaller(this._db, this._paths, this._importer);

  final AppDatabase _db;
  final AppPaths _paths;
  final RomImporter _importer;

  static const folder = 'assets/bundled/';
  static const sourceId = 'bundled';

  File get _doneFile => File(p.join(_paths.root.path, 'bundled_installed.json'));

  /// Metadatos de `bundled.json` (licencia, fuente...), por nombre de archivo.
  static Future<Map<String, BundledInfo>> loadInfo() async {
    try {
      final raw = await rootBundle.loadString('${folder}bundled.json');
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return {for (final j in list) (j['file'] as String): BundledInfo.fromJson(j)};
    } catch (_) {
      return const {}; // sin archivo de metadatos: se usa el nombre del archivo
    }
  }

  Future<void> installNew() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final extensions = {
      for (final c in ConsoleRegistry.all)
        if (c.status == CoreStatus.available) ...c.extensions.map((e) => '.$e'),
      '.zip',
    };
    final assets = manifest
        .listAssets()
        .where((a) => a.startsWith(folder) && extensions.contains(p.extension(a).toLowerCase()))
        .toList();
    if (assets.isEmpty) return;

    final done = await _readDone();
    final pending = assets.where((a) => !done.contains(p.basename(a))).toList();
    if (pending.isEmpty) return;
    final info = await loadInfo();

    final tmpDir = Directory(p.join(_paths.downloads.path, 'bundled_tmp'));
    await tmpDir.create(recursive: true);
    try {
      for (final asset in pending) {
        final name = p.basename(asset);
        try {
          final tmp = File(p.join(tmpDir.path, name));
          final data = await rootBundle.load(asset);
          await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true);
          final meta = info[name];
          final report = await _importer.importFiles(
            [tmp.path],
            sourceId: sourceId,
            sourceUrl: meta?.page ?? meta?.source,
            moveSources: true, // es una copia temporal sacada del APK
          );
          for (final id in report.added) {
            await _applyMeta(id, name, meta);
          }
          for (final (file, reason) in report.rejected) {
            debugPrint('Juego incluido rechazado: $file ($reason)');
          }
          if (await tmp.exists()) await tmp.delete();
        } catch (e) {
          debugPrint('No se pudo instalar el juego incluido $name: $e');
        }
        // Se marca aunque falle o sea un duplicado: así no se reintenta en
        // cada arranque ni reaparece si el usuario lo borró.
        done.add(name);
      }
    } finally {
      await _writeDone(done);
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    }
  }

  Future<void> _applyMeta(int gameId, String fileName, BundledInfo? meta) async {
    String? coverPath;
    if (meta?.cover case final cover?) {
      try {
        final data = await rootBundle.load('$folder$cover');
        await _paths.covers.create(recursive: true);
        final f = File(p.join(_paths.covers.path, 'bundled_$gameId${p.extension(cover)}'));
        await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
        coverPath = f.path;
      } catch (_) {
        // Sin portada: no impide instalar el juego.
      }
    }
    await (_db.update(_db.games)..where((g) => g.id.equals(gameId))).write(GamesCompanion(
      title: meta?.title == null ? const Value.absent() : Value(meta!.title!),
      coverPath: coverPath == null ? const Value.absent() : Value(coverPath),
      remoteId: Value(fileName),
    ));
  }

  Future<Set<String>> _readDone() async {
    try {
      return ((jsonDecode(await _doneFile.readAsString()) as List).cast<String>()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _writeDone(Set<String> done) async {
    await _doneFile.parent.create(recursive: true);
    await _doneFile.writeAsString(jsonEncode(done.toList()..sort()), flush: true);
  }
}
