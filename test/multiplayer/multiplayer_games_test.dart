import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/emulation/native_bindings.dart';
import 'package:retrostation/engines/console.dart';
import 'package:retrostation/engines/console_registry.dart';
import 'package:retrostation/multiplayer/multiplayer_games.dart';

LanGame game(String sha1, String console, {bool poke = false, String? title}) =>
    LanGame(id: 1, sha1: sha1, title: title ?? sha1, consoleId: console, pokemonLink: poke);

void main() {
  group('experiencesFor', () {
    test('solo juegos compartidos que tienen los dos (mismo SHA-1)', () {
      final mine = [game('aaa', 'snes', title: 'Kirby'), game('bbb', 'nes'), game('ccc', 'psx')];
      final theirs = [game('aaa', 'snes'), game('ccc', 'psx'), game('zzz', 'nes')];
      final exps = experiencesFor(mine, theirs);
      // Ordenados por título: "ccc" antes que "Kirby".
      expect(exps.map((e) => e.title).toList(), ['ccc', 'Kirby']);
      expect(exps.every((e) => e.mode == NetMode.shared), isTrue);
    });

    test('GBA con el mismo archivo: cable link de GBA; DS no aparece', () {
      final mine = [game('aaa', 'gba', title: 'Kirby GBA'), game('bbb', 'nds')];
      final exps = experiencesFor(mine, mine);
      expect(exps.single.mode, NetMode.gbaLink);
      expect(exps.single.sha1, 'aaa');
      expect(Experience.fromJson(exps.single.toJson())!.sameAs(exps.single), isTrue);
      // Un GBA que el otro no tiene (otro archivo) no sale.
      expect(experiencesFor(mine, [game('zzz', 'gba')]), isEmpty);
    });

    test('PSP con el mismo archivo: ad hoc de PSP', () {
      final mine = [game('dbz', 'psp', title: 'Dragon Ball Z Tenkaichi Tag Team')];
      final exps = experiencesFor(mine, mine);
      expect(exps.single.mode, NetMode.pspAdhoc);
      expect(exps.single.consoleId, 'psp');
      expect(Experience.fromJson(exps.single.toJson())!.sameAs(exps.single), isTrue);
      expect(experiencesFor(mine, [game('otro', 'psp')]), isEmpty);
    });

    test('opciones ad hoc: el anfitrión abre el servidor y el invitado va a su IP', () {
      final host = pspAdhocOptions(host: true, serverAddress: '192.168.1.20');
      expect(host['ppsspp_enable_wlan'], 'enabled');
      expect(host['ppsspp_enable_builtin_pro_ad_hoc_server'], 'enabled');
      // Nunca "localhost": el otro vería al anfitrión en 127.0.0.1.
      expect(host['ppsspp_change_pro_ad_hoc_server_address'], 'IP address');
      expect(host['ppsspp_port_offset'], '10000');
      final guest = pspAdhocOptions(host: false, serverAddress: '192.168.1.20');
      expect(guest['ppsspp_enable_builtin_pro_ad_hoc_server'], 'disabled');
      expect(guest['ppsspp_change_pro_ad_hoc_server_address'], 'IP address');
      final ip = [for (var i = 1; i <= 12; i++) guest['ppsspp_pro_ad_hoc_server_address${i.toString().padLeft(2, '0')}']].join();
      expect(ip, '192168001020');
      expect(() => pspAdhocOptions(host: false, serverAddress: 'x'), throwsArgumentError);
      expect(addressFacing('10.0.0.29', ['172.20.0.1', '10.0.0.10', '192.168.56.1']), '10.0.0.10');
      expect(addressFacing('10.0.0.29', const []), isNull);
    });

    test('link de Pokémon si los dos tienen uno, aunque sean juegos distintos', () {
      final mine = [game('emerald', 'gba', poke: true)];
      final theirs = [game('firered', 'gba', poke: true)];
      final exps = experiencesFor(mine, theirs);
      expect(exps.single.mode, NetMode.link);
      expect(experiencesFor(mine, const []), isEmpty);
    });
  });

  test('en Windows están todas las consolas, también PSP', () {
    isWindowsDesktop = () => true;
    addTearDown(() => isWindowsDesktop = () => false);
    for (final c in ConsoleRegistry.all) {
      expect(c.status, CoreStatus.available, reason: c.id);
    }
  });

  test('LanGame y Experience se envían y reciben por JSON', () {
    final g = game('abc', 'gba', poke: true, title: 'Pokémon Esmeralda');
    final back = LanGame.listFromJson([g.toJson(), 'basura', {'sha1': 1}]);
    expect(back.single.title, 'Pokémon Esmeralda');
    expect(back.single.pokemonLink, isTrue);
    expect(back.single.id, -1, reason: 'el id local no viaja');

    const shared = Experience.shared(sha1: 'abc', title: 'Kirby', consoleId: 'snes');
    expect(Experience.fromJson(shared.toJson())!.sameAs(shared), isTrue);
    expect(Experience.fromJson(const Experience.link().toJson())!.mode, NetMode.link);
    expect(Experience.fromJson('x'), isNull);
  });

  test('isPokemonGen3 lee el código de la cabecera del cartucho', () async {
    final dir = await Directory.systemTemp.createTemp('rs_poke');
    addTearDown(() => dir.delete(recursive: true));
    Future<String> rom(String code) async {
      final bytes = Uint8List(0xC0);
      bytes.setAll(0xAC, code.codeUnits);
      final f = File('${dir.path}/$code.gba');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    expect(await isPokemonGen3(await rom('BPES')), isTrue); // Esmeralda (España)
    expect(await isPokemonGen3(await rom('BPRS')), isTrue); // Rojo Fuego (España)
    expect(await isPokemonGen3(await rom('AXVE')), isTrue); // Rubí
    expect(await isPokemonGen3(await rom('BZME')), isFalse); // otro juego
    expect(await isPokemonGen3('${dir.path}/no_existe.gba'), isFalse);
  });
}
