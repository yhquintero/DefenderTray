<#
================================================================================
  DefenderTray v5.0 Pro - Control Profesional de Windows Defender
================================================================================
  Novedades v5.0:
    - Logs con ajuste de linea automatico (solo scroll vertical).
    - 15 mejoras continuas integradas.
    - Auto-reparacion de firmas al iniciar.
    - Programador de tareas integrado.
    - Instalacion como servicio (tarea programada).
    - Backup/Restore del registro de politicas.
    - Deteccion de antivirus de terceros.
    - Diagnostico de red y conectividad.
    - Multi-idioma ES/EN (parcial).
    - Limpieza automatica de logs >30 dias.
    - Verificacion SHA256 del script.
    - Estadisticas historicas.
    - Contrasena de desinstalacion.
  Autor: Ing. Yosvany Hernandez Quintero
  Movil: +53 5 2160801 / +53 5 9860911
================================================================================
#>

# ============================================================================
# SECCION 1 - ENSAMBLADOS
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue

# ============================================================================
# SECCION 2 - ARGUMENTOS Y RUTAS
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
$script:RegBackupDir = Join-Path $script:BackupDir "Registro"
$script:LogFile     = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ConfigFile  = Join-Path $script:ConfigDir "config.json"
$script:HistoryFile = Join-Path $script:ConfigDir "historial.json"

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir, $script:RegBackupDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ============================================================================
# SECCION 3 - CARACTERES ESPECIALES
# ============================================================================
$script:CH_N = [char]0x00F1

# ============================================================================
# SECCION 4 - i18n (Multi-idioma ES/EN)
# ============================================================================
$script:Strings = @{
    ES = @{
        Title         = "Control de Seguridad v5.0 Pro"
        Activar       = "ACTIVAR PROTECCION"
        Desactivar    = "DESACTIVAR PROTECCION"
        Diagnostico   = "DIAGNOSTICO"
        Reparar       = "REPARAR (Deep Repair)"
        Historial     = "Historial"
        Config        = "Config"
        Ayuda         = "Ayuda (F1)"
        Salir         = "SALIR"
        EstadoActual  = "ESTADO ACTUAL"
        Password      = "Contrase" + [char]0x00F1 + "a"
        PasswordShort = "Contrasena"
    }
    EN = @{
        Title         = "Security Control v5.0 Pro"
        Activar       = "ENABLE PROTECTION"
        Desactivar    = "DISABLE PROTECTION"
        Diagnostico   = "DIAGNOSTICS"
        Reparar       = "REPAIR (Deep Repair)"
        Historial     = "History"
        Config        = "Settings"
        Ayuda         = "Help (F1)"
        Salir         = "EXIT"
        EstadoActual  = "CURRENT STATUS"
        Password      = "Password"
        PasswordShort = "Password"
    }
}

$script:Lang = "ES"

function T {
    param([string]$Clave)
    if ($script:Strings.ContainsKey($script:Lang) -and $script:Strings[$script:Lang].ContainsKey($Clave)) {
        return $script:Strings[$script:Lang][$Clave]
    }
    return $Clave
}

# ============================================================================
# SECCION 5 - CONFIGURACION
# ============================================================================
$script:CfgDarkTheme      = $true
$script:CfgKioskMode      = $false
$script:CfgKioskHash      = ""
$script:CfgUninstallHash  = ""
$script:CfgFirstRunDone   = $false
$script:CfgLang           = "ES"
$script:CfgAutoRepair     = $true
$script:CfgAutoCleanup    = $true
$script:DarkTheme         = $true
$script:IsKioskMode       = $false
$script:ScriptHash        = ""

function Load-AppConfig {
    try {
        if (Test-Path $script:ConfigFile) {
            $json = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $json.DarkTheme)      { $script:CfgDarkTheme     = [bool]$json.DarkTheme }
            if ($null -ne $json.KioskMode)      { $script:CfgKioskMode     = [bool]$json.KioskMode }
            if ($null -ne $json.KioskHash)      { $script:CfgKioskHash     = [string]$json.KioskHash }
            if ($null -ne $json.UninstallHash)  { $script:CfgUninstallHash = [string]$json.UninstallHash }
            if ($null -ne $json.FirstRunDone)   { $script:CfgFirstRunDone  = [bool]$json.FirstRunDone }
            if ($null -ne $json.Lang)           { $script:CfgLang          = [string]$json.Lang }
            if ($null -ne $json.AutoRepair)     { $script:CfgAutoRepair    = [bool]$json.AutoRepair }
            if ($null -ne $json.AutoCleanup)    { $script:CfgAutoCleanup   = [bool]$json.AutoCleanup }
        }
    } catch { }
    $script:DarkTheme   = $script:CfgDarkTheme
    $script:IsKioskMode = $script:CfgKioskMode
    $script:Lang        = $script:CfgLang
}

function Save-AppConfig {
    try {
        $obj = [PSCustomObject]@{
            DarkTheme     = $script:DarkTheme
            KioskMode     = $script:IsKioskMode
            KioskHash     = $script:CfgKioskHash
            UninstallHash = $script:CfgUninstallHash
            FirstRunDone  = $script:CfgFirstRunDone
            Lang          = $script:Lang
            AutoRepair    = $script:CfgAutoRepair
            AutoCleanup   = $script:CfgAutoCleanup
        }
        $obj | ConvertTo-Json -Depth 3 | Set-Content -Path $script:ConfigFile -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 6 - LOG CON ROTACION Y LIMPIEZA
# ============================================================================
function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Clear-OldLogs {
    <#
    Elimina logs de mas de 30 dias si AutoCleanup esta activado.
    #>
    if (-not $script:CfgAutoCleanup) { return }
    try {
        $limite = (Get-Date).AddDays(-30)
        Get-ChildItem -Path $script:LogFolder -Filter "DefenderTray_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-AppLog "Limpieza de logs antiguos completada" "INFO"
    } catch { }
}

# ============================================================================
# SECCION 7 - ESPERA NO BLOQUEANTE
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
# SECCION 8 - HELPERS DE TIEMPO
# ============================================================================
function Start-ActionTimer { $script:ActionStartTicks = [DateTime]::Now.Ticks }

function Get-ActionElapsedSeconds {
    if ($null -eq $script:ActionStartTicks) { return 0 }
    if (-not ($script:ActionStartTicks -is [long])) { return 0 }
    return ([DateTime]::Now.Ticks - $script:ActionStartTicks) / 10000000
}

function Stop-ActionTimer {
    $elapsed = Get-ActionElapsedSeconds
    $script:ActionStartTicks = $null
    return $elapsed
}

# ============================================================================
# SECCION 9 - PALETA
# ============================================================================
function Get-FuturisticPalette {
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
# SECCION 10 - VERIFICACION SHA256 DEL SCRIPT
# ============================================================================
function Get-ScriptHash {
    try {
        if (Test-Path $script:ScriptPath) {
            $hash = Get-FileHash -Path $script:ScriptPath -Algorithm SHA256 -ErrorAction Stop
            $script:ScriptHash = $hash.Hash.Substring(0, 16)
            return $script:ScriptHash
        }
    } catch { }
    return ""
}

# ============================================================================
# SECCION 11 - ICONOS DINAMICOS
# ============================================================================
function New-ShieldBitmap {
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
    param([System.Drawing.Color]$Color)
    $bmp = New-ShieldBitmap -FillColor $Color
    if ($null -eq $bmp) { return [System.Drawing.SystemIcons]::Shield }
    try { return [System.Drawing.Icon]::FromHandle($bmp.GetHicon()) }
    catch { return [System.Drawing.SystemIcons]::Shield }
}

function Get-WindowsDefenderIcon {
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
                if ($null -ne $icon) { return $icon }
            }
        } catch { }
    }
    return $null
}

$script:OfficialDefenderIcon = Get-WindowsDefenderIcon

$script:IconOk      = if ($null -ne $script:OfficialDefenderIcon) { $script:OfficialDefenderIcon } else { New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(0, 200, 100)) }
$script:IconBad     = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 40, 80))
$script:IconPartial = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 140, 0))

function Update-TrayIcon {
    param([string]$Estado)
    if ($null -eq $script:notifyIcon) { return }
    try {
        if ($Estado -eq "ACTIVO") {
            $script:notifyIcon.Icon = $script:IconOk
            $script:notifyIcon.Text = "Windows Defender - ACTIVADO"
        } elseif ($Estado -eq "DESACTIVADO") {
            $script:notifyIcon.Icon = $script:IconBad
            $script:notifyIcon.Text = "Windows Defender - DESACTIVADO"
        } elseif ($Estado -eq "PARCIAL") {
            $script:notifyIcon.Icon = $script:IconPartial
            $script:notifyIcon.Text = "Windows Defender - PARCIAL"
        } else {
            $script:notifyIcon.Icon = $script:IconPartial
            $script:notifyIcon.Text = "Windows Defender"
        }
    } catch { }
}

# ============================================================================
# SECCION 12 - DETECCION DE ANTIVIRUS DE TERCEROS
# ============================================================================
function Get-ThirdPartyAV {
    <#
    Detecta antivirus de terceros instalados.
    #>
    $resultado = New-Object System.Collections.ArrayList
    try {
        $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($av in $avs) {
            $nombre = $av.displayName
            $estado = $av.productState
            [void]$resultado.Add([PSCustomObject]@{ Nombre=$nombre; Estado=$estado })
        }
    } catch { }
    return $resultado
}

# ============================================================================
# SECCION 13 - DIAGNOSTICO DE RED
# ============================================================================
function Test-NetworkConnectivity {
    <#
    Comprueba la conectividad con los servidores de Microsoft Update.
    #>
    $resultado = New-Object System.Collections.ArrayList
    $hosts = @(
        @{Nombre="Microsoft Update";  Host="update.microsoft.com";  Puerto=443},
        @{Nombre="Defender Signatures"; Host="definitionupdates.microsoft.com"; Puerto=443},
        @{Nombre="Windows Update";    Host="windowsupdate.microsoft.com"; Puerto=443}
    )
    foreach ($h in $hosts) {
        try {
            $test = Test-NetConnection -ComputerName $h.Host -Port $h.Puerto -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop
            [void]$resultado.Add([PSCustomObject]@{ Nombre=$h.Nombre; Host=$h.Host; OK=[bool]$test })
        } catch {
            [void]$resultado.Add([PSCustomObject]@{ Nombre=$h.Nombre; Host=$h.Host; OK=$false })
        }
    }
    return $resultado
}

# ============================================================================
# SECCION 14 - ESTADO RAPIDO
# ============================================================================
function Test-DefenderPolicyDisabled {
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

function Get-ServiceStartMode {
    param([string]$Name)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $resultado = "?"
    try {
        if (Test-Path $regPath) {
            $v = (Get-ItemProperty -Path $regPath -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($null -ne $v) {
                $num = [int]$v
                if ($num -eq 0)      { $resultado = "Boot" }
                elseif ($num -eq 1)  { $resultado = "System" }
                elseif ($num -eq 2)  { $resultado = "Automatic" }
                elseif ($num -eq 3)  { $resultado = "Manual" }
                elseif ($num -eq 4)  { $resultado = "Disabled" }
                else                 { $resultado = "$num" }
            }
        }
    } catch { }
    return $resultado
}

# ============================================================================
# SECCION 15 - UTILIDADES
# ============================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StringHash {
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
}

# ============================================================================
# SECCION 16 - BOTONES NEON
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
# SECCION 17 - DIALOGO DE RESULTADO (SCROLL VERTICAL + WORDWRAP)
# ============================================================================
function Show-ResultDialog {
    param(
        [string]$Titulo,
        [string]$Mensaje,
        [string]$Tipo = "Info"
    )

    $colorHeader = $script:Colors.AccentBlue
    if ($Tipo -eq "Success") { $colorHeader = $script:Colors.AccentGreen }
    elseif ($Tipo -eq "Error") { $colorHeader = $script:Colors.AccentRed }
    elseif ($Tipo -eq "Warning") { $colorHeader = $script:Colors.AccentAmber }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Titulo
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 560)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.MinimumSize = New-Object System.Drawing.Size(500, 400)
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 60
    $header.BackColor = $colorHeader
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = $Titulo
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)

    # TextBox SOLO con scroll vertical y ajuste de linea
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ScrollBars = "Vertical"
    $txt.ReadOnly = $true
    $txt.WordWrap = $true
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor = $script:Colors.ConsoleBg
    $txt.ForeColor = $script:Colors.ConsoleText
    $txt.BorderStyle = "FixedSingle"
    $txt.Location = New-Object System.Drawing.Point(15, 75)
    $txt.Size = New-Object System.Drawing.Size(690, 410)
    $txt.Anchor = "Top,Left,Right,Bottom"
    $txt.Text = $Mensaje
    $dlg.Controls.Add($txt)

    $btnCopiar = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 500 140 34
    $btnCerrar = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 565 500 140 34
    $btnCopiar.Anchor = "Bottom,Left"
    $btnCerrar.Anchor = "Bottom,Right"
    $dlg.Controls.Add($btnCopiar)
    $dlg.Controls.Add($btnCerrar)

    $btnCopiar.Add_Click({
        try {
            [System.Windows.Forms.Clipboard]::SetText($txt.Text)
            [System.Windows.Forms.MessageBox]::Show("Contenido copiado.","OK","OK","Information") | Out-Null
        } catch { }
    })
    $btnCerrar.Add_Click({ $dlg.Close() })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 18 - DIALOGO DE CONFIRMACION
# ============================================================================
function Show-ConfirmDialog {
    param([string]$Titulo, [string]$Mensaje)
    $r = [System.Windows.Forms.MessageBox]::Show($Mensaje, $Titulo, "YesNo", "Warning")
    return ($r -eq "Yes")
}

# ============================================================================
# SECCION 19 - BACKUP / RESTORE DEL REGISTRO
# ============================================================================
function Backup-DefenderRegistry {
    <#
    Exporta la rama HKLM\SOFTWARE\Policies\Microsoft\Windows Defender a .reg
    #>
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $archivo = Join-Path $script:RegBackupDir "DefenderPolicies_$timestamp.reg"
        $null = & reg.exe export "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" $archivo /y 2>&1
        if (Test-Path $archivo) {
            Write-AppLog "Backup del registro creado: $archivo" "INFO"
            return $archivo
        }
    } catch { }
    return $null
}

function Restore-DefenderRegistry {
    param([string]$Archivo)
    try {
        if (Test-Path $Archivo) {
            $null = & reg.exe import $Archivo 2>&1
            Write-AppLog "Restaurado desde: $Archivo" "INFO"
            return $true
        }
    } catch { }
    return $false
}

# ============================================================================
# SECCION 20 - DESHABILITAR FAILURE ACTIONS
# ============================================================================
function Disable-ServiceFailureActions {
    param([string]$ServiceName)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    try {
        if (-not (Test-Path $regPath)) { return $false }
        $empty = New-Object byte[] 20
        Set-ItemProperty -Path $regPath -Name "FailureActions"  -Value $empty -Type Binary -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "ResetPeriod"     -Value 0     -Type DWord  -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "RestartDelay"    -Value 0     -Type DWord  -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "RestartAttempts" -Value 0     -Type DWord  -Force -ErrorAction SilentlyContinue
        try { $null = & sc.exe failure $ServiceName reset= 0 actions= "" 2>&1 } catch { }
        return $true
    } catch { return $false }
}

# ============================================================================
# SECCION 21 - REPARAR FIRMAS CORRUPTAS
# ============================================================================
function Repair-DefenderSignatures {
    $log = New-Object System.Collections.ArrayList
    [void]$log.Add("=== REPARACION DE FIRMAS ===")
    [void]$log.Add("")

    $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmd)) {
        [void]$log.Add("[!] No se encontro MpCmdRun.exe")
        return ($log -join "`n")
    }

    [void]$log.Add("[1/6] Deteniendo WinDefend...")
    try {
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 3000
    } catch { }

    [void]$log.Add("[2/6] Removiendo definiciones corruptas...")
    try {
        $out = & $mpCmd -RemoveDefinitions -All 2>&1 | Out-String
        foreach ($linea in ($out -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($linea)) { [void]$log.Add("       $linea") }
        }
    } catch {
        [void]$log.Add("       Error: $($_.Exception.Message)")
    }

    [void]$log.Add("[3/6] Reiniciando WinDefend...")
    try {
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        $null = & sc.exe start WinDefend 2>&1
        Wait-WithDoEvents -Milliseconds 5000
    } catch { }

    [void]$log.Add("[4/6] Descargando firmas actualizadas...")
    if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
        try {
            Update-MpSignature -UpdateInterval 0 -ErrorAction SilentlyContinue
            [void]$log.Add("       Update-MpSignature ejecutado.")
        } catch {
            [void]$log.Add("       Error: $($_.Exception.Message)")
        }
    }
    Wait-WithDoEvents -Milliseconds 5000

    [void]$log.Add("[5/6] Verificando firmas...")
    try {
        $st = Get-MpComputerStatus -ErrorAction Stop
        $edad = $st.AntivirusSignatureAge
        $version = $st.AntivirusSignatureVersion
        $actual = $st.AntivirusSignatureLastUpdated
        [void]$log.Add("       Version: $version")
        [void]$log.Add("       Edad: $edad dias")
        [void]$log.Add("       Ultima actualizacion: $actual")
        if ($edad -le 30) {
            [void]$log.Add("")
            [void]$log.Add("[OK] Firmas reparadas correctamente.")
        } else {
            [void]$log.Add("")
            [void]$log.Add("[!] Firmas siguen antiguas. Intenta reiniciar el equipo.")
        }
    } catch {
        [void]$log.Add("       Error verificando: $($_.Exception.Message)")
    }

    return ($log -join "`n")
}

# ============================================================================
# SECCION 22 - AUTO-REPARACION AL INICIAR
# ============================================================================
function Invoke-StartupAutoRepair {
    <#
    Al iniciar, si las firmas tienen >30 dias o 65535, las repara.
    #>
    if (-not $script:CfgAutoRepair) { return }
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $edad = $st.AntivirusSignatureAge
            if ($edad -gt 30 -or $edad -eq 65535) {
                Write-AppLog "Auto-reparacion: firmas con $edad dias" "WARN"
                $null = Repair-DefenderSignatures
            }
        }
    } catch { }
}

# ============================================================================
# SECCION 23 - DESACTIVAR DEFENDER
# ============================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                [void]$log.Add("Desactivala en: Seguridad de Windows -> Proteccion antivirus")
                [void]$log.Add("-> Administrar la configuracion -> Proteccion contra alteraciones")
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Desactivacion iniciada" "INFO"

    # Backup del registro antes de modificar
    $backupReg = Backup-DefenderRegistry
    if ($backupReg) {
        [void]$log.Add("[0/10] Backup del registro: OK")
    }

    [void]$log.Add("[1/10] Desactivando preferencias via Set-MpPreference...")
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

    [void]$log.Add("[2/10] Eliminando politicas de grupo...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }

    [void]$log.Add("[3/10] Estableciendo politicas de bloqueo...")
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

    [void]$log.Add("[4/10] Deshabilitando FailureActions...")
    $svcs = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    $faCount = 0
    foreach ($s in $svcs) {
        if (Disable-ServiceFailureActions -ServiceName $s) { $faCount++ }
    }
    [void]$log.Add("       FailureActions deshabilitadas en $faCount servicios")

    [void]$log.Add("[5/10] Bucle de desactivacion (max 5 intentos)...")
    $maxIntentos = 5
    $intento = 0
    $exito = $false

    while (-not $exito -and $intento -lt $maxIntentos) {
        $intento++
        [void]$log.Add("")
        [void]$log.Add("=== INTENTO $intento de $maxIntentos ===")

        [void]$log.Add("  [A] Matando procesos del motor...")
        foreach ($proc in @("MsMpEng.exe","NisSrv.exe","SecurityHealthService.exe",
                            "SecurityHealthSystray.exe","MpCmdRun.exe","MpCopyAccelerator.exe")) {
            try { $null = & taskkill.exe /F /IM $proc 2>&1 } catch { }
        }

        [void]$log.Add("  [B] Deteniendo servicios...")
        foreach ($s in $svcs) {
            try {
                $null = & sc.exe stop $s 2>&1
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            } catch { }
        }

        [void]$log.Add("  [C] Escribiendo Start=4 en registro...")
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

        [void]$log.Add("  [D] Aplicando sc.exe config disabled...")
        foreach ($s in $svcs) {
            try { $null = & sc.exe config $s start= disabled 2>&1 } catch { }
        }

        [void]$log.Add("  [E] Esperando 4 segundos...")
        Wait-WithDoEvents -Milliseconds 4000

        $svcCheck = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        $procCheck = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
        $svcRunning = ($null -ne $svcCheck) -and ($svcCheck.Status -eq 'Running')
        $procRunning = ($null -ne $procCheck)

        if (-not $svcRunning -and -not $procRunning) {
            $exito = $true
            [void]$log.Add("  [OK] Desactivacion exitosa en intento $intento")
        } else {
            [void]$log.Add("  [!] Windows reinicio el servicio. Reintentando...")
            Wait-WithDoEvents -Milliseconds 2000
        }
    }

    [void]$log.Add("")
    [void]$log.Add("[9/10] Verificacion final...")
    $svcFin  = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $svcOk = ($null -eq $svcFin) -or ($svcFin.Status -ne 'Running')
    $procOk = ($null -eq $procFin)

    $startOk = $true
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        $sm = Get-ServiceStartMode -Name $s
        if ($sm -ne "Disabled") { $startOk = $false }
    }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO FINAL ===")
    if ($svcOk) { [void]$log.Add("  Servicio WinDefend: DETENIDO") } else { [void]$log.Add("  Servicio WinDefend: AUN CORRIENDO") }
    if ($procOk) { [void]$log.Add("  Proceso MsMpEng:    DETENIDO") } else { [void]$log.Add("  Proceso MsMpEng:    AUN CORRIENDO") }
    if ($startOk) { [void]$log.Add("  Registro Start=4:   APLICADO") } else { [void]$log.Add("  Registro Start=4:   PARCIAL") }
    [void]$log.Add("  Intentos usados:    $intento de $maxIntentos")

    [void]$log.Add("")
    if ($svcOk -and $procOk -and $startOk) {
        [void]$log.Add("[OK] DESACTIVACION TOTAL EXITOSA.")
    } elseif ($svcOk -and $procOk) {
        [void]$log.Add("[OK] Desactivacion funcional. Reinicia para confirmar.")
    } else {
        [void]$log.Add("[!] DESACTIVACION INCOMPLETA.")
        [void]$log.Add("")
        [void]$log.Add("En Windows 11 22H2+ el kernel de Windows reinicia")
        [void]$log.Add("WinDefend automaticamente. Los cambios de registro")
        [void]$log.Add("(Start=4) YA estan aplicados. Al REINICIAR el equipo")
        [void]$log.Add("el servicio NO arrancara porque tiene Start=4.")
    }

    $sw.Stop()
    [void]$log.Add("")
    [void]$log.Add("[OK] Tiempo total: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog "Desactivacion terminada en $intento intentos" "INFO"
    return ($log -join "`n")
}

# ============================================================================
# SECCION 24 - ACTIVAR DEFENDER (CON DEPENDENCIAS)
# ============================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AppLog "Activacion iniciada" "INFO"

    [void]$log.Add("[1/10] Configurando Start de cada servicio...")
    $svcConfig = @(
        @{N="WinDefend";             Start=2; Run=$true;  Orden=1},
        @{N="WdNisSvc";              Start=2; Run=$true;  Orden=2},
        @{N="Sense";                 Start=2; Run=$true;  Orden=3},
        @{N="SecurityHealthService"; Start=2; Run=$true;  Orden=4},
        @{N="wscsvc";                Start=2; Run=$true;  Orden=5},
        @{N="WdNisDrv";              Start=1; Run=$false; Orden=6},
        @{N="WdBoot";                Start=0; Run=$false; Orden=7},
        @{N="Wdfilter";              Start=0; Run=$false; Orden=8}
    )
    foreach ($s in $svcConfig) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.N)"
        if (Test-Path $p) {
            try {
                Set-ItemProperty -Path $p -Name "Start" -Value $s.Start -Type DWord -Force -ErrorAction SilentlyContinue
                $txtStart = "?"
                if ($s.Start -eq 0)      { $txtStart = "Boot" }
                elseif ($s.Start -eq 1)  { $txtStart = "System" }
                elseif ($s.Start -eq 2)  { $txtStart = "Automatic" }
                elseif ($s.Start -eq 3)  { $txtStart = "Manual" }
                elseif ($s.Start -eq 4)  { $txtStart = "Disabled" }
                [void]$log.Add("       $($s.N) -> $txtStart")
            } catch { }
        }
    }

    [void]$log.Add("[2/10] Eliminando politicas de bloqueo...")
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
            }
        } catch { }
    }

    [void]$log.Add("[3/10] Limpiando claves RTP...")
    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    if (Test-Path $rtWk) {
        foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                         "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning",
                         "DisableRawWriteNotification","DisableAsyncScan")) {
            try { Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("       Claves RTP limpiadas.")
    }

    [void]$log.Add("[4/10] Arrancando servicios por orden de dependencias...")
    $serviciosOrden = $svcConfig | Where-Object { $_.Run } | Sort-Object Orden
    foreach ($s in $serviciosOrden) {
        $nombre = $s.N
        $running = $false
        $maxIntentos = 4
        $intentos = 0
        while (-not $running -and $intentos -lt $maxIntentos) {
            $intentos++
            try {
                $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
                if ($null -eq $svc) { break }
                Set-Service -Name $nombre -StartupType Automatic -ErrorAction SilentlyContinue
                $null = & sc.exe config $nombre start= auto 2>&1
                if ($svc.Status -ne 'Running') {
                    Start-Service -Name $nombre -ErrorAction SilentlyContinue
                    $null = & sc.exe start $nombre 2>&1
                }
                Wait-WithDoEvents -Milliseconds 1500
                $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
                if ($null -ne $svc -and $svc.Status -eq 'Running') {
                    $running = $true
                    [void]$log.Add("       [OK] $nombre -> CORRIENDO (intento $intentos)")
                }
            } catch { }
        }
        if (-not $running) {
            $svcFinal = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            $estadoFinal = if ($null -ne $svcFinal) { $svcFinal.Status } else { "NO EXISTE" }
            [void]$log.Add("       [!] $nombre -> $estadoFinal")
        }
    }

    Wait-WithDoEvents -Milliseconds 2000

    [void]$log.Add("[5/10] Reiniciando WinDefend...")
    try {
        $null = & sc.exe stop WinDefend 2>&1
        Wait-WithDoEvents -Milliseconds 2000
        $null = & sc.exe start WinDefend 2>&1
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 5000
        [void]$log.Add("       WinDefend reiniciado.")
    } catch { }

    [void]$log.Add("[6/10] Reintentando servicios que fallaron...")
    foreach ($s in $serviciosOrden) {
        if ($s.N -eq "WinDefend") { continue }
        $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -ne 'Running') {
            try {
                $null = & sc.exe start $s.N 2>&1
                Start-Service -Name $s.N -ErrorAction SilentlyContinue
                Wait-WithDoEvents -Milliseconds 2000
                $svc2 = Get-Service -Name $s.N -ErrorAction SilentlyContinue
                if ($null -ne $svc2 -and $svc2.Status -eq 'Running') {
                    [void]$log.Add("       [OK] $($s.N) ahora esta CORRIENDO")
                }
            } catch { }
        }
    }

    [void]$log.Add("[7/10] Activando TODAS las protecciones...")
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

        $rtpActivo = $false
        $prefIntento = 0
        $prefMax = 5
        while (-not $rtpActivo -and $prefIntento -lt $prefMax) {
            $prefIntento++
            [void]$log.Add("       Intento $prefIntento de Set-MpPreference...")

            foreach ($p in $prefs) {
                try { Set-MpPreference @{ $p.N = $p.V } -Force -ErrorAction SilentlyContinue } catch { }
            }

            try {
                Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
                Set-MpPreference -CloudBlockLevel High -Force -ErrorAction SilentlyContinue
                Set-MpPreference -CloudExtendedTimeout 50 -Force -ErrorAction SilentlyContinue
                Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction SilentlyContinue
                Set-MpPreference -PUAProtection Enabled -Force -ErrorAction SilentlyContinue
                Set-MpPreference -EnableNetworkProtection Enabled -Force -ErrorAction SilentlyContinue
                Set-MpPreference -EnableFileHashComputation $true -Force -ErrorAction SilentlyContinue
            } catch { }

            Wait-WithDoEvents -Milliseconds 3000

            try {
                $stCheck = Get-MpComputerStatus -ErrorAction Stop
                $rtpActivo = [bool]$stCheck.RealTimeProtectionEnabled
                if ($rtpActivo) {
                    [void]$log.Add("       [OK] RTP activado en intento $prefIntento")
                }
            } catch { }

            if (-not $rtpActivo) { Wait-WithDoEvents -Milliseconds 2000 }
        }

        if ($rtpActivo) {
            [void]$log.Add("       15+ protecciones activadas")
            [void]$log.Add("       Nube (MAPS): Advanced + BlockLevel High")
        }
    }

    [void]$log.Add("[8/10] Intentando activar Tamper Protection...")
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
        if ($verify) { [void]$log.Add("       Tamper Protection: ACTIVADO") }
        else { [void]$log.Add("       Tamper Protection: RECHAZADO") }
    } catch { }

    [void]$log.Add("[9/10] Lanzando icono oficial + gpupdate...")
    try {
        $systray = "$env:windir\System32\SecurityHealthSystray.exe"
        if (Test-Path $systray) { Start-Process -FilePath $systray -ErrorAction SilentlyContinue }
    } catch { }
    try { $null = & gpupdate.exe /force 2>&1 } catch { }
    Wait-WithDoEvents -Milliseconds 2000

    [void]$log.Add("[10/10] Verificacion final...")
    Wait-WithDoEvents -Milliseconds 2000

    $allRunning = $true
    foreach ($s in $svcConfig) {
        if (-not $s.Run) { continue }
        $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
        $st = "NO EXISTE"
        if ($null -ne $svc) { $st = $svc.Status }
        $ok = ($st -eq 'Running')
        if (-not $ok) { $allRunning = $false }
        $marca = "[!]"
        if ($ok) { $marca = "[OK]" }
        [void]$log.Add("       $marca $($s.N): $st")
    }

    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $procOk = ($null -ne $procFin)
    $rtpOk = $false
    $antivirusOk = $false
    try {
        $stFin = Get-MpComputerStatus -ErrorAction Stop
        $rtpOk = $stFin.RealTimeProtectionEnabled
        $antivirusOk = $stFin.AntivirusEnabled
    } catch { }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO ===")
    if ($allRunning) { [void]$log.Add("  Servicios corriendo: TODOS") } else { [void]$log.Add("  Servicios corriendo: ALGUNOS FALLARON") }
    if ($procOk) { [void]$log.Add("  Proceso MsMpEng:     CORRIENDO") } else { [void]$log.Add("  Proceso MsMpEng:     DETENIDO") }
    if ($rtpOk) { [void]$log.Add("  Tiempo real:         ACTIVADO") } else { [void]$log.Add("  Tiempo real:         DESACTIVADO") }
    if ($antivirusOk) { [void]$log.Add("  Antivirus general:   ACTIVADO") } else { [void]$log.Add("  Antivirus general:   DESACTIVADO") }

    [void]$log.Add("")
    if ($allRunning -and $procOk -and $rtpOk) {
        [void]$log.Add("[OK] ACTIVACION TOTAL COMPLETADA.")
    } elseif ($procOk -and $rtpOk -and $antivirusOk) {
        [void]$log.Add("[OK] Activacion funcional. Reinicia para completar.")
    } else {
        [void]$log.Add("[!] Activacion parcial. Pulsa ACTIVAR de nuevo o reinicia.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog "Activacion terminada" "INFO"
    return ($log -join "`n")
}

# ============================================================================
# SECCION 25 - HISTORIAL
# ============================================================================
$script:EventHistory = New-Object System.Collections.ArrayList

function Load-History {
    try {
        if (Test-Path $script:HistoryFile) {
            $data = Get-Content -Path $script:HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data -is [array]) {
                foreach ($e in $data) {
                    [void]$script:EventHistory.Add([PSCustomObject]@{
                        Hora=[DateTime]$e.Hora; Accion=$e.Accion; Resultado=$e.Resultado; Segundos=[double]$e.Segundos
                    })
                }
            }
        }
    } catch { }
}

function Add-History {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    try {
        $entry = [PSCustomObject]@{ Hora=(Get-Date); Accion=$Accion; Resultado=$Resultado; Segundos=$Segundos }
        [void]$script:EventHistory.Insert(0, $entry)
        while ($script:EventHistory.Count -gt 50) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
        $script:EventHistory | ConvertTo-Json -Depth 3 | Set-Content -Path $script:HistoryFile -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 26 - INFORME DETALLADO
# ============================================================================
function Get-DiagnosticReport {
    $r = New-Object System.Collections.ArrayList

    [void]$r.Add([PSCustomObject]@{Item="=== SERVICIOS DE DEFENDER ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $serviciosDefender = @(
        @{Nombre="WinDefend";             Desc="Servicio principal del antivirus"; Driver=$false},
        @{Nombre="WdNisSvc";              Desc="Inspeccion de red";                 Driver=$false},
        @{Nombre="Sense";                 Desc="Deteccion de intrusiones (EDR)";    Driver=$false},
        @{Nombre="WdNisDrv";              Desc="Driver de inspeccion de red";       Driver=$true},
        @{Nombre="WdBoot";                Desc="Driver de arranque";                Driver=$true},
        @{Nombre="Wdfilter";              Desc="Driver de filtro";                  Driver=$true},
        @{Nombre="SecurityHealthService"; Desc="Seguridad de Windows (UI)";         Driver=$false},
        @{Nombre="wscsvc";                Desc="Centro de seguridad";               Driver=$false}
    )
    foreach ($s in $serviciosDefender) {
        $svc = Get-Service -Name $s.Nombre -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            [void]$r.Add([PSCustomObject]@{Item="  " + $s.Nombre; Status="NO EXISTE"; Detail=$s.Desc; Color=$script:Colors.TextMuted})
            continue
        }
        $running = ($svc.Status -eq 'Running')
        $startMode = Get-ServiceStartMode -Name $s.Nombre
        $estado = "DESACTIVADO"
        if ($running) { $estado = "ACTIVADO" }
        $color = $script:Colors.Bad
        if ($running -and ($startMode -eq "Automatic" -or $startMode -eq "Boot" -or $startMode -eq "System")) {
            $color = $script:Colors.Ok
        } elseif ($running) {
            $color = $script:Colors.Warn
        } elseif ($s.Driver -and $startMode -eq "Boot") {
            $color = $script:Colors.Warn
        }
        $detalle = $s.Desc
        if ($s.Driver -and $startMode -eq "Boot" -and -not $running) {
            $detalle = $s.Desc + " (requiere reinicio)"
        }
        [void]$r.Add([PSCustomObject]@{Item="  " + $s.Nombre; Status="$estado ($startMode)"; Detail=$detalle; Color=$color})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== PROCESOS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($p in @("MsMpEng","NisSrv","SecurityHealthService","SecurityHealthSystray")) {
        $procs = @(Get-Process -Name $p -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            $pids = ($procs | ForEach-Object { $_.Id }) -join ", "
            [void]$r.Add([PSCustomObject]@{Item="  " + $p + ".exe"; Status="CORRIENDO"; Detail="PID: $pids"; Color=$script:Colors.Bad})
        } else {
            [void]$r.Add([PSCustomObject]@{Item="  " + $p + ".exe"; Status="DETENIDO"; Detail="No esta corriendo"; Color=$script:Colors.Ok})
        }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== MODULOS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
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
                $c = $script:Colors.Neutral
                $txt = "?"
                if ($m.V -eq $true) { $c = $script:Colors.Ok; $txt = "ACTIVADO" }
                elseif ($m.V -eq $false) { $c = $script:Colors.Bad; $txt = "DESACTIVADO" }
                [void]$r.Add([PSCustomObject]@{Item="  " + $m.N; Status=$txt; Detail=""; Color=$c})
            }

            [void]$r.Add([PSCustomObject]@{Item="=== FIRMAS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
            $vf = $st.AntivirusSignatureVersion
            $ef = $st.AntivirusSignatureAge
            $cf = $script:Colors.Ok
            if ($ef -gt 30 -or $ef -eq 65535) { $cf = $script:Colors.Bad }
            [void]$r.Add([PSCustomObject]@{Item="  Version de firma"; Status="$vf"; Detail=""; Color=$script:Colors.TextDiag})
            [void]$r.Add([PSCustomObject]@{Item="  Edad (dias)"; Status="$ef"; Detail=""; Color=$cf})
        } catch { }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== ANTIVIRUS DE TERCEROS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $avs = Get-ThirdPartyAV
    if ($avs.Count -eq 0) {
        [void]$r.Add([PSCustomObject]@{Item="  Ninguno detectado"; Status="OK"; Detail=""; Color=$script:Colors.Ok})
    } else {
        foreach ($av in $avs) {
            [void]$r.Add([PSCustomObject]@{Item="  " + $av.Nombre; Status="INSTALADO"; Detail=""; Color=$script:Colors.Warn})
        }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== CONECTIVIDAD ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $nets = Test-NetworkConnectivity
    foreach ($n in $nets) {
        $c = $script:Colors.Ok
        $st = "OK"
        if (-not $n.OK) { $c = $script:Colors.Bad; $st = "FALLA" }
        [void]$r.Add([PSCustomObject]@{Item="  " + $n.Nombre; Status=$st; Detail=$n.Host; Color=$c})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== REGISTRO (Start) ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
        $startMode = Get-ServiceStartMode -Name $s
        $startVal = "?"
        try {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
            if (Test-Path $p) {
                $v = (Get-ItemProperty -Path $p -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($null -ne $v) { $startVal = "$v ($startMode)" }
            }
        } catch { }
        $c = $script:Colors.Warn
        if ($startMode -eq "Disabled") { $c = $script:Colors.Bad }
        elseif ($startMode -eq "Automatic" -or $startMode -eq "Boot" -or $startMode -eq "System") { $c = $script:Colors.Ok }
        [void]$r.Add([PSCustomObject]@{Item="  Start $s"; Status=$startVal; Detail=""; Color=$c})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== POLITICAS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $hp = Test-DefenderPolicyDisabled
    $colorPol = $script:Colors.Ok
    $textoPol = "NO"
    if ($hp) { $colorPol = $script:Colors.Bad; $textoPol = "SI - BLOQUEA" }
    [void]$r.Add([PSCustomObject]@{Item="  Politica bloqueante"; Status=$textoPol; Detail=""; Color=$colorPol})

    [void]$r.Add([PSCustomObject]@{Item="=== INFORMACION DEL SCRIPT ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $hash = Get-ScriptHash
    [void]$r.Add([PSCustomObject]@{Item="  SHA256 (16 chars)"; Status=$hash; Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Ruta"; Status="Script"; Detail=$script:ScriptPath; Color=$script:Colors.TextMuted})
    [void]$r.Add([PSCustomObject]@{Item="  Carpeta datos"; Status="Config"; Detail=$script:ConfigDir; Color=$script:Colors.TextMuted})

    [void]$r.Add([PSCustomObject]@{Item="=== ESTADO GLOBAL ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $q = Get-QuickStatus
    $colorGlobal = $script:Colors.Neutral
    if ($q.Estado -eq "ACTIVO")      { $colorGlobal = $script:Colors.Ok }
    elseif ($q.Estado -eq "PARCIAL") { $colorGlobal = $script:Colors.Warn }
    elseif ($q.Estado -eq "DESACTIVADO") { $colorGlobal = $script:Colors.Bad }
    [void]$r.Add([PSCustomObject]@{Item="  RESULTADO FINAL"; Status=$q.Estado; Detail=""; Color=$colorGlobal})

    return $r
}

# ============================================================================
# SECCION 27 - DIAGNOSTICO (con scroll vertical)
# ============================================================================
function Show-DiagnosticsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Diagnostico del Sistema"
    $dlg.ClientSize = New-Object System.Drawing.Size(900, 640)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

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
    $lblSub.Text = "Servicios + Procesos + Modulos + Firmas + AV Terceros + Red + Registro"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 200)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(17, 38)
    $header.Controls.Add($lblSub)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 75)
    $lv.Size = New-Object System.Drawing.Size(870, 490)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    $lv.Anchor = "Top,Left,Right,Bottom"
    [void]$lv.Columns.Add("Elemento", 330)
    [void]$lv.Columns.Add("Estado", 230)
    [void]$lv.Columns.Add("Detalle", 300)
    $dlg.Controls.Add($lv)

    $btnRef   = New-NeonButton "Refrescar"     $script:Colors.AccentAmber $script:Colors.AccentAmberH 15  575 130 32
    $btnCopy  = New-NeonButton "Copiar"        $script:Colors.AccentCyan  $script:Colors.AccentCyanH  155 575 130 32
    $btnRep   = New-NeonButton "Reparar Firmas" $script:Colors.AccentGreen $script:Colors.AccentGreenH 295 575 150 32
    $btnCerr  = New-NeonButton "Cerrar"        $script:Colors.Neutral     $script:Colors.TextMuted    755 575 130 32
    $dlg.Controls.Add($btnRef); $dlg.Controls.Add($btnCopy); $dlg.Controls.Add($btnRep); $dlg.Controls.Add($btnCerr)

    $script:DiagLv = $lv

    $cargarDiag = {
        $script:DiagLv.Items.Clear()
        foreach ($row in (Get-DiagnosticReport)) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$row.Item)
            [void]$it.SubItems.Add([string]$row.Status)
            [void]$it.SubItems.Add([string]$row.Detail)
            if ($null -ne $row.Color) { $it.ForeColor = $row.Color; $it.UseItemStyleForSubItems = $true }
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
            [System.Windows.Forms.MessageBox]::Show("Diagnostico copiado.","OK","OK","Information") | Out-Null
        } catch { }
    })
    $btnRep.Add_Click({
        $log = Repair-DefenderSignatures
        Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $log -Tipo "Success"
        & $cargarDiag
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 28 - HISTORIAL DIALOGO
# ============================================================================
function Show-HistoryDialog {
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
    $lblH.Text = "HISTORIAL (ultimas 50)"
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
# SECCION 29 - REPARACION PROFUNDA
# ============================================================================
$script:RepairConsole = $null

function Invoke-ConsoleCmd {
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
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Reparacion Profunda"
    $dlg.ClientSize = New-Object System.Drawing.Size(940, 700)
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
    $lblSub.Text = "Ejecuta los comandos en una consola con registro en vivo"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 200)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(17, 38)
    $header.Controls.Add($lblSub)

    $console = New-Object System.Windows.Forms.TextBox
    $console.Multiline = $true
    $console.ScrollBars = "Vertical"
    $console.WordWrap = $true
    $console.ReadOnly = $true
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.Location = New-Object System.Drawing.Point(15, 75)
    $console.Size = New-Object System.Drawing.Size(910, 490)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)
    $script:RepairConsole = $console

    $btnReg  = New-NeonButton "1. Borrar Politicas"    $script:Colors.AccentRed    $script:Colors.AccentRedH    15  580 165 34
    $btnSvc  = New-NeonButton "2. Reiniciar Servicios" $script:Colors.AccentAmber  $script:Colors.AccentAmberH  190 580 175 34
    $btnGpu  = New-NeonButton "3. gpupdate"            $script:Colors.AccentPurple $script:Colors.AccentPurpH   375 580 130 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"        $script:Colors.AccentBlue   $script:Colors.AccentBlueH   515 580 140 34
    $btnDISM = New-NeonButton "5. DISM Restore"        $script:Colors.AccentCyan   $script:Colors.AccentCyanH   665 580 140 34
    $btnKill = New-NeonButton "Matar MsMpEng"          $script:Colors.AccentRed    $script:Colors.AccentRedH    815 580 110 34

    $btnFirmas = New-NeonButton "REPARAR FIRMAS"  $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 625 250 40
    $btnTodo   = New-NeonButton "REPARAR TODO"    $script:Colors.AccentGreen $script:Colors.AccentGreenH 275 625 250 40
    $btnCerr   = New-NeonButton "Cerrar"          $script:Colors.Neutral     $script:Colors.TextMuted   815 625 110 40

    foreach ($b in @($btnReg,$btnSvc,$btnGpu,$btnSFC,$btnDISM,$btnKill,$btnFirmas,$btnTodo,$btnCerr)) {
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

    $btnFirmas.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n==============================================`r`n")
        $c.AppendText("  REPARACION DE FIRMAS CORRUPTAS`r`n")
        $c.AppendText("==============================================`r`n")
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) {
            $c.AppendText("$linea`r`n")
        }
        Add-History -Accion "Reparar Firmas" -Resultado "OK" -Segundos 0
        Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $repLog -Tipo "Success"
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
        $c.AppendText("`r`n[PASO 5] Reparando firmas...`r`n")
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        $c.AppendText("`r`n[PASO 6] sfc /scannow...`r`n")
        Invoke-ConsoleCmd "sfc /scannow"
        $c.AppendText("`r`n[PASO 7] DISM RestoreHealth...`r`n")
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("`r`n==============================================`r`n")
        $c.AppendText("  REPARACION COMPLETADA`r`n")
        $c.AppendText("  REINICIA EL EQUIPO PARA APLICAR LOS CAMBIOS.`r`n")
        $c.AppendText("==============================================`r`n")
        Add-History -Accion "Reparacion Completa" -Resultado "OK" -Segundos 0
        Show-ResultDialog -Titulo "Reparacion Completada" -Mensaje "Reparacion profunda completada.`n`nREINICIA EL EQUIPO." -Tipo "Success"
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    $console.AppendText("==============================================`r`n")
    $console.AppendText("  CONSOLA DE REPARACION - DefenderTray v5.0`r`n")
    $console.AppendText("==============================================`r`n")
    $console.AppendText("`r`nPuedes ejecutar cada paso individual o pulsar`r`n")
    $console.AppendText("REPARAR TODO o REPARAR FIRMAS.`r`n`r`n")

    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ============================================================================
# SECCION 30 - PROGRAMADOR DE TAREAS
# ============================================================================
function Register-TrayTask {
    param([string]$Nombre, [string]$Accion, [string]$Hora)
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`" -silent -action $Accion"
        $trigger = New-ScheduledTaskTrigger -Daily -At $Hora
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        Register-ScheduledTask -TaskName "DefenderTray_$Nombre" -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

function Unregister-TrayTask {
    param([string]$Nombre)
    try { Unregister-ScheduledTask -TaskName "DefenderTray_$Nombre" -Confirm:$false -ErrorAction Stop; return $true } catch { return $false }
}

function Get-TrayTasks {
    try { return Get-ScheduledTask -TaskName "DefenderTray_*" -ErrorAction SilentlyContinue } catch { return @() }
}

function Show-SchedulerDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Programador de tareas"
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 480)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentPurple
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "PROGRAMADOR"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text = "Desactivar a las:"; $lbl1.ForeColor = $script:Colors.Text
    $lbl1.Location = New-Object System.Drawing.Point(20, 110); $lbl1.Size = New-Object System.Drawing.Size(150, 25)
    $dlg.Controls.Add($lbl1)
    $dtpDisable = New-Object System.Windows.Forms.DateTimePicker
    $dtpDisable.Format = "Time"; $dtpDisable.ShowUpDown = $true
    $dtpDisable.Location = New-Object System.Drawing.Point(180, 108); $dtpDisable.Size = New-Object System.Drawing.Size(130, 25)
    $dtpDisable.Value = (Get-Date).Date.AddHours(22); $dlg.Controls.Add($dtpDisable)
    $chkDisable = New-Object System.Windows.Forms.CheckBox
    $chkDisable.Text = "Activar"; $chkDisable.Location = New-Object System.Drawing.Point(330, 108)
    $chkDisable.Size = New-Object System.Drawing.Size(80, 25); $chkDisable.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkDisable)

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text = "Activar a las:"; $lbl2.ForeColor = $script:Colors.Text
    $lbl2.Location = New-Object System.Drawing.Point(20, 150); $lbl2.Size = New-Object System.Drawing.Size(150, 25)
    $dlg.Controls.Add($lbl2)
    $dtpEnable = New-Object System.Windows.Forms.DateTimePicker
    $dtpEnable.Format = "Time"; $dtpEnable.ShowUpDown = $true
    $dtpEnable.Location = New-Object System.Drawing.Point(180, 148); $dtpEnable.Size = New-Object System.Drawing.Size(130, 25)
    $dtpEnable.Value = (Get-Date).Date.AddHours(7); $dlg.Controls.Add($dtpEnable)
    $chkEnable = New-Object System.Windows.Forms.CheckBox
    $chkEnable.Text = "Activar"; $chkEnable.Location = New-Object System.Drawing.Point(330, 148)
    $chkEnable.Size = New-Object System.Drawing.Size(80, 25); $chkEnable.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkEnable)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(20, 200); $lv.Size = New-Object System.Drawing.Size(580, 180)
    $lv.BorderStyle = "FixedSingle"; $lv.BackColor = $script:Colors.BgSecondary; $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Nombre", 200); [void]$lv.Columns.Add("Estado", 100); [void]$lv.Columns.Add("Proxima", 250)
    foreach ($t in (Get-TrayTasks)) {
        $it = New-Object System.Windows.Forms.ListViewItem($t.TaskName)
        [void]$it.SubItems.Add($t.State)
        $next = ""
        try { $next = ($t.Triggers | Select-Object -First 1).StartBoundary } catch { }
        [void]$it.SubItems.Add($next)
        [void]$lv.Items.Add($it)
    }
    $dlg.Controls.Add($lv)

    $btnGuardar = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 400 180 34
    $btnEliminar = New-NeonButton "Eliminar" $script:Colors.AccentRed $script:Colors.AccentRedH 210 400 180 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 420 400 180 34
    $dlg.Controls.Add($btnGuardar); $dlg.Controls.Add($btnEliminar); $dlg.Controls.Add($btnCerr)

    $btnGuardar.Add_Click({
        if ($chkDisable.Checked) {
            $hora = $dtpDisable.Value.ToString("HH:mm")
            $null = Register-TrayTask -Nombre "Desactivar" -Accion "disable" -Hora $hora
        }
        if ($chkEnable.Checked) {
            $hora = $dtpEnable.Value.ToString("HH:mm")
            $null = Register-TrayTask -Nombre "Activar" -Accion "enable" -Hora $hora
        }
        [System.Windows.Forms.MessageBox]::Show("Tareas programadas.","OK","OK","Information") | Out-Null
    })
    $btnEliminar.Add_Click({
        Unregister-TrayTask -Nombre "Desactivar" | Out-Null
        Unregister-TrayTask -Nombre "Activar" | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Tareas eliminadas.","OK","OK","Information") | Out-Null
        $dlg.Close()
    })
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 31 - INSTALACION COMO SERVICIO
# ============================================================================
function Install-AsService {
    try {
        if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { return "Ruta no valida." }
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName "DefenderTray_Service" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        return "Instalado correctamente al inicio del sistema."
    } catch { return "Error: $($_.Exception.Message)" }
}

function Uninstall-AsService {
    try {
        Unregister-ScheduledTask -TaskName "DefenderTray_Service" -Confirm:$false -ErrorAction Stop
        return "Desinstalado."
    } catch { return "Error: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 32 - DIALOGO MODO KIOSCO
# ============================================================================
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    if ([string]::IsNullOrEmpty($script:CfgKioskHash)) { return $true }

    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"
    $dlg.ClientSize = New-Object System.Drawing.Size(360, 160)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Introduce la " + (T "Password") + ":"
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
    $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.BackColor = $script:Colors.AccentGreen
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Location = New-Object System.Drawing.Point(255, 80)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.BackColor = $script:Colors.AccentRed
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnCancel)

    $btnOk.Add_Click({
        $h = Get-StringHash $txt.Text
        if ($h -eq $script:CfgKioskHash) {
            $script:KioskOk = $true
            $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Contrasena incorrecta.","Acceso","OK","Error") | Out-Null
            $txt.Clear(); $txt.Focus()
        }
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.AcceptButton = $btnOk

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:KioskOk
}

# ============================================================================
# SECCION 33 - CONFIGURACION
# ============================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 480)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
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

    $chkAutoRepair = New-Object System.Windows.Forms.CheckBox
    $chkAutoRepair.Text = "Auto-reparar firmas al iniciar (>30 dias)"
    $chkAutoRepair.Checked = $script:CfgAutoRepair
    $chkAutoRepair.Location = New-Object System.Drawing.Point(20, 65)
    $chkAutoRepair.Size = New-Object System.Drawing.Size(500, 25)
    $chkAutoRepair.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkAutoRepair)

    $chkAutoCleanup = New-Object System.Windows.Forms.CheckBox
    $chkAutoCleanup.Text = "Limpiar logs de mas de 30 dias"
    $chkAutoCleanup.Checked = $script:CfgAutoCleanup
    $chkAutoCleanup.Location = New-Object System.Drawing.Point(20, 95)
    $chkAutoCleanup.Size = New-Object System.Drawing.Size(500, 25)
    $chkAutoCleanup.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkAutoCleanup)

    $chkKiosk = New-Object System.Windows.Forms.CheckBox
    $chkKiosk.Text = "Modo kiosco (pedir " + (T "Password") + " al abrir)"
    $chkKiosk.Checked = $script:IsKioskMode
    $chkKiosk.Location = New-Object System.Drawing.Point(20, 125)
    $chkKiosk.Size = New-Object System.Drawing.Size(500, 25)
    $chkKiosk.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($chkKiosk)

    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = (T "Password") + ":"
    $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(40, 160)
    $lblPwd.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblPwd)

    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'
    $txtPwd.Location = New-Object System.Drawing.Point(160, 158)
    $txtPwd.Size = New-Object System.Drawing.Size(370, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary
    $txtPwd.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtPwd)

    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.Text = "Idioma / Language:"
    $lblLang.ForeColor = $script:Colors.Text
    $lblLang.Location = New-Object System.Drawing.Point(20, 200)
    $lblLang.Size = New-Object System.Drawing.Size(150, 25)
    $dlg.Controls.Add($lblLang)

    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.Items.AddRange(@("ES","EN"))
    $cmbLang.SelectedItem = $script:Lang
    $cmbLang.Location = New-Object System.Drawing.Point(180, 198)
    $cmbLang.Size = New-Object System.Drawing.Size(100, 25)
    $cmbLang.BackColor = $script:Colors.BgSecondary
    $cmbLang.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($cmbLang)

    $lblSvcInfo = New-Object System.Windows.Forms.Label
    $lblSvcInfo.Text = "Instalacion como servicio (tarea al inicio):"
    $lblSvcInfo.ForeColor = $script:Colors.TextMuted
    $lblSvcInfo.Location = New-Object System.Drawing.Point(20, 240)
    $lblSvcInfo.Size = New-Object System.Drawing.Size(500, 20)
    $dlg.Controls.Add($lblSvcInfo)

    $btnInstallSvc = New-NeonButton "Instalar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 270 180 34
    $btnUninstallSvc = New-NeonButton "Desinstalar" $script:Colors.AccentRed $script:Colors.AccentRedH 210 270 180 34
    $dlg.Controls.Add($btnInstallSvc); $dlg.Controls.Add($btnUninstallSvc)

    $btnScheduler = New-NeonButton "Programar tareas" $script:Colors.AccentPurple $script:Colors.AccentPurpH 20 320 200 34
    $dlg.Controls.Add($btnScheduler)

    $btnRestoreReg = New-NeonButton "Restaurar registro" $script:Colors.AccentAmber $script:Colors.AccentAmberH 230 320 200 34
    $dlg.Controls.Add($btnRestoreReg)

    $btnSave   = New-NeonButton "Guardar"  $script:Colors.AccentGreen  $script:Colors.AccentGreenH 20  400 200 34
    $btnCancel = New-NeonButton "Cancelar" $script:Colors.Neutral      $script:Colors.TextMuted   300 400 180 34
    $dlg.Controls.Add($btnSave)
    $dlg.Controls.Add($btnCancel)

    $btnSave.Add_Click({
        $script:CfgAutoRepair = $chkAutoRepair.Checked
        $script:CfgAutoCleanup = $chkAutoCleanup.Checked
        $script:IsKioskMode = $chkKiosk.Checked
        $script:Lang = $cmbLang.SelectedItem
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:CfgKioskHash = Get-StringHash $txtPwd.Text
        }
        if (-not $chkKiosk.Checked) { $script:CfgKioskHash = "" }
        Save-AppConfig
        [System.Windows.Forms.MessageBox]::Show("Configuracion guardada.","OK","OK","Information") | Out-Null
        $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.Close() })

    $btnInstallSvc.Add_Click({
        $r = Install-AsService
        [System.Windows.Forms.MessageBox]::Show($r, "Instalar", "OK", "Information") | Out-Null
    })
    $btnUninstallSvc.Add_Click({
        $r = Uninstall-AsService
        [System.Windows.Forms.MessageBox]::Show($r, "Desinstalar", "OK", "Information") | Out-Null
    })
    $btnScheduler.Add_Click({ Show-SchedulerDialog })
    $btnRestoreReg.Add_Click({
        $archivos = Get-ChildItem -Path $script:RegBackupDir -Filter "*.reg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($archivos.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No hay backups de registro.","Info","OK","Information") | Out-Null
            return
        }
        $ultimo = $archivos[0].FullName
        if (Show-ConfirmDialog "Restaurar registro" "Restaurar desde:`n$ultimo`n`nContinuar?") {
            if (Restore-DefenderRegistry -Archivo $ultimo) {
                [System.Windows.Forms.MessageBox]::Show("Registro restaurado.","OK","OK","Information") | Out-Null
            }
        }
    })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 34 - AYUDA
# ============================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(760, 560)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
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
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = "Vertical"
    $txt.WordWrap = $true
    $txt.Location = New-Object System.Drawing.Point(15, 65)
    $txt.Size = New-Object System.Drawing.Size(730, 440)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $ayuda = @'
DEFENDER CONTROL v5.0 PRO
===========================

ICONOS DINAMICOS
----------------
El icono de la bandeja cambia de color:
  VERDE   -> ACTIVADO
  ROJO    -> DESACTIVADO
  NARANJA -> PARCIAL

ACTIVACION CON DEPENDENCIAS
---------------------------
Los servicios se arrancan en este orden:
  1. WinDefend (padre)
  2. WdNisSvc (depende de WinDefend)
  3. Sense (depende de WinDefend + WdNisSvc)
  4. SecurityHealthService
  5. wscsvc

Si alguno falla, se reintenta hasta 4 veces.

REPARAR FIRMAS CORRUPTAS
------------------------
Si ves "Version creada el: 31/12/1969" o firmas >30 dias,
usa el boton "Reparar Firmas" en Diagnostico o Reparacion Profunda.

AUTO-REPARACION
---------------
Al iniciar la app, si las firmas tienen >30 dias, se reparan
automaticamente (configurable en Configuracion).

DESACTIVACION TOTAL
-------------------
En Windows 11 22H2+ el kernel de Windows reinicia WinDefend
automaticamente. Los cambios de registro (Start=4) YA se aplican,
pero el reinicio del equipo es la unica forma de completar la
desactivacion en caliente.

REPARACION PROFUNDA
-------------------
Ejecuta en consola con registro en vivo:
  1. reg delete (borrar politicas)
  2. sc config/start (servicios)
  3. gpupdate /force
  4. sfc /scannow
  5. DISM /RestoreHealth
  6. Reparar Firmas Corruptas

CONFIGURACION
-------------
- Auto-reparar firmas al iniciar
- Limpiar logs >30 dias
- Modo kiosco con contrasena
- Idioma ES/EN
- Instalacion como servicio (tarea al inicio)
- Programador de tareas (activar/desactivar por horario)
- Restaurar registro desde backup

MODO KIOSCO
-----------
1. Config -> marcar "Modo kiosco"
2. Escribir contrasena
3. Guardar
4. Al abrir el panel pedira la contrasena

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

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 605 515 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 35 - ESTADISTICAS HISTORICAS
# ============================================================================
function Show-StatsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Estadisticas"
    $dlg.ClientSize = New-Object System.Drawing.Size(800, 560)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.AccentCyan
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "ESTADISTICAS"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)

    try {
        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Location = New-Object System.Drawing.Point(15, 70)
        $chart.Size = New-Object System.Drawing.Size(770, 440)
        $chart.BackColor = $script:Colors.BgSecondary
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
        $area.BackColor = $script:Colors.BgSecondary
        $area.AxisX.LabelStyle.ForeColor = $script:Colors.Text
        $area.AxisY.LabelStyle.ForeColor = $script:Colors.Text
        [void]$chart.ChartAreas.Add($area)
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name = "Operaciones"; $series.ChartType = "Column"
        $series.Color = $script:Colors.AccentCyan
        $porDia = @{}
        foreach ($e in $script:EventHistory) {
            $k = $e.Hora.ToString("dd/MM")
            if (-not $porDia.ContainsKey($k)) { $porDia[$k] = 0 }
            $porDia[$k]++
        }
        foreach ($k in ($porDia.Keys | Sort-Object)) { [void]$series.Points.AddXY($k, $porDia[$k]) }
        [void]$chart.Series.Add($series)
        $dlg.Controls.Add($chart)
    } catch {
        $lblNo = New-Object System.Windows.Forms.Label
        $lblNo.Text = "Grafico no disponible."
        $lblNo.ForeColor = $script:Colors.Text
        $lblNo.Location = New-Object System.Drawing.Point(15, 100)
        $lblNo.Size = New-Object System.Drawing.Size(400, 25)
        $dlg.Controls.Add($lblNo)
    }

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 645 520 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 36 - PANEL PRINCIPAL
# ============================================================================
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
$script:PanelAllButtons    = @()
$script:IsBusy             = $false
$script:ActionStartTicks   = $null
$script:LastActionTime     = 0
$script:LastActionName     = ""

function Set-PanelBusy {
    param([bool]$Busy)
    foreach ($b in $script:PanelAllButtons) {
        if ($null -ne $b) {
            try { $b.Enabled = -not $Busy } catch { }
            if ($Busy) {
                $b.BackColor = $script:Colors.BtnDisabled
                $b.ForeColor = $script:Colors.BtnDisabledT
                $b.Cursor = "Default"
            } else {
                $b.BackColor = $b.Tag.Normal
                $b.ForeColor = [System.Drawing.Color]::White
                $b.Cursor = "Hand"
            }
        }
    }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $s = Get-QuickStatus
    $diag = "Svc:$($s.ServiceRunning) | Motor:$($s.EngineRunning) | RTP:$($s.RealTimeProtectionEnabled) | Pol:$($s.HasPolicy)"

    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $false
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "ACTIVADO"
            $script:PanelStatusLabel.ForeColor = $script:Colors.Ok
        }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Falta proteccion real. Pulsa ACTIVAR o reinicia."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "PARCIAL"
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
            $script:PanelStatusLabel.Text = "DESACTIVADO"
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
    if ($null -ne $script:PanelTimer) {
        try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
        $script:PanelTimer = $null
    }
    $script:PanelTimer = New-Object System.Windows.Forms.Timer
    $script:PanelTimer.Interval = 5000
    $script:PanelTimer.Add_Tick({
        if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
        $script:PanelLblReloj.Text = (Get-Date).ToString("HH:mm:ss")

        if ($null -ne $script:ActionStartTicks -and $script:ActionStartTicks -is [long]) {
            $el = ([DateTime]::Now.Ticks - $script:ActionStartTicks) / 10000000
            $script:PanelLblTimer.Text = "{0:N2}s" -f $el
        } else {
            $script:PanelLblTimer.Text = "listo"
        }

        if (-not $script:IsBusy) {
            try { Update-PanelStatusUI } catch { }
        }
    })
    $script:PanelTimer.Start()
}

function Show-DefenderPanel {
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
    $script:ActionStartTicks = $null
    $script:LastActionTime = 0
    $script:LastActionName = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (T "Title")
    $form.ClientSize = New-Object System.Drawing.Size(470, 495)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = $script:IconOk

    $menuStrip = New-Object System.Windows.Forms.MenuStrip
    $menuStrip.BackColor = $script:Colors.MenuBg
    $menuStrip.ForeColor = $script:Colors.Text
    $menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $menuStrip.Dock = "Top"

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

    $mAcciones = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAcciones.Text = "&Acciones"
    $mAcciones.ForeColor = $script:Colors.Text
    $miAct = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAct.Text = "Activar"
    $miAct.Add_Click({
        if (-not (Test-Admin)) { return }
        try {
            $script:IsBusy = $true; Set-PanelBusy $true
            Start-ActionTimer; $script:LastActionName = "Activar"
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed; Stop-ActionTimer | Out-Null
            $script:IsBusy = $false; Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
        } finally {
            $script:IsBusy = $false
            Stop-ActionTimer | Out-Null
            Set-PanelBusy $false
        }
    })
    $miDes = New-Object System.Windows.Forms.ToolStripMenuItem
    $miDes.Text = "Desactivar"
    $miDes.Add_Click({
        if (-not (Test-Admin)) { return }
        try {
            $script:IsBusy = $true; Set-PanelBusy $true
            Start-ActionTimer; $script:LastActionName = "Desactivar"
            [System.Windows.Forms.Application]::DoEvents()
            $null = Disable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed; Stop-ActionTimer | Out-Null
            $script:IsBusy = $false; Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
        } finally {
            $script:IsBusy = $false
            Stop-ActionTimer | Out-Null
            Set-PanelBusy $false
        }
    })
    $miVer = New-Object System.Windows.Forms.ToolStripMenuItem
    $miVer.Text = "Verificar estado"
    $miVer.Add_Click({ Show-DiagnosticsDialog })
    [void]$mAcciones.DropDownItems.Add($miAct)
    [void]$mAcciones.DropDownItems.Add($miDes)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miVer)

    $mHerram = New-Object System.Windows.Forms.ToolStripMenuItem
    $mHerram.Text = "&Herramientas"
    $mHerram.ForeColor = $script:Colors.Text
    $miRep = New-Object System.Windows.Forms.ToolStripMenuItem
    $miRep.Text = "Reparacion Profunda"
    $miRep.Add_Click({ Show-DeepRepairDialog })
    $miHist = New-Object System.Windows.Forms.ToolStripMenuItem
    $miHist.Text = "Historial"
    $miHist.Add_Click({ Show-HistoryDialog })
    $miStats = New-Object System.Windows.Forms.ToolStripMenuItem
    $miStats.Text = "Estadisticas"
    $miStats.Add_Click({ Show-StatsDialog })
    $miConf = New-Object System.Windows.Forms.ToolStripMenuItem
    $miConf.Text = "Configuracion"
    $miConf.Add_Click({ Show-SettingsDialog })
    [void]$mHerram.DropDownItems.Add($miRep)
    [void]$mHerram.DropDownItems.Add($miHist)
    [void]$mHerram.DropDownItems.Add($miStats)
    [void]$mHerram.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHerram.DropDownItems.Add($miConf)

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"
    $mAyuda.ForeColor = $script:Colors.Text
    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAy.Text = "Ayuda (F1)"
    $miAy.Add_Click({ Show-HelpDialog })
    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v5.0 Pro`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911`n`nSHA256: $($script:ScriptHash)"
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
    $lblSubH.Text = "v5.0 Pro - Total Disable Edition"
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

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 105)
    $card.Size = New-Object System.Drawing.Size(440, 130)
    $card.BackColor = $script:Colors.CardBg
    $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)
    $lblTag = New-Object System.Windows.Forms.Label
    $lblTag.Text = (T "EstadoActual")
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

    $btnDiagnostico = New-NeonButton (T "Diagnostico")  $script:Colors.AccentPurple $script:Colors.AccentPurpH  15  245 440 32
    $btnActivar     = New-NeonButton (T "Activar")      $script:Colors.AccentGreen  $script:Colors.AccentGreenH 15  285 215 32
    $btnDesactivar  = New-NeonButton (T "Desactivar")   $script:Colors.AccentRed    $script:Colors.AccentRedH   240 285 215 32
    $btnReparar     = New-NeonButton (T "Reparar")      $script:Colors.AccentAmber  $script:Colors.AccentAmberH 15  325 440 36
    $btnHistorial   = New-NeonButton (T "Historial")    $script:Colors.AccentBlue   $script:Colors.AccentBlueH  15  370 105 32
    $btnConfig      = New-NeonButton (T "Config")       $script:Colors.AccentBlue   $script:Colors.AccentBlueH  125 370 105 32
    $btnAyuda       = New-NeonButton (T "Ayuda")        $script:Colors.AccentBlue   $script:Colors.AccentBlueH  235 370 105 32
    $btnSalir       = New-NeonButton (T "Salir")        $script:Colors.AccentRed    $script:Colors.AccentRedH   345 370 110 32

    $script:PanelAllButtons = @($btnDiagnostico,$btnActivar,$btnDesactivar,$btnReparar,$btnHistorial,$btnConfig,$btnAyuda,$btnSalir)
    foreach ($b in $script:PanelAllButtons) { $form.Controls.Add($b) }

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
    $statusLabel.AutoSize = $false
    [void]$statusStrip.Items.Add($statusLabel)

    $statusShortcuts = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusShortcuts.Text = "F1|F5|Esc"
    $statusShortcuts.ForeColor = $script:Colors.TextMuted
    $statusShortcuts.AutoSize = $true
    [void]$statusStrip.Items.Add($statusShortcuts)

    $form.Controls.Add($statusStrip)
    $script:PanelStatusLabel = $statusLabel

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
            Set-PanelBusy $true
            Start-ActionTimer
            $script:LastActionName = "Activar"
            $script:PanelLblDet1.Text = "Activando..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed
            Stop-ActionTimer | Out-Null
            $script:IsBusy = $false
            Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
            $tipo = "Warning"
            if ($s.Estado -eq "ACTIVO") { $tipo = "Success" }
            Show-ResultDialog -Titulo "Resultado de Activacion" -Mensaje ("Estado: $($s.Estado)`nTiempo: {0:N2} segundos`n`n$log" -f $elapsed) -Tipo $tipo
        } finally {
            $script:IsBusy = $false
            Stop-ActionTimer | Out-Null
            Set-PanelBusy $false
        }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        if (-not (Show-ConfirmDialog "Confirmar" "Desactivar Windows Defender?`n`nPuede requerir REINICIO.")) { return }
        try {
            $script:IsBusy = $true
            Set-PanelBusy $true
            Start-ActionTimer
            $script:LastActionName = "Desactivar"
            $script:PanelLblDet1.Text = "Desactivando TOTAL..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Disable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed
            Stop-ActionTimer | Out-Null
            $script:IsBusy = $false
            Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
            $extra = ""
            if ($s.Estado -ne "DESACTIVADO") { $extra = "`n`nREINICIA EL EQUIPO." }
            $tipo = "Warning"
            if ($s.Estado -eq "DESACTIVADO") { $tipo = "Success" }
            Show-ResultDialog -Titulo "Resultado de Desactivacion" -Mensaje ("Estado: $($s.Estado)`nTiempo: {0:N2} segundos$extra`n`n$log" -f $elapsed) -Tipo $tipo
        } finally {
            $script:IsBusy = $false
            Stop-ActionTimer | Out-Null
            Set-PanelBusy $false
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
# SECCION 37 - ARRANQUE
# ============================================================================
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v5.0 Pro iniciado" "INFO"
Write-AppLog "SHA256: $(Get-ScriptHash)" "INFO"
Write-AppLog "=============================================" "INFO"

if (Test-Admin) {
    Write-AppLog "Admin: SI" "INFO"
    try { Add-MpPreference -ExclusionPath $script:ScriptDir -Force -ErrorAction SilentlyContinue } catch { }
} else {
    Write-AppLog "Admin: NO" "WARN"
}

# Limpieza de logs antiguos
Clear-OldLogs

# Cargar historial
Load-History

# Auto-reparacion al iniciar
Invoke-StartupAutoRepair

# Accion programada
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
# SECCION 38 - ICONO DE BANDEJA Y MENU CONTEXTUAL
# ============================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = (T "Title")
$script:notifyIcon.Visible = $true
Update-TrayIcon -Estado $initQuick.Estado

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor = $script:Colors.MenuBg
$menu.ForeColor = $script:Colors.Text
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 9)

function Add-MenuItem {
    param([string]$Texto, [scriptblock]$Accion)
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $Texto
    $mi.ForeColor = $script:Colors.Text
    $mi.Add_Click($Accion)
    return $mi
}

[void]$menu.Items.Add((Add-MenuItem "Abrir panel" { Show-DefenderPanel }))
[void]$menu.Items.Add((Add-MenuItem "Diagnostico" { Show-DiagnosticsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Reparar Firmas" {
    $log = Repair-DefenderSignatures
    Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $log -Tipo "Success"
}))
[void]$menu.Items.Add((Add-MenuItem "Reparacion Profunda" { Show-DeepRepairDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((Add-MenuItem "Historial" { Show-HistoryDialog }))
[void]$menu.Items.Add((Add-MenuItem "Estadisticas" { Show-StatsDialog }))
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
# SECCION 39 - BUCLE PRINCIPAL
# ============================================================================
[System.Windows.Forms.Application]::Run()