import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../emulation/emulator_session.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';

/// Save states por ranura: archivo del núcleo + miniatura PNG + registro en
/// la base de datos. Al sobrescribir una ranura se conserva la versión
/// anterior como copia de seguridad (`.bak`).
class SaveStateService {
  SaveStateService(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;

  static const slotCount = 6;

  Directory gameDir(Game game) =>
      Directory(p.join(_paths.states.path, game.sha1 ?? 'game_${game.id}'));

  String statePath(Game game, int slot) => p.join(gameDir(game).path, 'slot$slot.state');
  String thumbPath(Game game, int slot) => p.join(gameDir(game).path, 'slot$slot.png');

  Stream<List<SaveStateEntry>> watchForGame(int gameId) =>
      (_db.select(_db.saveStates)
            ..where((s) => s.gameId.equals(gameId))
            ..orderBy([(s) => OrderingTerm.asc(s.slot)]))
          .watch();

  Future<void> save(EmulatorSession session, Game game, int slot) async {
    await gameDir(game).create(recursive: true);
    final path = statePath(game, slot);
    final thumb = thumbPath(game, slot);

    // Copia de seguridad de la ranura anterior.
    for (final file in [path, thumb]) {
      final f = File(file);
      if (await f.exists()) await f.copy('$file.bak');
    }

    session.saveState(path);
    final png = await _thumbnailPng(session);
    if (png != null) {
      await File('$thumb.tmp').writeAsBytes(png, flush: true);
      await File('$thumb.tmp').rename(thumb);
      // La ruta no cambia al sobrescribir: hay que invalidar la caché de imágenes.
      await FileImage(File(thumb)).evict();
    }

    await _db.into(_db.saveStates).insert(
          SaveStatesCompanion.insert(
            gameId: game.id,
            slot: slot,
            filePath: path,
            thumbnailPath: Value(png != null ? thumb : null),
            createdAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  void load(EmulatorSession session, Game game, int slot) =>
      session.loadState(statePath(game, slot));

  Future<Uint8List?> _thumbnailPng(EmulatorSession session) async {
    final frame = session.copyFrame();
    if (frame == null) return null;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

final saveStateServiceProvider = Provider<SaveStateService>(
  (ref) => SaveStateService(ref.watch(databaseProvider), ref.watch(appPathsProvider)),
);

final gameSaveStatesProvider = StreamProvider.family<List<SaveStateEntry>, int>(
  (ref, gameId) => ref.watch(saveStateServiceProvider).watchForGame(gameId),
);
