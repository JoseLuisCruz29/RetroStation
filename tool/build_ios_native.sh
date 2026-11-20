#!/usr/bin/env bash
# Compila el motor de RetroStation y sus núcleos para iPhone (arm64) y los
# empaqueta como .framework en build/ios-frameworks. Hace falta un Mac con
# Xcode (lo usa .github/workflows/ios.yml en GitHub Actions).
#
#   tool/build_ios_native.sh
#
# Cada .dylib se convierte en <nombre>.framework/<nombre>, que es como iOS
# admite bibliotecas dinámicas dentro de una app. Dart las abre con su ruta
# completa (RetroNative.nativeLibraryPath).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/ios-native"
out="$root/build/ios-frameworks"
min_ios=15.0

cmake -S "$root/native" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$min_ios \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_INSTALL_NAME_DIR=@rpath
# El motor y los núcleos básicos son obligatorios. PS1, DS y gpSP se intentan
# uno a uno: si alguno no compila, la app sale igual y esa consola aparece
# como "próximamente" (Dart comprueba qué frameworks hay dentro de la app).
cmake --build "$build" --parallel --target \
  retrostation_native mgba_libretro fceumm_libretro snes9x_libretro gbalink_libretro
for target in pcsx_rearmed_libretro melonds_libretro gpsp_libretro; do
  if ! cmake --build "$build" --parallel --target "$target"; then
    echo "::warning::$target no compiló para iPhone (su consola quedará como próximamente)"
  fi
done

rm -rf "$out"
mkdir -p "$out"
version=$(grep '^version:' "$root/pubspec.yaml" | sed -E 's/version: *([0-9.]+).*/\1/')
find "$build" -name '*.dylib' -not -path '*/CMakeFiles/*' | while read -r lib; do
  file=$(basename "$lib" .dylib)
  # La biblioteca del motor se llama retrostation_native (sin "lib").
  name=${file#lib}
  [ "$name" = "retrostation_native" ] || name=$file
  fw="$out/$name.framework"
  mkdir -p "$fw"
  cp "$lib" "$fw/$name"
  install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name"
  bundle_id="com.moran.retrostation.$(echo "$name" | tr '_' '-')"
  cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>$min_ios</string>
</dict>
</plist>
EOF
  echo "  $name.framework ($(du -h "$fw/$name" | cut -f1))"
done
echo "Frameworks listos en $out"
