import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/game_library/game_repository.dart';
import 'package:retrostation/save_manager/save_state_repository.dart';
import 'package:retrostation/settings/app_settings.dart';
import 'package:retrostation/storage/database.dart';

import '../support/test_env.dart';

void main() {
  late AppDatabase db;
  late GameRepository games;

  setUp(() {
    db = memoryDatabase();
    games = GameRepository(db);
  });
  tearDown(() => db.close());

  Future<int> addGame(
    String title, {
    String console = 'gba',
    GameStatus status = GameStatus.installed,
    DateTime? lastPlayed,
    String? sha1,
  }) =>
      games.insert(GamesCompanion.insert(
        title: title,
        consoleId: console,
        status: status,
        lastPlayedAt: Value(lastPlayed),
        sha1: Value(sha1),
      ));

  group('GameRepository', () {
    test('Todos: orden alfabético sin distinguir mayúsculas', () async {
      await addGame('zeta');
      await addGame('Alfa');
      await addGame('beta');
      final list = await games.watch(const LibraryFilter()).first;
      expect(list.map((g) => g.title), ['Alfa', 'beta', 'zeta']);
    });

    test('filtra por consola, instalados y pendientes', () async {
      await addGame('A', console: 'gba');
      await addGame('B', console: 'nes');
      await addGame('C', console: 'gba', status: GameStatus.pending);
      await addGame('D', status: GameStatus.downloading);

      final gba = await games.watch(const LibraryFilter(consoleId: 'gba')).first;
      expect(gba.map((g) => g.title), ['A', 'C', 'D']);

      final installed = await games
          .watch(const LibraryFilter(category: LibraryCategory.installed))
          .first;
      expect(installed.map((g) => g.title), ['A', 'B']);

      final pending = await games
          .watch(const LibraryFilter(category: LibraryCategory.pending))
          .first;
      expect(pending.map((g) => g.title), ['C', 'D']);
    });

    test('favoritos y recientes', () async {
      final a = await addGame('A', lastPlayed: DateTime(2026, 1, 1));
      await addGame('B', lastPlayed: DateTime(2026, 3, 1));
      await addGame('C');
      await games.setFavorite(a, true);

      final favs = await games
          .watch(const LibraryFilter(category: LibraryCategory.favorites))
          .first;
      expect(favs.map((g) => g.title), ['A']);

      final recent = await games
          .watch(const LibraryFilter(category: LibraryCategory.recent))
          .first;
      expect(recent.map((g) => g.title), ['B', 'A']);
    });

    test('el SHA-1 impide duplicados', () async {
      await addGame('A', sha1: 'abc');
      expect(() => addGame('A copia', sha1: 'abc'), throwsA(isA<Exception>()));
    });

    test('contador de juegos', () async {
      expect(await games.watchCount().first, 0);
      await addGame('A');
      await addGame('B');
      expect(await games.watchCount().first, 2);
    });
  });

  group('SaveStateRepository', () {
    test('lista con el juego y se borra en cascada', () async {
      final id = await addGame('A');
      await db.into(db.saveStates).insert(SaveStatesCompanion.insert(
            gameId: id,
            slot: 1,
            filePath: '/no/existe.state',
          ));
      final repo = SaveStateRepository(db);
      final list = await repo.watchAll().first;
      expect(list.single.game.title, 'A');

      await (db.delete(db.games)..where((g) => g.id.equals(id))).go();
      expect(await repo.watchAll().first, isEmpty);
    });
  });

  group('SettingsRepository', () {
    test('valores por defecto y persistencia', () async {
      final repo = SettingsRepository(db);
      final initial = await repo.load();
      expect(initial.background, BackgroundStyle.charcoal);
      expect(initial.accent, AccentColor.cian);
      expect(initial.reduceMotion, isFalse);

      await repo.save(const AppSettings(
        background: BackgroundStyle.amoled,
        accent: AccentColor.ambar,
        reduceMotion: true,
      ));
      final loaded = await repo.load();
      expect(loaded.background, BackgroundStyle.amoled);
      expect(loaded.accent, AccentColor.ambar);
      expect(loaded.reduceMotion, isTrue);
    });

    test('valores desconocidos vuelven al valor por defecto', () {
      final s = AppSettings.fromMap({'ui.background': 'neon', 'ui.accent': '?'});
      expect(s.background, BackgroundStyle.charcoal);
      expect(s.accent, AccentColor.cian);
    });
  });
}
