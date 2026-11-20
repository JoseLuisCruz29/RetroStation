import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../engines/console_registry.dart';
import '../../engines/core_options.dart';
import '../widgets/empty_state.dart';

/// Ajustes del núcleo de una consola (opciones libretro reales).
class ConsoleSettingsScreen extends ConsumerWidget {
  const ConsoleSettingsScreen({super.key, required this.consoleId});

  final String consoleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final console = ConsoleRegistry.byId(consoleId);
    final options = CoreOptions.forConsole(consoleId);
    final chosen = ref.watch(coreOptionsProvider(consoleId)).value ?? const {};
    final repo = ref.read(coreOptionsRepositoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Ajustes de ${console?.shortName ?? consoleId}')),
      body: options.isEmpty
          ? const EmptyState(
              icon: Icons.tune_rounded,
              title: 'Sin ajustes',
              message: 'Esta consola todavía no tiene un núcleo con opciones configurables.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Núcleo: ${console?.activeCore.name ?? '—'}. Las opciones marcadas con ↻ '
                    'se aplican al volver a abrir el juego.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                for (final o in options)
                  ListTile(
                    title: Text('${o.label}${o.requiresRestart ? ' ↻' : ''}'),
                    subtitle: Text(o.description),
                    isThreeLine: true,
                    trailing: DropdownButton<String>(
                      value: chosen[o.key] != null && o.values.containsKey(chosen[o.key])
                          ? chosen[o.key]
                          : o.defaultValue,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final e in o.values.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(e.key == o.defaultValue ? '${e.value} (defecto)' : e.value),
                          ),
                      ],
                      onChanged: (v) => repo.set(consoleId, o.key, v == o.defaultValue ? null : v),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      for (final o in options) {
                        await repo.set(consoleId, o.key, null);
                      }
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Restablecer valores por defecto'),
                  ),
                ),
              ],
            ),
    );
  }
}
