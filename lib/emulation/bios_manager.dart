import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';
import '../storage/storage_providers.dart';

/// BIOS opcional de un sistema. RetroStation no incluye ninguna BIOS: el
/// usuario puede aportar su propio volcado; sin ella se usa la emulación HLE.
class BiosSpec {
  const BiosSpec({
    required this.consoleId,
    required this.fileName,
    required this.size,
    required this.sha1,
    required this.description,
  });

  final String consoleId;
  final String fileName;
  final int size;
  final String sha1;
  final String description;
}

class BiosManager {
  BiosManager(this._paths);

  final AppPaths _paths;

  static const gba = BiosSpec(
    consoleId: 'gba',
    fileName: 'gba_bios.bin',
    size: 16384,
    // Huella pública del BIOS oficial de GBA (base de datos de libretro).
    sha1: '300c20df6731a33952ded8c436f7f186d25d3492',
    description: 'BIOS de Game Boy Advance',
  );

  File fileFor(BiosSpec spec) => File(p.join(_paths.system.path, spec.fileName));

  bool isInstalled(BiosSpec spec) => fileFor(spec).existsSync();

  /// Copia la BIOS tras comprobar tamaño y SHA-1. Devuelve null si es válida
  /// o el motivo del rechazo.
  Future<String?> install(BiosSpec spec, String sourcePath) async {
    final source = File(sourcePath);
    final size = await source.length();
    if (size != spec.size) {
      return 'Tamaño incorrecto: ${spec.description} debe ocupar ${spec.size} bytes';
    }
    final bytes = await source.readAsBytes();
    final hash = sha1.convert(bytes).toString();
    if (hash != spec.sha1) {
      return 'El archivo no coincide con un volcado conocido de la ${spec.description}';
    }
    await _paths.system.create(recursive: true);
    final target = fileFor(spec);
    await File('${target.path}.tmp').writeAsBytes(bytes, flush: true);
    await File('${target.path}.tmp').rename(target.path);
    return null;
  }

  Future<void> remove(BiosSpec spec) async {
    final f = fileFor(spec);
    if (await f.exists()) await f.delete();
  }
}

final biosManagerProvider =
    Provider<BiosManager>((ref) => BiosManager(ref.watch(appPathsProvider)));
