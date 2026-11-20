import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/ui_sound.dart';
import '../../brand/logo.dart';
import '../../brand/retro.dart';

/// Zonas de la app que el tutorial resalta. Cada pantalla pone la clave en
/// su elemento; si no está montado, el paso se muestra sin resaltar nada.
abstract final class TutorialTargets {
  static final quickAccess = GlobalKey(debugLabel: 'tutorial-quick-access');
  static final importButton = GlobalKey(debugLabel: 'tutorial-import');
  static final library = GlobalKey(debugLabel: 'tutorial-library');
  static final navigation = GlobalKey(debugLabel: 'tutorial-navigation');
}

class _Step {
  const _Step({
    required this.tab,
    required this.icon,
    required this.title,
    required this.body,
    this.highlightTab = false,
  });

  /// Pestaña que se muestra en este paso (índice de la barra de navegación).
  final int tab;
  final IconData icon;
  final String title;
  final String body;

  /// Resaltar el botón de la pestaña en la barra de navegación.
  final bool highlightTab;
}

const _steps = [
  _Step(
    tab: 0,
    icon: Icons.waving_hand_rounded,
    title: 'Bienvenido a RetroStation',
    body: 'Tu centro de juegos retro, creado por Jose Cruz. Te enseño en un minuto '
        'cómo añadir juegos, jugar y guardar tu partida. Puedes saltarte el tutorial '
        'cuando quieras.',
  ),
  _Step(
    tab: 0,
    icon: Icons.home_rounded,
    title: 'Inicio',
    body: 'Aquí retomas tu último juego con «Continuar» y tienes accesos directos a '
        'tus juegos, tus partidas guardadas, las descargas y las consolas.',
  ),
  _Step(
    tab: 1,
    icon: Icons.add_rounded,
    title: 'Añade tus juegos',
    body: 'En «Mis juegos» está toda tu biblioteca. Con «Importar» eliges ROMs o '
        'archivos ZIP del teléfono; la app los comprueba y busca su portada.',
  ),
  _Step(
    tab: 1,
    icon: Icons.play_arrow_rounded,
    title: 'Cómo jugar',
    body: 'Toca un juego para ver su ficha y pulsa «Jugar». En el juego usas los '
        'controles de la pantalla: con ☰ guardas o cargas la partida, ⏩ acelera, '
        '⏸ pausa y ← sale del juego.',
  ),
  _Step(
    tab: 0,
    icon: Icons.wifi_tethering_rounded,
    title: '¡Nuevo! Multijugador LAN',
    body: 'Juega con un amigo, cada uno en su teléfono o en el PC, en la misma Wi-Fi. '
        'Toca «Multijugador» en Inicio, elige tu nombre y pulsa «Conectar» en tu amigo. '
        'Quien acepta elige el juego: cooperativo en NES, SNES y PS1, o cable link de GBA '
        '(Kirby, Pokémon...) con cada uno en su consola.',
  ),
  _Step(
    tab: 3,
    icon: Icons.memory_rounded,
    title: 'Consolas',
    body: 'Cada consola con su emulador. Con el icono de ajustes de una consola '
        'cambias sus opciones, como saltar fotogramas si un juego va lento.',
    highlightTab: true,
  ),
  _Step(
    tab: 2,
    icon: Icons.travel_explore_rounded,
    title: 'Descubrir',
    body: 'Busca y descarga juegos de libre distribución hechos por aficionados, '
        'listos para jugar.',
    highlightTab: true,
  ),
  _Step(
    tab: 4,
    icon: Icons.settings_rounded,
    title: 'Ajustes',
    body: 'Apariencia, sonido, controles táctiles y copias de seguridad de tus '
        'partidas. Desde aquí también puedes volver a ver este tutorial.',
    highlightTab: true,
  ),
  _Step(
    tab: 0,
    icon: Icons.sports_esports_rounded,
    title: '¡Listo para jugar!',
    body: 'Ya conoces lo básico. Importa tus juegos y que empiece la partida.',
  ),
];

/// Objetivo de cada paso (las GlobalKey no pueden ir en una lista const).
GlobalKey? _targetOf(int step) => switch (step) {
      1 => TutorialTargets.quickAccess,
      2 => TutorialTargets.importButton,
      3 => TutorialTargets.library,
      4 => TutorialTargets.quickAccess,
      _ => _steps[step].highlightTab ? TutorialTargets.navigation : null,
    };

/// Tutorial guiado sobre la propia app: cambia de pestaña en cada paso,
/// oscurece el resto y resalta la zona de la que habla.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.shell,
    required this.onFinish,
    required this.railMode,
  });

  final StatefulNavigationShell shell;

  /// Al terminar o saltar el tutorial (se guarda que ya se vio).
  final VoidCallback onFinish;

  /// Navegación lateral (horizontal/tablet) en vez de barra inferior.
  final bool railMode;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;
  Rect? _hole;
  Size? _lastSize;
  Timer? _measureTimer;

  static const tabCount = 5;

  @override
  void initState() {
    super.initState();
    _goTo(0, sound: false);
  }

  @override
  void dispose() {
    _measureTimer?.cancel();
    super.dispose();
  }

  void _goTo(int step, {bool sound = true}) {
    if (sound) UiSound.play(step > _step ? Sfx.open : Sfx.back);
    setState(() {
      _step = step;
      _hole = null;
    });
    final tab = _steps[step].tab;
    if (widget.shell.currentIndex != tab) widget.shell.goBranch(tab);
    _scheduleMeasure();
  }

  /// Mide la zona a resaltar cuando la pestaña ya se ha dibujado.
  void _scheduleMeasure() {
    _measureTimer?.cancel();
    _measureTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _hole = _measure());
    });
  }

  Rect? _measure() {
    final key = _targetOf(_step);
    final overlay = context.findRenderObject() as RenderBox?;
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize || !box.attached) return null;
    var rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    if (key == TutorialTargets.navigation && !widget.railMode) {
      // Solo el botón de la pestaña de este paso.
      final w = rect.width / tabCount;
      rect = Rect.fromLTWH(rect.left + w * _steps[_step].tab, rect.top, w, rect.height);
    }
    return rect.inflate(6).intersect(Offset.zero & overlay.size);
  }

  void _finish() {
    UiSound.play(_step == _steps.length - 1 ? Sfx.on : Sfx.back);
    if (widget.shell.currentIndex != 0) widget.shell.goBranch(0);
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_step];
    final last = _step == _steps.length - 1;
    return LayoutBuilder(builder: (context, box) {
      // Al girar la pantalla, la zona resaltada cambia de sitio.
      if (_lastSize != box.biggest) {
        _lastSize = box.biggest;
        if (_hole != null) _scheduleMeasure();
      }
      final hole = _hole;
      final cardAtTop = hole != null && hole.center.dy > box.maxHeight * 0.55;
      return Stack(
        children: [
          // Bloquea los toques sobre la app mientras dura el tutorial.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              // Sin zona que resaltar (bienvenida, final) solo se oscurece;
              // TweenAnimationBuilder no admite un destino nulo.
              child: hole == null
                  ? CustomPaint(painter: _HolePainter(null, theme.colorScheme.primary))
                  : TweenAnimationBuilder<Rect?>(
                      tween: RectTween(end: hole),
                      duration: const Duration(milliseconds: 220),
                      builder: (context, r, _) => CustomPaint(
                        painter: _HolePainter(r, theme.colorScheme.primary),
                      ),
                    ),
            ),
          ),
          Align(
            alignment: cardAtTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: RetroPanel(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_step == 0)
                              const LogoMark(size: 34)
                            else
                              Icon(step.icon, color: theme.colorScheme.primary, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(step.title.toUpperCase(),
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: theme.colorScheme.primary)),
                            ),
                            Text('${_step + 1}/${_steps.length}',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(step.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                        const SizedBox(height: 12),
                        _Dots(count: _steps.length, active: _step),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!last)
                              TextButton(onPressed: _finish, child: const Text('Saltar tutorial')),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_step > 0) ...[
                                  OutlinedButton(
                                    onPressed: () => _goTo(_step - 1),
                                    child: const Text('Atrás'),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                FilledButton(
                                  onPressed: last ? _finish : () => _goTo(_step + 1),
                                  child: Text(last ? '¡A jugar!' : 'Siguiente'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Puntos de progreso cuadrados (estilo pixel).
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == active ? 18 : 8,
            height: 8,
            margin: const EdgeInsets.only(right: 5),
            color: i <= active ? accent : RetroPalette.line.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

/// Oscurece la pantalla salvo un hueco con marco del color del cursor.
class _HolePainter extends CustomPainter {
  _HolePainter(this.hole, this.accent);

  final Rect? hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xC7050A0E);
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, dim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(h, const Radius.circular(12));
    canvas.drawPath(Path.combine(PathOperation.difference, all, Path()..addRRect(rrect)), dim);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent,
    );
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = accent.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.accent != accent;
}
