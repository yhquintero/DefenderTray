<#
================================================================================
  DefenderTray v4.3 Pro - Control Profesional de Windows Defender
================================================================================
  Descripcion:
    Aplicacion de bandeja del sistema para gestionar Windows Defender con:
      - Iconos dinamicos (verde/rojo/naranja + icono oficial de Microsoft).
      - Activacion COMPLETA de las 15+ protecciones disponibles.
      - Desactivacion TOTAL de los 8 servicios + 6 procesos.
      - Diagnostico detallado por servicio, proceso, modulo y registro.
      - Reparacion Profunda con consola en vivo (reg delete, sc, sfc, DISM).
      - Modo kiosco con contrasena hasheada (SHA256).
      - Barra de estado contextual en la parte inferior.
      - Barra de menu completa (Archivo, Acciones, Herramientas, Ayuda).
      - Atajos de teclado F1/F5/Esc.
      - Log rotativo diario y configuracion en JSON.
      - Excluye automaticamente su carpeta en Defender al arrancar.

  Requisitos:
    - Windows 7/8/8.1/10/11 (todas las builds).
    - PowerShell 5.1 o superior.
    - Ejecutar como Administrador para activar/desactivar/modificar servicios.

  Autor:  Ing. Yosvany Hernandez Quintero
  Movil:  +53 5 2160801 / +53 5 9860911
  Fecha:  2026
================================================================================
#>

# ============================================================================
# SECCION 1 - ENSAMBLADOS .NET
# Carga las librerias de Windows Forms y Drawing necesarias para toda la UI.
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# SECCION 2 - ARGUMENTOS DE LINEA DE COMANDOS Y RUTAS BASE
# Detecta los argumentos -silent, -portable, -action y construye las rutas
# de trabajo (config, logs, backups).
# ============================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")

$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

if ($script:PortableMode) {
    $script:ConfigDir = Join-Path $script:ScriptDir "DefenderTrayData"
} else {
    $script:ConfigDir = Join-Path $env:LOCALAPPDATA "DefenderTray"
}

$script:LogFolder   = Join-Path $script:ConfigDir "Logs"
$script:BackupDir   = Join-Path $script:ConfigDir "Backups"
$script:LogFile     = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ConfigFile  = Join-Path $script:ConfigDir "config.json"

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ============================================================================
# SECCION 3 - CARACTERES ESPECIALES
# Define la letra enie para usarla sin romper el parser de PowerShell.
# ============================================================================
$script:CH_N = [char]0x00F1
$script:TXT_PWD = "Contrase" + $script:CH_N + "a"

# ============================================================================
# SECCION 4 - CONFIGURACION PERSISTENTE
# Carga y guarda la configuracion del usuario desde/hacia config.json.
# Valores: tema, modo kiosco, hash de contrasena, primera ejecucion.
# ============================================================================
$script:CfgDarkTheme    = $true
$script:CfgKioskMode    = $false
$script:CfgKioskHash    = ""
$script:CfgFirstRunDone = $false
$script:DarkTheme       = $true
$script:IsKioskMode     = $false

function Load-AppConfig {
    <#
    Lee el archivo config.json y restaura la configuracion del usuario.
    Si el archivo no existe o esta corrupto, se usan los valores por defecto.
    #>
    try {
        if (Test-Path $script:ConfigFile) {
            $json = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $json.DarkTheme)    { $script:CfgDarkTheme    = [bool]$json.DarkTheme }
            if ($null -ne $json.KioskMode)    { $script:CfgKioskMode    = [bool]$json.KioskMode }
            if ($null -ne $json.KioskHash)    { $script:CfgKioskHash    = [string]$json.KioskHash }
            if ($null -ne $json.FirstRunDone) { $script:CfgFirstRunDone = [bool]$json.FirstRunDone }
        }
    } catch { }
    $script:DarkTheme   = $script:CfgDarkTheme
    $script:IsKioskMode = $script:CfgKioskMode
}

function Save-AppConfig {
    <#
    Persiste la configuracion actual en config.json.
    Se llama despues de cualquier cambio del usuario (kiosco, tema, etc).
    #>
    try {
        $obj = [PSCustomObject]@{
            DarkTheme    = $script:DarkTheme
            KioskMode    = $script:IsKioskMode
            KioskHash    = $script:CfgKioskHash
            FirstRunDone = $script:CfgFirstRunDone
        }
        $obj | ConvertTo-Json -Depth 3 | Set-Content -Path $script:ConfigFile -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 5 - SISTEMA DE LOG
# Escribe lineas con timestamp en un archivo diario rotativo.
# ============================================================================
function Write-AppLog {
    <#
    Escribe un mensaje en el archivo de log con timestamp y nivel.
    Niveles: INFO, WARN, ERROR.
    Nunca lanza excepcion aunque falle el acceso al archivo.
    #>
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ============================================================================
# SECCION 6 - ESPERA NO BLOQUEANTE
# Espera el tiempo indicado procesando los mensajes de Windows cada 50ms.
# Esto mantiene la UI responsiva durante operaciones largas.
# ============================================================================
function Wait-WithDoEvents {
    param([int]$Milliseconds)
    $end = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $end) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        Start-Sleep -Milliseconds 50
    }
}

# ============================================================================
# SECCION 7 - PALETA DE COLORES FUTURISTA
# Define todos los colores del tema oscuro tipo "cyberpunk/neon".
# ============================================================================
function Get-FuturisticPalette {
    <#
    Devuelve un hashtable con la paleta de colores completa.
    Los colores usan la nomenclatura AccentXXX para los botones y
    Ok/Bad/Warn para los indicadores de estado.
    #>
    return @{
        Bg           = [System.Drawing.Color]::FromArgb(10,14,26)
        BgSecondary  = [System.Drawing.Color]::FromArgb(20,27,46)
        CardBg       = [System.Drawing.Color]::FromArgb(24,32,52)
        Text         = [System.Drawing.Color]::FromArgb(224,230,240)
        TextMuted    = [System.Drawing.Color]::FromArgb(107,122,153)
        TextDiag     = [System.Drawing.Color]::FromArgb(180,200,220)
        AccentCyan   = [System.Drawing.Color]::FromArgb(0,229,255)
        AccentCyanH  = [System.Drawing.Color]::FromArgb(0,180,200)
        AccentPurple = [System.Drawing.Color]::FromArgb(177,78,255)
        AccentPurpH  = [System.Drawing.Color]::FromArgb(140,60,200)
        AccentGreen  = [System.Drawing.Color]::FromArgb(0,200,108)
        AccentGreenH = [System.Drawing.Color]::FromArgb(0,160,86)
        AccentRed    = [System.Drawing.Color]::FromArgb(255,51,102)
        AccentRedH   = [System.Drawing.Color]::FromArgb(200,40,80)
        AccentAmber  = [System.Drawing.Color]::FromArgb(255,170,0)
        AccentAmberH = [System.Drawing.Color]::FromArgb(200,130,0)
        AccentBlue   = [System.Drawing.Color]::FromArgb(0,140,255)
        AccentBlueH  = [System.Drawing.Color]::FromArgb(0,110,200)
        BtnDisabled  = [System.Drawing.Color]::FromArgb(45,55,75)
        BtnDisabledT = [System.Drawing.Color]::FromArgb(100,115,140)
        HeaderOk     = [System.Drawing.Color]::FromArgb(0,150,80)
        HeaderWarn   = [System.Drawing.Color]::FromArgb(180,30,60)
        HeaderPart   = [System.Drawing.Color]::FromArgb(180,110,0)
        HeaderUnk    = [System.Drawing.Color]::FromArgb(45,55,75)
        Ok           = [System.Drawing.Color]::FromArgb(0,230,120)
        Bad          = [System.Drawing.Color]::FromArgb(255,80,110)
        Warn         = [System.Drawing.Color]::FromArgb(255,180,50)
        Neutral      = [System.Drawing.Color]::FromArgb(120,135,160)
        ConsoleBg    = [System.Drawing.Color]::FromArgb(8,12,20)
        ConsoleText  = [System.Drawing.Color]::FromArgb(0,255,180)
        MenuBg       = [System.Drawing.Color]::FromArgb(16,22,38)
    }
}

Load-AppConfig
$script:Colors = Get-FuturisticPalette

# ============================================================================
# SECCION 8 - ICONOS DINAMICOS
# Genera escudos con el color segun el estado. Tambien intenta extraer
# el icono oficial de Windows Defender para usarlo como icono base.
# ============================================================================

function New-ShieldBitmap {
    <#
    Dibuja un escudo hexagonal con el color indicado usando GDI+.
    Devuelve un Bitmap de 32x32 por defecto.
    #>
    param([System.Drawing.Color]$FillColor, [int]$Size = 32)
    try {
        $bmp = New-Object System.Drawing.Bitmap $Size, $Size
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)

        $pts = New-Object 'System.Drawing.Point[]' 6
        $pts[0] = New-Object System.Drawing.Point ([int]($Size * 0.5)), ([int]($Size * 0.05))
        $pts[1] = New-Object System.Drawing.Point ([int]($Size * 0.9)), ([int]($Size * 0.25))
        $pts[2] = New-Object System.Drawing.Point ([int]($Size * 0.9)), ([int]($Size * 0.55))
        $pts[3] = New-Object System.Drawing.Point ([int]($Size * 0.5)), ([int]($Size * 0.95))
        $pts[4] = New-Object System.Drawing.Point ([int]($Size * 0.1)), ([int]($Size * 0.55))
        $pts[5] = New-Object System.Drawing.Point ([int]($Size * 0.1)), ([int]($Size * 0.25))

        $brush = New-Object System.Drawing.SolidBrush $FillColor
        $g.FillPolygon($brush, $pts)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(0,229,255)), 1.5
        $g.DrawPolygon($pen, $pts)

        $g.Dispose(); $brush.Dispose(); $pen.Dispose()
        return $bmp
    } catch { return $null }
}

function New-IconFromColor {
    <#
    Convierte un Bitmap de escudo en un Icon de Windows.
    Si falla la conversion, devuelve el icono de escudo del sistema.
    #>
    param([System.Drawing.Color]$Color)
    $bmp = New-ShieldBitmap -FillColor $Color
    if ($null -eq $bmp) { return [System.Drawing.SystemIcons]::Shield }
    try { return [System.Drawing.Icon]::FromHandle($bmp.GetHicon()) }
    catch { return [System.Drawing.SystemIcons]::Shield }
}

function Get-WindowsDefenderIcon {
    <#
    Intenta extraer el icono oficial de Windows Defender desde varios
    ejecutables del sistema. Devuelve el Icon o $null si no lo encuentra.
    #>
    $rutas = @(
        "$env:ProgramFiles\Windows Defender\MSASCui.exe",
        "$env:ProgramFiles\Windows Defender\MpCmdRun.exe",
        "$env:windir\System32\SecurityHealthSystray.exe",
        "$env:windir\System32\SecurityHealthService.exe"
    )
    foreach ($r in $rutas) {
        try {
            if (Test-Path $r) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($r)
                if ($null -ne $icon) {
                    Write-AppLog "Icono oficial cargado desde: $r" "INFO"
                    return $icon
                }
            }
        } catch { }
    }
    Write-AppLog "No se pudo extraer icono oficial. Usando icono dibujado." "WARN"
    return $null
}

# Intentar obtener el icono oficial de Windows Defender
$script:OfficialDefenderIcon = Get-WindowsDefenderIcon

# Asignar iconos por estado
# - ACTIVO: usa el icono oficial si esta disponible, si no el escudo verde.
# - DESACTIVADO: escudo rojo.
# - PARCIAL: escudo naranja.
$script:IconOk      = if ($null -ne $script:OfficialDefenderIcon) { $script:OfficialDefenderIcon } else { New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(0, 200, 100)) }
$script:IconBad     = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 40, 80))
$script:IconPartial = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 140, 0))

function Update-TrayIcon {
    <#
    Aplica el icono y tooltip correcto segun el estado de Defender.
    Se llama desde Update-PanelStatusUI y desde los handlers de acciones.
    #>
    param([string]$Estado)
    if ($null -eq $script:notifyIcon) { return }
    try {
        switch ($Estado) {
            "ACTIVO"      { $script:notifyIcon.Icon = $script:IconOk;      $script:notifyIcon.Text = "Windows Defender - ACTIVADO" }
            "DESACTIVADO" { $script:notifyIcon.Icon = $script:IconBad;     $script:notifyIcon.Text = "Windows Defender - DESACTIVADO" }
            "PARCIAL"     { $script:notifyIcon.Icon = $script:IconPartial; $script:notifyIcon.Text = "Windows Defender - PARCIAL" }
            default       { $script:notifyIcon.Icon = $script:IconPartial; $script:notifyIcon.Text = "Windows Defender" }
        }
    } catch { }
}

# ============================================================================
# SECCION 9 - ESTADO RAPIDO
# Determina el estado actual de Defender consultando servicios, procesos
# y politicas del registro. Retorna "ACTIVO", "PARCIAL" o "DESACTIVADO".
# ============================================================================

function Test-DefenderPolicyDisabled {
    <#
    Comprueba si existe una politica de grupo que desactiva Defender.
    Revisa DisableAntiSpyware y DisableAntiVirus en el registro.
    #>
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (-not (Test-Path $regPath)) { return $false }
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($null -ne $props) {
            if ($null -ne $props.DisableAntiSpyware -and [int]$props.DisableAntiSpyware -eq 1) { return $true }
            if ($null -ne $props.DisableAntiVirus   -and [int]$props.DisableAntiVirus   -eq 1) { return $true }
        }
    } catch { }
    return $false
}

function Test-RTPDisabled {
    <#
    Comprueba si la proteccion en tiempo real esta desactivada por politica.
    Revisa las 2 rutas posibles del registro.
    #>
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
                     "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection")) {
        if (Test-Path $p) {
            $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($null -ne $v -and $null -ne $v.DisableRealtimeMonitoring -and [int]$v.DisableRealtimeMonitoring -eq 1) { return $true }
        }
    }
    return $false
}

function Get-QuickStatus {
    <#
    Determina el estado global de Defender.
    - ACTIVO:      servicio + motor corriendo + RTP ON + sin politica.
    - DESACTIVADO: servicio Y motor detenidos.
    - PARCIAL:     cualquier estado intermedio.
    Devuelve un objeto con todas las propiedades booleanas y el estado.
    #>
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $running = ($null -ne $svc) -and ($svc.Status -eq 'Running')

    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $engineRunning = ($null -ne $proc)

    $rtpDisabled = Test-RTPDisabled
    $hasPolicy = Test-DefenderPolicyDisabled

    $isActive = $running -and $engineRunning -and (-not $rtpDisabled) -and (-not $hasPolicy)
    $isFullyDisabled = (-not $running) -and (-not $engineRunning)

    $estado = "PARCIAL"
    if ($isActive) { $estado = "ACTIVO" }
    elseif ($isFullyDisabled) { $estado = "DESACTIVADO" }

    return [PSCustomObject]@{
        ServiceRunning            = $running
        EngineRunning             = $engineRunning
        RealTimeProtectionEnabled = -not $rtpDisabled
        HasPolicy                 = $hasPolicy
        IsActive                  = $isActive
        IsFullyDisabled           = $isFullyDisabled
        Estado                    = $estado
    }
}

# ============================================================================
# SECCION 10 - UTILIDADES
# ============================================================================

function Test-Admin {
    <#
    Devuelve $true si el proceso actual se ejecuta con privilegios
    de Administrador.
    #>
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StringHash {
    <#
    Genera un hash SHA256 de 16 caracteres del texto indicado.
    Se usa para almacenar la contrasena del modo kiosco sin guardarla
    en texto plano.
    #>
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
}

# ============================================================================
# SECCION 11 - DESACTIVAR DEFENDER (TOTAL - 9 PASOS)
# Ejecuta la desactivacion completa: preferencias, politicas, servicios,
# registro, procesos y verificacion con reintento.
# ============================================================================
function Disable-Defender {
    <#
    Desactiva Windows Defender completamente:
      1. Desactiva 15+ preferencias via Set-MpPreference.
      2. Borra las politicas de grupo (4 rutas).
      3. Recrea politicas de bloqueo permanente.
      4. Detiene los 8 servicios con sc config disabled.
      5. Escribe Start=4 en el registro de los 8 servicios.
      6. Mata los 6 procesos del motor con taskkill.
      7. Espera 4 segundos y verifica.
      8. Reintenta detener si Windows reinicio el servicio.
      9. Reporta el resultado final.
    Devuelve un string con el log de todo el proceso.
    #>
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Comprobar Tamper Protection
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                [void]$log.Add("Desactivala manualmente en Seguridad de Windows.")
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Desactivacion TOTAL iniciada" "INFO"

    # PASO 1: Desactivar preferencias
    [void]$log.Add("[1/9] Desactivando TODAS las protecciones...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        $prefs = @(
            @{N="DisableRealtimeMonitoring";        V=$true},
            @{N="DisableBehaviorMonitoring";        V=$true},
            @{N="DisableIOAVProtection";            V=$true},
            @{N="DisableScriptScanning";            V=$true},
            @{N="DisableBlockAtFirstSeen";          V=$true},
            @{N="DisableArchiveScanning";           V=$true},
            @{N="DisableEmailScanning";             V=$true},
            @{N="DisableIntrusionPreventionSystem"; V=$true},
            @{N="DisableRemovableDriveScanning";    V=$true},
            @{N="DisableScanningNetworkFiles";      V=$true},
            @{N="DisableCatchupQuickScan";          V=$true},
            @{N="DisableCatchupFullScan";           V=$true}
        )
        foreach ($p in $prefs) {
            try { Set-MpPreference @{ $p.N = $p.V } -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { Set-MpPreference -MAPSReporting Disabled -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -PUAProtection Disabled -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -EnableNetworkProtection Disabled -Force -ErrorAction SilentlyContinue } catch { }
        [void]$log.Add("       15+ protecciones desactivadas")
    }

    # PASO 2: Borrar politicas de grupo
    [void]$log.Add("[2/9] Eliminando politicas de grupo...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }

    # PASO 3: Recrear politicas de bloqueo
    [void]$log.Add("[3/9] Estableciendo politicas de bloqueo...")
    $dp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $dp)) { New-Item -Path $dp -Force | Out-Null }
    Set-ItemProperty -Path $dp -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dp -Name "DisableAntiVirus"   -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    $rtp = "$dp\Real-Time Protection"
    if (-not (Test-Path $rtp)) { New-Item -Path $rtp -Force | Out-Null }
    foreach ($v in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                     "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning",
                     "DisableRawWriteNotification","DisableAsyncScan")) {
        Set-ItemProperty -Path $rtp -Name $v -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    $spynet = "$dp\Spynet"
    if (-not (Test-Path $spynet)) { New-Item -Path $spynet -Force | Out-Null }
    Set-ItemProperty -Path $spynet -Name "SpynetReporting"       -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $spynet -Name "SubmitSamplesConsent"  -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    # PASO 4: Detener servicios
    [void]$log.Add("[4/9] Deteniendo 8 servicios...")
    $svcs = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    foreach ($s in $svcs) {
        try {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            $null = & sc.exe stop $s 2>&1
            $null = & sc.exe config $s start= disabled 2>&1
        } catch { }
    }

    # PASO 5: Registro Start=4
    [void]$log.Add("[5/9] Escribiendo Start=4 en registro...")
    $paths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Sense",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisDrv",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Wdfilter",
        "HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService",
        "HKLM:\SYSTEM\CurrentControlSet\Services\wscsvc"
    )
    foreach ($sp in $paths) {
        try {
            if (Test-Path $sp) {
                Set-ItemProperty -Path $sp -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    # PASO 6: Matar procesos
    [void]$log.Add("[6/9] Matando procesos del motor...")
    foreach ($proc in @("MsMpEng.exe","NisSrv.exe","SecurityHealthService.exe",
                        "SecurityHealthSystray.exe","MpCmdRun.exe","MpCopyAccelerator.exe")) {
        try { $null = & taskkill.exe /F /IM $proc 2>&1 } catch { }
    }

    # PASO 7: Esperar y verificar
    [void]$log.Add("[7/9] Verificando...")
    Wait-WithDoEvents -Milliseconds 4000

    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        # PASO 8: Reintentar
        [void]$log.Add("[8/9] Reintentando detener WinDefend...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        $null = & taskkill.exe /F /IM MsMpEng.exe 2>&1
        try {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch { }
        $null = & sc.exe config WinDefend start= disabled 2>&1
        Wait-WithDoEvents -Milliseconds 2000
    } else {
        [void]$log.Add("[8/9] WinDefend ya detenido.")
    }

    # PASO 9: Resultado
    [void]$log.Add("[9/9] Resultado final...")
    $svcFin  = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $svcOk = ($null -eq $svcFin) -or ($svcFin.Status -ne 'Running')
    $procOk = ($null -eq $procFin)

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO ===")
    [void]$log.Add("  Servicio WinDefend: $(if($svcOk){'DETENIDO'}else{'CORRIENDO'})")
    [void]$log.Add("  Proceso MsMpEng:    $(if($procOk){'DETENIDO'}else{'CORRIENDO'})")

    if ($svcOk -and $procOk) {
        [void]$log.Add("")
        [void]$log.Add("[OK] DESACTIVACION TOTAL EXITOSA.")
    } else {
        [void]$log.Add("")
        [void]$log.Add("[!] Aun activo. REINICIA EL EQUIPO para completar.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog "Desactivacion terminada" "INFO"
    return ($log -join "`n")
}

# ============================================================================
# SECCION 12 - ACTIVAR DEFENDER (TOTAL - 9 PASOS)
# Ejecuta la activacion completa: registro, politicas, servicios,
# preferencias, tamper, systray y verificacion.
# ============================================================================
function Enable-Defender {
    <#
    Activa Windows Defender completamente:
      1. Restaura Start=2 en los 8 servicios del registro.
      2. Elimina todas las politicas de bloqueo (5 rutas).
      3. Limpia las claves de Real-Time Protection en registro.
      4. Inicia WdNisSvc, Sense, SecurityHealthService, wscsvc.
      5. Inicia WinDefend (servicio principal).
      6. Activa 15+ preferencias + MAPS Advanced + Samples + PUA + Network.
      7. Intenta activar Tamper Protection.
      8. Lanza SecurityHealthSystray.exe (icono oficial en bandeja).
      9. Verifica servicio + motor + RTP y reporta el resultado.
    Devuelve un string con el log de todo el proceso.
    #>
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AppLog "Activacion COMPLETA iniciada" "INFO"

    # PASO 1: Restaurar Start=2
    [void]$log.Add("[1/9] Restaurando Start=2 en registro...")
    $servicios = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    foreach ($s in $servicios) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (Test-Path $p) {
            try {
                Set-ItemProperty -Path $p -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                [void]$log.Add("       $s -> Start=2 (Automatic)")
            } catch { }
        }
    }

    # PASO 2: Eliminar politicas
    [void]$log.Add("[2/9] Eliminando politicas de bloqueo...")
    $rutasPoliticas = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates"
    )
    foreach ($rp in $rutasPoliticas) {
        try {
            if (Test-Path $rp) {
                Remove-Item -Path $rp -Recurse -Force -ErrorAction SilentlyContinue
                [void]$log.Add("       Eliminado: $rp")
            }
        } catch { }
    }
    foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                      "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try {
            if (Test-Path "$rp\Windows Defender") {
                Remove-Item -Path "$rp\Windows Defender" -Recurse -Force -ErrorAction SilentlyContinue
                [void]$log.Add("       Eliminado: $rp\Windows Defender")
            }
        } catch { }
    }

    # PASO 3: Limpiar claves RTP en registro de trabajo
    [void]$log.Add("[3/9] Limpiando claves de RTP en registro...")
    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    if (Test-Path $rtWk) {
        foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                         "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning",
                         "DisableRawWriteNotification","DisableAsyncScan")) {
            try { Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("       Claves RTP limpiadas.")
    }

    # PASO 4: Iniciar servicios relacionados
    [void]$log.Add("[4/9] Iniciando servicios relacionados...")
    foreach ($s in @("WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
        try {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
                $null = & sc.exe config $s start= auto 2>&1
                Start-Service -Name $s -ErrorAction SilentlyContinue
                [void]$log.Add("       $s -> INICIADO")
            }
        } catch { }
    }

    # PASO 5: Iniciar WinDefend
    [void]$log.Add("[5/9] Iniciando WinDefend...")
    try {
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= auto 2>&1
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("       WinDefend -> INICIADO")
    } catch { }

    Wait-WithDoEvents -Milliseconds 3000

    # PASO 6: Activar TODAS las preferencias
    [void]$log.Add("[6/9] Activando TODAS las protecciones...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        $prefs = @(
            @{N="DisableRealtimeMonitoring";        V=$false},
            @{N="DisableBehaviorMonitoring";        V=$false},
            @{N="DisableIOAVProtection";            V=$false},
            @{N="DisableScriptScanning";            V=$false},
            @{N="DisableBlockAtFirstSeen";          V=$false},
            @{N="DisableArchiveScanning";           V=$false},
            @{N="DisableEmailScanning";             V=$false},
            @{N="DisableIntrusionPreventionSystem"; V=$false},
            @{N="DisableRemovableDriveScanning";    V=$false},
            @{N="DisableScanningNetworkFiles";      V=$false},
            @{N="DisableCatchupQuickScan";          V=$false},
            @{N="DisableCatchupFullScan";           V=$false},
            @{N="DisableRestorePoint";              V=$false}
        )
        foreach ($p in $prefs) {
            try { Set-MpPreference @{ $p.N = $p.V } -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("       15+ protecciones activadas")

        # Nube MAPS al maximo
        try {
            Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
            Set-MpPreference -CloudBlockLevel High -Force -ErrorAction SilentlyContinue
            Set-MpPreference -CloudExtendedTimeout 50 -Force -ErrorAction SilentlyContinue
            [void]$log.Add("       Nube (MAPS): Advanced + BlockLevel High")
        } catch { }

        # Envio de muestras
        try {
            Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction SilentlyContinue
            [void]$log.Add("       Envio de muestras: Safe samples")
        } catch { }

        # PUA Protection
        try {
            Set-MpPreference -PUAProtection Enabled -Force -ErrorAction SilentlyContinue
            [void]$log.Add("       PUA Protection: Enabled")
        } catch { }

        # Network Protection
        try {
            Set-MpPreference -EnableNetworkProtection Enabled -Force -ErrorAction SilentlyContinue
            [void]$log.Add("       Network Protection: Enabled")
        } catch { }

        # File Hash Computation
        try {
            Set-MpPreference -EnableFileHashComputation $true -Force -ErrorAction SilentlyContinue
        } catch { }
    } else {
        [void]$log.Add("       [AVISO] Set-MpPreference no disponible.")
    }

    # PASO 7: Tamper Protection
    [void]$log.Add("[7/9] Intentando activar Tamper Protection...")
    try {
        $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
        Set-ItemProperty -Path $tpPath -Name "TamperProtection"       -Value 5 -Type DWord  -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $tpPath -Name "TamperProtectionSource" -Value 1 -Type String -Force -ErrorAction SilentlyContinue

        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 800
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 3000

        $verify = $false
        try { $verify = (Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected } catch { }
        if ($verify) {
            [void]$log.Add("       Tamper Protection: ACTIVADO")
        } else {
            [void]$log.Add("       Tamper Protection: RECHAZADO (activar manualmente)")
        }
    } catch {
        [void]$log.Add("       Tamper Protection: Error")
    }

    # PASO 8: Lanzar SecurityHealthSystray
    [void]$log.Add("[8/9] Restaurando icono oficial en bandeja...")
    try {
        $systray = "$env:windir\System32\SecurityHealthSystray.exe"
        if (Test-Path $systray) {
            Start-Process -FilePath $systray -ErrorAction SilentlyContinue
            [void]$log.Add("       SecurityHealthSystray.exe lanzado")
        }
    } catch { }

    # PASO 9: Verificar
    [void]$log.Add("[9/9] Verificando resultado...")
    Wait-WithDoEvents -Milliseconds 2000

    $svcFin  = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $svcOk  = ($null -ne $svcFin) -and ($svcFin.Status -eq 'Running')
    $procOk = ($null -ne $procFin)

    $rtpOk = $false
    try { $rtpOk = (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch { }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO ===")
    [void]$log.Add("  Servicio WinDefend: $(if($svcOk){'CORRIENDO'}else{'DETENIDO'})")
    [void]$log.Add("  Proceso MsMpEng:    $(if($procOk){'CORRIENDO'}else{'DETENIDO'})")
    [void]$log.Add("  Tiempo real:        $(if($rtpOk){'ACTIVADO'}else{'DESACTIVADO'})")

    if ($svcOk -and $procOk -and $rtpOk) {
        [void]$log.Add("")
        [void]$log.Add("[OK] ACTIVACION TOTAL COMPLETADA.")
    } else {
        [void]$log.Add("")
        [void]$log.Add("[!] Activacion parcial. Reinicia el equipo si es necesario.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog "Activacion terminada" "INFO"
    return ($log -join "`n")
}

# ============================================================================
# SECCION 13 - DIALOGO MODO KIOSCO
# Pide la contrasena al usuario antes de abrir el panel si el kiosco
# esta activo. Compara el hash SHA256 con el guardado.
# ============================================================================
function Test-KioskPassword {
    <#
    Si el modo kiosco esta activo, muestra un dialogo pidiendo la
    contrasena. Devuelve $true si la contrasena es correcta o si
    el modo kiosco esta desactivado.
    #>
    if (-not $script:IsKioskMode) { return $true }
    if ([string]::IsNullOrEmpty($script:CfgKioskHash)) { return $true }

    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"
    $dlg.ClientSize = New-Object System.Drawing.Size(360, 160)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Introduce la " + $script:TXT_PWD + ":"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(320, 20)
    $lbl.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.PasswordChar = '*'
    $txt.Location = New-Object System.Drawing.Point(15, 40)
    $txt.Size = New-Object System.Drawing.Size(330, 25)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txt)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Aceptar"
    $btnOk.Location = New-Object System.Drawing.Point(155, 80)
    $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.FlatStyle = "Flat"
    $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.BackColor = $script:Colors.AccentGreen
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Location = New-Object System.Drawing.Point(255, 80)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.BackColor = $script:Colors.AccentRed
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnCancel)

    $btnOk.Add_Click({
        $h = Get-StringHash $txt.Text
        if ($h -eq $script:CfgKioskHash) {
            $script:KioskOk = $true
            $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Contrase" + [char]0x00F1 + "a incorrecta.","Acceso","OK","Error") | Out-Null
            $txt.Clear()
            $txt.Focus()
        }
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.AcceptButton = $btnOk

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:KioskOk
}

# ============================================================================
# SECCION 14 - BOTONES NEON
# Crea botones con estilo flat y colores neon. Devuelve el control Button
# listo para agregarse a un formulario.
# ============================================================================
function New-NeonButton {
    param([string]$Texto, [System.Drawing.Color]$Color, [System.Drawing.Color]$Hover,
          [int]$X, [int]$Y, [int]$Ancho = 180, [int]$Alto = 30)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Texto
    $b.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $Color
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Color
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = "Hand"
    $b.Tag = @{ Normal = $Color; Hover = $Hover }
    return $b
}

function Set-NeonButtonState {
    <#
    Activa o desactiva visualmente un boton neon cambiando su color.
    Se usa cuando un boton no aplica segun el estado de Defender.
    #>
    param([System.Windows.Forms.Button]$Boton, [bool]$Habilitado)
    if ($null -eq $Boton) { return }
    if ($Habilitado) {
        $Boton.BackColor = $Boton.Tag.Normal
        $Boton.ForeColor = [System.Drawing.Color]::White
        $Boton.FlatAppearance.BorderColor = $Boton.Tag.Normal
        $Boton.FlatAppearance.MouseOverBackColor = $Boton.Tag.Hover
        $Boton.Cursor = "Hand"
    } else {
        $Boton.BackColor = $script:Colors.BtnDisabled
        $Boton.ForeColor = $script:Colors.BtnDisabledT
        $Boton.FlatAppearance.BorderColor = $script:Colors.BtnDisabled
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnDisabled
        $Boton.Cursor = "Default"
    }
}

# ============================================================================
# SECCION 15 - HISTORIAL DE OPERACIONES
# Mantiene las ultimas 20 operaciones en memoria.
# ============================================================================
$script:EventHistory = New-Object System.Collections.ArrayList

function Add-History {
    <#
    Anade una entrada al historial (max 20).
    Formato: Hora, Accion, Resultado, Segundos.
    #>
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    try {
        $entry = [PSCustomObject]@{ Hora=(Get-Date); Accion=$Accion; Resultado=$Resultado; Segundos=$Segundos }
        [void]$script:EventHistory.Insert(0, $entry)
        while ($script:EventHistory.Count -gt 20) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
    } catch { }
}

# ============================================================================
# SECCION 16 - INFORME DETALLADO (DIAGNOSTICO)
# Construye una lista de objetos con toda la informacion del sistema:
# servicios, procesos, modulos, registro, politicas y estado global.
# ============================================================================
function Get-DiagnosticReport {
    <#
    Devuelve una lista de objetos {Item, Status, Detail, Color}.
    Secciones:
      - SERVICIOS DE DEFENDER: 8 servicios con estado + modo inicio.
      - PROCESOS: 4 procesos del motor con PID.
      - MODULOS DE PROTECCION: 9 modulos via Get-MpComputerStatus.
      - REGISTRO (Start): 8 valores Start con traduccion.
      - POLITICAS: bloqueante SI/NO.
      - ESTADO GLOBAL: resultado final (ACTIVO/PARCIAL/DESACTIVADO).
    #>
    $r = New-Object System.Collections.ArrayList

    # --- SERVICIOS ---
    [void]$r.Add([PSCustomObject]@{Item="=== SERVICIOS DE DEFENDER ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})

    $serviciosDefender = @(
        @{Nombre="WinDefend";             Desc="Servicio principal del antivirus"},
        @{Nombre="WdNisSvc";              Desc="Inspeccion de red"},
        @{Nombre="Sense";                 Desc="Deteccion de intrusiones (EDR)"},
        @{Nombre="WdNisDrv";              Desc="Driver de inspeccion de red"},
        @{Nombre="WdBoot";                Desc="Driver de arranque"},
        @{Nombre="Wdfilter";              Desc="Driver de filtro"},
        @{Nombre="SecurityHealthService"; Desc="Seguridad de Windows (UI)"},
        @{Nombre="wscsvc";                Desc="Centro de seguridad"}
    )

    foreach ($s in $serviciosDefender) {
        $svc = Get-Service -Name $s.Nombre -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            [void]$r.Add([PSCustomObject]@{
                Item="  " + $s.Nombre
                Status="NO EXISTE"
                Detail=$s.Desc
                Color=$script:Colors.TextMuted
            })
            continue
        }
        $running = ($svc.Status -eq 'Running')
        $startMode = "?"
        try {
            $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($s.Nombre)'" -ErrorAction SilentlyContinue
            if ($null -ne $wmiSvc) { $startMode = $wmiSvc.StartMode }
        } catch { }
        $estado = if ($running) { "ACTIVADO" } else { "DESACTIVADO" }
        $color = if ($running) { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$r.Add([PSCustomObject]@{
            Item="  " + $s.Nombre
            Status="$estado ($startMode)"
            Detail=$s.Desc
            Color=$color
        })
    }

    # --- PROCESOS ---
    [void]$r.Add([PSCustomObject]@{Item="=== PROCESOS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})

    foreach ($p in @("MsMpEng","NisSrv","SecurityHealthService","SecurityHealthSystray")) {
        $proc = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            [void]$r.Add([PSCustomObject]@{
                Item="  " + $p + ".exe"
                Status="CORRIENDO"
                Detail="PID $($proc.Id)"
                Color=$script:Colors.Bad
            })
        } else {
            [void]$r.Add([PSCustomObject]@{
                Item="  " + $p + ".exe"
                Status="DETENIDO"
                Detail="No esta corriendo"
                Color=$script:Colors.Ok
            })
        }
    }

    # --- MODULOS ---
    [void]$r.Add([PSCustomObject]@{Item="=== MODULOS DE PROTECCION ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})

    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $modulos = @(
                @{N="Antivirus habilitado";   V=$st.AntivirusEnabled},
                @{N="Antispyware habilitado"; V=$st.AntispywareEnabled},
                @{N="Servicio AM";            V=$st.AMServiceEnabled},
                @{N="Proteccion tiempo real"; V=$st.RealTimeProtectionEnabled},
                @{N="Monitor comportamiento"; V=$st.BehaviorMonitorEnabled},
                @{N="IOAV Protection";        V=$st.IoavProtectionEnabled},
                @{N="On-Access Protection";   V=$st.OnAccessProtectionEnabled},
                @{N="Inspeccion red (NIS)";   V=$st.NISEnabled},
                @{N="Tamper Protection";      V=$st.IsTamperProtected}
            )
            foreach ($m in $modulos) {
                $c = if ($m.V -eq $true) { $script:Colors.Ok } elseif ($m.V -eq $false) { $script:Colors.Bad } else { $script:Colors.Neutral }
                $txt = if ($m.V -eq $true) { "ACTIVADO" } elseif ($m.V -eq $false) { "DESACTIVADO" } else { "?" }
                [void]$r.Add([PSCustomObject]@{Item="  " + $m.N; Status=$txt; Detail=""; Color=$c})
            }
        } catch { }
    }

    # --- REGISTRO ---
    [void]$r.Add([PSCustomObject]@{Item="=== REGISTRO (Start) ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})

    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        $startVal = "N/A"
        try {
            if (Test-Path $p) {
                $v = (Get-ItemProperty -Path $p -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($null -ne $v) {
                    $startVal = switch ([int]$v) {
                        0 { "0 (Boot)" }
                        1 { "1 (System)" }
                        2 { "2 (Automatic) ACTIVO" }
                        3 { "3 (Manual)" }
                        4 { "4 (Disabled) DESACTIVADO" }
                        default { "$v" }
                    }
                }
            }
        } catch { }
        $c = if ($startVal -match "4 \(Disabled") { $script:Colors.Bad } elseif ($startVal -match "2 \(Automatic") { $script:Colors.Ok } else { $script:Colors.TextMuted }
        [void]$r.Add([PSCustomObject]@{Item="  Start $s"; Status=$startVal; Detail=""; Color=$c})
    }

    # --- POLITICAS ---
    [void]$r.Add([PSCustomObject]@{Item="=== POLITICAS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $hp = Test-DefenderPolicyDisabled
    [void]$r.Add([PSCustomObject]@{
        Item="  Politica bloqueante"
        Status=$(if($hp){"SI - BLOQUEA"}else{"NO"})
        Detail="HKLM\SOFTWARE\Policies\Microsoft\Windows Defender"
        Color=$(if($hp){$script:Colors.Bad}else{$script:Colors.Ok})
    })

    # --- ESTADO GLOBAL ---
    [void]$r.Add([PSCustomObject]@{Item="=== ESTADO GLOBAL ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $q = Get-QuickStatus
    $colorGlobal = switch ($q.Estado) {
        "ACTIVO"      { $script:Colors.Ok }
        "PARCIAL"     { $script:Colors.Warn }
        "DESACTIVADO" { $script:Colors.Bad }
        default       { $script:Colors.Neutral }
    }
    [void]$r.Add([PSCustomObject]@{Item="  RESULTADO FINAL"; Status=$q.Estado; Detail=""; Color=$colorGlobal})

    return $r
}

# ============================================================================
# SECCION 17 - DIALOGO DE DIAGNOSTICO
# Muestra la lista completa del diagnostico en un ListView con colores.
# ============================================================================
function Show-DiagnosticsDialog {
    <#
    Ventana modal con el diagnostico detallado del sistema.
    Botones: Refrescar, Copiar, Cerrar.
    #>
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Diagnostico del Sistema"
    $dlg.ClientSize = New-Object System.Drawing.Size(800, 620)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

    # Cabecera
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60
    $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "DIAGNOSTICO COMPLETO"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblH)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Servicios + Procesos + Modulos + Registro + Politicas"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 200)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(17, 38)
    $header.Controls.Add($lblSub)

    # ListView
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 75)
    $lv.Size = New-Object System.Drawing.Size(770, 470)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    $lv.Anchor = "Top,Left,Right,Bottom"
    [void]$lv.Columns.Add("Elemento", 330)
    [void]$lv.Columns.Add("Estado", 230)
    [void]$lv.Columns.Add("Detalle", 200)
    $dlg.Controls.Add($lv)

    # Botones
    $btnRef  = New-NeonButton "Refrescar" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15  555 140 32
    $btnCopy = New-NeonButton "Copiar"    $script:Colors.AccentCyan  $script:Colors.AccentCyanH  165 555 140 32
    $btnCerr = New-NeonButton "Cerrar"    $script:Colors.Neutral     $script:Colors.TextMuted    645 555 140 32
    $dlg.Controls.Add($btnRef)
    $dlg.Controls.Add($btnCopy)
    $dlg.Controls.Add($btnCerr)

    $script:DiagLv = $lv

    # Funcion interna para cargar el listado
    $cargarDiag = {
        $script:DiagLv.Items.Clear()
        foreach ($row in (Get-DiagnosticReport)) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$row.Item)
            [void]$it.SubItems.Add([string]$row.Status)
            [void]$it.SubItems.Add([string]$row.Detail)
            if ($null -ne $row.Color) {
                $it.ForeColor = $row.Color
                $it.UseItemStyleForSubItems = $true
            }
            [void]$script:DiagLv.Items.Add($it)
        }
    }
    & $cargarDiag

    $btnRef.Add_Click({ & $cargarDiag })

    $btnCopy.Add_Click({
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("DIAGNOSTICO - WINDOWS DEFENDER")
        [void]$sb.AppendLine(("Fecha: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)))
        [void]$sb.AppendLine("================================================================")
        foreach ($it in $script:DiagLv.Items) {
            $txt = $it.Text + " | " + $it.SubItems[1].Text + " | " + $it.SubItems[2].Text
            [void]$sb.AppendLine($txt)
        }
        try {
            [System.Windows.Forms.Clipboard]::SetText($sb.ToString())
            [System.Windows.Forms.MessageBox]::Show("Diagnostico copiado al portapapeles.","OK","OK","Information") | Out-Null
        } catch { }
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 18 - DIALOGO DE HISTORIAL
# Muestra las ultimas 20 operaciones realizadas.
# ============================================================================
function Show-HistoryDialog {
    <#
    Ventana con ListView mostrando el historial de operaciones con
    colores segun el resultado (verde OK, rojo error).
    #>
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial de operaciones"
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 480)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "HISTORIAL (ultimas 20)"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 65)
    $lv.Size = New-Object System.Drawing.Size(690, 360)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 170)
    [void]$lv.Columns.Add("Accion", 150)
    [void]$lv.Columns.Add("Resultado", 290)
    [void]$lv.Columns.Add("Seg", 70)
    $dlg.Controls.Add($lv)

    foreach ($e in $script:EventHistory) {
        $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$it.SubItems.Add($e.Accion)
        [void]$it.SubItems.Add($e.Resultado)
        [void]$it.SubItems.Add(("{0:N2}" -f $e.Segundos))
        if ($e.Resultado -match "OK|activado|desactivado") { $it.ForeColor = $script:Colors.Ok }
        elseif ($e.Resultado -match "parcial|ERROR") { $it.ForeColor = $script:Colors.Bad }
        [void]$lv.Items.Add($it)
    }

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 565 440 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 19 - REPARACION PROFUNDA
# Consola con log en vivo para ejecutar los 5 comandos de reparacion.
# ============================================================================
$script:RepairConsole = $null

function Invoke-ConsoleCmd {
    <#
    Ejecuta un comando en cmd.exe redirigiendo la salida al TextBox
    de la consola. Se muestra linea por linea en tiempo real.
    #>
    param([string]$Comando)
    if ($null -eq $script:RepairConsole -or $script:RepairConsole.IsDisposed) { return }
    $c = $script:RepairConsole
    $c.AppendText("`r`n> $Comando`r`n")
    $c.SelectionStart = $c.Text.Length
    $c.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = "cmd.exe"
        $proc.StartInfo.Arguments = "/c $Comando"
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.CreateNoWindow = $true
        $proc.Start()
        while (-not $proc.HasExited) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -ne $line) {
                $c.AppendText("$line`r`n")
                $c.SelectionStart = $c.Text.Length
                $c.ScrollToCaret()
                [System.Windows.Forms.Application]::DoEvents()
            }
            Start-Sleep -Milliseconds 20
        }
        $out = $proc.StandardOutput.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($out)) { $c.AppendText($out) }
        $err = $proc.StandardError.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($err)) { $c.AppendText("$err") }
        $proc.Dispose()
        $c.AppendText("[OK]`r`n")
    } catch {
        $c.AppendText("ERROR: $($_.Exception.Message)`r`n")
    }
}

function Show-DeepRepairDialog {
    <#
    Ventana de reparacion con 6 botones individuales (Borrar Politicas,
    Servicios, gpupdate, sfc, DISM, Matar MsMpEng) y un boton
    REPARAR TODO que ejecuta la secuencia completa.
    #>
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Reparacion Profunda"
    $dlg.ClientSize = New-Object System.Drawing.Size(920, 660)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60
    $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "REPARACION PROFUNDA"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblH)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Ejecuta los comandos en una consola con log en vivo"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 200)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(17, 38)
    $header.Controls.Add($lblSub)

    $console = New-Object System.Windows.Forms.TextBox
    $console.Multiline = $true
    $console.ScrollBars = "Both"
    $console.ReadOnly = $true
    $console.WordWrap = $false
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.Location = New-Object System.Drawing.Point(15, 75)
    $console.Size = New-Object System.Drawing.Size(890, 475)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)
    $script:RepairConsole = $console

    # Botones de acciones individuales
    $btnReg  = New-NeonButton "1. Borrar Politicas"  $script:Colors.AccentRed    $script:Colors.AccentRedH    15  560 175 34
    $btnSvc  = New-NeonButton "2. Servicios"         $script:Colors.AccentAmber  $script:Colors.AccentAmberH  200 560 145 34
    $btnGpu  = New-NeonButton "3. gpupdate"          $script:Colors.AccentPurple $script:Colors.AccentPurpH   355 560 140 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"      $script:Colors.AccentBlue   $script:Colors.AccentBlueH   505 560 145 34
    $btnDISM = New-NeonButton "5. DISM Restore"      $script:Colors.AccentCyan   $script:Colors.AccentCyanH   660 560 150 34
    $btnKill = New-NeonButton "Matar MsMpEng"        $script:Colors.AccentRed    $script:Colors.AccentRedH    815 560 090 34

    $btnTodo = New-NeonButton "REPARAR TODO AUTOMATICAMENTE" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 605 400 40
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 815 605 90 40

    foreach ($b in @($btnReg,$btnSvc,$btnGpu,$btnSFC,$btnDISM,$btnKill,$btnTodo,$btnCerr)) {
        $dlg.Controls.Add($b)
    }

    $btnReg.Add_Click({
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`" /f"
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies`" /f"
        Invoke-ConsoleCmd "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Policies`" /f"
    })
    $btnSvc.Add_Click({
        foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
            Invoke-ConsoleCmd "sc config $s start= auto"
            Invoke-ConsoleCmd "sc start $s"
        }
    })
    $btnGpu.Add_Click({ Invoke-ConsoleCmd "gpupdate /force" })
    $btnSFC.Add_Click({ Invoke-ConsoleCmd "sfc /scannow" })
    $btnDISM.Add_Click({ Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth" })
    $btnKill.Add_Click({
        Invoke-ConsoleCmd "taskkill /F /IM MsMpEng.exe"
        Invoke-ConsoleCmd "taskkill /F /IM NisSrv.exe"
    })

    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n==============================================`r`n")
        $c.AppendText("      REPARACION AUTOMATICA COMPLETA`r`n")
        $c.AppendText("==============================================`r`n")
        $c.AppendText("Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")

        $c.AppendText("`r`n[PASO 1] Borrando politicas...`r`n")
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`" /f"

        $c.AppendText("`r`n[PASO 2] gpupdate /force...`r`n")
        Invoke-ConsoleCmd "gpupdate /force"

        $c.AppendText("`r`n[PASO 3] Reiniciando servicios...`r`n")
        foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
            Invoke-ConsoleCmd "sc config $s start= auto"
            Invoke-ConsoleCmd "sc start $s"
        }

        $c.AppendText("`r`n[PASO 4] Reactivando protecciones...`r`n")
        try {
            if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
                Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -DisableBehaviorMonitoring $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -DisableIOAVProtection $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
                $c.AppendText("  [OK] Preferencias aplicadas.`r`n")
            }
        } catch { $c.AppendText("  [ERR] $($_.Exception.Message)`r`n") }

        $c.AppendText("`r`n[PASO 5] sfc /scannow (puede tardar)...`r`n")
        Invoke-ConsoleCmd "sfc /scannow"

        $c.AppendText("`r`n[PASO 6] DISM RestoreHealth...`r`n")
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"

        $c.AppendText("`r`n==============================================`r`n")
        $c.AppendText("  REPARACION COMPLETADA`r`n")
        $c.AppendText("  REINICIA EL EQUIPO PARA APLICAR LOS CAMBIOS.`r`n")
        $c.AppendText("==============================================`r`n")

        Add-History -Accion "Reparacion Completa" -Resultado "OK" -Segundos 0
        [System.Windows.Forms.MessageBox]::Show("Reparacion completada.`nReinicia el equipo.","OK","OK","Information") | Out-Null
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    $console.AppendText("==============================================`r`n")
    $console.AppendText("  CONSOLA DE REPARACION - DefenderTray v4.3`r`n")
    $console.AppendText("==============================================`r`n")
    $console.AppendText("`r`nPuedes ejecutar cada paso individual o pulsar`r`n")
    $console.AppendText("REPARAR TODO AUTOMATICAMENTE.`r`n`r`n")

    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ============================================================================
# SECCION 20 - DIALOGO DE CONFIGURACION
# Permite activar el modo kiosco y establecer la contrasena.
# ============================================================================
function Show-SettingsDialog {
    <#
    Ventana de configuracion con:
      - Checkbox para activar modo kiosco.
      - Campo de texto para la contrasena.
      - Botones Guardar y Cancelar.
    #>
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"
    $dlg.ClientSize = New-Object System.Drawing.Size(520, 320)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "CONFIGURACION"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $chkKiosk = New-Object System.Windows.Forms.CheckBox
    $chkKiosk.Text = "Modo kiosco (pedir " + $script:TXT_PWD + " al abrir)"
    $chkKiosk.Checked = $script:IsKioskMode
    $chkKiosk.Location = New-Object System.Drawing.Point(20, 70)
    $chkKiosk.Size = New-Object System.Drawing.Size(450, 25)
    $chkKiosk.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkKiosk)

    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = $script:TXT_PWD + ":"
    $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(20, 110)
    $lblPwd.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblPwd)

    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'
    $txtPwd.Location = New-Object System.Drawing.Point(140, 108)
    $txtPwd.Size = New-Object System.Drawing.Size(340, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary
    $txtPwd.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtPwd)

    $lblNota = New-Object System.Windows.Forms.Label
    $lblNota.Text = "Si olvidas la " + $script:TXT_PWD + ", edita config.json y pon KioskMode: false"
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblNota.ForeColor = $script:Colors.TextMuted
    $lblNota.Location = New-Object System.Drawing.Point(20, 150)
    $lblNota.Size = New-Object System.Drawing.Size(470, 40)
    $dlg.Controls.Add($lblNota)

    $btnSave   = New-NeonButton "Guardar"  $script:Colors.AccentGreen  $script:Colors.AccentGreenH 20  220 200 34
    $btnCancel = New-NeonButton "Cancelar" $script:Colors.Neutral      $script:Colors.TextMuted   300 220 180 34
    $dlg.Controls.Add($btnSave)
    $dlg.Controls.Add($btnCancel)

    $btnSave.Add_Click({
        $script:IsKioskMode = $chkKiosk.Checked
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:CfgKioskHash = Get-StringHash $txtPwd.Text
        }
        if (-not $chkKiosk.Checked) { $script:CfgKioskHash = "" }
        Save-AppConfig
        [System.Windows.Forms.MessageBox]::Show("Configuracion guardada.","OK","OK","Information") | Out-Null
        $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 21 - DIALOGO DE AYUDA
# ============================================================================
function Show-HelpDialog {
    <#
    Ventana modal con el manual de uso completo.
    #>
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 520)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "AYUDA"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblH)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = "Vertical"
    $txt.Location = New-Object System.Drawing.Point(15, 65)
    $txt.Size = New-Object System.Drawing.Size(690, 400)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $ayuda = @'
DEFENDER CONTROL v4.3 PRO
===========================

ICONOS DINAMICOS
----------------
El icono de la bandeja cambia de color:
  VERDE   -> ACTIVADO (usa icono oficial de Windows)
  ROJO    -> DESACTIVADO (inactivo)
  NARANJA -> PARCIAL (falta algo)

ACTIVACION COMPLETA
-------------------
Activa 15+ protecciones:
  - Realtime, Behavior, IOAV, Script, BlockAtFirstSeen
  - Archive, Email, Intrusion Prevention, Removable, Network
  - Nube MAPS Advanced + CloudBlockLevel High
  - Envio de muestras (Safe samples)
  - PUA Protection + Network Protection
  - Intenta activar Tamper Protection
  - Lanza el icono oficial de SecurityHealthSystray

DESACTIVACION TOTAL
-------------------
Desactiva 15+ protecciones + 8 servicios + 6 procesos:
  - Set-MpPreference con 12 preferencias en true
  - reg delete de politicas (4 rutas)
  - sc config start= disabled (8 servicios)
  - Start=4 en registro (8 servicios)
  - taskkill de MsMpEng, NisSrv y 4 mas

DIAGNOSTICO
-----------
Muestra detalladamente:
  - Cada servicio (ACTIVADO/DESACTIVADO + modo).
  - Cada proceso (con PID).
  - Cada modulo de proteccion.
  - Cada valor Start del registro.
  - Politicas bloqueantes.
  - Resultado final.

REPARACION PROFUNDA
-------------------
Ejecuta en consola con log en vivo:
  1. reg delete (borrar politicas)
  2. sc config/start (servicios)
  3. gpupdate /force
  4. sfc /scannow
  5. DISM /RestoreHealth
  O bien REPARAR TODO en un solo clic.

MODO KIOSCO
-----------
1. Config -> marcar "Modo kiosco".
2. Escribir contrasena.
3. Guardar.
4. Al abrir el panel pedira la contrasena.

ATAJOS
------
F1   Ayuda
F5   Refrescar
Esc  Cerrar panel

(c) 2026 - Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801 / +53 5 9860911
'@
    $txt.Text = $ayuda
    $dlg.Controls.Add($txt)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 565 475 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 22 - PANEL PRINCIPAL
# Ventana principal con card de estado, botones de accion, barra de menu,
# barra de estado y atajos de teclado.
# ============================================================================

# Variables globales del panel (usadas por los handlers de eventos)
$script:PanelForm          = $null
$script:PanelHeader        = $null
$script:PanelLblValor      = $null
$script:PanelLblDet1       = $null
$script:PanelLblDet2       = $null
$script:PanelLblDet3       = $null
$script:PanelLblReloj      = $null
$script:PanelLblTimer      = $null
$script:PanelBtnActivar    = $null
$script:PanelBtnDesactivar = $null
$script:PanelTimer         = $null
$script:PanelStatusLabel   = $null
$script:IsBusy             = $false
$script:ActionStartTime    = $null
$script:LastActionTime     = 0
$script:LastActionName     = ""

function Update-PanelStatusUI {
    <#
    Actualiza todos los elementos del panel segun el estado actual.
    Cambia color de cabecera, texto de estado, botones habilitados,
    barra de estado e icono de bandeja.
    #>
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }

    $s = Get-QuickStatus
    $diag = "Servicio:$($s.ServiceRunning) | Motor:$($s.EngineRunning) | RTP:$($s.RealTimeProtectionEnabled) | Politica:$($s.HasPolicy)"

    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $false
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "ACTIVADO: Defender protegiendo el equipo."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Ok
        }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Falta proteccion real. Pulsa REPARAR o reinicia."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "PARCIAL: usa REPARAR o reinicia el equipo."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Warn
        }
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        $script:PanelLblDet1.Text = "El antivirus esta completamente inactivo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $false
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "DESACTIVADO: antivirus inactivo."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Bad
        }
    }

    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDet3.Text = "Ultima: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDet3.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    }

    if ($null -ne $script:notifyIcon) {
        Update-TrayIcon -Estado $s.Estado
    }
}

function Start-PanelTimer {
    <#
    Inicia el timer que refresca el panel cada 5 segundos.
    Detiene el timer anterior si existe.
    #>
    if ($null -ne $script:PanelTimer) {
        try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
        $script:PanelTimer = $null
    }
    $script:PanelTimer = New-Object System.Windows.Forms.Timer
    $script:PanelTimer.Interval = 5000
    $script:PanelTimer.Add_Tick({
        if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
        $script:PanelLblReloj.Text = (Get-Date).ToString("HH:mm:ss")
        if ($null -ne $script:ActionStartTime) {
            $el = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:PanelLblTimer.Text = "{0:N2}s" -f $el
        } else {
            $script:PanelLblTimer.Text = "listo"
        }
        if (-not $script:IsBusy -and $null -eq $script:ActionStartTime) {
            try { Update-PanelStatusUI } catch { }
        }
    })
    $script:PanelTimer.Start()
}

function Show-DefenderPanel {
    <#
    Crea y muestra el panel principal. Si ya esta abierto, lo trae al frente.
    Si el modo kiosco esta activo, pide contrasena antes de mostrarlo.
    #>
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try {
            $script:PanelForm.Show()
            $script:PanelForm.BringToFront()
            $script:PanelForm.Activate()
        } catch { }
        return
    }
    if (-not (Test-KioskPassword)) { return }

    $script:IsBusy = $false
    $script:ActionStartTime = $null
    $script:LastActionTime = 0
    $script:LastActionName = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Control de Seguridad v4.3 Pro"
    $form.ClientSize = New-Object System.Drawing.Size(470, 495)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = $script:IconOk

    # --- BARRA DE MENU ---
    $menuStrip = New-Object System.Windows.Forms.MenuStrip
    $menuStrip.BackColor = $script:Colors.MenuBg
    $menuStrip.ForeColor = $script:Colors.Text
    $menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $menuStrip.Dock = "Top"

    # Menu Archivo
    $mArchivo = New-Object System.Windows.Forms.ToolStripMenuItem
    $mArchivo.Text = "&Archivo"
    $mArchivo.ForeColor = $script:Colors.Text
    $miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
    $miSalir.Text = "Salir"
    $miSalir.Add_Click({
        if ($null -ne $script:PanelTimer) {
            try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
            $script:PanelTimer = $null
        }
        $script:PanelForm.Close()
    })
    [void]$mArchivo.DropDownItems.Add($miSalir)

    # Menu Acciones
    $mAcciones = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAcciones.Text = "&Acciones"
    $mAcciones.ForeColor = $script:Colors.Text

    $miAct = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAct.Text = "Activar"
    $miAct.Add_Click({
        if (-not (Test-Admin)) { return }
        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:LastActionName = "Activar"
            [System.Windows.Forms.Application]::DoEvents()
            $null = Enable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null
            $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $miDes = New-Object System.Windows.Forms.ToolStripMenuItem
    $miDes.Text = "Desactivar"
    $miDes.Add_Click({
        if (-not (Test-Admin)) { return }
        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:LastActionName = "Desactivar"
            [System.Windows.Forms.Application]::DoEvents()
            $null = Disable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null
            $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $miVer = New-Object System.Windows.Forms.ToolStripMenuItem
    $miVer.Text = "Verificar estado"
    $miVer.Add_Click({ Show-DiagnosticsDialog })

    [void]$mAcciones.DropDownItems.Add($miAct)
    [void]$mAcciones.DropDownItems.Add($miDes)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miVer)

    # Menu Herramientas
    $mHerram = New-Object System.Windows.Forms.ToolStripMenuItem
    $mHerram.Text = "&Herramientas"
    $mHerram.ForeColor = $script:Colors.Text

    $miRep = New-Object System.Windows.Forms.ToolStripMenuItem
    $miRep.Text = "Reparacion Profunda"
    $miRep.Add_Click({ Show-DeepRepairDialog })

    $miHist = New-Object System.Windows.Forms.ToolStripMenuItem
    $miHist.Text = "Historial"
    $miHist.Add_Click({ Show-HistoryDialog })

    $miConf = New-Object System.Windows.Forms.ToolStripMenuItem
    $miConf.Text = "Configuracion"
    $miConf.Add_Click({ Show-SettingsDialog })

    [void]$mHerram.DropDownItems.Add($miRep)
    [void]$mHerram.DropDownItems.Add($miHist)
    [void]$mHerram.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHerram.DropDownItems.Add($miConf)

    # Menu Ayuda
    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"
    $mAyuda.ForeColor = $script:Colors.Text

    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAy.Text = "Ayuda (F1)"
    $miAy.Add_Click({ Show-HelpDialog })

    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v4.3 Pro`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911"
        [System.Windows.Forms.MessageBox]::Show($t,"Acerca de","OK","Information") | Out-Null
    })

    [void]$mAyuda.DropDownItems.Add($miAy)
    [void]$mAyuda.DropDownItems.Add($miAc)

    [void]$menuStrip.Items.Add($mArchivo)
    [void]$menuStrip.Items.Add($mAcciones)
    [void]$menuStrip.Items.Add($mHerram)
    [void]$menuStrip.Items.Add($mAyuda)
    $form.MainMenuStrip = $menuStrip
    $form.Controls.Add($menuStrip)

    # --- HEADER ---
    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 24)
    $header.Size = New-Object System.Drawing.Size(470, 70)
    $header.BackColor = $script:Colors.HeaderUnk
    $form.Controls.Add($header)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "DEFENDER CONTROL"
    $lblHeader.Font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true
    $lblHeader.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblHeader)

    $lblSubH = New-Object System.Windows.Forms.Label
    $lblSubH.Text = "v4.3 Pro - Total Disable Edition"
    $lblSubH.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSubH.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
    $lblSubH.BackColor = [System.Drawing.Color]::Transparent
    $lblSubH.AutoSize = $true
    $lblSubH.Location = New-Object System.Drawing.Point(17, 44)
    $header.Controls.Add($lblSubH)

    $lblReloj = New-Object System.Windows.Forms.Label
    $lblReloj.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lblReloj.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
    $lblReloj.BackColor = [System.Drawing.Color]::Transparent
    $lblReloj.Size = New-Object System.Drawing.Size(160, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(295, 12)
    $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)

    $lblTimer = New-Object System.Windows.Forms.Label
    $lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimer.ForeColor = $script:Colors.AccentCyan
    $lblTimer.BackColor = [System.Drawing.Color]::Transparent
    $lblTimer.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimer.Location = New-Object System.Drawing.Point(295, 32)
    $lblTimer.TextAlign = "MiddleRight"
    $lblTimer.Text = "listo"
    $header.Controls.Add($lblTimer)

    # --- CARD DE ESTADO ---
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 105)
    $card.Size = New-Object System.Drawing.Size(440, 130)
    $card.BackColor = $script:Colors.CardBg
    $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)

    $lblTag = New-Object System.Windows.Forms.Label
    $lblTag.Text = "ESTADO ACTUAL"
    $lblTag.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
    $lblTag.ForeColor = $script:Colors.TextMuted
    $lblTag.BackColor = [System.Drawing.Color]::Transparent
    $lblTag.AutoSize = $true
    $lblTag.Location = New-Object System.Drawing.Point(12, 6)
    $card.Controls.Add($lblTag)

    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize = $true
    $lblValor.Location = New-Object System.Drawing.Point(12, 26)
    $lblValor.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($lblValor)

    $lblDet1 = New-Object System.Windows.Forms.Label
    $lblDet1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDet1.ForeColor = $script:Colors.TextDiag
    $lblDet1.BackColor = [System.Drawing.Color]::Transparent
    $lblDet1.Size = New-Object System.Drawing.Size(420, 16)
    $lblDet1.Location = New-Object System.Drawing.Point(12, 62)
    $card.Controls.Add($lblDet1)

    $lblDet2 = New-Object System.Windows.Forms.Label
    $lblDet2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDet2.ForeColor = $script:Colors.TextMuted
    $lblDet2.BackColor = [System.Drawing.Color]::Transparent
    $lblDet2.Size = New-Object System.Drawing.Size(420, 16)
    $lblDet2.Location = New-Object System.Drawing.Point(12, 82)
    $card.Controls.Add($lblDet2)

    $lblDet3 = New-Object System.Windows.Forms.Label
    $lblDet3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDet3.ForeColor = $script:Colors.AccentCyan
    $lblDet3.BackColor = [System.Drawing.Color]::Transparent
    $lblDet3.Size = New-Object System.Drawing.Size(420, 16)
    $lblDet3.Location = New-Object System.Drawing.Point(12, 104)
    $card.Controls.Add($lblDet3)

    # --- BOTONES ---
    $btnDiagnostico = New-NeonButton "DIAGNOSTICO"           $script:Colors.AccentPurple $script:Colors.AccentPurpH  15  245 440 32
    $btnActivar     = New-NeonButton "ACTIVAR PROTECCION"    $script:Colors.AccentGreen  $script:Colors.AccentGreenH 15  285 215 32
    $btnDesactivar  = New-NeonButton "DESACTIVAR PROTECCION" $script:Colors.AccentRed    $script:Colors.AccentRedH   240 285 215 32
    $btnReparar     = New-NeonButton "REPARAR (Deep Repair)" $script:Colors.AccentAmber  $script:Colors.AccentAmberH 15  325 440 36
    $btnHistorial   = New-NeonButton "Historial"             $script:Colors.AccentBlue   $script:Colors.AccentBlueH  15  370 105 32
    $btnConfig      = New-NeonButton "Config"                $script:Colors.AccentBlue   $script:Colors.AccentBlueH  125 370 105 32
    $btnAyuda       = New-NeonButton "Ayuda (F1)"            $script:Colors.AccentBlue   $script:Colors.AccentBlueH  235 370 105 32
    $btnSalir       = New-NeonButton "SALIR"                 $script:Colors.AccentRed    $script:Colors.AccentRedH   345 370 110 32

    foreach ($b in @($btnDiagnostico,$btnActivar,$btnDesactivar,$btnReparar,$btnHistorial,$btnConfig,$btnAyuda,$btnSalir)) {
        $form.Controls.Add($b)
    }

    # --- BARRA DE ESTADO ---
    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusStrip.SizingGrip = $false
    $statusStrip.BackColor = $script:Colors.BgSecondary
    $statusStrip.ForeColor = $script:Colors.Text
    $statusStrip.Font = New-Object System.Drawing.Font("Consolas", 8)
    $statusStrip.Dock = "Bottom"

    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = "Iniciando..."
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = "MiddleLeft"
    $statusLabel.ForeColor = $script:Colors.TextDiag
    [void]$statusStrip.Items.Add($statusLabel)

    $statusShortcuts = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusShortcuts.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    $statusShortcuts.ForeColor = $script:Colors.TextMuted
    [void]$statusStrip.Items.Add($statusShortcuts)

    $form.Controls.Add($statusStrip)
    $script:PanelStatusLabel = $statusLabel

    # --- GUARDAR REFERENCIAS EN SCOPE SCRIPT ---
    $script:PanelForm          = $form
    $script:PanelHeader        = $header
    $script:PanelLblValor      = $lblValor
    $script:PanelLblDet1       = $lblDet1
    $script:PanelLblDet2       = $lblDet2
    $script:PanelLblDet3       = $lblDet3
    $script:PanelLblReloj      = $lblReloj
    $script:PanelLblTimer      = $lblTimer
    $script:PanelBtnActivar    = $btnActivar
    $script:PanelBtnDesactivar = $btnDesactivar

    # --- ATAJOS DE TECLADO ---
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F1) { Show-HelpDialog; $e.Handled = $true }
        elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) { Update-PanelStatusUI; $e.Handled = $true }
        elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            if ($null -ne $script:PanelTimer) {
                try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
                $script:PanelTimer = $null
            }
            $script:PanelForm.Close()
        }
    })

    # --- EVENTOS DE BOTONES ---
    $btnDiagnostico.Add_Click({ Show-DiagnosticsDialog })
    $btnReparar.Add_Click({ Show-DeepRepairDialog })
    $btnHistorial.Add_Click({ Show-HistoryDialog })
    $btnAyuda.Add_Click({ Show-HelpDialog })
    $btnConfig.Add_Click({ Show-SettingsDialog })

    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:LastActionName = "Activar"
            $script:PanelLblDet1.Text = "Activando..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null
            $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
            [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s`n`n$log" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $c = [System.Windows.Forms.MessageBox]::Show(
            "Desactivar Windows Defender COMPLETAMENTE?`n`nSe detendran 8 servicios y se mataran los procesos.`nPuede requerir REINICIO.",
            "Confirmar", "YesNo", "Warning")
        if ($c -ne "Yes") { return }
        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:LastActionName = "Desactivar"
            $script:PanelLblDet1.Text = "Desactivando TOTAL..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Disable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null
            $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
            $extra = ""
            if ($s.Estado -ne "DESACTIVADO") { $extra = "`n`nREINICIA EL EQUIPO para completar." }
            [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s$extra`n`n$log" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $btnSalir.Add_Click({
        if ($null -ne $script:PanelTimer) {
            try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
            $script:PanelTimer = $null
        }
        $script:PanelForm.Close()
    })

    $form.Add_FormClosed({
        if ($null -ne $script:PanelTimer) {
            try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
            $script:PanelTimer = $null
        }
        $script:PanelForm = $null
    })

    $form.Add_Shown({ Update-PanelStatusUI; Start-PanelTimer })
    $form.Show()
}

# ============================================================================
# SECCION 23 - ARRANQUE
# Ejecuta las verificaciones iniciales, aplica exclusion y muestra la
# bandeja del sistema con el menu contextual.
# ============================================================================
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v4.3 Pro iniciado" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "=============================================" "INFO"

if (Test-Admin) {
    Write-AppLog "Admin: SI" "INFO"
    try { Add-MpPreference -ExclusionPath $script:ScriptDir -Force -ErrorAction SilentlyContinue } catch { }
} else {
    Write-AppLog "Admin: NO" "WARN"
}

# Accion programada (para el scheduler)
if ($args -contains "-action") {
    $idx = [array]::IndexOf($args, "-action")
    if ($idx -ge 0 -and $idx + 1 -lt $args.Count) {
        $actionArg = $args[$idx + 1]
        if ($actionArg -eq "disable") { $null = Disable-Defender; exit 0 }
        elseif ($actionArg -eq "enable") { $null = Enable-Defender; exit 0 }
    }
}

$initQuick = Get-QuickStatus

# ============================================================================
# SECCION 24 - ICONO DE BANDEJA Y MENU CONTEXTUAL
# ============================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = "Control de Seguridad v4.3 Pro"
$script:notifyIcon.Visible = $true
Update-TrayIcon -Estado $initQuick.Estado

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor = $script:Colors.MenuBg
$menu.ForeColor = $script:Colors.Text
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 9)

function Add-MenuItem {
    <#
    Helper para agregar items al menu contextual con el color correcto.
    #>
    param([string]$Texto, [scriptblock]$Accion)
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $Texto
    $mi.ForeColor = $script:Colors.Text
    $mi.Add_Click($Accion)
    return $mi
}

[void]$menu.Items.Add((Add-MenuItem "Abrir panel" { Show-DefenderPanel }))
[void]$menu.Items.Add((Add-MenuItem "Diagnostico" { Show-DiagnosticsDialog }))
[void]$menu.Items.Add((Add-MenuItem "REPARACION PROFUNDA" { Show-DeepRepairDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((Add-MenuItem "Historial" { Show-HistoryDialog }))
[void]$menu.Items.Add((Add-MenuItem "Configuracion" { Show-SettingsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Ayuda" { Show-HelpDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miAct = Add-MenuItem "Activar Defender" {
    if (-not (Test-Admin)) { return }
    $null = Enable-Defender
    $s = Get-QuickStatus
    Add-History -Accion "Activar (menu)" -Resultado $s.Estado -Segundos 0
    Update-TrayIcon -Estado $s.Estado
}
$miDes = Add-MenuItem "Desactivar Defender" {
    if (-not (Test-Admin)) { return }
    $null = Disable-Defender
    $s = Get-QuickStatus
    Add-History -Accion "Desactivar (menu)" -Resultado $s.Estado -Segundos 0
    Update-TrayIcon -Estado $s.Estado
}
[void]$menu.Items.Add($miAct)
[void]$menu.Items.Add($miDes)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

[void]$menu.Items.Add((Add-MenuItem "Salir" {
    if ($null -ne $script:PanelTimer) {
        try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
    }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try { $script:PanelForm.Close() } catch { }
    }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}))

$menu.Add_Opening({
    $s = Get-QuickStatus
    if ($s.Estado -eq "ACTIVO") {
        $miAct.Enabled = $false
        $miDes.Enabled = $true
    } else {
        $miAct.Enabled = $true
        $miDes.Enabled = $false
    }
})

$script:notifyIcon.ContextMenuStrip = $menu
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

Write-AppLog "Bandeja inicializada. Estado: $($initQuick.Estado)" "INFO"

# ============================================================================
# SECCION 25 - BUCLE PRINCIPAL
# Mantiene la aplicacion en ejecucion hasta que el usuario sale.
# ============================================================================
[System.Windows.Forms.Application]::Run()