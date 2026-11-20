# Versión para compartir con amigos: SIN los juegos comerciales.
#
# Solo se incluyen los juegos homebrew de assets/bundled/bundled.json (con
# licencia libre). El resto de archivos de assets/bundled se aparta durante la
# compilación y se devuelve a su sitio al terminar (también si falla).
#
# Genera en Descargas:
#   RetroStation-<versión>-Instalador.exe   (Windows, con IExpress y el logo como icono)
#   RetroStation-<versión>-compartir.apk    (Android)
#
#   powershell -ExecutionPolicy Bypass -File tool\build_compartir.ps1 [-SinApk] [-SoloEmpaquetar]
#
# -SoloEmpaquetar: no compila; rehace el .exe con el app.zip de la última vez
# (build\instalador), por ejemplo tras cambiar los scripts del instalador.
param([switch]$SinApk, [switch]$SoloEmpaquetar)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundled = Join-Path $root 'assets\bundled'
$aside = Join-Path $root 'build\bundled_privado'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
$stage = Join-Path $root 'build\instalador'
$release = Join-Path $root 'build\windows\x64\runner\Release'
$version = ((Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value)

if (-not $SoloEmpaquetar) {
  # Archivos que sí se pueden compartir: los de bundled.json, sus portadas y la documentación.
  $info = Get-Content (Join-Path $bundled 'bundled.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $keep = @('bundled.json', 'LEEME.md')
  foreach ($g in $info) { $keep += $g.file; if ($g.cover) { $keep += $g.cover } }

  # Si una compilación anterior se interrumpió, primero se devuelve lo apartado.
  if (Test-Path $aside) {
    Get-ChildItem $aside | ForEach-Object { Move-Item $_.FullName $bundled -Force }
  }
  New-Item -ItemType Directory -Force $aside | Out-Null
  $private = Get-ChildItem $bundled -File | Where-Object { $keep -notcontains $_.Name }
  Write-Host "Se apartan $($private.Count) juegos que no se pueden compartir."

  Push-Location $root
  try {
    $private | ForEach-Object { Move-Item $_.FullName $aside -Force }

    # Windows. Se borra la compilación anterior para que no quede ningún juego.
    if (Test-Path $release) { Remove-Item $release -Recurse -Force }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows falló' }
    $leaked = Get-ChildItem (Join-Path $release 'data\flutter_assets\assets\bundled') -File |
      Where-Object { $keep -notcontains $_.Name }
    if ($leaked) { throw "La compilación incluye juegos privados: $($leaked.Name -join ', ')" }

    if (-not $SinApk) {
      flutter build apk --release --target-platform android-arm,android-arm64
      if ($LASTEXITCODE -ne 0) { throw 'flutter build apk falló' }
      $apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
      try {
        $inApk = $zip.Entries | Where-Object { $_.FullName -like 'assets/flutter_assets/assets/bundled/*' } |
          ForEach-Object { [Uri]::UnescapeDataString(($_.FullName -split '/')[-1]) }
      } finally { $zip.Dispose() }
      $leakedApk = $inApk | Where-Object { $keep -notcontains $_ }
      if ($leakedApk) { throw "El APK incluye juegos privados: $($leakedApk -join ', ')" }
      Copy-Item $apk (Join-Path $downloads "RetroStation-$version-compartir.apk") -Force
      Write-Host "APK: $downloads\RetroStation-$version-compartir.apk"
    }
  } finally {
    Get-ChildItem $aside | ForEach-Object { Move-Item $_.FullName $bundled -Force }
    Remove-Item $aside -Force -ErrorAction SilentlyContinue
    Pop-Location
  }

  # La app comprimida (app.zip) para el instalador.
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force $stage | Out-Null
  $app = Join-Path $stage 'app'
  Copy-Item $release $app -Recurse
  $exe = Get-ChildItem $app -Filter '*.exe' | Select-Object -First 1
  if ($exe.Name -cne 'RetroStation.exe') { Rename-Item $exe.FullName 'RetroStation.exe' }
  Compress-Archive -Path (Join-Path $app '*') -DestinationPath (Join-Path $stage 'app.zip') -CompressionLevel Optimal
  Remove-Item $app -Recurse -Force
}

# Instalador: app.zip + scripts + logo, empaquetados con IExpress (incluido en Windows).
if (-not (Test-Path (Join-Path $stage 'app.zip'))) { throw 'No hay build\instalador\app.zip: compila sin -SoloEmpaquetar.' }
$icon = Join-Path $root 'windows\runner\resources\app_icon.ico'
Copy-Item $icon $stage -Force
Copy-Item (Join-Path $PSScriptRoot 'installer\instalar.ps1') $stage -Force
Copy-Item (Join-Path $PSScriptRoot 'installer\desinstalar.ps1') $stage -Force
Set-Content (Join-Path $stage 'version.txt') $version -Encoding ASCII

$target = Join-Path $downloads "RetroStation-$version-Instalador.exe"
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=RetroStation $version
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File instalar.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="app.zip"
FILE1="instalar.ps1"
FILE2="desinstalar.ps1"
FILE3="version.txt"
FILE4="app_icon.ico"
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
"@
$sedPath = Join-Path $stage 'instalador.sed'
Set-Content $sedPath $sed -Encoding ASCII
if (Test-Path $target) { Remove-Item $target -Force }
# A veces (antivirus revisando el archivo) IExpress termina sin generarlo: se reintenta.
for ($try = 1; $try -le 3 -and -not (Test-Path $target); $try++) {
  Start-Process iexpress.exe -ArgumentList '/N', '/Q', $sedPath -Wait | Out-Null
  for ($i = 0; $i -lt 20 -and -not (Test-Path $target); $i++) { Start-Sleep -Milliseconds 500 }
}
if (-not (Test-Path $target)) { throw 'IExpress no generó el instalador.' }

# El logo como icono del .exe (IExpress no permite elegirlo).
$iconTool = Join-Path $root 'build\set_exe_icon.exe'
if (-not (Test-Path $iconTool)) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  $vs = & $vswhere -latest -products * -property installationPath
  $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
  $src = Join-Path $PSScriptRoot 'installer\set_exe_icon.cpp'
  cmd /c "`"$vcvars`" >nul && cl /nologo /O2 /EHsc /std:c++17 /utf-8 /DUNICODE /D_UNICODE `"$src`" /Fe:`"$iconTool`" /Fo:`"$root\build\set_exe_icon.obj`""
}
& $iconTool $target $icon
if ($LASTEXITCODE -ne 0) { Write-Warning 'No se pudo poner el logo al instalador.' }
Write-Host "Instalador: $target ($([math]::Round((Get-Item $target).Length / 1MB)) MB)"
