import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/http_fetch.dart';
import '../game_library/game_repository.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';
import 'discovery_models.dart';

/// Pasa resultados de Descubrir a la biblioteca como "Pendientes".
class DiscoveryLibrary {
  DiscoveryLibrary(this._db, this._paths, this._games);

  final AppDatabase _db;
  final AppPaths _paths;
  final GameRepository _games;

  /// Guarda el juego como pendiente (sin archivo). Devuelve el id del juego,
  /// existente o nuevo.
  Future<int> savePending(DiscoveryItem item) async {
    final consoleId = item.consoleId;
    if (consoleId == null) {
      throw StateError('${item.platformLabel ?? 'Esta plataforma'} no está soportada');
    }
    final existing = await _games.findRemote(item.sourceId, item.remoteId);
    if (existing != null) return existing.id;

    final id = await _db.into(_db.games).insert(GamesCompanion.insert(
          title: item.title,
          consoleId: consoleId,
          status: GameStatus.pending,
          releaseYear: Value(item.year),
          genre: Value(item.tags.firstOrNull),
          sourceId: Value(item.sourceId),
          sourceUrl: Value(item.pageUrl.toString()),
          remoteId: Value(item.remoteId),
          downloadUrl: Value(item.primaryFile?.url.toString()),
        ));
    // Portada: primera captura de la fuente (opcional, sin bloquear).
    final cover = item.coverUrl;
    if (cover != null) {
      try {
        final bytes = await fetchBytes(cover, retries: 1, maxBytes: 4 * 1024 * 1024);
        const png = [0x89, 0x50, 0x4E, 0x47];
        const jpg = [0xFF, 0xD8, 0xFF];
        bool starts(List<int> magic) =>
            bytes.length > magic.length &&
            List.generate(magic.length, (i) => bytes[i] == magic[i]).every((b) => b);
        if (starts(png) || starts(jpg)) {
          await _paths.covers.create(recursive: true);
          final file = File(p.join(_paths.covers.path, 'remote_$id${starts(png) ? '.png' : '.jpg'}'));
          await file.writeAsBytes(bytes, flush: true);
          await (_db.update(_db.games)..where((g) => g.id.equals(id)))
              .write(GamesCompanion(coverPath: Value(file.path)));
        }
      } on HttpFetchException {
        // Sin portada: se puede añadir después desde la ficha.
      }
    }
    return id;
  }
}

final discoveryLibraryProvider = Provider<DiscoveryLibrary>((ref) => DiscoveryLibrary(
      ref.watch(databaseProvider),
      ref.watch(appPathsProvider),
      ref.watch(gameRepositoryProvider),
    ));
