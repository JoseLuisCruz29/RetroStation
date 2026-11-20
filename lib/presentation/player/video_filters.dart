import 'package:material_ui/material_ui.dart';

import '../../settings/app_settings.dart';

/// Textura del juego con el filtro elegido. Los filtros son baratos: el
/// escalado lo hace la GPU y las líneas/rejilla son un CustomPaint encima.
class FilteredGameTexture extends StatelessWidget {
  const FilteredGameTexture({
    super.key,
    required this.textureId,
    required this.filter,
    required this.sourceHeight,
  });

  final int textureId;
  final VideoFilter filter;

  /// Líneas de la imagen original (160 en GBA): define el tamaño de la trama.
  final int sourceHeight;

  @override
  Widget build(BuildContext context) {
    final texture = Texture(
      textureId: textureId,
      filterQuality: filter == VideoFilter.smooth ? FilterQuality.medium : FilterQuality.none,
    );
    if (filter == VideoFilter.sharp || filter == VideoFilter.smooth) return texture;
    return Stack(
      fit: StackFit.expand,
      children: [
        texture,
        IgnorePointer(
          child: CustomPaint(
            painter: _OverlayPainter(
              lcd: filter == VideoFilter.lcd,
              sourceHeight: sourceHeight,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.lcd, required this.sourceHeight});

  final bool lcd;
  final int sourceHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final pixel = size.height / sourceHeight;
    if (pixel < 2) return; // demasiado pequeño para que la trama se aprecie
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: lcd ? 0.22 : 0.35)
      ..strokeWidth = (pixel * (lcd ? 0.15 : 0.35)).clamp(1, 4);
    for (var y = pixel; y < size.height; y += pixel) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (lcd) {
      for (var x = pixel; x < size.width; x += pixel) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.lcd != lcd || old.sourceHeight != sourceHeight;
}
