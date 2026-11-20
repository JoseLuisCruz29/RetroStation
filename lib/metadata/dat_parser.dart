/// Parser del formato clrmamepro que usan las bases de datos de libretro
/// (No-Intro, géneros, años). Función pura: se ejecuta en un isolate.
class DatEntry {
  const DatEntry({
    required this.name,
    this.region,
    this.genre,
    this.releaseYear,
    this.crc,
    this.sha1,
    this.size,
  });

  final String name;
  final String? region;
  final String? genre;
  final int? releaseYear;
  final String? crc; // en mayúsculas
  final String? sha1; // en minúsculas
  final int? size;
}

final _gameBlock = RegExp(r'^game \($(.*?)^\)', multiLine: true, dotAll: true);
final _field = RegExp(r'^\s*(name|comment|region|genre|releaseyear) "((?:[^"\\]|\\.)*)"', multiLine: true);
final _rom = RegExp(r'rom \((.*?)\)\s*$', multiLine: true);
final _romCrc = RegExp(r'\bcrc ([0-9A-Fa-f]{8})');
final _romSha1 = RegExp(r'\bsha1 ([0-9A-Fa-f]{40})');
final _romSize = RegExp(r'\bsize (\d+)');

List<DatEntry> parseDat(String text) {
  final entries = <DatEntry>[];
  for (final block in _gameBlock.allMatches(text.replaceAll('\r\n', '\n'))) {
    final body = block.group(1)!;
    final fields = <String, String>{};
    for (final f in _field.allMatches(body)) {
      fields.putIfAbsent(f.group(1)!, () => f.group(2)!);
    }
    final name = fields['name'] ?? fields['comment'];
    if (name == null) continue;
    final rom = _rom.firstMatch(body)?.group(1) ?? '';
    entries.add(DatEntry(
      name: name,
      region: fields['region'],
      genre: fields['genre'],
      releaseYear: int.tryParse(fields['releaseyear'] ?? ''),
      crc: _romCrc.firstMatch(rom)?.group(1)?.toUpperCase(),
      sha1: _romSha1.firstMatch(rom)?.group(1)?.toLowerCase(),
      size: int.tryParse(_romSize.firstMatch(rom)?.group(1) ?? ''),
    ));
  }
  return entries;
}

/// Índice combinado de una consola: identificación por SHA-1 y datos
/// adicionales (género, año) por CRC.
class MetadataIndex {
  MetadataIndex({
    required this.bySha1,
    required this.genreByCrc,
    required this.yearByCrc,
  });

  final Map<String, DatEntry> bySha1;
  final Map<String, String> genreByCrc;
  final Map<String, int> yearByCrc;

  int get size => bySha1.length;

  factory MetadataIndex.fromDats({
    required String noIntro,
    String? genres,
    String? years,
  }) {
    final bySha1 = <String, DatEntry>{};
    for (final e in parseDat(noIntro)) {
      if (e.sha1 != null) bySha1[e.sha1!] = e;
    }
    final genreByCrc = <String, String>{};
    if (genres != null) {
      for (final e in parseDat(genres)) {
        if (e.crc != null && e.genre != null) genreByCrc[e.crc!] = e.genre!;
      }
    }
    final yearByCrc = <String, int>{};
    if (years != null) {
      for (final e in parseDat(years)) {
        if (e.crc != null && e.releaseYear != null) yearByCrc[e.crc!] = e.releaseYear!;
      }
    }
    return MetadataIndex(bySha1: bySha1, genreByCrc: genreByCrc, yearByCrc: yearByCrc);
  }

  GameMetadata? lookup(String sha1) {
    final entry = bySha1[sha1.toLowerCase()];
    if (entry == null) return null;
    final crc = entry.crc;
    return GameMetadata(
      name: entry.name,
      region: entry.region,
      genre: crc == null ? null : genreByCrc[crc],
      releaseYear: crc == null ? null : yearByCrc[crc],
    );
  }
}

class GameMetadata {
  const GameMetadata({required this.name, this.region, this.genre, this.releaseYear});

  /// Nombre No-Intro, p. ej. "Pokemon - Emerald Version (USA, Europe)".
  final String name;
  final String? region;
  final String? genre;
  final int? releaseYear;
}

/// Nombre de archivo de libretro-thumbnails: estos caracteres se sustituyen por `_`.
String thumbnailFileName(String noIntroName) =>
    '${noIntroName.replaceAll(RegExp(r'[&*/:`<>?\\|"]'), '_')}.png';
