import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/ui_sound.dart';
import '../emulation/native_bindings.dart';
import '../settings/app_settings.dart';
import 'gamepad.dart';

/// Moverse por la app con el mando (en el PC): cruceta o joystick para
/// moverse entre opciones, A (o Start) para elegir y B para volver.
///
/// Mientras se juega, el mando es del juego ([Gamepads.gameCapture]).
class GamepadNavigator extends StatefulWidget {
  const GamepadNavigator({super.key, required this.child, required this.settings, required this.onBack});

  final Widget child;
  final AppSettings settings;

  /// Volver atrás cuando no hay un diálogo que cerrar.
  final VoidCallback onBack;

  @override
  State<GamepadNavigator> createState() => _GamepadNavigatorState();
}

enum _NavAction { up, down, left, right, accept, back }

class _GamepadNavigatorState extends State<GamepadNavigator> {
  StreamSubscription<PadState>? _sub;
  Set<_NavAction> _held = const {};
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _sub = Gamepads.instance.changes.listen((_) => _update());
  }

  @override
  void dispose() {
    _repeat?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Set<_NavAction> _current() {
    final pads = Gamepads.instance;
    final read = pads.read(
      GamepadBindings.resolve(widget.settings.gamepad, pads.connected.firstOrNull),
      analogStick: false, // el joystick también mueve el cursor
    );
    bool has(int button) => read.mask & (1 << button) != 0;
    return {
      if (has(RetroButton.up)) _NavAction.up,
      if (has(RetroButton.down)) _NavAction.down,
      if (has(RetroButton.left)) _NavAction.left,
      if (has(RetroButton.right)) _NavAction.right,
      if (has(RetroButton.a) || has(RetroButton.start)) _NavAction.accept,
      if (has(RetroButton.b)) _NavAction.back,
    };
  }

  void _update() {
    if (Gamepads.instance.gameCapture) {
      _held = const {};
      _repeat?.cancel();
      return;
    }
    final now = _current();
    final fresh = now.difference(_held);
    _held = now;
    for (final action in fresh) {
      _perform(action);
    }
    // Mantener una dirección: se repite (primero tras 400 ms, luego cada 120 ms).
    final direction = now.where((a) => a.index <= _NavAction.right.index).firstOrNull;
    if (direction == null) {
      _repeat?.cancel();
      _repeat = null;
    } else if (fresh.contains(direction)) {
      _repeat?.cancel();
      _repeat = Timer(const Duration(milliseconds: 400), () {
        _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) {
          if (_held.contains(direction) && !Gamepads.instance.gameCapture) {
            _perform(direction);
          } else {
            _repeat?.cancel();
          }
        });
      });
    }
  }

  void _perform(_NavAction action) {
    final manager = FocusManager.instance;
    // Con el mando, el elemento elegido se resalta (como con el teclado).
    manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final focus = manager.primaryFocus;
    switch (action) {
      case _NavAction.accept:
        final ctx = focus?.context;
        if (ctx != null && focus is! FocusScopeNode) {
          Actions.maybeInvoke(ctx, const ActivateIntent());
        } else {
          _moveFirst(focus);
        }
      case _NavAction.back:
        UiSound.play(Sfx.back);
        final ctx = focus?.context;
        final navigator = ctx == null ? null : Navigator.maybeOf(ctx);
        if (navigator != null && navigator.canPop()) {
          unawaited(navigator.maybePop());
        } else {
          widget.onBack();
        }
      case _NavAction.up || _NavAction.down || _NavAction.left || _NavAction.right:
        if (focus == null || focus is FocusScopeNode || focus.context == null) {
          _moveFirst(focus);
        } else {
          final moved = focus.focusInDirection(switch (action) {
            _NavAction.up => TraversalDirection.up,
            _NavAction.down => TraversalDirection.down,
            _NavAction.left => TraversalDirection.left,
            _ => TraversalDirection.right,
          });
          // Sin nada en esa dirección (fin de una lista): orden de lectura.
          if (!moved) {
            if (action == _NavAction.down || action == _NavAction.right) {
              focus.nextFocus();
            } else {
              focus.previousFocus();
            }
          }
        }
        UiSound.play(Sfx.move);
    }
  }

  /// Nada elegido aún: el primer elemento de la pantalla.
  void _moveFirst(FocusNode? focus) {
    final scope = focus is FocusScopeNode ? focus : (focus?.nearestScope ?? FocusManager.instance.rootScope);
    scope.nextFocus();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
