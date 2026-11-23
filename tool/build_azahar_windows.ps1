# Compila el núcleo libretro de Azahar (Nintendo 3DS) para Windows x64 con
# MSVC y lo deja en windows/native_bin/libazahar_libretro.dll, junto al resto de
# núcleos (tool/build_windows_native.ps1 los copia al lado del .exe).
#
# Se compila aparte porque son ~2.000 archivos (tarda bastante la primera vez).
# Uso, desde la raíz del proyecto:
#   powershell -File tool\build_azahar_windows.ps1
#
# Fuente: native/third_party/azahar (GPL-2.0+), con su CMake oficial
# (-DENABLE_LIBRETRO=ON). En el PC dibuja con OpenGL 4.3 (render por hardware
# de RetroStation con WGL) y usa el JIT de ARM (dynarmic).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'native\third_party\azahar'
$build = Join-Path $root 'build\azahar-win'
$out = Join-Path $root 'windows\native_bin'

# Cambios propios de RetroStation (native/patches/azahar.patch): se aplican
# una sola vez sobre el submódulo.
$patch = Join-Path $root 'native\patches\azahar.patch'
# Ya aplicado si se puede deshacer; si no, se aplica.
cmd /c "git -C `"$src`" apply --reverse --check `"$patch`" 2>nul"
if ($LASTEXITCODE -ne 0) {
    git -C $src apply $patch
    if ($LASTEXITCODE -ne 0) { throw "No se pudo aplicar $patch" }
}

$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

# Vulkan apagado: el frontend de RetroStation ofrece OpenGL en el PC.
# Sin LTO: compila igual y gasta menos memoria. Las cabeceras precompiladas
# se dejan activas: algunos archivos de Azahar dependen de ellas (<string>, <chrono>).
$cmd = "`"$vcvars`" >nul && cmake -S `"$src`" -B `"$build`" -G Ninja " +
       "-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl " +
       "-DENABLE_LIBRETRO=ON -DENABLE_VULKAN=OFF -DENABLE_OPENGL=ON -DENABLE_TESTS=OFF " +
       "-DENABLE_LTO=OFF -DCITRA_WARNINGS_AS_ERRORS=OFF " +
       "-DCMAKE_POLICY_VERSION_MINIMUM=3.5 " +
       "&& cmake --build `"$build`" --target citra_libretro"
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "La compilación de Azahar falló ($LASTEXITCODE)" }

$dll = Get-ChildItem -Recurse $build -Filter 'azahar_libretro.dll' | Select-Object -First 1
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item $dll.FullName (Join-Path $out 'libazahar_libretro.dll') -Force
Write-Host "libazahar_libretro.dll -> $out"
