/// Qué se puede hacer con un resultado de una fuente externa.
enum Availability {
  /// La fuente publica el enlace del archivo: se descarga con un toque.
  downloadable('Descarga directa'),

  /// La web de la fuente entrega el archivo (aceptar, pagar o pulsar su
  /// botón). Se abre en el navegador integrado y el archivo se recoge ahí.
  sourcePage('Desde su página');

  const Availability(this.label);
  final String label;
}

/// Archivo descargable de un resultado.
class RemoteFile {
  const RemoteFile({
    required this.url,
    required this.fileName,
    this.description,
    this.sha1,
    this.size,
  });

  final Uri url;
  final String fileName;
  final String? description;

  /// Huella publicada por la fuente (si la hay) para verificar la descarga.
  final String? sha1;
  final int? size;
}

/// Un juego encontrado en una fuente externa. Todos los datos vienen de la
/// fuente: no se rellena nada por suposición.
class DiscoveryItem {
  const DiscoveryItem({
    required this.sourceId,
    required this.remoteId,
    required this.title,
    required this.availability,
    required this.pageUrl,
    this.consoleId,
    this.platformLabel,
    this.developers = const [],
    this.year,
    this.description,
    this.tags = const [],
    this.coverUrl,
    this.screenshotUrls = const [],
    this.license,
    this.price,
    this.commercial = false,
    this.files = const [],
  });

  final String sourceId;
  final String remoteId;
  final String title;
  final Availability availability;

  /// Página original (procedencia) que se puede abrir en el navegador.
  final Uri pageUrl;

  /// Consola de RetroStation (null si la plataforma no está soportada).
  final String? consoleId;

  /// Plataforma tal como la nombra la fuente (p. ej. "GBC").
  final String? platformLabel;
  final List<String> developers;
  final int? year;
  final String? description;
  final List<String> tags;
  final Uri? coverUrl;
  final List<Uri> screenshotUrls;

  /// Licencia declarada por el autor (null si la fuente no la indica).
  final String? license;

  /// Precio en la tienda de origen (solo fuentes de enlace).
  final String? price;

  /// La versión completa se vende (lo descargable suele ser una demo gratuita).
  final bool commercial;
  final List<RemoteFile> files;

  RemoteFile? get primaryFile => files.isEmpty ? null : files.first;
}

class DiscoveryQuery {
  const DiscoveryQuery({
    this.text = '',
    this.consoleId,
    this.tag,
    this.year,
    this.availability,
    this.spanishOnly = false,
  });

  final String text;
  final String? consoleId;

  /// Género o etiqueta (coincidencia exacta en la fuente).
  final String? tag;
  final int? year;
  final Availability? availability;

  /// Solo juegos cuyo autor declara el español entre sus idiomas. Solo lo
  /// respetan las fuentes que publican el idioma ([SourceAdapter.supportsLanguage]).
  final bool spanishOnly;

  DiscoveryQuery copyWith({
    String? text,
    String? Function()? consoleId,
    String? Function()? tag,
    int? Function()? year,
    Availability? Function()? availability,
    bool? spanishOnly,
  }) =>
      DiscoveryQuery(
        text: text ?? this.text,
        consoleId: consoleId != null ? consoleId() : this.consoleId,
        tag: tag != null ? tag() : this.tag,
        year: year != null ? year() : this.year,
        availability: availability != null ? availability() : this.availability,
        spanishOnly: spanishOnly ?? this.spanishOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is DiscoveryQuery &&
      other.text == text &&
      other.consoleId == consoleId &&
      other.tag == tag &&
      other.year == year &&
      other.availability == availability &&
      other.spanishOnly == spanishOnly;

  @override
  int get hashCode => Object.hash(text, consoleId, tag, year, availability, spanishOnly);
}

class DiscoveryPage {
  const DiscoveryPage({required this.items, required this.hasMore});

  final List<DiscoveryItem> items;
  final bool hasMore;
}
