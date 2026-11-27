# terminal-hacker-neon

Configuración de Windows Terminal + PowerShell con estética "Hacker Neon":

- Esquema de colores **Hacker Neon**, **transparencia** (opacidad 78), cursor tipo barra verde neón y padding.
- Prompt de **oh-my-posh** (usuario · carpeta · git · tiempo de ejecución · hora).
- **fastfetch** con el logo **ARES** al abrir la terminal.
- Atajos: `ls`/`ll`/`la`/`tree` (eza), `cat`/`less` (bat), `search` (rg), `ff` (fd), `z` (zoxide), `Ctrl+R` historial con fzf, `gs`/`gp`/`gl`/`lg` para git.
- Flechas normales: `→` mueve el cursor (al final de la línea acepta la sugerencia), `↑`/`↓` recorren el historial. `F8` / `Shift+F8` buscan en el historial lo ya escrito; `F2` cambia la vista de sugerencias.

## Instalación

En PowerShell (no hace falta ser administrador):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unicorniotoxico/terminal-hacker-neon/main/install.ps1)))
```

Con opciones:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unicorniotoxico/terminal-hacker-neon/main/install.ps1))) -PowerShell7
```

O clonando el repo:

```powershell
git clone https://github.com/unicorniotoxico/terminal-hacker-neon
cd terminal-hacker-neon
.\install.ps1
```

Después cerrá y abrí Windows Terminal.

### Opciones

| Opción | Qué hace |
|---|---|
| `-PowerShell7` | Instala PowerShell 7 y lo deja como pestaña por defecto. **Recomendado**: el prompt responde mucho más rápido (ver abajo). |
| `-Admin` | La pestaña de PowerShell abre siempre como administrador (pide UAC en cada pestaña). |
| `-SinPaquetes` | No instala programas ni fuentes; solo copia la configuración. |

## Qué cambia en tu equipo

Todo se adapta al usuario que lo ejecuta (`$HOME`, `%LOCALAPPDATA%`, Documentos aunque esté en OneDrive).

| Dónde | Qué |
|---|---|
| winget | Instala lo que falte: oh-my-posh, fastfetch, zoxide, eza, bat, ripgrep, fd, fzf (y PowerShell 7 con `-PowerShell7`). |
| Fuentes | MesloLGM Nerd Font (iconos del prompt), con `oh-my-posh font install`. |
| `settings.json` de Windows Terminal | Agrega el esquema y los valores por defecto de los perfiles. **No borra** tus perfiles, atajos ni acciones. Hace copia `settings.json.bak-<fecha>`. |
| `~\.config\ohmyposh`, `~\.config\fastfetch` | Tema del prompt, config de fastfetch y logo. |
| `~\.config\powershell\hacker-profile.ps1` | El perfil. |
| `$PROFILE` (5.1 y 7) | Agrega **una línea** que carga el perfil, entre marcadores `# >>> terminal-hacker-neon >>>`. Tu perfil actual se conserva (con copia `.bak`). |
| Execution policy | Si estaba en `Restricted`, la pone en `RemoteSigned` para el usuario actual (si no, PowerShell no carga ningún perfil). |

Se puede ejecutar varias veces: no duplica nada.

### Desinstalar

1. Borrá el bloque `# >>> terminal-hacker-neon >>>` … `# <<< terminal-hacker-neon <<<` de tu `$PROFILE`.
2. Restaurá `settings.json` desde el `.bak` (o cambiá el esquema en Configuración de Windows Terminal).

## Velocidad

El perfil está optimizado para arrancar rápido:

- El `init` de zoxide y de oh-my-posh se guarda en caché (`%LOCALAPPDATA%\terminal-hacker-neon`), así no se lanzan sus programas en cada pestaña. Se regenera solo si se actualizan; también se puede borrar con `Clear-HackerCache`.
- En scripts, tareas de VS Code o salida redirigida no carga lo visual (solo los atajos).
- fastfetch se muestra una sola vez por sesión (no al hacer `reload`).

Lo que más pesa es **Windows PowerShell 5.1**: ahí oh-my-posh tiene que lanzar su programa **cada vez que apretás Enter** (~150-400 ms). En PowerShell 7 usa un proceso que queda corriendo y el prompt sale casi al instante. Por eso conviene instalar con `-PowerShell7`.

Si tu `$PROFILE` ya iniciaba oh-my-posh, zoxide o fastfetch por su cuenta, el instalador te avisa: sacá esas líneas para no cargarlos dos veces.
