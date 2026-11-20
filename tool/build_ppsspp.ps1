# Compila el núcleo libretro de PPSSPP (PSP) para Android y lo deja en
# android/app/src/main/jniLibs/<abi>/libppsspp_libretro.so, de donde Gradle lo
# empaqueta en el APK.
#
# Se compila aparte (no en cada `flutter build`) porque son ~1.500 archivos.
# Uso, desde la raíz del proyecto:
#   powershell -File tool\build_ppsspp.ps1
#
# Fuente: native/third_party/ppsspp (GPL-2.0+), con su libretro/jni/Android.mk
# oficial. Incluye el JIT de ARM de 32 y 64 bits de PPSSPP.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'native\third_party\ppsspp\libretro'
$ndk = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\ndk" | Sort-Object Name | Select-Object -Last 1
$ndkBuild = Join-Path $ndk.FullName 'ndk-build.cmd'
$jobs = [Environment]::ProcessorCount

# Android.mk usa rutas relativas a libretro/jni: hay que lanzarlo desde ahí.
Push-Location (Join-Path $src 'jni')
try {
    # -frtti/-fexceptions: Application.mk los pedía con una variable que los NDK
    # actuales ignoran. LOCAL_ARM_MODE=arm: código ARM (no Thumb), más rápido.
    & $ndkBuild "APP_ABI=armeabi-v7a arm64-v8a" APP_PLATFORM=android-24 `
        "APP_CPPFLAGS=-frtti -fexceptions" LOCAL_ARM_MODE=arm `
        APP_SHORT_COMMANDS=true "-j$jobs"  # Windows: enlace con archivo de respuesta
    if ($LASTEXITCODE -ne 0) { throw "ndk-build falló ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

foreach ($abi in 'armeabi-v7a', 'arm64-v8a') {
    $out = Join-Path $root "android\app\src\main\jniLibs\$abi"
    New-Item -ItemType Directory -Force $out | Out-Null
    Copy-Item (Join-Path $src "libs\$abi\libretro.so") (Join-Path $out 'libppsspp_libretro.so') -Force
    Write-Host "$abi -> $out\libppsspp_libretro.so"
}
