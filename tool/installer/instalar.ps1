# Instalador de RetroStation para Windows (lo ejecuta RetroStation-Instalador.exe).
# Muestra una ventana para elegir la carpeta y los accesos directos. Instala
# para el usuario actual, sin permisos de administrador (salvo que se elija
# una carpeta protegida como Archivos de programa).
#
# Pruebas sin ventana:
#   instalar.ps1 -Silencioso [-Destino <carpeta>] [-SinEscritorio] [-SinInicio]
param(
  [switch]$Silencioso,
  [string]$Destino,
  [switch]$SinEscritorio,
  [switch]$SinInicio
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$title = 'RetroStation'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = (Get-Content (Join-Path $here 'version.txt') -Raw).Trim()
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RetroStation'
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RetroStation.lnk'
$startLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'RetroStation.lnk'

# Instalación anterior (para actualizar en el mismo sitio).
$previous = $null
try { $previous = (Get-ItemProperty $uninstallKey -ErrorAction Stop).InstallLocation } catch {}
$defaultDir = if ($previous) { $previous } else { Join-Path $env:LOCALAPPDATA 'Programs\RetroStation' }

function Show-Message($text, $icon = 'Information', $buttons = 'OK') {
  if ($Silencioso) { return 'OK' }
  return [System.Windows.Forms.MessageBox]::Show($text, $title, $buttons, $icon)
}

# Carpeta final: si se elige una carpeta cualquiera (D:\Juegos), se instala
# dentro de ella en "RetroStation" para no mezclarse con otros archivos.
function Resolve-Target([string]$dir) {
  $dir = [Environment]::ExpandEnvironmentVariables($dir.Trim().Trim('"'))
  if (-not [IO.Path]::IsPathRooted($dir)) { throw 'Escribe una ruta completa, por ejemplo D:\Juegos\RetroStation.' }
  $dir = [IO.Path]::GetFullPath($dir).TrimEnd('\')
  if ((Split-Path -Leaf $dir) -ne 'RetroStation') { $dir = Join-Path $dir 'RetroStation' }
  return $dir
}

function Install-RetroStation([string]$target, [bool]$desktop, [bool]$startMenu, $report) {
  & $report 'Cerrando RetroStation si está abierto…'
  Get-Process RetroStation -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500

  if (Test-Path $target) {
    $items = @(Get-ChildItem $target -Force)
    if ($items.Count -gt 0 -and -not (Test-Path (Join-Path $target 'RetroStation.exe'))) {
      throw "La carpeta $target ya tiene otros archivos. Elige una carpeta vacía o nueva."
    }
    & $report 'Quitando la versión anterior…'
    Remove-Item $target -Recurse -Force
  }
  # Si antes estaba en otra carpeta, se quita esa (los juegos y partidas no están ahí).
  if ($previous -and ($previous.TrimEnd('\') -ne $target) -and
      (Test-Path (Join-Path $previous 'RetroStation.exe'))) {
    Remove-Item $previous -Recurse -Force -ErrorAction SilentlyContinue
  }

  & $report 'Copiando archivos…'
  New-Item -ItemType Directory -Force $target | Out-Null
  # tar (incluido en Windows 10/11) descomprime zip mucho más rápido que Expand-Archive.
  & tar.exe -xf (Join-Path $here 'app.zip') -C $target
  if ($LASTEXITCODE -ne 0) { Expand-Archive (Join-Path $here 'app.zip') -DestinationPath $target -Force }
  Copy-Item (Join-Path $here 'desinstalar.ps1') $target -Force
  $exe = Join-Path $target 'RetroStation.exe'
  if (-not (Test-Path $exe)) { throw 'No se encontró RetroStation.exe después de copiar los archivos.' }

  & $report 'Creando accesos directos…'
  $shell = New-Object -ComObject WScript.Shell
  foreach ($link in @(@{ Path = $desktopLink; Want = $desktop }, @{ Path = $startLink; Want = $startMenu })) {
    if ($link.Want) {
      $lnk = $shell.CreateShortcut($link.Path)
      $lnk.TargetPath = $exe
      $lnk.WorkingDirectory = $target
      $lnk.IconLocation = "$exe,0"
      $lnk.Description = 'RetroStation - emulador de consolas retro'
      $lnk.Save()
    } else {
      Remove-Item $link.Path -Force -ErrorAction SilentlyContinue  # de una instalación anterior
    }
  }

  # Entrada en Configuración > Aplicaciones para poder desinstalar.
  New-Item -Path $uninstallKey -Force | Out-Null
  $size = [int]((Get-ChildItem $target -Recurse | Measure-Object Length -Sum).Sum / 1KB)
  $props = @{
    DisplayName = 'RetroStation'
    DisplayVersion = $version
    Publisher = 'Jose Cruz'
    DisplayIcon = $exe
    InstallLocation = $target
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target\desinstalar.ps1`""
  }
  foreach ($p in $props.GetEnumerator()) { Set-ItemProperty -Path $uninstallKey -Name $p.Key -Value $p.Value }
  Set-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -Type DWord
  Set-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -Type DWord
  Set-ItemProperty -Path $uninstallKey -Name EstimatedSize -Value $size -Type DWord
  return $exe
}

# --- Sin ventana (pruebas) ----------------------------------------------------------
if ($Silencioso) {
  try {
    $target = Resolve-Target $(if ($Destino) { $Destino } else { $defaultDir })
    $exe = Install-RetroStation $target (-not $SinEscritorio) (-not $SinInicio) { param($t) Write-Host $t }
    Write-Host "Instalado en $target"
    exit 0
  } catch {
    Write-Error $_
    exit 1
  }
}

# --- Ventana del instalador ---------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Instalar RetroStation $version"
$form.ClientSize = New-Object System.Drawing.Size(520, 330)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$icoPath = Join-Path $here 'app_icon.ico'
if (Test-Path $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }

$header = New-Object System.Windows.Forms.Label
$header.Text = "RetroStation $version"
$header.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$header.Location = New-Object System.Drawing.Point(20, 16)
$header.AutoSize = $true
$form.Controls.Add($header)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = 'Emulador de consolas retro con multijugador por Wi-Fi. Si ya lo tenías, tus juegos y partidas guardadas se conservan.'
$intro.Location = New-Object System.Drawing.Point(22, 52)
$intro.Size = New-Object System.Drawing.Size(480, 40)
$form.Controls.Add($intro)

$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Text = 'Carpeta de instalación:'
$folderLabel.Location = New-Object System.Drawing.Point(22, 100)
$folderLabel.AutoSize = $true
$form.Controls.Add($folderLabel)

$folderBox = New-Object System.Windows.Forms.TextBox
$folderBox.Text = $defaultDir
$folderBox.Location = New-Object System.Drawing.Point(24, 124)
$folderBox.Size = New-Object System.Drawing.Size(370, 26)
$form.Controls.Add($folderBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Examinar…'
$browse.Location = New-Object System.Drawing.Point(402, 122)
$browse.Size = New-Object System.Drawing.Size(96, 30)
$browse.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = 'Elige dónde instalar RetroStation (se creará la carpeta "RetroStation" dentro).'
  $dialog.ShowNewFolderButton = $true
  $start = Split-Path -Parent $folderBox.Text
  if ($start -and (Test-Path $start)) { $dialog.SelectedPath = $start }
  if ($dialog.ShowDialog($form) -eq 'OK') {
    try { $folderBox.Text = Resolve-Target $dialog.SelectedPath } catch { $folderBox.Text = $dialog.SelectedPath }
  }
})
$form.Controls.Add($browse)

$desktopCheck = New-Object System.Windows.Forms.CheckBox
$desktopCheck.Text = 'Crear acceso directo en el Escritorio'
$desktopCheck.Checked = $true
$desktopCheck.Location = New-Object System.Drawing.Point(24, 166)
$desktopCheck.AutoSize = $true
$form.Controls.Add($desktopCheck)

$startCheck = New-Object System.Windows.Forms.CheckBox
$startCheck.Text = 'Añadir al menú Inicio'
$startCheck.Checked = $true
$startCheck.Location = New-Object System.Drawing.Point(24, 194)
$startCheck.AutoSize = $true
$form.Controls.Add($startCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = 'Abrir RetroStation al terminar'
$launchCheck.Checked = $true
$launchCheck.Location = New-Object System.Drawing.Point(24, 222)
$launchCheck.AutoSize = $true
$form.Controls.Add($launchCheck)

$status = New-Object System.Windows.Forms.Label
$status.Text = ''
$status.ForeColor = [System.Drawing.Color]::DimGray
$status.Location = New-Object System.Drawing.Point(22, 256)
$status.Size = New-Object System.Drawing.Size(480, 22)
$form.Controls.Add($status)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Instalar'
$installButton.Location = New-Object System.Drawing.Point(298, 284)
$installButton.Size = New-Object System.Drawing.Size(96, 32)
$form.Controls.Add($installButton)
$form.AcceptButton = $installButton

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancelar'
$cancelButton.Location = New-Object System.Drawing.Point(402, 284)
$cancelButton.Size = New-Object System.Drawing.Size(96, 32)
$cancelButton.DialogResult = 'Cancel'
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

$installButton.Add_Click({
  $controls = @($folderBox, $browse, $desktopCheck, $startCheck, $launchCheck, $installButton, $cancelButton)
  $controls | ForEach-Object { $_.Enabled = $false }
  $form.Cursor = 'WaitCursor'
  $report = { param($t) $status.Text = $t; $form.Refresh() }
  try {
    $target = Resolve-Target $folderBox.Text
    $exe = Install-RetroStation $target $desktopCheck.Checked $startCheck.Checked $report
    $form.Cursor = 'Default'
    $where = @()
    if ($desktopCheck.Checked) { $where += 'el Escritorio' }
    if ($startCheck.Checked) { $where += 'el menú Inicio' }
    $access = if ($where) { "Tienes el acceso directo en $($where -join ' y ')." } else { "Se abre con RetroStation.exe en esa carpeta." }
    [System.Windows.Forms.MessageBox]::Show(
      "RetroStation $version está instalado en:`n$target`n`n$access`n`nMultijugador: la primera vez, si Windows pregunta por el Firewall, pulsa «Permitir».",
      $title, 'OK', 'Information') | Out-Null
    if ($launchCheck.Checked) { Start-Process $exe -WorkingDirectory $target }
    $form.Close()
  } catch {
    $form.Cursor = 'Default'
    $message = $_.Exception.Message
    if ($_.Exception -is [UnauthorizedAccessException] -or $message -match 'denegado|denied') {
      $message = "No hay permiso para escribir en esa carpeta. Elige otra (por ejemplo dentro de tu usuario o en D:\).`n`n$message"
    }
    $status.Text = ''
    [System.Windows.Forms.MessageBox]::Show("No se pudo instalar:`n`n$message", $title, 'OK', 'Error') | Out-Null
    $controls | ForEach-Object { $_.Enabled = $true }
  }
})

[void]$form.ShowDialog()
