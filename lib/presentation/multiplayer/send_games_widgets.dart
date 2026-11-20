part of 'multiplayer_screen.dart';

/// Pregunta al recibir una oferta de juegos.
class _OfferDialog extends StatelessWidget {
  const _OfferDialog({required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = offer.games.take(6).toList();
    final count = offer.games.length == 1 ? 'un juego' : '${offer.games.length} juegos';
    return AlertDialog(
      icon: Icon(Icons.download_for_offline_rounded, color: theme.colorScheme.primary),
      title: const Text('Te quieren enviar juegos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${offer.peerName} quiere enviarte $count (${formatBytes(offer.total)}):'),
          const SizedBox(height: 10),
          for (final g in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Text(ConsoleRegistry.byId(g.consoleId)?.shortName ?? g.consoleId.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(width: 8),
                Expanded(child: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          if (offer.games.length > shown.length) Text('y ${offer.games.length - shown.length} más…'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rechazar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recibir')),
      ],
    );
  }
}

/// Progreso del envío o de la recepción.
class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.progress, required this.onCancel, required this.onClose});

  final TransferProgress progress;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = progress.peerName;
    final title = switch (progress.phase) {
      TransferPhase.waiting => 'Esperando a que $who acepte…',
      TransferPhase.sending => 'Enviando a $who',
      TransferPhase.receiving => 'Recibiendo de $who',
      TransferPhase.importing =>
        progress.outgoing ? '$who está guardando los juegos…' : 'Añadiendo a tu biblioteca…',
      TransferPhase.finished => progress.outgoing ? 'Envío terminado' : 'Recepción terminada',
      TransferPhase.failed => progress.outgoing ? 'No se pudo enviar' : 'No se pudo recibir',
    };
    final showBar = progress.phase == TransferPhase.sending || progress.phase == TransferPhase.receiving;
    return RetroPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              progress.outgoing ? Icons.upload_rounded : Icons.download_rounded,
              color: progress.phase == TransferPhase.failed ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            if (progress.active)
              TextButton(onPressed: onCancel, child: const Text('Cancelar'))
            else
              IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close_rounded), onPressed: onClose),
          ]),
          if (progress.active) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: showBar ? progress.fraction : null),
            if (showBar)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${formatBytes(progress.done)} de ${formatBytes(progress.total)}',
                    style: theme.textTheme.bodySmall),
              ),
          ] else if (progress.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(progress.message!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Lista de juegos instalados para elegir cuáles enviar.
class _PickGamesSheet extends ConsumerStatefulWidget {
  const _PickGamesSheet({required this.peerName});

  final String peerName;

  @override
  ConsumerState<_PickGamesSheet> createState() => _PickGamesSheetState();
}

class _PickGamesSheetState extends ConsumerState<_PickGamesSheet> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider(const LibraryFilter(category: LibraryCategory.installed)));
    final games = [
      for (final g in library.value ?? const <Game>[])
        if (g.romPath != null) g,
    ];
    final total = games.where((g) => _selected.contains(g.id)).fold<int>(0, (a, g) => a + (g.fileSize ?? 0));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Enviar juegos a ${widget.peerName}', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Envía solo juegos que tengas derecho a compartir (homebrew, o copias de tus '
                'propios juegos entre tus dispositivos).',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: library.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : games.isEmpty
                      ? const Center(child: Text('No tienes juegos instalados.'))
                      : ListView.builder(
                          itemCount: games.length,
                          itemBuilder: (ctx, i) {
                            final g = games[i];
                            final console = ConsoleRegistry.byId(g.consoleId);
                            return CheckboxListTile(
                              value: _selected.contains(g.id),
                              onChanged: (v) =>
                                  setState(() => v == true ? _selected.add(g.id) : _selected.remove(g.id)),
                              title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${console?.shortName ?? g.consoleId.toUpperCase()} · ${formatBytes(g.fileSize ?? 0)}'),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                            for (final g in games)
                              if (_selected.contains(g.id)) g,
                          ]),
                  label: Text(_selected.isEmpty
                      ? 'Elige uno o más juegos'
                      : 'Enviar ${_selected.length} (${formatBytes(total)})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
