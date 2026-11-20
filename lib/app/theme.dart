import 'package:material_ui/material_ui.dart';

import '../brand/logo.dart';
import '../brand/retro.dart';
import '../settings/app_settings.dart';

/// Paleta de la interfaz (estilo RetroStation OS). La base está en
/// [RetroPalette]; aquí van los colores con nombre de uso.
abstract final class RetroColors {
  static const charcoal = RetroPalette.bg;
  static const charcoalSurface = RetroPalette.panel;
  static const amoled = Color(0xFF000000);
  static const amoledSurface = Color(0xFF101C24);

  static const text = RetroPalette.text;
  static const textMuted = RetroPalette.muted;
  static const outline = RetroPalette.line;

  // Colores del cursor (acento) que puede elegir el usuario.
  static const cian = Color(0xFF8FDCEF);
  static const ambar = Color(0xFFFFCF6B);
  static const verde = Color(0xFF8FF0A4);

  // Estados: se usan solo para comunicar resultado, nunca como decoración.
  static const success = Color(0xFF5ED16A);
  static const warning = Color(0xFFF2B43B);
  static const danger = Color(0xFFEF5B4C);
  static const favorite = Color(0xFFF472B6);
  static const power = RetroPalette.power;
}

/// Radios comunes, para que todas las tarjetas y controles se vean iguales.
abstract final class RetroRadii {
  static const card = 10.0;
  static const control = 8.0;
  static const sheet = 12.0;
}

Color accentOf(AccentColor a) => switch (a) {
      AccentColor.cian => RetroColors.cian,
      AccentColor.ambar => RetroColors.ambar,
      AccentColor.verde => RetroColors.verde,
    };

ThemeData buildRetroTheme(AppSettings settings) {
  final amoled = settings.background == BackgroundStyle.amoled;
  final background = amoled ? RetroColors.amoled : RetroPalette.bg;
  final surface = amoled ? RetroColors.amoledSurface : RetroPalette.panel;
  final primary = accentOf(settings.accent);
  const onAccent = Color(0xFF0B161E); // texto sobre el color del cursor
  const high = RetroPalette.panel2;
  const highest = RetroPalette.panelHi;

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: primary,
    onPrimary: onAccent,
    primaryContainer: const Color(0xFF2F6F86),
    onPrimaryContainer: RetroColors.text,
    secondary: RetroPalette.power,
    surface: surface,
    onSurface: RetroColors.text,
    surfaceContainerLowest: background,
    surfaceContainerLow: Color.lerp(background, surface, 0.5),
    surfaceContainer: surface,
    surfaceContainerHigh: high,
    surfaceContainerHighest: highest,
    onSurfaceVariant: RetroColors.textMuted,
    outline: RetroPalette.line,
    outlineVariant: RetroPalette.line.withValues(alpha: 0.5),
    error: RetroColors.danger,
  );

  final transitions = settings.reduceMotion
      ? const PageTransitionsTheme(builders: {
          TargetPlatform.android: _NoTransitionsBuilder(),
          TargetPlatform.iOS: _NoTransitionsBuilder(),
        })
      : const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        });

  // Toda la interfaz con la tipografía pixel; un poco de espaciado entre
  // letras la hace más legible.
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    fontFamily: brandFont,
  );
  final t = base.textTheme;
  TextStyle? s(TextStyle? x, FontWeight w, [double spacing = 0.4]) =>
      x?.copyWith(fontWeight: w, letterSpacing: spacing);
  final textTheme = t
      .copyWith(
        displaySmall: s(t.displaySmall, FontWeight.w700, 0.5),
        headlineLarge: s(t.headlineLarge, FontWeight.w700, 0.5),
        headlineMedium: s(t.headlineMedium, FontWeight.w700, 0.5),
        headlineSmall: s(t.headlineSmall, FontWeight.w700, 0.4),
        titleLarge: s(t.titleLarge, FontWeight.w700, 0.6),
        titleMedium: s(t.titleMedium, FontWeight.w600, 0.5),
        titleSmall: s(t.titleSmall, FontWeight.w600, 0.5),
        bodyLarge: s(t.bodyLarge, FontWeight.w400, 0.4),
        bodyMedium: s(t.bodyMedium, FontWeight.w400, 0.4),
        bodySmall: s(t.bodySmall, FontWeight.w400, 0.4),
        labelLarge: s(t.labelLarge, FontWeight.w600, 1.0),
        labelMedium: s(t.labelMedium, FontWeight.w600, 0.8),
        labelSmall: s(t.labelSmall, FontWeight.w600, 0.8),
      )
      .apply(bodyColor: RetroColors.text, displayColor: RetroColors.text);

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RetroRadii.control),
    side: const BorderSide(color: RetroPalette.line, width: 3),
  );
  RoundedRectangleBorder framed(Color color) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RetroRadii.control),
        side: BorderSide(color: color, width: 3),
      );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
  const buttonSize = Size(64, 46);

  return base.copyWith(
    scaffoldBackgroundColor: background,
    canvasColor: background,
    pageTransitionsTheme: transitions,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22, color: primary),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RetroRadii.card),
        side: const BorderSide(color: RetroPalette.line, width: 3),
      ),
    ),
    // Botones con el marco de 3 px de los menús de consola.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2F6F86),
        foregroundColor: RetroColors.text,
        disabledBackgroundColor: RetroPalette.panel,
        shape: framed(primary),
        padding: buttonPadding,
        minimumSize: buttonSize,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: RetroPalette.panelHi,
        foregroundColor: RetroColors.text,
        shape: controlShape,
        side: const BorderSide(color: RetroPalette.line, width: 3),
        padding: buttonPadding,
        minimumSize: buttonSize,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RetroRadii.control)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: const Color(0xFF2F6F86),
      foregroundColor: RetroColors.text,
      elevation: 0,
      highlightElevation: 0,
      shape: framed(primary),
      extendedTextStyle: textTheme.labelLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RetroPalette.panel,
      indicatorColor: primary.withValues(alpha: 0.16),
      indicatorShape: framed(primary),
      surfaceTintColor: Colors.transparent,
      height: 70,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelSmall?.copyWith(
          fontSize: 11.5,
          color: states.contains(WidgetState.selected) ? primary : RetroColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? primary : RetroColors.textMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: RetroPalette.panel,
      indicatorColor: primary.withValues(alpha: 0.16),
      indicatorShape: framed(primary),
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: const IconThemeData(color: RetroColors.textMuted),
      selectedLabelTextStyle: textTheme.labelSmall?.copyWith(color: primary),
      unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(color: RetroColors.textMuted),
      labelType: NavigationRailLabelType.all,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: RetroPalette.panel,
      selectedColor: RetroPalette.panelHi,
      side: const BorderSide(color: RetroPalette.line, width: 3),
      labelStyle: textTheme.labelMedium?.copyWith(color: RetroColors.text),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RetroRadii.control)),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: RetroPalette.screen,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RetroRadii.control),
        borderSide: const BorderSide(color: RetroPalette.line, width: 3),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RetroRadii.control),
        borderSide: const BorderSide(color: RetroPalette.line, width: 3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RetroRadii.control),
        borderSide: BorderSide(color: primary, width: 3),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: const WidgetStatePropertyAll(RetroPalette.screen),
      elevation: const WidgetStatePropertyAll(0),
      side: const WidgetStatePropertyAll(BorderSide(color: RetroPalette.line, width: 3)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RetroRadii.control))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: high,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RetroRadii.sheet),
        side: const BorderSide(color: RetroPalette.line, width: 3),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(color: primary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: high,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RetroRadii.sheet)),
        side: BorderSide(color: RetroPalette.line, width: 3),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: highest,
      surfaceTintColor: Colors.transparent,
      shape: controlShape,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: highest,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: RetroColors.text),
      actionTextColor: primary,
      shape: controlShape,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: RetroPalette.screen,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: RetroPalette.panel,
        selectedBackgroundColor: RetroPalette.panelHi,
        selectedForegroundColor: primary,
        side: const BorderSide(color: RetroPalette.line, width: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RetroRadii.control)),
        textStyle: textTheme.labelMedium,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? RetroColors.success : RetroColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? RetroColors.success.withValues(alpha: 0.25)
          : RetroPalette.screen),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? RetroColors.success : RetroPalette.line),
      trackOutlineWidth: const WidgetStatePropertyAll(3),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: RetroPalette.screen,
      thumbColor: primary,
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: RetroPalette.power, textColor: Colors.white),
    listTileTheme: ListTileThemeData(
      iconColor: RetroColors.textMuted,
      titleTextStyle: textTheme.bodyLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RetroRadii.control)),
    ),
    dividerTheme: const DividerThemeData(color: RetroPalette.line, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: highest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: RetroPalette.line, width: 2),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: RetroColors.text),
    ),
  );
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
