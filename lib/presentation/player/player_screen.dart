import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../emulation/emulator_session.dart';
import '../../controllers/gamepad.dart';
import '../../controllers/keyboard_bindings.dart';
import '../../emulation/native_bindings.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../engines/core_options.dart';
import '../../game_library/game_repository.dart';
import '../../multiplayer/lan_service.dart';
import '../../multiplayer/multiplayer_games.dart';
import '../../save_manager/save_state_service.dart';
import '../../settings/app_settings.dart';
import '../../storage/database.dart';
import '../../storage/storage_providers.dart';
import '../widgets/empty_state.dart';
import 'quick_menu.dart';
import 'touch_controls.dart';
import 'video_filters.dart';

/// Pantalla de juego: imagen del núcleo, controles táctiles, teclado/mando,
/// menú rápido (save states, avance rápido, reinicio) y ciclo de vida.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.gameId, this.loadSlot, this.netplay});

  final int gameId;

  /// Partida multijugador por la red local (null = un jugador).
  final NetplayArgs? netplay;

  /// Si se indica, se carga esa ranura de save state al arrancar.
  final int? loadSlot;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  EmulatorSession? _session;
  Game? _game;
  Object? _error;
  String? _unavailable;
  bool _userPaused = false;
  bool _menuOpen = false;
  bool _fastForward = false;
  bool _rewinding = false;
  late final AppLifecycleListener _lifecycle;
  final _focusNode = FocusNode();
  final _playStopwatch = Stopwatch();
  // Riverpod no permite usar `ref` dentro de dispose(): se obtienen antes.
  late final GameRepository _games;
  late final SaveStateService _states;
  Timer? _playTimeTimer;
  Duration _recorded = Duration.zero;

  // Multijugador: estado de la conexión (se consulta 4 veces por segundo).
  NetStatus? _net;
  Timer? _netTimer;
  String? _netEndMessage;
  NetplayArgs? get _netplay => widget.netplay;

  /// Guarda el tiempo jugado pendiente. Se llama cada minuto, al pasar a
  /// segundo plano y al salir: si el sistema mata la app no se pierde.
  void _flushPlayTime() {
    final game = _game;
    if (game == null) return;
    final delta = _playStopwatch.elapsed - _recorded;
    if (delta < const Duration(seconds: 1)) return;
    _recorded = _playStopwatch.elapsed;
    unawaited(_games.recordSession(game.id, delta));
  }

  // Teclas del PC (Ajustes > Teclado) y mandos físicos; se recalcula si cambian.
  Map<int, int>? _keysFor;
  Map<LogicalKeyboardKey, int> _keyMap = const {};

  /// Calidad gráfica del PC (Ajustes > Juego); en Android no se usa.
  GraphicsQuality? get _pcQuality => isWindowsDesktop() ? ref.read(settingsProvider).pcQuality : null;

  // Mandos del PC (Pro Controller, Xbox...): ver Ajustes > Mando.
  StreamSubscription<PadState>? _padSub;
  bool _padMenuHeld = false;

  void _onPad(PadState _) {
    final session = _session;
    final game = _game;
    if (session == null || game == null || !mounted) return;
    final settings = ref.read(settingsProvider);
    final analog = game.consoleId == 'psp' || game.consoleId == 'n64';
    final read = Gamepads.instance.read(
      GamepadBindings.resolve(settings.gamepad, Gamepads.instance.connected.firstOrNull),
      analogStick: analog,
    );
    // Botón de menú (Home): abre el menú del juego, o lo cierra si ya está abierto.
    if (read.menu && !_padMenuHeld) {
      if (_menuOpen) {
        Navigator.of(context).maybePop();
      } else {
        unawaited(_openMenu());
      }
    }
    _padMenuHeld = read.menu;
    session.setPadMask(_menuOpen ? 0 : read.mask);
    if (analog) session.setAnalog(_menuOpen ? Offset.zero : read.stick);
    if (game.consoleId == 'n64') session.setRightAnalog(_menuOpen ? Offset.zero : read.rightStick);
  }

  Map<LogicalKeyboardKey, int> _currentKeyMap() {
    final custom = ref.read(settingsProvider).keyboard;
    if (!identical(custom, _keysFor)) {
      _keysFor = custom;
      _keyMap = KeyboardBindings.keyMap(custom);
    }
    return _keyMap;
  }


  @override
  void initState() {
    super.initState();
    _padSub = Gamepads.instance.changes.listen(_onPad);
    _games = ref.read(gameRepositoryProvider);
    _states = ref.read(saveStateServiceProvider);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _applyPause(forceBackground: true);
        _flushPlayTime();
      },
      onShow: _applyPause,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _applyOrientation(ref.read(settingsProvider).orientation);
    // Ningún aviso de otras pantallas puede quedar encima de los controles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final game = await _games.watchById(widget.gameId).first;
      if (!mounted) return;
      if (game == null) {
        setState(() => _unavailable = 'Este juego ya no está en la biblioteca.');
        return;
      }
      _game = game;
      final console = ConsoleRegistry.byId(game.consoleId);
      if (console == null || console.status != CoreStatus.available) {
        setState(() => _unavailable = console == null
            ? 'No hay un núcleo registrado para "${game.consoleId}".'
            : console.note ??
                'La emulación de ${console.name} se integra en la Etapa ${console.plannedStage}.');
        return;
      }
      final chosen = await ref.read(coreOptionsRepositoryProvider).load(console.id);
      final net = _netplay;
      final paths = ref.read(appPathsProvider);
      var options = CoreOptionsRepository.effective(console.id, chosen, pcQuality: _pcQuality);
      // Link de GBA: gpSP con sus opciones. Juego compartido: el invitado usa
      // las opciones del anfitrión para que los dos juegos sean idénticos.
      if (net != null && (net.mode != NetMode.shared || !net.host)) options = net.coreOptions;
      final session = await EmulatorSession.start(
        game: game,
        console: console,
        paths: paths,
        coreOptions: options,
        coreLibraryOverride: switch (net?.mode) {
          NetMode.link => linkCoreLibrary,
          NetMode.gbaLink => gbaLinkCoreLibrary,
          _ => null,
        },
        // El invitado de un juego compartido recibe el estado del anfitrión:
        // sus propias partidas guardadas no se tocan.
        saveDirOverride: net != null && net.mode == NetMode.shared && !net.host
            ? p.join(paths.saves.path, 'multijugador_invitado')
            : null,
        // Ad hoc de PSP: la red la lleva PPSSPP; solo se pide Wi-Fi rápida.
        beforeStart: net == null
            ? null
            : net.mode == NetMode.pspAdhoc
                ? () => _lowLatencyWifi(true)
                : () => _startNetplay(game, net),
      );
      if (!mounted) {
        await session.dispose();
        return;
      }
      final settings = ref.read(settingsProvider);
      session
        ..setVolume(settings.volume)
        ..setRewindEnabled(net == null && settings.rewindEnabled && console.supportsRewind);
      final slot = net == null ? widget.loadSlot : null;
      if (slot != null) {
        try {
          _states.load(session, game, slot);
        } catch (e) {
          _snack('No se pudo cargar la ranura $slot: $e');
        }
      }
      _playStopwatch.start();
      _playTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) => _flushPlayTime());
      setState(() => _session = session);
      Gamepads.instance.gameCapture = true;
      // Marca la partida como reciente desde el primer momento.
      unawaited(_games.recordSession(game.id, Duration.zero));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static const _lan = MethodChannel('retrostation/lan');

  void _lowLatencyWifi(bool enabled) => unawaited(
      _lan.invokeMethod<void>('lowLatency', {'enabled': enabled}).catchError((Object _) {}));

  void _startNetplay(Game game, NetplayArgs net) {
    _lowLatencyWifi(true);
    try {
      RetroNative.instance.netplayStart(
        host: net.host,
        mode: net.mode,
        address: net.hostAddress,
        port: LanPorts.game,
        delay: 3,
        token: net.token,
        gameKey: game.sha1 ?? '',
      );
    } catch (e) {
      _netEndMessage = 'No se pudo iniciar el multijugador: $e';
      return;
    }
    _netTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final status = RetroNative.instance.netplayStatus();
      final ended = status.phase == NetPhase.disconnected || status.phase == NetPhase.failed;
      if (ended && _netEndMessage == null) {
        final msg = RetroNative.instance.netplayMessage;
        _netEndMessage = msg.isEmpty ? 'Se perdió la conexión con ${net.peerName}.' : msg;
      }
      setState(() => _net = status);
    });
  }

  /// El núcleo corre solo si la app está visible, el menú cerrado y el
  /// usuario no ha pausado.
  void _applyPause({bool forceBackground = false}) {
    final session = _session;
    if (session == null) return;
    final shouldPause = forceBackground || _userPaused || _menuOpen;
    if (shouldPause) {
      session.releaseAllButtons();
      session.pause();
      _playStopwatch.stop();
    } else {
      session.resume();
      _playStopwatch.start();
    }
  }

  void _applyOrientation(PlayerOrientation o) {
    SystemChrome.setPreferredOrientations(switch (o) {
      PlayerOrientation.auto => const [],
      PlayerOrientation.portrait => const [DeviceOrientation.portraitUp],
      PlayerOrientation.landscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
    });
  }

  void _toggleFastForward() {
    final session = _session;
    if (session == null) return;
    setState(() => _fastForward = !_fastForward);
    session.setSpeed(
        _fastForward ? ref.read(settingsProvider).fastForwardSpeed.toDouble() : 1);
  }

  void _setRewinding(bool value) {
    if (_rewinding == value) return;
    _session?.setRewinding(value);
    setState(() => _rewinding = value);
  }

  Future<void> _openMenu() async {
    final session = _session;
    final game = _game;
    if (session == null || game == null) return;
    setState(() => _menuOpen = true);
    Gamepads.instance.gameCapture = false; // el mando mueve el menú
    _applyPause();
    final action = await showModalBottomSheet<QuickMenuResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => QuickMenu(
        game: game,
        // En multijugador no se cargan estados ni se reinicia: los dos
        // teléfonos deben seguir el mismo juego.
        supportsStates: (_netplay == null || _netplay!.mode == NetMode.pspAdhoc) && session.supportsStates,
        allowReset: _netplay == null,
      ),
    );
    if (!mounted) return;
    switch (action) {
      case SaveSlot(:final slot):
        try {
          await _states.save(session, game, slot);
          _snack('Estado guardado en la ranura $slot');
        } catch (e) {
          _snack('No se pudo guardar: $e');
        }
      case LoadSlot(:final slot):
        try {
          _states.load(session, game, slot);
          _snack('Ranura $slot cargada');
        } catch (e) {
          _snack('No se pudo cargar: $e');
        }
      case ResetGame():
        session.reset();
      case ExitGame():
        Navigator.of(context).maybePop();
      case null:
        break;
    }
    if (!mounted) return;
    setState(() => _menuOpen = false);
    Gamepads.instance.gameCapture = _session != null;
    _applyPause();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final button = _currentKeyMap()[event.logicalKey];
    final session = _session;
    if (button == null || session == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      session.setButton(button, true);
    } else if (event is KeyUpEvent) {
      session.setButton(button, false);
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    // dispose() es síncrono: guardar la SRAM y soltar la superficie se
    // completan en segundo plano (el núcleo ya no se ejecuta tras unload).
    _lifecycle.dispose();
    unawaited(_padSub?.cancel());
    Gamepads.instance.gameCapture = false;
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    _playTimeTimer?.cancel();
    _netTimer?.cancel();
    if (_netplay != null) _lowLatencyWifi(false);
    final session = _session;
    if (session != null) {
      unawaited(session.dispose());
      _playStopwatch.stop();
      _flushPlayTime();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    ref.listen(settingsProvider, (prev, next) {
      _session?.setVolume(next.volume);
      _session?.setRewindEnabled(
          next.rewindEnabled && (ConsoleRegistry.byId(_game?.consoleId ?? '')?.supportsRewind ?? true));
      if (prev?.orientation != next.orientation) _applyOrientation(next.orientation);
    });
    final game = _game;
    if (game != null) {
      // Cambios de opciones del núcleo durante la partida.
      ref.listen(coreOptionsProvider(game.consoleId), (_, next) {
        final chosen = next.value;
        // En multijugador mandan las opciones de la sala (la Wi-Fi de la PSP
        // en ad hoc, las del anfitrión en juego compartido...): no se pisan.
        if (chosen != null && _netplay == null) {
          _session?.setCoreOptions(
              CoreOptionsRepository.effective(game.consoleId, chosen, pcQuality: _pcQuality));
        }
      });
    }
    final session = _session;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: session == null
            ? SafeArea(child: Column(children: [_topBar(settings, null), Expanded(child: _status())]))
            : Platform.isWindows
                ? _desktop(session, settings)
                : landscape
                ? _landscape(session, settings)
                : _portrait(session, settings),
      ),
    );
  }

  Widget _portrait(EmulatorSession session, AppSettings settings) => SafeArea(
        child: Column(
          children: [
            _topBar(settings, session),
            // Las pantallas altas (DS: 2 pantallas, 2:3) no pueden quitar el sitio
            // de los controles: como máximo el 58 % del alto disponible.
            LayoutBuilder(builder: (context, c) {
              final maxH = MediaQuery.sizeOf(context).height * 0.58;
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Center(child: _gameView(session, settings)),
              );
            }),
            Expanded(
              child: TouchControls(
                consoleId: _game!.consoleId,
                landscape: false,
                overrides: settings.layoutPortrait,
                opacity: settings.controlsOpacity,
                scale: settings.controlsScale,
                haptics: settings.haptics,
                skin: settings.controlSkin,
                onMaskChanged: session.setTouchMask,
                onAnalogChanged: session.setAnalog,
              ),
            ),
          ],
        ),
      );

  /// Windows: se juega con teclado o mando; la imagen ocupa toda la ventana
  /// y abajo se recuerdan las teclas.
  Widget _desktop(EmulatorSession session, AppSettings settings) => Column(
        children: [
          _topBar(settings, session),
          Expanded(child: Center(child: _gameView(session, settings))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ListenableBuilder(
              listenable: Gamepads.instance,
              builder: (context, _) {
                final pad = Gamepads.instance.connected.firstOrNull;
                final menu = GamepadBindings.inputsFor(GamepadBindings.menu, settings.gamepad, pad);
                return Text(
                  pad == null
                      ? KeyboardBindings.guide(settings.keyboard)
                      : 'Mando: ${pad.displayName} · '
                          '${menu.isEmpty ? '' : '${GamepadBindings.inputName(menu.first, pad)}: menú del juego · '}'
                          'cambia los botones en Ajustes > Mando',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                );
              },
            ),
          ),
        ],
      );

  /// Horizontal: barra arriba, imagen centrada y controles en franjas
  /// laterales que nunca se superponen a la imagen.
  Widget _landscape(EmulatorSession session, AppSettings settings) => SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          const barHeight = 48.0;
          var gameH = c.maxHeight - barHeight;
          var gameW = gameH * session.aspectRatio;
          final maxW = c.maxWidth * 0.6; // deja al menos un 20 % por lado
          if (gameW > maxW) {
            gameW = maxW;
            gameH = gameW / session.aspectRatio;
          }
          final gutter = (c.maxWidth - gameW) / 2;
          return Stack(
            children: [
              Positioned(
                left: gutter,
                top: barHeight,
                width: gameW,
                height: gameH,
                child: _gameView(session, settings),
              ),
              Positioned.fill(
                child: TouchControls(
                  consoleId: _game!.consoleId,
                  landscape: true,
                  gutter: gutter,
                  overrides: settings.layoutLandscape,
                  opacity: settings.controlsOpacity,
                  scale: settings.controlsScale,
                  haptics: settings.haptics,
                  skin: settings.controlSkin,
                  onMaskChanged: session.setTouchMask,
                  onAnalogChanged: session.setAnalog,
                ),
              ),
              Positioned(
                left: gutter,
                width: gameW,
                top: 0,
                height: barHeight,
                child: Center(child: _topBar(settings, session, compact: true)),
              ),
            ],
          );
        }),
      );

  /// Consolas cuya pantalla responde al tacto (la imagen es la pantalla táctil).
  bool get _hasTouchScreen => _game?.consoleId == 'nds';

  Widget _gameView(EmulatorSession session, AppSettings settings) => AspectRatio(
        aspectRatio: session.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FilteredGameTexture(
              textureId: session.textureId,
              filter: settings.videoFilter,
              sourceHeight: session.height,
            ),
            if (_hasTouchScreen)
              LayoutBuilder(builder: (context, c) {
                void send(Offset p, bool down) =>
                    session.setPointer(p.dx / c.maxWidth, p.dy / c.maxHeight, down);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => send(e.localPosition, true),
                  onPointerMove: (e) => send(e.localPosition, true),
                  onPointerUp: (e) => send(e.localPosition, false),
                  onPointerCancel: (e) => send(e.localPosition, false),
                );
              }),
            if (_netplay != null && _netplay!.mode != NetMode.pspAdhoc)
              _NetOverlay(status: _net, args: _netplay!, endMessage: _netEndMessage),
            if (_userPaused)
              const ColoredBox(
                color: Colors.black54,
                child: Center(child: Icon(Icons.pause_rounded, size: 64, color: Colors.white70)),
              ),
            if (_rewinding)
              const Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.fast_rewind_rounded, color: Colors.white70),
                ),
              ),
          ],
        ),
      );

  Widget _status() {
    if (_unavailable != null) {
      return EmptyState(
        icon: Icons.construction_rounded,
        title: 'No se puede jugar todavía',
        message: _unavailable!,
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo iniciar el juego',
        message: '$_error',
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _topBar(AppSettings settings, EmulatorSession? session, {bool compact = false}) {
    final iconColor = Colors.white.withValues(alpha: compact ? 0.7 : 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          IconButton(
            tooltip: 'Salir',
            color: iconColor,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          if (!compact)
            Expanded(
              child: Text(
                _game?.title ?? 'Cargando…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (session != null) ...[
            if (settings.showFps) FpsCounter(session: session),
            if (_netplay != null && _netplay!.mode != NetMode.pspAdhoc) _NetBadge(status: _net, args: _netplay!),
            if (_netplay?.mode == NetMode.pspAdhoc) _AdhocBadge(args: _netplay!),
            if (_netplay == null &&
                settings.rewindEnabled &&
                session.supportsStates &&
                (ConsoleRegistry.byId(_game?.consoleId ?? '')?.supportsRewind ?? true))
              // Sin Tooltip: su reconocedor de pulsación larga competía con
              // el gesto de mantener pulsado.
              Semantics(
                button: true,
                label: 'Mantén pulsado para rebobinar',
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _setRewinding(true),
                  onPointerUp: (_) => _setRewinding(false),
                  onPointerCancel: (_) => _setRewinding(false),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.fast_rewind_rounded,
                        color: _rewinding ? Theme.of(context).colorScheme.primary : iconColor),
                  ),
                ),
              ),
            if (_netplay == null)
              IconButton(
                tooltip: _fastForward ? 'Velocidad normal' : 'Avance rápido x${settings.fastForwardSpeed}',
              color: _fastForward ? Theme.of(context).colorScheme.primary : iconColor,
              icon: const Icon(Icons.fast_forward_rounded),
              onPressed: _toggleFastForward,
            ),
            IconButton(
              tooltip: _userPaused ? 'Reanudar' : 'Pausar',
              color: iconColor,
              icon: Icon(_userPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              onPressed: () {
                setState(() => _userPaused = !_userPaused);
                _applyPause();
              },
            ),
            IconButton(
              tooltip: 'Menú rápido',
              color: iconColor,
              icon: const Icon(Icons.menu_rounded),
              onPressed: _openMenu,
            ),
          ],
        ],
      ),
    );
  }
}

/// Jugador (J1/J2) y latencia en la barra superior.
/// Ad hoc de PSP: con quién se juega (la conexión la lleva el propio juego).
class _AdhocBadge extends StatelessWidget {
  const _AdhocBadge({required this.args});

  final NetplayArgs args;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Dentro del juego, entrad los dos al modo multijugador inalámbrico (ad hoc)',
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.lightBlueAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_tethering_rounded, size: 14, color: Colors.lightBlueAccent),
            const SizedBox(width: 4),
            Text('Ad hoc · ${args.peerName}',
                style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _NetBadge extends StatelessWidget {
  const _NetBadge({required this.status, required this.args});

  final NetStatus? status;
  final NetplayArgs args;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final online = s?.phase == NetPhase.playing;
    final color = online ? Colors.greenAccent : Colors.orangeAccent;
    final player = args.host ? 'J1' : 'J2';
    final ping = online && s!.rttMs >= 0 ? ' · ${s.rttMs} ms' : '';
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$player$ping', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Avisos del multijugador sobre la imagen: conectando, esperando al otro
/// jugador, pausa remota o desconexión.
class _NetOverlay extends StatelessWidget {
  const _NetOverlay({required this.status, required this.args, required this.endMessage});

  final NetStatus? status;
  final NetplayArgs args;
  final String? endMessage;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final peer = args.peerName;
    // Juego compartido y cable link de GBA: el juego se detiene sin el otro.
    final shared = args.mode != NetMode.link;
    // Mensaje a pantalla completa cuando el juego compartido está detenido.
    String? blocking;
    String? banner;
    if (endMessage != null) {
      banner = '$endMessage Sigues jugando solo.';
    } else if (s == null || s.phase == NetPhase.connecting) {
      final text = args.host ? 'Esperando a $peer…' : 'Conectando con $peer…';
      if (shared) {
        blocking = text;
      } else {
        banner = text;
      }
    } else if (s.phase == NetPhase.syncing) {
      blocking = 'Sincronizando con $peer…';
    } else if (s.phase == NetPhase.playing && shared && s.remotePaused) {
      blocking = '$peer ha pausado el juego';
    } else if (s.phase == NetPhase.playing && shared && s.stalled) {
      blocking = 'Esperando a $peer…';
    } else if (s.phase == NetPhase.playing && !shared && s.remotePaused) {
      banner = '$peer tiene el juego en pausa';
    }
    if (blocking != null) {
      return ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 12),
            Text(blocking, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    if (banner == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
        child: Text(banner, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
      ),
    );
  }
}

/// FPS medidos por el hilo nativo (no por Flutter).
class FpsCounter extends StatefulWidget {
  const FpsCounter({super.key, required this.session});

  final EmulatorSession session;

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter> {
  late final Timer _timer;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _fps = widget.session.fps);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _fps >= widget.session.targetFps * 0.97;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${_fps.toStringAsFixed(1)} FPS',
        style: TextStyle(
          color: ok ? Colors.greenAccent : Colors.orangeAccent,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
