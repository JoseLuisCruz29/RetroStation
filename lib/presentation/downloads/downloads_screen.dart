import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../download_manager/download_manager.dart';
import '../widgets/empty_state.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(downloadsProvider).values.toList()
      ..sort((a, b) {
        if (a.phase.isActive != b.phase.isActive) return a.phase.isActive ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.download_rounded,
              title: 'Sin descargas',
              message: 'Los juegos que descargues desde Descubrir aparecerán aquí con su progreso.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _DownloadCard(entry: entries[i]),
            ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manager = ref.read(downloadManagerProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final e = entry;

    final detail = <String>[
      if (e.totalBytes != null)
        '${formatBytes(e.receivedBytes ?? 0)} de ${formatBytes(e.totalBytes!)}'
      else if (e.phase == DownloadPhase.running)
        '${(e.progress * 100).toStringAsFixed(0)} %',
      if (e.speedMBs != null) '${formatBytes((e.speedMBs! * 1024 * 1024).round())}/s',
      if (e.remaining != null) 'quedan ${_eta(e.remaining!)}',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text(e.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                ]),
              ),
              ..._actions(context, manager),
            ]),
            const SizedBox(height: 8),
            if (e.phase.isActive)
              LinearProgressIndicator(
                value: e.phase == DownloadPhase.queued || e.phase == DownloadPhase.verifying ? null : e.progress,
                borderRadius: BorderRadius.circular(4),
              ),
            const SizedBox(height: 6),
            Text(
              [
                e.phase.label,
                if (detail.isNotEmpty) detail,
                if (e.phase == DownloadPhase.paused && !e.canResume) 'el servidor no admite reanudar: se reiniciará',
              ].join(' · '),
              style: muted,
            ),
            if (e.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(e.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, DownloadController m) {
    final e = entry;
    IconButton btn(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon), onPressed: onTap);
    return switch (e.phase) {
      DownloadPhase.running => [
          btn(Icons.pause_rounded, 'Pausar', () => m.pause(e.taskId)),
          btn(Icons.close_rounded, 'Cancelar', () => m.cancel(e.taskId)),
        ],
      DownloadPhase.paused => [
          btn(Icons.play_arrow_rounded, 'Reanudar', () => m.resume(e.taskId)),
          btn(Icons.close_rounded, 'Cancelar', () => m.cancel(e.taskId)),
        ],
      DownloadPhase.queued => [btn(Icons.close_rounded, 'Cancelar', () => m.cancel(e.taskId))],
      DownloadPhase.verifying => const [],
      DownloadPhase.completed => [
          btn(Icons.sports_esports_rounded, 'Abrir juego', () => context.push(Routes.game(e.gameId))),
          btn(Icons.delete_sweep_outlined, 'Quitar de la lista', () => m.remove(e.taskId)),
        ],
      DownloadPhase.failed || DownloadPhase.canceled => [
          btn(Icons.refresh_rounded, 'Reintentar', () => m.retry(e.taskId)),
          btn(Icons.delete_sweep_outlined, 'Quitar de la lista', () => m.remove(e.taskId)),
        ],
    };
  }

  static String _eta(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    return '${d.inSeconds} s';
  }
}
