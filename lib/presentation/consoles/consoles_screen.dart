import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../engines/core_options.dart';
import '../widgets/console_card.dart';
import '../widgets/status_chip.dart';

class ConsolesScreen extends StatelessWidget {
  const ConsolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consolas')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: ConsoleRegistry.all.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ConsoleTile(ConsoleRegistry.all[i]),
      ),
    );
  }
}

class _ConsoleTile extends StatelessWidget {
  const _ConsoleTile(this.console);

  final ConsoleDescriptor console;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: InkWell(
        onTap: () => context.go(Routes.libraryForConsole(console.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ConsoleMonogram(console: console, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(console.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${console.manufacturer} · ${console.releaseYear}',
                        style: muted),
                    const SizedBox(height: 2),
                    Text(
                      'Núcleo: ${console.activeCore.name} (${console.activeCore.license})',
                      style: muted,
                    ),
                    Text(
                      'Archivos: ${console.extensions.map((e) => '.$e').join(', ')}',
                      style: muted,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CoreStatusChip(console.status),
                        if (console.status == CoreStatus.planned)
                          Text('Etapa ${console.plannedStage}', style: muted),
                      ],
                    ),
                    if (console.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(console.note!, style: muted),
                      ),
                  ],
                ),
              ),
              if (CoreOptions.forConsole(console.id).isNotEmpty &&
                  console.status == CoreStatus.available)
                IconButton(
                  tooltip: 'Ajustes de ${console.shortName}',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => context.push(Routes.consoleSettings(console.id)),
                )
              else
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
