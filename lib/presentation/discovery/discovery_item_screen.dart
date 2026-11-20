import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../discovery/discovery_library.dart';
import '../../discovery/discovery_models.dart';
import '../../discovery/discovery_service.dart';
import '../../download_manager/download_manager.dart';
import '../../engines/console_registry.dart';
import 'source_browser_screen.dart';

/// Ficha de un resultado de Descubrir: procedencia, licencia, capturas y
/// acciones (descargar si la fuente lo permite, o abrir la página original).
class DiscoveryItemScreen extends ConsumerStatefulWidget {
  const DiscoveryItemScreen({super.key, required this.item});

  final DiscoveryItem item;

  @override
  ConsumerState<DiscoveryItemScreen> createState() => _DiscoveryItemScreenState();
}

class _DiscoveryItemScreenState extends ConsumerState<DiscoveryItemScreen> {
  bool _busy = false;

  DiscoveryItem get item => widget.item;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openPage() async {
    final ok = await launchUrl(item.pageUrl, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('No se pudo abrir ${item.pageUrl}');
  }

  Future<bool> _confirmUnknownLicense() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
        title: const Text('Licencia no indicada'),
        content: const Text(
          'El autor no ha declarado una licencia para este juego. Homebrew Hub lo '
          'distribuye públicamente como homebrew, pero no hay una autorización '
          'expresa de redistribución registrada en la ficha.\n\n'
          'El archivo se comprobará (cabecera y tamaño) antes de añadirlo a la biblioteca.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descargar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _download() async {
    if (item.license == null && !await _confirmUnknownLicense()) return;
    setState(() => _busy = true);
    try {
      final gameId = await ref.read(discoveryLibraryProvider).savePending(item);
      await ref.read(downloadManagerProvider).enqueueForGame(gameId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        // Con acción, Flutter lo deja fijo por defecto (persist): se cierra solo.
        persist: false,
        duration: const Duration(seconds: 4),
        content: Text('Descargando "${item.title}"'),
        action: SnackBarAction(label: 'Ver', onPressed: () => context.push(Routes.downloads)),
      ));
    } catch (e) {
      if (mounted) _snack('No se pudo iniciar la descarga: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Abre la página original en el navegador integrado. El juego se guarda
  /// antes como pendiente para que la descarga tenga dónde quedar.
  Future<void> _downloadFromPage() async {
    setState(() => _busy = true);
    try {
      final gameId = await ref.read(discoveryLibraryProvider).savePending(item);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SourceBrowserScreen(gameId: gameId, title: item.title, url: item.pageUrl),
      ));
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePending() async {
    setState(() => _busy = true);
    try {
      await ref.read(discoveryLibraryProvider).savePending(item);
      if (mounted) _snack('Guardado en Biblioteca > Pendientes');
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final source = ref
        .watch(sourceAdaptersProvider)
        .where((s) => s.id == item.sourceId)
        .firstOrNull;
    final console = item.consoleId == null ? null : ConsoleRegistry.byId(item.consoleId!);
    final downloadable = item.availability == Availability.downloadable && item.primaryFile != null;

    return Scaffold(
      appBar: AppBar(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (item.screenshotUrls.isNotEmpty || item.coverUrl != null)
            SizedBox(
              height: 200,
              child: PageView(
                children: [
                  for (final url in item.screenshotUrls.isEmpty ? [item.coverUrl!] : item.screenshotUrls)
                    Image.network(
                      url.toString(),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.developers.isNotEmpty) item.developers.join(', '),
                    if (item.year != null) '${item.year}',
                    console?.name ?? item.platformLabel ?? '',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: muted,
                ),
                const SizedBox(height: 12),
                _InfoBox(
                  icon: Icons.source_rounded,
                  title: 'Procedencia: ${source?.name ?? item.sourceId}',
                  body: item.pageUrl.toString(),
                ),
                const SizedBox(height: 8),
                if (downloadable)
                  _InfoBox(
                    icon: item.license == null ? Icons.warning_amber_rounded : Icons.gavel_rounded,
                    title: item.license == null ? 'Licencia no indicada por el autor' : 'Licencia',
                    body: item.license ??
                        'Distribuido públicamente por Homebrew Hub como homebrew. '
                            'Se pedirá confirmación antes de descargar.',
                    color: item.license == null ? Colors.amberAccent : null,
                  )
                else
                  _InfoBox(
                    icon: Icons.public_rounded,
                    title: 'Se descarga desde su página',
                    body: 'La web de ${source?.name ?? 'la fuente'} entrega el archivo: se abre aquí '
                        'dentro y pulsas su botón de descarga (si pide pagar o aceptar, se hace ahí). '
                        'RetroStation recoge el archivo y lo valida. Algunos resultados de itch.io '
                        'son juegos de PC de estilo retro: esos se rechazan al validar.',
                  ),
                if (item.commercial) ...[
                  const SizedBox(height: 8),
                  _InfoBox(
                    icon: Icons.sell_outlined,
                    title: 'Juego comercial',
                    body: item.price != null
                        ? 'Precio en la tienda: ${item.price}.'
                        : 'La versión completa es de pago; lo descargable aquí es la versión gratuita o demo que publica el autor.',
                  ),
                ],
                const SizedBox(height: 16),
                if (console == null)
                  Text('${item.platformLabel ?? 'Esta plataforma'} no está soportada por RetroStation.',
                      style: muted)
                else if (downloadable) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _download,
                      icon: const Icon(Icons.download_rounded),
                      label: Text('Descargar ${item.primaryFile!.fileName.split('/').last}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _savePending,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Guardar en Pendientes'),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _downloadFromPage,
                      icon: const Icon(Icons.download_rounded),
                      label: Text('Descargar desde ${source?.name ?? 'su página'}'),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openPage,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir en el navegador'),
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Descripción', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(item.description!),
                ],
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in item.tags) Chip(label: Text(t))]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.title, required this.body, this.color});

  final IconData icon;
  final String title;
  final String body;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            SelectableText(body, style: theme.textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
