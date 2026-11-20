# Desinstala RetroStation (Configuración > Aplicaciones). Se borra la carpeta
# donde está este script (la de instalación), los accesos directos y la
# entrada de Aplicaciones. Los juegos y las partidas guardadas
# (AppData\Roaming\Jose Cruz\RetroStation) se conservan.
param([switch]$Silencioso)
Add-Type -AssemblyName System.Windows.Forms
$title = 'RetroStation'
$dest = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Silencioso) {
  $answer = [System.Windows.Forms.MessageBox]::Show(
    "¿Desinstalar RetroStation?`n`nTus juegos y partidas guardadas no se borran (por si lo vuelves a instalar).",
    $title, 'YesNo', 'Question')
  if ($answer -ne 'Yes') { exit 0 }
}

Get-Process RetroStation -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Set-Location $env:TEMP
$shell = New-Object -ComObject WScript.Shell
foreach ($lnk in @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RetroStation.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'RetroStation.lnk'))) {
  # Solo los accesos que apuntan a esta instalación.
  if ((Test-Path $lnk) -and $shell.CreateShortcut($lnk).TargetPath -like "$dest\*") {
    Remove-Item $lnk -Force -ErrorAction SilentlyContinue
  }
}
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RetroStation' -Recurse -Force -ErrorAction SilentlyContinue
# Por seguridad, solo se borra si de verdad es la carpeta de RetroStation.
if (Test-Path (Join-Path $dest 'RetroStation.exe')) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $Silencioso) {
  [System.Windows.Forms.MessageBox]::Show('RetroStation se ha desinstalado.', $title, 'OK', 'Information') | Out-Null
}
