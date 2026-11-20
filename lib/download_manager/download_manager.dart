import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../game_library/game_repository.dart';
import '../game_library/rom_importer.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';

enum DownloadPhase {
  queued('En cola'),
  running('Descargando'),
  paused('En pausa'),
  verifying('Verificando'),
  completed('Completada'),
  failed('Error'),
  canceled('Cancelada');

  const DownloadPhase(this.label);
  final String label;

  bool get isActive => this == queued || this == running || this == paused || this == verifying;
}

/// Estado visible de una descarga.
class DownloadEntry {
  const DownloadEntry({
    required this.taskId,
    required this.gameId,
    required this.title,
    required this.fileName,
    required this.url,
    required this.phase,
    this.progress = 0,
    this.totalBytes,
    this.speedMBs,
    this.remaining,
    this.error,
    this.canResume = false,
    required this.updatedAt,
  });

  final String taskId;
  final int gameId;
  final String title;
  final String fileName;
  final String url;
  final DownloadPhase phase;
  final double progress; // 0..1
  final int? totalBytes;
  final double? speedMBs;
  final Duration? remaining;
  final String? error;

  /// El servidor admite reanudar (cabecera Range).
  final bool canResume;
  final DateTime updatedAt;

  int? get receivedBytes => totalBytes == null ? null : (totalBytes! * progress).round();

  DownloadEntry copyWith({
    DownloadPhase? phase,
    double? progress,
    int? totalBytes,
    double? Function()? speedMBs,
    Duration? Function()? remaining,
    String? Function()? error,
    bool? canResume,
  }) =>
      DownloadEntry(
        taskId: taskId,
        gameId: gameId,
        title: title,
        fileName: fileName,
        url: url,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        totalBytes: totalBytes ?? this.totalBytes,
        speedMBs: speedMBs != null ? speedMBs() : this.speedMBs,
        remaining: remaining != null ? remaining() : this.remaining,
        error: error != null ? error() : this.error,
        canResume: canResume ?? this.canResume,
        updatedAt: DateTime.now(),
      );
}

/// Gestor de descargas real sobre `background_downloader`:
/// - Android: WorkManager (sigue en segundo plano); iOS: URLSession en segundo plano.
/// - Progreso, velocidad, tiempo restante y tamaño total.
/// - Pausa/reanudación si el servidor admite `Range`; reintentos automáticos.
/// - Al terminar: verificación (hash si existe, cabecera, ZIP) e incorporación
///   a la biblioteca; el archivo temporal se borra siempre.
class DownloadController extends Notifier<Map<String, DownloadEntry>> {
  static const group = 'roms';
  StreamSubscription<TaskUpdate>? _sub;

  FileDownloader get _fd => FileDownloader();
  AppDatabase get _db => ref.read(databaseProvider);
  AppPaths get _paths => ref.read(appPathsProvider);

  @override
  Map<String, DownloadEntry> build() {
    ref.onDispose(() => _sub?.cancel());
    _sub = _fd.updates.listen(_onUpdate);
    unawaited(_restore());
    return const {};
  }

  /// Recupera el historial (la base de datos de tareas sobrevive a reinicios)
  /// y borra archivos parciales que ya no pertenecen a ninguna descarga.
  Future<void> _restore() async {
    final records = await _fd.database.allRecords(group: group);
    final entries = <String, DownloadEntry>{};
    for (final r in records) {
      final entry = _entryFromTask(r.task, _phaseFor(r.status), progress: r.progress.clamp(0, 1),
          total: r.expectedFileSize > 0 ? r.expectedFileSize : null,
          error: r.exception?.description);
      if (entry != null) entries[r.taskId] = entry;
    }
    state = {...entries, ...state};
    await _cleanOrphans(entries.values.where((e) => e.phase.isActive).map((e) => e.fileName).toSet());
  }

  Future<void> _cleanOrphans(Set<String> activeFiles) async {
    final dir = _paths.downloads;
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is File && !activeFiles.contains(p.basename(f.path))) {
        await f.delete();
      }
    }
  }

  DownloadEntry? _entryFromTask(Task task, DownloadPhase phase,
      {double progress = 0, int? total, String? error}) {
    final meta = _meta(task);
    final gameId = meta?['gameId'];
    if (gameId is! int) return null;
    return DownloadEntry(
      taskId: task.taskId,
      gameId: gameId,
      title: task.displayName.isEmpty ? task.filename : task.displayName,
      fileName: task.filename,
      url: task.url,
      phase: phase,
      progress: progress,
      totalBytes: total,
      error: error,
      updatedAt: DateTime.now(),
    );
  }

  static Map<String, dynamic>? _meta(Task task) {
    try {
      return jsonDecode(task.metaData) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  static DownloadPhase _phaseFor(TaskStatus s) => switch (s) {
        TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadPhase.queued,
        TaskStatus.running => DownloadPhase.running,
        TaskStatus.paused => DownloadPhase.paused,
        TaskStatus.complete => DownloadPhase.completed,
        TaskStatus.canceled => DownloadPhase.canceled,
        TaskStatus.failed || TaskStatus.notFound => DownloadPhase.failed,
      };

  /// Descarga el archivo de un juego pendiente guardado desde Descubrir.
  Future<void> enqueueForGame(int gameId, {String? expectedSha1}) async {
    final game = await ref.read(gameRepositoryProvider).watchById(gameId).first;
    if (game == null) throw StateError('El juego ya no existe');
    if (game.status == GameStatus.installed) throw StateError('Este juego ya está descargado');
    final url = game.downloadUrl;
    if (url == null) throw StateError('Esta fuente no ofrece descarga directa');
    await _enqueue(gameId, game.title, Uri.parse(url), expectedSha1: expectedSha1);
  }

  /// Descarga un archivo que ha entregado la página original de la fuente
  /// (navegador integrado). El usuario ha pulsado el botón de descarga de la
  /// propia web; aquí solo se recoge el archivo. Se valida igual que el resto.
  Future<void> enqueueUrlForGame(
    int gameId,
    Uri url, {
    String? fileName,
    Map<String, String> headers = const {},
  }) async {
    final game = await ref.read(gameRepositoryProvider).watchById(gameId).first;
    if (game == null) throw StateError('El juego ya no existe');
    if (game.status == GameStatus.installed) throw StateError('Este juego ya está descargado');
    await _enqueue(gameId, game.title, url, fileName: fileName, headers: headers);
  }

  Future<void> _enqueue(
    int gameId,
    String title,
    Uri uri, {
    String? fileName,
    String? expectedSha1,
    Map<String, String> headers = const {},
  }) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('Tipo de enlace no admitido (${uri.scheme})');
    }
    if (state.values.any((e) => e.gameId == gameId && e.phase.isActive)) return; // evita duplicados
    final name = sanitizeFileName(fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : (uri.pathSegments.isEmpty ? 'descarga' : Uri.decodeComponent(uri.pathSegments.last)));
    final task = DownloadTask(
      url: uri.toString(),
      headers: headers,
      filename: name,
      directory: p.relative(_paths.downloads.path, from: p.dirname(_paths.root.path)),
      baseDirectory: BaseDirectory.applicationSupport,
      group: group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      displayName: title,
      metaData: jsonEncode({'gameId': gameId, 'sha1': ?expectedSha1}),
    );
    await _paths.downloads.create(recursive: true);
    // Android 13+: permiso para mostrar el progreso en la barra de notificaciones.
    // Si se deniega, la descarga funciona igual (sin notificación).
    if (await _fd.permissions.status(PermissionType.notifications) != PermissionStatus.granted) {
      await _fd.permissions.request(PermissionType.notifications);
    }
    await _setGameStatus(gameId, GameStatus.downloading);
    state = {
      ...state,
      task.taskId: _entryFromTask(task, DownloadPhase.queued)!,
    };
    if (!await _fd.enqueue(task)) {
      await _setGameStatus(gameId, GameStatus.pending);
      _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.failed, error: () => 'No se pudo encolar'));
    }
  }

  Future<void> _setGameStatus(int gameId, GameStatus status) =>
      (_db.update(_db.games)..where((g) => g.id.equals(gameId)))
          .write(GamesCompanion(status: Value(status)));

  void _patch(String taskId, DownloadEntry Function(DownloadEntry) f) {
    final e = state[taskId];
    if (e == null) return;
    state = {...state, taskId: f(e)};
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final task = update.task;
    if (task.group != group) return;
    if (!state.containsKey(task.taskId)) {
      final entry = _entryFromTask(task, DownloadPhase.queued);
      if (entry == null) return;
      state = {...state, task.taskId: entry};
    }
    switch (update) {
      case TaskProgressUpdate():
        if (update.progress < 0) return; // valores especiales (fallo/pausa/cancelación)
        _patch(task.taskId, (e) => e.copyWith(
              phase: DownloadPhase.running,
              progress: update.progress,
              totalBytes: update.hasExpectedFileSize ? update.expectedFileSize : null,
              speedMBs: () => update.hasNetworkSpeed ? update.networkSpeed : null,
              remaining: () => update.hasTimeRemaining ? update.timeRemaining : null,
            ));
      case TaskStatusUpdate(:final status):
        final gameId = state[task.taskId]!.gameId;
        switch (status) {
          case TaskStatus.running:
            final canResume = task is DownloadTask && await _fd.taskCanResume(task);
            _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.running, canResume: canResume, error: () => null));
          case TaskStatus.complete:
            await _finalize(task, gameId);
          case TaskStatus.failed || TaskStatus.notFound:
            await _setGameStatus(gameId, GameStatus.pending);
            _patch(task.taskId, (e) => e.copyWith(
                  phase: DownloadPhase.failed,
                  speedMBs: () => null,
                  remaining: () => null,
                  error: () => status == TaskStatus.notFound
                      ? 'El archivo ya no existe en el servidor (404)'
                      : (update.exception?.description ?? 'Error de red'),
                ));
          case TaskStatus.canceled:
            await _setGameStatus(gameId, GameStatus.pending);
            _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.canceled, speedMBs: () => null, remaining: () => null));
          case TaskStatus.paused:
            _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.paused, speedMBs: () => null, remaining: () => null));
          case TaskStatus.enqueued || TaskStatus.waitingToRetry:
            _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.queued));
        }
    }
  }

  Future<void> _finalize(Task task, int gameId) async {
    _patch(task.taskId, (e) => e.copyWith(phase: DownloadPhase.verifying, progress: 1, speedMBs: () => null, remaining: () => null));
    final path = await task.filePath();
    String? error;
    try {
      error = await ref.read(romImporterProvider).attachDownload(
            gameId,
            path,
            expectedSha1: _meta(task)?['sha1'] as String?,
          );
    } catch (e) {
      error = 'No se pudo procesar el archivo: $e';
    } finally {
      final f = File(path);
      if (await f.exists()) await f.delete(); // nunca quedan archivos sueltos
    }
    if (error != null) await _setGameStatus(gameId, GameStatus.pending);
    _patch(task.taskId, (e) => e.copyWith(
          phase: error == null ? DownloadPhase.completed : DownloadPhase.failed,
          error: () => error,
        ));
  }

  Future<DownloadTask?> _task(String taskId) async {
    final t = await _fd.taskForId(taskId) ?? (await _fd.database.recordForId(taskId))?.task;
    return t is DownloadTask ? t : null;
  }

  Future<bool> pause(String taskId) async {
    final task = await _task(taskId);
    return task != null && await _fd.pause(task);
  }

  Future<bool> resume(String taskId) async {
    final task = await _task(taskId);
    return task != null && await _fd.resume(task);
  }

  Future<void> cancel(String taskId) => _fd.cancelTaskWithId(taskId);

  /// Vuelve a intentar una descarga fallida o cancelada (desde cero).
  Future<void> retry(String taskId) async {
    final entry = state[taskId];
    if (entry == null) return;
    await remove(taskId);
    final game = await ref.read(gameRepositoryProvider).watchById(entry.gameId).first;
    if (game?.downloadUrl != null) {
      await enqueueForGame(entry.gameId);
    } else {
      // Enlace entregado por la página original: puede haber caducado; si es
      // así, el error lo indicará y habrá que volver a pulsar en la página.
      await _enqueue(entry.gameId, entry.title, Uri.parse(entry.url), fileName: entry.fileName);
    }
  }

  /// Quita una descarga terminada del historial.
  Future<void> remove(String taskId) async {
    await _fd.database.deleteRecordWithId(taskId);
    state = {...state}..remove(taskId);
  }
}

final downloadsProvider =
    NotifierProvider<DownloadController, Map<String, DownloadEntry>>(DownloadController.new);

/// Acceso a las acciones del gestor (iniciar, pausar, reanudar...).
final downloadManagerProvider = Provider<DownloadController>((ref) => ref.watch(downloadsProvider.notifier));
