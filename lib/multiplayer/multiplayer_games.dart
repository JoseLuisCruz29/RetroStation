import 'dart:io';

import '../emulation/native_bindings.dart';
import '../engines/console.dart';
import '../engines/console_registry.dart';
import '../game_library/game_repository.dart';

/// Consolas con juego compartido por la red (los dos teléfonos ejecutan el
/// mismo juego): sus núcleos guardan estados y son deterministas.
const sharedPlayConsoles = {'nes', 'snes', 'psx'};

/// Núcleo con cable link / adaptador inalámbrico de GBA por red.
const linkCoreLibrary = 'libgpsp_libretro.so';

/// Opciones de gpSP para el link: modo automático (adaptador inalámbrico en
/// Rojo Fuego/Verde Hoja/Esmeralda, cable en Rubí/Zafiro) y reloj real, como
/// con mGBA, para que eventos y bayas sigan su curso.
const linkCoreOptions = {'gpsp_serial': 'auto', 'gpsp_rtc_time_source': 'system'};

/// Núcleo con las dos GBA unidas por el cable (cualquier juego de GBA).
const gbaLinkCoreLibrary = 'libgbalink_libretro.so';

/// Ad hoc de PSP: Wi-Fi de la consola emulada encendida. El anfitrión abre
/// el servidor de PPSSPP (el "PRO Ad Hoc Server") y los dos se conectan a él
/// por la IP del anfitrión en la red ([serverAddress]). El anfitrión no puede
/// usar "localhost": el servidor anunciaría su IP como 127.0.0.1 y el otro
/// nunca lo alcanzaría. Cada PSP con una MAC al azar.
///
/// Los puertos de la PSP se desplazan 10000 (como en PPSSPP de escritorio):
/// los juegos usan puertos bajos (1, 2...) que Android no deja abrir.
Map<String, String> pspAdhocOptions({required bool host, required String serverAddress}) {
  // PPSSPP pide la IP cifra a cifra: 12 opciones, 3 por número (192.168.001.020).
  final parts = serverAddress.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((n) => n == null || n < 0 || n > 255)) {
    throw ArgumentError('Dirección del anfitrión no válida: $serverAddress');
  }
  final digits = parts.map((n) => n!.toString().padLeft(3, '0')).join();
  return {
    'ppsspp_enable_wlan': 'enabled',
    'ppsspp_enable_builtin_pro_ad_hoc_server': host ? 'enabled' : 'disabled',
    'ppsspp_change_pro_ad_hoc_server_address': 'IP address',
    for (var i = 0; i < 12; i++)
      'ppsspp_pro_ad_hoc_server_address${(i + 1).toString().padLeft(2, '0')}': digits[i],
    'ppsspp_port_offset': '10000',
  };
}

/// IP de este dispositivo en la misma red que [peer] (la que el otro ve).
/// Con varias redes (Wi-Fi, Ethernet, VPN...) se elige la que comparte más
/// prefijo con la del otro.
String? addressFacing(String peer, List<String> mine) {
  if (mine.isEmpty) return null;
  int common(String a) {
    final x = a.split('.'), y = peer.split('.');
    var n = 0;
    while (n < 4 && n < x.length && n < y.length && x[n] == y[n]) {
      n++;
    }
    return n;
  }

  return (List.of(mine)..sort((a, b) => common(b).compareTo(common(a)))).first;
}

/// Códigos de cartucho (cabecera, 0xAC) de los Pokémon de 3.ª generación,
/// los que gpSP sabe conectar por red: Rubí, Zafiro, Esmeralda, Rojo Fuego y
/// Verde Hoja (cualquier región; el 4.º carácter es el idioma).
const _pokemonGen3Codes = {'AXV', 'AXP', 'BPE', 'BPR', 'BPG'};

/// Un juego de la biblioteca tal como se comparte con el otro teléfono.
class LanGame {
  const LanGame({
    required this.id,
    required this.sha1,
    required this.title,
    required this.consoleId,
    this.pokemonLink = false,
  });

  /// Id en la base de datos local (solo tiene sentido en este teléfono).
  final int id;
  final String sha1;
  final String title;
  final String consoleId;

  /// Pokémon de 3.ª generación: intercambios y combates por link.
  final bool pokemonLink;

  Map<String, Object?> toJson() =>
      {'sha1': sha1, 'title': title, 'console': consoleId, if (pokemonLink) 'poke': true};

  static LanGame? fromJson(Object? json) {
    if (json is! Map) return null;
    final sha1 = json['sha1'];
    final title = json['title'];
    final console = json['console'];
    if (sha1 is! String || title is! String || console is! String) return null;
    return LanGame(id: -1, sha1: sha1, title: title, consoleId: console, pokemonLink: json['poke'] == true);
  }

  static List<Map<String, Object?>> listToJson(List<LanGame> games) => [for (final g in games) g.toJson()];

  static List<LanGame> listFromJson(Object? json) => [
        if (json is List)
          for (final e in json) ?LanGame.fromJson(e),
      ];
}

/// Lo que se puede jugar juntos en la sala.
class Experience {
  const Experience.shared({required this.sha1, required this.title, required this.consoleId})
      : mode = NetMode.shared;

  const Experience.link()
      : mode = NetMode.link,
        sha1 = '',
        title = 'Pokémon: intercambios y combates',
        consoleId = 'gba';

  /// Un juego de GBA con cable link (el mismo archivo en los dos).
  const Experience.gbaLink({required this.sha1, required this.title})
      : mode = NetMode.gbaLink,
        consoleId = 'gba';

  /// Un juego de PSP con multijugador inalámbrico (el mismo archivo en los dos).
  const Experience.pspAdhoc({required this.sha1, required this.title})
      : mode = NetMode.pspAdhoc,
        consoleId = 'psp';

  final NetMode mode;

  /// Juego compartido (vacío en el link: cada uno usa el suyo).
  final String sha1;
  final String title;
  final String consoleId;

  String get subtitle => switch (mode) {
        NetMode.link => 'Cable link de GBA · cada uno con su juego y su partida',
        NetMode.gbaLink => 'Cable link de GBA · cada uno con su GBA y su partida',
        NetMode.shared => 'Jugador 1 y jugador 2 en el mismo juego',
        NetMode.pspAdhoc => 'Ad hoc de PSP · cada uno con su PSP y su partida',
      };

  bool sameAs(Experience? other) => other != null && other.mode == mode && other.sha1 == sha1;

  Map<String, Object?> toJson() =>
      {'mode': mode.name, 'sha1': sha1, 'title': title, 'console': consoleId};

  static Experience? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['mode'] == NetMode.link.name) return const Experience.link();
    final sha1 = json['sha1'];
    final title = json['title'];
    final console = json['console'];
    if (sha1 is! String || title is! String || console is! String) return null;
    if (json['mode'] == NetMode.gbaLink.name) return Experience.gbaLink(sha1: sha1, title: title);
    if (json['mode'] == NetMode.pspAdhoc.name) return Experience.pspAdhoc(sha1: sha1, title: title);
    return Experience.shared(sha1: sha1, title: title, consoleId: console);
  }
}

/// Experiencias posibles con las dos bibliotecas: los juegos compartidos que
/// tienen los dos (mismo archivo), los de GBA con cable link (mismo archivo)
/// y el link de Pokémon si ambos tienen uno (aunque sean ediciones distintas).
List<Experience> experiencesFor(List<LanGame> mine, List<LanGame> theirs) {
  final theirSha1 = {for (final g in theirs) g.sha1};
  final shared = [
    for (final g in mine)
      if (g.sha1.isNotEmpty && theirSha1.contains(g.sha1))
        if (sharedPlayConsoles.contains(g.consoleId))
          Experience.shared(sha1: g.sha1, title: g.title, consoleId: g.consoleId)
        else if (g.consoleId == 'gba')
          Experience.gbaLink(sha1: g.sha1, title: g.title)
        else if (g.consoleId == 'psp')
          Experience.pspAdhoc(sha1: g.sha1, title: g.title),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return [
    if (mine.any((g) => g.pokemonLink) && theirs.any((g) => g.pokemonLink)) const Experience.link(),
    ...shared,
  ];
}

/// Juegos instalados que sirven para el multijugador. Solo los de consolas
/// que este dispositivo puede emular (por si a alguna consola le falta núcleo):
/// así la sala nunca ofrece un juego que uno de los dos no puede abrir.
Future<List<LanGame>> loadLanLibrary(GameRepository repo) async {
  final games = await repo.watch(const LibraryFilter(category: LibraryCategory.installed)).first;
  final result = <LanGame>[];
  for (final g in games) {
    final sha1 = g.sha1;
    if (sha1 == null || g.romPath == null) continue;
    if (ConsoleRegistry.byId(g.consoleId)?.status != CoreStatus.available) continue;
    if (sharedPlayConsoles.contains(g.consoleId) || g.consoleId == 'psp') {
      result.add(LanGame(id: g.id, sha1: sha1, title: g.title, consoleId: g.consoleId));
    } else if (g.consoleId == 'gba') {
      // Cualquier GBA sirve para el cable link; los Pokémon, además, para gpSP.
      final poke = await isPokemonGen3(g.romPath!);
      result.add(LanGame(id: g.id, sha1: sha1, title: g.title, consoleId: g.consoleId, pokemonLink: poke));
    }
  }
  return result;
}

Future<bool> isPokemonGen3(String romPath) async {
  try {
    final file = await File(romPath).open();
    try {
      await file.setPosition(0xAC);
      final code = String.fromCharCodes(await file.read(3));
      return _pokemonGen3Codes.contains(code);
    } finally {
      await file.close();
    }
  } on Object {
    return false;
  }
}

/// Juegos de Pokémon de este teléfono (para elegir con cuál conectarse).
List<LanGame> pokemonGames(List<LanGame> library) => [for (final g in library) if (g.pokemonLink) g];

/// Juego local que corresponde a una experiencia compartida.
LanGame? localGameFor(Experience exp, List<LanGame> library) =>
    library.where((g) => g.sha1 == exp.sha1).firstOrNull;
