# Paquetes de terceros modificados

## flutter_inappwebview_android 1.1.3

- Origen: https://pub.dev/packages/flutter_inappwebview_android (versión 1.1.3)
- Licencia: Apache-2.0 (ver `flutter_inappwebview_android/LICENSE`)
- Cambio: en `android/build.gradle` se cambió
  `getDefaultProguardFile('proguard-android.txt')` por
  `getDefaultProguardFile('proguard-android-optimize.txt')` (dos líneas).
  El Android Gradle Plugin actual rechaza el primero y no se puede compilar sin el cambio.
- Uso: `dependency_overrides` en `pubspec.yaml`. Cuando se publique una versión
  que lo corrija, se puede quitar la copia y el override.
