import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../engines/console_registry.dart';
import '../../save_manager/save_state_repository.dart';
import '../widgets/empty_state.dart';

class SavesScreen extends ConsumerWidget {
  const SavesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(saveStatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas guardadas')),
      body: states.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error al leer las partidas: $e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.save_outlined,
                title: 'No hay save states',
                message:
                    'Cuando guardes un estado desde el menú rápido del juego, '
                    'aparecerá aquí con su captura, fecha y ranura.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _SaveStateTile(list[i]),
              ),
      ),
    );
  }
}

class _SaveStateTile extends ConsumerWidget {
  const _SaveStateTile(this.item);

  final SaveStateWithGame item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thumb = item.state.thumbnailPath;
    final console = ConsoleRegistry.byId(item.game.consoleId);
    return Card(
      child: ListTile(
        onTap: () => context.push(Routes.player(item.game.id, slot: item.state.slot)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 48,
            child: thumb != null && File(thumb).existsSync()
                ? Image.file(File(thumb), fit: BoxFit.cover, filterQuality: FilterQuality.none)
                : ColoredBox(
                    color: (console?.color ?? theme.colorScheme.primary)
                        .withValues(alpha: 0.2),
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
          ),
        ),
        title: Text(item.game.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Ranura ${item.state.slot} · ${formatDateTime(item.state.createdAt)}',
        ),
        trailing: IconButton(
          tooltip: 'Eliminar',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar save state'),
        content: Text(
          '¿Eliminar la ranura ${item.state.slot} de "${item.game.title}"? '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(saveStateRepositoryProvider).delete(item.state);
    }
  }
}
