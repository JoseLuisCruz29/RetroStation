# Compila el núcleo libretro de PPSSPP (PSP) para Windows x64 con MSVC y lo
# deja en build\ppsspp-win\ppsspp_libretro.dll. build_windows_native.ps1 lo
# copia a windows\native_bin como libppsspp_libretro.dll.
#
# Se compila aparte (son ~1.500 archivos y tarda bastante):
#   powershell -ExecutionPolicy Bypass -File tool\build_ppsspp_windows.ps1
#
# Fuente: native/third_party/ppsspp (GPL-2.0+), con su CMake oficial
# (-DLIBRETRO=ON). Incluye el JIT x86-64 de PPSSPP y FFmpeg desde ext/ffmpeg.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio no tiene las herramientas de C++ instaladas.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$src = Join-Path $root 'native\third_party\ppsspp'
$build = Join-Path $root 'build\ppsspp-win'
New-Item -ItemType Directory -Force $build | Out-Null

$cmd = "`"$vcvars`" >nul && cmake -S `"$src`" -B `"$build`" -G Ninja " +
       "-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl " +
       "-DLIBRETRO=ON -DUSE_DISCORD=OFF -DUSE_SYSTEM_LIBPNG=OFF -DUNITTEST=OFF -DHEADLESS=OFF " +
       "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded " +
       "&& cmake --build `"$build`" --target ppsspp_libretro"
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "La compilación de PPSSPP falló ($LASTEXITCODE)." }

$dll = Get-ChildItem $build -Recurse -Filter 'ppsspp_libretro.dll' | Select-Object -First 1
if (-not $dll) { throw 'No se generó ppsspp_libretro.dll.' }
Write-Host "Listo: $($dll.FullName)"
