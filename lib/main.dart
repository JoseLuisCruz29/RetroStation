import 'controllers/gamepad.dart';
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'brand/boot_splash.dart';
import 'game_library/bundled_games.dart';
import 'game_library/rom_importer.dart';
import 'game_library/rom_scanner.dart';
import 'metadata/metadata_service.dart';
import 'settings/app_settings.dart';
import 'storage/app_paths.dart';
import 'storage/database.dart';
import 'storage/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mandos del PC: se escuchan desde el arranque para saber cuáles hay conectados.
  Gamepads.instance;
  // Pantalla de carga con el logo mientras se prepara todo lo demás.
  runApp(const BootSplash());
  Intl.defaultLocale = 'es';
  await initializeDateFormatting('es');

  // Licencias de los núcleos nativos (no las detecta pub automáticamente).
  LicenseRegistry.addLicense(() async* {
    const cores = [
      ('mGBA 0.10.5 (GBA, GB, GBC)', 'native/third_party/mgba/LICENSE',
          'https://github.com/mgba-emu/mgba (etiqueta 0.10.5)'),
      ('FCEUmm (NES)', 'native/third_party/fceumm/Copying',
          'https://github.com/libretro/libretro-fceumm (commit e0f3086a)'),
      ('Snes9x (SNES, uso no comercial)', 'native/third_party/snes9x/LICENSE',
          'https://github.com/libretro/snes9x (commit fae2fea0)'),
      ('PCSX ReARMed (PlayStation)', 'native/third_party/pcsx_rearmed/COPYING',
          'https://github.com/libretro/pcsx_rearmed (commit 7b0e8f8f)'),
      ('melonDS (Nintendo DS)', 'native/third_party/melonds/LICENSE',
          'https://github.com/libretro/melonDS (commit fab81072, con un parche de compilación para Android)'),
      ('DeSmuME 2015 (Nintendo DS en Android de 32 bits)',
          'native/third_party/desmume2015/desmume/COPYING',
          'https://github.com/libretro/desmume2015 (commit 422b6880)'),
      ('PPSSPP (PlayStation Portable)', 'native/third_party/ppsspp/LICENSE.TXT',
          'https://github.com/hrydgard/ppsspp (commit 9416bbc)'),
      ('gpSP (cable link de GBA en el multijugador LAN)', 'native/third_party/gpsp/COPYING',
          'https://github.com/libretro/gpsp (commit 5819380)'),
    ];
    for (final (name, asset, source) in cores) {
      final text = await rootBundle.loadString(asset);
      yield LicenseEntryWithLineBreaks([name], 'Código fuente: $source\n\n$text');
    }
    // Juegos incluidos en el APK: autor, licencia y dónde está su código fuente.
    for (final info in (await BundledGamesInstaller.loadInfo()).values) {
      yield LicenseEntryWithLineBreaks(
        ['${info.title ?? info.file} (juego incluido)'],
        [
          if (info.developer != null) 'Autor: ${info.developer}',
          if (info.license != null) 'Licencia: ${info.license}',
          if (info.source != null) 'Código fuente: ${info.source}',
          if (info.page != null) 'Ficha: ${info.page}',
        ].join('\n'),
      );
    }
  });

  final paths = await AppPaths.init();
  final db = AppDatabase.openDefault();
  final settings = await SettingsRepository(db).load();

  // Gestor de descargas: notificaciones de progreso y recuperación de tareas
  // tras un cierre (las tareas se guardan en su propia base de datos).
  FileDownloader().configureNotification(
    running: const TaskNotification('Descargando', '{displayName} · {progress}'),
    complete: const TaskNotification('Descarga completada', '{displayName}'),
    error: const TaskNotification('Error de descarga', '{displayName}'),
    paused: const TaskNotification('Descarga en pausa', '{displayName}'),
    progressBar: true,
  );
  await FileDownloader().start();

  // En segundo plano: primero los juegos incluidos en el APK (solo los que no
  // se instalaron antes) y después la detección de ROMs nuevos en la carpeta
  // privada. En ese orden, para que el escáner no los añada por su cuenta.
  unawaited(() async {
    try {
      await BundledGamesInstaller(db, paths, RomImporter(db, paths)).installNew();
    } catch (e) {
      debugPrint('Juegos incluidos: $e');
    }
    final result = await RomScanner(db, paths).scan();
    for (final r in result.rejected) {
      debugPrint('ROM rechazado: ${r.path} (${r.reason})');
    }
    // Portadas: los juegos que aún no tienen (los incluidos en el APK o
    // copiados a la carpeta) se identifican y se busca su portada si hay
    // conexión. Los ya identificados no se vuelven a consultar.
    try {
      final pending = await (db.select(db.games)
            ..where((g) => g.coverPath.isNull() & g.verified.equals(false)))
          .get();
      final metadata = MetadataService(db, paths);
      for (final game in pending) {
        if (await metadata.enrich(game) == EnrichResult.offline) break; // sin red: otro día
      }
    } catch (e) {
      debugPrint('Portadas automáticas: $e');
    }
  }());

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appPathsProvider.overrideWithValue(paths),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const RetroStationApp(),
    ),
  );
}
