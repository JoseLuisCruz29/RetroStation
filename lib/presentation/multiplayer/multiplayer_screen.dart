import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../brand/retro.dart';
import '../../engines/console_registry.dart';
import '../../game_library/game_repository.dart';
import '../../multiplayer/game_transfer.dart';
import '../../multiplayer/lan_service.dart';
import '../../storage/database.dart';
import '../../settings/app_settings.dart';
import '../widgets/section_header.dart';

part 'send_games_widgets.dart';

/// Multijugador LAN: perfil, jugadores encontrados en la misma Wi-Fi y
/// peticiones de conexión. Al aceptar (o ser aceptado) se pasa a la sala.
class MultiplayerScreen extends ConsumerStatefulWidget {
  const MultiplayerScreen({super.key});

  @override
  ConsumerState<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends ConsumerState<MultiplayerScreen> {
  late final LanController _lan;
  late final GameTransferController _transfer;
  bool _requestDialogOpen = false;
  bool _offerDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _lan = ref.read(lanProvider.notifier);
    _transfer = ref.read(gameTransferProvider.notifier);
    unawaited(_transfer.listen());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ref.read(settingsProvider).playerName.trim().isEmpty) await _editName(first: true);
      if (mounted) unawaited(_lan.start());
    });
  }

  @override
  void dispose() {
    unawaited(_lan.stopDiscovery());
    unawaited(_transfer.stopListening());
    super.dispose();
  }

  Future<void> _editName({bool first = false}) async {
    final controller = TextEditingController(text: ref.read(settingsProvider).playerName);
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: !first,
      builder: (ctx) => AlertDialog(
        title: Text(first ? '¿Cómo te llamas?' : 'Tu nombre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Es el nombre que verán los demás jugadores de tu red.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 16,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Por ejemplo, Kigi'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          if (!first) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) {
      if (first && mounted && ref.read(settingsProvider).playerName.trim().isEmpty) {
        await ref.read(settingsProvider.notifier).update(ref.read(settingsProvider).copyWith(playerName: 'Jugador'));
      }
      return;
    }
    await ref.read(settingsProvider.notifier).update(ref.read(settingsProvider).copyWith(playerName: clean));
  }

  Future<void> _connectByIp() async {
    final controller = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar por IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Si tu amigo no aparece en la lista, escribe la IP que ve en su pantalla.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: '192.168.1.20'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Conectar')),
        ],
      ),
    );
    final address = InternetAddress.tryParse(ip?.trim() ?? '');
    if (address == null) {
      if (ip != null && ip.trim().isNotEmpty) _snack('Esa dirección no es válida.');
      return;
    }
    await _lan.requestJoinAddress(address);
  }

  Future<void> _showRequest(JoinRequest req) async {
    if (_requestDialogOpen) return;
    _requestDialogOpen = true;
    final me = ref.read(settingsProvider).playerName;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RequestDialog(request: req, myName: me),
    );
    _requestDialogOpen = false;
    if (!mounted) return;
    // La petición pudo cancelarse mientras el diálogo estaba abierto.
    if (ref.read(lanProvider).request == null) return;
    if (accept == true) {
      await _lan.acceptRequest();
    } else {
      _lan.rejectRequest();
    }
  }

  Future<void> _showOffer(IncomingOffer offer) async {
    if (_offerDialogOpen) return;
    _offerDialogOpen = true;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfferDialog(offer: offer),
    );
    _offerDialogOpen = false;
    if (!mounted || ref.read(gameTransferProvider).offer == null) return;
    _transfer.answerOffer(accept == true);
  }

  Future<void> _sendGames(LanPeer peer) async {
    final games = await showModalBottomSheet<List<Game>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PickGamesSheet(peerName: peer.name),
    );
    if (games == null || games.isEmpty || !mounted) return;
    await _transfer.send(peer.address, peer.name, games);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final lan = ref.watch(lanProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    ref.listen(lanProvider, (prev, next) {
      if (next.notice != null && next.notice != prev?.notice) {
        _snack(next.notice!);
        _lan.clearNotice();
      }
      if (next.request != null && prev?.request == null) unawaited(_showRequest(next.request!));
      if (next.request == null && prev?.request != null && _requestDialogOpen) {
        Navigator.of(context, rootNavigator: true).maybePop(false);
      }
      if (next.room != null && prev?.room == null) unawaited(context.push(Routes.multiplayerRoom));
    });
    ref.listen(gameTransferProvider, (prev, next) {
      if (next.offer != null && prev?.offer == null) unawaited(_showOffer(next.offer!));
      if (next.offer == null && prev?.offer != null && _offerDialogOpen) {
        Navigator.of(context, rootNavigator: true).maybePop(false);
      }
      final done = next.progress;
      if (done != null && !done.active && (prev?.progress?.active ?? false) && done.message != null) {
        _snack(done.message!);
      }
    });
    final transfer = ref.watch(gameTransferProvider).progress;

    final peers = lan.peers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multijugador LAN'),
        actions: [
          IconButton(
            tooltip: 'Conectar por IP',
            icon: const Icon(Icons.lan_rounded),
            onPressed: lan.connectingTo == null ? _connectByIp : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _PlayerCard(
              name: settings.playerName.isEmpty ? 'Jugador' : settings.playerName,
              status: lan.room != null ? 'En línea · En una sala' : 'En línea · Buscando partida',
              trailing: IconButton(
                tooltip: 'Cambiar nombre',
                icon: const Icon(Icons.edit_rounded),
                onPressed: _editName,
              ),
              highlight: true,
              footer: lan.addresses.isEmpty
                  ? 'Conéctate a una Wi-Fi (o a la zona Wi-Fi de tu amigo).'
                  : 'Tu IP: ${lan.addresses.join(' · ')}',
            ),
          ),
          if (transfer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _TransferCard(
                progress: transfer,
                onCancel: _transfer.cancel,
                onClose: _transfer.clearFinished,
              ),
            ),
          SectionHeader(
            'Jugadores en tu red',
            subtitle: 'Con RetroStation abierto en esta sección',
            trailing: lan.running
                ? const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.wifi_find_rounded, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Buscando jugadores…', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Pide a tu amigo que abra Multijugador LAN en su teléfono, conectado a la misma Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            for (final peer in peers)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _PlayerCard(
                  name: peer.name,
                  status: 'En línea · ${peer.status.label}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Enviar juegos a ${peer.name}',
                      icon: const Icon(Icons.send_to_mobile_rounded),
                      onPressed: transfer?.active ?? false ? null : () => _sendGames(peer),
                    ),
                    if (lan.connectingTo == peer.id)
                      TextButton(onPressed: _lan.cancelRequest, child: const Text('Cancelar'))
                    else
                      FilledButton(
                        onPressed: peer.status == PeerStatus.available &&
                                lan.connectingTo == null &&
                                lan.room == null
                            ? () => _lan.requestJoin(peer)
                            : null,
                        child: const Text('Conectar'),
                      ),
                  ]),
                  footer: lan.connectingTo == peer.id ? 'Esperando a que ${peer.name} acepte…' : null,
                ),
              ),
          if (lan.connectingTo != null && !peers.any((p) => p.id == lan.connectingTo))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text('Conectando con ${lan.connectingTo}…')),
                TextButton(onPressed: _lan.cancelRequest, child: const Text('Cancelar')),
              ]),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _HowItWorks(),
          ),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.name,
    required this.status,
    this.trailing,
    this.footer,
    this.highlight = false,
  });

  final String name;
  final String status;
  final Widget? trailing;
  final String? footer;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RetroPanel(
      selected: highlight,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
                child: Text(name.characters.first.toUpperCase(),
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      const Icon(Icons.circle, size: 8, color: RetroColors.success),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(status,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    ]),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Text(footer!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _RequestDialog extends StatelessWidget {
  const _RequestDialog({required this.request, required this.myName});

  final JoinRequest request;
  final String myName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget side(String role, String name) => Expanded(
          child: Column(children: [
            Text(role, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            Text(name, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          ]),
        );
    return AlertDialog(
      title: const Text('Solicitud de conexión'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            side('ANFITRIÓN', myName.isEmpty ? 'Tú' : myName),
            Icon(Icons.sync_alt_rounded, color: theme.colorScheme.primary),
            side('INVITADO', request.peerName),
          ]),
          const SizedBox(height: 16),
          Text('${request.peerName} quiere conectarse contigo para jugar.', textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rechazar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
      ],
    );
  }
}

const _firewallTip = '\n• En el PC: si Windows pregunta por el Firewall, pulsa «Permitir» '
    '(redes privadas); si no, los teléfonos no podrán encontrarte.';

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cómo funciona', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          '• Los dos dispositivos en la misma Wi-Fi (o uno compartiendo su zona Wi-Fi). '
          'Funciona entre teléfonos y también entre el PC y un teléfono.\n'
          '• Quien acepta la conexión es el anfitrión y elige a qué jugar.\n'
          '• Cada uno juega en su dispositivo con sus controles: no es ver la pantalla del otro.\n'
          '• Juego compartido (NES, SNES, PS1): hace falta el mismo archivo del juego en los dos.\n'
          '• Cable link de GBA (Kirby, Mario Kart...): el mismo archivo en los dos; cada uno ve '
          'su GBA y guarda su partida. Dentro del juego, elegid el modo multijugador.\n'
          '• Pokémon Rubí, Zafiro, Esmeralda, Rojo Fuego y Verde Hoja: intercambios y combates, '
          'cada uno con su partida (también con ediciones distintas).\n'
          '• PSP (Dragon Ball, Monster Hunter, Tekken...): «Ad hoc de PSP», el multijugador '
          'inalámbrico de la consola. El mismo juego en los dos; dentro del juego, entrad los '
          'dos al modo multijugador inalámbrico.\n'
          '• Enviar juegos: pulsa el icono de envío junto a un dispositivo y elige los juegos. '
          'Se copian por la Wi-Fi, sin internet, y aparecen en «Mis juegos» del otro.'
          '${Platform.isWindows ? _firewallTip : ''}',
          style: muted,
        ),
      ],
    );
  }
}
