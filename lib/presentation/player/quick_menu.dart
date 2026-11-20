import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../save_manager/save_state_service.dart';
import '../../storage/database.dart';

sealed class QuickMenuResult {
  const QuickMenuResult();
}

class SaveSlot extends QuickMenuResult {
  const SaveSlot(this.slot);
  final int slot;
}

class LoadSlot extends QuickMenuResult {
  const LoadSlot(this.slot);
  final int slot;
}

class ResetGame extends QuickMenuResult {
  const ResetGame();
}

class ExitGame extends QuickMenuResult {
  const ExitGame();
}

/// Menú rápido (el juego queda en pausa mientras está abierto).
class QuickMenu extends ConsumerWidget {
  const QuickMenu({super.key, required this.game, required this.supportsStates, this.allowReset = true});

  final Game game;
  final bool supportsStates;
  final bool allowReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final states = ref.watch(gameSaveStatesProvider(game.id)).value ?? const [];
    final bySlot = {for (final s in states) s.slot: s};

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(game.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (supportsStates) ...[
              Text('Save states', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
                children: [
                  for (var slot = 1; slot <= SaveStateService.slotCount; slot++)
                    _SlotCard(slot: slot, entry: bySlot[slot]),
                ],
              ),
            ] else
              Text(
                'Este núcleo no admite save states.',
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 8),
            if (allowReset)
              ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Reiniciar juego'),
              subtitle: const Text('La partida guardada del cartucho no se borra'),
              onTap: () => Navigator.pop(context, const ResetGame()),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Salir del juego'),
              subtitle: const Text('Se guarda la partida del cartucho'),
              onTap: () => Navigator.pop(context, const ExitGame()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.entry});

  final int slot;
  final SaveStateEntry? entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = entry?.thumbnailPath;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: thumb != null && File(thumb).existsSync()
                ? Image.file(File(thumb), fit: BoxFit.cover, filterQuality: FilterQuality.none)
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(child: Text('Vacía', style: theme.textTheme.bodySmall)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Text(
              entry == null ? 'Ranura $slot' : '$slot · ${formatDateTime(entry!.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => Navigator.pop(context, SaveSlot(slot)),
                  child: const Text('Guardar'),
                ),
              ),
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: entry == null ? null : () => Navigator.pop(context, LoadSlot(slot)),
                  child: const Text('Cargar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
