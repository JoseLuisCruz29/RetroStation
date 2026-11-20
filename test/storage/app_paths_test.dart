import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_env.dart';

void main() {
  test('crea las carpetas y calcula su tamaño', () async {
    final paths = await tempPaths();
    addTearDown(() => paths.root.delete(recursive: true));

    for (final dir in paths.named.values) {
      expect(dir.existsSync(), isTrue);
    }
    await File(p.join(paths.roms.path, 'a.gba')).writeAsBytes(List.filled(1000, 1));
    final usage = await paths.usage();
    expect(usage['ROMs'], 1000);
    expect(usage['Portadas'], 0);
  });

  test('contains rechaza rutas que escapan del directorio', () async {
    final paths = await tempPaths();
    addTearDown(() => paths.root.delete(recursive: true));

    expect(paths.contains(p.join(paths.roms.path, 'juego.gba')), isTrue);
    expect(paths.contains(p.join(paths.roms.path, '..', '..', 'x')), isFalse);
    expect(paths.contains(p.join(paths.root.path, '..', 'otro')), isFalse);
  });
}
