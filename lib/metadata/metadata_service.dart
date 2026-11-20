import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/http_fetch.dart';
import '../engines/console.dart';
import '../engines/console_registry.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';
import 'dat_parser.dart';

/// Resultado de buscar metadatos para un juego.
enum EnrichResult { updated, notInDatabase, unsupported, offline }

/// Identificación de ROMs (No-Intro por SHA-1), género, año y portadas.
///
/// Fuentes (públicas, sin clave):
/// - libretro-database: `metadat/no-intro`, `metadat/genre`, `metadat/releaseyear`
/// - libretro-thumbnails: `Named_Boxarts`
///
/// Los DAT se descargan una vez y se guardan en `metadata/`; el índice se
/// construye en un isolate y se mantiene en memoria.
class MetadataService {
  MetadataService(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;
  final _indexes = <String, MetadataIndex>{};

  static const _databaseBase =
      'https://raw.githubusercontent.com/libretro/libretro-database/master/metadat';
  static const _thumbnailsBase = 'https://raw.githubusercontent.com/libretro-thumbnails';

  Directory get _dir => Directory(p.join(_paths.root.path, 'metadata'));

  Uri _datUrl(String kind, String system) =>
      Uri.parse('$_databaseBase/$kind/${Uri.encodeComponent(system)}.dat');

  Future<String> _datFile(String kind, String system) async {
    final file = File(p.join(_dir.path, '${kind}_${system.replaceAll(' ', '_')}.dat'));
    if (await file.exists() && await file.length() > 0) return file.readAsString();
    await _dir.create(recursive: true);
    final bytes = await fetchBytes(_datUrl(kind, system), maxBytes: 32 * 1024 * 1024);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Carga (descargando si hace falta) el índice de una consola.
  Future<MetadataIndex?> indexFor(ConsoleDescriptor console) async {
    final system = console.libretroSystem;
    if (system == null) return null;
    final cached = _indexes[console.id];
    if (cached != null) return cached;
    final noIntro = await _datFile('no-intro', system);
    // Género y año son opcionales: si fallan, se identifica igualmente.
    String? genres;
    String? years;
    try {
      genres = await _datFile('genre', system);
    } on HttpFetchException {
      genres = null;
    }
    try {
      years = await _datFile('releaseyear', system);
    } on HttpFetchException {
      years = null;
    }
    final index = await compute(
      _buildIndex,
      (noIntro: noIntro, genres: genres, years: years),
    );
    _indexes[console.id] = index;
    return index;
  }

  /// Identifica el juego y descarga su portada. Actualiza la base de datos.
  Future<EnrichResult> enrich(Game game) async {
    final console = ConsoleRegistry.byId(game.consoleId);
    final sha1 = game.sha1;
    if (console?.libretroSystem == null || sha1 == null) return EnrichResult.unsupported;
    final MetadataIndex? index;
    try {
      index = await indexFor(console!);
    } on HttpFetchException {
      return EnrichResult.offline;
    }
    final meta = index?.lookup(sha1);
    if (meta == null) return EnrichResult.notInDatabase;

    String? coverPath = game.coverPath;
    try {
      coverPath = await _downloadCover(console, meta.name, sha1) ?? coverPath;
    } on HttpFetchException {
      // Sin portada (no existe o sin red): el resto de datos se guarda igual.
    }
    await (_db.update(_db.games)..where((g) => g.id.equals(game.id))).write(
      GamesCompanion(
        title: Value(meta.name),
        genre: Value(meta.genre ?? game.genre),
        releaseYear: Value(meta.releaseYear ?? game.releaseYear),
        coverPath: Value(coverPath),
        verified: const Value(true),
      ),
    );
    return EnrichResult.updated;
  }

  Future<String?> _downloadCover(ConsoleDescriptor console, String name, String sha1) async {
    final repo = console.libretroSystem!.replaceAll(' ', '_');
    final url = Uri.parse(
        '$_thumbnailsBase/$repo/master/Named_Boxarts/${Uri.encodeComponent(thumbnailFileName(name))}');
    final bytes = await fetchBytes(url, retries: 2, maxBytes: 4 * 1024 * 1024);
    // Solo se aceptan PNG reales (firma de 8 bytes).
    const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < 8 || !listEquals(bytes.sublist(0, 8), pngMagic)) return null;
    await _paths.covers.create(recursive: true);
    final file = File(p.join(_paths.covers.path, '$sha1.png'));
    await File('${file.path}.tmp').writeAsBytes(bytes, flush: true);
    await File('${file.path}.tmp').rename(file.path);
    await FileImage(file).evict();
    return file.path;
  }
}

MetadataIndex _buildIndex(({String noIntro, String? genres, String? years}) d) =>
    MetadataIndex.fromDats(noIntro: d.noIntro, genres: d.genres, years: d.years);

final metadataServiceProvider = Provider<MetadataService>(
  (ref) => MetadataService(ref.watch(databaseProvider), ref.watch(appPathsProvider)),
);
