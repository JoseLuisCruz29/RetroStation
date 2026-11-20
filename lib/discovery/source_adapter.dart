import 'discovery_models.dart';

/// Contrato de una fuente externa de juegos. Cada fuente es un adaptador
/// independiente: añadir, quitar o actualizar una no afecta al resto de la app.
abstract class SourceAdapter {
  /// Identificador estable (se guarda como procedencia de los juegos).
  String get id;
  String get name;

  /// Qué ofrece la fuente y bajo qué condiciones (se muestra al usuario).
  String get description;

  /// Disponibilidad de sus resultados.
  Availability get availability;

  /// Consolas de RetroStation que cubre.
  Set<String> get consoles;

  /// Si admite filtrar por etiqueta/género en la propia fuente.
  bool get supportsTags => false;

  /// Si la fuente publica el idioma de los juegos (y puede filtrar por él).
  /// Las que no lo publican se excluyen al pedir "solo en español": no se
  /// adivina el idioma a partir del título.
  bool get supportsLanguage => false;

  /// Página [page] (empieza en 1) de resultados para [query].
  /// Debe lanzar una excepción si la fuente no responde.
  Future<DiscoveryPage> search(DiscoveryQuery query, int page);
}
