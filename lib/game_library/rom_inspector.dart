import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../engines/console_registry.dart';

/// Resultado de examinar un archivo candidato a ROM.
sealed class RomInspection {
  const RomInspection(this.path);
  final String path;
}

class ValidRom extends RomInspection {
  const ValidRom(
    super.path, {
    required this.consoleId,
    required this.title,
    required this.sha1,
    required this.size,
  });

  final String consoleId;
  final String title;
  final String sha1;
  final int size;
}

class RejectedRom extends RomInspection {
  const RejectedRom(super.path, this.reason);
  final String reason;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Validación de cabeceras y huella SHA-1. Funciones puras: se ejecutan en
/// un isolate aparte desde [RomScanner].
abstract final class RomInspector {
  /// Tamaño máximo de un cartucho GBA (32 MB).
  static const gbaMaxSize = 32 * 1024 * 1024;

  static RomInspection inspect(String path) {
    final file = File(path);
    final ext = p.extension(path);
    final console = ConsoleRegistry.byExtension(ext);
    if (console == null) return RejectedRom(path, 'Extensión no reconocida ($ext)');

    final size = file.lengthSync();
    switch (console.id) {
      case 'gba':
        if (size < 0xC0) return RejectedRom(path, 'Archivo demasiado pequeño');
        if (size > gbaMaxSize) return RejectedRom(path, 'Mayor de 32 MB');
        final bytes = file.readAsBytesSync();
        final error = validateGbaHeader(bytes);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          consoleId: 'gba',
          // El nombre del archivo suele ser más legible (p. ej. nombres
          // No-Intro) que los 12 caracteres internos de la cabecera.
          title: titleFromFileName(path) ?? gbaTitle(bytes) ?? 'Sin título',
          sha1: sha1.convert(bytes).toString(),
          size: size,
        );
      case 'gb' || 'gbc':
        if (size < 0x150) return RejectedRom(path, 'Archivo demasiado pequeño');
        if (size > 8 * 1024 * 1024) return RejectedRom(path, 'Mayor de 8 MB');
        final bytes = file.readAsBytesSync();
        final error = validateGbHeader(bytes);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          // El indicador CGB de la cabecera manda sobre la extensión.
          consoleId: isGbcOnlyOrEnhanced(bytes) ? 'gbc' : 'gb',
          title: titleFromFileName(path) ?? gbTitle(bytes) ?? 'Sin título',
          sha1: sha1.convert(bytes).toString(),
          size: size,
        );
      case 'nes':
        if (size < 16 + 8192) return RejectedRom(path, 'Archivo demasiado pequeño');
        if (size > 8 * 1024 * 1024) return RejectedRom(path, 'Mayor de 8 MB');
        final bytes = file.readAsBytesSync();
        final error = validateInesHeader(bytes);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          consoleId: 'nes',
          title: titleFromFileName(path) ?? 'Sin título',
          sha1: sha1.convert(bytes).toString(),
          size: size,
        );
      case 'psx':
        return _inspectPsx(path, file, size, ext.toLowerCase());
      case 'nds':
        if (size < 0x200) return RejectedRom(path, 'Archivo demasiado pequeño');
        // Solo se lee la cabecera y la huella se calcula por bloques.
        if (size > maxImportSize) return RejectedRom(path, 'Mayor de 10 GB');
        final raf = file.openSync();
        final Uint8List header;
        try {
          header = raf.readSync(0x200);
        } finally {
          raf.closeSync();
        }
        final error = validateNdsHeader(header);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          consoleId: 'nds',
          title: titleFromFileName(path) ?? 'Sin título',
          sha1: sha1OfFile(path),
          size: size,
        );
      case 'psp':
        final error = validatePspImage(file, ext.toLowerCase(), size);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          consoleId: 'psp',
          title: titleFromFileName(path) ?? 'Sin título',
          sha1: sha1OfFile(path),
          size: size,
        );
      case 'snes':
        if (size < 0x8000) return RejectedRom(path, 'Archivo demasiado pequeño');
        if (size > 12 * 1024 * 1024) return RejectedRom(path, 'Mayor de 12 MB');
        final bytes = file.readAsBytesSync();
        final error = validateSnesHeader(bytes);
        if (error != null) return RejectedRom(path, error);
        return ValidRom(
          path,
          consoleId: 'snes',
          title: titleFromFileName(path) ?? 'Sin título',
          sha1: sha1.convert(bytes).toString(),
          size: size,
        );
      default:
        return RejectedRom(path, '${console.name} todavía no tiene núcleo');
    }
  }

  /// Tamaño máximo de un archivo importado: 10 GB. Los formatos de cartucho
  /// tienen además el tamaño real máximo de su consola (GBA 32 MB, etc.).
  static const maxImportSize = 10 * 1024 * 1024 * 1024;

  /// PlayStation: discos (y `.pbp` de varios discos) hasta el límite general.
  static const psxMaxSize = maxImportSize;

  /// PlayStation: `.cue` (+ sus `.bin`), `.chd`, `.pbp` o un programa PS-X EXE.
  /// Los archivos se procesan por bloques: nunca se cargan enteros en memoria.
  static RomInspection _inspectPsx(String path, File file, int size, String ext) {
    if (size > psxMaxSize) return RejectedRom(path, 'Mayor de 10 GB');
    String head(int n) {
      final raf = file.openSync();
      try {
        return latin1.decode(raf.readSync(n), allowInvalid: true);
      } finally {
        raf.closeSync();
      }
    }

    ValidRom ok(String hashOf, int totalSize) => ValidRom(
          path,
          consoleId: 'psx',
          title: titleFromFileName(path) ?? 'Sin título',
          sha1: sha1OfFile(hashOf),
          size: totalSize,
        );

    switch (ext) {
      case '.exe':
        if (size < 2048 + 4 || size > 2048 + 2 * 1024 * 1024) {
          return RejectedRom(path, 'Tamaño de PS-X EXE inválido');
        }
        return head(8) == 'PS-X EXE' ? ok(path, size) : RejectedRom(path, 'No es un programa PS-X EXE');
      case '.chd':
        return head(8) == 'MComprHD' ? ok(path, size) : RejectedRom(path, 'Cabecera CHD inválida');
      case '.pbp':
        return head(4) == '\u0000PBP' ? ok(path, size) : RejectedRom(path, 'Cabecera PBP inválida');
      case '.cue':
        if (size > 64 * 1024) return RejectedRom(path, 'Archivo .cue demasiado grande');
        final tracks = cueTrackFiles(file.readAsStringSync(encoding: latin1));
        if (tracks.isEmpty) return RejectedRom(path, 'El .cue no hace referencia a ningún archivo');
        var total = size;
        for (final name in tracks) {
          final track = File(p.join(p.dirname(path), name));
          if (!track.existsSync()) return RejectedRom(path, 'Falta el archivo de pista "$name"');
          final len = track.lengthSync();
          if (len == 0 || (len % 2352 != 0 && len % 2048 != 0)) {
            return RejectedRom(path, '"$name" no tiene un tamaño de pista de CD válido');
          }
          total += len;
        }
        if (total > psxMaxSize) return RejectedRom(path, 'Mayor de 10 GB');
        // La huella es la de la primera pista (la de datos), como en No-Intro/Redump.
        return ok(p.join(p.dirname(path), tracks.first), total);
      default:
        return RejectedRom(path, 'Formato de PlayStation no admitido ($ext)');
    }
  }

  /// Comprueba una imagen de PSP: ISO 9660 ("CD001" en el sector 16) o CSO
  /// comprimido ("CISO"). Devuelve el motivo del rechazo o null si es válida.
  static String? validatePspImage(File file, String ext, int size) {
    if (size > maxImportSize) return 'Mayor de 10 GB';
    final raf = file.openSync();
    try {
      if (ext == '.cso') {
        if (size < 24) return 'Archivo demasiado pequeño';
        return ascii.decode(raf.readSync(4), allowInvalid: true) == 'CISO'
            ? null
            : 'Cabecera CSO inválida';
      }
      if (size < 0x8006) return 'Archivo demasiado pequeño';
      raf.setPositionSync(0x8001);
      return ascii.decode(raf.readSync(5), allowInvalid: true) == 'CD001'
          ? null
          : 'No es una imagen de disco ISO';
    } finally {
      raf.closeSync();
    }
  }

  /// Nombres de archivo que referencia un `.cue` (líneas `FILE "x.bin" BINARY`).
  /// Solo se aceptan nombres simples: sin rutas (nada fuera de su carpeta).
  static List<String> cueTrackFiles(String cue) => [
        for (final m in RegExp(r'^\s*FILE\s+"([^"]+)"', multiLine: true, caseSensitive: false)
            .allMatches(cue))
          if (!m.group(1)!.contains('/') && !m.group(1)!.contains('\\') && m.group(1) != '..')
            m.group(1)!,
      ];

  /// SHA-1 leyendo el archivo por bloques de 1 MB.
  static String sha1OfFile(String path) {
    final out = _DigestSink();
    final input = sha1.startChunkedConversion(out);
    final raf = File(path).openSync();
    try {
      final buffer = Uint8List(1024 * 1024);
      while (true) {
        final n = raf.readIntoSync(buffer);
        if (n <= 0) break;
        input.add(Uint8List.sublistView(buffer, 0, n));
      }
    } finally {
      raf.closeSync();
    }
    input.close();
    return out.value.toString();
  }

  /// Cabecera de Nintendo DS (GBATEK, "DS Cartridge Header"): CRC-16 de
  /// 0x000..0x15D guardado en 0x15E.
  static String? validateNdsHeader(Uint8List h) {
    if (h.length < 0x160) return 'Cabecera incompleta';
    var crc = 0xFFFF;
    for (var i = 0; i < 0x15E; i++) {
      crc ^= h[i];
      for (var b = 0; b < 8; b++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
    }
    final stored = h[0x15E] | (h[0x15F] << 8);
    return crc == stored ? null : 'CRC de cabecera de Nintendo DS incorrecto';
  }

  /// SNES no tiene número mágico: la cabecera interna está en 0x7FC0
  /// (LoROM), 0xFFC0 (HiROM) o 0x40FFC0 (ExHiROM), desplazada 512 bytes si
  /// el volcado conserva la cabecera de copiadora. Se acepta si el checksum
  /// y su complemento suman 0xFFFF, o si el modo de mapeo y el tamaño
  /// declarado son coherentes (muchos homebrew no calculan el checksum).
  static String? validateSnesHeader(Uint8List bytes) {
    final copier = bytes.length % 1024 == 512 ? 512 : 0;
    var plausible = false;
    for (final base in const [0x7FC0, 0xFFC0, 0x40FFC0]) {
      final h = base + copier;
      if (bytes.length < h + 0x20) continue;
      final complement = bytes[h + 0x1C] | (bytes[h + 0x1D] << 8);
      final checksum = bytes[h + 0x1E] | (bytes[h + 0x1F] << 8);
      final map = bytes[h + 0x15];
      final romSize = bytes[h + 0x17];
      final mapOk = (map & 0xE0) == 0x20 && const {0, 1, 2, 3, 5, 0xA}.contains(map & 0x0F);
      if (mapOk && (checksum + complement) == 0xFFFF) return null;
      if (mapOk && romSize >= 0x07 && romSize <= 0x0D) plausible = true;
    }
    return plausible ? null : 'Cabecera de SNES no reconocida';
  }

  /// Cabecera de Game Boy (Pan Docs, "The Cartridge Header"): checksum en
  /// 0x14D sobre 0x134..0x14C.
  static String? validateGbHeader(Uint8List bytes) {
    if (bytes.length < 0x150) return 'Cabecera incompleta';
    var x = 0;
    for (var i = 0x134; i <= 0x14C; i++) {
      x = (x - bytes[i] - 1) & 0xFF;
    }
    if (bytes[0x14D] != x) return 'Checksum de cabecera de Game Boy incorrecto';
    return null;
  }

  /// 0x143: 0x80 = compatible con GBC, 0xC0 = solo GBC.
  static bool isGbcOnlyOrEnhanced(Uint8List bytes) =>
      bytes.length > 0x143 && (bytes[0x143] == 0x80 || bytes[0x143] == 0xC0);

  static String? gbTitle(Uint8List bytes) {
    final raw = bytes.sublist(0x134, 0x143).takeWhile((b) => b != 0).toList();
    if (raw.isEmpty || raw.any((b) => b < 0x20 || b > 0x7E)) return null;
    final t = ascii.decode(raw).trim();
    return t.isEmpty ? null : t;
  }

  /// Cabecera iNES / NES 2.0: "NES" + 0x1A y tamaños coherentes con el archivo.
  static String? validateInesHeader(Uint8List bytes) {
    if (bytes.length < 16 ||
        bytes[0] != 0x4E || bytes[1] != 0x45 || bytes[2] != 0x53 || bytes[3] != 0x1A) {
      return 'Cabecera iNES inválida';
    }
    final prg = bytes[4] * 16384;
    final chr = bytes[5] * 8192;
    final trainer = (bytes[6] & 0x04) != 0 ? 512 : 0;
    final nes2 = (bytes[7] & 0x0C) == 0x08;
    if (prg == 0 && !nes2) return 'El ROM no declara programa (PRG)';
    if (!nes2 && bytes.length < 16 + trainer + prg + chr) {
      return 'El archivo es más pequeño de lo que declara su cabecera';
    }
    return null;
  }

  /// Comprueba la cabecera del cartucho GBA (GBATEK, "Cartridge Header"):
  /// valor fijo 0x96 en 0xB2 y el checksum complementario en 0xBD.
  /// Devuelve null si es válida o el motivo del rechazo.
  static String? validateGbaHeader(Uint8List bytes) {
    if (bytes.length < 0xC0) return 'Cabecera incompleta';
    if (bytes[0xB2] != 0x96) return 'Cabecera GBA inválida (byte fijo)';
    var sum = 0;
    for (var i = 0xA0; i <= 0xBC; i++) {
      sum += bytes[i];
    }
    final checksum = (-(sum + 0x19)) & 0xFF;
    if (bytes[0xBD] != checksum) return 'Checksum de cabecera incorrecto';
    return null;
  }

  /// Título a partir del nombre de archivo: sin extensión y con `_` como espacios.
  static String? titleFromFileName(String path) {
    final name = p.basenameWithoutExtension(path).replaceAll('_', ' ').trim();
    return name.isEmpty ? null : name;
  }

  /// Título interno (12 caracteres ASCII en 0xA0), si es legible.
  static String? gbaTitle(Uint8List bytes) {
    final raw = bytes.sublist(0xA0, 0xAC).takeWhile((b) => b != 0).toList();
    if (raw.isEmpty || raw.any((b) => b < 0x20 || b > 0x7E)) return null;
    final title = ascii.decode(raw).trim();
    return title.isEmpty ? null : title;
  }
}
