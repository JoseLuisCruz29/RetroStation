import 'package:material_ui/material_ui.dart';

import 'logo.dart';

/// Pantalla de carga mientras se abren la base de datos y los ajustes.
/// Continúa la pantalla de carga nativa (mismo fondo y símbolo centrado) y
/// añade el nombre y un indicador de progreso.
class BootSplash extends StatelessWidget {
  const BootSplash({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: const Scaffold(
          backgroundColor: BrandColors.ink,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoMark(size: 112),
                SizedBox(height: 20),
                Wordmark(height: 26, showSymbol: false, onLight: false),
                SizedBox(height: 10),
                Text(
                  'por Jose Cruz',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 13, letterSpacing: 1.2),
                ),
                SizedBox(height: 28),
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: BrandColors.violet,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
