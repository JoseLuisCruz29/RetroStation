import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../controllers/touch_layout.dart';
import '../../settings/app_settings.dart';
import '../player/touch_controls.dart';

/// Editor de controles táctiles: arrastra cada botón para moverlo y ajusta
/// su tamaño. Hay un diseño para vertical y otro para horizontal.
class ControlsEditorScreen extends ConsumerStatefulWidget {
  const ControlsEditorScreen({super.key});

  @override
  ConsumerState<ControlsEditorScreen> createState() => _ControlsEditorScreenState();
}

class _ControlsEditorScreenState extends ConsumerState<ControlsEditorScreen> {
  bool _landscape = false;

  /// Distribución que se edita: 'gba' (GBA/GB/GBC/NES), 'snes' (SNES, PS1
  /// y DS: botones en rombo) o 'psp' (con joystick).
  String _console = 'gba';

  String _key(String id) => TouchLayout.overrideKey(_console, id);
  late Map<String, ControlOverride> _portrait;
  late Map<String, ControlOverride> _landscapeLayout;
  String? _selected;
  bool _dirty = false;

  // Áreas de referencia (dp) iguales a las del reproductor en un teléfono típico.
  static const _portraitArea = Size(360, 420);
  static const _landscapeArea = Size(800, 360);

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _portrait = {...s.layoutPortrait};
    _landscapeLayout = {...s.layoutLandscape};
  }

  Map<String, ControlOverride> get _current => _landscape ? _landscapeLayout : _portrait;
  Size get _area => _landscape ? _landscapeArea : _portraitArea;

  List<ControlRegion> _regions() {
    final settings = ref.read(settingsProvider);
    return TouchLayout.customize(
      TouchLayout.forConsole(_console, _area, landscape: _landscape, scale: settings.controlsScale),
      _area,
      _current,
      consoleId: _console,
    );
  }

  void _update(String id, ControlOverride Function(ControlOverride) f) {
    final key = _key(id);
    setState(() {
      _current[key] = f(_current[key] ?? const ControlOverride());
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final c = ref.read(settingsProvider.notifier);
    await c.update(ref.read(settingsProvider).copyWith(
          layoutPortrait: {..._portrait},
          layoutLandscape: {..._landscapeLayout},
        ));
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diseño de controles guardado')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final selected =
        _selected == null ? null : _current[_key(_selected!)] ?? const ControlOverride();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor de controles'),
        actions: [
          TextButton(onPressed: _dirty ? _save : null, child: const Text('Guardar')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Vertical'), icon: Icon(Icons.stay_current_portrait)),
                ButtonSegment(value: true, label: Text('Horizontal'), icon: Icon(Icons.stay_current_landscape)),
              ],
              selected: {_landscape},
              onSelectionChanged: (s) => setState(() {
                _landscape = s.first;
                _selected = null;
              }),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gba', label: Text('GBA · NES')),
                ButtonSegment(value: 'snes', label: Text('SNES · PS1 · DS')),
                ButtonSegment(value: 'psp', label: Text('PSP')),
              ],
              selected: {_console},
              onSelectionChanged: (s) => setState(() {
                _console = s.first;
                _selected = null;
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text('Toca un control para elegirlo y arrástralo para moverlo.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: _area,
                  child: _EditableArea(
                    regions: _regions(),
                    landscape: _landscape,
                    selectedId: _selected,
                    opacity: settings.controlsOpacity,
                    onSelect: (id) => setState(() => _selected = id),
                    onDrag: (id, delta) => _update(
                      id,
                      (o) => o.copyWith(
                        dx: (o.dx + delta.dx / _area.width).clamp(-1, 1),
                        dy: (o.dy + delta.dy / _area.height).clamp(-1, 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selected != null)
            ListTile(
              title: Text('Tamaño de ${_selected!.toUpperCase()}'),
              subtitle: Slider(
                value: selected.scale,
                min: 0.5,
                max: 2,
                divisions: 30,
                label: '${(selected.scale * 100).round()} %',
                onChanged: (v) => _update(_selected!, (o) => o.copyWith(scale: v)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _selected == null
                      ? null
                      : () => setState(() {
                            _current.remove(_key(_selected!));
                            _dirty = true;
                          }),
                  child: const Text('Restablecer este'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _current.isEmpty
                      ? null
                      : () => setState(() {
                            _current.clear();
                            _selected = null;
                            _dirty = true;
                          }),
                  child: const Text('Restablecer todo'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _EditableArea extends StatefulWidget {
  const _EditableArea({
    required this.regions,
    required this.landscape,
    required this.selectedId,
    required this.opacity,
    required this.onSelect,
    required this.onDrag,
  });

  final List<ControlRegion> regions;
  final bool landscape;
  final String? selectedId;
  final double opacity;
  final ValueChanged<String?> onSelect;
  final void Function(String id, Offset delta) onDrag;

  @override
  State<_EditableArea> createState() => _EditableAreaState();
}

class _EditableAreaState extends State<_EditableArea> {
  String? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onPanDown: (d) {
        final hit = widget.regions
            .where((r) => r.rect.inflate(8).contains(d.localPosition))
            .map((r) => r.id)
            .firstOrNull;
        _dragging = hit;
        widget.onSelect(hit);
      },
      onPanUpdate: (d) {
        if (_dragging != null) widget.onDrag(_dragging!, d.delta);
      },
      onPanEnd: (_) => _dragging = null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(children: [
          // Zona de la imagen del juego como referencia (horizontal).
          if (widget.landscape)
            Positioned.fromRect(
              rect: Rect.fromLTRB(
                TouchLayout.defaultGutter(const Size(800, 360)),
                0,
                800 - TouchLayout.defaultGutter(const Size(800, 360)),
                360,
              ),
              child: ColoredBox(
                color: Colors.white10,
                child: Center(child: Text('Imagen del juego', style: theme.textTheme.bodySmall)),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: ControlsPainter(
                regions: widget.regions,
                mask: 0,
                opacity: widget.opacity,
                accent: theme.colorScheme.primary,
                selectedId: widget.selectedId,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
