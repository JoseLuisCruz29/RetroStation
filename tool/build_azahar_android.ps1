# Compila el núcleo libretro de Azahar (Nintendo 3DS) para Android de 64 bits
# y lo deja en android/app/src/main/jniLibs/arm64-v8a/libazahar_libretro.so,
# de donde Gradle lo empaqueta en el APK.
#
# Solo arm64-v8a: Azahar no existe para ARM de 32 bits (en esos teléfonos la
# 3DS aparece como no disponible, ver ConsoleDescriptor.arm32Note).
# Uso, desde la raíz del proyecto:
#   powershell -File tool\build_azahar_android.ps1
#
# Fuente: native/third_party/azahar (GPL-2.0+), con su CMake oficial
# (-DENABLE_LIBRETRO=ON). Dibuja con OpenGL ES 3.2 (render por hardware de
# RetroStation con EGL) y usa el JIT de ARM64 (dynarmic).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'native\third_party\azahar'
$build = Join-Path $root 'build\azahar-android'
$out = Join-Path $root 'android\app\src\main\jniLibs\arm64-v8a'

# Cambios propios de RetroStation (native/patches/azahar.patch): se aplican
# una sola vez sobre el submódulo.
$patch = Join-Path $root 'native\patches\azahar.patch'
# Ya aplicado si se puede deshacer; si no, se aplica.
cmd /c "git -C `"$src`" apply --reverse --check `"$patch`" 2>nul"
if ($LASTEXITCODE -ne 0) {
    git -C $src apply $patch
    if ($LASTEXITCODE -ne 0) { throw "No se pudo aplicar $patch" }
}

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ndk = Get-ChildItem (Join-Path $sdk 'ndk') | Sort-Object Name | Select-Object -Last 1
$cmakeDir = Get-ChildItem (Join-Path $sdk 'cmake') | Sort-Object Name | Select-Object -Last 1
$cmake = Join-Path $cmakeDir.FullName 'bin\cmake.exe'
$ninja = Join-Path $cmakeDir.FullName 'bin\ninja.exe'
$toolchain = Join-Path $ndk.FullName 'build\cmake\android.toolchain.cmake'

# Vulkan apagado: el frontend de RetroStation ofrece OpenGL ES.
& $cmake -S $src -B $build -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 `
    -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release `
    -DENABLE_LIBRETRO=ON -DENABLE_VULKAN=OFF -DENABLE_OPENGL=ON -DENABLE_TESTS=OFF `
    -DENABLE_LTO=OFF -DCITRA_WARNINGS_AS_ERRORS=OFF `
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
if ($LASTEXITCODE -ne 0) { throw "La configuración de Azahar falló ($LASTEXITCODE)" }
& $cmake --build $build --target citra_libretro
if ($LASTEXITCODE -ne 0) { throw "La compilación de Azahar falló ($LASTEXITCODE)" }

$so = Get-ChildItem -Recurse $build -Filter 'azahar_libretro.so' | Select-Object -First 1
New-Item -ItemType Directory -Force $out | Out-Null
$strip = Join-Path $ndk.FullName 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe'
& $strip -s -o (Join-Path $out 'libazahar_libretro.so') $so.FullName
Write-Host "libazahar_libretro.so -> $out"
