import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import '../storage/storage_providers.dart';

class SaveStateWithGame {
  const SaveStateWithGame(this.state, this.game);

  final SaveStateEntry state;
  final Game game;
}

class SaveStateRepository {
  SaveStateRepository(this._db);

  final AppDatabase _db;

  Stream<List<SaveStateWithGame>> watchAll() {
    final query = _db.select(_db.saveStates).join([
      innerJoin(_db.games, _db.games.id.equalsExp(_db.saveStates.gameId)),
    ])
      ..orderBy([OrderingTerm.desc(_db.saveStates.createdAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              SaveStateWithGame(
                row.readTable(_db.saveStates),
                row.readTable(_db.games),
              ),
          ],
        );
  }

  /// Elimina el registro y sus archivos (estado y miniatura).
  Future<void> delete(SaveStateEntry entry) async {
    await (_db.delete(_db.saveStates)..where((s) => s.id.equals(entry.id)))
        .go();
    for (final path in [entry.filePath, entry.thumbnailPath]) {
      if (path == null) continue;
      for (final file in [File(path), File('$path.bak')]) {
        if (await file.exists()) await file.delete();
      }
    }
  }
}

final saveStateRepositoryProvider = Provider<SaveStateRepository>(
  (ref) => SaveStateRepository(ref.watch(databaseProvider)),
);

final saveStatesProvider = StreamProvider<List<SaveStateWithGame>>(
  (ref) => ref.watch(saveStateRepositoryProvider).watchAll(),
);
