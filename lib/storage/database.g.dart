// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $GamesTable extends Games with TableInfo<$GamesTable, Game> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GamesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consoleIdMeta = const VerificationMeta(
    'consoleId',
  );
  @override
  late final GeneratedColumn<String> consoleId = GeneratedColumn<String>(
    'console_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _romPathMeta = const VerificationMeta(
    'romPath',
  );
  @override
  late final GeneratedColumn<String> romPath = GeneratedColumn<String>(
    'rom_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha1Meta = const VerificationMeta('sha1');
  @override
  late final GeneratedColumn<String> sha1 = GeneratedColumn<String>(
    'sha1',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseYearMeta = const VerificationMeta(
    'releaseYear',
  );
  @override
  late final GeneratedColumn<int> releaseYear = GeneratedColumn<int>(
    'release_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<GameStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<GameStatus>($GamesTable.$converterstatus);
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playTimeSecondsMeta = const VerificationMeta(
    'playTimeSeconds',
  );
  @override
  late final GeneratedColumn<int> playTimeSeconds = GeneratedColumn<int>(
    'play_time_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<bool> verified = GeneratedColumn<bool>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadUrlMeta = const VerificationMeta(
    'downloadUrl',
  );
  @override
  late final GeneratedColumn<String> downloadUrl = GeneratedColumn<String>(
    'download_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    consoleId,
    romPath,
    sha1,
    fileSize,
    coverPath,
    genre,
    releaseYear,
    sourceId,
    sourceUrl,
    status,
    isFavorite,
    addedAt,
    lastPlayedAt,
    playTimeSeconds,
    verified,
    remoteId,
    downloadUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'games';
  @override
  VerificationContext validateIntegrity(
    Insertable<Game> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('console_id')) {
      context.handle(
        _consoleIdMeta,
        consoleId.isAcceptableOrUnknown(data['console_id']!, _consoleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_consoleIdMeta);
    }
    if (data.containsKey('rom_path')) {
      context.handle(
        _romPathMeta,
        romPath.isAcceptableOrUnknown(data['rom_path']!, _romPathMeta),
      );
    }
    if (data.containsKey('sha1')) {
      context.handle(
        _sha1Meta,
        sha1.isAcceptableOrUnknown(data['sha1']!, _sha1Meta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('release_year')) {
      context.handle(
        _releaseYearMeta,
        releaseYear.isAcceptableOrUnknown(
          data['release_year']!,
          _releaseYearMeta,
        ),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('play_time_seconds')) {
      context.handle(
        _playTimeSecondsMeta,
        playTimeSeconds.isAcceptableOrUnknown(
          data['play_time_seconds']!,
          _playTimeSecondsMeta,
        ),
      );
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('download_url')) {
      context.handle(
        _downloadUrlMeta,
        downloadUrl.isAcceptableOrUnknown(
          data['download_url']!,
          _downloadUrlMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Game map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Game(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      consoleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}console_id'],
      )!,
      romPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rom_path'],
      ),
      sha1: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha1'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      releaseYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}release_year'],
      ),
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      ),
      status: $GamesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      ),
      playTimeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_time_seconds'],
      )!,
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}verified'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
      downloadUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}download_url'],
      ),
    );
  }

  @override
  $GamesTable createAlias(String alias) {
    return $GamesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<GameStatus, String, String> $converterstatus =
      const EnumNameConverter<GameStatus>(GameStatus.values);
}

class Game extends DataClass implements Insertable<Game> {
  final int id;
  final String title;

  /// Identificador de consola (ver `ConsoleId` en engines/).
  final String consoleId;

  /// Ruta del ROM dentro del almacenamiento privado de la app.
  final String? romPath;

  /// SHA-1 del ROM: identifica el juego y evita duplicados.
  final String? sha1;
  final int? fileSize;
  final String? coverPath;
  final String? genre;
  final int? releaseYear;

  /// Procedencia: id del adaptador (`local`, `homebrew_hub`...) y URL original.
  final String? sourceId;
  final String? sourceUrl;
  final GameStatus status;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final int playTimeSeconds;

  /// El SHA-1 coincide con un volcado No-Intro conocido (versión 2).
  final bool verified;

  /// Identificador del juego en su fuente externa (versión 3).
  final String? remoteId;

  /// Archivo a descargar para juegos pendientes de una fuente (versión 3).
  final String? downloadUrl;
  const Game({
    required this.id,
    required this.title,
    required this.consoleId,
    this.romPath,
    this.sha1,
    this.fileSize,
    this.coverPath,
    this.genre,
    this.releaseYear,
    this.sourceId,
    this.sourceUrl,
    required this.status,
    required this.isFavorite,
    required this.addedAt,
    this.lastPlayedAt,
    required this.playTimeSeconds,
    required this.verified,
    this.remoteId,
    this.downloadUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['console_id'] = Variable<String>(consoleId);
    if (!nullToAbsent || romPath != null) {
      map['rom_path'] = Variable<String>(romPath);
    }
    if (!nullToAbsent || sha1 != null) {
      map['sha1'] = Variable<String>(sha1);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || releaseYear != null) {
      map['release_year'] = Variable<int>(releaseYear);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || sourceUrl != null) {
      map['source_url'] = Variable<String>(sourceUrl);
    }
    {
      map['status'] = Variable<String>(
        $GamesTable.$converterstatus.toSql(status),
      );
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    map['play_time_seconds'] = Variable<int>(playTimeSeconds);
    map['verified'] = Variable<bool>(verified);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    if (!nullToAbsent || downloadUrl != null) {
      map['download_url'] = Variable<String>(downloadUrl);
    }
    return map;
  }

  GamesCompanion toCompanion(bool nullToAbsent) {
    return GamesCompanion(
      id: Value(id),
      title: Value(title),
      consoleId: Value(consoleId),
      romPath: romPath == null && nullToAbsent
          ? const Value.absent()
          : Value(romPath),
      sha1: sha1 == null && nullToAbsent ? const Value.absent() : Value(sha1),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      releaseYear: releaseYear == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseYear),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      sourceUrl: sourceUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUrl),
      status: Value(status),
      isFavorite: Value(isFavorite),
      addedAt: Value(addedAt),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      playTimeSeconds: Value(playTimeSeconds),
      verified: Value(verified),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      downloadUrl: downloadUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadUrl),
    );
  }

  factory Game.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Game(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      consoleId: serializer.fromJson<String>(json['consoleId']),
      romPath: serializer.fromJson<String?>(json['romPath']),
      sha1: serializer.fromJson<String?>(json['sha1']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      genre: serializer.fromJson<String?>(json['genre']),
      releaseYear: serializer.fromJson<int?>(json['releaseYear']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      sourceUrl: serializer.fromJson<String?>(json['sourceUrl']),
      status: $GamesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
      playTimeSeconds: serializer.fromJson<int>(json['playTimeSeconds']),
      verified: serializer.fromJson<bool>(json['verified']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      downloadUrl: serializer.fromJson<String?>(json['downloadUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'consoleId': serializer.toJson<String>(consoleId),
      'romPath': serializer.toJson<String?>(romPath),
      'sha1': serializer.toJson<String?>(sha1),
      'fileSize': serializer.toJson<int?>(fileSize),
      'coverPath': serializer.toJson<String?>(coverPath),
      'genre': serializer.toJson<String?>(genre),
      'releaseYear': serializer.toJson<int?>(releaseYear),
      'sourceId': serializer.toJson<String?>(sourceId),
      'sourceUrl': serializer.toJson<String?>(sourceUrl),
      'status': serializer.toJson<String>(
        $GamesTable.$converterstatus.toJson(status),
      ),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
      'playTimeSeconds': serializer.toJson<int>(playTimeSeconds),
      'verified': serializer.toJson<bool>(verified),
      'remoteId': serializer.toJson<String?>(remoteId),
      'downloadUrl': serializer.toJson<String?>(downloadUrl),
    };
  }

  Game copyWith({
    int? id,
    String? title,
    String? consoleId,
    Value<String?> romPath = const Value.absent(),
    Value<String?> sha1 = const Value.absent(),
    Value<int?> fileSize = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> releaseYear = const Value.absent(),
    Value<String?> sourceId = const Value.absent(),
    Value<String?> sourceUrl = const Value.absent(),
    GameStatus? status,
    bool? isFavorite,
    DateTime? addedAt,
    Value<DateTime?> lastPlayedAt = const Value.absent(),
    int? playTimeSeconds,
    bool? verified,
    Value<String?> remoteId = const Value.absent(),
    Value<String?> downloadUrl = const Value.absent(),
  }) => Game(
    id: id ?? this.id,
    title: title ?? this.title,
    consoleId: consoleId ?? this.consoleId,
    romPath: romPath.present ? romPath.value : this.romPath,
    sha1: sha1.present ? sha1.value : this.sha1,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    genre: genre.present ? genre.value : this.genre,
    releaseYear: releaseYear.present ? releaseYear.value : this.releaseYear,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    sourceUrl: sourceUrl.present ? sourceUrl.value : this.sourceUrl,
    status: status ?? this.status,
    isFavorite: isFavorite ?? this.isFavorite,
    addedAt: addedAt ?? this.addedAt,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    playTimeSeconds: playTimeSeconds ?? this.playTimeSeconds,
    verified: verified ?? this.verified,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
    downloadUrl: downloadUrl.present ? downloadUrl.value : this.downloadUrl,
  );
  Game copyWithCompanion(GamesCompanion data) {
    return Game(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      consoleId: data.consoleId.present ? data.consoleId.value : this.consoleId,
      romPath: data.romPath.present ? data.romPath.value : this.romPath,
      sha1: data.sha1.present ? data.sha1.value : this.sha1,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      genre: data.genre.present ? data.genre.value : this.genre,
      releaseYear: data.releaseYear.present
          ? data.releaseYear.value
          : this.releaseYear,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      status: data.status.present ? data.status.value : this.status,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      playTimeSeconds: data.playTimeSeconds.present
          ? data.playTimeSeconds.value
          : this.playTimeSeconds,
      verified: data.verified.present ? data.verified.value : this.verified,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      downloadUrl: data.downloadUrl.present
          ? data.downloadUrl.value
          : this.downloadUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Game(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('consoleId: $consoleId, ')
          ..write('romPath: $romPath, ')
          ..write('sha1: $sha1, ')
          ..write('fileSize: $fileSize, ')
          ..write('coverPath: $coverPath, ')
          ..write('genre: $genre, ')
          ..write('releaseYear: $releaseYear, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('status: $status, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('playTimeSeconds: $playTimeSeconds, ')
          ..write('verified: $verified, ')
          ..write('remoteId: $remoteId, ')
          ..write('downloadUrl: $downloadUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    consoleId,
    romPath,
    sha1,
    fileSize,
    coverPath,
    genre,
    releaseYear,
    sourceId,
    sourceUrl,
    status,
    isFavorite,
    addedAt,
    lastPlayedAt,
    playTimeSeconds,
    verified,
    remoteId,
    downloadUrl,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Game &&
          other.id == this.id &&
          other.title == this.title &&
          other.consoleId == this.consoleId &&
          other.romPath == this.romPath &&
          other.sha1 == this.sha1 &&
          other.fileSize == this.fileSize &&
          other.coverPath == this.coverPath &&
          other.genre == this.genre &&
          other.releaseYear == this.releaseYear &&
          other.sourceId == this.sourceId &&
          other.sourceUrl == this.sourceUrl &&
          other.status == this.status &&
          other.isFavorite == this.isFavorite &&
          other.addedAt == this.addedAt &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.playTimeSeconds == this.playTimeSeconds &&
          other.verified == this.verified &&
          other.remoteId == this.remoteId &&
          other.downloadUrl == this.downloadUrl);
}

class GamesCompanion extends UpdateCompanion<Game> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> consoleId;
  final Value<String?> romPath;
  final Value<String?> sha1;
  final Value<int?> fileSize;
  final Value<String?> coverPath;
  final Value<String?> genre;
  final Value<int?> releaseYear;
  final Value<String?> sourceId;
  final Value<String?> sourceUrl;
  final Value<GameStatus> status;
  final Value<bool> isFavorite;
  final Value<DateTime> addedAt;
  final Value<DateTime?> lastPlayedAt;
  final Value<int> playTimeSeconds;
  final Value<bool> verified;
  final Value<String?> remoteId;
  final Value<String?> downloadUrl;
  const GamesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.consoleId = const Value.absent(),
    this.romPath = const Value.absent(),
    this.sha1 = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseYear = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.status = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.playTimeSeconds = const Value.absent(),
    this.verified = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.downloadUrl = const Value.absent(),
  });
  GamesCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String consoleId,
    this.romPath = const Value.absent(),
    this.sha1 = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.genre = const Value.absent(),
    this.releaseYear = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    required GameStatus status,
    this.isFavorite = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.playTimeSeconds = const Value.absent(),
    this.verified = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.downloadUrl = const Value.absent(),
  }) : title = Value(title),
       consoleId = Value(consoleId),
       status = Value(status);
  static Insertable<Game> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? consoleId,
    Expression<String>? romPath,
    Expression<String>? sha1,
    Expression<int>? fileSize,
    Expression<String>? coverPath,
    Expression<String>? genre,
    Expression<int>? releaseYear,
    Expression<String>? sourceId,
    Expression<String>? sourceUrl,
    Expression<String>? status,
    Expression<bool>? isFavorite,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? playTimeSeconds,
    Expression<bool>? verified,
    Expression<String>? remoteId,
    Expression<String>? downloadUrl,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (consoleId != null) 'console_id': consoleId,
      if (romPath != null) 'rom_path': romPath,
      if (sha1 != null) 'sha1': sha1,
      if (fileSize != null) 'file_size': fileSize,
      if (coverPath != null) 'cover_path': coverPath,
      if (genre != null) 'genre': genre,
      if (releaseYear != null) 'release_year': releaseYear,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (status != null) 'status': status,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (addedAt != null) 'added_at': addedAt,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (playTimeSeconds != null) 'play_time_seconds': playTimeSeconds,
      if (verified != null) 'verified': verified,
      if (remoteId != null) 'remote_id': remoteId,
      if (downloadUrl != null) 'download_url': downloadUrl,
    });
  }

  GamesCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? consoleId,
    Value<String?>? romPath,
    Value<String?>? sha1,
    Value<int?>? fileSize,
    Value<String?>? coverPath,
    Value<String?>? genre,
    Value<int?>? releaseYear,
    Value<String?>? sourceId,
    Value<String?>? sourceUrl,
    Value<GameStatus>? status,
    Value<bool>? isFavorite,
    Value<DateTime>? addedAt,
    Value<DateTime?>? lastPlayedAt,
    Value<int>? playTimeSeconds,
    Value<bool>? verified,
    Value<String?>? remoteId,
    Value<String?>? downloadUrl,
  }) {
    return GamesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      consoleId: consoleId ?? this.consoleId,
      romPath: romPath ?? this.romPath,
      sha1: sha1 ?? this.sha1,
      fileSize: fileSize ?? this.fileSize,
      coverPath: coverPath ?? this.coverPath,
      genre: genre ?? this.genre,
      releaseYear: releaseYear ?? this.releaseYear,
      sourceId: sourceId ?? this.sourceId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playTimeSeconds: playTimeSeconds ?? this.playTimeSeconds,
      verified: verified ?? this.verified,
      remoteId: remoteId ?? this.remoteId,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (consoleId.present) {
      map['console_id'] = Variable<String>(consoleId.value);
    }
    if (romPath.present) {
      map['rom_path'] = Variable<String>(romPath.value);
    }
    if (sha1.present) {
      map['sha1'] = Variable<String>(sha1.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (releaseYear.present) {
      map['release_year'] = Variable<int>(releaseYear.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $GamesTable.$converterstatus.toSql(status.value),
      );
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (playTimeSeconds.present) {
      map['play_time_seconds'] = Variable<int>(playTimeSeconds.value);
    }
    if (verified.present) {
      map['verified'] = Variable<bool>(verified.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (downloadUrl.present) {
      map['download_url'] = Variable<String>(downloadUrl.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GamesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('consoleId: $consoleId, ')
          ..write('romPath: $romPath, ')
          ..write('sha1: $sha1, ')
          ..write('fileSize: $fileSize, ')
          ..write('coverPath: $coverPath, ')
          ..write('genre: $genre, ')
          ..write('releaseYear: $releaseYear, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('status: $status, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('playTimeSeconds: $playTimeSeconds, ')
          ..write('verified: $verified, ')
          ..write('remoteId: $remoteId, ')
          ..write('downloadUrl: $downloadUrl')
          ..write(')'))
        .toString();
  }
}

class $SaveStatesTable extends SaveStates
    with TableInfo<$SaveStatesTable, SaveStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaveStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _gameIdMeta = const VerificationMeta('gameId');
  @override
  late final GeneratedColumn<int> gameId = GeneratedColumn<int>(
    'game_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES games (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gameId,
    slot,
    filePath,
    thumbnailPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'save_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaveStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('game_id')) {
      context.handle(
        _gameIdMeta,
        gameId.isAcceptableOrUnknown(data['game_id']!, _gameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gameIdMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {gameId, slot},
  ];
  @override
  SaveStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaveStateEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      gameId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}game_id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SaveStatesTable createAlias(String alias) {
    return $SaveStatesTable(attachedDatabase, alias);
  }
}

class SaveStateEntry extends DataClass implements Insertable<SaveStateEntry> {
  final int id;
  final int gameId;
  final int slot;
  final String filePath;
  final String? thumbnailPath;
  final DateTime createdAt;
  const SaveStateEntry({
    required this.id,
    required this.gameId,
    required this.slot,
    required this.filePath,
    this.thumbnailPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['game_id'] = Variable<int>(gameId);
    map['slot'] = Variable<int>(slot);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SaveStatesCompanion toCompanion(bool nullToAbsent) {
    return SaveStatesCompanion(
      id: Value(id),
      gameId: Value(gameId),
      slot: Value(slot),
      filePath: Value(filePath),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      createdAt: Value(createdAt),
    );
  }

  factory SaveStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaveStateEntry(
      id: serializer.fromJson<int>(json['id']),
      gameId: serializer.fromJson<int>(json['gameId']),
      slot: serializer.fromJson<int>(json['slot']),
      filePath: serializer.fromJson<String>(json['filePath']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'gameId': serializer.toJson<int>(gameId),
      'slot': serializer.toJson<int>(slot),
      'filePath': serializer.toJson<String>(filePath),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SaveStateEntry copyWith({
    int? id,
    int? gameId,
    int? slot,
    String? filePath,
    Value<String?> thumbnailPath = const Value.absent(),
    DateTime? createdAt,
  }) => SaveStateEntry(
    id: id ?? this.id,
    gameId: gameId ?? this.gameId,
    slot: slot ?? this.slot,
    filePath: filePath ?? this.filePath,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    createdAt: createdAt ?? this.createdAt,
  );
  SaveStateEntry copyWithCompanion(SaveStatesCompanion data) {
    return SaveStateEntry(
      id: data.id.present ? data.id.value : this.id,
      gameId: data.gameId.present ? data.gameId.value : this.gameId,
      slot: data.slot.present ? data.slot.value : this.slot,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaveStateEntry(')
          ..write('id: $id, ')
          ..write('gameId: $gameId, ')
          ..write('slot: $slot, ')
          ..write('filePath: $filePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, gameId, slot, filePath, thumbnailPath, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaveStateEntry &&
          other.id == this.id &&
          other.gameId == this.gameId &&
          other.slot == this.slot &&
          other.filePath == this.filePath &&
          other.thumbnailPath == this.thumbnailPath &&
          other.createdAt == this.createdAt);
}

class SaveStatesCompanion extends UpdateCompanion<SaveStateEntry> {
  final Value<int> id;
  final Value<int> gameId;
  final Value<int> slot;
  final Value<String> filePath;
  final Value<String?> thumbnailPath;
  final Value<DateTime> createdAt;
  const SaveStatesCompanion({
    this.id = const Value.absent(),
    this.gameId = const Value.absent(),
    this.slot = const Value.absent(),
    this.filePath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SaveStatesCompanion.insert({
    this.id = const Value.absent(),
    required int gameId,
    required int slot,
    required String filePath,
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : gameId = Value(gameId),
       slot = Value(slot),
       filePath = Value(filePath);
  static Insertable<SaveStateEntry> custom({
    Expression<int>? id,
    Expression<int>? gameId,
    Expression<int>? slot,
    Expression<String>? filePath,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gameId != null) 'game_id': gameId,
      if (slot != null) 'slot': slot,
      if (filePath != null) 'file_path': filePath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SaveStatesCompanion copyWith({
    Value<int>? id,
    Value<int>? gameId,
    Value<int>? slot,
    Value<String>? filePath,
    Value<String?>? thumbnailPath,
    Value<DateTime>? createdAt,
  }) {
    return SaveStatesCompanion(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      slot: slot ?? this.slot,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (gameId.present) {
      map['game_id'] = Variable<int>(gameId.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SaveStatesCompanion(')
          ..write('id: $id, ')
          ..write('gameId: $gameId, ')
          ..write('slot: $slot, ')
          ..write('filePath: $filePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SettingEntriesTable extends SettingEntries
    with TableInfo<$SettingEntriesTable, SettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setting_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingEntriesTable createAlias(String alias) {
    return $SettingEntriesTable(attachedDatabase, alias);
  }
}

class SettingEntry extends DataClass implements Insertable<SettingEntry> {
  final String key;
  final String value;
  const SettingEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory SettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingEntry copyWith({String? key, String? value}) =>
      SettingEntry(key: key ?? this.key, value: value ?? this.value);
  SettingEntry copyWithCompanion(SettingEntriesCompanion data) {
    return SettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingEntry &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingEntriesCompanion extends UpdateCompanion<SettingEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingEntriesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GamesTable games = $GamesTable(this);
  late final $SaveStatesTable saveStates = $SaveStatesTable(this);
  late final $SettingEntriesTable settingEntries = $SettingEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    games,
    saveStates,
    settingEntries,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'games',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('save_states', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$GamesTableCreateCompanionBuilder = GamesCompanion Function({
  Value<int> id,
  required String title,
  required String consoleId,
  Value<String?> romPath,
  Value<String?> sha1,
  Value<int?> fileSize,
  Value<String?> coverPath,
  Value<String?> genre,
  Value<int?> releaseYear,
  Value<String?> sourceId,
  Value<String?> sourceUrl,
  required GameStatus status,
  Value<bool> isFavorite,
  Value<DateTime> addedAt,
  Value<DateTime?> lastPlayedAt,
  Value<int> playTimeSeconds,
  Value<bool> verified,
  Value<String?> remoteId,
  Value<String?> downloadUrl,
});
typedef $$GamesTableUpdateCompanionBuilder = GamesCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String> consoleId,
  Value<String?> romPath,
  Value<String?> sha1,
  Value<int?> fileSize,
  Value<String?> coverPath,
  Value<String?> genre,
  Value<int?> releaseYear,
  Value<String?> sourceId,
  Value<String?> sourceUrl,
  Value<GameStatus> status,
  Value<bool> isFavorite,
  Value<DateTime> addedAt,
  Value<DateTime?> lastPlayedAt,
  Value<int> playTimeSeconds,
  Value<bool> verified,
  Value<String?> remoteId,
  Value<String?> downloadUrl,
});

final class $$GamesTableReferences
    extends BaseReferences<_$AppDatabase, $GamesTable, Game> {
  $$GamesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SaveStatesTable, List<SaveStateEntry>>
  _saveStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.saveStates,
    aliasName: 'games__id__save_states__game_id',
  );

  $$SaveStatesTableProcessedTableManager get saveStatesRefs {
    final manager = $$SaveStatesTableTableManager(
      $_db,
      $_db.saveStates,
    ).filter((f) => f.gameId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_saveStatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GamesTableFilterComposer extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consoleId => $composableBuilder(
    column: $table.consoleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get romPath => $composableBuilder(
    column: $table.romPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha1 => $composableBuilder(
    column: $table.sha1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<GameStatus, GameStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playTimeSeconds => $composableBuilder(
    column: $table.playTimeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> saveStatesRefs(
    Expression<bool> Function($$SaveStatesTableFilterComposer f) f,
  ) {
    final $$SaveStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saveStates,
      getReferencedColumn: (t) => t.gameId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaveStatesTableFilterComposer(
            $db: $db,
            $table: $db.saveStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GamesTableOrderingComposer
    extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consoleId => $composableBuilder(
    column: $table.consoleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get romPath => $composableBuilder(
    column: $table.romPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha1 => $composableBuilder(
    column: $table.sha1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playTimeSeconds => $composableBuilder(
    column: $table.playTimeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GamesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GamesTable> {
  $$GamesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get consoleId =>
      $composableBuilder(column: $table.consoleId, builder: (column) => column);

  GeneratedColumn<String> get romPath =>
      $composableBuilder(column: $table.romPath, builder: (column) => column);

  GeneratedColumn<String> get sha1 =>
      $composableBuilder(column: $table.sha1, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<GameStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playTimeSeconds => $composableBuilder(
    column: $table.playTimeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get downloadUrl => $composableBuilder(
    column: $table.downloadUrl,
    builder: (column) => column,
  );

  Expression<T> saveStatesRefs<T extends Object>(
    Expression<T> Function($$SaveStatesTableAnnotationComposer a) f,
  ) {
    final $$SaveStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.saveStates,
      getReferencedColumn: (t) => t.gameId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SaveStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.saveStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GamesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GamesTable,
          Game,
          $$GamesTableFilterComposer,
          $$GamesTableOrderingComposer,
          $$GamesTableAnnotationComposer,
          $$GamesTableCreateCompanionBuilder,
          $$GamesTableUpdateCompanionBuilder,
          (Game, $$GamesTableReferences),
          Game,
          PrefetchHooks Function({bool saveStatesRefs})
        > {
  $$GamesTableTableManager(_$AppDatabase db, $GamesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GamesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GamesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GamesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> consoleId = const Value.absent(),
                Value<String?> romPath = const Value.absent(),
                Value<String?> sha1 = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> releaseYear = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                Value<GameStatus> status = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> playTimeSeconds = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> downloadUrl = const Value.absent(),
              }) => GamesCompanion(
                id: id,
                title: title,
                consoleId: consoleId,
                romPath: romPath,
                sha1: sha1,
                fileSize: fileSize,
                coverPath: coverPath,
                genre: genre,
                releaseYear: releaseYear,
                sourceId: sourceId,
                sourceUrl: sourceUrl,
                status: status,
                isFavorite: isFavorite,
                addedAt: addedAt,
                lastPlayedAt: lastPlayedAt,
                playTimeSeconds: playTimeSeconds,
                verified: verified,
                remoteId: remoteId,
                downloadUrl: downloadUrl,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String consoleId,
                Value<String?> romPath = const Value.absent(),
                Value<String?> sha1 = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> releaseYear = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> sourceUrl = const Value.absent(),
                required GameStatus status,
                Value<bool> isFavorite = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> playTimeSeconds = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> downloadUrl = const Value.absent(),
              }) => GamesCompanion.insert(
                id: id,
                title: title,
                consoleId: consoleId,
                romPath: romPath,
                sha1: sha1,
                fileSize: fileSize,
                coverPath: coverPath,
                genre: genre,
                releaseYear: releaseYear,
                sourceId: sourceId,
                sourceUrl: sourceUrl,
                status: status,
                isFavorite: isFavorite,
                addedAt: addedAt,
                lastPlayedAt: lastPlayedAt,
                playTimeSeconds: playTimeSeconds,
                verified: verified,
                remoteId: remoteId,
                downloadUrl: downloadUrl,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GamesTable, Game>(table),
                  $$GamesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({saveStatesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (saveStatesRefs) db.saveStates],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (saveStatesRefs)
                    await $_getPrefetchedDataByColumns<
                      Game,
                      $GamesTable,
                      SaveStateEntry,
                      $SaveStatesTable
                    >(
                      currentTable: table,
                      referencedTable: $$GamesTableReferences
                          ._saveStatesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$GamesTableReferences(db, table, p0).saveStatesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'game_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GamesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GamesTable,
      Game,
      $$GamesTableFilterComposer,
      $$GamesTableOrderingComposer,
      $$GamesTableAnnotationComposer,
      $$GamesTableCreateCompanionBuilder,
      $$GamesTableUpdateCompanionBuilder,
      (Game, $$GamesTableReferences),
      Game,
      PrefetchHooks Function({bool saveStatesRefs})
    >;
typedef $$SaveStatesTableCreateCompanionBuilder = SaveStatesCompanion Function({
  Value<int> id,
  required int gameId,
  required int slot,
  required String filePath,
  Value<String?> thumbnailPath,
  Value<DateTime> createdAt,
});
typedef $$SaveStatesTableUpdateCompanionBuilder = SaveStatesCompanion Function({
  Value<int> id,
  Value<int> gameId,
  Value<int> slot,
  Value<String> filePath,
  Value<String?> thumbnailPath,
  Value<DateTime> createdAt,
});

final class $$SaveStatesTableReferences
    extends BaseReferences<_$AppDatabase, $SaveStatesTable, SaveStateEntry> {
  $$SaveStatesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GamesTable _gameIdTable(_$AppDatabase db) =>
      db.games.createAlias('save_states__game_id__games__id');

  $$GamesTableProcessedTableManager get gameId {
    final $_column = $_itemColumn<int>('game_id')!;

    final manager = $$GamesTableTableManager(
      $_db,
      $_db.games,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_gameIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SaveStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SaveStatesTable> {
  $$SaveStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$GamesTableFilterComposer get gameId {
    final $$GamesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableFilterComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaveStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SaveStatesTable> {
  $$SaveStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GamesTableOrderingComposer get gameId {
    final $$GamesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableOrderingComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaveStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SaveStatesTable> {
  $$SaveStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$GamesTableAnnotationComposer get gameId {
    final $$GamesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.gameId,
      referencedTable: $db.games,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GamesTableAnnotationComposer(
            $db: $db,
            $table: $db.games,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SaveStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SaveStatesTable,
          SaveStateEntry,
          $$SaveStatesTableFilterComposer,
          $$SaveStatesTableOrderingComposer,
          $$SaveStatesTableAnnotationComposer,
          $$SaveStatesTableCreateCompanionBuilder,
          $$SaveStatesTableUpdateCompanionBuilder,
          (SaveStateEntry, $$SaveStatesTableReferences),
          SaveStateEntry,
          PrefetchHooks Function({bool gameId})
        > {
  $$SaveStatesTableTableManager(_$AppDatabase db, $SaveStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaveStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaveStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaveStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> gameId = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SaveStatesCompanion(
                id: id,
                gameId: gameId,
                slot: slot,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int gameId,
                required int slot,
                required String filePath,
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SaveStatesCompanion.insert(
                id: id,
                gameId: gameId,
                slot: slot,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SaveStatesTable, SaveStateEntry>(table),
                  $$SaveStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({gameId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (gameId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.gameId,
                        referencedTable: $$SaveStatesTableReferences
                            ._gameIdTable(db),
                        referencedColumn: $$SaveStatesTableReferences
                            ._gameIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SaveStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SaveStatesTable,
      SaveStateEntry,
      $$SaveStatesTableFilterComposer,
      $$SaveStatesTableOrderingComposer,
      $$SaveStatesTableAnnotationComposer,
      $$SaveStatesTableCreateCompanionBuilder,
      $$SaveStatesTableUpdateCompanionBuilder,
      (SaveStateEntry, $$SaveStatesTableReferences),
      SaveStateEntry,
      PrefetchHooks Function({bool gameId})
    >;
typedef $$SettingEntriesTableCreateCompanionBuilder =
    SettingEntriesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingEntriesTableUpdateCompanionBuilder =
    SettingEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingEntriesTable,
          SettingEntry,
          $$SettingEntriesTableFilterComposer,
          $$SettingEntriesTableOrderingComposer,
          $$SettingEntriesTableAnnotationComposer,
          $$SettingEntriesTableCreateCompanionBuilder,
          $$SettingEntriesTableUpdateCompanionBuilder,
          (
            SettingEntry,
            BaseReferences<_$AppDatabase, $SettingEntriesTable, SettingEntry>,
          ),
          SettingEntry,
          PrefetchHooks Function()
        > {
  $$SettingEntriesTableTableManager(
    _$AppDatabase db,
    $SettingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingEntriesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingEntriesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingEntriesTable, SettingEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SettingEntriesTable,
                    SettingEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingEntriesTable,
      SettingEntry,
      $$SettingEntriesTableFilterComposer,
      $$SettingEntriesTableOrderingComposer,
      $$SettingEntriesTableAnnotationComposer,
      $$SettingEntriesTableCreateCompanionBuilder,
      $$SettingEntriesTableUpdateCompanionBuilder,
      (
        SettingEntry,
        BaseReferences<_$AppDatabase, $SettingEntriesTable, SettingEntry>,
      ),
      SettingEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GamesTableTableManager get games =>
      $$GamesTableTableManager(_db, _db.games);
  $$SaveStatesTableTableManager get saveStates =>
      $$SaveStatesTableTableManager(_db, _db.saveStates);
  $$SettingEntriesTableTableManager get settingEntries =>
      $$SettingEntriesTableTableManager(_db, _db.settingEntries);
}
