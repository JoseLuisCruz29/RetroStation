import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Directorios privados de RetroStation. Todo vive dentro del sandbox de la
/// app: otras aplicaciones no pueden leerlo y se borra al desinstalar.
class AppPaths {
  AppPaths(this.root);

  final Directory root;

  Directory get roms => _dir('roms');
  Directory get saves => _dir('saves');
  Directory get states => _dir('states');
  Directory get covers => _dir('covers');
  Directory get downloads => _dir('downloads');

  /// Archivos de sistema de los núcleos (p. ej. BIOS opcionales).
  Directory get system => _dir('system');

  /// Carpetas con su nombre visible, en el orden en que se muestran.
  Map<String, Directory> get named => {
        'ROMs': roms,
        'Partidas (SRAM)': saves,
        'Save states': states,
        'Portadas': covers,
        'Descargas': downloads,
      };

  Directory _dir(String name) => Directory(p.join(root.path, name));

  static Future<AppPaths> init() async {
    final support = await getApplicationSupportDirectory();
    final paths = AppPaths(Directory(p.join(support.path, 'retrostation')));
    await paths.ensureCreated();
    return paths;
  }

  Future<void> ensureCreated() async {
    for (final dir in [...named.values, system]) {
      await dir.create(recursive: true);
    }
  }

  /// Comprueba que [path] está dentro del directorio raíz. Se usará para
  /// validar extracciones de archivos y rutas importadas.
  bool contains(String path) =>
      p.isWithin(p.normalize(root.path), p.normalize(p.absolute(path)));

  /// Calcula el espacio ocupado por cada carpeta en un isolate aparte para no
  /// bloquear la interfaz.
  Future<Map<String, int>> usage() {
    final entries = named.map((k, v) => MapEntry(k, v.path));
    return Isolate.run(() => {
          for (final e in entries.entries) e.key: _dirSize(e.value),
        });
  }
}

int _dirSize(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  var total = 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) total += entity.lengthSync();
  }
  return total;
}
