import 'package:drift/drift.dart';

import 'app_paths.dart';
import 'database.dart';

/// En iPhone, la carpeta de la app cambia de nombre
/// (`.../Application/<UUID>/...`) cada vez que se instala una versión nueva.
/// Las rutas guardadas en la base de datos (ROMs, portadas, save states)
/// apuntaban a la carpeta anterior y los juegos dejaban de abrirse: PPSSPP
/// incluso cerraba la app al no encontrar el ISO.
///
/// Si [stored] está dentro de una carpeta `retrostation` que no es la
/// actual ([root]), devuelve la misma ruta dentro de [root]; si no, null.
String? relocatedPath(String? stored, String root) {
  if (stored == null || stored.isEmpty) return null;
  final normalizedRoot = root.replaceAll('\\', '/');
  final path = stored.replaceAll('\\', '/');
  if (path.startsWith('$normalizedRoot/')) return null;
  const marker = '/retrostation/';
  final i = path.lastIndexOf(marker);
  if (i < 0) return null;
  return '$normalizedRoot/${path.substring(i + marker.length)}';
}

/// Actualiza en la base de datos las rutas que quedaron en una carpeta de
/// instalación anterior. Devuelve cuántas filas se corrigieron.
Future<int> relocateStoredPaths(AppDatabase db, AppPaths paths) async {
  final root = paths.root.path;
  var fixed = 0;
  await db.transaction(() async {
    for (final g in await db.select(db.games).get()) {
      final rom = relocatedPath(g.romPath, root);
      final cover = relocatedPath(g.coverPath, root);
      if (rom == null && cover == null) continue;
      await (db.update(db.games)..where((t) => t.id.equals(g.id))).write(GamesCompanion(
        romPath: rom == null ? const Value.absent() : Value(rom),
        coverPath: cover == null ? const Value.absent() : Value(cover),
      ));
      fixed++;
    }
    for (final s in await db.select(db.saveStates).get()) {
      final file = relocatedPath(s.filePath, root);
      final thumb = relocatedPath(s.thumbnailPath, root);
      if (file == null && thumb == null) continue;
      await (db.update(db.saveStates)..where((t) => t.id.equals(s.id))).write(SaveStatesCompanion(
        filePath: file == null ? const Value.absent() : Value(file),
        thumbnailPath: thumb == null ? const Value.absent() : Value(thumb),
      ));
      fixed++;
    }
  });
  return fixed;
}
