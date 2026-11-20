import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Archivos de sistema que PPSSPP busca en `<system>/PPSSPP`: base de datos de
/// compatibilidad, regiones, funciones conocidas, el atlas de los menús del
/// sistema de la PSP (PPGe) y sus fuentes (flash0/font). Van dentro del APK en
/// `assets/ppsspp/` y se copian la primera vez que se abre un juego de PSP.
abstract final class PpssppAssets {
  static const _prefix = 'assets/ppsspp/';

  /// Cambiar al actualizar los archivos de assets/ppsspp para que se recopien.
  static const version = '9416bbc';

  static Future<void> ensureInstalled(String systemDir) async {
    final root = Directory(p.join(systemDir, 'PPSSPP'));
    final marker = File(p.join(root.path, '.retrostation_assets'));
    if (await marker.exists() && (await marker.readAsString()).trim() == version) return;

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where((a) => a.startsWith(_prefix)).toList();
    for (final asset in assets) {
      final relative = asset.substring(_prefix.length);
      final out = File(p.joinAll([root.path, ...relative.split('/')]));
      await out.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
    }
    await marker.writeAsString(version, flush: true);
  }
}
