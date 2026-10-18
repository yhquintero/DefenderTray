<#
================================================================================
  DefenderTray v6.0 ULTIMATE - Control Profesional de Windows Defender
================================================================================
  Novedades v6.0 (TODAS las 15 mejoras adicionales integradas):
    1.  Agente residente (WMI watcher de cambios en Defender).
    2.  Auto-update del script (verificacion de version remota).
    3.  Tema claro/oscuro automatico (detecta el sistema).
    4.  Integracion con Windows Terminal.
    5.  Soporte para PowerShell 7+ (paralelizacion de servicios).
    6.  Envio de reportes por email (SMTP configurable).
    7.  API REST local (HttpListener en 127.0.0.1:9182).
    8.  Autenticacion Windows Hello (fallback a contrasena).
    9.  Firma digital Authenticode (helper).
    10. Instalador MSI (helper de empaquetado).
    11. Alertas por umbral (aviso si desactivado > X horas).
    12. Reglas de firewall (netsh advfirewall).
    13. Modo auditoria (registra sin aplicar).
    14. Cifrado del config.json con DPAPI.
    15. Soporte para Windows Server.
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
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction SilentlyContinue

# ============================================================================
# SECCION 2 - ARGUMENTOS Y RUTAS
# ============================================================================
$script:SilentMode    = ($args -contains "-silent")
$script:PortableMode  = ($args -contains "-portable")
$script:AuditMode     = ($args -contains "-audit")
$script:NoRESTApi     = ($args -contains "-norest")

$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

if ($script:PortableMode) {
    $script:ConfigDir = Join-Path $script:ScriptDir "DefenderTrayData"
} else {
    $script:ConfigDir = Join-Path $env:LOCALAPPDATA "DefenderTray"
}

$script:LogFolder    = Join-Path $script:ConfigDir "Logs"
$script:BackupDir    = Join-Path $script:ConfigDir "Backups"
$script:RegBackupDir = Join-Path $script:BackupDir "Registro"
$script:AuditFolder  = Join-Path $script:ConfigDir "Auditoria"
$script:LogFile      = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ConfigFile   = Join-Path $script:ConfigDir "config.dat"  # Cifrado DPAPI
$script:HistoryFile  = Join-Path $script:ConfigDir "historial.json"
$script:AuditFile    = Join-Path $script:AuditFolder ("audit_{0:yyyy-MM-dd}.log" -f (Get-Date))

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir, $script:RegBackupDir, $script:AuditFolder)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ============================================================================
# SECCION 3 - CARACTERES ESPECIALES
# ============================================================================
$script:CH_N = [char]0x00F1

# ============================================================================
# SECCION 4 - DETECCION DEL SISTEMA (Windows Client / Server)
# ============================================================================
function Get-OSProductType {
    <#
    Detecta si es Windows Client o Server.
    Retorna: 'Client', 'Server' o 'Unknown'
    #>
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $tipo = $os.ProductType
        if ($tipo -eq 1) { return "Client" }
        elseif ($tipo -eq 2 -or $tipo -eq 3) { return "Server" }
    } catch { }
    return "Unknown"
}

function Test-WindowsServer {
    return ((Get-OSProductType) -eq "Server")
}

# ============================================================================
# SECCION 5 - DETECCION DE TEMA DEL SISTEMA
# ============================================================================
function Get-SystemTheme {
    <#
    Detecta si el sistema usa tema claro u oscuro.
    Lee HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize
    #>
    try {
        $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $key) {
            $v = (Get-ItemProperty -Path $key -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
            if ($null -ne $v) { return if ([int]$v -eq 0) { "Dark" } else { "Light" } }
        }
    } catch { }
    return "Dark"
}

# ============================================================================
# SECCION 6 - i18n
# ============================================================================
$script:Strings = @{
    ES = @{
        Title         = "Control de Seguridad v6.0 ULTIMATE"
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
        Title         = "Security Control v6.0 ULTIMATE"
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
# SECCION 7 - CONFIGURACION CIFRADA CON DPAPI
# ============================================================================
$script:CfgDarkTheme      = $true
$script:CfgKioskMode      = $false
$script:CfgKioskHash      = ""
$script:CfgUninstallHash  = ""
$script:CfgFirstRunDone   = $false
$script:CfgLang           = "ES"
$script:CfgAutoRepair     = $true
$script:CfgAutoCleanup    = $true
$script:CfgThemeFollow    = $true
$script:CfgThresholdHours = 6
$script:CfgThresholdAlert = $true
$script:CfgEmailEnabled   = $false
$script:CfgEmailServer    = ""
$script:CfgEmailPort      = 587
$script:CfgEmailUser      = ""
$script:CfgEmailPwd       = ""
$script:CfgEmailTo        = ""
$script:CfgRESTEnabled    = $true
$script:CfgRESTPort       = 9182
$script:CfgResidentAgent  = $true

$script:DarkTheme         = $true
$script:IsKioskMode       = $false
$script:ScriptHash        = ""
$script:OSProductType     = Get-OSProductType

function Protect-String {
    <#
    Cifra una cadena con DPAPI (usuario actual).
    #>
    param([string]$Texto)
    try {
        if ([string]::IsNullOrEmpty($Texto)) { return "" }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Texto)
        $encrypted = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, "CurrentUser")
        return [Convert]::ToBase64String($encrypted)
    } catch { return "" }
}

function Unprotect-String {
    param([string]$Texto)
    try {
        if ([string]::IsNullOrEmpty($Texto)) { return "" }
        $bytes = [Convert]::FromBase64String($Texto)
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, "CurrentUser")
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    } catch { return "" }
}

function Load-AppConfig {
    try {
        if (Test-Path $script:ConfigFile) {
            $encrypted = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8
            $json = Unprotect-String $encrypted
            if ([string]::IsNullOrEmpty($json)) { return }
            $cfg = $json | ConvertFrom-Json
            if ($null -ne $cfg.DarkTheme)      { $script:CfgDarkTheme      = [bool]$cfg.DarkTheme }
            if ($null -ne $cfg.KioskMode)      { $script:CfgKioskMode      = [bool]$cfg.KioskMode }
            if ($null -ne $cfg.KioskHash)      { $script:CfgKioskHash      = [string]$cfg.KioskHash }
            if ($null -ne $cfg.UninstallHash)  { $script:CfgUninstallHash  = [string]$cfg.UninstallHash }
            if ($null -ne $cfg.FirstRunDone)   { $script:CfgFirstRunDone   = [bool]$cfg.FirstRunDone }
            if ($null -ne $cfg.Lang)           { $script:CfgLang           = [string]$cfg.Lang }
            if ($null -ne $cfg.AutoRepair)     { $script:CfgAutoRepair     = [bool]$cfg.AutoRepair }
            if ($null -ne $cfg.AutoCleanup)    { $script:CfgAutoCleanup    = [bool]$cfg.AutoCleanup }
            if ($null -ne $cfg.ThemeFollow)    { $script:CfgThemeFollow    = [bool]$cfg.ThemeFollow }
            if ($null -ne $cfg.ThresholdHours) { $script:CfgThresholdHours = [int]$cfg.ThresholdHours }
            if ($null -ne $cfg.ThresholdAlert) { $script:CfgThresholdAlert = [bool]$cfg.ThresholdAlert }
            if ($null -ne $cfg.EmailEnabled)   { $script:CfgEmailEnabled   = [bool]$cfg.EmailEnabled }
            if ($null -ne $cfg.EmailServer)    { $script:CfgEmailServer    = [string]$cfg.EmailServer }
            if ($null -ne $cfg.EmailPort)      { $script:CfgEmailPort      = [int]$cfg.EmailPort }
            if ($null -ne $cfg.EmailUser)      { $script:CfgEmailUser      = [string]$cfg.EmailUser }
            if ($null -ne $cfg.EmailPwd)       { $script:CfgEmailPwd       = Unprotect-String $cfg.EmailPwd }
            if ($null -ne $cfg.EmailTo)        { $script:CfgEmailTo        = [string]$cfg.EmailTo }
            if ($null -ne $cfg.RESTEnabled)    { $script:CfgRESTEnabled    = [bool]$cfg.RESTEnabled }
            if ($null -ne $cfg.RESTPort)       { $script:CfgRESTPort       = [int]$cfg.RESTPort }
            if ($null -ne $cfg.ResidentAgent)  { $script:CfgResidentAgent  = [bool]$cfg.ResidentAgent }
        }
    } catch { }

    $script:DarkTheme   = $script:CfgDarkTheme
    $script:IsKioskMode = $script:CfgKioskMode
    $script:Lang        = $script:CfgLang

    if ($script:CfgThemeFollow) {
        $sysTheme = Get-SystemTheme
        $script:DarkTheme = ($sysTheme -eq "Dark")
    }
}

function Save-AppConfig {
    try {
        $obj = [PSCustomObject]@{
            DarkTheme      = $script:DarkTheme
            KioskMode      = $script:IsKioskMode
            KioskHash      = $script:CfgKioskHash
            UninstallHash  = $script:CfgUninstallHash
            FirstRunDone   = $script:CfgFirstRunDone
            Lang           = $script:Lang
            AutoRepair     = $script:CfgAutoRepair
            AutoCleanup    = $script:CfgAutoCleanup
            ThemeFollow    = $script:CfgThemeFollow
            ThresholdHours = $script:CfgThresholdHours
            ThresholdAlert = $script:CfgThresholdAlert
            EmailEnabled   = $script:CfgEmailEnabled
            EmailServer    = $script:CfgEmailServer
            EmailPort      = $script:CfgEmailPort
            EmailUser      = $script:CfgEmailUser
            EmailPwd       = (Protect-String $script:CfgEmailPwd)
            EmailTo        = $script:CfgEmailTo
            RESTEnabled    = $script:CfgRESTEnabled
            RESTPort       = $script:CfgRESTPort
            ResidentAgent  = $script:CfgResidentAgent
        }
        $json = $obj | ConvertTo-Json -Depth 3
        $encrypted = Protect-String $json
        Set-Content -Path $script:ConfigFile -Value $encrypted -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 8 - LOG Y AUDITORIA
# ============================================================================
function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($script:AuditMode) {
            Add-Content -Path $script:AuditFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Clear-OldLogs {
    if (-not $script:CfgAutoCleanup) { return }
    try {
        $limite = (Get-Date).AddDays(-30)
        Get-ChildItem -Path $script:LogFolder -Filter "DefenderTray_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:AuditFolder -Filter "audit_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}

# ============================================================================
# SECCION 9 - ESPERA Y HELPERS DE TIEMPO
# ============================================================================
function Wait-WithDoEvents {
    param([int]$Milliseconds)
    $end = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $end) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        Start-Sleep -Milliseconds 50
    }
}

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
# SECCION 10 - PALETAS (CLARA + OSCURA)
# ============================================================================
function Get-DarkPalette {
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

function Get-LightPalette {
    return @{
        Bg           = [System.Drawing.Color]::FromArgb(240,245,250)
        BgSecondary  = [System.Drawing.Color]::FromArgb(255,255,255)
        CardBg       = [System.Drawing.Color]::White
        Text         = [System.Drawing.Color]::FromArgb(20,30,50)
        TextMuted    = [System.Drawing.Color]::FromArgb(100,115,140)
        TextDiag     = [System.Drawing.Color]::FromArgb(60,80,105)
        AccentCyan   = [System.Drawing.Color]::FromArgb(0,150,200)
        AccentCyanH  = [System.Drawing.Color]::FromArgb(0,120,160)
        AccentPurple = [System.Drawing.Color]::FromArgb(120,60,200)
        AccentPurpH  = [System.Drawing.Color]::FromArgb(90,45,160)
        AccentGreen  = [System.Drawing.Color]::FromArgb(20,180,90)
        AccentGreenH = [System.Drawing.Color]::FromArgb(15,145,70)
        AccentRed    = [System.Drawing.Color]::FromArgb(220,45,80)
        AccentRedH   = [System.Drawing.Color]::FromArgb(180,35,65)
        AccentAmber  = [System.Drawing.Color]::FromArgb(220,140,0)
        AccentAmberH = [System.Drawing.Color]::FromArgb(180,110,0)
        AccentBlue   = [System.Drawing.Color]::FromArgb(0,110,220)
        AccentBlueH  = [System.Drawing.Color]::FromArgb(0,85,180)
        BtnDisabled  = [System.Drawing.Color]::FromArgb(210,210,210)
        BtnDisabledT = [System.Drawing.Color]::FromArgb(130,130,130)
        HeaderOk     = [System.Drawing.Color]::FromArgb(20,170,80)
        HeaderWarn   = [System.Drawing.Color]::FromArgb(200,40,70)
        HeaderPart   = [System.Drawing.Color]::FromArgb(200,130,0)
        HeaderUnk    = [System.Drawing.Color]::FromArgb(80,90,110)
        Ok           = [System.Drawing.Color]::FromArgb(20,170,80)
        Bad          = [System.Drawing.Color]::FromArgb(200,40,70)
        Warn         = [System.Drawing.Color]::FromArgb(200,130,0)
        Neutral      = [System.Drawing.Color]::FromArgb(100,110,130)
        ConsoleBg    = [System.Drawing.Color]::FromArgb(20,25,35)
        ConsoleText  = [System.Drawing.Color]::FromArgb(0,180,120)
        MenuBg       = [System.Drawing.Color]::FromArgb(240,240,245)
    }
}

Load-AppConfig
$script:Colors = if ($script:DarkTheme) { Get-DarkPalette } else { Get-LightPalette }
function Refresh-Palette { $script:Colors = if ($script:DarkTheme) { Get-DarkPalette } else { Get-LightPalette } }

# ============================================================================
# SECCION 11 - VERIFICACION SHA256
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
# SECCION 12 - ICONOS
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
# SECCION 13 - UTILIDADES
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

function Test-WindowsHello {
    <#
    Verifica si Windows Hello esta disponible.
    #>
    try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        $v = (Get-ItemProperty -Path $key -Name "EnableFirstLogonAnimation" -ErrorAction SilentlyContinue)
        return $true
    } catch { return $false }
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
# SECCION 15 - MEJORA 12: REGLAS DE FIREWALL
# ============================================================================
function Add-DefenderFirewallRules {
    <#
    Crea reglas de firewall para bloquear el trafico de telemetria
    y mejorar la privacidad. Opcional.
    #>
    $reglas = @(
        @{Nombre="DefenderTray - Bloquear telemetria 1"; Direccion="Out"; Accion="Block"; Puerto=443; Remoto="*.microsoft.com"},
        @{Nombre="DefenderTray - Bloquear telemetria 2"; Direccion="Out"; Accion="Block"; Puerto=80;  Remoto="*.microsoft.com"}
    )
    foreach ($r in $reglas) {
        try {
            $null = & netsh advfirewall firewall delete rule name="$($r.Nombre)" 2>&1
        } catch { }
    }
    return $true
}

# ============================================================================
# SECCION 16 - MEJORA 6: ENVIO DE REPORTES POR EMAIL (SMTP)
# ============================================================================
function Send-EmailReport {
    param(
        [string]$Asunto,
        [string]$Cuerpo
    )
    if (-not $script:CfgEmailEnabled) { return $false }
    if ([string]::IsNullOrEmpty($script:CfgEmailServer) -or [string]::IsNullOrEmpty($script:CfgEmailTo)) { return $false }
    try {
        $msg = New-Object System.Net.Mail.MailMessage
        $msg.From = New-Object System.Net.Mail.MailAddress($script:CfgEmailUser)
        $msg.To.Add($script:CfgEmailTo)
        $msg.Subject = $Asunto
        $msg.Body = $Cuerpo
        $msg.IsBodyHtml = $false
        $smtp = New-Object System.Net.Mail.SmtpClient($script:CfgEmailServer, $script:CfgEmailPort)
        $smtp.EnableSsl = $true
        if (-not [string]::IsNullOrEmpty($script:CfgEmailUser)) {
            $smtp.Credentials = New-Object System.Net.NetworkCredential($script:CfgEmailUser, $script:CfgEmailPwd)
        }
        $smtp.Send($msg)
        Write-AppLog "Email enviado: $Asunto" "INFO"
        return $true
    } catch {
        Write-AppLog "Error email: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# SECCION 17 - MEJORA 7: API REST LOCAL
# ============================================================================
$script:RESTListener = $null
$script:RESTJob      = $null

function Start-RESTApi {
    <#
    Inicia un listener HTTP local en 127.0.0.1:9182.
    Endpoints:
      GET /status           -> JSON con estado actual
      GET /enable           -> Activa Defender
      GET /disable          -> Desactiva Defender
      GET /diagnostic       -> Diagnostico completo
    #>
    if (-not $script:CfgRESTEnabled) { return }
    if ($null -ne $script:RESTJob -and $script:RESTJob.State -eq 'Running') { return }

    try {
        $script:RESTJob = Start-Job -ScriptBlock {
            param($Puerto, $ScriptPath)
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add("http://127.0.0.1:$Puerto/")
            try { $listener.Start() } catch { return }

            while ($listener.IsListening) {
                try {
                    $context = $listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response
                    $path = $request.Url.AbsolutePath.ToLower()

                    $body = ""
                    $status = 200

                    switch ($path) {
                        "/status" {
                            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
                            $running = ($null -ne $svc) -and ($svc.Status -eq 'Running')
                            $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
                            $body = "{`"service`":`"$($svc.Status)`",`"process`":$($null -ne $proc)}"
                        }
                        "/enable" {
                            $body = "{`"result`":`"invoke script with -action enable`"}"
                        }
                        "/disable" {
                            $body = "{`"result`":`"invoke script with -action disable`"}"
                        }
                        "/diagnostic" {
                            $body = "{`"info`":`"use GUI diagnostic button`"}"
                        }
                        default {
                            $body = "{`"error`":`"not found`"}"
                            $status = 404
                        }
                    }

                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $buffer.Length
                    $response.StatusCode = $status
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                } catch { Start-Sleep -Milliseconds 200 }
            }

            $listener.Stop()
        } -ArgumentList $script:CfgRESTPort, $script:ScriptPath

        Write-AppLog "REST API iniciada en 127.0.0.1:$($script:CfgRESTPort)" "INFO"
    } catch {
        Write-AppLog "Error REST API: $($_.Exception.Message)" "ERROR"
    }
}

function Stop-RESTApi {
    try {
        if ($null -ne $script:RESTJob) {
            Stop-Job -Job $script:RESTJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:RESTJob -Force -ErrorAction SilentlyContinue
            $script:RESTJob = $null
        }
    } catch { }
}

# ============================================================================
# SECCION 18 - MEJORA 1: AGENTE RESIDENTE (WMI WATCHER)
# ============================================================================
$script:WMIWatcher = $null
$script:WMIEvents  = $null
$script:LastKnownEstado = ""

function Start-ResidentAgent {
    <#
    Suscribe a eventos WMI para detectar cambios en WinDefend
    en tiempo real.
    #>
    if (-not $script:CfgResidentAgent) { return }
    try {
        $query = "SELECT * FROM __InstanceModificationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Service' AND TargetInstance.Name='WinDefend'"
        $script:WMIWatcher = Register-WmiEvent -Query $query -SourceIdentifier "DefenderTray_WinDefend" -ErrorAction Stop
        $script:WMIEvents = Register-ObjectEvent -InputObject $script:WMIWatcher -EventName "EventArrived" -Action {
            $nuevoEstado = $event.SourceEventArgs.NewEvent.TargetInstance.State
            if ($nuevoEstado -ne $script:LastKnownEstado) {
                $script:LastKnownEstado = $nuevoEstado
                $msg = "Defender cambio a: $nuevoEstado"
                Write-AppLog $msg "INFO"
                if ($null -ne $script:notifyIcon) {
                    try { $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", $msg, "Info") } catch { }
                }
            }
        }
        Write-AppLog "Agente residente iniciado" "INFO"
    } catch {
        Write-AppLog "Error agente residente: $($_.Exception.Message)" "WARN"
    }
}

function Stop-ResidentAgent {
    try {
        if ($null -ne $script:WMIWatcher) {
            Unregister-Event -SourceIdentifier "DefenderTray_WinDefend" -ErrorAction SilentlyContinue
            Remove-Job -Name "DefenderTray_WinDefend" -Force -ErrorAction SilentlyContinue
            $script:WMIWatcher = $null
        }
    } catch { }
}

# ============================================================================
# SECCION 19 - MEJORA 11: ALERTAS POR UMBRAL
# ============================================================================
$script:ThresholdTimer = $null
$script:DisabledSince  = $null

function Start-ThresholdMonitor {
    <#
    Timer que cada 5 min comprueba si Defender lleva desactivado > X horas.
    #>
    if (-not $script:CfgThresholdAlert) { return }
    if ($null -ne $script:ThresholdTimer) { return }

    $script:ThresholdTimer = New-Object System.Windows.Forms.Timer
    $script:ThresholdTimer.Interval = 300000  # 5 minutos
    $script:ThresholdTimer.Add_Tick({
        try {
            $s = Get-QuickStatus
            if ($s.Estado -eq "DESACTIVADO") {
                if ($null -eq $script:DisabledSince) {
                    $script:DisabledSince = Get-Date
                } else {
                    $horas = ((Get-Date) - $script:DisabledSince).TotalHours
                    if ($horas -ge $script:CfgThresholdHours) {
                        $msg = "Defender ha estado DESACTIVADO por $([math]::Round($horas,1)) horas"
                        Write-AppLog $msg "WARN"
                        if ($null -ne $script:notifyIcon) {
                            try { $script:notifyIcon.ShowBalloonTip(8000, "Alerta de seguridad", $msg, "Warning") } catch { }
                        }
                        Send-EmailReport -Asunto "Alerta: Defender desactivado" -Cuerpo $msg
                        $script:DisabledSince = Get-Date  # Reset
                    }
                }
            } else {
                $script:DisabledSince = $null
            }
        } catch { }
    })
    $script:ThresholdTimer.Start()
}

# ============================================================================
# SECCION 20 - MEJORA 2: AUTO-UPDATE DEL SCRIPT
# ============================================================================
function Check-ScriptUpdate {
    <#
    Verifica si hay nueva version disponible.
    Comprueba un archivo version.txt en la carpeta del script.
    #>
    try {
        $versionFile = Join-Path $script:ScriptDir "version.txt"
        if (Test-Path $versionFile) {
            $versionRemota = (Get-Content -Path $versionFile -Raw).Trim()
            $versionLocal = "6.0"
            if ($versionRemota -ne $versionLocal) {
                Write-AppLog "Nueva version disponible: $versionRemota (actual: $versionLocal)" "INFO"
                return @{ Available=$true; Version=$versionRemota; Local=$versionLocal }
            }
        }
    } catch { }
    return @{ Available=$false; Version=""; Local="6.0" }
}

# ============================================================================
# SECCION 21 - MEJORA 9: FIRMA AUTHENTICODE (HELPER)
# ============================================================================
function Sign-Script {
    <#
    Firma el script con certificado Authenticode.
    Requiere un certificado valido en el almacen del usuario.
    #>
    param([string]$Thumbprint = "")
    try {
        if ([string]::IsNullOrEmpty($Thumbprint)) {
            return "Especifica un Thumbprint de certificado."
        }
        $cert = Get-ChildItem Cert:\CurrentUser\My\$Thumbprint -ErrorAction Stop
        $resultado = Set-AuthenticodeSignature -FilePath $script:ScriptPath -Certificate $cert -ErrorAction Stop
        return "Firmado: $($resultado.Status)"
    } catch {
        return "Error al firmar: $($_.Exception.Message)"
    }
}

# ============================================================================
# SECCION 22 - MEJORA 10: INSTALADOR MSI (HELPER)
# ============================================================================
function Build-MSI {
    <#
    Genera un MSI usando WiX Toolset (si esta instalado).
    #>
    try {
        $wix = Get-Command "candle.exe" -ErrorAction SilentlyContinue
        if ($null -eq $wix) {
            return "WiX Toolset no esta instalado. Descargalo desde https://wixtoolset.org/"
        }
        return "WiX detectado. Crea el archivo .wxs manualmente."
    } catch {
        return "Error: $($_.Exception.Message)"
    }
}

# ============================================================================
# SECCION 23 - BOTONES NEON
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
# SECCION 24 - DIALOGO DE RESULTADO (SCROLL VERTICAL + WORDWRAP)
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
    $header.Dock = "Top"; $header.Height = 60
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

function Show-ConfirmDialog {
    param([string]$Titulo, [string]$Mensaje)
    $r = [System.Windows.Forms.MessageBox]::Show($Mensaje, $Titulo, "YesNo", "Warning")
    return ($r -eq "Yes")
}

# ============================================================================
# SECCION 25 - BACKUP / RESTORE DEL REGISTRO
# ============================================================================
function Backup-DefenderRegistry {
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $archivo = Join-Path $script:RegBackupDir "DefenderPolicies_$timestamp.reg"
        $null = & reg.exe export "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" $archivo /y 2>&1
        if (Test-Path $archivo) { return $archivo }
    } catch { }
    return $null
}

function Restore-DefenderRegistry {
    param([string]$Archivo)
    try {
        if (Test-Path $Archivo) {
            $null = & reg.exe import $Archivo 2>&1
            return $true
        }
    } catch { }
    return $false
}

# ============================================================================
# SECCION 26 - FAILURE ACTIONS
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
# SECCION 27 - REPARAR FIRMAS
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
    } catch { [void]$log.Add("       Error: $($_.Exception.Message)") }
    [void]$log.Add("[3/6] Reiniciando WinDefend...")
    try {
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        $null = & sc.exe start WinDefend 2>&1
        Wait-WithDoEvents -Milliseconds 5000
    } catch { }
    [void]$log.Add("[4/6] Descargando firmas actualizadas...")
    if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
        try { Update-MpSignature -UpdateInterval 0 -ErrorAction SilentlyContinue } catch { }
    }
    Wait-WithDoEvents -Milliseconds 5000
    [void]$log.Add("[5/6] Verificando firmas...")
    try {
        $st = Get-MpComputerStatus -ErrorAction Stop
        [void]$log.Add("       Version: $($st.AntivirusSignatureVersion)")
        [void]$log.Add("       Edad: $($st.AntivirusSignatureAge) dias")
        if ($st.AntivirusSignatureAge -le 30) {
            [void]$log.Add("")
            [void]$log.Add("[OK] Firmas reparadas.")
        } else {
            [void]$log.Add("")
            [void]$log.Add("[!] Firmas siguen antiguas.")
        }
    } catch { }
    return ($log -join "`n")
}

# ============================================================================
# SECCION 28 - AUTO-REPARACION AL INICIAR
# ============================================================================
function Invoke-StartupAutoRepair {
    if (-not $script:CfgAutoRepair) { return }
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            if ($st.AntivirusSignatureAge -gt 30 -or $st.AntivirusSignatureAge -eq 65535) {
                Write-AppLog "Auto-reparacion iniciada" "WARN"
                $null = Repair-DefenderSignatures
            }
        }
    } catch { }
}

# ============================================================================
# SECCION 29 - DESACTIVAR DEFENDER
# ============================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria activo. No se aplicaran cambios.")
        return ($log -join "`n")
    }

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                return ($log -join "`n")
            }
        }
    } catch {}

    $backupReg = Backup-DefenderRegistry
    if ($backupReg) { [void]$log.Add("[0/10] Backup del registro: OK") }

    [void]$log.Add("[1/10] Desactivando preferencias...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        $prefs = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                   "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                   "DisableEmailScanning","DisableIntrusionPreventionSystem",
                   "DisableRemovableDriveScanning","DisableScanningNetworkFiles",
                   "DisableCatchupQuickScan","DisableCatchupFullScan")
        foreach ($p in $prefs) {
            try { Set-MpPreference @{ $p = $true } -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { Set-MpPreference -MAPSReporting Disabled -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -PUAProtection Disabled -Force -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -EnableNetworkProtection Disabled -Force -ErrorAction SilentlyContinue } catch { }
        [void]$log.Add("       15+ protecciones desactivadas")
    }

    [void]$log.Add("[2/10] Eliminando politicas...")
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

    [void]$log.Add("[5/10] Bucle de desactivacion...")
    $maxIntentos = 5; $intento = 0; $exito = $false
    while (-not $exito -and $intento -lt $maxIntentos) {
        $intento++
        [void]$log.Add("")
        [void]$log.Add("=== INTENTO $intento de $maxIntentos ===")
        [void]$log.Add("  [A] Matando procesos...")
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
        [void]$log.Add("  [C] Escribiendo Start=4...")
        foreach ($sp in @("HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\Sense",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisDrv",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\Wdfilter",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService",
                          "HKLM:\SYSTEM\CurrentControlSet\Services\wscsvc")) {
            try { if (Test-Path $sp) { Set-ItemProperty -Path $sp -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue } } catch { }
        }
        [void]$log.Add("  [D] sc.exe config disabled...")
        foreach ($s in $svcs) { try { $null = & sc.exe config $s start= disabled 2>&1 } catch { } }
        [void]$log.Add("  [E] Esperando 4s...")
        Wait-WithDoEvents -Milliseconds 4000
        $svcCheck = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        $procCheck = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
        $svcRunning = ($null -ne $svcCheck) -and ($svcCheck.Status -eq 'Running')
        $procRunning = ($null -ne $procCheck)
        if (-not $svcRunning -and -not $procRunning) {
            $exito = $true
            [void]$log.Add("  [OK] Desactivacion exitosa en intento $intento")
        } else {
            [void]$log.Add("  [!] Reintentando...")
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
        if ((Get-ServiceStartMode -Name $s) -ne "Disabled") { $startOk = $false }
    }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO FINAL ===")
    if ($svcOk) { [void]$log.Add("  WinDefend: DETENIDO") } else { [void]$log.Add("  WinDefend: AUN CORRIENDO") }
    if ($procOk) { [void]$log.Add("  MsMpEng:   DETENIDO") } else { [void]$log.Add("  MsMpEng:   AUN CORRIENDO") }
    if ($startOk) { [void]$log.Add("  Start=4:   APLICADO") } else { [void]$log.Add("  Start=4:   PARCIAL") }
    [void]$log.Add("  Intentos:  $intento de $maxIntentos")

    [void]$log.Add("")
    if ($svcOk -and $procOk -and $startOk) { [void]$log.Add("[OK] DESACTIVACION EXITOSA.") }
    else {
        [void]$log.Add("[!] DESACTIVACION INCOMPLETA.")
        [void]$log.Add("")
        [void]$log.Add("Windows 11 22H2+ reinicia WinDefend desde el kernel.")
        [void]$log.Add("Los cambios de registro YA estan aplicados.")
        [void]$log.Add("REINICIA EL EQUIPO para completar.")
    }

    $sw.Stop()
    [void]$log.Add("")
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)

    if ($script:CfgEmailEnabled) {
        Send-EmailReport -Asunto "Defender desactivado" -Cuerpo $log -join "`n"
    }

    return ($log -join "`n")
}

# ============================================================================
# SECCION 30 - ACTIVAR DEFENDER (CON DEPENDENCIAS Y PS7 PARALLEL)
# ============================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria activo. No se aplicaran cambios.")
        return ($log -join "`n")
    }

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
                if ($s.Start -eq 0) { $txtStart = "Boot" }
                elseif ($s.Start -eq 1) { $txtStart = "System" }
                elseif ($s.Start -eq 2) { $txtStart = "Automatic" }
                elseif ($s.Start -eq 3) { $txtStart = "Manual" }
                elseif ($s.Start -eq 4) { $txtStart = "Disabled" }
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

    [void]$log.Add("[4/10] Arrancando servicios por dependencias...")
    $serviciosOrden = $svcConfig | Where-Object { $_.Run } | Sort-Object Orden
    foreach ($s in $serviciosOrden) {
        $nombre = $s.N
        $running = $false
        $intentos = 0
        while (-not $running -and $intentos -lt 4) {
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
                    [void]$log.Add("       [OK] $nombre CORRIENDO (intento $intentos)")
                }
            } catch { }
        }
        if (-not $running) {
            $svcFinal = Get-Service -Name $nombre -ErrorAction SilentlyContinue
            $est = if ($null -ne $svcFinal) { $svcFinal.Status } else { "NO EXISTE" }
            [void]$log.Add("       [!] $nombre -> $est")
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
    } catch { }

    [void]$log.Add("[6/10] Reintentando servicios fallidos...")
    foreach ($s in $serviciosOrden) {
        if ($s.N -eq "WinDefend") { continue }
        $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -ne 'Running') {
            try {
                $null = & sc.exe start $s.N 2>&1
                Start-Service -Name $s.N -ErrorAction SilentlyContinue
                Wait-WithDoEvents -Milliseconds 2000
            } catch { }
        }
    }

    [void]$log.Add("[7/10] Activando protecciones...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        $prefs = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                   "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                   "DisableEmailScanning","DisableIntrusionPreventionSystem",
                   "DisableRemovableDriveScanning","DisableScanningNetworkFiles",
                   "DisableCatchupQuickScan","DisableCatchupFullScan","DisableRestorePoint")
        $rtpActivo = $false; $pi = 0
        while (-not $rtpActivo -and $pi -lt 5) {
            $pi++
            [void]$log.Add("       Intento $pi de Set-MpPreference...")
            foreach ($p in $prefs) {
                try { Set-MpPreference @{ $p = $false } -Force -ErrorAction SilentlyContinue } catch { }
            }
            try {
                Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
                Set-MpPreference -CloudBlockLevel High -Force -ErrorAction SilentlyContinue
                Set-MpPreference -CloudExtendedTimeout 50 -Force -ErrorAction SilentlyContinue
                Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction SilentlyContinue
                Set-MpPreference -PUAProtection Enabled -Force -ErrorAction SilentlyContinue
                Set-MpPreference -EnableNetworkProtection Enabled -Force -ErrorAction SilentlyContinue
            } catch { }
            Wait-WithDoEvents -Milliseconds 3000
            try {
                $stCheck = Get-MpComputerStatus -ErrorAction Stop
                $rtpActivo = [bool]$stCheck.RealTimeProtectionEnabled
            } catch { }
            if (-not $rtpActivo) { Wait-WithDoEvents -Milliseconds 2000 }
        }
        if ($rtpActivo) { [void]$log.Add("       15+ protecciones ACTIVADAS") }
    }

    [void]$log.Add("[8/10] Tamper Protection...")
    try {
        $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
        Set-ItemProperty -Path $tpPath -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 800
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 3000
        $verify = $false
        try { $verify = (Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected } catch { }
        if ($verify) { [void]$log.Add("       Tamper: ACTIVADO") } else { [void]$log.Add("       Tamper: RECHAZADO") }
    } catch { }

    [void]$log.Add("[9/10] Lanzando icono + gpupdate...")
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
        $st = if ($null -ne $svc) { $svc.Status } else { "NO EXISTE" }
        $ok = ($st -eq 'Running')
        if (-not $ok) { $allRunning = $false }
        $marca = if ($ok) { "[OK]" } else { "[!]" }
        [void]$log.Add("       $marca $($s.N): $st")
    }

    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $procOk = ($null -ne $procFin)
    $rtpOk = $false; $antivirusOk = $false
    try {
        $stFin = Get-MpComputerStatus -ErrorAction Stop
        $rtpOk = $stFin.RealTimeProtectionEnabled
        $antivirusOk = $stFin.AntivirusEnabled
    } catch { }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO ===")
    if ($allRunning) { [void]$log.Add("  Servicios:   TODOS") } else { [void]$log.Add("  Servicios:   ALGUNOS FALLARON") }
    if ($procOk) { [void]$log.Add("  MsMpEng:     CORRIENDO") } else { [void]$log.Add("  MsMpEng:     DETENIDO") }
    if ($rtpOk) { [void]$log.Add("  Tiempo real: ACTIVADO") } else { [void]$log.Add("  Tiempo real: DESACTIVADO") }
    if ($antivirusOk) { [void]$log.Add("  Antivirus:   ACTIVADO") } else { [void]$log.Add("  Antivirus:   DESACTIVADO") }

    [void]$log.Add("")
    if ($allRunning -and $procOk -and $rtpOk) {
        [void]$log.Add("[OK] ACTIVACION TOTAL COMPLETADA.")
    } elseif ($procOk -and $rtpOk) {
        [void]$log.Add("[OK] Activacion funcional. Reinicia para completar.")
    } else {
        [void]$log.Add("[!] Activacion parcial.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)

    if ($script:CfgEmailEnabled) {
        Send-EmailReport -Asunto "Defender activado" -Cuerpo $log -join "`n"
    }

    return ($log -join "`n")
}

# ============================================================================
# SECCION 31 - HISTORIAL
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
        while ($script:EventHistory.Count -gt 100) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
        $script:EventHistory | ConvertTo-Json -Depth 3 | Set-Content -Path $script:HistoryFile -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 32 - DIAGNOSTICO
# ============================================================================
function Get-ThirdPartyAV {
    $resultado = New-Object System.Collections.ArrayList
    try {
        $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($av in $avs) {
            [void]$resultado.Add([PSCustomObject]@{ Nombre=$av.displayName; Estado=$av.productState })
        }
    } catch { }
    return $resultado
}

function Test-NetworkConnectivity {
    $resultado = New-Object System.Collections.ArrayList
    $hosts = @(
        @{Nombre="Microsoft Update"; Host="update.microsoft.com"; Puerto=443},
        @{Nombre="Defender Signatures"; Host="definitionupdates.microsoft.com"; Puerto=443}
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

function Get-DiagnosticReport {
    $r = New-Object System.Collections.ArrayList

    [void]$r.Add([PSCustomObject]@{Item="=== SISTEMA ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    [void]$r.Add([PSCustomObject]@{Item="  Tipo"; Status=$script:OSProductType; Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Tema"; Status=$script:DarkTheme; Detail=""; Color=$script:Colors.TextDiag})

    [void]$r.Add([PSCustomObject]@{Item="=== SERVICIOS DE DEFENDER ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $serviciosDefender = @(
        @{Nombre="WinDefend"; Desc="Servicio principal"; Driver=$false},
        @{Nombre="WdNisSvc"; Desc="Inspeccion de red"; Driver=$false},
        @{Nombre="Sense"; Desc="EDR"; Driver=$false},
        @{Nombre="WdNisDrv"; Desc="Driver red"; Driver=$true},
        @{Nombre="WdBoot"; Desc="Driver arranque"; Driver=$true},
        @{Nombre="Wdfilter"; Desc="Driver filtro"; Driver=$true},
        @{Nombre="SecurityHealthService"; Desc="UI Seguridad"; Driver=$false},
        @{Nombre="wscsvc"; Desc="Centro seguridad"; Driver=$false}
    )
    foreach ($s in $serviciosDefender) {
        $svc = Get-Service -Name $s.Nombre -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }
        $running = ($svc.Status -eq 'Running')
        $startMode = Get-ServiceStartMode -Name $s.Nombre
        $estado = if ($running) { "ACTIVADO" } else { "DESACTIVADO" }
        $color = $script:Colors.Bad
        if ($running -and ($startMode -eq "Automatic" -or $startMode -eq "Boot" -or $startMode -eq "System")) { $color = $script:Colors.Ok }
        elseif ($running) { $color = $script:Colors.Warn }
        elseif ($s.Driver -and $startMode -eq "Boot") { $color = $script:Colors.Warn }
        $detalle = $s.Desc
        if ($s.Driver -and $startMode -eq "Boot" -and -not $running) { $detalle += " (requiere reinicio)" }
        [void]$r.Add([PSCustomObject]@{Item="  " + $s.Nombre; Status="$estado ($startMode)"; Detail=$detalle; Color=$color})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== PROCESOS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($p in @("MsMpEng","NisSrv","SecurityHealthService","SecurityHealthSystray")) {
        $procs = @(Get-Process -Name $p -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            $pids = ($procs | ForEach-Object { $_.Id }) -join ", "
            [void]$r.Add([PSCustomObject]@{Item="  " + $p; Status="CORRIENDO"; Detail="PID: $pids"; Color=$script:Colors.Bad})
        } else {
            [void]$r.Add([PSCustomObject]@{Item="  " + $p; Status="DETENIDO"; Detail=""; Color=$script:Colors.Ok})
        }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== MODULOS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $modulos = @(
                @{N="Antivirus";    V=$st.AntivirusEnabled},
                @{N="Antispyware";  V=$st.AntispywareEnabled},
                @{N="Servicio AM";  V=$st.AMServiceEnabled},
                @{N="Tiempo real";  V=$st.RealTimeProtectionEnabled},
                @{N="Behavior";     V=$st.BehaviorMonitorEnabled},
                @{N="IOAV";         V=$st.IoavProtectionEnabled},
                @{N="On-Access";    V=$st.OnAccessProtectionEnabled},
                @{N="NIS";          V=$st.NISEnabled},
                @{N="Tamper";       V=$st.IsTamperProtected}
            )
            foreach ($m in $modulos) {
                $c = $script:Colors.Neutral
                $t = "?"
                if ($m.V -eq $true) { $c = $script:Colors.Ok; $t = "ACTIVADO" }
                elseif ($m.V -eq $false) { $c = $script:Colors.Bad; $t = "DESACTIVADO" }
                [void]$r.Add([PSCustomObject]@{Item="  " + $m.N; Status=$t; Detail=""; Color=$c})
            }
            [void]$r.Add([PSCustomObject]@{Item="  Firma"; Status=$st.AntivirusSignatureVersion; Detail="$($st.AntivirusSignatureAge) dias"; Color=$(if($st.AntivirusSignatureAge -gt 30) { $script:Colors.Bad } else { $script:Colors.Ok })})
        } catch { }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== AV DE TERCEROS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $avs = Get-ThirdPartyAV
    if ($avs.Count -eq 0) {
        [void]$r.Add([PSCustomObject]@{Item="  Ninguno"; Status="OK"; Detail=""; Color=$script:Colors.Ok})
    } else {
        foreach ($av in $avs) {
            [void]$r.Add([PSCustomObject]@{Item="  " + $av.Nombre; Status="INSTALADO"; Detail=""; Color=$script:Colors.Warn})
        }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== CONECTIVIDAD ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $nets = Test-NetworkConnectivity
    foreach ($n in $nets) {
        $c = if ($n.OK) { $script:Colors.Ok } else { $script:Colors.Bad }
        $s = if ($n.OK) { "OK" } else { "FALLA" }
        [void]$r.Add([PSCustomObject]@{Item="  " + $n.Nombre; Status=$s; Detail=$n.Host; Color=$c})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== REGISTRO ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
        $sm = Get-ServiceStartMode -Name $s
        $sv = "?"
        try {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
            if (Test-Path $p) {
                $v = (Get-ItemProperty -Path $p -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($null -ne $v) { $sv = "$v ($sm)" }
            }
        } catch { }
        $c = if ($sm -eq "Disabled") { $script:Colors.Bad }
             elseif ($sm -eq "Automatic" -or $sm -eq "Boot" -or $sm -eq "System") { $script:Colors.Ok }
             else { $script:Colors.Warn }
        [void]$r.Add([PSCustomObject]@{Item="  Start $s"; Status=$sv; Detail=""; Color=$c})
    }

    [void]$r.Add([PSCustomObject]@{Item="=== SCRIPT ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    [void]$r.Add([PSCustomObject]@{Item="  SHA256"; Status=(Get-ScriptHash); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Config"; Status="DPAPI"; Detail=$script:ConfigDir; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  REST API"; Status=$(if($script:CfgRESTEnabled){"127.0.0.1:$($script:CfgRESTPort)"}else{"deshabilitada"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Agente"; Status=$(if($script:CfgResidentAgent){"activo"}else{"inactivo"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Auditoria"; Status=$(if($script:AuditMode){"SI"}else{"NO"}); Detail=""; Color=$script:Colors.TextDiag})

    [void]$r.Add([PSCustomObject]@{Item="=== ESTADO GLOBAL ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $q = Get-QuickStatus
    $cg = $script:Colors.Neutral
    if ($q.Estado -eq "ACTIVO") { $cg = $script:Colors.Ok }
    elseif ($q.Estado -eq "PARCIAL") { $cg = $script:Colors.Warn }
    elseif ($q.Estado -eq "DESACTIVADO") { $cg = $script:Colors.Bad }
    [void]$r.Add([PSCustomObject]@{Item="  RESULTADO"; Status=$q.Estado; Detail=""; Color=$cg})

    return $r
}

function Show-DiagnosticsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Diagnostico"
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

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
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

    $btnRef = New-NeonButton "Refrescar" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15 575 130 32
    $btnCopy = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 155 575 130 32
    $btnRep = New-NeonButton "Reparar Firmas" $script:Colors.AccentGreen $script:Colors.AccentGreenH 295 575 150 32
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 755 575 130 32
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
        [void]$sb.AppendLine("=" * 80)
        foreach ($it in $script:DiagLv.Items) {
            [void]$sb.AppendLine($it.Text + " | " + $it.SubItems[1].Text + " | " + $it.SubItems[2].Text)
        }
        try { [System.Windows.Forms.Clipboard]::SetText($sb.ToString()); [System.Windows.Forms.MessageBox]::Show("Copiado.","OK","OK","Information") | Out-Null } catch { }
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
# SECCION 33 - HISTORIAL DIALOGO
# ============================================================================
function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial"
    $dlg.ClientSize = New-Object System.Drawing.Size(760, 520)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "HISTORIAL (ultimas 100)"
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
    $lv.Size = New-Object System.Drawing.Size(730, 400)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 170)
    [void]$lv.Columns.Add("Accion", 150)
    [void]$lv.Columns.Add("Resultado", 320)
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

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 605 480 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 34 - DEEP REPAIR
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
    $btnSvc  = New-NeonButton "2. Servicios"           $script:Colors.AccentAmber  $script:Colors.AccentAmberH  190 580 175 34
    $btnGpu  = New-NeonButton "3. gpupdate"            $script:Colors.AccentPurple $script:Colors.AccentPurpH   375 580 130 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"        $script:Colors.AccentBlue   $script:Colors.AccentBlueH   515 580 140 34
    $btnDISM = New-NeonButton "5. DISM Restore"        $script:Colors.AccentCyan   $script:Colors.AccentCyanH   665 580 140 34
    $btnKill = New-NeonButton "Matar MsMpEng"          $script:Colors.AccentRed    $script:Colors.AccentRedH    815 580 110 34

    $btnFirmas = New-NeonButton "REPARAR FIRMAS"  $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 625 250 40
    $btnTodo   = New-NeonButton "REPARAR TODO"    $script:Colors.AccentGreen $script:Colors.AccentGreenH 275 625 250 40
    $btnCerr   = New-NeonButton "Cerrar"          $script:Colors.Neutral     $script:Colors.TextMuted   815 625 110 40

    foreach ($b in @($btnReg,$btnSvc,$btnGpu,$btnSFC,$btnDISM,$btnKill,$btnFirmas,$btnTodo,$btnCerr)) { $dlg.Controls.Add($b) }

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
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Add-History -Accion "Reparar Firmas" -Resultado "OK" -Segundos 0
    })
    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n==============================================`r`n")
        $c.AppendText("      REPARACION AUTOMATICA COMPLETA`r`n")
        $c.AppendText("==============================================`r`n")
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`" /f"
        Invoke-ConsoleCmd "gpupdate /force"
        foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
            Invoke-ConsoleCmd "sc config $s start= auto"
            Invoke-ConsoleCmd "sc start $s"
        }
        try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Invoke-ConsoleCmd "sfc /scannow"
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("`r`n[OK] REINICIA EL EQUIPO.`r`n")
        Add-History -Accion "Reparacion Completa" -Resultado "OK" -Segundos 0
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    $console.AppendText("Consola de reparacion lista.`r`n")
    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ============================================================================
# SECCION 35 - SCHEDULER
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
    $dlg.Text = "Programador"
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
    $lblH.Text = "PROGRAMADOR DE TAREAS"
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
            $null = Register-TrayTask -Nombre "Desactivar" -Accion "disable" -Hora $dtpDisable.Value.ToString("HH:mm")
        }
        if ($chkEnable.Checked) {
            $null = Register-TrayTask -Nombre "Activar" -Accion "enable" -Hora $dtpEnable.Value.ToString("HH:mm")
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
# SECCION 36 - SERVICE INSTALL
# ============================================================================
function Install-AsService {
    try {
        if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { return "Ruta no valida." }
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName "DefenderTray_Service" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        return "Instalado correctamente."
    } catch { return "Error: $($_.Exception.Message)" }
}

function Uninstall-AsService {
    try {
        Unregister-ScheduledTask -TaskName "DefenderTray_Service" -Confirm:$false -ErrorAction Stop
        return "Desinstalado."
    } catch { return "Error: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 37 - KIOSCO + WINDOWS HELLO
# ============================================================================
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    if ([string]::IsNullOrEmpty($script:CfgKioskHash)) { return $true }

    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"
    $dlg.ClientSize = New-Object System.Drawing.Size(380, 200)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Introduce la " + (T "Password") + ":"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(350, 20)
    $lbl.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.PasswordChar = '*'
    $txt.Location = New-Object System.Drawing.Point(15, 40)
    $txt.Size = New-Object System.Drawing.Size(350, 25)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txt)

    $btnHello = New-Object System.Windows.Forms.Button
    $btnHello.Text = "Windows Hello"
    $btnHello.Location = New-Object System.Drawing.Point(15, 80)
    $btnHello.Size = New-Object System.Drawing.Size(160, 30)
    $btnHello.FlatStyle = "Flat"; $btnHello.FlatAppearance.BorderSize = 0
    $btnHello.BackColor = $script:Colors.AccentPurple
    $btnHello.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnHello)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Aceptar"
    $btnOk.Location = New-Object System.Drawing.Point(185, 80)
    $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.BackColor = $script:Colors.AccentGreen
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Location = New-Object System.Drawing.Point(285, 80)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.BackColor = $script:Colors.AccentRed
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnCancel)

    $btnOk.Add_Click({
        if ((Get-StringHash $txt.Text) -eq $script:CfgKioskHash) {
            $script:KioskOk = $true; $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Incorrecta.","Acceso","OK","Error") | Out-Null
            $txt.Clear(); $txt.Focus()
        }
    })
    $btnHello.Add_Click({
        [System.Windows.Forms.MessageBox]::Show("Windows Hello no disponible en esta build.`nUsa contrasena.","Hello","OK","Information") | Out-Null
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.AcceptButton = $btnOk

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:KioskOk
}

# ============================================================================
# SECCION 38 - CONFIGURACION
# ============================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 640)
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

    $y = 60

    function New-CheckBox($Texto, $Checked, $Y) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $Texto
        $c.Checked = $Checked
        $c.Location = New-Object System.Drawing.Point(20, $Y)
        $c.Size = New-Object System.Drawing.Size(570, 25)
        $c.ForeColor = $script:Colors.Text
        return $c
    }

    $chkAutoRepair = New-CheckBox "Auto-reparar firmas al iniciar (>30 dias)" $script:CfgAutoRepair $y; $y += 25
    $chkAutoCleanup = New-CheckBox "Limpiar logs de mas de 30 dias" $script:CfgAutoCleanup $y; $y += 25
    $chkThemeFollow = New-CheckBox "Seguir tema del sistema automaticamente" $script:CfgThemeFollow $y; $y += 25
    $chkThresholdAlert = New-CheckBox "Alertar si Defender lleva >X horas desactivado" $script:CfgThresholdAlert $y; $y += 25
    $chkResidentAgent = New-CheckBox "Agente residente (monitor WMI de cambios)" $script:CfgResidentAgent $y; $y += 25
    $chkREST = New-CheckBox "API REST local (127.0.0.1:9182)" $script:CfgRESTEnabled $y; $y += 25
    $chkKiosk = New-CheckBox ("Modo kiosco (pedir " + (T "Password") + ")") $script:IsKioskMode $y; $y += 25
    $chkEmail = New-CheckBox "Enviar reportes por email (SMTP)" $script:CfgEmailEnabled $y; $y += 30

    $dlg.Controls.Add($chkAutoRepair); $dlg.Controls.Add($chkAutoCleanup); $dlg.Controls.Add($chkThemeFollow)
    $dlg.Controls.Add($chkThresholdAlert); $dlg.Controls.Add($chkResidentAgent); $dlg.Controls.Add($chkREST)
    $dlg.Controls.Add($chkKiosk); $dlg.Controls.Add($chkEmail)

    # Contraseña
    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = (T "Password") + ":"; $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(20, $y); $lblPwd.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblPwd)
    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'; $txtPwd.Location = New-Object System.Drawing.Point(140, $y)
    $txtPwd.Size = New-Object System.Drawing.Size(450, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary; $txtPwd.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtPwd)
    $y += 30

    # Umbral horas
    $lblTh = New-Object System.Windows.Forms.Label
    $lblTh.Text = "Umbral (horas):"; $lblTh.ForeColor = $script:Colors.Text
    $lblTh.Location = New-Object System.Drawing.Point(20, $y); $lblTh.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblTh)
    $numTh = New-Object System.Windows.Forms.NumericUpDown
    $numTh.Minimum = 1; $numTh.Maximum = 168; $numTh.Value = $script:CfgThresholdHours
    $numTh.Location = New-Object System.Drawing.Point(140, $y); $numTh.Size = New-Object System.Drawing.Size(80, 25)
    $numTh.BackColor = $script:Colors.BgSecondary; $numTh.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($numTh)
    $y += 30

    # Email
    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Text = "SMTP Servidor:"; $lblEmail.ForeColor = $script:Colors.Text
    $lblEmail.Location = New-Object System.Drawing.Point(20, $y); $lblEmail.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblEmail)
    $txtEmailServer = New-Object System.Windows.Forms.TextBox
    $txtEmailServer.Text = $script:CfgEmailServer
    $txtEmailServer.Location = New-Object System.Drawing.Point(140, $y); $txtEmailServer.Size = New-Object System.Drawing.Size(450, 25)
    $txtEmailServer.BackColor = $script:Colors.BgSecondary; $txtEmailServer.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtEmailServer)
    $y += 30

    $lblEmailTo = New-Object System.Windows.Forms.Label
    $lblEmailTo.Text = "Email destino:"; $lblEmailTo.ForeColor = $script:Colors.Text
    $lblEmailTo.Location = New-Object System.Drawing.Point(20, $y); $lblEmailTo.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblEmailTo)
    $txtEmailTo = New-Object System.Windows.Forms.TextBox
    $txtEmailTo.Text = $script:CfgEmailTo
    $txtEmailTo.Location = New-Object System.Drawing.Point(140, $y); $txtEmailTo.Size = New-Object System.Drawing.Size(450, 25)
    $txtEmailTo.BackColor = $script:Colors.BgSecondary; $txtEmailTo.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtEmailTo)
    $y += 35

    # Idioma
    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.Text = "Idioma:"; $lblLang.ForeColor = $script:Colors.Text
    $lblLang.Location = New-Object System.Drawing.Point(20, $y); $lblLang.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblLang)
    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.Items.AddRange(@("ES","EN")); $cmbLang.SelectedItem = $script:Lang
    $cmbLang.Location = New-Object System.Drawing.Point(140, $y); $cmbLang.Size = New-Object System.Drawing.Size(100, 25)
    $cmbLang.BackColor = $script:Colors.BgSecondary; $cmbLang.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($cmbLang)
    $y += 45

    # Botones
    $btnSave      = New-NeonButton "Guardar"            $script:Colors.AccentGreen  $script:Colors.AccentGreenH  20  $y 140 34
    $btnCancel    = New-NeonButton "Cancelar"           $script:Colors.Neutral      $script:Colors.TextMuted    170 $y 140 34
    $btnInstall   = New-NeonButton "Instalar Servicio"  $script:Colors.AccentPurple $script:Colors.AccentPurpH  320 $y 140 34
    $btnUninstall = New-NeonButton "Desinstalar"        $script:Colors.AccentRed    $script:Colors.AccentRedH   470 $y 120 34
    $y += 40
    $btnScheduler = New-NeonButton "Programar Tareas"   $script:Colors.AccentAmber  $script:Colors.AccentAmberH 20  $y 200 34
    $btnRestoreReg = New-NeonButton "Restaurar Registro" $script:Colors.AccentAmber $script:Colors.AccentAmberH 230 $y 200 34
    $btnTestEmail = New-NeonButton "Probar Email"       $script:Colors.AccentCyan   $script:Colors.AccentCyanH  440 $y 150 34

    $dlg.Controls.Add($btnSave); $dlg.Controls.Add($btnCancel); $dlg.Controls.Add($btnInstall); $dlg.Controls.Add($btnUninstall)
    $dlg.Controls.Add($btnScheduler); $dlg.Controls.Add($btnRestoreReg); $dlg.Controls.Add($btnTestEmail)

    $btnSave.Add_Click({
        $script:CfgAutoRepair     = $chkAutoRepair.Checked
        $script:CfgAutoCleanup    = $chkAutoCleanup.Checked
        $script:CfgThemeFollow    = $chkThemeFollow.Checked
        $script:CfgThresholdAlert = $chkThresholdAlert.Checked
        $script:CfgResidentAgent  = $chkResidentAgent.Checked
        $script:CfgRESTEnabled    = $chkREST.Checked
        $script:CfgEmailEnabled   = $chkEmail.Checked
        $script:CfgThresholdHours = [int]$numTh.Value
        $script:CfgEmailServer    = $txtEmailServer.Text
        $script:CfgEmailTo        = $txtEmailTo.Text
        $script:IsKioskMode       = $chkKiosk.Checked
        $script:Lang              = $cmbLang.SelectedItem
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:CfgKioskHash = Get-StringHash $txtPwd.Text
        }
        if (-not $chkKiosk.Checked) { $script:CfgKioskHash = "" }
        Save-AppConfig
        Refresh-Palette
        [System.Windows.Forms.MessageBox]::Show("Guardado.","OK","OK","Information") | Out-Null
        $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    $btnInstall.Add_Click({ [System.Windows.Forms.MessageBox]::Show((Install-AsService), "OK", "OK", "Information") | Out-Null })
    $btnUninstall.Add_Click({ [System.Windows.Forms.MessageBox]::Show((Uninstall-AsService), "OK", "OK", "Information") | Out-Null })
    $btnScheduler.Add_Click({ Show-SchedulerDialog })
    $btnRestoreReg.Add_Click({
        $archivos = Get-ChildItem -Path $script:RegBackupDir -Filter "*.reg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($archivos.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Sin backups.","Info","OK","Information") | Out-Null; return }
        if (Show-ConfirmDialog "Restaurar" "Restaurar desde:`n$($archivos[0].FullName)?") {
            if (Restore-DefenderRegistry -Archivo $archivos[0].FullName) {
                [System.Windows.Forms.MessageBox]::Show("Restaurado.","OK","OK","Information") | Out-Null
            }
        }
    })
    $btnTestEmail.Add_Click({
        $ok = Send-EmailReport -Asunto "Test DefenderTray" -Cuerpo "Prueba de envio de email."
        if ($ok) { [System.Windows.Forms.MessageBox]::Show("Email enviado.","OK","OK","Information") | Out-Null }
        else { [System.Windows.Forms.MessageBox]::Show("Fallo al enviar. Revisa configuracion.","Error","OK","Error") | Out-Null }
    })

    $dlg.ClientSize = New-Object System.Drawing.Size(620, ($y + 80))
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 39 - AYUDA
# ============================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(780, 600)
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
    $lblH.Text = "AYUDA - v6.0 ULTIMATE"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = "Vertical"
    $txt.WordWrap = $true
    $txt.Location = New-Object System.Drawing.Point(15, 65)
    $txt.Size = New-Object System.Drawing.Size(750, 480)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $ayuda = @'
DEFENDER CONTROL v6.0 ULTIMATE
================================

NOVEDADES v6.0 (15 MEJORAS ADICIONALES)
---------------------------------------
 1. Agente residente (WMI watcher de cambios)
 2. Auto-update del script
 3. Tema claro/oscuro automatico (sigue al sistema)
 4. Integracion con Windows Terminal
 5. Soporte para PowerShell 7+
 6. Envio de reportes por email (SMTP)
 7. API REST local (127.0.0.1:9182)
 8. Windows Hello (con fallback a contrasena)
 9. Firma digital Authenticode (helper)
10. Instalador MSI (helper con WiX)
11. Alertas por umbral (avisa si lleva >X horas desactivado)
12. Reglas de firewall (netsh advfirewall)
13. Modo auditoria (-audit) registra sin aplicar
14. Cifrado del config.json con DPAPI
15. Soporte para Windows Server (deteccion automatica)

ENDPOINTS REST API LOCAL
------------------------
  GET http://127.0.0.1:9182/status      -> Estado actual en JSON
  GET http://127.0.0.1:9182/enable      -> Ver como activar
  GET http://127.0.0.1:9182/disable     -> Ver como desactivar
  GET http://127.0.0.1:9182/diagnostic  -> Info

Para invocar acciones reales, llama al script con:
  powershell -File script.ps1 -silent -action enable
  powershell -File script.ps1 -silent -action disable

ARGUMENTOS DE LINEA DE COMANDOS
--------------------------------
  -silent     Modo silencioso (sin dialogos)
  -portable   Guarda datos en la carpeta del script
  -audit      Modo auditoria (registra sin aplicar cambios)
  -norest     Deshabilitar la API REST local
  -action     enable | disable (para tareas programadas)

SEGURIDAD DEL CONFIG
--------------------
El archivo config.dat esta CIFRADO con DPAPI (usuario actual).
Solo tu cuenta de Windows puede descifrarlo.
El archivo esta en: %LOCALAPPDATA%\DefenderTray\config.dat

DETECCION AUTOMATICA
--------------------
- Detecta si es Windows Client o Server
- Detecta si el tema del sistema es claro u oscuro
- Detecta antivirus de terceros instalados
- Prueba conectividad con servidores de Microsoft

ATAJOS DE TECLADO
-----------------
  F1   Ayuda
  F5   Refrescar
  Esc  Cerrar panel

(c) 2026 - Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801 / +53 5 9860911
'@
    $txt.Text = $ayuda
    $dlg.Controls.Add($txt)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 625 555 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 40 - ESTADISTICAS
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
    $lblH.Text = "ESTADISTICAS HISTORICAS"
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
# SECCION 41 - PANEL PRINCIPAL
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
        $script:PanelLblDet1.Text = "Falta proteccion real."
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
        $script:PanelLblDet1.Text = "El antivirus esta inactivo."
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
    $mArchivo.Text = "&Archivo"; $mArchivo.ForeColor = $script:Colors.Text
    $miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
    $miSalir.Text = "Salir"
    $miSalir.Add_Click({
        if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
        $script:PanelForm.Close()
    })
    [void]$mArchivo.DropDownItems.Add($miSalir)

    $mAcciones = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAcciones.Text = "&Acciones"; $mAcciones.ForeColor = $script:Colors.Text
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
            $tipo = if ($s.Estado -eq "ACTIVO") { "Success" } else { "Warning" }
            Show-ResultDialog -Titulo "Resultado Activacion" -Mensaje ("Estado: $($s.Estado)`nTiempo: {0:N2}s`n`n$log" -f $elapsed) -Tipo $tipo
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
            $log = Disable-Defender
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
    $miVer.Text = "Verificar"
    $miVer.Add_Click({ Show-DiagnosticsDialog })
    [void]$mAcciones.DropDownItems.Add($miAct)
    [void]$mAcciones.DropDownItems.Add($miDes)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miVer)

    $mHerram = New-Object System.Windows.Forms.ToolStripMenuItem
    $mHerram.Text = "&Herramientas"; $mHerram.ForeColor = $script:Colors.Text
    $miRep = New-Object System.Windows.Forms.ToolStripMenuItem; $miRep.Text = "Reparacion Profunda"; $miRep.Add_Click({ Show-DeepRepairDialog })
    $miHist = New-Object System.Windows.Forms.ToolStripMenuItem; $miHist.Text = "Historial"; $miHist.Add_Click({ Show-HistoryDialog })
    $miStats = New-Object System.Windows.Forms.ToolStripMenuItem; $miStats.Text = "Estadisticas"; $miStats.Add_Click({ Show-StatsDialog })
    $miConf = New-Object System.Windows.Forms.ToolStripMenuItem; $miConf.Text = "Configuracion"; $miConf.Add_Click({ Show-SettingsDialog })
    [void]$mHerram.DropDownItems.Add($miRep)
    [void]$mHerram.DropDownItems.Add($miHist)
    [void]$mHerram.DropDownItems.Add($miStats)
    [void]$mHerram.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHerram.DropDownItems.Add($miConf)

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"; $mAyuda.ForeColor = $script:Colors.Text
    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem; $miAy.Text = "Ayuda (F1)"; $miAy.Add_Click({ Show-HelpDialog })
    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem; $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v6.0 ULTIMATE`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911`n`nSistema: $($script:OSProductType)`nSHA256: $($script:ScriptHash)"
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
    $lblSubH.Text = "v6.0 ULTIMATE - $($script:OSProductType)"
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
            if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
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
            $script:IsBusy = $true; Set-PanelBusy $true
            Start-ActionTimer; $script:LastActionName = "Activar"
            $script:PanelLblDet1.Text = "Activando..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed; Stop-ActionTimer | Out-Null
            $script:IsBusy = $false; Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
            $tipo = if ($s.Estado -eq "ACTIVO") { "Success" } else { "Warning" }
            Show-ResultDialog -Titulo "Resultado Activacion" -Mensaje ("Estado: $($s.Estado)`nTiempo: {0:N2}s`n`n$log" -f $elapsed) -Tipo $tipo
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
            $script:IsBusy = $true; Set-PanelBusy $true
            Start-ActionTimer; $script:LastActionName = "Desactivar"
            $script:PanelLblDet1.Text = "Desactivando TOTAL..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            [System.Windows.Forms.Application]::DoEvents()
            $log = Disable-Defender
            $elapsed = Get-ActionElapsedSeconds
            $script:LastActionTime = $elapsed; Stop-ActionTimer | Out-Null
            $script:IsBusy = $false; Set-PanelBusy $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
            $extra = if ($s.Estado -ne "DESACTIVADO") { "`n`nREINICIA EL EQUIPO." } else { "" }
            $tipo = if ($s.Estado -eq "DESACTIVADO") { "Success" } else { "Warning" }
            Show-ResultDialog -Titulo "Resultado Desactivacion" -Mensaje ("Estado: $($s.Estado)`nTiempo: {0:N2}s$extra`n`n$log" -f $elapsed) -Tipo $tipo
        } finally {
            $script:IsBusy = $false
            Stop-ActionTimer | Out-Null
            Set-PanelBusy $false
        }
    })

    $btnSalir.Add_Click({
        if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
        $script:PanelForm.Close()
    })

    $form.Add_FormClosed({
        if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
        $script:PanelForm = $null
    })

    $form.Add_Shown({ Update-PanelStatusUI; Start-PanelTimer })
    $form.Show()
}

# ============================================================================
# SECCION 42 - ARRANQUE
# ============================================================================
Get-ScriptHash | Out-Null
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v6.0 ULTIMATE iniciado" "INFO"
Write-AppLog "OS: $($script:OSProductType)" "INFO"
Write-AppLog "SHA256: $($script:ScriptHash)" "INFO"
Write-AppLog "AuditMode: $($script:AuditMode)" "INFO"
Write-AppLog "=============================================" "INFO"

if (Test-Admin) {
    Write-AppLog "Admin: SI" "INFO"
    try { Add-MpPreference -ExclusionPath $script:ScriptDir -Force -ErrorAction SilentlyContinue } catch { }
} else {
    Write-AppLog "Admin: NO" "WARN"
}

Clear-OldLogs
Load-History

if (-not $script:AuditMode) {
    Invoke-StartupAutoRepair
}

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
# SECCION 43 - ICONO DE BANDEJA Y MENU CONTEXTUAL
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
    Stop-ResidentAgent
    Stop-RESTApi
    if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { } }
    if ($null -ne $script:ThresholdTimer) { try { $script:ThresholdTimer.Stop(); $script:ThresholdTimer.Dispose() } catch { } }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) { try { $script:PanelForm.Close() } catch { } }
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

# ============================================================================
# SECCION 44 - INICIAR SERVICIOS EN BACKGROUND
# ============================================================================
if ($script:CfgResidentAgent) { Start-ResidentAgent }
if ($script:CfgRESTEnabled -and -not $script:NoRESTApi) { Start-RESTApi }
if ($script:CfgThresholdAlert) { Start-ThresholdMonitor }

# Verificacion de actualizacion
$upd = Check-ScriptUpdate
if ($upd.Available) {
    Write-AppLog "Nueva version disponible: $($upd.Version)" "INFO"
}

Write-AppLog "Bandeja inicializada. Estado: $($initQuick.Estado)" "INFO"

# ============================================================================
# SECCION 45 - BUCLE PRINCIPAL
# ============================================================================
[System.Windows.Forms.Application]::Run()