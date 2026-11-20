import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';
import 'rom_importer.dart' show discardStagedRom;
import '../storage/database.dart';
import '../storage/storage_providers.dart';

/// Categorías de la biblioteca.
enum LibraryCategory {
  all('Todos'),
  installed('Instalados'),
  favorites('Favoritos'),
  recent('Recientes'),
  pending('Pendientes');

  const LibraryCategory(this.label);
  final String label;
}

class LibraryFilter {
  const LibraryFilter({this.category = LibraryCategory.all, this.consoleId});

  final LibraryCategory category;
  final String? consoleId;

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      other.category == category &&
      other.consoleId == consoleId;

  @override
  int get hashCode => Object.hash(category, consoleId);
}

class GameRepository {
  GameRepository(this._db);

  final AppDatabase _db;

  static const recentLimit = 30;

  Stream<List<Game>> watch(LibraryFilter filter) {
    final q = _db.select(_db.games);
    if (filter.consoleId != null) {
      q.where((g) => g.consoleId.equals(filter.consoleId!));
    }
    switch (filter.category) {
      case LibraryCategory.all:
        q.orderBy([(g) => OrderingTerm.asc(g.title.collate(Collate.noCase))]);
      case LibraryCategory.installed:
        q
          ..where((g) => g.status.equalsValue(GameStatus.installed))
          ..orderBy([(g) => OrderingTerm.asc(g.title.collate(Collate.noCase))]);
      case LibraryCategory.favorites:
        q
          ..where((g) => g.isFavorite.equals(true))
          ..orderBy([(g) => OrderingTerm.asc(g.title.collate(Collate.noCase))]);
      case LibraryCategory.recent:
        q
          ..where((g) => g.lastPlayedAt.isNotNull())
          ..orderBy([(g) => OrderingTerm.desc(g.lastPlayedAt)])
          ..limit(recentLimit);
      case LibraryCategory.pending:
        q
          ..where((g) => g.status.equalsValue(GameStatus.installed).not())
          ..orderBy([(g) => OrderingTerm.asc(g.title.collate(Collate.noCase))]);
    }
    return q.watch();
  }

  Stream<Game?> watchById(int id) =>
      (_db.select(_db.games)..where((g) => g.id.equals(id)))
          .watchSingleOrNull();

  Stream<int> watchCount() {
    final count = _db.games.id.count();
    return (_db.selectOnly(_db.games)..addColumns([count]))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  Future<int> insert(GamesCompanion game) => _db.into(_db.games).insert(game);

  /// Registra una sesión de juego: actualiza la última partida y suma el tiempo.
  Future<void> recordSession(int id, Duration played) =>
      _db.customUpdate(
        'UPDATE games SET last_played_at = ?, '
        'play_time_seconds = play_time_seconds + ? WHERE id = ?',
        variables: [
          Variable<DateTime>(DateTime.now()),
          Variable<int>(played.inSeconds),
          Variable<int>(id),
        ],
        updates: {_db.games},
      );

  /// Juego ya guardado desde una fuente (para no duplicar pendientes).
  Future<Game?> findRemote(String sourceId, String remoteId) =>
      (_db.select(_db.games)
            ..where((g) => g.sourceId.equals(sourceId) & g.remoteId.equals(remoteId))
            ..limit(1))
          .getSingleOrNull();

  Future<void> rename(int id, String title) =>
      (_db.update(_db.games)..where((g) => g.id.equals(id)))
          .write(GamesCompanion(title: Value(title.trim())));

  /// Elimina el juego de la biblioteca y su ROM. Si [deleteSaves] es true,
  /// borra también la partida del cartucho, los save states y la portada.
  Future<void> delete(Game game, AppPaths paths, {required bool deleteSaves}) async {
    await (_db.delete(_db.games)..where((g) => g.id.equals(game.id))).go();
    Future<void> rm(String? path) async {
      if (path == null || !paths.contains(path)) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
    }

    final rom = game.romPath;
    if (rom != null && paths.contains(rom)) {
      // Los discos de varias pistas viven en su propia carpeta: se borra entera.
      discardStagedRom(rom, paths.roms.path);
    }
    await rm(game.coverPath);
    if (deleteSaves && game.sha1 != null) {
      await rm(p.join(paths.saves.path, '${game.sha1}.srm'));
      final states = Directory(p.join(paths.states.path, game.sha1!));
      if (await states.exists()) await states.delete(recursive: true);
    }
  }

  Future<void> setFavorite(int id, bool favorite) =>
      (_db.update(_db.games)..where((g) => g.id.equals(id)))
          .write(GamesCompanion(isFavorite: Value(favorite)));
}

final gameRepositoryProvider =
    Provider<GameRepository>((ref) => GameRepository(ref.watch(databaseProvider)));

final libraryProvider = StreamProvider.family<List<Game>, LibraryFilter>(
  (ref, filter) => ref.watch(gameRepositoryProvider).watch(filter),
);

final gameByIdProvider = StreamProvider.family<Game?, int>(
  (ref, id) => ref.watch(gameRepositoryProvider).watchById(id),
);

final gameCountProvider = StreamProvider<int>(
  (ref) => ref.watch(gameRepositoryProvider).watchCount(),
);
