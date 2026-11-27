<#
.SYNOPSIS
    Instala la configuracion "Hacker Neon" de Windows Terminal + PowerShell.

.DESCRIPTION
    - Instala (si faltan) oh-my-posh, fastfetch, zoxide, eza, bat, ripgrep, fd y fzf con winget.
    - Instala la fuente MesloLGM Nerd Font (iconos del prompt).
    - Agrega el esquema "Hacker Neon", transparencia, cursor y fuente a Windows Terminal
      sin borrar el resto de tu configuracion (hace copia de seguridad antes).
    - Copia el tema de oh-my-posh y fastfetch con el logo ARES.
    - Agrega una linea a tu $PROFILE que carga el perfil optimizado (tu perfil actual se conserva).

    Se adapta al usuario que lo ejecuta: usa sus rutas ($HOME, LOCALAPPDATA, Documentos/OneDrive).

.EXAMPLE
    irm https://raw.githubusercontent.com/unicorniotoxico/terminal-hacker-neon/main/install.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/unicorniotoxico/terminal-hacker-neon/main/install.ps1))) -Admin

.EXAMPLE
    .\install.ps1 -SinPaquetes
#>
[CmdletBinding()]
param(
    # Abre la pestana de Windows PowerShell como administrador (pide UAC en cada pestana)
    [switch]$Admin,
    # Instala PowerShell 7 y lo deja como pestana por defecto (prompt mucho mas rapido)
    [switch]$PowerShell7,
    # No instala programas ni fuentes (solo copia la configuracion)
    [switch]$SinPaquetes,
    # Rama del repositorio de la que se descargan los archivos cuando se ejecuta con irm | iex
    [string]$Rama = 'main',
    # Rutas destino (por defecto, las del usuario actual; se pueden cambiar para pruebas)
    [string]$UserHome = $env:USERPROFILE,
    [string]$LocalAppData = $env:LOCALAPPDATA,
    [string]$Documents = [Environment]::GetFolderPath('MyDocuments')
)

$ErrorActionPreference = 'Stop'

$RepoRaw = "https://raw.githubusercontent.com/unicorniotoxico/terminal-hacker-neon/$Rama"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Marker = '# >>> terminal-hacker-neon >>>'

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "    OK  $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "    !!  $Text" -ForegroundColor Yellow }

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $bak = "$Path.bak-$Stamp"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
        Write-Ok "copia de seguridad: $bak"
    }
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# ---------------------------------------------------------
# Archivos fuente: carpeta local (clon) o descarga desde GitHub (irm | iex)
# ---------------------------------------------------------

$AssetFiles = @(
    'config/ohmyposh/hacker.omp.json',
    'config/fastfetch/config.jsonc',
    'config/fastfetch/ares-logo.txt',
    'profile/hacker-profile.ps1',
    'terminal/hacker-neon.json'
)

function Get-SourceDir {
    $local = $null
    if ($PSCommandPath) { $local = Split-Path -Parent $PSCommandPath }
    if ($local -and (Test-Path (Join-Path $local 'terminal\hacker-neon.json'))) { return $local }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "terminal-hacker-neon-$Stamp"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    foreach ($f in $AssetFiles) {
        $dest = Join-Path $tmp ($f -replace '/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        # -OutFile guarda los bytes exactos (los iconos son UTF-8)
        Invoke-WebRequest -Uri "$RepoRaw/$f" -OutFile $dest -UseBasicParsing
    }
    return $tmp
}

# ---------------------------------------------------------
# JSON con comentarios (settings.json de Windows Terminal es JSONC)
# ---------------------------------------------------------

function ConvertFrom-Jsonc([string]$Text) {
    $sb = New-Object System.Text.StringBuilder
    $inString = $false; $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq '\' -and $i + 1 -lt $n) { [void]$sb.Append($Text[$i + 1]); $i += 2; continue }
            if ($c -eq '"') { $inString = $false }
            $i++; continue
        }
        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '*') {
            $end = $Text.IndexOf('*/', $i + 2)
            if ($end -lt 0) { throw 'settings.json: comentario /* sin cerrar' }
            $i = $end + 2; continue
        }
        if ($c -eq ',') {
            # coma final antes de } o ] (Windows Terminal la acepta, ConvertFrom-Json no)
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            if ($j -lt $n -and ($Text[$j] -eq '}' -or $Text[$j] -eq ']')) { $i++; continue }
        }
        [void]$sb.Append($c); $i++
    }
    $clean = $sb.ToString().Trim()
    if (-not $clean) { return New-Object PSObject }
    return $clean | ConvertFrom-Json
}

function Set-Prop($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-Prop($Object, [string]$Name) {
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# Devuelve el perfil de Windows Terminal con ese guid; si no existe lo agrega a la lista
function Get-TerminalProfile($Profiles, [string]$Guid, [hashtable]$NewProps) {
    $list = @(Get-Prop $Profiles 'list')
    $found = $list | Where-Object { $_ -and (Get-Prop $_ 'guid') -eq $Guid } | Select-Object -First 1
    if ($found) { return $found }
    $new = New-Object PSObject
    Set-Prop $new 'guid' $Guid
    foreach ($k in $NewProps.Keys) { Set-Prop $new $k $NewProps[$k] }
    Set-Prop $Profiles 'list' ($list + $new)
    return $new
}

function Update-TerminalSettings([string]$SettingsPath, $Theme) {
    $dir = Split-Path -Parent $SettingsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path -LiteralPath $SettingsPath) {
        Backup-File $SettingsPath
        $settings = ConvertFrom-Jsonc ([IO.File]::ReadAllText($SettingsPath, $Utf8))
    } else {
        $settings = New-Object PSObject
        Set-Prop $settings '$schema' 'https://aka.ms/terminal-profiles-schema'
    }

    # profiles: formato viejo (lista) -> { defaults, list }
    $profiles = Get-Prop $settings 'profiles'
    if ($null -eq $profiles) {
        $profiles = New-Object PSObject
        Set-Prop $profiles 'list' @()
    } elseif ($profiles -is [array]) {
        $list = $profiles
        $profiles = New-Object PSObject
        Set-Prop $profiles 'list' $list
    }
    Set-Prop $settings 'profiles' $profiles

    $defaults = Get-Prop $profiles 'defaults'
    if ($null -eq $defaults) { $defaults = New-Object PSObject }
    foreach ($p in $Theme.defaults.PSObject.Properties) { Set-Prop $defaults $p.Name $p.Value }
    Set-Prop $profiles 'defaults' $defaults

    # esquema de colores: reemplaza el del mismo nombre
    $scheme = $Theme.scheme
    $schemes = @(Get-Prop $settings 'schemes' | Where-Object { $_ -and (Get-Prop $_ 'name') -ne $scheme.name })
    $schemes += $scheme
    Set-Prop $settings 'schemes' $schemes

    $winPsGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    $ps7Guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    if ($PowerShell7) {
        $p7 = Get-TerminalProfile $profiles $ps7Guid @{ name = 'PowerShell'; source = 'Windows.Terminal.PowershellCore' }
        Set-Prop $p7 'hidden' $false
        Set-Prop $settings 'defaultProfile' $ps7Guid
    }

    if ($Admin) {
        $ps = Get-TerminalProfile $profiles $winPsGuid @{ name = 'Windows PowerShell'; commandline = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
        Set-Prop $ps 'elevate' $true
        if ($PowerShell7) { Set-Prop (Get-TerminalProfile $profiles $ps7Guid @{}) 'elevate' $true }
    }

    $json = $settings | ConvertTo-Json -Depth 32
    # validar antes de escribir
    $null = $json | ConvertFrom-Json
    [IO.File]::WriteAllText($SettingsPath, $json, $Utf8)
    Write-Ok "Windows Terminal: $SettingsPath"
}

# ---------------------------------------------------------
# 1. Programas
# ---------------------------------------------------------

$Packages = [ordered]@{
    'oh-my-posh' = 'JanDeDobbeleer.OhMyPosh'
    'fastfetch'  = 'Fastfetch-cli.Fastfetch'
    'zoxide'     = 'ajeetdsouza.zoxide'
    'eza'        = 'eza-community.eza'
    'bat'        = 'sharkdp.bat'
    'rg'         = 'BurntSushi.ripgrep.MSVC'
    'fd'         = 'sharkdp.fd'
    'fzf'        = 'junegunn.fzf'
}

Write-Host ''
Write-Host '  terminal-hacker-neon' -ForegroundColor Green
Write-Host "  usuario: $env:USERNAME   home: $UserHome" -ForegroundColor DarkGray
Write-Host ''

if (-not $SinPaquetes) {
    Write-Step 'Programas'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn2 'winget no esta disponible: instala "App Installer" desde Microsoft Store o usa -SinPaquetes.'
    } else {
        if ($PowerShell7) { $Packages['pwsh'] = 'Microsoft.PowerShell' }
        foreach ($cmd in $Packages.Keys) {
            if (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue) { Write-Ok "$cmd ya instalado"; continue }
            Write-Host "    ..  instalando $cmd ($($Packages[$cmd]))"
            & winget install --id $Packages[$cmd] --exact --source winget --silent --accept-package-agreements --accept-source-agreements | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-Warn2 "winget devolvio $LASTEXITCODE para $cmd" }
        }
        Update-SessionPath
    }

    Write-Step 'Fuente MesloLGM Nerd Font (iconos)'
    $fontKeys = @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts')
    $hasFont = $false
    foreach ($k in $fontKeys) {
        if ((Test-Path $k) -and ((Get-Item $k).GetValueNames() -match 'MesloLGM Nerd Font')) { $hasFont = $true }
    }
    if ($hasFont) { Write-Ok 'ya instalada' }
    elseif (Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue) {
        & oh-my-posh font install Meslo | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Warn2 'no se pudo instalar la fuente; los iconos pueden verse como cuadrados' }
    } else { Write-Warn2 'sin oh-my-posh no se puede instalar la fuente automaticamente' }
}

# ---------------------------------------------------------
# 2. Archivos de configuracion
# ---------------------------------------------------------

Write-Step 'Archivos de configuracion'
$Src = Get-SourceDir

$ompDir = Join-Path $UserHome '.config\ohmyposh'
$ffDir = Join-Path $UserHome '.config\fastfetch'
$psDir = Join-Path $UserHome '.config\powershell'
New-Item -ItemType Directory -Path $ompDir, $ffDir, $psDir -Force | Out-Null

$ompTarget = Join-Path $ompDir 'hacker.omp.json'
Backup-File $ompTarget
Copy-Item (Join-Path $Src 'config\ohmyposh\hacker.omp.json') $ompTarget -Force
Write-Ok $ompTarget

$logoTarget = Join-Path $ffDir 'ares-logo.txt'
Copy-Item (Join-Path $Src 'config\fastfetch\ares-logo.txt') $logoTarget -Force
$ffTarget = Join-Path $ffDir 'config.jsonc'
Backup-File $ffTarget
$ffText = [IO.File]::ReadAllText((Join-Path $Src 'config\fastfetch\config.jsonc'), $Utf8)
$ffText = $ffText.Replace('__LOGO_PATH__', $logoTarget.Replace('\', '\\'))
[IO.File]::WriteAllText($ffTarget, $ffText, $Utf8)
Write-Ok $ffTarget

$profileTarget = Join-Path $psDir 'hacker-profile.ps1'
Copy-Item (Join-Path $Src 'profile\hacker-profile.ps1') $profileTarget -Force
Unblock-File -LiteralPath $profileTarget -ErrorAction SilentlyContinue
Write-Ok $profileTarget

# ---------------------------------------------------------
# 3. Windows Terminal
# ---------------------------------------------------------

Write-Step 'Windows Terminal'
$Theme = [IO.File]::ReadAllText((Join-Path $Src 'terminal\hacker-neon.json'), $Utf8) | ConvertFrom-Json

$wtTargets = @(
    (Join-Path $LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $LocalAppData 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $LocalAppData 'Microsoft\Windows Terminal\settings.json')
)
$applied = 0
foreach ($t in $wtTargets) {
    # aplica si existe settings.json o si la app esta instalada (carpeta del paquete)
    $pkgDir = Split-Path -Parent (Split-Path -Parent $t)
    if ((Test-Path -LiteralPath $t) -or ($t -like '*\Packages\*' -and (Test-Path $pkgDir))) {
        Update-TerminalSettings $t $Theme
        $applied++
    }
}
if ($applied -eq 0) {
    Write-Warn2 'No encontre Windows Terminal. Instalalo (winget install Microsoft.WindowsTerminal) y volve a ejecutar este script.'
}

# ---------------------------------------------------------
# 4. Perfil de PowerShell (5.1 y 7)
# ---------------------------------------------------------

Write-Step 'Perfil de PowerShell'
$loadLine = '. "$HOME\.config\powershell\hacker-profile.ps1"'
$profileTargets = @(
    (Join-Path $Documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $Documents 'PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($pf in $profileTargets) {
    $isPs7 = $pf -like '*\PowerShell\Microsoft.PowerShell_profile.ps1' -and $pf -notlike '*\WindowsPowerShell\*'
    if ($isPs7 -and -not (Test-Path -LiteralPath $pf) -and -not (Get-Command pwsh -ErrorAction SilentlyContinue)) { continue }

    $content = ''
    if (Test-Path -LiteralPath $pf) { $content = [IO.File]::ReadAllText($pf) }
    if ($content.Contains($Marker)) { Write-Ok "ya configurado: $pf"; continue }

    if ($content -match '(?m)oh-my-posh\s+init|zoxide\s+init|^\s*fastfetch\s*$') {
        Write-Warn2 "$pf ya inicia oh-my-posh/zoxide/fastfetch por su cuenta: quita esas lineas para no cargarlos dos veces (arranque mas lento)."
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $pf) -Force | Out-Null
    Backup-File $pf
    $block = "`r`n$Marker`r`n$loadLine`r`n# <<< terminal-hacker-neon <<<`r`n"
    [IO.File]::AppendAllText($pf, $block, $Utf8)
    Write-Ok $pf
}

# Sin esto Windows PowerShell no ejecuta el perfil
# Solo se cambia Restricted/Undefined; AllSigned es una decision explicita y se respeta.
$effective = [string](Get-ExecutionPolicy)
if ($effective -eq 'AllSigned') {
    Write-Warn2 'La politica de ejecucion es AllSigned: no se cambia, pero el perfil (sin firmar) no va a cargar.'
} elseif ($effective -in @('Restricted', 'Undefined')) {
    $gpo = Get-ExecutionPolicy -List | Where-Object { $_.Scope -in 'MachinePolicy', 'UserPolicy' -and [string]$_.ExecutionPolicy -ne 'Undefined' }
    if ($gpo) {
        Write-Warn2 "La politica de ejecucion la fija el sistema ($effective, por directiva): el perfil puede no cargar."
    } else {
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Ok 'ExecutionPolicy (CurrentUser) = RemoteSigned, para que cargue el perfil'
        } catch {
            Write-Warn2 "No se pudo cambiar la politica de ejecucion: $($_.Exception.Message)"
        }
    }
}

# Borra la cache de arranque anterior para que se regenere con los archivos nuevos
Remove-Item -Recurse -Force (Join-Path $LocalAppData 'terminal-hacker-neon') -ErrorAction SilentlyContinue
# Borra la descarga temporal (solo si vino de GitHub, no la carpeta del clon)
if ($Src -like (Join-Path ([IO.Path]::GetTempPath()) 'terminal-hacker-neon-*')) {
    Remove-Item -Recurse -Force $Src -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '  Listo. Cerra y abri Windows Terminal para ver los cambios.' -ForegroundColor Green
if (-not $Admin) { Write-Host '  (Para abrir PowerShell como administrador siempre, ejecuta el instalador con -Admin)' -ForegroundColor DarkGray }
if (-not $PowerShell7) { Write-Host '  (Para un prompt mas rapido, ejecuta el instalador con -PowerShell7)' -ForegroundColor DarkGray }
Write-Host ''
