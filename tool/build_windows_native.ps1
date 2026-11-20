# Compila el motor nativo para Windows (retrostation_native.dll y los núcleos)
# con el Clang de Visual Studio Build Tools, y deja las DLL en
# windows/native_bin, de donde las copia `flutter build windows`.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows_native.ps1
#
# Requiere Visual Studio 2022 (o Build Tools) con "Desarrollo para el
# escritorio con C++" y el componente "Clang de C++ para Windows".
# -SinExtras: sin PS1 ni DS (compilación más rápida para pruebas).
param([switch]$SinExtras)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'No se encuentra Visual Studio (vswhere.exe).' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio no tiene las herramientas de C++ instaladas.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$llvm = Join-Path $vs 'VC\Tools\Llvm\x64\bin'
if (-not (Test-Path (Join-Path $llvm 'clang.exe'))) { throw 'Falta el componente Clang de Visual Studio.' }

$build = Join-Path $root 'build\windows-native'
$out = Join-Path $root 'windows\native_bin'
New-Item -ItemType Directory -Force $build, $out | Out-Null
$extra = if ($SinExtras) { 'OFF' } else { 'ON' }

# vcvars64 prepara INCLUDE/LIB del SDK de Windows; después se usa Clang
# (sintaxis GNU, ABI de MSVC) con Ninja, ambos incluidos en Visual Studio.
$cmd = "`"$vcvars`" >nul && cmake -S `"$root\native`" -B `"$build`" -G Ninja " +
       "-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=`"$llvm\clang.exe`" " +
       "-DCMAKE_CXX_COMPILER=`"$llvm\clang++.exe`" -DCMAKE_ASM_COMPILER=`"$llvm\clang.exe`" " +
       "-DCMAKE_LINKER=`"$llvm\lld-link.exe`" -DRS_WINDOWS_EXTRA_CORES=$extra " +
       "&& cmake --build `"$build`""
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "La compilación nativa falló ($LASTEXITCODE)." }

Remove-Item (Join-Path $out '*.dll') -ErrorAction SilentlyContinue
Get-ChildItem $build -Recurse -Filter *.dll | Where-Object { $_.FullName -notmatch 'CMakeFiles' } |
  ForEach-Object { Copy-Item $_.FullName $out -Force; Write-Host "  $($_.Name)" }
# PSP: PPSSPP se compila aparte con tool\build_ppsspp_windows.ps1 (tarda mucho).
$ppsspp = Join-Path $root 'build\ppsspp-win\ppsspp_libretro.dll'
if (Test-Path $ppsspp) {
  Copy-Item $ppsspp (Join-Path $out 'libppsspp_libretro.dll') -Force
  Write-Host '  libppsspp_libretro.dll'
} else {
  Write-Warning 'Sin PPSSPP (PSP): ejecuta antes tool\build_ppsspp_windows.ps1'
}
# Runtime de Visual C++ junto a la app (despliegue local que Microsoft permite):
# así funciona en PCs sin el "Visual C++ Redistributable" instalado.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $src) { Copy-Item $src $out -Force; Write-Host "  $dll (runtime)" }
}
Write-Host "DLL listas en $out"
