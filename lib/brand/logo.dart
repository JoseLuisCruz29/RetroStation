import 'package:material_ui/material_ui.dart';

/// Colores de la marca RetroStation. Los del logo (azul pizarra y gris de los
/// contornos) se toman del diseño del autor; violeta y azul siguen siendo los
/// acentos de la interfaz.
abstract final class BrandColors {
  static const violet = Color(0xFF8B5CF6);
  static const blue = Color(0xFF3B82F6);

  /// Azul pizarra del mando del logo y del nombre.
  static const slate = Color(0xFF5E92A8);
  static const slateLight = Color(0xFF9CC3D3);

  /// Fondo de la pantalla de carga.
  static const ink = Color(0xFF0B0A14);

  /// Fondo claro de la loseta del logo (igual que el icono de la app).
  static const tile = Color(0xFFF3F5F6);

  /// Texto del logotipo sobre fondos claros.
  static const inkText = Color(0xFF2F4B5C);
}

/// Tipografía pixel de toda la interfaz (Pixelify Sans, licencia OFL).
const brandFont = 'PixelifySans';

/// Logo de RetroStation (tren sobre un mando, diseño del autor).
///
/// Sin [color], se muestra a todo color sobre una loseta clara redondeada,
/// que se lee igual en fondos oscuros y claros. Con [color], es la silueta
/// del símbolo en ese color (marcas de agua, estados vacíos).
///
/// Los PNG se generan con `tool/make_brand_assets.py`.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'RetroStation',
        image: true,
        child: color == null
            ? Image.asset(
                'assets/brand/logo_tile.png',
                width: size,
                height: size,
                filterQuality: FilterQuality.medium,
              )
            : Image.asset(
                'assets/brand/logo_symbol_white.png',
                width: size,
                height: size,
                color: color,
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.medium,
              ),
      );
}

/// Logotipo completo: símbolo + nombre. Se adapta a fondos oscuros y claros
/// según el brillo del tema (o el que se indique con [onLight]).
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 32, this.onLight, this.showSymbol = true});

  final double height;
  final bool? onLight;
  final bool showSymbol;

  @override
  Widget build(BuildContext context) {
    final light = onLight ?? Theme.of(context).brightness == Brightness.light;
    final style = TextStyle(
      fontFamily: brandFont,
      fontSize: height * 0.72,
      height: 1,
      letterSpacing: -0.02 * height,
      color: light ? BrandColors.inkText : Colors.white,
    );
    return Semantics(
      label: 'RetroStation',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSymbol) ...[
              LogoMark(size: height * 1.15),
              SizedBox(width: height * 0.3),
            ],
            Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Retro', style: style.copyWith(fontWeight: FontWeight.w800)),
                TextSpan(
                  text: 'Station',
                  style: style.copyWith(
                    fontWeight: FontWeight.w500,
                    color: light ? BrandColors.slate : BrandColors.slateLight,
                  ),
                ),
              ]),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
