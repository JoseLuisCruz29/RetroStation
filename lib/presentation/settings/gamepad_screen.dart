import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../controllers/gamepad.dart';
import '../../settings/app_settings.dart';
import '../widgets/section_header.dart';

/// Ajustes > Mando (PC): mandos conectados y qué botón hace cada cosa.
class GamepadScreen extends ConsumerWidget {
  const GamepadScreen({super.key});

  Future<void> _change(BuildContext context, WidgetRef ref, int action, String label) async {
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => _CaptureButtonDialog(label: label),
    );
    if (input == null) return;
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(
            gamepad: GamepadBindings.assign(
                settings.gamepad, action, input, Gamepads.instance.connected.firstOrNull)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Gamepads.instance,
      builder: (context, _) {
        final pads = Gamepads.instance.connected;
        final pad = pads.firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mando'),
            actions: [
              TextButton(
                onPressed: settings.gamepad.isEmpty
                    ? null
                    : () => ref.read(settingsProvider.notifier).update(settings.copyWith(gamepad: const {})),
                child: const Text('Restablecer'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SectionHeader('Mandos conectados'),
              if (pads.isEmpty)
                ListTile(
                  leading: Icon(Icons.gamepad_outlined, color: theme.colorScheme.onSurfaceVariant),
                  title: const Text('No hay ningún mando'),
                  subtitle: const Text(
                      'Conéctalo por USB o Bluetooth (en Configuración de Windows > Bluetooth). '
                      'Aparece aquí solo en unos segundos.'),
                )
              else
                for (final p in pads)
                  ListTile(
                    leading: Icon(Icons.sports_esports_rounded, color: theme.colorScheme.primary),
                    title: Text(p.displayName),
                    subtitle: _LiveInputs(pad: p),
                  ),
              const SectionHeader('Botones'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'La cruceta del mando es la cruceta. El joystick izquierdo también la mueve, '
                  'y en PSP funciona como joystick. Pulsa un botón de la lista para cambiarlo.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final (action, label) in GamepadBindings.actions)
                ListTile(
                  leading: Icon(action == GamepadBindings.menu ? Icons.menu_rounded : Icons.radio_button_checked),
                  title: Text(label),
                  subtitle: action == GamepadBindings.menu
                      ? const Text('Pausa, guardar o cargar estado, salir')
                      : null,
                  trailing: Text(
                    GamepadBindings.inputsFor(action, settings.gamepad, pad)
                        .map((i) => GamepadBindings.inputName(i, pad))
                        .join(' / '),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: settings.gamepad.containsKey(action)
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _change(context, ref, action, label),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Muestra lo que se está pulsando (para comprobar que el mando funciona).
class _LiveInputs extends StatefulWidget {
  const _LiveInputs({required this.pad});
  final PadState pad;

  @override
  State<_LiveInputs> createState() => _LiveInputsState();
}

class _LiveInputsState extends State<_LiveInputs> {
  StreamSubscription<PadState>? _sub;
  late PadState _pad = widget.pad;

  @override
  void initState() {
    super.initState();
    _sub = Gamepads.instance.changes.listen((p) {
      if (p.id == _pad.id && mounted) setState(() => _pad = p);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pad.pressed.map((i) => GamepadBindings.inputName(i, _pad)).toList();
    return Text(pressed.isEmpty ? 'Conectado · pulsa un botón para probarlo' : 'Pulsado: ${pressed.join(', ')}');
  }
}

/// Espera a que se pulse un botón del mando.
class _CaptureButtonDialog extends StatefulWidget {
  const _CaptureButtonDialog({required this.label});
  final String label;

  @override
  State<_CaptureButtonDialog> createState() => _CaptureButtonDialogState();
}

class _CaptureButtonDialogState extends State<_CaptureButtonDialog> {
  StreamSubscription<PadState>? _sub;
  final _held = <int, Set<String>>{};

  @override
  void initState() {
    super.initState();
    // Lo que ya estaba pulsado al abrir no cuenta: solo una pulsación nueva.
    for (final p in Gamepads.instance.connected) {
      _held[p.id] = p.pressed;
    }
    _sub = Gamepads.instance.changes.listen((p) {
      final before = _held[p.id] ?? const {};
      final now = p.pressed;
      final fresh = now.difference(before).where((i) => i.startsWith('b'));
      _held[p.id] = now;
      if (fresh.isNotEmpty && mounted) Navigator.pop(context, fresh.first);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.sports_esports_rounded),
        title: Text(widget.label),
        content: const Text('Pulsa el botón del mando que quieres usar.', textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
}
