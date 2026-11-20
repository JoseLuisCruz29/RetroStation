import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../controllers/keyboard_bindings.dart';
import '../../settings/app_settings.dart';
import '../widgets/section_header.dart';

/// Ajustes > Teclado: qué tecla corresponde a cada botón al jugar en el PC.
class KeyboardScreen extends ConsumerWidget {
  const KeyboardScreen({super.key});

  Future<void> _change(BuildContext context, WidgetRef ref, BindableButton button) async {
    final key = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (ctx) => _CaptureKeyDialog(button: button),
    );
    if (key == null) return;
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(keyboard: KeyboardBindings.assign(settings.keyboard, button.id, key)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final keys = KeyboardBindings.resolve(settings.keyboard);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teclado'),
        actions: [
          TextButton(
            onPressed: settings.keyboard.isEmpty
                ? null
                : () => ref.read(settingsProvider.notifier).update(settings.copyWith(keyboard: const {})),
            child: const Text('Restablecer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Pulsa un botón de la lista y después la tecla que quieras usar. Si esa tecla ya '
              'la usaba otro botón, se intercambian. Los mandos USB o Bluetooth siempre funcionan.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SectionHeader('Botones'),
          for (final b in KeyboardBindings.buttons)
            ListTile(
              leading: const Icon(Icons.keyboard_rounded),
              title: Text(b.label),
              subtitle: b.hint == null ? null : Text(b.hint!),
              trailing: _KeyCap(
                KeyboardBindings.keyName(keys[b.id]!),
                changed: keys[b.id] != KeyboardBindings.defaults[b.id],
              ),
              onTap: () => _change(context, ref, b),
            ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label, {required this.changed});

  final String label;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = changed ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
    );
  }
}

/// Espera a que se pulse una tecla (Esc cancela).
class _CaptureKeyDialog extends StatelessWidget {
  const _CaptureKeyDialog({required this.button});

  final BindableButton button;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
        } else if (!KeyboardBindings.reserved(event.logicalKey)) {
          Navigator.pop(context, event.logicalKey);
        }
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        icon: const Icon(Icons.keyboard_alt_rounded),
        title: Text('Botón ${button.label}'),
        content: const Text('Pulsa la tecla que quieres usar.\nEsc para cancelar.', textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
