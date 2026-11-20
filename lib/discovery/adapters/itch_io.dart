import 'dart:convert';

import '../../core/http_fetch.dart';
import '../discovery_models.dart';
import '../source_adapter.dart';

/// itch.io: tienda de juegos independientes. La descarga la entrega su web
/// (botón "Download", pago o "No thanks, just take me to the downloads"), así
/// que se hace en el navegador integrado de la app: [Availability.sourcePage].
///
/// Usa los feeds RSS públicos de itch.io:
/// - GBA: etiqueta `gameboy-advance`;
/// - Game Boy: juegos hechos con GB Studio (exporta ROMs de GB/GBC);
/// - NES y SNES: etiquetas `nes` y `snes`.
/// Con [DiscoveryQuery.spanishOnly] se usa el filtro de idioma de itch.io
/// (`/games/lang-es/...`), que se basa en los idiomas que declara el autor.
class ItchIoAdapter implements SourceAdapter {
  /// Consola de RetroStation -> ruta del feed en itch.io.
  static const feeds = {
    'gba': 'tag-gameboy-advance',
    'gb': 'made-with-gb-studio',
    'nes': 'tag-nes',
    'snes': 'tag-snes',
  };

  ItchIoAdapter({Future<String> Function(Uri)? fetch}) : _fetch = fetch ?? _defaultFetch;

  final Future<String> Function(Uri) _fetch;

  // Hasta 4 feeds por búsqueda: cada uno con un límite corto para que una
  // respuesta lenta no deje la búsqueda colgada.
  static Future<String> _defaultFetch(Uri url) async => utf8.decode(
        await fetchBytes(url, retries: 2, timeout: const Duration(seconds: 12)),
        allowMalformed: true,
      );

  @override
  String get id => 'itch_io';

  @override
  String get name => 'itch.io';

  @override
  String get description =>
      'Juegos independientes de GBA, Game Boy, NES y SNES publicados en itch.io '
      '(gratuitos y de pago). Se descargan desde su página, dentro de la app.';

  @override
  Availability get availability => Availability.sourcePage;

  @override
  Set<String> get consoles => feeds.keys.toSet();

  @override
  bool get supportsTags => false;

  @override
  bool get supportsLanguage => true;

  @override
  Future<DiscoveryPage> search(DiscoveryQuery query, int page) async {
    if ((query.consoleId != null && !consoles.contains(query.consoleId)) ||
        query.tag != null) {
      return const DiscoveryPage(items: [], hasMore: false);
    }
    final wanted = query.consoleId == null
        ? feeds.entries.toList()
        : feeds.entries.where((e) => e.key == query.consoleId).toList();
    final items = <DiscoveryItem>[];
    var anyFull = false;
    Object? lastError;
    // En paralelo pero escalonadas (250 ms): así no se suman los tiempos de
    // espera y no se dispara el límite de peticiones de itch.io (429).
    final results = await Future.wait([
      for (final (i, feed) in wanted.indexed)
        Future<void>.delayed(Duration(milliseconds: 250 * i)).then((_) async {
          final path = '/games/${query.spanishOnly ? 'lang-es/' : ''}${feed.value}.xml';
          try {
            return (
              parseFeed(
                await _fetch(Uri.https('itch.io', path, {if (page > 1) 'page': '$page'})),
                consoleId: feed.key,
              ),
              null,
            );
          } catch (e) {
            return (<DiscoveryItem>[], e);
          }
        }),
    ]);
    for (final (parsed, error) in results) {
      if (error != null) lastError = error;
      anyFull |= parsed.length >= 30;
      // Un juego con varias etiquetas (p. ej. NES y SNES) aparece una vez.
      final seen = items.map((i) => i.remoteId).toSet();
      items.addAll(parsed.where((i) => !seen.contains(i.remoteId)));
    }
    if (items.isEmpty && lastError != null) throw lastError;
    final text = query.text.trim().toLowerCase();
    final filtered = items.where((i) {
      if (text.isNotEmpty &&
          !i.title.toLowerCase().contains(text) &&
          !(i.description?.toLowerCase().contains(text) ?? false)) {
        return false;
      }
      return query.year == null || i.year == query.year;
    }).toList();
    // El feed no indica el total de páginas: se sigue mientras traiga resultados.
    return DiscoveryPage(items: filtered, hasMore: anyFull && page < 5);
  }

  static const _labels = {'gba': 'GBA', 'gb': 'Game Boy', 'nes': 'NES', 'snes': 'SNES'};

  List<DiscoveryItem> parseFeed(String xml, {String consoleId = 'gba'}) {
    String? tag(String body, String name) {
      final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(body);
      if (m == null) return null;
      var v = m.group(1)!;
      final cdata = RegExp(r'^<!\[CDATA\[(.*)\]\]>$', dotAll: true).firstMatch(v);
      if (cdata != null) v = cdata.group(1)!;
      return _unescape(v).trim();
    }

    final result = <DiscoveryItem>[];
    for (final m in RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml)) {
      final body = m.group(1)!;
      final link = tag(body, 'link');
      final title = tag(body, 'plainTitle') ?? tag(body, 'title');
      if (link == null || title == null) continue;
      final page = Uri.tryParse(link);
      if (page == null || !page.host.endsWith('itch.io')) continue;
      final image = tag(body, 'imageurl');
      final description = tag(body, 'description')
          ?.replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final price = tag(body, 'price');
      result.add(DiscoveryItem(
        sourceId: id,
        remoteId: link,
        title: title,
        availability: Availability.sourcePage,
        pageUrl: page,
        consoleId: consoleId,
        platformLabel: _labels[consoleId],
        developers: [page.host.split('.').first],
        year: _year(tag(body, 'pubDate')),
        description: description,
        coverUrl: image == null ? null : Uri.tryParse(image),
        price: price == null || price == r'$0.00' ? 'Gratis' : price,
        commercial: price != null && price != r'$0.00',
      ));
    }
    return result;
  }

  static int? _year(String? rfc822) =>
      rfc822 == null ? null : int.tryParse(RegExp(r'\b(\d{4})\b').firstMatch(rfc822)?.group(1) ?? '');

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
