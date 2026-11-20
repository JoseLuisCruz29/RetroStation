import 'dart:convert';

import '../../core/http_fetch.dart';
import '../discovery_models.dart';
import '../source_adapter.dart';

/// Homebrew Hub (gbdev.io): archivo comunitario de homebrew para GB, GBC,
/// GBA y NES. Según su aviso legal, todo lo que aloja es software libre y no
/// aloja material comercial con copyright; retira entradas a petición.
///
/// API (comprobada contra el servidor real):
/// - `GET /api/search?platform=GBA&q=texto&tags=Puzzle&page=N` (10 por página)
/// - Archivos: `/static/<basepath>/entries/<slug>/<archivo>`
class HomebrewHubAdapter implements SourceAdapter {
  HomebrewHubAdapter({Future<String> Function(Uri)? fetch})
      : _fetch = fetch ?? _defaultFetch;

  final Future<String> Function(Uri) _fetch;

  static const _host = 'hh3.gbdev.io';

  static const _platformToConsole = {
    'GB': 'gb',
    'GBC': 'gbc',
    'GBA': 'gba',
    'NES': 'nes',
  };

  static Future<String> _defaultFetch(Uri url) async =>
      utf8.decode(await fetchBytes(url), allowMalformed: true);

  @override
  String get id => 'homebrew_hub';

  @override
  String get name => 'Homebrew Hub';

  @override
  String get description =>
      'Archivo comunitario de juegos homebrew (software libre) para Game Boy, '
      'Game Boy Color, Game Boy Advance y NES. Descarga directa.';

  @override
  Availability get availability => Availability.downloadable;

  @override
  Set<String> get consoles => _platformToConsole.values.toSet();

  @override
  bool get supportsTags => true;

  /// La API no tiene campo de idioma (se comprobó: no figura en sus fichas).
  @override
  bool get supportsLanguage => false;

  @override
  Future<DiscoveryPage> search(DiscoveryQuery query, int page) async {
    final platform = query.consoleId == null
        ? null
        : _platformToConsole.entries
            .where((e) => e.value == query.consoleId)
            .map((e) => e.key)
            .firstOrNull;
    if (query.consoleId != null && platform == null) {
      return const DiscoveryPage(items: [], hasMore: false);
    }
    final url = Uri.https(_host, '/api/search', {
      'platform': ?platform,
      if (query.text.trim().isNotEmpty) 'q': query.text.trim(),
      'tags': ?query.tag,
      'page': '$page',
    });
    final json = jsonDecode(await _fetch(url)) as Map<String, dynamic>;
    final entries = (json['entries'] as List? ?? const []).cast<Map<String, dynamic>>();
    final total = (json['page_total'] as num?)?.toInt() ?? 1;
    final current = (json['page_current'] as num?)?.toInt() ?? page;
    final items = [for (final e in entries) ?parseEntry(e)];
    return DiscoveryPage(
      items: query.year == null
          ? items
          : items.where((i) => i.year == query.year).toList(),
      // La API devuelve la última página si se pide una fuera de rango.
      hasMore: current < total && current == page,
    );
  }

  /// Convierte una entrada de la API. Devuelve null si le falta lo esencial.
  DiscoveryItem? parseEntry(Map<String, dynamic> e) {
    final slug = e['slug'] as String?;
    final title = e['title'] as String?;
    final basepath = e['basepath'] as String?;
    if (slug == null || title == null || basepath == null) return null;
    final platform = e['platform'] as String?;
    Uri asset(String file) =>
        Uri.https(_host, '/static/$basepath/entries/$slug/$file');

    final files = <RemoteFile>[
      for (final f in (e['files'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (f['filename'] is String && f['playable'] != false)
          RemoteFile(
            url: asset(f['filename'] as String),
            fileName: f['filename'] as String,
            description: f['description'] as String?,
          ),
    ]..sort((a, b) => _isDefault(e, b) ? 1 : (_isDefault(e, a) ? -1 : 0));
    final screenshots = [
      for (final s in (e['screenshots'] as List? ?? const []))
        if (s is String) asset(s),
    ];
    final baserepo = e['baserepo'] as String?;
    final license = [
      if (e['gameLicense'] is String) 'Juego: ${e['gameLicense']}',
      if (e['assetsLicense'] is String) 'Recursos: ${e['assetsLicense']}',
    ].join(' · ');

    return DiscoveryItem(
      sourceId: id,
      remoteId: slug,
      title: title,
      availability: files.isEmpty ? Availability.sourcePage : Availability.downloadable,
      pageUrl: baserepo != null
          ? Uri.parse('$baserepo/tree/master/entries/$slug')
          : Uri.https(_host, '/api/entry/$slug.json'),
      consoleId: _platformToConsole[platform],
      platformLabel: platform,
      developers: _developers(e['developer']),
      year: int.tryParse(((e['date'] as String?) ?? '').split('-').first),
      description: (e['description'] as String?)?.trim(),
      tags: [for (final t in (e['tags'] as List? ?? const [])) if (t is String) t],
      coverUrl: screenshots.firstOrNull,
      screenshotUrls: screenshots,
      license: license.isEmpty ? null : license,
      commercial: e['commercial'] == true,
      files: files,
    );
  }

  static bool _isDefault(Map<String, dynamic> e, RemoteFile f) {
    for (final raw in (e['files'] as List? ?? const [])) {
      if (raw is Map && raw['filename'] == f.fileName) return raw['default'] == true;
    }
    return false;
  }

  /// `developer` puede ser texto, lista de textos, objeto o lista de objetos.
  static List<String> _developers(Object? raw) {
    String? one(Object? d) => switch (d) {
          final String s => s,
          final Map m when m['name'] is String => m['name'] as String,
          _ => null,
        };
    return switch (raw) {
      final List list => [for (final d in list) ?one(d)],
      _ => [?one(raw)],
    };
  }
}
