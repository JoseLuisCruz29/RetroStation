import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Estado de un juego dentro de la biblioteca.
enum GameStatus {
  /// El archivo ROM está en el almacenamiento privado y se puede ejecutar.
  installed,

  /// El juego está en la biblioteca pero todavía no tiene archivo local.
  pending,

  /// Hay una descarga activa para este juego.
  downloading,
}

@DataClassName('Game')
class Games extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 255)();

  /// Identificador de consola (ver `ConsoleId` en engines/).
  TextColumn get consoleId => text()();

  /// Ruta del ROM dentro del almacenamiento privado de la app.
  TextColumn get romPath => text().nullable()();

  /// SHA-1 del ROM: identifica el juego y evita duplicados.
  TextColumn get sha1 => text().nullable().unique()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get releaseYear => integer().nullable()();

  /// Procedencia: id del adaptador (`local`, `homebrew_hub`...) y URL original.
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceUrl => text().nullable()();

  TextColumn get status => textEnum<GameStatus>()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  IntColumn get playTimeSeconds => integer().withDefault(const Constant(0))();

  /// El SHA-1 coincide con un volcado No-Intro conocido (versión 2).
  BoolColumn get verified => boolean().withDefault(const Constant(false))();

  /// Identificador del juego en su fuente externa (versión 3).
  TextColumn get remoteId => text().nullable()();

  /// Archivo a descargar para juegos pendientes de una fuente (versión 3).
  TextColumn get downloadUrl => text().nullable()();
}

@DataClassName('SaveStateEntry')
class SaveStates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get gameId =>
      integer().references(Games, #id, onDelete: KeyAction.cascade)();
  IntColumn get slot => integer()();
  TextColumn get filePath => text()();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {gameId, slot},
      ];
}

@DataClassName('SettingEntry')
class SettingEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Games, SaveStates, SettingEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Base de datos en el directorio privado de soporte de la aplicación
  /// (no visible para otras apps ni para el usuario).
  factory AppDatabase.openDefault() => AppDatabase(
        driftDatabase(
          name: 'retrostation',
          native: const DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(games, games.verified);
          if (from < 3) {
            await m.addColumn(games, games.remoteId);
            await m.addColumn(games, games.downloadUrl);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
