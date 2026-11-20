import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../brand/retro.dart';
import '../../emulation/native_bindings.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../engines/core_options.dart';
import '../../multiplayer/lan_service.dart';
import '../../multiplayer/multiplayer_games.dart';
import '../../settings/app_settings.dart';
import '../../storage/storage_providers.dart';
import '../widgets/section_header.dart';

/// Sala privada de dos jugadores: los dos marcan "Listo", el anfitrión elige
/// la experiencia y pulsa Empezar; entonces los dos teléfonos abren el juego.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  late final LanController _lan;

  /// Juego de Pokémon propio con el que conectarse por link.
  int? _linkGameId;
  int _handledLaunch = 0;

  @override
  void initState() {
    super.initState();
    _lan = ref.read(lanProvider.notifier);
  }

  Future<void> _start(RoomState room) async {
    final exp = room.selection;
    if (exp == null) return;
    var options = <String, String>{};
    if (exp.mode == NetMode.shared) {
      final chosen = await ref.read(coreOptionsRepositoryProvider).load(exp.consoleId);
      options = CoreOptionsRepository.effective(exp.consoleId, chosen);
    }
    _lan.startGame(coreOptions: options);
  }

  Future<void> _launch(RoomState room, RoomLaunch launch) async {
    _handledLaunch = launch.serial;
    final library = ref.read(lanProvider).library;
    final exp = launch.experience;
    final int? gameId;
    if (exp.mode == NetMode.link) {
      final games = pokemonGames(library);
      gameId = games.where((g) => g.id == _linkGameId).firstOrNull?.id ?? games.firstOrNull?.id;
    } else {
      gameId = localGameFor(exp, library)?.id;
    }
    if (gameId == null) {
      _snack('No tienes ese juego en tu biblioteca.');
      _lan.consumeLaunch();
      return;
    }
    var coreOptions = exp.mode == NetMode.link ? linkCoreOptions : launch.coreOptions;
    if (exp.mode == NetMode.gbaLink) {
      // Cada dispositivo arranca las dos GBA con las mismas partidas: la suya
      // (saves/<sha1>.srm, la de siempre) y la que acaba de enviar el otro.
      final saves = ref.read(appPathsProvider).saves.path;
      final own = p.join(saves, '${exp.sha1}.srm');
      final dir = Directory(p.join(saves, 'multijugador_link'));
      await dir.create(recursive: true);
      final peer = File(p.join(dir.path, '${exp.sha1}_otro.srm'));
      await peer.writeAsBytes(launch.peerSave ?? const [], flush: true);
      coreOptions = {
        'gbalink_local': room.isHost ? '1' : '2',
        'gbalink_save1': room.isHost ? own : peer.path,
        'gbalink_save2': room.isHost ? peer.path : own,
      };
      if (!mounted) return;
    }
    if (exp.mode == NetMode.pspAdhoc) {
      // Cada uno con sus opciones de PSP y la red ad hoc de PPSSPP.
      final chosen = await ref.read(coreOptionsRepositoryProvider).load('psp');
      final settings = ref.read(settingsProvider);
      try {
        coreOptions = {
          ...CoreOptionsRepository.effective('psp', chosen,
              pcQuality: isWindowsDesktop() ? settings.pcQuality : null),
          ...pspAdhocOptions(
            host: room.isHost,
            // El servidor está en el anfitrión: él usa su IP en esta red y el
            // invitado la del anfitrión.
            serverAddress: room.isHost
                ? addressFacing(room.peerAddress.address, ref.read(lanProvider).addresses) ?? ''
                : launch.hostAddress,
          ),
          'rs_username': _pspNickname(settings.playerName),
        };
      } on ArgumentError {
        _snack('No se pudo conectar con ${room.peerName}: dirección no válida.');
        _lan.consumeLaunch();
        return;
      }
      if (!mounted) return;
    }
    _lan.setPlaying(true);
    await context.push(
      Routes.player(gameId),
      extra: NetplayArgs(
        host: room.isHost,
        mode: exp.mode,
        hostAddress: launch.hostAddress,
        token: launch.token,
        peerName: room.peerName,
        coreOptions: coreOptions,
      ),
    );
    _lan.setPlaying(false);
    _lan.consumeLaunch();
    // El otro jugador pudo salir de la sala durante la partida.
    if (mounted && ref.read(lanProvider).room == null) context.pop();
  }

  /// Apodo de la PSP: el nombre del multijugador, sin acentos y corto.
  static String _pspNickname(String name) {
    const from = 'áéíóúüñÁÉÍÓÚÜÑ';
    const to = 'aeiouunAEIOUUN';
    final buf = StringBuffer();
    for (final ch in name.trim().split('')) {
      final i = from.indexOf(ch);
      final c = i >= 0 ? to[i] : ch;
      if (RegExp(r'[A-Za-z0-9 _\-]').hasMatch(c)) buf.write(c);
    }
    final clean = buf.toString().trim();
    final nick = clean.isEmpty ? 'Jugador' : clean;
    return nick.length > 16 ? nick.substring(0, 16) : nick;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir de la sala?'),
        content: const Text('Se cerrará la conexión con el otro jugador.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quedarme')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final lan = ref.watch(lanProvider);
    final room = lan.room;
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    ref.listen(lanProvider, (prev, next) {
      final launch = next.room?.launch;
      if (launch != null && launch.serial != _handledLaunch) unawaited(_launch(next.room!, launch));
      // Sala cerrada: se vuelve a Multijugador (que muestra el aviso). Si hay
      // una partida abierta encima, sigue: se vuelve al terminarla.
      if (next.room == null && prev?.room != null && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        context.pop();
      }
    });

    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final me = settings.playerName.isEmpty ? 'Jugador' : settings.playerName;
    final experiences = experiencesFor(lan.library, room.peerLibrary);
    final selection = room.selection;
    final myPokemon = pokemonGames(lan.library);
    final canStart =
        room.isHost && selection != null && room.myReady && room.peerReady && !room.waitingSave;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) _lan.leaveRoom();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Sala LAN')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SectionHeader('Conectados'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _Seat(
                      name: room.isHost ? me : room.peerName,
                      role: 'Anfitrión · Jugador 1',
                      ready: room.isHost ? room.myReady : room.peerReady,
                      isMe: room.isHost,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Seat(
                      name: room.isHost ? room.peerName : me,
                      role: 'Invitado · Jugador 2',
                      ready: room.isHost ? room.peerReady : room.myReady,
                      isMe: !room.isHost,
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader(
              'Seleccionar experiencia',
              subtitle: room.isHost ? 'Juegos que tenéis los dos' : 'La elige el anfitrión',
            ),
            if (experiences.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No tenéis ningún juego en común. Para jugar juntos hace falta el mismo archivo '
                  'de NES, SNES o PS1 en los dos teléfonos, o un Pokémon de GBA de 3.ª generación cada uno.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            for (final exp in experiences)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: RetroPanel(
                  selected: exp.sameAs(selection),
                  onTap: room.isHost ? () => _lan.select(exp) : null,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox.square(dimension: 44, child: ConsoleArt(exp.consoleId)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(exp.title, style: theme.textTheme.titleMedium),
                            Text(
                              '${ConsoleRegistry.byId(exp.consoleId)?.shortName ?? exp.consoleId} · ${exp.subtitle}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (exp.sameAs(selection))
                        Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            if (selection?.mode == NetMode.link && myPokemon.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: DropdownButtonFormField<int>(
                  initialValue: _linkGameId ?? myPokemon.first.id,
                  decoration: const InputDecoration(labelText: 'Tu juego'),
                  items: [
                    for (final g in myPokemon) DropdownMenuItem(value: g.id, child: Text(g.title)),
                  ],
                  onChanged: (v) => setState(() => _linkGameId = v),
                ),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _lan.setReady(!room.myReady),
                    icon: Icon(room.myReady ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                    label: Text(room.myReady ? 'Listo' : 'Marcar como listo'),
                  ),
                  if (room.isHost) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: canStart ? () => _start(room) : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Empezar'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    room.waitingSave
                        ? 'Recibiendo la partida guardada de ${room.peerName}…'
                        : switch ((room.isHost, selection, room.myReady && room.peerReady)) {
                      (true, null, _) => 'Elige una experiencia.',
                      (true, _, false) => 'Esperando a que los dos estéis listos.',
                      (true, _, true) => '¡Todo listo! Pulsa Empezar.',
                      (false, null, _) => 'Esperando selección del anfitrión.',
                      (false, _, _) => 'Esperando a que ${room.peerName} empiece la partida.',
                    },
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.name, required this.role, required this.ready, required this.isMe});

  final String name;
  final String role;
  final bool ready;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RetroPanel(
      selected: isMe,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Text(name.characters.first.toUpperCase(),
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 20)),
          ),
          const SizedBox(height: 8),
          Text(isMe ? '$name (tú)' : name,
              style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(role, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
                  size: 16, color: ready ? RetroColors.success : RetroColors.warning),
              const SizedBox(width: 4),
              Text(ready ? 'Listo' : 'Esperando',
                  style: TextStyle(color: ready ? RetroColors.success : RetroColors.warning)),
            ],
          ),
        ],
      ),
    );
  }
}
