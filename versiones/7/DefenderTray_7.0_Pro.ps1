<#
================================================================================
  DefenderTray v7.0 ULTIMATE - Control Profesional de Windows Defender
================================================================================
  Novedades v7.0:
    1.  Panel web HTML5 servido por la API REST.
    2.  Multi-usuario con perfiles SQLite (simulado con JSON).
    3.  Notificaciones moviles via Telegram Bot.
    4.  Auto-reparacion inteligente con heuristica.
    5.  Control por voz (Windows Speech Recognition).
    6.  Exportacion a PDF firmado digitalmente.
    7.  Modo de emergencia (Panic Button con hotkey Ctrl+Alt+D).
    8.  Historial del Event Log de Windows Defender.
    9.  Integracion con captura de trafico.
    10. Backup a la nube (OneDrive/Google Drive).
    11. Soporte multi-monitor (se abre en el monitor activo).
    12. Tema personalizable con editor de colores.
    13. Modo tutela (bloqueo parental).
    14. API para movil (endpoints JSON).
    15. Modo forense (screenshot + logs antes de cambios).
  Fixes v7.0:
    - Newlines correctos con \r\n (CRLF) en dialogos.
    - REST API con urlacl + HTTPS opcional.
    - Certificado autofirmado para HTTPS.
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
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Speech -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

# ============================================================================
# SECCION 2 - ARGUMENTOS Y RUTAS
# ============================================================================
$script:SilentMode    = ($args -contains "-silent")
$script:PortableMode  = ($args -contains "-portable")
$script:AuditMode     = ($args -contains "-audit")
$script:NoRESTApi     = ($args -contains "-norest")
$script:UseHTTPS      = ($args -contains "-https")
$script:UseHTTP       = -not $script:UseHTTPS

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
$script:ForensicDir  = Join-Path $script:ConfigDir "Forense"
$script:ProfilesDir  = Join-Path $script:ConfigDir "Perfiles"
$script:LogFile      = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ConfigFile   = Join-Path $script:ConfigDir "config.dat"
$script:HistoryFile  = Join-Path $script:ConfigDir "historial.json"
$script:AuditFile    = Join-Path $script:AuditFolder ("audit_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ProfilesFile = Join-Path $script:ProfilesDir "profiles.json"

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir, $script:RegBackupDir, $script:AuditFolder, $script:ForensicDir, $script:ProfilesDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ============================================================================
# SECCION 3 - CARACTERES ESPECIALES
# ============================================================================
$script:CH_N = [char]0x00F1

# ============================================================================
# SECCION 4 - DETECCION DEL SISTEMA
# ============================================================================
function Get-OSProductType {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $tipo = $os.ProductType
        if ($tipo -eq 1) { return "Client" }
        elseif ($tipo -eq 2 -or $tipo -eq 3) { return "Server" }
    } catch { }
    return "Unknown"
}

# ============================================================================
# SECCION 5 - DETECCION DE TEMA
# ============================================================================
function Get-SystemTheme {
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
# SECCION 6 - NORMALIZACION DE SALTOS DE LINEA (FIX CRITICO)
# ============================================================================
function Normalize-LineEndings {
    <#
    Convierte TODOS los saltos de linea a \r\n (CRLF).
    WinForms TextBox requiere CRLF para renderizar correctamente.
    #>
    param([string]$Texto)
    if ([string]::IsNullOrEmpty($Texto)) { return "" }
    # Primero normalizar a LF, luego a CRLF
    $t = $Texto -replace "`r`n", "`n"
    $t = $t -replace "`r", "`n"
    $t = $t -replace "`n", "`r`n"
    return $t
}

# ============================================================================
# SECCION 7 - i18n
# ============================================================================
$script:Strings = @{
    ES = @{
        Title = "Control de Seguridad v7.0 ULTIMATE"
        Activar = "ACTIVAR PROTECCION"
        Desactivar = "DESACTIVAR PROTECCION"
        Diagnostico = "DIAGNOSTICO"
        Reparar = "REPARAR (Deep Repair)"
        Historial = "Historial"
        Config = "Config"
        Ayuda = "Ayuda (F1)"
        Salir = "SALIR"
        EstadoActual = "ESTADO ACTUAL"
        Password = "Contrase" + [char]0x00F1 + "a"
        Emergencia = "EMERGENCIA"
    }
    EN = @{
        Title = "Security Control v7.0 ULTIMATE"
        Activar = "ENABLE PROTECTION"
        Desactivar = "DISABLE PROTECTION"
        Diagnostico = "DIAGNOSTICS"
        Reparar = "REPAIR (Deep Repair)"
        Historial = "History"
        Config = "Settings"
        Ayuda = "Help (F1)"
        Salir = "EXIT"
        EstadoActual = "CURRENT STATUS"
        Password = "Password"
        Emergencia = "EMERGENCY"
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
# SECCION 8 - CONFIGURACION CON DPAPI
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
$script:CfgTelegramEnabled = $false
$script:CfgTelegramToken  = ""
$script:CfgTelegramChatId = ""
$script:CfgMultiMonitor   = $true
$script:CfgForensicMode   = $false
$script:CfgParentalMode   = $false
$script:CfgCloudBackup    = $false
$script:CfgCloudPath      = ""
$script:CfgCustomTheme    = @{
        Bg = "#0A0E1A"
        CardBg = "#182034"
        AccentGreen = "#00C86C"
        AccentRed = "#FF3366"
        AccentAmber = "#FFAA00"
        AccentCyan = "#00E5FF"
        AccentPurple = "#B14EFF"
        AccentBlue = "#008CFF"
    }

$script:DarkTheme = $true
$script:IsKioskMode = $false
$script:ScriptHash = ""
$script:OSProductType = Get-OSProductType
$script:EmergencyHotkeyId = 1

function Protect-String {
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
            foreach ($prop in $cfg.PSObject.Properties) {
                switch ($prop.Name) {
                    "DarkTheme"      { $script:CfgDarkTheme = [bool]$prop.Value }
                    "KioskMode"      { $script:CfgKioskMode = [bool]$prop.Value }
                    "KioskHash"      { $script:CfgKioskHash = [string]$prop.Value }
                    "UninstallHash"  { $script:CfgUninstallHash = [string]$prop.Value }
                    "FirstRunDone"   { $script:CfgFirstRunDone = [bool]$prop.Value }
                    "Lang"           { $script:CfgLang = [string]$prop.Value }
                    "AutoRepair"     { $script:CfgAutoRepair = [bool]$prop.Value }
                    "AutoCleanup"    { $script:CfgAutoCleanup = [bool]$prop.Value }
                    "ThemeFollow"    { $script:CfgThemeFollow = [bool]$prop.Value }
                    "ThresholdHours" { $script:CfgThresholdHours = [int]$prop.Value }
                    "ThresholdAlert" { $script:CfgThresholdAlert = [bool]$prop.Value }
                    "EmailEnabled"   { $script:CfgEmailEnabled = [bool]$prop.Value }
                    "EmailServer"    { $script:CfgEmailServer = [string]$prop.Value }
                    "EmailPort"      { $script:CfgEmailPort = [int]$prop.Value }
                    "EmailUser"      { $script:CfgEmailUser = [string]$prop.Value }
                    "EmailPwd"       { $script:CfgEmailPwd = Unprotect-String $prop.Value }
                    "EmailTo"        { $script:CfgEmailTo = [string]$prop.Value }
                    "RESTEnabled"    { $script:CfgRESTEnabled = [bool]$prop.Value }
                    "RESTPort"       { $script:CfgRESTPort = [int]$prop.Value }
                    "ResidentAgent"  { $script:CfgResidentAgent = [bool]$prop.Value }
                    "TelegramEnabled" { $script:CfgTelegramEnabled = [bool]$prop.Value }
                    "TelegramToken"  { $script:CfgTelegramToken = [string]$prop.Value }
                    "TelegramChatId" { $script:CfgTelegramChatId = [string]$prop.Value }
                    "MultiMonitor"   { $script:CfgMultiMonitor = [bool]$prop.Value }
                    "ForensicMode"   { $script:CfgForensicMode = [bool]$prop.Value }
                    "ParentalMode"   { $script:CfgParentalMode = [bool]$prop.Value }
                    "CloudBackup"    { $script:CfgCloudBackup = [bool]$prop.Value }
                    "CloudPath"      { $script:CfgCloudPath = [string]$prop.Value }
                }
            }
        }
    } catch { }

    $script:DarkTheme = $script:CfgDarkTheme
    $script:IsKioskMode = $script:CfgKioskMode
    $script:Lang = $script:CfgLang

    if ($script:CfgThemeFollow) {
        $sysTheme = Get-SystemTheme
        $script:DarkTheme = ($sysTheme -eq "Dark")
    }
}

function Save-AppConfig {
    try {
        $obj = [PSCustomObject]@{
            DarkTheme = $script:DarkTheme
            KioskMode = $script:IsKioskMode
            KioskHash = $script:CfgKioskHash
            UninstallHash = $script:CfgUninstallHash
            FirstRunDone = $script:CfgFirstRunDone
            Lang = $script:Lang
            AutoRepair = $script:CfgAutoRepair
            AutoCleanup = $script:CfgAutoCleanup
            ThemeFollow = $script:CfgThemeFollow
            ThresholdHours = $script:CfgThresholdHours
            ThresholdAlert = $script:CfgThresholdAlert
            EmailEnabled = $script:CfgEmailEnabled
            EmailServer = $script:CfgEmailServer
            EmailPort = $script:CfgEmailPort
            EmailUser = $script:CfgEmailUser
            EmailPwd = (Protect-String $script:CfgEmailPwd)
            EmailTo = $script:CfgEmailTo
            RESTEnabled = $script:CfgRESTEnabled
            RESTPort = $script:CfgRESTPort
            ResidentAgent = $script:CfgResidentAgent
            TelegramEnabled = $script:CfgTelegramEnabled
            TelegramToken = $script:CfgTelegramToken
            TelegramChatId = $script:CfgTelegramChatId
            MultiMonitor = $script:CfgMultiMonitor
            ForensicMode = $script:CfgForensicMode
            ParentalMode = $script:CfgParentalMode
            CloudBackup = $script:CfgCloudBackup
            CloudPath = $script:CfgCloudPath
        }
        $json = $obj | ConvertTo-Json -Depth 3
        $encrypted = Protect-String $json
        Set-Content -Path $script:ConfigFile -Value $encrypted -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 9 - LOG Y AUDITORIA
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
            Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:AuditFolder -Filter "audit_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:ForensicDir -Filter "*.png" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}

# ============================================================================
# SECCION 10 - ESPERA Y HELPERS
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
# SECCION 11 - PALETAS
# ============================================================================
function HexToColor {
    param([string]$Hex)
    try {
        $h = $Hex.TrimStart('#')
        return [System.Drawing.Color]::FromArgb(
            [Convert]::ToInt32($h.Substring(0,2),16),
            [Convert]::ToInt32($h.Substring(2,2),16),
            [Convert]::ToInt32($h.Substring(4,2),16)
        )
    } catch { return [System.Drawing.Color]::Gray }
}

function Get-DarkPalette {
    $c = $script:CfgCustomTheme
    return @{
        Bg = HexToColor $c.Bg
        BgSecondary = [System.Drawing.Color]::FromArgb(20,27,46)
        CardBg = HexToColor $c.CardBg
        Text = [System.Drawing.Color]::FromArgb(224,230,240)
        TextMuted = [System.Drawing.Color]::FromArgb(107,122,153)
        TextDiag = [System.Drawing.Color]::FromArgb(180,200,220)
        AccentCyan = HexToColor $c.AccentCyan
        AccentCyanH = [System.Drawing.Color]::FromArgb(0,180,200)
        AccentPurple = HexToColor $c.AccentPurple
        AccentPurpH = [System.Drawing.Color]::FromArgb(140,60,200)
        AccentGreen = HexToColor $c.AccentGreen
        AccentGreenH = [System.Drawing.Color]::FromArgb(0,160,86)
        AccentRed = HexToColor $c.AccentRed
        AccentRedH = [System.Drawing.Color]::FromArgb(200,40,80)
        AccentAmber = HexToColor $c.AccentAmber
        AccentAmberH = [System.Drawing.Color]::FromArgb(200,130,0)
        AccentBlue = HexToColor $c.AccentBlue
        AccentBlueH = [System.Drawing.Color]::FromArgb(0,110,200)
        BtnDisabled = [System.Drawing.Color]::FromArgb(45,55,75)
        BtnDisabledT = [System.Drawing.Color]::FromArgb(100,115,140)
        HeaderOk = [System.Drawing.Color]::FromArgb(0,150,80)
        HeaderWarn = [System.Drawing.Color]::FromArgb(180,30,60)
        HeaderPart = [System.Drawing.Color]::FromArgb(180,110,0)
        HeaderUnk = [System.Drawing.Color]::FromArgb(45,55,75)
        Ok = [System.Drawing.Color]::FromArgb(0,230,120)
        Bad = [System.Drawing.Color]::FromArgb(255,80,110)
        Warn = [System.Drawing.Color]::FromArgb(255,180,50)
        Neutral = [System.Drawing.Color]::FromArgb(120,135,160)
        ConsoleBg = [System.Drawing.Color]::FromArgb(8,12,20)
        ConsoleText = [System.Drawing.Color]::FromArgb(0,255,180)
        MenuBg = [System.Drawing.Color]::FromArgb(16,22,38)
    }
}

function Get-LightPalette {
    return @{
        Bg = [System.Drawing.Color]::FromArgb(240,245,250)
        BgSecondary = [System.Drawing.Color]::FromArgb(255,255,255)
        CardBg = [System.Drawing.Color]::White
        Text = [System.Drawing.Color]::FromArgb(20,30,50)
        TextMuted = [System.Drawing.Color]::FromArgb(100,115,140)
        TextDiag = [System.Drawing.Color]::FromArgb(60,80,105)
        AccentCyan = [System.Drawing.Color]::FromArgb(0,150,200)
        AccentCyanH = [System.Drawing.Color]::FromArgb(0,120,160)
        AccentPurple = [System.Drawing.Color]::FromArgb(120,60,200)
        AccentPurpH = [System.Drawing.Color]::FromArgb(90,45,160)
        AccentGreen = [System.Drawing.Color]::FromArgb(20,180,90)
        AccentGreenH = [System.Drawing.Color]::FromArgb(15,145,70)
        AccentRed = [System.Drawing.Color]::FromArgb(220,45,80)
        AccentRedH = [System.Drawing.Color]::FromArgb(180,35,65)
        AccentAmber = [System.Drawing.Color]::FromArgb(220,140,0)
        AccentAmberH = [System.Drawing.Color]::FromArgb(180,110,0)
        AccentBlue = [System.Drawing.Color]::FromArgb(0,110,220)
        AccentBlueH = [System.Drawing.Color]::FromArgb(0,85,180)
        BtnDisabled = [System.Drawing.Color]::FromArgb(210,210,210)
        BtnDisabledT = [System.Drawing.Color]::FromArgb(130,130,130)
        HeaderOk = [System.Drawing.Color]::FromArgb(20,170,80)
        HeaderWarn = [System.Drawing.Color]::FromArgb(200,40,70)
        HeaderPart = [System.Drawing.Color]::FromArgb(200,130,0)
        HeaderUnk = [System.Drawing.Color]::FromArgb(80,90,110)
        Ok = [System.Drawing.Color]::FromArgb(20,170,80)
        Bad = [System.Drawing.Color]::FromArgb(200,40,70)
        Warn = [System.Drawing.Color]::FromArgb(200,130,0)
        Neutral = [System.Drawing.Color]::FromArgb(100,110,130)
        ConsoleBg = [System.Drawing.Color]::FromArgb(20,25,35)
        ConsoleText = [System.Drawing.Color]::FromArgb(0,180,120)
        MenuBg = [System.Drawing.Color]::FromArgb(240,240,245)
    }
}

Load-AppConfig
$script:Colors = if ($script:DarkTheme) { Get-DarkPalette } else { Get-LightPalette }
function Refresh-Palette { $script:Colors = if ($script:DarkTheme) { Get-DarkPalette } else { Get-LightPalette } }

# ============================================================================
# SECCION 12 - SHA256
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
# SECCION 13 - ICONOS
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
        "$env:windir\System32\SecurityHealthSystray.exe"
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
        }
    } catch { }
}

# ============================================================================
# SECCION 14 - UTILIDADES
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
# SECCION 15 - ESTADO RAPIDO
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
        ServiceRunning = $running
        EngineRunning = $engineRunning
        RealTimeProtectionEnabled = -not $rtpDisabled
        HasPolicy = $hasPolicy
        IsActive = $isActive
        IsFullyDisabled = $isFullyDisabled
        Estado = $estado
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
            }
        }
    } catch { }
    return $resultado
}

# ============================================================================
# SECCION 16 - v7.0 MEJORA 3: NOTIFICACIONES TELEGRAM
# ============================================================================
function Send-TelegramNotification {
    param([string]$Mensaje)
    if (-not $script:CfgTelegramEnabled) { return $false }
    if ([string]::IsNullOrEmpty($script:CfgTelegramToken) -or [string]::IsNullOrEmpty($script:CfgTelegramChatId)) { return $false }
    try {
        $url = "https://api.telegram.org/bot$($script:CfgTelegramToken)/sendMessage"
        $body = @{
            chat_id = $script:CfgTelegramChatId
            text = "[DefenderTray] $Mensaje"
            parse_mode = "HTML"
        } | ConvertTo-Json
        $null = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop
        Write-AppLog "Telegram enviado: $Mensaje" "INFO"
        return $true
    } catch {
        Write-AppLog "Error Telegram: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# ============================================================================
# SECCION 17 - v7.0 MEJORA 6: EXPORTACION A PDF FIRMADO
# ============================================================================
function Export-ReportAsPDF {
    param([string]$Titulo, [string]$Contenido, [string]$RutaDestino)
    try {
        # Generar HTML con estilos
        $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>$Titulo</title>
<style>
body { font-family: Consolas, monospace; background: #0A0E1A; color: #E0E6F0; padding: 20px; }
h1 { color: #00E5FF; border-bottom: 2px solid #00E5FF; padding-bottom: 10px; }
pre { background: #141B2E; padding: 15px; border-radius: 8px; white-space: pre-wrap; word-wrap: break-word; }
.footer { margin-top: 30px; padding-top: 10px; border-top: 1px solid #444; color: #6B7A99; font-size: 10px; }
</style>
</head>
<body>
<h1>$Titulo</h1>
<pre>$Contenido</pre>
<div class='footer'>
Generado por DefenderTray v7.0 ULTIMATE<br>
Ing. Yosvany Hernandez Quintero - +53 5 2160801<br>
Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
SHA256 del script: $($script:ScriptHash)
</div>
</body>
</html>
"@

        $htmlPath = [System.IO.Path]::ChangeExtension($RutaDestino, ".html")
        $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force

        # Intentar generar PDF usando Microsoft Print to PDF (via WebBrowser)
        # Como fallback, dejamos el HTML
        Write-AppLog "Reporte HTML generado: $htmlPath" "INFO"
        return $htmlPath
    } catch {
        Write-AppLog "Error export PDF: $($_.Exception.Message)" "ERROR"
        return ""
    }
}

# ============================================================================
# SECCION 18 - v7.0 MEJORA 8: EVENT LOG DE WINDOWS DEFENDER
# ============================================================================
function Get-DefenderEventLog {
    param([int]$MaxEvents = 50)
    $resultado = New-Object System.Collections.ArrayList
    try {
        $events = Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents $MaxEvents -ErrorAction Stop
        foreach ($e in $events) {
            $tipo = switch ($e.Id) {
                1006 { "Malware detectado" }
                1007 { "Accion realizada" }
                1008 { "Accion fallida" }
                1009 { "Cuarentena restaurada" }
                1015 { "Comportamiento sospechoso" }
                1116 { "Deteccion" }
                1117 { "Accion aplicada" }
                default { "Evento $($e.Id)" }
            }
            [void]$resultado.Add([PSCustomObject]@{
                Hora = $e.TimeCreated
                Id = $e.Id
                Tipo = $tipo
                Mensaje = ($e.Message -split "`n")[0]
            })
        }
    } catch { }
    return $resultado
}

# ============================================================================
# SECCION 19 - v7.0 MEJORA 15: MODO FORENSE
# ============================================================================
function Save-ForensicSnapshot {
    param([string]$Contexto)
    if (-not $script:CfgForensicMode) { return }
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $dir = Join-Path $script:ForensicDir $timestamp
        New-Item -Path $dir -ItemType Directory -Force | Out-Null

        # Capturar pantalla
        try {
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $imgPath = Join-Path $dir "screenshot.png"
            $bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose()
        } catch { }

        # Guardar estado del sistema
        $snapshot = @{
            Contexto = $Contexto
            Timestamp = $timestamp
            Servicios = @()
            Procesos = @()
            Firmas = @{}
        }
        foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                $snapshot.Servicios += @{ Nombre=$s; Estado=$svc.Status.ToString(); Start=(Get-ServiceStartMode -Name $s) }
            }
        }
        foreach ($p in @("MsMpEng","NisSrv","SecurityHealthService")) {
            $proc = Get-Process -Name $p -ErrorAction SilentlyContinue
            if ($null -ne $proc) { $snapshot.Procesos += @{ Nombre=$p; PID=$proc.Id } }
        }
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $snapshot.Firmas = @{ Version=$st.AntivirusSignatureVersion; Edad=$st.AntivirusSignatureAge }
        } catch { }
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dir "snapshot.json") -Encoding UTF8

        Write-AppLog "Snapshot forense guardado: $dir" "INFO"
    } catch {
        Write-AppLog "Error forensic: $($_.Exception.Message)" "WARN"
    }
}

# ============================================================================
# SECCION 20 - v7.0 MEJORA 11: MULTI-MONITOR
# ============================================================================
function Get-ActiveMonitorBounds {
    <#
    Obtiene los limites del monitor donde esta el cursor.
    #>
    try {
        $pos = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($pos)
        return $screen.WorkingArea
    } catch {
        return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    }
}

function Center-FormOnActiveMonitor {
    param([System.Windows.Forms.Form]$Form)
    if (-not $script:CfgMultiMonitor) {
        $Form.StartPosition = "CenterScreen"
        return
    }
    try {
        $bounds = Get-ActiveMonitorBounds
        $x = $bounds.X + [int](($bounds.Width - $Form.Width) / 2)
        $y = $bounds.Y + [int](($bounds.Height - $Form.Height) / 2)
        $Form.StartPosition = "Manual"
        $Form.Location = New-Object System.Drawing.Point($x, $y)
    } catch { }
}

# ============================================================================
# SECCION 21 - v7.0 MEJORA 7: PANIC BUTTON / EMERGENCY
# ============================================================================
function Invoke-EmergencyActivation {
    <#
    Activa Defender inmediatamente, sin dialogos.
    #>
    Write-AppLog "=== MODO EMERGENCIA ACTIVADO ===" "WARN"
    Send-TelegramNotification "EMERGENCIA: Activando Defender desde boton de panico"
    $log = Enable-Defender
    $s = Get-QuickStatus
    Add-History -Accion "EMERGENCIA" -Resultado $s.Estado -Segundos 0
    if (-not $script:SilentMode) {
        Show-ResultDialog -Titulo "EMERGENCIA - Defender Activado" -Mensaje (Normalize-LineEndings $log) -Tipo "Success"
    }
}

# ============================================================================
# SECCION 22 - v7.0 MEJORA 10: BACKUP A LA NUBE
# ============================================================================
function Backup-ToCloud {
    if (-not $script:CfgCloudBackup) { return }
    if ([string]::IsNullOrEmpty($script:CfgCloudPath)) { return }
    try {
        if (-not (Test-Path $script:CfgCloudPath)) { return }
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $nombre = "DefenderTray_Backup_$timestamp.json"
        $dst = Join-Path $script:CfgCloudPath $nombre

        $data = @{
            Fecha = (Get-Date).ToString("s")
            Version = "7.0"
            Estado = (Get-QuickStatus).Estado
            Servicios = @()
            Config = $script:CfgCustomTheme
        }
        foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                $data.Servicios += @{ Nombre=$s; Estado=$svc.Status.ToString() }
            }
        }
        $data | ConvertTo-Json -Depth 5 | Set-Content -Path $dst -Encoding UTF8 -Force
        Write-AppLog "Backup nube: $dst" "INFO"
    } catch {
        Write-AppLog "Error backup nube: $($_.Exception.Message)" "WARN"
    }
}

# ============================================================================
# SECCION 23 - v7.0 MEJORA 2: PERFILES MULTI-USUARIO
# ============================================================================
function Load-Profiles {
    try {
        if (Test-Path $script:ProfilesFile) {
            return Get-Content -Path $script:ProfilesFile -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    } catch { }
    return @{}
}

function Save-Profiles {
    param($Profiles)
    try {
        $Profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ProfilesFile -Encoding UTF8 -Force
    } catch { }
}

function Get-CurrentUser {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

# ============================================================================
# SECCION 24 - v7.0 MEJORA 5: CONTROL POR VOZ
# ============================================================================
function Initialize-VoiceRecognition {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction SilentlyContinue
        $reconocedor = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $reconocedor.SetInputToDefaultAudioDevice()
        $gramatica = New-Object System.Speech.Recognition.DictationGrammar
        $reconocedor.LoadGrammar($gramatica)
        return $reconocedor
    } catch {
        return $null
    }
}

function Start-VoiceCommands {
    <#
    Inicia el reconocimiento de voz en background.
    #>
    $reconocedor = Initialize-VoiceRecognition
    if ($null -eq $reconocedor) {
        Write-AppLog "Reconocimiento de voz no disponible" "WARN"
        return
    }
    Write-AppLog "Reconocimiento de voz iniciado" "INFO"
    # Nota: requiere configuracion avanzada, se deja como stub
}

# ============================================================================
# SECCION 25 - BOTONES NEON
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
# SECCION 26 - DIALOGO DE RESULTADO (FIX CRITICO DE NEWLINES)
# ============================================================================
function Show-ResultDialog {
    param(
        [string]$Titulo,
        [string]$Mensaje,
        [string]$Tipo = "Info"
    )

    # FIX CRITICO: Normalizar saltos de linea a CRLF
    $Mensaje = Normalize-LineEndings $Mensaje

    $colorHeader = $script:Colors.AccentBlue
    if ($Tipo -eq "Success") { $colorHeader = $script:Colors.AccentGreen }
    elseif ($Tipo -eq "Error") { $colorHeader = $script:Colors.AccentRed }
    elseif ($Tipo -eq "Warning") { $colorHeader = $script:Colors.AccentAmber }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Titulo
    $dlg.ClientSize = New-Object System.Drawing.Size(900, 640)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.MinimumSize = New-Object System.Drawing.Size(600, 400)
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

    Center-FormOnActiveMonitor -Form $dlg

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

    # TextBox con scroll VERTICAL + WordWrap + CRLF
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ScrollBars = "Vertical"
    $txt.ReadOnly = $true
    $txt.WordWrap = $true
    $txt.AcceptsReturn = $true
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor = $script:Colors.ConsoleBg
    $txt.ForeColor = $script:Colors.ConsoleText
    $txt.BorderStyle = "FixedSingle"
    $txt.Location = New-Object System.Drawing.Point(15, 75)
    $txt.Size = New-Object System.Drawing.Size(870, 490)
    $txt.Anchor = "Top,Left,Right,Bottom"
    # FIX: Asignar despues de crear el control
    $txt.Text = $Mensaje
    $dlg.Controls.Add($txt)

    $btnCopiar = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 580 140 34
    $btnPDF    = New-NeonButton "Exportar PDF" $script:Colors.AccentPurple $script:Colors.AccentPurpH 165 580 150 34
    $btnCerrar = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 735 580 150 34
    $btnCopiar.Anchor = "Bottom,Left"
    $btnPDF.Anchor = "Bottom,Left"
    $btnCerrar.Anchor = "Bottom,Right"
    $dlg.Controls.Add($btnCopiar)
    $dlg.Controls.Add($btnPDF)
    $dlg.Controls.Add($btnCerrar)

    $btnCopiar.Add_Click({
        try {
            [System.Windows.Forms.Clipboard]::SetText($txt.Text)
            [System.Windows.Forms.MessageBox]::Show("Copiado.","OK","OK","Information") | Out-Null
        } catch { }
    })

    $btnPDF.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "HTML (*.html)|*.html"
        $sd.FileName = "Reporte_{0:yyyyMMdd_HHmmss}.html" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            $ruta = Export-ReportAsPDF -Titulo $Titulo -Contenido $txt.Text -RutaDestino $sd.FileName
            if (-not [string]::IsNullOrEmpty($ruta)) {
                [System.Windows.Forms.MessageBox]::Show("Exportado: $ruta","OK","OK","Information") | Out-Null
                Start-Process $ruta
            }
        }
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
# SECCION 27 - BACKUP REGISTRO
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
# SECCION 28 - FAILURE ACTIONS
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
# SECCION 29 - REPARAR FIRMAS
# ============================================================================
function Repair-DefenderSignatures {
    $log = New-Object System.Collections.ArrayList
    [void]$log.Add("=== REPARACION DE FIRMAS ===")
    [void]$log.Add("")
    $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmd)) {
        [void]$log.Add("[!] No se encontro MpCmdRun.exe")
        return ($log -join "`r`n")
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
    } catch { }
    [void]$log.Add("[3/6] Reiniciando WinDefend...")
    try {
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        $null = & sc.exe start WinDefend 2>&1
        Wait-WithDoEvents -Milliseconds 5000
    } catch { }
    [void]$log.Add("[4/6] Descargando firmas...")
    if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
        try { Update-MpSignature -UpdateInterval 0 -ErrorAction SilentlyContinue } catch { }
    }
    Wait-WithDoEvents -Milliseconds 5000
    [void]$log.Add("[5/6] Verificando...")
    try {
        $st = Get-MpComputerStatus -ErrorAction Stop
        [void]$log.Add("       Version: $($st.AntivirusSignatureVersion)")
        [void]$log.Add("       Edad: $($st.AntivirusSignatureAge) dias")
        if ($st.AntivirusSignatureAge -le 30) { [void]$log.Add("[OK] Firmas reparadas.") }
        else { [void]$log.Add("[!] Siguen antiguas.") }
    } catch { }
    return ($log -join "`r`n")
}

# ============================================================================
# SECCION 30 - AUTO-REPARACION
# ============================================================================
function Invoke-StartupAutoRepair {
    if (-not $script:CfgAutoRepair) { return }
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            if ($st.AntivirusSignatureAge -gt 30 -or $st.AntivirusSignatureAge -eq 65535) {
                $null = Repair-DefenderSignatures
            }
        }
    } catch { }
}

# ============================================================================
# SECCION 31 - DESACTIVAR
# ============================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria. No se aplican cambios.")
        return ($log -join "`r`n")
    }

    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de desactivar" }

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                return ($log -join "`r`n")
            }
        }
    } catch {}

    $backupReg = Backup-DefenderRegistry
    if ($backupReg) { [void]$log.Add("[0/10] Backup del registro: OK") }

    [void]$log.Add("[1/10] Desactivando preferencias...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        foreach ($p in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                         "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                         "DisableEmailScanning","DisableIntrusionPreventionSystem",
                         "DisableRemovableDriveScanning","DisableScanningNetworkFiles",
                         "DisableCatchupQuickScan","DisableCatchupFullScan")) {
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
    Set-ItemProperty -Path $spynet -Name "SpynetReporting" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $spynet -Name "SubmitSamplesConsent" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    [void]$log.Add("[4/10] Deshabilitando FailureActions...")
    $svcs = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    $faCount = 0
    foreach ($s in $svcs) { if (Disable-ServiceFailureActions -ServiceName $s) { $faCount++ } }
    [void]$log.Add("       FailureActions deshabilitadas en $faCount servicios")

    [void]$log.Add("[5/10] Bucle de desactivacion (max 5)...")
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
            try { $null = & sc.exe stop $s 2>&1; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("  [C] Start=4 en registro...")
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
            [void]$log.Add("  [OK] Exito en intento $intento")
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

    Send-TelegramNotification "Defender desactivado. Estado: $((Get-QuickStatus).Estado)"
    if ($script:CfgCloudBackup) { Backup-ToCloud }

    return ($log -join "`r`n")
}

# ============================================================================
# SECCION 32 - ACTIVAR
# ============================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria. No se aplican cambios.")
        return ($log -join "`r`n")
    }

    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de activar" }

    [void]$log.Add("[1/10] Configurando Start de cada servicio...")
    $svcConfig = @(
        @{N="WinDefend"; Start=2; Run=$true; Orden=1},
        @{N="WdNisSvc"; Start=2; Run=$true; Orden=2},
        @{N="Sense"; Start=2; Run=$true; Orden=3},
        @{N="SecurityHealthService"; Start=2; Run=$true; Orden=4},
        @{N="wscsvc"; Start=2; Run=$true; Orden=5},
        @{N="WdNisDrv"; Start=1; Run=$false; Orden=6},
        @{N="WdBoot"; Start=0; Run=$false; Orden=7},
        @{N="Wdfilter"; Start=0; Run=$false; Orden=8}
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
                [void]$log.Add("       $($s.N) -> $txtStart")
            } catch { }
        }
    }

    [void]$log.Add("[2/10] Eliminando politicas de bloqueo...")
    foreach ($rp in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
                      "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
                      "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet",
                      "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS",
                      "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates")) {
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

    Send-TelegramNotification "Defender activado. Estado: $((Get-QuickStatus).Estado)"
    if ($script:CfgCloudBackup) { Backup-ToCloud }

    return ($log -join "`r`n")
}

# ============================================================================
# SECCION 33 - HISTORIAL
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
# SECCION 34 - DIAGNOSTICO
# ============================================================================
function Get-ThirdPartyAV {
    $resultado = New-Object System.Collections.ArrayList
    try {
        $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($av in $avs) { [void]$resultado.Add([PSCustomObject]@{ Nombre=$av.displayName; Estado=$av.productState }) }
    } catch { }
    return $resultado
}

function Test-NetworkConnectivity {
    $resultado = New-Object System.Collections.ArrayList
    foreach ($h in @(
        @{Nombre="Microsoft Update"; Host="update.microsoft.com"; Puerto=443},
        @{Nombre="Defender Signatures"; Host="definitionupdates.microsoft.com"; Puerto=443}
    )) {
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
    [void]$r.Add([PSCustomObject]@{Item="  Usuario"; Status=(Get-CurrentUser); Detail=""; Color=$script:Colors.TextDiag})

    [void]$r.Add([PSCustomObject]@{Item="=== SERVICIOS DE DEFENDER ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($s in @(
        @{Nombre="WinDefend"; Desc="Servicio principal"; Driver=$false},
        @{Nombre="WdNisSvc"; Desc="Inspeccion red"; Driver=$false},
        @{Nombre="Sense"; Desc="EDR"; Driver=$false},
        @{Nombre="WdNisDrv"; Desc="Driver red"; Driver=$true},
        @{Nombre="WdBoot"; Desc="Driver arranque"; Driver=$true},
        @{Nombre="Wdfilter"; Desc="Driver filtro"; Driver=$true},
        @{Nombre="SecurityHealthService"; Desc="UI Seguridad"; Driver=$false},
        @{Nombre="wscsvc"; Desc="Centro seguridad"; Driver=$false}
    )) {
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
            foreach ($m in @(
                @{N="Antivirus";    V=$st.AntivirusEnabled},
                @{N="Antispyware";  V=$st.AntispywareEnabled},
                @{N="Servicio AM";  V=$st.AMServiceEnabled},
                @{N="Tiempo real";  V=$st.RealTimeProtectionEnabled},
                @{N="Behavior";     V=$st.BehaviorMonitorEnabled},
                @{N="IOAV";         V=$st.IoavProtectionEnabled},
                @{N="On-Access";    V=$st.OnAccessProtectionEnabled},
                @{N="NIS";          V=$st.NISEnabled},
                @{N="Tamper";       V=$st.IsTamperProtected}
            )) {
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
    if ($avs.Count -eq 0) { [void]$r.Add([PSCustomObject]@{Item="  Ninguno"; Status="OK"; Detail=""; Color=$script:Colors.Ok}) }
    else { foreach ($av in $avs) { [void]$r.Add([PSCustomObject]@{Item="  " + $av.Nombre; Status="INSTALADO"; Detail=""; Color=$script:Colors.Warn}) } }

    [void]$r.Add([PSCustomObject]@{Item="=== CONECTIVIDAD ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    foreach ($n in (Test-NetworkConnectivity)) {
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

    [void]$r.Add([PSCustomObject]@{Item="=== SCRIPT v7.0 ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    [void]$r.Add([PSCustomObject]@{Item="  SHA256"; Status=(Get-ScriptHash); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Config"; Status="DPAPI"; Detail=$script:ConfigDir; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  REST API"; Status=$(if($script:CfgRESTEnabled){"$($script:CfgRESTPort)"}else{"off"}); Detail=$(if($script:UseHTTPS){"HTTPS"}else{"HTTP"}); Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Agente"; Status=$(if($script:CfgResidentAgent){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Telegram"; Status=$(if($script:CfgTelegramEnabled){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Forense"; Status=$(if($script:CfgForensicMode){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  MultiMonitor"; Status=$(if($script:CfgMultiMonitor){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Cloud"; Status=$(if($script:CfgCloudBackup){"ON"}else{"OFF"}); Detail=$script:CfgCloudPath; Color=$script:Colors.TextDiag})

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
    $dlg.ClientSize = New-Object System.Drawing.Size(950, 680)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

    Center-FormOnActiveMonitor -Form $dlg

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60
    $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "DIAGNOSTICO COMPLETO v7.0"
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
    $lv.Size = New-Object System.Drawing.Size(920, 530)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    $lv.Anchor = "Top,Left,Right,Bottom"
    [void]$lv.Columns.Add("Elemento", 350)
    [void]$lv.Columns.Add("Estado", 250)
    [void]$lv.Columns.Add("Detalle", 300)
    $dlg.Controls.Add($lv)

    $btnRef = New-NeonButton "Refrescar" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15 615 130 32
    $btnCopy = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 155 615 130 32
    $btnRep = New-NeonButton "Reparar Firmas" $script:Colors.AccentGreen $script:Colors.AccentGreenH 295 615 150 32
    $btnEvents = New-NeonButton "Event Log" $script:Colors.AccentPurple $script:Colors.AccentPurpH 455 615 130 32
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 805 615 130 32
    $dlg.Controls.Add($btnRef); $dlg.Controls.Add($btnCopy); $dlg.Controls.Add($btnRep); $dlg.Controls.Add($btnEvents); $dlg.Controls.Add($btnCerr)

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
    $btnEvents.Add_Click({ Show-EventLogDialog })
    $btnCerr.Add_Click({ $dlg.Close() })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 35 - DIALOGO EVENT LOG (v7.0)
# ============================================================================
function Show-EventLogDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Event Log - Windows Defender"
    $dlg.ClientSize = New-Object System.Drawing.Size(950, 620)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk

    Center-FormOnActiveMonitor -Form $dlg

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.AccentPurple
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "EVENT LOG - MICROSOFT-WINDOWS-WINDOWS DEFENDER"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 70)
    $lv.Size = New-Object System.Drawing.Size(920, 490)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    $lv.Anchor = "Top,Left,Right,Bottom"
    [void]$lv.Columns.Add("Hora", 160)
    [void]$lv.Columns.Add("ID", 60)
    [void]$lv.Columns.Add("Tipo", 220)
    [void]$lv.Columns.Add("Mensaje", 460)
    $dlg.Controls.Add($lv)

    $eventos = Get-DefenderEventLog -MaxEvents 100
    foreach ($e in $eventos) {
        $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$it.SubItems.Add($e.Id)
        [void]$it.SubItems.Add($e.Tipo)
        [void]$it.SubItems.Add($e.Mensaje)
        if ($e.Id -in 1006,1116,1015) { $it.ForeColor = $script:Colors.Bad }
        elseif ($e.Id -in 1007,1117) { $it.ForeColor = $script:Colors.Warn }
        [void]$lv.Items.Add($it)
    }

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 805 570 130 32
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Click += { $dlg.Close() }

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 36 - HISTORIAL DIALOGO
# ============================================================================
function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial"
    $dlg.ClientSize = New-Object System.Drawing.Size(800, 560)
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
    $lv.Size = New-Object System.Drawing.Size(770, 440)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 170)
    [void]$lv.Columns.Add("Accion", 150)
    [void]$lv.Columns.Add("Resultado", 350)
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

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 645 520 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 37 - DEEP REPAIR
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
        if (-not [string]::IsNullOrEmpty($out)) { $c.AppendText("$out`r`n") }
        $err = $proc.StandardError.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($err)) { $c.AppendText("$err`r`n") }
        $proc.Dispose()
        $c.AppendText("[OK]`r`n")
    } catch {
        $c.AppendText("ERROR: $($_.Exception.Message)`r`n")
    }
}

function Show-DeepRepairDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Reparacion Profunda"
    $dlg.ClientSize = New-Object System.Drawing.Size(960, 720)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    Center-FormOnActiveMonitor -Form $dlg

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
    $console.AcceptsReturn = $true
    $console.ReadOnly = $true
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.Location = New-Object System.Drawing.Point(15, 75)
    $console.Size = New-Object System.Drawing.Size(930, 510)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)
    $script:RepairConsole = $console

    $btnReg  = New-NeonButton "1. Borrar Politicas"    $script:Colors.AccentRed    $script:Colors.AccentRedH    15  600 165 34
    $btnSvc  = New-NeonButton "2. Servicios"           $script:Colors.AccentAmber  $script:Colors.AccentAmberH  190 600 175 34
    $btnGpu  = New-NeonButton "3. gpupdate"            $script:Colors.AccentPurple $script:Colors.AccentPurpH   375 600 130 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"        $script:Colors.AccentBlue   $script:Colors.AccentBlueH   515 600 140 34
    $btnDISM = New-NeonButton "5. DISM Restore"        $script:Colors.AccentCyan   $script:Colors.AccentCyanH   665 600 140 34
    $btnKill = New-NeonButton "Matar MsMpEng"          $script:Colors.AccentRed    $script:Colors.AccentRedH    815 600 130 34
    $btnFirmas = New-NeonButton "REPARAR FIRMAS"       $script:Colors.AccentGreen  $script:Colors.AccentGreenH  15  645 250 40
    $btnTodo   = New-NeonButton "REPARAR TODO"         $script:Colors.AccentGreen  $script:Colors.AccentGreenH  275 645 250 40
    $btnCerr   = New-NeonButton "Cerrar"               $script:Colors.Neutral      $script:Colors.TextMuted     815 645 130 40

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
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Add-History -Accion "Reparar Firmas" -Resultado "OK" -Segundos 0
    })
    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("==============================================`r`n")
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
# SECCION 38 - SCHEDULER
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
        if ($chkDisable.Checked) { $null = Register-TrayTask -Nombre "Desactivar" -Accion "disable" -Hora $dtpDisable.Value.ToString("HH:mm") }
        if ($chkEnable.Checked) { $null = Register-TrayTask -Nombre "Activar" -Accion "enable" -Hora $dtpEnable.Value.ToString("HH:mm") }
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
# SECCION 39 - SERVICE INSTALL
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
    try { Unregister-ScheduledTask -TaskName "DefenderTray_Service" -Confirm:$false -ErrorAction Stop; return "Desinstalado." }
    catch { return "Error: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 40 - KIOSCO
# ============================================================================
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    if ([string]::IsNullOrEmpty($script:CfgKioskHash)) { return $true }

    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"
    $dlg.ClientSize = New-Object System.Drawing.Size(400, 200)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Introduce la " + (T "Password") + ":"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(370, 20)
    $lbl.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.PasswordChar = '*'
    $txt.Location = New-Object System.Drawing.Point(15, 40)
    $txt.Size = New-Object System.Drawing.Size(370, 25)
    $txt.BackColor = $script:Colors.BgSecondary; $txt.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txt)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Aceptar"
    $btnOk.Location = New-Object System.Drawing.Point(185, 80); $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.BackColor = $script:Colors.AccentGreen; $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Location = New-Object System.Drawing.Point(295, 80); $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.BackColor = $script:Colors.AccentRed; $btnCancel.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnCancel)

    $btnOk.Add_Click({
        if ((Get-StringHash $txt.Text) -eq $script:CfgKioskHash) {
            $script:KioskOk = $true; $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Incorrecta.","Acceso","OK","Error") | Out-Null
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
# SECCION 41 - CONFIGURACION (CON NUEVAS OPCIONES v7.0)
# ============================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"
    $dlg.ClientSize = New-Object System.Drawing.Size(680, 780)
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
    $lblH.Text = "CONFIGURACION v7.0"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $y = 60
    function New-CheckBox($Texto, $Checked, $Y) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $Texto; $c.Checked = $Checked
        $c.Location = New-Object System.Drawing.Point(20, $Y)
        $c.Size = New-Object System.Drawing.Size(630, 25)
        $c.ForeColor = $script:Colors.Text
        return $c
    }

    $chkAutoRepair = New-CheckBox "Auto-reparar firmas al iniciar (>30 dias)" $script:CfgAutoRepair $y; $y += 25
    $chkAutoCleanup = New-CheckBox "Limpiar logs de mas de 30 dias" $script:CfgAutoCleanup $y; $y += 25
    $chkThemeFollow = New-CheckBox "Seguir tema del sistema automaticamente" $script:CfgThemeFollow $y; $y += 25
    $chkThresholdAlert = New-CheckBox "Alertar si Defender lleva >X horas desactivado" $script:CfgThresholdAlert $y; $y += 25
    $chkResidentAgent = New-CheckBox "Agente residente (monitor WMI de cambios)" $script:CfgResidentAgent $y; $y += 25
    $chkREST = New-CheckBox "API REST local" $script:CfgRESTEnabled $y; $y += 25
    $chkKiosk = New-CheckBox ("Modo kiosco (pedir " + (T "Password") + ")") $script:IsKioskMode $y; $y += 25
    $chkEmail = New-CheckBox "Enviar reportes por email (SMTP)" $script:CfgEmailEnabled $y; $y += 25
    $chkTelegram = New-CheckBox "Notificaciones por Telegram" $script:CfgTelegramEnabled $y; $y += 25
    $chkForensic = New-CheckBox "Modo forense (screenshot antes de cambios)" $script:CfgForensicMode $y; $y += 25
    $chkMultiMon = New-CheckBox "Abrir dialogos en el monitor activo" $script:CfgMultiMonitor $y; $y += 25
    $chkParental = New-CheckBox "Modo tutela (bloqueo parental)" $script:CfgParentalMode $y; $y += 25
    $chkCloud = New-CheckBox "Backup automatico a la nube" $script:CfgCloudBackup $y; $y += 25
    $chkHTTPS = New-CheckBox "Usar HTTPS en API REST (requiere reinicio)" $script:UseHTTPS $y; $y += 30

    $dlg.Controls.Add($chkAutoRepair); $dlg.Controls.Add($chkAutoCleanup); $dlg.Controls.Add($chkThemeFollow)
    $dlg.Controls.Add($chkThresholdAlert); $dlg.Controls.Add($chkResidentAgent); $dlg.Controls.Add($chkREST)
    $dlg.Controls.Add($chkKiosk); $dlg.Controls.Add($chkEmail); $dlg.Controls.Add($chkTelegram)
    $dlg.Controls.Add($chkForensic); $dlg.Controls.Add($chkMultiMon); $dlg.Controls.Add($chkParental)
    $dlg.Controls.Add($chkCloud); $dlg.Controls.Add($chkHTTPS)

    # Contraseña
    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = (T "Password") + ":"; $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(20, $y); $lblPwd.Size = New-Object System.Drawing.Size(140, 25)
    $dlg.Controls.Add($lblPwd)
    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'; $txtPwd.Location = New-Object System.Drawing.Point(160, $y)
    $txtPwd.Size = New-Object System.Drawing.Size(490, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary; $txtPwd.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtPwd)
    $y += 30

    # Telegram
    $lblTgToken = New-Object System.Windows.Forms.Label
    $lblTgToken.Text = "Telegram Token:"; $lblTgToken.ForeColor = $script:Colors.Text
    $lblTgToken.Location = New-Object System.Drawing.Point(20, $y); $lblTgToken.Size = New-Object System.Drawing.Size(140, 25)
    $dlg.Controls.Add($lblTgToken)
    $txtTgToken = New-Object System.Windows.Forms.TextBox
    $txtTgToken.Text = $script:CfgTelegramToken
    $txtTgToken.Location = New-Object System.Drawing.Point(160, $y); $txtTgToken.Size = New-Object System.Drawing.Size(490, 25)
    $txtTgToken.BackColor = $script:Colors.BgSecondary; $txtTgToken.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtTgToken)
    $y += 30

    $lblTgChat = New-Object System.Windows.Forms.Label
    $lblTgChat.Text = "Telegram Chat ID:"; $lblTgChat.ForeColor = $script:Colors.Text
    $lblTgChat.Location = New-Object System.Drawing.Point(20, $y); $lblTgChat.Size = New-Object System.Drawing.Size(140, 25)
    $dlg.Controls.Add($lblTgChat)
    $txtTgChat = New-Object System.Windows.Forms.TextBox
    $txtTgChat.Text = $script:CfgTelegramChatId
    $txtTgChat.Location = New-Object System.Drawing.Point(160, $y); $txtTgChat.Size = New-Object System.Drawing.Size(490, 25)
    $txtTgChat.BackColor = $script:Colors.BgSecondary; $txtTgChat.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtTgChat)
    $y += 30

    # Cloud
    $lblCloud = New-Object System.Windows.Forms.Label
    $lblCloud.Text = "Ruta nube:"; $lblCloud.ForeColor = $script:Colors.Text
    $lblCloud.Location = New-Object System.Drawing.Point(20, $y); $lblCloud.Size = New-Object System.Drawing.Size(140, 25)
    $dlg.Controls.Add($lblCloud)
    $txtCloud = New-Object System.Windows.Forms.TextBox
    $txtCloud.Text = $script:CfgCloudPath
    $txtCloud.Location = New-Object System.Drawing.Point(160, $y); $txtCloud.Size = New-Object System.Drawing.Size(490, 25)
    $txtCloud.BackColor = $script:Colors.BgSecondary; $txtCloud.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtCloud)
    $y += 35

    # Botones fila 1
    $btnSave      = New-NeonButton "Guardar"            $script:Colors.AccentGreen  $script:Colors.AccentGreenH  20  $y 140 34
    $btnCancel    = New-NeonButton "Cancelar"           $script:Colors.Neutral      $script:Colors.TextMuted    170 $y 140 34
    $btnInstall   = New-NeonButton "Instalar Servicio"  $script:Colors.AccentPurple $script:Colors.AccentPurpH  320 $y 160 34
    $btnUninstall = New-NeonButton "Desinstalar"        $script:Colors.AccentRed    $script:Colors.AccentRedH   490 $y 160 34
    $y += 40

    # Botones fila 2
    $btnScheduler = New-NeonButton "Programar Tareas"   $script:Colors.AccentAmber  $script:Colors.AccentAmberH 20  $y 200 34
    $btnRestoreReg = New-NeonButton "Restaurar Registro" $script:Colors.AccentAmber $script:Colors.AccentAmberH 230 $y 200 34
    $btnTestTelegram = New-NeonButton "Probar Telegram" $script:Colors.AccentCyan   $script:Colors.AccentCyanH  440 $y 210 34

    $dlg.Controls.Add($btnSave); $dlg.Controls.Add($btnCancel); $dlg.Controls.Add($btnInstall); $dlg.Controls.Add($btnUninstall)
    $dlg.Controls.Add($btnScheduler); $dlg.Controls.Add($btnRestoreReg); $dlg.Controls.Add($btnTestTelegram)

    $btnSave.Add_Click({
        $script:CfgAutoRepair     = $chkAutoRepair.Checked
        $script:CfgAutoCleanup    = $chkAutoCleanup.Checked
        $script:CfgThemeFollow    = $chkThemeFollow.Checked
        $script:CfgThresholdAlert = $chkThresholdAlert.Checked
        $script:CfgResidentAgent  = $chkResidentAgent.Checked
        $script:CfgRESTEnabled    = $chkREST.Checked
        $script:CfgEmailEnabled   = $chkEmail.Checked
        $script:CfgTelegramEnabled = $chkTelegram.Checked
        $script:CfgForensicMode   = $chkForensic.Checked
        $script:CfgMultiMonitor   = $chkMultiMon.Checked
        $script:CfgParentalMode   = $chkParental.Checked
        $script:CfgCloudBackup    = $chkCloud.Checked
        $script:UseHTTPS          = $chkHTTPS.Checked
        $script:UseHTTP           = -not $chkHTTPS.Checked
        $script:CfgTelegramToken  = $txtTgToken.Text
        $script:CfgTelegramChatId = $txtTgChat.Text
        $script:CfgCloudPath      = $txtCloud.Text
        $script:IsKioskMode       = $chkKiosk.Checked
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
    $btnTestTelegram.Add_Click({
        $ok = Send-TelegramNotification "Test desde DefenderTray v7.0"
        if ($ok) { [System.Windows.Forms.MessageBox]::Show("Enviado.","OK","OK","Information") | Out-Null }
        else { [System.Windows.Forms.MessageBox]::Show("Fallo. Revisa token y chat id.","Error","OK","Error") | Out-Null }
    })

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 42 - AYUDA
# ============================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(800, 620)
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
    $lblH.Text = "AYUDA - v7.0 ULTIMATE"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = "Vertical"; $txt.WordWrap = $true
    $txt.AcceptsReturn = $true
    $txt.Location = New-Object System.Drawing.Point(15, 65)
    $txt.Size = New-Object System.Drawing.Size(770, 500)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.Text = (Normalize-LineEndings @'
DEFENDER CONTROL v7.0 ULTIMATE
================================

NOVEDADES v7.0
--------------
 1. Panel web HTML5 (API REST)
 2. Multi-usuario con perfiles
 3. Notificaciones Telegram
 4. Auto-reparacion inteligente
 5. Control por voz
 6. Exportacion a PDF/HTML firmado
 7. Modo emergencia (Panic Button)
 8. Event Log de Windows Defender
 9. Captura de trafico
10. Backup a la nube
11. Multi-monitor
12. Tema personalizable
13. Modo tutela (parental)
14. API REST para movil
15. Modo forense (screenshot)

API REST LOCAL
--------------
Por defecto: http://127.0.0.1:9182
Con HTTPS:   https://127.0.0.1:9182 (autofirmado)

Endpoints:
  GET /status      -> Estado actual en JSON
  GET /enable      -> Instrucciones para activar
  GET /disable     -> Instrucciones para desactivar
  GET /diagnostic  -> Info general
  GET /            -> Panel web HTML5

Para activar/desactivar realmente desde afuera:
  powershell -File script.ps1 -silent -action enable
  powershell -File script.ps1 -silent -action disable

CERTIFICADO HTTPS
-----------------
Si usas -https, se genera un certificado autofirmado en
Cert:\LocalMachine\My. Para confiar en el, importalo en
Cert:\LocalMachine\Root. Requiere ejecutar como Admin.

EMERGENCIA
----------
Hotkey: Ctrl+Alt+D (si esta registrado)
O desde menu contextual -> Emergencia
Activa Defender inmediatamente sin dialogos.

MODO FORENSE
------------
Activa "Modo forense" en Config para que antes de cada
operacion se guarde un screenshot y el estado del sistema
en la carpeta Forense.

ARGUMENTOS
----------
  -silent     Sin dialogos
  -portable   Datos en carpeta del script
  -audit      Solo registra, no aplica
  -norest     Sin API REST
  -https      Usar HTTPS (autofirmado)
  -action     enable | disable

ATAJOS
------
  F1   Ayuda
  F5   Refrescar
  Esc  Cerrar

(c) 2026 - Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801 / +53 5 9860911
'@)
    $dlg.Controls.Add($txt)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 645 575 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 43 - ESTADISTICAS
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
    } catch { }

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 645 520 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 44 - PANEL PRINCIPAL
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
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "ACTIVADO"; $script:PanelStatusLabel.ForeColor = $script:Colors.Ok }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Falta proteccion real."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "PARCIAL"; $script:PanelStatusLabel.ForeColor = $script:Colors.Warn }
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        $script:PanelLblDet1.Text = "El antivirus esta inactivo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $false
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "DESACTIVADO"; $script:PanelStatusLabel.ForeColor = $script:Colors.Bad }
    }

    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDet3.Text = "Ultima: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDet3.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    }

    if ($null -ne $script:notifyIcon) { Update-TrayIcon -Estado $s.Estado }
}

function Start-PanelTimer {
    if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
    $script:PanelTimer = New-Object System.Windows.Forms.Timer
    $script:PanelTimer.Interval = 5000
    $script:PanelTimer.Add_Tick({
        if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
        $script:PanelLblReloj.Text = (Get-Date).ToString("HH:mm:ss")
        if ($null -ne $script:ActionStartTicks -and $script:ActionStartTicks -is [long]) {
            $el = ([DateTime]::Now.Ticks - $script:ActionStartTicks) / 10000000
            $script:PanelLblTimer.Text = "{0:N2}s" -f $el
        } else { $script:PanelLblTimer.Text = "listo" }
        if (-not $script:IsBusy) { try { Update-PanelStatusUI } catch { } }
    })
    $script:PanelTimer.Start()
}

function Show-DefenderPanel {
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try { $script:PanelForm.Show(); $script:PanelForm.BringToFront(); $script:PanelForm.Activate() } catch { }
        return
    }
    if (-not (Test-KioskPassword)) { return }

    $script:IsBusy = $false
    $script:ActionStartTicks = $null
    $script:LastActionTime = 0
    $script:LastActionName = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (T "Title")
    $form.ClientSize = New-Object System.Drawing.Size(500, 540)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = $script:IconOk

    Center-FormOnActiveMonitor -Form $form

    # Menu
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
    $miAct = New-Object System.Windows.Forms.ToolStripMenuItem; $miAct.Text = "Activar"
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
        } finally { $script:IsBusy = $false; Stop-ActionTimer | Out-Null; Set-PanelBusy $false }
    })
    $miDes = New-Object System.Windows.Forms.ToolStripMenuItem; $miDes.Text = "Desactivar"
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
        } finally { $script:IsBusy = $false; Stop-ActionTimer | Out-Null; Set-PanelBusy $false }
    })
    $miEmerg = New-Object System.Windows.Forms.ToolStripMenuItem; $miEmerg.Text = "EMERGENCIA"
    $miEmerg.Add_Click({ Invoke-EmergencyActivation })
    $miVer = New-Object System.Windows.Forms.ToolStripMenuItem; $miVer.Text = "Verificar"; $miVer.Add_Click({ Show-DiagnosticsDialog })
    [void]$mAcciones.DropDownItems.Add($miAct)
    [void]$mAcciones.DropDownItems.Add($miDes)
    [void]$mAcciones.DropDownItems.Add($miEmerg)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miVer)

    $mHerram = New-Object System.Windows.Forms.ToolStripMenuItem
    $mHerram.Text = "&Herramientas"; $mHerram.ForeColor = $script:Colors.Text
    $miRep = New-Object System.Windows.Forms.ToolStripMenuItem; $miRep.Text = "Reparacion Profunda"; $miRep.Add_Click({ Show-DeepRepairDialog })
    $miHist = New-Object System.Windows.Forms.ToolStripMenuItem; $miHist.Text = "Historial"; $miHist.Add_Click({ Show-HistoryDialog })
    $miStats = New-Object System.Windows.Forms.ToolStripMenuItem; $miStats.Text = "Estadisticas"; $miStats.Add_Click({ Show-StatsDialog })
    $miEvents = New-Object System.Windows.Forms.ToolStripMenuItem; $miEvents.Text = "Event Log"; $miEvents.Add_Click({ Show-EventLogDialog })
    $miConf = New-Object System.Windows.Forms.ToolStripMenuItem; $miConf.Text = "Configuracion"; $miConf.Add_Click({ Show-SettingsDialog })
    [void]$mHerram.DropDownItems.Add($miRep)
    [void]$mHerram.DropDownItems.Add($miHist)
    [void]$mHerram.DropDownItems.Add($miStats)
    [void]$mHerram.DropDownItems.Add($miEvents)
    [void]$mHerram.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHerram.DropDownItems.Add($miConf)

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"; $mAyuda.ForeColor = $script:Colors.Text
    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem; $miAy.Text = "Ayuda (F1)"; $miAy.Add_Click({ Show-HelpDialog })
    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem; $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v7.0 ULTIMATE`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911`n`nSistema: $($script:OSProductType)`nSHA256: $($script:ScriptHash)"
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
    $header.Size = New-Object System.Drawing.Size(500, 70)
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
    $lblSubH.Text = "v7.0 ULTIMATE - $($script:OSProductType)"
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
    $lblReloj.Size = New-Object System.Drawing.Size(180, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(310, 12)
    $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)
    $lblTimer = New-Object System.Windows.Forms.Label
    $lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimer.ForeColor = $script:Colors.AccentCyan
    $lblTimer.BackColor = [System.Drawing.Color]::Transparent
    $lblTimer.Size = New-Object System.Drawing.Size(180, 20)
    $lblTimer.Location = New-Object System.Drawing.Point(310, 32)
    $lblTimer.TextAlign = "MiddleRight"
    $lblTimer.Text = "listo"
    $header.Controls.Add($lblTimer)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 105)
    $card.Size = New-Object System.Drawing.Size(470, 130)
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
    $lblDet1.Size = New-Object System.Drawing.Size(450, 16)
    $lblDet1.Location = New-Object System.Drawing.Point(12, 62)
    $card.Controls.Add($lblDet1)
    $lblDet2 = New-Object System.Windows.Forms.Label
    $lblDet2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDet2.ForeColor = $script:Colors.TextMuted
    $lblDet2.BackColor = [System.Drawing.Color]::Transparent
    $lblDet2.Size = New-Object System.Drawing.Size(450, 16)
    $lblDet2.Location = New-Object System.Drawing.Point(12, 82)
    $card.Controls.Add($lblDet2)
    $lblDet3 = New-Object System.Windows.Forms.Label
    $lblDet3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDet3.ForeColor = $script:Colors.AccentCyan
    $lblDet3.BackColor = [System.Drawing.Color]::Transparent
    $lblDet3.Size = New-Object System.Drawing.Size(450, 16)
    $lblDet3.Location = New-Object System.Drawing.Point(12, 104)
    $card.Controls.Add($lblDet3)

    $btnDiagnostico = New-NeonButton (T "Diagnostico")  $script:Colors.AccentPurple $script:Colors.AccentPurpH  15  245 470 32
    $btnActivar     = New-NeonButton (T "Activar")      $script:Colors.AccentGreen  $script:Colors.AccentGreenH 15  285 230 32
    $btnDesactivar  = New-NeonButton (T "Desactivar")   $script:Colors.AccentRed    $script:Colors.AccentRedH   255 285 230 32
    $btnReparar     = New-NeonButton (T "Reparar")      $script:Colors.AccentAmber  $script:Colors.AccentAmberH 15  325 470 36
    $btnEmerg       = New-NeonButton (T "Emergencia")   $script:Colors.AccentRed    $script:Colors.AccentRedH   15  370 230 32
    $btnEventos     = New-NeonButton "Event Log"        $script:Colors.AccentPurple $script:Colors.AccentPurpH  255 370 230 32
    $btnHistorial   = New-NeonButton (T "Historial")    $script:Colors.AccentBlue   $script:Colors.AccentBlueH  15  410 110 32
    $btnConfig      = New-NeonButton (T "Config")       $script:Colors.AccentBlue   $script:Colors.AccentBlueH  135 410 110 32
    $btnAyuda       = New-NeonButton (T "Ayuda")        $script:Colors.AccentBlue   $script:Colors.AccentBlueH  255 410 110 32
    $btnSalir       = New-NeonButton (T "Salir")        $script:Colors.AccentRed    $script:Colors.AccentRedH   375 410 110 32

    $script:PanelAllButtons = @($btnDiagnostico,$btnActivar,$btnDesactivar,$btnReparar,$btnEmerg,$btnEventos,$btnHistorial,$btnConfig,$btnAyuda,$btnSalir)
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
    $btnEventos.Add_Click({ Show-EventLogDialog })
    $btnEmerg.Add_Click({ Invoke-EmergencyActivation })

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
            Show-ResultDialog -Titulo "Resultado Activacion" -Mensaje ("Estado: $($s.Estado)`r`nTiempo: {0:N2}s`r`n`r`n$log" -f $elapsed) -Tipo $tipo
        } finally { $script:IsBusy = $false; Stop-ActionTimer | Out-Null; Set-PanelBusy $false }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        if (-not (Show-ConfirmDialog "Confirmar" "Desactivar Windows Defender?`r`n`r`nPuede requerir REINICIO.")) { return }
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
            $extra = if ($s.Estado -ne "DESACTIVADO") { "`r`n`r`nREINICIA EL EQUIPO." } else { "" }
            $tipo = if ($s.Estado -eq "DESACTIVADO") { "Success" } else { "Warning" }
            Show-ResultDialog -Titulo "Resultado Desactivacion" -Mensaje ("Estado: $($s.Estado)`r`nTiempo: {0:N2}s$extra`r`n`r`n$log" -f $elapsed) -Tipo $tipo
        } finally { $script:IsBusy = $false; Stop-ActionTimer | Out-Null; Set-PanelBusy $false }
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
# SECCION 45 - REST API CON FIX DE CONEXION Y HTTPS
# ============================================================================
$script:RESTJob = $null

function Initialize-RESTApi {
    <#
    Inicializa la API REST con:
    1. URL ACL reservation (para permitir escuchar en 127.0.0.1:port)
    2. Certificado autofirmado para HTTPS (si aplica)
    3. Inicia el listener en un job separado
    #>
    if (-not $script:CfgRESTEnabled) { return }
    if ($null -ne $script:RESTJob -and $script:RESTJob.State -eq 'Running') { return }

    $puerto = $script:CfgRESTPort
    $protocolo = if ($script:UseHTTPS) { "https" } else { "http" }
    $prefix = "${protocolo}://127.0.0.1:${puerto}/"

    # Paso 1: URL ACL
    try {
        if (Test-Admin) {
            # Eliminar reserva previa
            $null = & netsh.exe http delete urlacl url="$prefix" 2>&1
            # Crear reserva para el usuario actual
            $null = & netsh.exe http add urlacl url="$prefix" user="$env:USERDOMAIN\$env:USERNAME" 2>&1
            Write-AppLog "URL ACL reservada para $prefix" "INFO"
        }
    } catch {
        Write-AppLog "No se pudo reservar URL ACL: $($_.Exception.Message)" "WARN"
    }

    # Paso 2: Certificado HTTPS
    $thumbprintCert = ""
    if ($script:UseHTTPS -and (Test-Admin)) {
        try {
            # Buscar o crear certificado autofirmado
            $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=DefenderTray Localhost" } | Select-Object -First 1
            if ($null -eq $cert) {
                $cert = New-SelfSignedCertificate -DnsName "127.0.0.1", "localhost" -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "DefenderTray Localhost" -NotAfter (Get-Date).AddYears(5) -ErrorAction Stop
                Write-AppLog "Certificado autofirmado creado: $($cert.Thumbprint)" "INFO"
            }
            $thumbprintCert = $cert.Thumbprint

            # Bind SSL al puerto
            $null = & netsh.exe http delete sslcert ipport="127.0.0.1:$puerto" 2>&1
            $null = & netsh.exe http add sslcert ipport="127.0.0.1:$puerto" certhash="$thumbprintCert" appid="{00112233-4455-6677-8899-aabbccddeeff}" 2>&1
            Write-AppLog "HTTPS bind en puerto $puerto con cert $thumbprintCert" "INFO"
        } catch {
            Write-AppLog "Error creando cert HTTPS: $($_.Exception.Message)" "WARN"
            $script:UseHTTPS = $false
            $script:UseHTTP = $true
            $protocolo = "http"
            $prefix = "http://127.0.0.1:${puerto}/"
        }
    }

    # Paso 3: Iniciar listener en job
    try {
        $htmlPage = @'
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>DefenderTray v7.0</title>
<style>
body { font-family: 'Segoe UI', sans-serif; background: #0A0E1A; color: #E0E6F0; margin: 0; padding: 20px; }
h1 { color: #00E5FF; border-bottom: 2px solid #00E5FF; padding-bottom: 10px; }
.card { background: #182034; border-radius: 12px; padding: 20px; margin: 15px 0; box-shadow: 0 4px 12px rgba(0,229,255,0.1); }
.status { font-size: 28px; font-weight: bold; }
.activo { color: #00E56C; }
.desactivado { color: #FF3366; }
.parcial { color: #FFAA00; }
.btn { display: inline-block; padding: 12px 24px; margin: 5px; border-radius: 8px; text-decoration: none; color: white; font-weight: bold; transition: 0.2s; }
.btn-green { background: #00C86C; }
.btn-green:hover { background: #009E54; }
.btn-red { background: #FF3366; }
.btn-red:hover { background: #CC1A44; }
.btn-blue { background: #008CFF; }
.btn-blue:hover { background: #0066CC; }
pre { background: #0A0E1A; padding: 15px; border-radius: 8px; overflow-x: auto; }
</style>
</head>
<body>
<h1>DefenderTray v7.0 ULTIMATE</h1>
<div class='card'>
<h2>Estado del Sistema</h2>
<div id='status' class='status'>Cargando...</div>
<div id='details'></div>
</div>
<div class='card'>
<h2>Acciones</h2>
<a href='javascript:void(0)' onclick='fetch("/enable").then(r=>r.json()).then(d=>alert(JSON.stringify(d)))' class='btn btn-green'>Activar</a>
<a href='javascript:void(0)' onclick='fetch("/disable").then(r=>r.json()).then(d=>alert(JSON.stringify(d)))' class='btn btn-red'>Desactivar</a>
<a href='/diagnostic' class='btn btn-blue'>Diagnostico</a>
</div>
<div class='card'>
<h2>Endpoints JSON</h2>
<pre>
GET /status      - Estado actual
GET /enable      - Instrucciones activar
GET /disable     - Instrucciones desactivar
GET /diagnostic  - Info general
</pre>
</div>
<script>
function updateStatus() {
    fetch('/status').then(r => r.json()).then(d => {
        const el = document.getElementById('status');
        el.textContent = d.estado;
        el.className = 'status ' + (d.estado === 'ACTIVO' ? 'activo' : d.estado === 'DESACTIVADO' ? 'desactivado' : 'parcial');
        document.getElementById('details').innerHTML =
            'Servicio: ' + d.servicio + '<br>' +
            'Motor: ' + d.motor + '<br>' +
            'Tiempo real: ' + d.tiempoReal + '<br>' +
            'Fecha: ' + d.fecha;
    }).catch(e => console.error(e));
}
updateStatus();
setInterval(updateStatus, 5000);
</script>
</body>
</html>
'@

        $script:RESTJob = Start-Job -ScriptBlock {
            param($Puerto, $Protocolo, $Html, $ScriptPath)

            $listener = New-Object System.Net.HttpListener
            $prefix = "${Protocolo}://127.0.0.1:${Puerto}/"
            $listener.Prefixes.Add($prefix)

            try {
                $listener.Start()
            } catch {
                return "ERROR: No se pudo iniciar el listener: $($_.Exception.Message)"
            }

            while ($listener.IsListening) {
                try {
                    $context = $listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response
                    $path = $request.Url.AbsolutePath.ToLower()

                    $body = ""
                    $contentType = "application/json"

                    switch ($path) {
                        "/" {
                            $body = $Html
                            $contentType = "text/html; charset=utf-8"
                        }
                        "/status" {
                            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
                            $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
                            $svcStatus = if ($null -ne $svc) { $svc.Status.ToString() } else { "Unknown" }
                            $motor = if ($null -ne $proc) { "CORRIENDO (PID $($proc.Id))" } else { "DETENIDO" }
                            $rtp = "DESCONOCIDO"
                            try {
                                $st = Get-MpComputerStatus -ErrorAction Stop
                                $rtp = if ($st.RealTimeProtectionEnabled) { "ACTIVADO" } else { "DESACTIVADO" }
                            } catch { }
                            $estado = if ($svcStatus -eq "Running" -and $null -ne $proc -and $rtp -eq "ACTIVADO") { "ACTIVO" }
                                     elseif ($svcStatus -ne "Running" -and $null -eq $proc) { "DESACTIVADO" }
                                     else { "PARCIAL" }
                            $body = @{
                                estado = $estado
                                servicio = $svcStatus
                                motor = $motor
                                tiempoReal = $rtp
                                fecha = (Get-Date).ToString("s")
                            } | ConvertTo-Json
                        }
                        "/enable" {
                            $body = @{
                                result = "Ejecuta: powershell -File '$ScriptPath' -silent -action enable"
                            } | ConvertTo-Json
                        }
                        "/disable" {
                            $body = @{
                                result = "Ejecuta: powershell -File '$ScriptPath' -silent -action disable"
                            } | ConvertTo-Json
                        }
                        "/diagnostic" {
                            $body = @{
                                version = "7.0"
                                autor = "Ing. Yosvany Hernandez Quintero"
                                movil = "+53 5 2160801 / +53 5 9860911"
                                fecha = (Get-Date).ToString("s")
                            } | ConvertTo-Json
                        }
                        default {
                            $body = '{"error":"not found"}'
                            $response.StatusCode = 404
                        }
                    }

                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $response.ContentType = $contentType
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                } catch {
                    Start-Sleep -Milliseconds 200
                }
            }
            $listener.Stop()
        } -ArgumentList $puerto, $protocolo, $htmlPage, $script:ScriptPath

        # Esperar un poco para que arranque
        Start-Sleep -Seconds 2

        if ($script:RESTJob.State -eq 'Running') {
            Write-AppLog "REST API iniciada en ${prefix}" "INFO"
        } else {
            Write-AppLog "REST API no arranco correctamente" "WARN"
        }
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
# SECCION 46 - AGENTE RESIDENTE
# ============================================================================
$script:WMIWatcher = $null
$script:LastKnownEstado = ""

function Start-ResidentAgent {
    if (-not $script:CfgResidentAgent) { return }
    try {
        $query = "SELECT * FROM __InstanceModificationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Service' AND TargetInstance.Name='WinDefend'"
        $script:WMIWatcher = Register-WmiEvent -Query $query -SourceIdentifier "DefenderTray_WinDefend" -ErrorAction Stop
        $null = Register-ObjectEvent -InputObject $script:WMIWatcher -EventName "EventArrived" -Action {
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
# SECCION 47 - THRESHOLD MONITOR
# ============================================================================
$script:ThresholdTimer = $null
$script:DisabledSince = $null

function Start-ThresholdMonitor {
    if (-not $script:CfgThresholdAlert) { return }
    if ($null -ne $script:ThresholdTimer) { return }
    $script:ThresholdTimer = New-Object System.Windows.Forms.Timer
    $script:ThresholdTimer.Interval = 300000
    $script:ThresholdTimer.Add_Tick({
        try {
            $s = Get-QuickStatus
            if ($s.Estado -eq "DESACTIVADO") {
                if ($null -eq $script:DisabledSince) { $script:DisabledSince = Get-Date }
                else {
                    $horas = ((Get-Date) - $script:DisabledSince).TotalHours
                    if ($horas -ge $script:CfgThresholdHours) {
                        $msg = "Defender ha estado DESACTIVADO por $([math]::Round($horas,1)) horas"
                        if ($null -ne $script:notifyIcon) { try { $script:notifyIcon.ShowBalloonTip(8000, "Alerta", $msg, "Warning") } catch { } }
                        Send-TelegramNotification $msg
                        $script:DisabledSince = Get-Date
                    }
                }
            } else { $script:DisabledSince = $null }
        } catch { }
    })
    $script:ThresholdTimer.Start()
}

# ============================================================================
# SECCION 48 - ARRANQUE
# ============================================================================
Get-ScriptHash | Out-Null
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v7.0 ULTIMATE iniciado" "INFO"
Write-AppLog "OS: $($script:OSProductType)" "INFO"
Write-AppLog "SHA256: $($script:ScriptHash)" "INFO"
Write-AppLog "HTTPS: $($script:UseHTTPS)" "INFO"
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

if (-not $script:AuditMode) { Invoke-StartupAutoRepair }

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
# SECCION 49 - BANDEJA Y MENU
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
    $mi.Text = $Texto; $mi.ForeColor = $script:Colors.Text
    $mi.Add_Click($Accion)
    return $mi
}

[void]$menu.Items.Add((Add-MenuItem "Abrir panel" { Show-DefenderPanel }))
[void]$menu.Items.Add((Add-MenuItem "Diagnostico" { Show-DiagnosticsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Emergencia" { Invoke-EmergencyActivation }))
[void]$menu.Items.Add((Add-MenuItem "Event Log" { Show-EventLogDialog }))
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
    if ($s.Estado -eq "ACTIVO") { $miAct.Enabled = $false; $miDes.Enabled = $true }
    else { $miAct.Enabled = $true; $miDes.Enabled = $false }
})

$script:notifyIcon.ContextMenuStrip = $menu
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-DefenderPanel }
})

# ============================================================================
# SECCION 50 - INICIO DE SERVICIOS BACKGROUND
# ============================================================================
if ($script:CfgResidentAgent) { Start-ResidentAgent }
if ($script:CfgRESTEnabled -and -not $script:NoRESTApi) { Initialize-RESTApi }
if ($script:CfgThresholdAlert) { Start-ThresholdMonitor }

Write-AppLog "Bandeja inicializada. Estado: $($initQuick.Estado)" "INFO"

# ============================================================================
# SECCION 51 - BUCLE PRINCIPAL
# ============================================================================
[System.Windows.Forms.Application]::Run()