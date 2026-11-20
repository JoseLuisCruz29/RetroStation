import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../download_manager/download_manager.dart';

/// Navegador integrado que abre la página original de un juego (p. ej. itch.io).
///
/// La descarga la inicia el usuario con el botón de la propia web: si la
/// fuente pide aceptar condiciones, pagar o iniciar sesión, se hace ahí, igual
/// que en un navegador normal. RetroStation solo recoge el archivo que la web
/// entrega, lo pasa al gestor de descargas y lo valida antes de añadirlo.
class SourceBrowserScreen extends ConsumerStatefulWidget {
  const SourceBrowserScreen({
    super.key,
    required this.gameId,
    required this.title,
    required this.url,
  });

  final int gameId;
  final String title;
  final Uri url;

  @override
  ConsumerState<SourceBrowserScreen> createState() => _SourceBrowserScreenState();
}

class _SourceBrowserScreenState extends ConsumerState<SourceBrowserScreen> {
  InAppWebViewController? _web;
  double _progress = 0;
  String? _host;
  bool _handling = false;

  static String _size(int bytes) {
    if (bytes <= 0) return 'tamaño desconocido';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _onDownload(DownloadStartRequest request) async {
    if (_handling) return;
    final url = Uri.tryParse(request.url.toString());
    if (url == null || (url.scheme != 'https' && url.scheme != 'http')) {
      _snack('Esta página entrega el archivo de una forma que la app no puede recoger '
          '(${request.url.scheme}). Usa "Abrir en el navegador".');
      return;
    }
    _handling = true;
    try {
      final name = request.suggestedFilename ??
          (url.pathSegments.isEmpty ? 'descarga' : Uri.decodeComponent(url.pathSegments.last));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.download_rounded),
          title: const Text('Descargar a RetroStation'),
          content: Text(
            '$name · ${_size(request.contentLength)}\n\n'
            'Se comprobará el archivo (cabecera y, si es un ZIP, su contenido). '
            'Si no es un juego de una consola compatible, se descartará.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descargar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      // Algunas webs exigen la misma sesión que la página: se pasan sus cookies
      // y el agente de usuario del navegador integrado.
      final cookies = await CookieManager.instance().getCookies(url: request.url);
      final userAgent = request.userAgent;
      await ref.read(downloadManagerProvider).enqueueUrlForGame(
        widget.gameId,
        url,
        fileName: name,
        headers: {
          if (cookies.isNotEmpty) 'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
          'User-Agent': ?userAgent,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        persist: false,
        duration: const Duration(seconds: 4),
        content: Text('Descargando "$name"'),
        action: SnackBarAction(label: 'Ver', onPressed: () => context.push(Routes.downloads)),
      ));
    } catch (e) {
      _snack('No se pudo iniciar la descarga: $e');
    } finally {
      _handling = false;
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // "Atrás" navega dentro de la web antes de cerrar el navegador.
        if (await _web?.canGoBack() ?? false) {
          await _web!.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_host ?? widget.url.host, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _web?.reload(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _progress < 1
                ? LinearProgressIndicator(value: _progress, minHeight: 3)
                : const SizedBox(height: 3),
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              child: Text(
                'Pulsa el botón de descarga de la página. Si pide pagar o iniciar '
                'sesión, se hace aquí mismo, igual que en el navegador.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri.uri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  useOnDownloadStart: true,
                  javaScriptEnabled: true,
                  supportMultipleWindows: false,
                  mediaPlaybackRequiresUserGesture: true,
                ),
                onWebViewCreated: (c) => _web = c,
                onProgressChanged: (_, p) => setState(() => _progress = p / 100),
                onLoadStop: (_, url) => setState(() => _host = url?.host),
                onDownloadStartRequest: (_, request) => _onDownload(request),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
