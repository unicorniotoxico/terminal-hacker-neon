# =========================================================
# terminal-hacker-neon - perfil de PowerShell
# Se carga desde $PROFILE con:  . "$HOME\.config\powershell\hacker-profile.ps1"
# =========================================================

# ---------------------------------------------------------
# Atajos (se definen siempre: son baratos)
# ---------------------------------------------------------

# En PowerShell los alias ganan a las funciones: hay que quitar los alias
# integrados (ls, cat, gp, gl) para que se usen estas funciones. Son AllScope,
# asi que se quitan aca mismo (en el scope del perfil), no dentro de una funcion.
$HackerAliases = @('gp', 'gl')
$HackerHasEza = [bool](Get-Command eza -CommandType Application -ErrorAction SilentlyContinue)
$HackerHasBat = [bool](Get-Command bat -CommandType Application -ErrorAction SilentlyContinue)
if ($HackerHasEza) { $HackerAliases += 'ls' }
if ($HackerHasBat) { $HackerAliases += 'cat' }
foreach ($n in $HackerAliases) { Remove-Item "Alias:$n" -Force -ErrorAction SilentlyContinue }

# Solo si el programa esta instalado (si no, ls/cat siguen siendo los de PowerShell)
if ($HackerHasEza) {
    function ls  { eza --icons --group-directories-first @args }
    function ll   { eza -lah --icons --group-directories-first --git @args }
    function la   { eza -a --icons --group-directories-first @args }
    function tree { eza --tree --icons --group-directories-first @args }
}

if ($HackerHasBat) {
    function cat { bat --paging=never @args }
    function less { bat @args }
}

function search { rg @args }
function ff     { fd @args }

function lg   { lazygit }
function gs    { git status }
function gp    { git pull }
function gpush { git push }
function gl    { git log --oneline --graph --decorate -15 }

function mkcd {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

function path   { $env:PATH -split ';' }
function reload { . $PROFILE }

function which {
    param([Parameter(Mandatory = $true)][string]$Command)
    Get-Command $Command | Select-Object Name, Source, CommandType
}

# Borra la cache de arranque (usar si actualizas oh-my-posh o zoxide y algo falla)
function Clear-HackerCache {
    Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'terminal-hacker-neon') -ErrorAction SilentlyContinue
    Write-Host 'Cache borrada. Abri una pestana nueva.'
}

# ---------------------------------------------------------
# Lo visual solo en una consola interactiva real
# (scripts, VS Code tasks, agentes, salida redirigida: arrancan rapido)
# ---------------------------------------------------------

if ($Host.Name -ne 'ConsoleHost' -or [Console]::IsOutputRedirected) { return }

$HackerCacheDir = Join-Path $env:LOCALAPPDATA 'terminal-hacker-neon'
if (-not (Test-Path $HackerCacheDir)) { New-Item -ItemType Directory -Path $HackerCacheDir -Force | Out-Null }

# En una pestana de administrador no se ejecuta nada cacheado en disco:
# los init se generan en vivo (un poco mas lento, pero sin scripts escribibles sin elevacion)
$HackerIsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Clave de cache: cambia si se actualiza el exe o el archivo de config
function Get-HackerCacheKey([string]$Exe, [string]$Config) {
    $parts = foreach ($p in @($Exe, $Config)) {
        if ($p -and (Test-Path $p)) { $i = Get-Item $p; "$($i.FullName)|$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" }
    }
    $parts -join ';'
}

# ---------------------------------------------------------
# PSReadLine
# ---------------------------------------------------------

if (-not (Get-Module PSReadLine)) { Import-Module PSReadLine }

try {
    Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
    # InlineView: la sugerencia aparece en gris y no secuestra las flechas arriba/abajo (F2 alterna a lista)
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
} catch { }

# Flecha derecha: mueve el cursor; al final de la linea acepta la sugerencia
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
# Flechas arriba/abajo: historial completo
Set-PSReadLineKeyHandler -Key UpArrow -Function PreviousHistory
Set-PSReadLineKeyHandler -Key DownArrow -Function NextHistory
# Buscar en el historial por lo ya escrito
Set-PSReadLineKeyHandler -Key F8 -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key Shift+F8 -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Ctrl+R: historial interactivo con fzf
Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    $result = Get-Content $historyPath -ErrorAction SilentlyContinue | Select-Object -Unique | fzf
    if ($result) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result) }
}

# ---------------------------------------------------------
# ZOXIDE (init cacheado en disco: evita lanzar el exe en cada pestana)
# ---------------------------------------------------------

$zoxideCmd = Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($zoxideCmd -and $HackerIsAdmin) {
    Invoke-Expression (zoxide init powershell | Out-String)
} elseif ($zoxideCmd) {
    $zFile = Join-Path $HackerCacheDir 'zoxide-init.ps1'
    $zKeyFile = "$zFile.key"
    $zKey = Get-HackerCacheKey $zoxideCmd.Source $null
    if (-not (Test-Path $zFile) -or -not (Test-Path $zKeyFile) -or (Get-Content $zKeyFile -Raw).Trim() -ne $zKey) {
        $zInit = zoxide init powershell | Out-String
        if ($LASTEXITCODE -eq 0 -and $zInit) {
            Set-Content -Path $zFile -Value $zInit -Encoding UTF8
            Set-Content -Path $zKeyFile -Value $zKey -Encoding UTF8
        }
    }
    if (Test-Path $zFile) { . $zFile }
}

# ---------------------------------------------------------
# FASTFETCH (logo, una vez por sesion)
# ---------------------------------------------------------

if (-not $global:FastfetchShown) {
    $global:FastfetchShown = $true
    if (Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue) { fastfetch }
}

# ---------------------------------------------------------
# OH MY POSH
# oh-my-posh init solo imprime una linea que apunta a un script ya cacheado
# por oh-my-posh. Guardamos esa ruta y generamos un session id nuevo por
# pestana, asi no se lanza el exe (~250 ms) para obtenerla.
# Si la ruta cacheada ya no existe (actualizacion), se regenera sola.
# ---------------------------------------------------------

$ompConfig = Join-Path $HOME '.config\ohmyposh\hacker.omp.json'
$ompCmd = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ompCmd -and (Test-Path $ompConfig) -and $HackerIsAdmin) {
    oh-my-posh init pwsh --config $ompConfig | Out-String | Invoke-Expression
} elseif ($ompCmd -and (Test-Path $ompConfig)) {
    $ompFile = Join-Path $HackerCacheDir 'omp-init.txt'
    $ompKey = Get-HackerCacheKey $ompCmd.Source $ompConfig
    $ompScript = $null

    # Caduca a las 24 h: el alias de Microsoft Store no cambia de fecha al actualizarse
    if ((Test-Path $ompFile) -and ((Get-Date) - (Get-Item $ompFile).LastWriteTime).TotalHours -lt 24) {
        $cached = Get-Content $ompFile
        if ($cached.Count -eq 2 -and $cached[0] -eq $ompKey -and (Test-Path -LiteralPath $cached[1])) { $ompScript = $cached[1] }
    }

    if (-not $ompScript) {
        $initLine = (oh-my-posh init pwsh --config $ompConfig) -join "`n"
        # Formato esperado: $env:POSH_SESSION_ID = "..."; $env:POSH_CONFIG = '...';& '<script>.ps1'
        if ($initLine -match '^\$env:POSH_SESSION_ID = "[^"]+"; \$env:POSH_CONFIG = ''[^'']+'';& ''([^'']+\.ps1)''\s*$') {
            $ompScript = $Matches[1]
            Set-Content -Path $ompFile -Value @($ompKey, $ompScript) -Encoding UTF8
        } elseif ($initLine) {
            # Formato desconocido (otra version de oh-my-posh): se usa tal cual, sin cache
            Invoke-Expression $initLine
        }
    }

    if ($ompScript) {
        $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
        $env:POSH_CONFIG = $ompConfig
        & $ompScript
    }
}
