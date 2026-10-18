<#
================================================================================
  DefenderTray v8.2 ULTIMATE - Enterprise Security Control
================================================================================
  Novedades v8.2 sobre v8.1:
    1.  UN SOLO CLIC: interruptor unico ACTIVAR/DESACTIVAR en el panel, en el
        menu de bandeja y en la CLI. Sin dialogo de confirmacion y sin dialogo
        modal de resultado: la accion COMPLETA se ejecuta con un unico clic.
    2.  Desactivacion TOTAL, no parcial. Fix critico: en v8.1 TODAS las
        llamadas a Set-MpPreference fallaban en silencio (se pasaba un
        hashtable como parametro posicional y se usaba -Force, parametro que
        el cmdlet no tiene), asi que las 15+ protecciones nunca se aplicaban.
        Ahora se aplican de verdad con splatting por nombre.
    3.  Activacion TOTAL, no parcial: mismo fix + verificacion con reintentos
        hasta que la Proteccion en tiempo real quede ACTIVADA.
    4.  Tamper Protection ya no aborta la desactivacion: se intenta bajar por
        registro y, si Windows lo impide, se aplica todo lo persistente y se
        guia con un boton para abrir Seguridad de Windows.
    5.  Estado real: con politicas + servicios deshabilitados se reporta
        DESACTIVADO (con detalle "reinicio pendiente" si hace falta), no
        PARCIAL. PARCIAL queda reservado para estados a medio hacer.
    6.  Politicas completas en ambos sentidos: Network Protection, PUA,
        SmartScreen, Exploit Guard y claves RTP del registro.
    7.  CLI: -action toggle ademas de enable/disable.
    8.  ACTIVAR PROTECCION siempre visible en el panel, incluso en estado
        PARCIAL; llama directamente a Enable-Defender y actualiza el estado.
  Conserva TODAS las funciones de la v8.1 (SQLite cifrado, MSI con WiX, FCM,
  Fleet, ML, Active Directory, GraphQL, PWA, kiosco biometrico, webhooks,
  Excel/CSV, SSE, auto-update, Docker, etc.).
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
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

# ============================================================================
# SECCION 2 - ARGUMENTOS Y RUTAS
# ============================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")
$script:AuditMode    = ($args -contains "-audit")
$script:NoRESTApi    = ($args -contains "-norest")
$script:UseHTTPS     = ($args -contains "-https")
$script:UseHTTP      = -not $script:UseHTTPS
$script:AutoUpdate   = ($args -contains "-autoupdate")

$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

# ============================================================================
# SECCION 2b - AUTO-ELEVACION A ADMINISTRADOR (obligatoria)
# ============================================================================
# DefenderTray manipula Defender, las politicas del registro y los servicios
# del sistema: todo eso exige Administrador. Si el script arranca sin
# permisos, se relanza a si mismo elevado (UAC) y espera al proceso elevado
# para devolver su codigo de salida. Con -noelevate se desactiva este
# comportamiento (pruebas, auditoria o equipos sin UAC).
$script:NoElevate = ($args -contains "-noelevate")
$script:CliArgs   = @($args)

function Test-IsAdministrator {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-PowerShellHostPath {
    # Ruta del ejecutable de PowerShell en curso (pwsh.exe o powershell.exe)
    # para relanzar el script con el mismo motor y la misma version.
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -and (Test-Path -LiteralPath $exe) -and
            ([IO.Path]::GetFileNameWithoutExtension($exe) -in @("pwsh", "powershell"))) {
            return $exe
        }
    } catch { }
    foreach ($candidato in @((Join-Path $PSHOME "pwsh.exe"), (Join-Path $PSHOME "powershell.exe"))) {
        if (Test-Path -LiteralPath $candidato) { return $candidato }
    }
    return "powershell.exe"
}

function Invoke-SelfElevation {
    # Relanza el script actual como Administrador (UAC). Devuelve el codigo de
    # salida del proceso elevado o -1 si el usuario cancela el UAC.
    $exe = Get-PowerShellHostPath
    $linea = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"{0}"' -f $script:ScriptPath))
    foreach ($a in $script:CliArgs) {
        if ($null -eq $a) { continue }
        $linea += $(if ("$a" -match "\s") { '"{0}"' -f $a } else { "$a" })
    }
    $opciones = @{
        FilePath     = $exe
        ArgumentList = $linea
        Verb         = "RunAs"
        PassThru     = $true
        Wait         = $true
        ErrorAction  = "Stop"
    }
    # Si la consola actual esta oculta (acceso directo del MSI, tarea
    # programada, -silent), el proceso elevado tambien se oculta: el
    # DefenderTray es una aplicacion de bandeja y no debe ensuciar el
    # escritorio con una ventana de consola.
    $oculto = $script:SilentMode
    if (-not $oculto) {
        try {
            $cmdPadre = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).CommandLine
            if ($cmdPadre -match "-WindowStyle\s+Hidden") { $oculto = $true }
        } catch { }
    }
    if ($oculto) { $opciones["WindowStyle"] = "Hidden" }
    try {
        $proc = Start-Process @opciones
        try { return $proc.ExitCode } catch { return 0 }
    } catch { return -1 }
}

if (-not $script:NoElevate -and -not (Test-IsAdministrator)) {
    if ($env:DEFENDERTRAY_ELEVATED -eq "1") {
        # El relanzamiento elevado ya se intento: no se repite (evita bucles).
        Write-Warning "DefenderTray necesita Administrador y no se ha podido elevar (UAC)."
    } elseif ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
        Write-Warning "DefenderTray: sin ruta de script no se puede elevar a Administrador."
    } else {
        $env:DEFENDERTRAY_ELEVATED = "1"
        $codigo = Invoke-SelfElevation
        if ($codigo -lt 0) {
            $mensaje = "DefenderTray necesita ejecutarse como Administrador. Acepta el UAC para continuar."
            if ($script:SilentMode) {
                Write-Error $mensaje
            } else {
                try { [System.Windows.Forms.MessageBox]::Show($mensaje, "DefenderTray", "OK", "Warning") | Out-Null }
                catch { Write-Error $mensaje }
            }
            exit 1
        }
        exit $codigo
    }
}

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
$script:LibDir       = Join-Path $script:ConfigDir "lib"
$script:LogFile      = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ConfigFile   = Join-Path $script:ConfigDir "config.dat"
$script:HistoryFile  = Join-Path $script:ConfigDir "historial.json"
$script:AuditFile    = Join-Path $script:AuditFolder ("audit_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:ProfilesFile = Join-Path $script:ProfilesDir "profiles.json"

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir, $script:RegBackupDir,
                 $script:AuditFolder, $script:ForensicDir, $script:ProfilesDir, $script:LibDir)) {
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
# SECCION 6 - NORMALIZACION DE SALTOS DE LINEA
# ============================================================================
function Normalize-LineEndings {
    param([string]$Texto)
    if ([string]::IsNullOrEmpty($Texto)) { return "" }
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
        Title = "Control de Seguridad v8.2 ULTIMATE"
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
        ToggleDisable  = "UN CLIC - DESACTIVAR COMPLETO"
        ToggleEnable   = "UN CLIC - ACTIVAR COMPLETO"
        ToggleFinishOff = "UN CLIC - TERMINAR DE DESACTIVAR"
        ToggleFinishOn  = "UN CLIC - TERMINAR DE ACTIVAR"
    }
    EN = @{
        Title = "Security Control v8.2 ULTIMATE"
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
        ToggleDisable  = "ONE CLICK - FULL DISABLE"
        ToggleEnable   = "ONE CLICK - FULL ENABLE"
        ToggleFinishOff = "ONE CLICK - FINISH DISABLING"
        ToggleFinishOn  = "ONE CLICK - FINISH ENABLING"
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
$script:CfgDarkTheme       = $true
$script:CfgKioskMode       = $false
$script:CfgKioskHash       = ""
$script:CfgUninstallHash   = ""
$script:CfgFirstRunDone    = $false
$script:CfgLang            = "ES"
$script:CfgAutoRepair      = $true
$script:CfgAutoCleanup     = $true
$script:CfgThemeFollow     = $true
$script:CfgThresholdHours  = 6
$script:CfgThresholdAlert  = $true
$script:CfgEmailEnabled    = $false
$script:CfgEmailServer     = ""
$script:CfgEmailPort       = 587
$script:CfgEmailUser       = ""
$script:CfgEmailPwd        = ""
$script:CfgEmailTo         = ""
$script:CfgRESTEnabled     = $true
$script:CfgRESTPort        = 9182
$script:CfgResidentAgent   = $true
$script:CfgTelegramEnabled = $false
$script:CfgTelegramToken   = ""
$script:CfgTelegramChatId  = ""
$script:CfgMultiMonitor    = $true
$script:CfgForensicMode    = $false
$script:CfgParentalMode    = $false
$script:CfgCloudBackup     = $false
$script:CfgCloudPath       = ""
# --- v8.1 ---
$script:CfgSignReports     = $false
$script:CfgBiometricKiosk  = $false
$script:CfgFCMEnabled      = $false
$script:CfgFCMProjectId    = ""
$script:CfgFCMServiceJson  = ""
$script:CfgFCMToken        = ""
$script:CfgAnomalyEnabled  = $true
$script:CfgAnomalyZ        = 3.0
$script:CfgGitHubRepo      = "usuario/DefenderTray"
$script:CfgCustomTheme     = @{
    Bg = "#0A0E1A"
    CardBg = "#182034"
    AccentGreen = "#00C86C"
    AccentRed = "#FF3366"
    AccentAmber = "#FFAA00"
    AccentCyan = "#00E5FF"
    AccentPurple = "#B14EFF"
    AccentBlue = "#008CFF"
}

$script:DarkTheme          = $true
$script:IsKioskMode        = $false
$script:ScriptHash         = ""
$script:OSProductType      = Get-OSProductType
$script:EmergencyHotkeyId  = 1

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
                    "DarkTheme"       { $script:CfgDarkTheme = [bool]$prop.Value }
                    "KioskMode"       { $script:CfgKioskMode = [bool]$prop.Value }
                    "KioskHash"       { $script:CfgKioskHash = [string]$prop.Value }
                    "FirstRunDone"    { $script:CfgFirstRunDone = [bool]$prop.Value }
                    "Lang"            { $script:CfgLang = [string]$prop.Value }
                    "AutoRepair"      { $script:CfgAutoRepair = [bool]$prop.Value }
                    "AutoCleanup"     { $script:CfgAutoCleanup = [bool]$prop.Value }
                    "ThemeFollow"     { $script:CfgThemeFollow = [bool]$prop.Value }
                    "ThresholdHours"  { $script:CfgThresholdHours = [int]$prop.Value }
                    "ThresholdAlert"  { $script:CfgThresholdAlert = [bool]$prop.Value }
                    "EmailEnabled"    { $script:CfgEmailEnabled = [bool]$prop.Value }
                    "EmailServer"     { $script:CfgEmailServer = [string]$prop.Value }
                    "EmailPort"       { $script:CfgEmailPort = [int]$prop.Value }
                    "EmailUser"       { $script:CfgEmailUser = [string]$prop.Value }
                    "EmailPwd"        { $script:CfgEmailPwd = Unprotect-String $prop.Value }
                    "EmailTo"         { $script:CfgEmailTo = [string]$prop.Value }
                    "RESTEnabled"     { $script:CfgRESTEnabled = [bool]$prop.Value }
                    "RESTPort"        { $script:CfgRESTPort = [int]$prop.Value }
                    "ResidentAgent"   { $script:CfgResidentAgent = [bool]$prop.Value }
                    "TelegramEnabled" { $script:CfgTelegramEnabled = [bool]$prop.Value }
                    "TelegramToken"   { $script:CfgTelegramToken = [string]$prop.Value }
                    "TelegramChatId"  { $script:CfgTelegramChatId = [string]$prop.Value }
                    "MultiMonitor"    { $script:CfgMultiMonitor = [bool]$prop.Value }
                    "ForensicMode"    { $script:CfgForensicMode = [bool]$prop.Value }
                    "ParentalMode"    { $script:CfgParentalMode = [bool]$prop.Value }
                    "CloudBackup"     { $script:CfgCloudBackup = [bool]$prop.Value }
                    "CloudPath"       { $script:CfgCloudPath = [string]$prop.Value }
                    # v8
                    "SignReports"     { $script:CfgSignReports = [bool]$prop.Value }
                    "BiometricKiosk"  { $script:CfgBiometricKiosk = [bool]$prop.Value }
                    "FCMEnabled"      { $script:CfgFCMEnabled = [bool]$prop.Value }
                    "FCMProjectId"    { $script:CfgFCMProjectId = [string]$prop.Value }
                    "FCMServiceJson"  { $script:CfgFCMServiceJson = [string]$prop.Value }
                    "FCMToken"        { $script:CfgFCMToken = [string]$prop.Value }
                    "AnomalyEnabled"  { $script:CfgAnomalyEnabled = [bool]$prop.Value }
                    "AnomalyZ"        { $script:CfgAnomalyZ = [double]$prop.Value }
                    "GitHubRepo"      { $script:CfgGitHubRepo = [string]$prop.Value }
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
            DarkTheme       = $script:DarkTheme
            KioskMode       = $script:IsKioskMode
            KioskHash       = $script:CfgKioskHash
            FirstRunDone    = $script:CfgFirstRunDone
            Lang            = $script:Lang
            AutoRepair      = $script:CfgAutoRepair
            AutoCleanup     = $script:CfgAutoCleanup
            ThemeFollow     = $script:CfgThemeFollow
            ThresholdHours  = $script:CfgThresholdHours
            ThresholdAlert  = $script:CfgThresholdAlert
            EmailEnabled    = $script:CfgEmailEnabled
            EmailServer     = $script:CfgEmailServer
            EmailPort       = $script:CfgEmailPort
            EmailUser       = $script:CfgEmailUser
            EmailPwd        = (Protect-String $script:CfgEmailPwd)
            EmailTo         = $script:CfgEmailTo
            RESTEnabled     = $script:CfgRESTEnabled
            RESTPort        = $script:CfgRESTPort
            ResidentAgent   = $script:CfgResidentAgent
            TelegramEnabled = $script:CfgTelegramEnabled
            TelegramToken   = $script:CfgTelegramToken
            TelegramChatId  = $script:CfgTelegramChatId
            MultiMonitor    = $script:CfgMultiMonitor
            ForensicMode    = $script:CfgForensicMode
            ParentalMode    = $script:CfgParentalMode
            CloudBackup     = $script:CfgCloudBackup
            CloudPath       = $script:CfgCloudPath
            SignReports     = $script:CfgSignReports
            BiometricKiosk  = $script:CfgBiometricKiosk
            FCMEnabled      = $script:CfgFCMEnabled
            FCMProjectId    = $script:CfgFCMProjectId
            FCMServiceJson  = $script:CfgFCMServiceJson
            FCMToken        = $script:CfgFCMToken
            AnomalyEnabled  = $script:CfgAnomalyEnabled
            AnomalyZ        = $script:CfgAnomalyZ
            GitHubRepo      = $script:CfgGitHubRepo
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
# SECCION 12 - SHA256 Y HASH
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

function Get-StringHash {
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
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
    # Misma comprobacion que usa la auto-elevacion (SECCION 2b).
    return (Test-IsAdministrator)
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

function Test-DefenderServicesDisabled {
    # v8.2: los tres servicios clave deben quedar con Start=Disabled (Start=4).
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        if ((Get-ServiceStartMode -Name $s) -ne "Disabled") { return $false }
    }
    return $true
}

function Get-QuickStatus {
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $running = ($null -ne $svc) -and ($svc.Status -eq 'Running')
    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $engineRunning = ($null -ne $proc)
    $rtpDisabled = Test-RTPDisabled
    $hasPolicy = Test-DefenderPolicyDisabled
    $servicesDisabled = Test-DefenderServicesDisabled
    $isActive = $running -and $engineRunning -and (-not $rtpDisabled) -and (-not $hasPolicy)
    $isFullyDisabled = (-not $running) -and (-not $engineRunning)
    # v8.2: politicas + servicios deshabilitados = DESACTIVADO real (Windows lo
    # hace efectivo en el arranque). Ya no se reporta como PARCIAL.
    $isDisabledCommitted = $hasPolicy -and $servicesDisabled
    $estado = "PARCIAL"
    if ($isActive) { $estado = "ACTIVO" }
    elseif ($isFullyDisabled -or $isDisabledCommitted) { $estado = "DESACTIVADO" }
    return [PSCustomObject]@{
        ServiceRunning = $running
        EngineRunning = $engineRunning
        RealTimeProtectionEnabled = -not $rtpDisabled
        HasPolicy = $hasPolicy
        ServicesDisabled = $servicesDisabled
        IsActive = $isActive
        IsFullyDisabled = $isFullyDisabled
        PendingReboot = (($estado -eq "DESACTIVADO") -and (-not $isFullyDisabled))
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
# SECCION 16 - v8.1: SQLITE REAL CON CIFRADO
# ============================================================================
$script:SqliteOk = $false
$script:SqliteConn = $null
$script:SqliteDll = $null

function Initialize-Sqlite {
    if ($script:SqliteOk) { return $true }
    $dllPath = Join-Path $script:LibDir "System.Data.SQLite.dll"
    $interopPath = Join-Path $script:LibDir "SQLite.Interop.dll"

    if (-not (Test-Path $dllPath)) {
        try {
            Write-AppLog "Descargando System.Data.SQLite..." "INFO"
            $zip = Join-Path $env:TEMP "sqlite_pkg.zip"
            $ver = "1.0.118.1"
            $url = "https://www.nuget.org/api/v2/package/System.Data.SQLite.Core/$ver"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
            $extract = Join-Path $env:TEMP "sqlite_extract"
            if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)

            $arch = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
            $dllSrc = Join-Path $extract "lib\net46\System.Data.SQLite.dll"
            if (-not (Test-Path $dllSrc)) { $dllSrc = Join-Path $extract "lib\net40\System.Data.SQLite.dll" }
            if (Test-Path $dllSrc) { Copy-Item $dllSrc $dllPath -Force }

            $interopCandidates = Get-ChildItem -Path $extract -Filter "SQLite.Interop.dll" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\$arch\\" }
            if ($interopCandidates) { Copy-Item $interopCandidates[0].FullName $interopPath -Force }
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-AppLog "SQLite auto-install fallo: $($_.Exception.Message)" "WARN"
            return $false
        }
    }

    try {
        Add-Type -Path $dllPath
        $script:SqliteDll = $dllPath
        $script:SqliteOk = $true
        return $true
    } catch {
        Write-AppLog "No se pudo cargar SQLite: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Open-SqliteDB {
    param([string]$DbName = "defendertray.db")
    if (-not (Initialize-Sqlite)) { return $null }
    try {
        if ($null -ne $script:SqliteConn) {
            try { $script:SqliteConn.Close() } catch { }
        }
        $dbPath = Join-Path $script:ConfigDir $DbName
        $pwd = Protect-String "DTv8_MasterKey_$env:COMPUTERNAME"
        if ([string]::IsNullOrEmpty($pwd)) { $pwd = "DTv8_DefaultKey" }
        $csb = New-Object System.Data.SQLite.SQLiteConnectionStringBuilder
        $csb.DataSource = $dbPath
        $csb.Password   = $pwd
        $csb.ForeignKeys = $true
        $csb.JournalMode = "WAL"
        $csb.SyncMode    = "Normal"
        $conn = New-Object System.Data.SQLite.SQLiteConnection($csb.ToString())
        $conn.Open()
        $script:SqliteConn = $conn

        $schema = @"
CREATE TABLE IF NOT EXISTS Usuarios (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre TEXT NOT NULL UNIQUE,
    Hash TEXT NOT NULL,
    Rol TEXT NOT NULL DEFAULT 'user',
    Activo INTEGER NOT NULL DEFAULT 1,
    Creado TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS Historial (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Fecha TEXT NOT NULL,
    Usuario TEXT,
    Equipo TEXT,
    Accion TEXT NOT NULL,
    Resultado TEXT,
    Segundos REAL DEFAULT 0,
    Detalle TEXT
);
CREATE TABLE IF NOT EXISTS Eventos (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Fecha TEXT NOT NULL,
    Equipo TEXT NOT NULL,
    Severidad TEXT NOT NULL,
    Categoria TEXT,
    Mensaje TEXT
);
CREATE TABLE IF NOT EXISTS Metricas (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Fecha TEXT NOT NULL,
    Equipo TEXT NOT NULL,
    Metrica TEXT NOT NULL,
    Valor REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS Equipos (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre TEXT NOT NULL UNIQUE,
    IP TEXT,
    Version TEXT,
    UltimoContacto TEXT,
    Estado TEXT,
    Notas TEXT,
    FCMToken TEXT
);
CREATE TABLE IF NOT EXISTS Webhooks (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Url TEXT NOT NULL,
    Eventos TEXT NOT NULL,
    Activo INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS Baselines (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Metrica TEXT NOT NULL,
    Media REAL NOT NULL,
    StdDev REAL NOT NULL,
    Muestras INTEGER NOT NULL,
    Actualizado TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS IX_Hist_Fecha ON Historial(Fecha);
CREATE INDEX IF NOT EXISTS IX_Event_Fecha ON Eventos(Fecha);
CREATE INDEX IF NOT EXISTS IX_Metric_Fecha ON Metricas(Fecha);
"@
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $schema
        [void]$cmd.ExecuteNonQuery()
        $cmd.Dispose()
        Write-AppLog "SQLite abierto: $dbPath" "INFO"
        return $conn
    } catch {
        Write-AppLog "Error abriendo SQLite: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Invoke-Sqlite {
    param([string]$Sql, [hashtable]$Params = @{})
    if (-not $script:SqliteOk -or $null -eq $script:SqliteConn) { return $null }
    try {
        $cmd = $script:SqliteConn.CreateCommand()
        $cmd.CommandText = $Sql
        foreach ($k in $Params.Keys) {
            $p = $cmd.CreateParameter()
            $p.ParameterName = $k
            if ($null -eq $Params[$k]) { $p.Value = [DBNull]::Value } else { $p.Value = $Params[$k] }
            [void]$cmd.Parameters.Add($p)
        }
        if ($Sql -match "^\s*(SELECT|WITH)" ) {
            $reader = $cmd.ExecuteReader()
            $rows = New-Object System.Collections.ArrayList
            while ($reader.Read()) {
                $row = @{}
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $val = $reader.GetValue($i)
                    if ($val -is [DBNull]) { $val = $null }
                    $row[$reader.GetName($i)] = $val
                }
                [void]$rows.Add([PSCustomObject]$row)
            }
            $reader.Close()
            $cmd.Dispose()
            return $rows
        } else {
            $affected = $cmd.ExecuteNonQuery()
            $cmd.Dispose()
            return $affected
        }
    } catch {
        Write-AppLog "SQLite error: $($_.Exception.Message) | SQL: $Sql" "WARN"
        return $null
    }
}

function Close-SqliteDB {
    try { if ($null -ne $script:SqliteConn) { $script:SqliteConn.Close(); $script:SqliteConn.Dispose(); $script:SqliteConn = $null } } catch { }
}

# ============================================================================
# SECCION 17 - v8.1: FIRMA DIGITAL AUTHENTICODE + GUIA EV
# ============================================================================
function Get-CodeSigningCert {
    param([string]$Thumbprint = "")
    try {
        if ($Thumbprint) {
            return Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
        }
        $certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
            Where-Object { $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey }
        return ($certs | Sort-Object NotAfter -Descending | Select-Object -First 1)
    } catch { return $null }
}

function Sign-FileAuthenticode {
    param([string]$Path, [string]$CertThumbprint = "", [string]$TimestampUrl = "http://timestamp.digicert.com")
    try {
        if (-not (Test-Path $Path)) { return $false }
        $cert = Get-CodeSigningCert -Thumbprint $CertThumbprint
        if ($null -eq $cert) {
            Write-AppLog "Sin certificado de firma disponible" "WARN"
            return $false
        }
        $sig = Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -TimestampServer $TimestampUrl -HashAlgorithm SHA256 -ErrorAction Stop
        Write-AppLog "Firmado: $Path | Status: $($sig.Status) | Thumbprint: $($cert.Thumbprint)" "INFO"
        return ($sig.Status -eq "Valid" -or $sig.Status -eq "UnknownError")
    } catch {
        Write-AppLog "Error firmando $Path : $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Sign-Report {
    param([string]$Path)
    if (-not $script:CfgSignReports) { return }
    $null = Sign-FileAuthenticode -Path $Path
}

function Get-EVStatus {
    $result = @{ EVDetectado = $false; Detalles = "Sin EV" }
    try {
        $certs = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue
        foreach ($c in $certs) {
            $ku = $c.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
            if ($ku -and $ku.Format($true) -match "1\.3\.6\.1\.4\.1\.311\.10\.3\.13") {
                $result.EVDetectado = $true
                $result.Detalles = "EV: $($c.Subject) expira $($c.NotAfter)"
                break
            }
        }
    } catch { }
    return $result
}

function Show-CertificateGuide {
    $msg = @"
GUIA DE FIRMA DIGITAL - DefenderTray v8.2
==========================================

1. FIRMA DE DESARROLLO (gratis - solo confianza local)
   New-SelfSignedCertificate -Type CodeSigningCert `
     -Subject "CN=DefenderTray Dev" `
     -KeyUsage DigitalSignature `
     -CertStoreLocation Cert:\CurrentUser\My `
     -NotAfter (Get-Date).AddYears(3)

   Luego:
   Set-AuthenticodeSignature -FilePath .\DefenderTray_8.2.ps1 `
     -Certificate (Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert)[0]

2. FIRMA EV (reconocida por Windows SmartScreen)
   a) Comprar cert EV Code Signing en DigiCert / Sectigo / GlobalSign (~`$300-500/anio)
   b) Recibes un token USB (SafeNet eToken) con el certificado
   c) Instalas SafeNet Authentication Client + driver del token
   d) El certificado aparece en Cert:\CurrentUser\My con EKU 1.3.6.1.4.1.311.10.3.13
   e) Firma con Set-AuthenticodeSignature (timestamp obligatorio)

3. VERIFICAR FIRMA
   Get-AuthenticodeSignature -FilePath .\DefenderTray_8.2.ps1 | Format-List

4. CONFIGURAR EN ESTE SCRIPT
   Settings -> "Firmar reportes con Authenticode" [x]
"@
    Show-ResultDialog -Titulo "Guia de Firma Digital" -Mensaje (Normalize-LineEndings $msg) -Tipo "Info"
}

# ============================================================================
# SECCION 18 - v8.1: MSI CON WIX TOOLSET
# ============================================================================
function Get-WixToolPath {
    # Devuelve la ruta de candle.exe / light.exe. Primero mira en el PATH y
    # luego en las instalaciones habituales de WiX Toolset v3 (por ejemplo
    # "C:\Program Files (x86)\WiX Toolset v3.11\bin"), anadiendo el directorio
    # al PATH de la sesion para poder invocarlos por su nombre.
    param([Parameter(Mandatory = $true)][string]$Ejecutable)

    $enPath = Get-Command $Ejecutable -ErrorAction SilentlyContinue
    if ($enPath) { return $enPath.Source }

    $candidatos = New-Object System.Collections.ArrayList
    [void]$candidatos.Add("C:\Program Files (x86)\WiX Toolset v3.11\bin")
    [void]$candidatos.Add("C:\Program Files\WiX Toolset v3.11\bin")
    foreach ($base in @("C:\Program Files (x86)", "C:\Program Files")) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem -Path $base -Directory -Filter "WiX Toolset v*" -ErrorAction SilentlyContinue |
            Sort-Object -Property Name -Descending |
            ForEach-Object { [void]$candidatos.Add((Join-Path $_.FullName "bin")) }
    }

    foreach ($dir in $candidatos) {
        $exe = Join-Path $dir $Ejecutable
        if (Test-Path -LiteralPath $exe) {
            if (($env:PATH -split ";") -notcontains $dir) { $env:PATH = "$dir;$env:PATH" }
            return $exe
        }
    }
    return $null
}

function New-WixInstallerPackage {
    param([string]$OutputDir = "$env:USERPROFILE\Desktop\DefenderTray_v8_MSI")
    try {
        if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
        $scriptCopy = Join-Path $OutputDir "DefenderTray_8.2.ps1"
        Copy-Item -Path $script:ScriptPath -Destination $scriptCopy -Force

        $wxs = @'
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Instalador de DefenderTray 8.2 (WiX Toolset v3, x64, instalacion por maquina).

  Los tres puntos que hacen que compile sin los errores ICE de siempre:
    * Platform="x64" y Win64="yes" -> el paquete y sus componentes son de
      64 bits (ICE80: "This 32BitComponent ... uses 64BitDirectory ...").
    * El componente del acceso directo vive dentro de ProgramMenuDir y su
      RemoveFolder declara el directorio -> la carpeta queda en la tabla
      RemoveFile (ICE64: "The directory ProgramMenuDir is in the user profile
      but is not listed in the RemoveFile table").
    * La clave de registro es HKLM -> el componente es por maquina y el menu
      Inicio es el de todos los usuarios, no el del perfil del usuario.
-->
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="DefenderTray Ultimate" Language="1033"
           Version="8.2.0.0" Manufacturer="Ing. Yosvany Hernandez Quintero"
           UpgradeCode="A1B2C3D4-E5F6-7890-ABCD-EF1234567890">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" Platform="x64"/>
    <MajorUpgrade DowngradeErrorMessage="Ya existe una version instalada."/>
    <MediaTemplate EmbedCab="yes"/>
    <Condition Message="DefenderTray necesita Windows de 64 bits (x64).">VersionNT64</Condition>
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="DefenderTray">
          <Component Id="MainScript" Guid="*" Win64="yes">
            <File Id="ScriptPs1" Source="DefenderTray_8.2.ps1" KeyPath="yes"/>
          </Component>
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder" Name="Programs">
        <Directory Id="ProgramMenuDir" Name="DefenderTray">
          <Component Id="StartMenuShortcut" Guid="*" Win64="yes">
            <Shortcut Id="AppShortcut" Directory="ProgramMenuDir"
                      Name="DefenderTray v8.2"
                      Target="[System64Folder]WindowsPowerShell\v1.0\powershell.exe"
                      Arguments="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;[INSTALLFOLDER]DefenderTray_8.2.ps1&quot;"
                      WorkingDirectory="INSTALLFOLDER"/>
            <RemoveFolder Id="ProgramMenuDir" Directory="ProgramMenuDir" On="uninstall"/>
            <RegistryValue Root="HKLM" Key="Software\DefenderTray" Name="installed" Type="integer" Value="1" KeyPath="yes"/>
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="MainFeature" Title="DefenderTray v8.2" Level="1">
      <ComponentRef Id="MainScript"/>
      <ComponentRef Id="StartMenuShortcut"/>
    </Feature>
    <UIRef Id="WixUI_Minimal"/>
    <WixVariable Id="WixUILicenseRtf" Value="License.rtf"/>
  </Product>
</Wix>
'@
        Set-Content -Path (Join-Path $OutputDir "DefenderTray.wxs") -Value $wxs -Encoding UTF8 -Force

        $licenseRtf = @'
{\rtf1\ansi\deff0
{\fonttbl{\f0 Segoe UI;}}
\f0\fs20
{\b DefenderTray v8.2 - Licencia de uso}\par
\par
Software de administracion de seguridad. Uso bajo responsabilidad del operador.\par
Autor: Ing. Yosvany Hernandez Quintero\par
Movil: +53 5 2160801 / +53 5 9860911\par
}
'@
        Set-Content -Path (Join-Path $OutputDir "License.rtf") -Value $licenseRtf -Encoding ASCII -Force

        $candle = Get-WixToolPath -Ejecutable "candle.exe"
        $light  = Get-WixToolPath -Ejecutable "light.exe"
        $msiPath = Join-Path $OutputDir "DefenderTray_v8.2.msi"

        if ($candle -and $light) {
            Push-Location $OutputDir
            try {
                $null = & $candle -nologo -arch x64 -ext WixUIExtension DefenderTray.wxs 2>&1
                if (Test-Path "DefenderTray.wixobj") {
                    $null = & $light -nologo -ext WixUIExtension -o "DefenderTray_v8.2.msi" DefenderTray.wixobj 2>&1
                }
            } finally { Pop-Location }
            if (Test-Path $msiPath) { return "MSI generado: $msiPath" }
        }

        return @"
Paquete preparado en: $OutputDir

Archivos generados:
  - DefenderTray_8.2.ps1  (script)
  - DefenderTray.wxs      (definicion WiX)
  - License.rtf           (EULA)

Para generar el MSI:
  1. Instala WiX Toolset v3.11: https://wixtoolset.org/releases/
  2. Anade al PATH de Windows: C:\Program Files (x86)\WiX Toolset v3.11\bin
     (o ejecuta .\Add-WiXToPath.ps1 -Scope Machine como Administrador)
  3. Ejecuta de nuevo esta opcion, o manualmente:
     cd "$OutputDir"
     candle.exe -nologo -arch x64 -ext WixUIExtension DefenderTray.wxs
     light.exe  -nologo -ext WixUIExtension -o DefenderTray_v8.2.msi DefenderTray.wixobj
"@
    } catch { return "Error: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 19 - v8.1: NOTIFICACIONES PUSH FIREBASE (FCM v1)
# ============================================================================
function Get-GoogleAccessToken {
    param([string]$ServiceAccountJsonPath)
    try {
        if (-not (Test-Path $ServiceAccountJsonPath)) { return $null }
        $sa = Get-Content $ServiceAccountJsonPath -Raw | ConvertFrom-Json
        $now = [int][double]::Parse((Get-Date -UFormat %s))
        $header = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
        $claim = @{
            iss = $sa.client_email
            scope = "https://www.googleapis.com/auth/firebase.messaging"
            aud = "https://oauth2.googleapis.com/token"
            iat = $now
            exp = $now + 3600
        } | ConvertTo-Json -Compress

        $b64url = { param($s) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)).TrimEnd('=').Replace('+','-').Replace('/','_') }
        $signingInput = (& $b64url $header) + "." + (& $b64url $claim)

        $pem = $sa.private_key
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $pemLines = $pem -split "`n" | Where-Object { $_ -notmatch "-----" -and $_.Trim() -ne "" }
        $keyBytes = [Convert]::FromBase64String(($pemLines -join ""))
        try {
            $rsa.ImportRSAPrivateKey($keyBytes, [ref]0) 2>$null
        } catch {
            $rsa.ImportCspBlob($keyBytes)
        }
        $sigBytes = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signingInput), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $sigB64 = [Convert]::ToBase64String($sigBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
        $jwt = $signingInput + "." + $sigB64

        $body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt"
        $resp = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post `
            -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 15
        return $resp.access_token
    } catch {
        Write-AppLog "FCM OAuth error: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Send-FCMPush {
    param([string]$Titulo, [string]$Cuerpo, [hashtable]$Data = @{})
    if (-not $script:CfgFCMEnabled) { return $false }
    if ([string]::IsNullOrEmpty($script:CfgFCMProjectId) -or [string]::IsNullOrEmpty($script:CfgFCMServiceJson)) {
        Write-AppLog "FCM: falta config" "WARN"
        return $false
    }
    try {
        $token = Get-GoogleAccessToken -ServiceAccountJsonPath $script:CfgFCMServiceJson
        if (-not $token) { return $false }
        $tokens = @()
        if ($script:CfgFCMToken) { $tokens += $script:CfgFCMToken }
        if ($script:SqliteOk) {
            $rows = Invoke-Sqlite "SELECT FCMToken FROM Equipos WHERE FCMToken IS NOT NULL AND FCMToken <> ''" 2>$null
            if ($rows) { foreach ($r in $rows) { if ($r.FCMToken) { $tokens += $r.FCMToken } } }
        }
        $url = "https://fcm.googleapis.com/v1/projects/$($script:CfgFCMProjectId)/messages:send"
        $ok = $false
        foreach ($tk in ($tokens | Select-Object -Unique)) {
            if ([string]::IsNullOrEmpty($tk)) { continue }
            $msg = @{
                message = @{
                    token = $tk
                    notification = @{ title = $Titulo; body = $Cuerpo }
                    data = $Data
                    android = @{ priority = "high" }
                    apns = @{ payload = @{ aps = @{ "content-available" = 1; alert = @{ title = $Titulo; body = $Cuerpo } } } }
                }
            } | ConvertTo-Json -Depth 10 -Compress
            try {
                $null = Invoke-RestMethod -Uri $url -Method Post -Headers @{ Authorization = "Bearer $token" } `
                    -Body $msg -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                $ok = $true
            } catch { Write-AppLog "FCM send error: $($_.Exception.Message)" "WARN" }
        }
        return $ok
    } catch {
        Write-AppLog "FCM error: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# ============================================================================
# SECCION 20 - v8.1: FLEET (MULTI-EQUIPO)
# ============================================================================
function Register-FleetComputer {
    if (-not $script:SqliteOk) { return }
    $ip = ""
    try { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress } catch { }
    $estado = (Get-QuickStatus).Estado
    $null = Invoke-Sqlite @"
INSERT INTO Equipos (Nombre, IP, Version, UltimoContacto, Estado)
VALUES (@n, @ip, '8.2', @t, @e)
ON CONFLICT(Nombre) DO UPDATE SET IP=@ip, UltimoContacto=@t, Estado=@e
"@ @{ n = $env:COMPUTERNAME; ip = $ip; t = (Get-Date).ToString("s"); e = $estado }
}

function Get-FleetComputers {
    if (-not $script:SqliteOk) { return @() }
    return (Invoke-Sqlite "SELECT * FROM Equipos ORDER BY UltimoContacto DESC")
}

function Get-FleetHtmlConsole {
    return @'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>DefenderTray Fleet Console</title>
<style>*{box-sizing:border-box}body{font-family:'Segoe UI',sans-serif;background:#070B14;color:#E0E6F0;margin:0;padding:0}
.header{background:linear-gradient(90deg,#0A1628,#0A1E3A);padding:18px 30px;border-bottom:2px solid #00E5FF}
.header h1{margin:0;color:#00E5FF;font-size:22px}.header .sub{color:#6B7A99;font-size:11px;margin-top:3px}
.container{padding:20px 30px}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:16px;margin-bottom:24px}
.stat{background:#101928;border:1px solid #1E2D4A;border-radius:10px;padding:16px}
.stat .lbl{color:#6B7A99;font-size:11px;text-transform:uppercase;letter-spacing:1px}
.stat .val{font-size:32px;font-weight:bold;color:#00E5FF;margin-top:6px}
.stat.ok .val{color:#00E56C}.stat.warn .val{color:#FFAA00}.stat.bad .val{color:#FF3366}
table{width:100%;border-collapse:collapse;background:#101928;border-radius:10px;overflow:hidden}
th,td{padding:12px 16px;text-align:left;border-bottom:1px solid #1E2D4A}
th{background:#0A1424;color:#00E5FF;font-size:11px;text-transform:uppercase;letter-spacing:1px}
td{font-size:13px}tr:hover td{background:#0A1628}
.badge{padding:3px 10px;border-radius:12px;font-size:11px;font-weight:bold}
.badge.active{background:#00E56C;color:#000}.badge.disabled{background:#FF3366;color:#fff}.badge.partial{background:#FFAA00;color:#000}
.toolbar{display:flex;gap:10px;margin-bottom:16px}.btn{padding:10px 18px;border-radius:6px;border:none;color:#fff;font-weight:bold;cursor:pointer;font-size:12px}
.btn-blue{background:#008CFF}.btn-green{background:#00C86C}.btn-red{background:#FF3366}
</style></head><body>
<div class="header"><h1>DefenderTray Fleet Console</h1><div class="sub">Panel multi-equipo — v8.2</div></div>
<div class="container">
<div class="stats">
<div class="stat ok"><div class="lbl">Activos</div><div class="val" id="sActivos">—</div></div>
<div class="stat warn"><div class="lbl">Parciales</div><div class="val" id="sParciales">—</div></div>
<div class="stat bad"><div class="lbl">Desactivados</div><div class="val" id="sDesactivados">—</div></div>
<div class="stat"><div class="lbl">Total</div><div class="val" id="sTotal">—</div></div>
</div>
<div class="toolbar">
<button class="btn btn-blue" onclick="refresh()">Refrescar</button>
<button class="btn btn-green" onclick="broadcast('enable')">Activar Todos</button>
<button class="btn btn-red" onclick="broadcast('disable')">Desactivar Todos</button>
</div>
<table><thead><tr><th>Equipo</th><th>IP</th><th>Version</th><th>Estado</th><th>Ultimo Contacto</th><th>Acciones</th></tr></thead>
<tbody id="tbody"></tbody></table></div>
<script>
async function refresh(){
 const r=await fetch('/fleet/computers');const j=await r.json();
 const tbody=document.getElementById('tbody');tbody.innerHTML='';
 let a=0,p=0,d=0;
 for(const c of j){
  if(c.Estado==='ACTIVO')a++;else if(c.Estado==='PARCIAL')p++;else if(c.Estado==='DESACTIVADO')d++;
  const cls=c.Estado==='ACTIVO'?'active':c.Estado==='DESACTIVADO'?'disabled':'partial';
  tbody.innerHTML+=`<tr><td><b>${c.Nombre}</b></td><td>${c.IP||'—'}</td><td>${c.Version||'—'}</td>
   <td><span class="badge ${cls}">${c.Estado}</span></td><td>${c.UltimoContacto||'—'}</td>
   <td><button class="btn btn-blue" onclick="cmd('${c.Nombre}','enable')">ON</button>
   <button class="btn btn-red" onclick="cmd('${c.Nombre}','disable')">OFF</button></td></tr>`;
 }
 document.getElementById('sActivos').textContent=a;
 document.getElementById('sParciales').textContent=p;
 document.getElementById('sDesactivados').textContent=d;
 document.getElementById('sTotal').textContent=j.length;
}
async function cmd(host,action){await fetch('/fleet/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({host,action})});refresh();}
async function broadcast(action){if(!confirm('Aplicar '+action+' a TODOS?'))return;await fetch('/fleet/broadcast',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action})});refresh();}
refresh();setInterval(refresh,8000);
</script></body></html>
'@
}

# ============================================================================
# SECCION 21 - v8.1: ML ANOMALIAS (Z-SCORE)
# ============================================================================
$script:AnomalyTimer = $null

function Add-MetricSample {
    param([string]$Metrica, [double]$Valor)
    if (-not $script:SqliteOk) { return }
    $null = Invoke-Sqlite "INSERT INTO Metricas (Fecha,Equipo,Metrica,Valor) VALUES (@f,@e,@m,@v)" @{
        f = (Get-Date).ToString("s"); e = $env:COMPUTERNAME; m = $Metrica; v = $Valor
    }
}

function Get-Baseline {
    param([string]$Metrica)
    if (-not $script:SqliteOk) { return $null }
    $rows = Invoke-Sqlite "SELECT Valor FROM Metricas WHERE Metrica=@m AND Fecha > @c ORDER BY Id DESC LIMIT 200" @{
        m = $Metrica; c = (Get-Date).AddHours(-24).ToString("s")
    }
    if (-not $rows -or $rows.Count -lt 20) { return $null }
    $vals = $rows | ForEach-Object { [double]$_.Valor }
    $mean = ($vals | Measure-Object -Average).Average
    $sumSq = ($vals | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
    $stddev = [Math]::Sqrt($sumSq / $vals.Count)
    return @{ Media = $mean; StdDev = $stddev; Muestras = $vals.Count }
}

function Test-Anomaly {
    param([string]$Metrica, [double]$Valor)
    $base = Get-Baseline -Metrica $Metrica
    if ($null -eq $base) { return $null }
    if ($base.StdDev -eq 0) { return $null }
    $z = [Math]::Abs(($Valor - $base.Media) / $base.StdDev)
    if ($z -gt $script:CfgAnomalyZ) {
        return @{
            Anomalia = $true; Metrica = $Metrica; Valor = $Valor; Media = $base.Media
            Z = [Math]::Round($z, 2)
            Severidad = if ($z -gt 5) { "CRITICA" } elseif ($z -gt 4) { "ALTA" } else { "MEDIA" }
        }
    }
    return $null
}

function Get-SystemMetrics {
    $metrics = @{}
    try { $metrics["cpu"] = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average } catch { $metrics["cpu"] = 0 }
    try { $metrics["procesos"] = (Get-Process).Count } catch { $metrics["procesos"] = 0 }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $metrics["ram_pct"] = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)
    } catch { $metrics["ram_pct"] = 0 }
    try {
        $net = Get-NetAdapterStatistics | Measure-Object -Property ReceivedBytes -Sum
        $metrics["red_rx_mb"] = if ($net.Sum) { [Math]::Round($net.Sum / 1MB, 2) } else { 0 }
    } catch { $metrics["red_rx_mb"] = 0 }
    try {
        $files = (Get-ChildItem $env:TEMP -ErrorAction SilentlyContinue | Measure-Object).Count
        $metrics["temp_files"] = $files
    } catch { $metrics["temp_files"] = 0 }
    return $metrics
}

function Invoke-AnomalyCheck {
    $m = Get-SystemMetrics
    foreach ($k in $m.Keys) {
        Add-MetricSample -Metrica $k -Valor $m[$k]
        $anom = Test-Anomaly -Metrica $k -Valor $m[$k]
        if ($anom) {
            $msg = "Anomalia $($anom.Severidad) en $k : valor=$($anom.Valor), media=$([Math]::Round($anom.Media,2)), Z=$($anom.Z)"
            Write-AppLog $msg "WARN"
            Add-HistoryDB -Accion "Anomalia ML" -Resultado $anom.Severidad -Segundos 0 -Detalle $msg
            if ($anom.Z -gt 4) {
                Send-AllNotifications -Mensaje $msg -Severidad "warning" -Data @{ anomalia = $k; z = $anom.Z }
            }
        }
    }
}

function Start-AnomalyMonitor {
    if (-not $script:CfgAnomalyEnabled) { return }
    if ($null -ne $script:AnomalyTimer) { return }
    $script:AnomalyTimer = New-Object System.Windows.Forms.Timer
    $script:AnomalyTimer.Interval = 120000
    $script:AnomalyTimer.Add_Tick({ try { Invoke-AnomalyCheck } catch { } })
    $script:AnomalyTimer.Start()
}

# ============================================================================
# SECCION 22 - v8.1: ACTIVE DIRECTORY
# ============================================================================
function Test-ADDisponible {
    try {
        $null = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-ADInventory {
    $resultado = [PSCustomObject]@{
        Disponible = (Test-ADDisponible); Dominio = ""; Equipos = @(); Usuarios = @(); GPOs = @(); Error = ""
    }
    if (-not $resultado.Disponible) {
        $resultado.Error = "Modulo ActiveDirectory no disponible (RSAT no instalado)"
        return $resultado
    }
    try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $resultado.Dominio = (Get-ADDomain).DNSRoot
        $computer = Get-ADComputer -Filter "Name -eq '$env:COMPUTERNAME'" -Properties * -ErrorAction SilentlyContinue
        if ($computer) {
            $resultado.Equipos += [PSCustomObject]@{
                Nombre = $computer.Name; OU = $computer.DistinguishedName
                SO = $computer.OperatingSystem; UltimoLogon = $computer.LastLogonDate; Activo = $computer.Enabled
            }
        }
        $grp = Get-ADGroupMember -Identity "Domain Admins" -ErrorAction SilentlyContinue
        if ($grp) { $resultado.Usuarios = @($grp | Select-Object -First 20 | ForEach-Object { $_.SamAccountName }) }
    } catch { $resultado.Error = $_.Exception.Message }
    return $resultado
}

function Show-ADDialog {
    $info = Get-ADInventory
    $msg = @"
ACTIVE DIRECTORY - v8.2
=======================
Modulo disponible: $($info.Disponible)
Dominio:           $(if($info.Dominio){$info.Dominio}else{'(no detectado)'})
Error:             $(if($info.Error){$info.Error}else{'(ninguno)'})

Equipos encontrados:
$($info.Equipos | ForEach-Object { "  - $($_.Nombre) | SO=$($_.SO) | UltimoLogon=$($_.UltimoLogon)" } -join "`r`n")

Usuarios (Domain Admins, muestra):
$($info.Usuarios -join ", ")
"@
    Show-ResultDialog -Titulo "Inventario Active Directory" -Mensaje (Normalize-LineEndings $msg) -Tipo "Info"
}

# ============================================================================
# SECCION 23 - v8.1: API GRAPHQL (SUBSET)
# ============================================================================
function Invoke-GraphQLQuery {
    param([string]$Query)
    $respuesta = @{ data = @{}; errors = @() }
    try {
        if ([string]::IsNullOrWhiteSpace($Query)) {
            $respuesta.errors += "Query vacia"
            return $respuesta | ConvertTo-Json -Depth 6 -Compress
        }
        $q = ($Query -replace "\s+"," " -replace "query\s*\w*\s*","").Trim()

        if ($q -match "\bstatus\b") {
            $s = Get-QuickStatus
            $respuesta.data.status = @{
                estado = $s.Estado
                servicio = if ($s.ServiceRunning) {"Running"} else {"Stopped"}
                motor = if ($s.EngineRunning) {"Running"} else {"Stopped"}
                tiempoReal = if ($s.RealTimeProtectionEnabled) {"ACTIVADO"} else {"DESACTIVADO"}
                politica = $s.HasPolicy
                fecha = (Get-Date).ToString("s")
            }
        }
        if ($q -match "\bequipos\b" -or $q -match "\bfleet\b") { $respuesta.data.equipos = @(Get-FleetComputers) }
        if ($q -match "\bhistorial\b" -or $q -match "\bhistory\b") {
            if ($script:SqliteOk) {
                $limit = 20
                if ($q -match "first:\s*(\d+)") { $limit = [int]$Matches[1] }
                $respuesta.data.historial = @(Invoke-Sqlite "SELECT * FROM Historial ORDER BY Id DESC LIMIT $limit")
            }
        }
        if ($q -match "\bconfig\b" -or $q -match "\bsettings\b") {
            $respuesta.data.config = @{
                version = "8.2"; tema = if ($script:DarkTheme) {"dark"} else {"light"}
                idioma = $script:Lang; REST = $script:CfgRESTEnabled; Puerto = $script:CfgRESTPort
                forense = $script:CfgForensicMode; telegram = $script:CfgTelegramEnabled
            }
        }
        return $respuesta | ConvertTo-Json -Depth 8 -Compress
    } catch {
        $respuesta.errors += $_.Exception.Message
        return $respuesta | ConvertTo-Json -Depth 6 -Compress
    }
}

# ============================================================================
# SECCION 24 - v8.1: PWA INSTALABLE
# ============================================================================
function Get-PWAHtml {
    return @'
<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta name="theme-color" content="#00E5FF"><title>DefenderTray</title>
<link rel="manifest" href="/pwa/manifest.json"><link rel="apple-touch-icon" href="/pwa/icon-192.png">
<style>*{margin:0;padding:0;box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,'Segoe UI',sans-serif;background:#070B14;color:#E0E6F0;min-height:100vh;padding:20px}
.header{padding:20px 0 30px;text-align:center;border-bottom:1px solid #1E2D4A;margin-bottom:24px}
.header h1{color:#00E5FF;font-size:24px}.header .sub{color:#6B7A99;font-size:11px;margin-top:4px}
.status{font-size:42px;font-weight:bold;text-align:center;margin:30px 0;letter-spacing:2px}
.activo{color:#00E56C;text-shadow:0 0 20px rgba(0,229,108,.5)}
.desactivado{color:#FF3366;text-shadow:0 0 20px rgba(255,51,102,.5)}
.parcial{color:#FFAA00;text-shadow:0 0 20px rgba(255,170,0,.5)}
.card{background:#101928;border:1px solid #1E2D4A;border-radius:12px;padding:20px;margin-bottom:16px}
.card .lbl{color:#6B7A99;font-size:10px;text-transform:uppercase;letter-spacing:1px}
.card .val{font-size:15px;margin-top:6px;font-family:Consolas,monospace}
.actions{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:20px}
.btn{padding:16px;border-radius:10px;border:none;color:#fff;font-weight:bold;font-size:14px;cursor:pointer}
.btn-on{background:#00C86C}.btn-off{background:#FF3366}.btn-diag{background:#008CFF}.btn-emerg{background:#B14EFF}
.info{color:#6B7A99;font-size:11px;text-align:center;margin-top:20px}
</style></head><body>
<div class="header"><h1>DefenderTray</h1><div class="sub">v8.2 ULTIMATE — Panel movil</div></div>
<div id="status" class="status">...</div>
<div class="card"><div class="lbl">Servicio</div><div id="svc" class="val">—</div></div>
<div class="card"><div class="lbl">Motor</div><div id="eng" class="val">—</div></div>
<div class="card"><div class="lbl">Tiempo real</div><div id="rtp" class="val">—</div></div>
<div class="card"><div class="lbl">Ultima actualizacion</div><div id="ts" class="val">—</div></div>
<div class="actions">
<button class="btn btn-on" onclick="cmd('enable')">ACTIVAR</button>
<button class="btn btn-off" onclick="cmd('disable')">DESACTIVAR</button>
<button class="btn btn-diag" onclick="diag()">DIAGNOSTICO</button>
<button class="btn btn-emerg" onclick="emerg()">EMERGENCIA</button>
</div>
<div class="info">Ing. Yosvany Hernandez Quintero<br>+53 5 2160801 / +53 5 9860911</div>
<script>
const API=window.location.origin;
async function refresh(){try{const r=await fetch(API+'/status');const d=await r.json();
const st=document.getElementById('status');st.textContent=d.estado;
st.className='status '+d.estado.toLowerCase();
document.getElementById('svc').textContent=d.servicio;
document.getElementById('eng').textContent=d.motor;
document.getElementById('rtp').textContent=d.tiempoReal;
document.getElementById('ts').textContent=new Date().toLocaleString();
}catch(e){document.getElementById('status').textContent='Offline';}}
async function cmd(a){if(!confirm('¿'+a+'?'))return;
try{const r=await fetch(API+'/'+a);const j=await r.json();alert(j.result||JSON.stringify(j));refresh();}catch(e){alert('Error: '+e);}}
async function diag(){location.href=API+'/diagnostic';}
async function emerg(){if(!confirm('MODO EMERGENCIA: activar Defender ya?'))return;
const r=await fetch(API+'/emergency');const j=await r.json();alert(j.result||'OK');refresh();}
refresh();setInterval(refresh,5000);
if('serviceWorker' in navigator){navigator.serviceWorker.register('/pwa/sw.js');}
</script></body></html>
'@
}

function Get-PWAManifest {
    return @'
{"name":"DefenderTray Ultimate","short_name":"DefenderTray","start_url":"/pwa/","display":"standalone",
"background_color":"#070B14","theme_color":"#00E5FF","orientation":"portrait",
"icons":[{"src":"/pwa/icon-192.png","sizes":"192x192","type":"image/png","purpose":"any maskable"},
{"src":"/pwa/icon-512.png","sizes":"512x512","type":"image/png","purpose":"any maskable"}]}
'@
}

function Get-PWAServiceWorker {
    return @'
const CACHE='defendertray-v8';
const ASSETS=['/pwa/','/pwa/manifest.json'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)));self.skipWaiting();});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))));self.clients.claim();});
self.addEventListener('fetch',e=>{
if(e.request.url.includes('/pwa/')){e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)));}
else{e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)));}
});
'@
}

function Get-PWAIcon {
    param([int]$Size = 192)
    if ($null -eq $script:IconOk) { return $null }
    $bmp = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(0,200,100)) -Size $Size
    if ($null -eq $bmp) { return $null }
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $bmp.Dispose(); $ms.Dispose()
    return $bytes
}

# ============================================================================
# SECCION 25 - v8.1: KIOSCO BIOMETRICO (WINDOWS HELLO)
# ============================================================================
function Test-BiometricAvailable {
    try {
        [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime] | Out-Null
        $avail = [Windows.Security.Credentials.UI.UserConsentVerifier]::CheckAvailabilityAsync()
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
        $task = $asTask.MakeGenericMethod([Windows.Security.Credentials.UI.UserConsentVerifierAvailability]).Invoke($null, @($avail))
        $task.Wait(5000) | Out-Null
        return ($task.Result -eq [Windows.Security.Credentials.UI.UserConsentVerifierAvailability]::Available)
    } catch {
        Write-AppLog "Windows Hello no disponible: $($_.Exception.Message)" "INFO"
        return $false
    }
}

function Request-BiometricVerification {
    param([string]$Mensaje = "Verifica tu identidad para acceder a DefenderTray")
    try {
        [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime] | Out-Null
        $op = [Windows.Security.Credentials.UI.UserConsentVerifier]::RequestVerificationAsync($Mensaje)
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
        $task = $asTask.MakeGenericMethod([Windows.Security.Credentials.UI.UserConsentVerificationResult]).Invoke($null, @($op))
        $task.Wait(30000) | Out-Null
        return ($task.Result -eq [Windows.Security.Credentials.UI.UserConsentVerificationResult]::Verified)
    } catch {
        Write-AppLog "Error biometria: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Test-KioskAuth {
    if (-not $script:IsKioskMode) { return $true }
    if ($script:CfgBiometricKiosk) {
        if (Request-BiometricVerification) {
            Add-HistoryDB -Accion "Biometria" -Resultado "OK" -Segundos 0
            return $true
        }
    }
    return (Test-KioskPassword)
}

# ============================================================================
# SECCION 26 - v8.1: WEBHOOKS
# ============================================================================
$script:CfgWebhooks = @()

function Invoke-Webhooks {
    param([string]$Evento, [hashtable]$Payload = @{})
    if ($script:CfgWebhooks.Count -eq 0) { return }
    $body = @{
        event = $Evento; timestamp = (Get-Date).ToString("s"); host = $env:COMPUTERNAME; payload = $Payload
    } | ConvertTo-Json -Depth 6 -Compress
    foreach ($wh in $script:CfgWebhooks) {
        if (-not $wh.Activo) { continue }
        $match = ($wh.Eventos -contains $Evento) -or ($wh.Eventos -contains "*")
        if (-not $match) { continue }
        try {
            $null = Invoke-RestMethod -Uri $wh.Url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 8 -ErrorAction Stop
            Write-AppLog "Webhook OK: $($wh.Url) [$Evento]" "INFO"
        } catch {
            Write-AppLog "Webhook fallo: $($wh.Url) - $($_.Exception.Message)" "WARN"
        }
    }
}

function Add-Webhook {
    param([string]$Url, [string[]]$Eventos = @("*"))
    if (-not $script:SqliteOk) {
        $script:CfgWebhooks += @{ Url = $Url; Eventos = $Eventos; Activo = $true }
    } else {
        $null = Invoke-Sqlite "INSERT INTO Webhooks (Url,Eventos,Activo) VALUES (@u,@e,1)" @{ u = $Url; e = ($Eventos -join ",") }
    }
}

function Get-WebhooksFromDB {
    if (-not $script:SqliteOk) { return }
    $rows = Invoke-Sqlite "SELECT * FROM Webhooks WHERE Activo=1"
    $script:CfgWebhooks = @()
    if ($rows) { foreach ($r in $rows) { $script:CfgWebhooks += @{ Url = $r.Url; Eventos = ($r.Eventos -split ","); Activo = $true } } }
}

# ============================================================================
# SECCION 27 - v8.1: EXPORTACION EXCEL / CSV
# ============================================================================
function Export-HistoryToCsv {
    param([string]$Path)
    try {
        $rows = if ($script:SqliteOk) { Invoke-Sqlite "SELECT * FROM Historial ORDER BY Id DESC" } else { $script:EventHistory }
        $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Delimiter ","
        Write-AppLog "CSV exportado: $Path" "INFO"
        return $true
    } catch {
        Write-AppLog "Error CSV: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Export-HistoryToExcel {
    param([string]$Path)
    try {
        if (Get-Module -ListAvailable -Name ImportExcel -ErrorAction SilentlyContinue) {
            Import-Module ImportExcel -ErrorAction SilentlyContinue
            $rows = if ($script:SqliteOk) { Invoke-Sqlite "SELECT * FROM Historial ORDER BY Id DESC" } else { $script:EventHistory }
            $rows | Export-Excel -Path $Path -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -WorksheetName "Historial"
            Write-AppLog "Excel (ImportExcel) exportado: $Path" "INFO"
            return $true
        }
        $excel = New-Object -ComObject Excel.Application -ErrorAction Stop
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $wb = $excel.Workbooks.Add()
        $ws = $wb.Worksheets.Item(1)
        $ws.Name = "Historial"
        $ws.Cells.Item(1,1) = "Fecha"; $ws.Cells.Item(1,2) = "Accion"
        $ws.Cells.Item(1,3) = "Resultado"; $ws.Cells.Item(1,4) = "Segundos"
        $ws.Range("A1:D1").Font.Bold = $true
        $rows = if ($script:SqliteOk) { Invoke-Sqlite "SELECT * FROM Historial ORDER BY Id DESC" } else { $script:EventHistory }
        $i = 2
        foreach ($r in $rows) {
            $ws.Cells.Item($i,1) = if ($r.Fecha) { $r.Fecha } else { $r.Hora.ToString("s") }
            $ws.Cells.Item($i,2) = $r.Accion
            $ws.Cells.Item($i,3) = $r.Resultado
            $ws.Cells.Item($i,4) = $r.Segundos
            $i++
        }
        $ws.Columns.AutoFit() | Out-Null
        $wb.SaveAs($Path)
        $wb.Close($false)
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
        Write-AppLog "Excel (COM) exportado: $Path" "INFO"
        return $true
    } catch {
        Write-AppLog "Excel fallo (no instalado?), exportando CSV: $($_.Exception.Message)" "WARN"
        return (Export-HistoryToCsv -Path ([IO.Path]::ChangeExtension($Path, ".csv")))
    }
}

# ============================================================================
# SECCION 28 - v8.1: DASHBOARD SSE TIEMPO REAL
# ============================================================================
function Get-SSEDashboardHtml {
    return @'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Dashboard tiempo real</title>
<style>body{font-family:'Segoe UI',sans-serif;background:#070B14;color:#E0E6F0;margin:0;padding:20px}
h1{color:#00E5FF;border-bottom:2px solid #00E5FF;padding-bottom:12px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:20px 0}
.card{background:#101928;border:1px solid #1E2D4A;border-radius:10px;padding:18px}
.card .lbl{color:#6B7A99;font-size:10px;text-transform:uppercase;letter-spacing:1px}
.card .val{font-size:28px;font-weight:bold;color:#00E5FF;margin-top:6px}
.log{background:#0A1424;border-radius:10px;padding:16px;font-family:Consolas,monospace;font-size:12px;height:400px;overflow-y:auto;border:1px solid #1E2D4A}
.log .line{padding:3px 0;border-bottom:1px solid #0F1A2C}
.log .line.info{color:#6B7A99}.log .line.ok{color:#00E56C}.log .line.warn{color:#FFAA00}.log .line.err{color:#FF3366}
.status-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px;background:#00E56C;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}</style></head><body>
<h1>Dashboard en Tiempo Real — v8.2</h1>
<div class="grid">
<div class="card"><div class="lbl">Estado</div><div class="val" id="vEstado">—</div></div>
<div class="card"><div class="lbl">Servicio</div><div class="val" id="vSvc">—</div></div>
<div class="card"><div class="lbl">Motor</div><div class="val" id="vEng">—</div></div>
<div class="card"><div class="lbl">Tiempo Real</div><div class="val" id="vRtp">—</div></div>
<div class="card"><div class="lbl">Anomalias</div><div class="val" id="vAnom">0</div></div>
</div>
<div class="card"><div style="margin-bottom:8px"><span class="status-dot"></span><b>Eventos en vivo</b></div>
<div class="log" id="log"></div></div>
<script>
const log=document.getElementById('log');let anomCount=0;
function addLine(txt,cls){const div=document.createElement('div');div.className='line '+(cls||'info');
div.textContent=new Date().toLocaleTimeString()+'  '+txt;log.prepend(div);
while(log.children.length>300)log.lastChild.remove();}
function setStat(id,val){document.getElementById(id).textContent=val;}
if(window.EventSource){const es=new EventSource('/sse/stream');
es.addEventListener('status',e=>{const d=JSON.parse(e.data);setStat('vEstado',d.estado);setStat('vSvc',d.servicio);setStat('vEng',d.motor);setStat('vRtp',d.tiempoReal);});
es.addEventListener('action',e=>{const d=JSON.parse(e.data);addLine(d.accion+' -> '+d.resultado,d.resultado&&d.resultado.match(/OK/i)?'ok':'warn');});
es.addEventListener('log',e=>{const d=JSON.parse(e.data);addLine(d.mensaje,d.nivel||'info');});
es.addEventListener('anomaly',e=>{const d=JSON.parse(e.data);addLine('ANOMALIA '+d.metrica+' Z='+d.z,'err');anomCount++;setStat('vAnom',anomCount);});
es.onerror=()=>{addLine('SSE desconectado','err');};
}else{addLine('SSE no soportado','err');}
</script></body></html>
'@
}

# ============================================================================
# SECCION 29 - v8.1: AUTO-UPDATE GITHUB
# ============================================================================
$script:CurrentVersion = "8.2"

function Get-LatestGitHubRelease {
    try {
        if ([string]::IsNullOrEmpty($script:CfgGitHubRepo) -or $script:CfgGitHubRepo -eq "usuario/DefenderTray") { return $null }
        $url = "https://api.github.com/repos/$($script:CfgGitHubRepo)/releases/latest"
        $resp = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "DefenderTray" } -TimeoutSec 15
        return @{
            Tag = $resp.tag_name; Version = ($resp.tag_name -replace "^v","")
            Url = $resp.html_url; Assets = $resp.assets
            Published = $resp.published_at; Body = $resp.body
        }
    } catch {
        Write-AppLog "GitHub update check error: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Test-UpdateAvailable {
    $latest = Get-LatestGitHubRelease
    if ($null -eq $latest) { return $null }
    try {
        $cur = [version]$script:CurrentVersion
        $new = [version]$latest.Version
        if ($new -gt $cur) { return $latest }
    } catch { }
    return $null
}

function Invoke-AutoUpdate {
    $latest = Test-UpdateAvailable
    if ($null -eq $latest) { return "Ya tienes la ultima version ($($script:CurrentVersion))" }
    try {
        $asset = $latest.Assets | Where-Object { $_.name -match '\.(ps1|zip)$' } | Select-Object -First 1
        if (-not $asset) { return "Release $($latest.Version) no tiene asset descargable" }
        $dst = Join-Path $script:ConfigDir "updates"
        if (-not (Test-Path $dst)) { New-Item -Path $dst -ItemType Directory -Force | Out-Null }
        $dstFile = Join-Path $dst $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dstFile -UseBasicParsing -TimeoutSec 120
        $shaAsset = $latest.Assets | Where-Object { $_.name -match 'sha256|checksums' } | Select-Object -First 1
        if ($shaAsset) {
            $shaTxt = (Invoke-WebRequest -Uri $shaAsset.browser_download_url -UseBasicParsing).Content
            $expected = ($shaTxt -split "\s+")[0]
            $actual = (Get-FileHash -Path $dstFile -Algorithm SHA256).Hash
            if ($actual -ne $expected) { return "SHA256 no coincide. Abortando actualizacion." }
        }
        $backup = "$($script:ScriptPath).v$($script:CurrentVersion).bak"
        Copy-Item -Path $script:ScriptPath -Destination $backup -Force
        if ($dstFile -match '\.zip$') {
            Expand-Archive -Path $dstFile -DestinationPath (Split-Path $script:ScriptPath) -Force
        } else {
            Copy-Item -Path $dstFile -Destination $script:ScriptPath -Force
        }
        Add-HistoryDB -Accion "Auto-Update" -Resultado "OK v$($latest.Version)" -Segundos 0
        return "Actualizado a v$($latest.Version). Reinicia DefenderTray. Backup: $backup"
    } catch { return "Error: $($_.Exception.Message)" }
}

function Show-UpdateDialog {
    $latest = Test-UpdateAvailable
    if ($null -eq $latest) {
        [System.Windows.Forms.MessageBox]::Show("Ya tienes la ultima version ($($script:CurrentVersion)).","Sin actualizaciones","OK","Information") | Out-Null
        return
    }
    $msg = "Nueva version disponible: v$($latest.Version)`r`nFecha: $($latest.Published)`r`n`r`n$($latest.Body)`r`n`r`n¿Actualizar ahora?"
    if (Show-ConfirmDialog "Actualizacion" $msg) {
        $res = Invoke-AutoUpdate
        [System.Windows.Forms.MessageBox]::Show($res,"Auto-Update","OK","Information") | Out-Null
    }
}

# ============================================================================
# SECCION 30 - v8.1: DOCKER
# ============================================================================
function New-DockerPackage {
    param([string]$OutputDir = "$env:USERPROFILE\Desktop\DefenderTray_v8_Docker")
    try {
        if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $script:ScriptPath -Destination (Join-Path $OutputDir "DefenderTray.ps1") -Force

        $dockerfile = @'
FROM mcr.microsoft.com/windows/servercore:ltsc2022
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
WORKDIR C:\DefenderTray
COPY DefenderTray.ps1 .
EXPOSE 9182
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD powershell -Command "try { (Invoke-WebRequest -UseBasicParsing http://localhost:9182/status -TimeoutSec 3).StatusCode -eq 200 } catch { exit 1 }"
ENTRYPOINT ["powershell", "-ExecutionPolicy", "Bypass", "-File", "C:\\DefenderTray\\DefenderTray.ps1", "-portable"]
'@
        Set-Content -Path (Join-Path $OutputDir "Dockerfile") -Value $dockerfile -Encoding ASCII -Force

        $compose = @'
version: "3.9"
services:
  defendertray:
    build: .
    image: defendertray:v8.2
    container_name: defendertray
    restart: unless-stopped
    ports: ["9182:9182"]
    volumes: [defendertray_data:C:\DefenderTrayData]
    environment: [DEFENDERTRAY_LOG_LEVEL=INFO, DEFENDERTRAY_PORT=9182]
volumes:
  defendentray_data: {driver: local}
'@
        Set-Content -Path (Join-Path $OutputDir "docker-compose.yml") -Value $compose -Encoding ASCII -Force

        $readme = @'
# DefenderTray v8.2 - Docker
Esta imagen NO puede administrar Defender del HOST (contenedores Windows sin acceso al kernel).
Uso: panel fleet centralizado, API REST, dashboard de monitoreo.
docker-compose up -d --build
Dashboard: http://localhost:9182/
Fleet: http://localhost:9182/fleet
'@
        Set-Content -Path (Join-Path $OutputDir "README.md") -Value $readme -Encoding UTF8 -Force
        return "Paquete Docker en: $OutputDir"
    } catch { return "Error: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 31 - TELEGRAM
# ============================================================================
function Send-TelegramNotification {
    param([string]$Mensaje)
    if (-not $script:CfgTelegramEnabled) { return $false }
    if ([string]::IsNullOrEmpty($script:CfgTelegramToken) -or [string]::IsNullOrEmpty($script:CfgTelegramChatId)) { return $false }
    try {
        $url = "https://api.telegram.org/bot$($script:CfgTelegramToken)/sendMessage"
        $body = @{ chat_id = $script:CfgTelegramChatId; text = "[DefenderTray] $Mensaje"; parse_mode = "HTML" } | ConvertTo-Json
        $null = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop
        Write-AppLog "Telegram enviado: $Mensaje" "INFO"
        return $true
    } catch {
        Write-AppLog "Error Telegram: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Send-AllNotifications {
    param([string]$Mensaje, [string]$Severidad = "info", [hashtable]$Data = @{})
    $null = Send-TelegramNotification $Mensaje
    $null = Send-FCMPush -Titulo "DefenderTray" -Cuerpo $Mensaje -Data $Data
    $null = Invoke-Webhooks -Evento $Severidad -Payload (@{ mensaje = $Mensaje; equipo = $env:COMPUTERNAME; ts = (Get-Date).ToString("s") } + $Data)
}

# ============================================================================
# SECCION 32 - PDF/HTML EXPORT CON FIRMA
# ============================================================================
function Export-ReportAsPDF {
    param([string]$Titulo, [string]$Contenido, [string]$RutaDestino)
    try {
        $html = @"
<!DOCTYPE html>
<html><head><meta charset='UTF-8'><title>$Titulo</title>
<style>
body { font-family: Consolas, monospace; background: #0A0E1A; color: #E0E6F0; padding: 20px; }
h1 { color: #00E5FF; border-bottom: 2px solid #00E5FF; padding-bottom: 10px; }
pre { background: #141B2E; padding: 15px; border-radius: 8px; white-space: pre-wrap; word-wrap: break-word; }
.footer { margin-top: 30px; padding-top: 10px; border-top: 1px solid #444; color: #6B7A99; font-size: 10px; }
</style></head><body>
<h1>$Titulo</h1>
<pre>$Contenido</pre>
<div class='footer'>
Generado por DefenderTray v8.2 ULTIMATE<br>
Ing. Yosvany Hernandez Quintero - +53 5 2160801<br>
Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
SHA256 del script: $($script:ScriptHash)
</div></body></html>
"@
        $htmlPath = [System.IO.Path]::ChangeExtension($RutaDestino, ".html")
        $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force
        Sign-Report -Path $htmlPath
        Write-AppLog "Reporte HTML generado: $htmlPath" "INFO"
        return $htmlPath
    } catch {
        Write-AppLog "Error export PDF: $($_.Exception.Message)" "ERROR"
        return ""
    }
}

# ============================================================================
# SECCION 33 - EVENT LOG WINDOWS DEFENDER
# ============================================================================
function Get-DefenderEventLog {
    param([int]$MaxEvents = 50)
    $resultado = New-Object System.Collections.ArrayList
    try {
        $events = Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents $MaxEvents -ErrorAction Stop
        foreach ($e in $events) {
            $tipo = switch ($e.Id) {
                1006 { "Malware detectado" }; 1007 { "Accion realizada" }
                1008 { "Accion fallida" }; 1009 { "Cuarentena restaurada" }
                1015 { "Comportamiento sospechoso" }; 1116 { "Deteccion" }; 1117 { "Accion aplicada" }
                default { "Evento $($e.Id)" }
            }
            [void]$resultado.Add([PSCustomObject]@{
                Hora = $e.TimeCreated; Id = $e.Id; Tipo = $tipo
                Mensaje = ($e.Message -split "`n")[0]
            })
        }
    } catch { }
    return $resultado
}

# ============================================================================
# SECCION 34 - MODO FORENSE
# ============================================================================
function Save-ForensicSnapshot {
    param([string]$Contexto)
    if (-not $script:CfgForensicMode) { return }
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $dir = Join-Path $script:ForensicDir $timestamp
        New-Item -Path $dir -ItemType Directory -Force | Out-Null

        try {
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $bmp.Save((Join-Path $dir "screenshot.png"), [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose()
        } catch { }

        $snapshot = @{ Contexto = $Contexto; Timestamp = $timestamp; Servicios = @(); Procesos = @(); Firmas = @{} }
        foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) { $snapshot.Servicios += @{ Nombre=$s; Estado=$svc.Status.ToString(); Start=(Get-ServiceStartMode -Name $s) } }
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
    } catch { Write-AppLog "Error forensic: $($_.Exception.Message)" "WARN" }
}

# ============================================================================
# SECCION 35 - MULTI-MONITOR
# ============================================================================
function Get-ActiveMonitorBounds {
    try {
        $pos = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($pos)
        return $screen.WorkingArea
    } catch { return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
}

function Center-FormOnActiveMonitor {
    param([System.Windows.Forms.Form]$Form)
    if (-not $script:CfgMultiMonitor) { $Form.StartPosition = "CenterScreen"; return }
    try {
        $bounds = Get-ActiveMonitorBounds
        $x = $bounds.X + [int](($bounds.Width - $Form.Width) / 2)
        $y = $bounds.Y + [int](($bounds.Height - $Form.Height) / 2)
        $Form.StartPosition = "Manual"
        $Form.Location = New-Object System.Drawing.Point($x, $y)
    } catch { }
}

# ============================================================================
# SECCION 36 - PANIC BUTTON / EMERGENCIA
# ============================================================================
function Invoke-EmergencyActivation {
    Write-AppLog "=== MODO EMERGENCIA ACTIVADO ===" "WARN"
    Send-AllNotifications -Mensaje "EMERGENCIA: Activando Defender desde boton de panico" -Severidad "emergency"
    $log = Enable-Defender
    $s = Get-QuickStatus
    Add-HistoryDB -Accion "EMERGENCIA" -Resultado $s.Estado -Segundos 0
    if (-not $script:SilentMode) {
        Show-ResultDialog -Titulo "EMERGENCIA - Defender Activado" -Mensaje (Normalize-LineEndings $log) -Tipo "Success"
    }
}

# ============================================================================
# SECCION 36b - v8.2: INTERRUPTOR DE UN SOLO CLIC
# ============================================================================
function Get-ToggleAction {
    # Decide el sentido del interruptor: "Activar" o "Desactivar".
    param($Estado)
    if ($null -eq $Estado) { $Estado = Get-QuickStatus }
    if ($Estado.Estado -eq "DESACTIVADO") { return "Activar" }
    if ($Estado.Estado -eq "PARCIAL") {
        # Completar el sentido ya iniciado: si hay politicas o servicios
        # deshabilitados, terminar de desactivar; si no, terminar de activar.
        if ($Estado.HasPolicy -or $Estado.ServicesDisabled) { return "Desactivar" }
        return "Activar"
    }
    return "Desactivar"
}

function Invoke-ToggleProtection {
    # v8.2: TODO con un unico clic. Sin dialogo de confirmacion y sin dialogo
    # modal de resultado (aviso por globo: cero clics extra). La operacion se
    # ejecuta COMPLETA (desactivacion o activacion total, con reintentos).
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
        return
    }
    if ($script:IsBusy) { return }
    $s = Get-QuickStatus
    $accion = Get-ToggleAction -Estado $s
    $script:IsBusy = $true
    try {
        Set-PanelBusy $true
        Start-ActionTimer; $script:LastActionName = "$accion (1 clic)"
        if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
            if ($accion -eq "Desactivar") { $script:PanelLblDet1.Text = "Desactivando COMPLETO (1 clic)..." }
            else { $script:PanelLblDet1.Text = "Activando COMPLETO (1 clic)..." }
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
        }
        [System.Windows.Forms.Application]::DoEvents()
        if ($accion -eq "Desactivar") { $log = Disable-Defender } else { $log = Enable-Defender }
        $elapsed = Get-ActionElapsedSeconds
        $script:LastActionTime = $elapsed
        Stop-ActionTimer | Out-Null
        $s2 = Get-QuickStatus
        Add-HistoryDB -Accion "$accion (1 clic)" -Resultado $s2.Estado -Segundos $elapsed -Detalle $log
        Update-PanelStatusUI
        Update-TrayIcon -Estado $s2.Estado

        $msg = ("Estado: {0}. {1} completado en {2:N2}s." -f $s2.Estado, $accion, $elapsed)
        if ($s2.PendingReboot) {
            $msg = "$msg Cambios aplicados al 100%: REINICIA el equipo para hacerlos efectivos."
        } elseif ($s2.Estado -eq "PARCIAL") {
            $msg = "$msg Estado PARCIAL: consulta Diagnostico."
        }
        if ($null -ne $script:notifyIcon) {
            try {
                $icono = "Warning"
                if ($s2.Estado -eq "ACTIVO") { $icono = "Info" }
                $script:notifyIcon.ShowBalloonTip(6000, "DefenderTray", $msg, $icono)
            } catch { }
        }
        if (($accion -eq "Desactivar") -and (Test-TamperProtectionActive)) {
            Show-TamperProtectionGuide -Contexto "Para desactivar Windows Defender al 100%"
        }
    } finally {
        $script:IsBusy = $false
        Stop-ActionTimer | Out-Null
        Set-PanelBusy $false
    }
}

function Invoke-EnableProtection {
    param([string]$Accion = "Activar")
    if (-not (Test-Admin)) {
        if (-not $script:SilentMode) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
        }
        return
    }
    if ($script:IsBusy) { return }

    $panelVisible = ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed)
    $script:IsBusy = $true
    try {
        if ($panelVisible) {
            Set-PanelBusy $true
            if ($null -ne $script:PanelLblDet1) {
                $script:PanelLblDet1.Text = "Activando Windows Defender..."
                $script:PanelLblDet1.ForeColor = $script:Colors.Warn
            }
        }
        Start-ActionTimer
        $script:LastActionName = $Accion
        [System.Windows.Forms.Application]::DoEvents()
        $log = Enable-Defender
        $elapsed = Get-ActionElapsedSeconds
        $script:LastActionTime = $elapsed
        Stop-ActionTimer | Out-Null

        $s = Get-QuickStatus
        Add-HistoryDB -Accion $Accion -Resultado $s.Estado -Segundos $elapsed -Detalle $log
        Update-PanelStatusUI
        Update-TrayIcon -Estado $s.Estado

        $mensaje = ("Estado: {0}. Activacion finalizada en {1:N2}s." -f $s.Estado, $elapsed)
        if ($s.Estado -ne "ACTIVO") { $mensaje += " Revisa Diagnostico y Seguridad de Windows." }
        if ($null -ne $script:notifyIcon) {
            try {
                $tipo = if ($s.Estado -eq "ACTIVO") { "Info" } else { "Warning" }
                $script:notifyIcon.ShowBalloonTip(6000, "DefenderTray", $mensaje, $tipo)
            } catch { }
        }
    } catch {
        $mensajeError = "Error al activar Defender: $($_.Exception.Message)"
        Write-AppLog $mensajeError "ERROR"
        if ($null -ne $script:notifyIcon) {
            try { $script:notifyIcon.ShowBalloonTip(6000, "DefenderTray", $mensajeError, "Error") } catch { }
        } elseif (-not $script:SilentMode) {
            [System.Windows.Forms.MessageBox]::Show($mensajeError,"DefenderTray","OK","Error") | Out-Null
        }
    } finally {
        $script:IsBusy = $false
        Stop-ActionTimer | Out-Null
        if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) { Set-PanelBusy $false }
    }
}

# ============================================================================
# SECCION 37 - BACKUP NUBE
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
            Fecha = (Get-Date).ToString("s"); Version = "8.2"
            Estado = (Get-QuickStatus).Estado; Servicios = @(); Config = $script:CfgCustomTheme
        }
        foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) { $data.Servicios += @{ Nombre=$s; Estado=$svc.Status.ToString() } }
        }
        $data | ConvertTo-Json -Depth 5 | Set-Content -Path $dst -Encoding UTF8 -Force
        Write-AppLog "Backup nube: $dst" "INFO"
    } catch { Write-AppLog "Error backup nube: $($_.Exception.Message)" "WARN" }
}

# ============================================================================
# SECCION 38 - PERFILES MULTI-USUARIO (JSON fallback)
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
    try { $Profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ProfilesFile -Encoding UTF8 -Force } catch { }
}

function Get-CurrentUser {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

# ============================================================================
# SECCION 39 - CONTROL POR VOZ (STUB)
# ============================================================================
function Initialize-VoiceRecognition {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction SilentlyContinue
        $reconocedor = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $reconocedor.SetInputToDefaultAudioDevice()
        $gramatica = New-Object System.Speech.Recognition.DictationGrammar
        $reconocedor.LoadGrammar($gramatica)
        return $reconocedor
    } catch { return $null }
}

function Start-VoiceCommands {
    $reconocedor = Initialize-VoiceRecognition
    if ($null -eq $reconocedor) {
        Write-AppLog "Reconocimiento de voz no disponible" "WARN"
        return
    }
    Write-AppLog "Reconocimiento de voz iniciado" "INFO"
}

# ============================================================================
# SECCION 40 - BOTONES NEON
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
# SECCION 41 - DIALOGO RESULTADO
# ============================================================================
function Show-ResultDialog {
    param([string]$Titulo, [string]$Mensaje, [string]$Tipo = "Info")
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

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.ReadOnly = $true
    $txt.WordWrap = $true; $txt.AcceptsReturn = $true
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor = $script:Colors.ConsoleBg
    $txt.ForeColor = $script:Colors.ConsoleText
    $txt.BorderStyle = "FixedSingle"
    $txt.Location = New-Object System.Drawing.Point(15, 75)
    $txt.Size = New-Object System.Drawing.Size(870, 490)
    $txt.Anchor = "Top,Left,Right,Bottom"
    $txt.Text = $Mensaje
    $dlg.Controls.Add($txt)

    $btnCopiar = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 580 140 34
    $btnPDF    = New-NeonButton "Exportar HTML" $script:Colors.AccentPurple $script:Colors.AccentPurpH 165 580 160 34
    $btnCerrar = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 735 580 150 34
    $btnCopiar.Anchor = "Bottom,Left"; $btnPDF.Anchor = "Bottom,Left"; $btnCerrar.Anchor = "Bottom,Right"
    $dlg.Controls.Add($btnCopiar); $dlg.Controls.Add($btnPDF); $dlg.Controls.Add($btnCerrar)

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
# SECCION 42 - BACKUP REGISTRO
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
# SECCION 43 - FAILURE ACTIONS
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
# SECCION 44 - REPARAR FIRMAS
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
# SECCION 45 - DESACTIVAR DEFENDER
# ============================================================================
# --- v8.2: helpers de preferencias y Tamper Protection ---

function Set-MpPrefValue {
    # v8.2: fix critico. En v8.1 se hacia `Set-MpPreference @{ $p = $true }`,
    # que PowerShell intenta enlazar como parametro POSICIONAL (falla siempre)
    # y ademas se le pasaba -Force, parametro que Set-MpPreference NO tiene.
    # Resultado: silencio total y activacion/desactivacion PARCIALES. Aqui se
    # aplica cada preferencia por su nombre real via splatting.
    param([string]$Nombre, $Valor)
    if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) { return $false }
    try {
        $splat = @{ ErrorAction = "SilentlyContinue" }
        $splat[$Nombre] = $Valor
        Set-MpPreference @splat
        return $true
    } catch { return $false }
}

function Test-TamperProtectionActive {
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            return [bool](Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected
        }
    } catch { }
    return $false
}

function Disable-TamperProtectionBestEffort {
    # Intenta bajar el flag por registro con los servicios detenidos. En varios
    # builds Windows protege la clave (TrustedInstaller) y devuelve $false.
    try {
        $p = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        if (Test-Path $p) {
            Set-ItemProperty -Path $p -Name "TamperProtection" -Value 0 -Type DWord -Force -ErrorAction Stop
            Remove-ItemProperty -Path $p -Name "TamperProtectionSource" -Force -ErrorAction SilentlyContinue
            return $true
        }
    } catch { }
    return $false
}

function Show-TamperProtectionGuide {
    param([string]$Contexto = "Para completar la accion")
    $msg = "Tamper Protection (Proteccion contra manipulaciones) esta ACTIVA y Windows bloquea cambios en Defender.`r`n`r`n" +
           "$Contexto debes desactivarla UNA sola vez en Seguridad de Windows:`r`n`r`n" +
           "  Seguridad de Windows > Proteccion antivirus y contra amenazas >`r`n" +
           "  Configuracion de proteccion antivirus y contra amenazas >`r`n" +
           "  Proteccion contra manipulaciones = DESACTIVADA`r`n`r`n" +
           "Todo lo demas ya esta aplicado por DefenderTray y se conserva.`r`n" +
           "Tras desactivarla, vuelve a pulsar el boton (un solo clic).`r`n`r`n" +
           "Abrir Seguridad de Windows ahora?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "Tamper Protection", "YesNo", "Warning")
    if ($r -eq "Yes") {
        try { Start-Process "windowsdefender://threatsettings" } catch { }
    }
}

# ============================================================================
# SECCION 45 - DESACTIVAR DEFENDER (v8.2: TOTAL en una pasada)
# ============================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria. No se aplican cambios.")
        return ($log -join "`r`n")
    }
    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de desactivar" }

    # v8.2: Tamper Protection ya NO aborta la operacion: se intenta y se
    # continua con todo lo demas (politicas y Start=4 persisten igualmente).
    $tpActiva = Test-TamperProtectionActive
    if ($tpActiva) {
        [void]$log.Add("[!] Tamper Protection ACTIVA: Windows puede bloquear parte de la operacion.")
        [void]$log.Add("    Se aplicara TODO lo posible; el resto se completa desactivandola y reiniciando.")
    }

    $backupReg = Backup-DefenderRegistry
    if ($backupReg) { [void]$log.Add("[0/11] Backup del registro: OK") }

    [void]$log.Add("[1/11] Desactivando preferencias (Set-MpPreference, splatting)...")
    $prefsOff = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                  "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                  "DisableEmailScanning","DisableIntrusionPreventionSystem",
                  "DisableRemovableDriveScanning","DisableScanningNetworkFiles",
                  "DisableCatchupQuickScan","DisableCatchupFullScan","DisableRestorePoint")
    $okPrefs = 0
    foreach ($p in $prefsOff) { if (Set-MpPrefValue -Nombre $p -Valor $true) { $okPrefs++ } }
    [void]$log.Add("       $okPrefs de $($prefsOff.Count) preferencias forzadas a OFF (v8.1: 0 por el bug)")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        try { Set-MpPreference -MAPSReporting Disabled -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -SubmitSamplesConsent NeverSend -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -PUAProtection Disabled -ErrorAction SilentlyContinue } catch { }
        try { Set-MpPreference -EnableNetworkProtection Disabled -ErrorAction SilentlyContinue } catch { }
    }

    [void]$log.Add("[2/11] Limpiando politicas anteriores...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }

    [void]$log.Add("[3/11] Estableciendo politicas de bloqueo (persisten tras reinicio)...")
    $dp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $dp)) { New-Item -Path $dp -Force | Out-Null }
    Set-ItemProperty -Path $dp -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dp -Name "DisableAntiVirus"   -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dp -Name "PUAProtection"      -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
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
    $eg = "$dp\Windows Defender Exploit Guard\Network Protection"
    if (-not (Test-Path $eg)) { New-Item -Path $eg -Force | Out-Null }
    Set-ItemProperty -Path $eg -Name "EnableNetworkProtection" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    $ss = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $ss)) { New-Item -Path $ss -Force | Out-Null }
    Set-ItemProperty -Path $ss -Name "EnableSmartScreen" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ss -Name "ShellSmartScreenLevel" -Value "Off" -Type String -Force -ErrorAction SilentlyContinue
    [void]$log.Add("       AntiSpyware + RTP + Spynet + ExploitGuard + PUA + SmartScreen")

    [void]$log.Add("[4/11] Deshabilitando FailureActions...")
    $svcs = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    $faCount = 0
    foreach ($s in $svcs) { if (Disable-ServiceFailureActions -ServiceName $s) { $faCount++ } }
    [void]$log.Add("       FailureActions deshabilitadas en $faCount servicios")

    [void]$log.Add("[5/11] Bucle de desactivacion (max 5)...")
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

    [void]$log.Add("[6/11] Intentando bajar Tamper Protection por registro...")
    if ($tpActiva -or (Test-TamperProtectionActive)) {
        if (Disable-TamperProtectionBestEffort) {
            [void]$log.Add("       TamperProtection=0 aplicado en registro.")
        } else {
            [void]$log.Add("       Windows protege la clave: desactivala en Seguridad de Windows.")
        }
    } else {
        [void]$log.Add("       Tamper Protection ya estaba desactivada.")
    }

    [void]$log.Add("")
    [void]$log.Add("[7/11] Verificacion final...")
    $svcFin  = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $svcOk = ($null -eq $svcFin) -or ($svcFin.Status -ne 'Running')
    $procOk = ($null -eq $procFin)
    $startOk = $true
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        if ((Get-ServiceStartMode -Name $s) -ne "Disabled") { $startOk = $false }
    }
    $policyOk = Test-DefenderPolicyDisabled

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO FINAL ===")
    if ($svcOk) { [void]$log.Add("  WinDefend: DETENIDO") } else { [void]$log.Add("  WinDefend: AUN CORRIENDO") }
    if ($procOk) { [void]$log.Add("  MsMpEng:   DETENIDO") } else { [void]$log.Add("  MsMpEng:   AUN CORRIENDO") }
    if ($startOk) { [void]$log.Add("  Start=4:   APLICADO") } else { [void]$log.Add("  Start=4:   PENDIENTE") }
    if ($policyOk) { [void]$log.Add("  Politicas: APLICADAS") } else { [void]$log.Add("  Politicas: PENDIENTES") }
    [void]$log.Add("  Intentos:  $intento de $maxIntentos")

    [void]$log.Add("")
    $completoAhora = $svcOk -and $procOk -and $startOk -and $policyOk
    $completoTrasReiniciar = $startOk -and $policyOk
    if ($completoAhora) {
        [void]$log.Add("[OK] DESACTIVACION COMPLETA. Defender esta 100% desactivado.")
    } elseif ($completoTrasReiniciar) {
        [void]$log.Add("[OK] DESACTIVACION APLICADA AL 100%. Windows la hace efectiva al REINICIAR.")
        [void]$log.Add("     (Windows 11 22H2+ reactiva WinDefend desde el kernel hasta el reinicio.)")
    } else {
        [void]$log.Add("[!] DESACTIVACION INCOMPLETA.")
        if ($tpActiva -and (Test-TamperProtectionActive)) {
            [void]$log.Add("     Motivo: Tamper Protection ACTIVA.")
            [void]$log.Add("     Desactivala en Seguridad de Windows y vuelve a pulsar UN CLIC.")
        } else {
            [void]$log.Add("     Revisa el log; puedes usar Reparacion Profunda.")
        }
    }

    $sw.Stop()
    [void]$log.Add("")
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Send-AllNotifications -Mensaje "Defender desactivado. Estado: $((Get-QuickStatus).Estado)" -Severidad "warning" -Data @{ estado=(Get-QuickStatus).Estado }
    if ($script:CfgCloudBackup) { Backup-ToCloud }
    return ($log -join "`r`n")
}

# ============================================================================
# SECCION 46 - ACTIVAR DEFENDER (v8.2: TOTAL en una pasada)
# ============================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:AuditMode) {
        [void]$log.Add("[AUDITORIA] Modo auditoria. No se aplican cambios.")
        return ($log -join "`r`n")
    }
    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de activar" }

    [void]$log.Add("[1/11] Configurando Start de cada servicio...")
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

    [void]$log.Add("[2/11] Eliminando politicas de bloqueo...")
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
    $ss = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (Test-Path $ss) {
        foreach ($n in @("EnableSmartScreen","ShellSmartScreenLevel")) {
            try { Remove-ItemProperty -Path $ss -Name $n -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("       SmartScreen restaurado (valores de politica eliminados).")
    }

    [void]$log.Add("[3/11] Limpiando claves RTP...")
    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    if (Test-Path $rtWk) {
        foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                         "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning",
                         "DisableRawWriteNotification","DisableAsyncScan")) {
            try { Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue } catch { }
        }
        [void]$log.Add("       Claves RTP limpiadas.")
    }

    [void]$log.Add("[4/11] Arrancando servicios por dependencias...")
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

    [void]$log.Add("[5/11] Reiniciando WinDefend...")
    try {
        $null = & sc.exe stop WinDefend 2>&1
        Wait-WithDoEvents -Milliseconds 2000
        $null = & sc.exe start WinDefend 2>&1
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        Wait-WithDoEvents -Milliseconds 5000
    } catch { }

    [void]$log.Add("[6/11] Reintentando servicios fallidos...")
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

    [void]$log.Add("[7/11] Activando protecciones (Set-MpPreference, splatting)...")
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        $prefsOn = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                     "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                     "DisableEmailScanning","DisableIntrusionPreventionSystem",
                     "DisableRemovableDriveScanning","DisableScanningNetworkFiles",
                     "DisableCatchupQuickScan","DisableCatchupFullScan","DisableRestorePoint")
        $rtpActivo = $false; $pi = 0
        while (-not $rtpActivo -and $pi -lt 5) {
            $pi++
            $okPrefs = 0
            foreach ($p in $prefsOn) { if (Set-MpPrefValue -Nombre $p -Valor $false) { $okPrefs++ } }
            [void]$log.Add("       Intento ${pi}: $okPrefs de $($prefsOn.Count) preferencias forzadas a ON")
            try {
                Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
                Set-MpPreference -CloudBlockLevel High -ErrorAction SilentlyContinue
                Set-MpPreference -CloudExtendedTimeout 50 -ErrorAction SilentlyContinue
                Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue
                Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
                Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue
            } catch { }
            Wait-WithDoEvents -Milliseconds 3000
            try {
                $stCheck = Get-MpComputerStatus -ErrorAction Stop
                $rtpActivo = [bool]$stCheck.RealTimeProtectionEnabled
            } catch { }
            if (-not $rtpActivo) { Wait-WithDoEvents -Milliseconds 2000 }
        }
        if ($rtpActivo) {
            [void]$log.Add("       Protecciones ACTIVADAS (tiempo real confirmado).")
        } else {
            [void]$log.Add("       [!] Tiempo real aun no confirmado tras $pi intentos.")
        }
    }

    [void]$log.Add("[8/11] Tamper Protection...")
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
        if ($verify) { [void]$log.Add("       Tamper: ACTIVADO") } else { [void]$log.Add("       Tamper: RECHAZADO (activala en Seguridad de Windows)") }
    } catch { }

    [void]$log.Add("[9/11] Lanzando icono + gpupdate...")
    try {
        $systray = "$env:windir\System32\SecurityHealthSystray.exe"
        if (Test-Path $systray) { Start-Process -FilePath $systray -ErrorAction SilentlyContinue }
    } catch { }
    try { $null = & gpupdate.exe /force 2>&1 } catch { }
    Wait-WithDoEvents -Milliseconds 2000

    [void]$log.Add("[10/11] Verificacion final...")
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
    $startOk = $true
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        if ((Get-ServiceStartMode -Name $s) -eq "Disabled") { $startOk = $false }
    }

    [void]$log.Add("")
    [void]$log.Add("=== RESULTADO ===")
    if ($allRunning) { [void]$log.Add("  Servicios:   TODOS") } else { [void]$log.Add("  Servicios:   ALGUNOS FALLARON") }
    if ($procOk) { [void]$log.Add("  MsMpEng:     CORRIENDO") } else { [void]$log.Add("  MsMpEng:     DETENIDO") }
    if ($rtpOk) { [void]$log.Add("  Tiempo real: ACTIVADO") } else { [void]$log.Add("  Tiempo real: DESACTIVADO") }
    if ($antivirusOk) { [void]$log.Add("  Antivirus:   ACTIVADO") } else { [void]$log.Add("  Antivirus:   DESACTIVADO") }
    if ($startOk) { [void]$log.Add("  Servicios:   inicio automatico restaurado") } else { [void]$log.Add("  Servicios:   inicio aun deshabilitado") }

    [void]$log.Add("")
    if ($allRunning -and $procOk -and $rtpOk -and $antivirusOk -and $startOk) {
        [void]$log.Add("[OK] ACTIVACION TOTAL COMPLETADA. Defender esta 100% activado.")
    } elseif ($procOk -and $rtpOk) {
        [void]$log.Add("[OK] Activacion funcional. Reinicia para completar.")
    } else {
        [void]$log.Add("[!] Activacion parcial.")
    }

    $sw.Stop()
    [void]$log.Add("")
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Send-AllNotifications -Mensaje "Defender activado. Estado: $((Get-QuickStatus).Estado)" -Severidad "info" -Data @{ estado=(Get-QuickStatus).Estado }
    if ($script:CfgCloudBackup) { Backup-ToCloud }
    return ($log -join "`r`n")
}

# ============================================================================
# SECCION 47 - HISTORIAL + Add-HistoryDB (v8)
# ============================================================================
$script:EventHistory = New-Object System.Collections.ArrayList

function Load-History {
    try {
        if (Test-Path $script:HistoryFile) {
            $data = Get-Content -Path $script:HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data -is [array]) {
                foreach ($e in $data) {
                    [void]$script:EventHistory.Add([PSCustomObject]@{
                        Hora = [DateTime]$e.Hora
                        Accion = $e.Accion
                        Resultado = $e.Resultado
                        Segundos = [double]$e.Segundos
                    })
                }
            }
        }
    } catch { }
}

function Add-History {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    try {
        $entry = [PSCustomObject]@{ Hora = (Get-Date); Accion = $Accion; Resultado = $Resultado; Segundos = $Segundos }
        [void]$script:EventHistory.Insert(0, $entry)
        while ($script:EventHistory.Count -gt 100) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
        $script:EventHistory | ConvertTo-Json -Depth 3 | Set-Content -Path $script:HistoryFile -Encoding UTF8 -Force
    } catch { }
}

function Add-HistoryDB {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0, [string]$Detalle = "")
    Add-History -Accion $Accion -Resultado $Resultado -Segundos $Segundos
    if ($script:SqliteOk) {
        $null = Invoke-Sqlite "INSERT INTO Historial (Fecha,Usuario,Equipo,Accion,Resultado,Segundos,Detalle) VALUES (@f,@u,@eq,@a,@r,@s,@d)" @{
            f=(Get-Date).ToString("s"); u=(Get-CurrentUser); eq=$env:COMPUTERNAME
            a=$Accion; r=$Resultado; s=$Segundos; d=$Detalle
        }
    }
    $null = Invoke-Webhooks -Evento "action" -Payload @{ accion=$Accion; resultado=$Resultado; segundos=$Segundos; equipo=$env:COMPUTERNAME }
}

function Migrate-HistoryToSqlite {
    if (-not $script:SqliteOk) { return }
    try {
        $cnt = Invoke-Sqlite "SELECT COUNT(*) AS N FROM Historial"
        if ($cnt -and $cnt[0].N -gt 0) { return }
        foreach ($e in $script:EventHistory) {
            $null = Invoke-Sqlite "INSERT INTO Historial (Fecha,Usuario,Equipo,Accion,Resultado,Segundos) VALUES (@f,@u,@e,@a,@r,@s)" @{
                f = $e.Hora.ToString("s"); u = (Get-CurrentUser); e = $env:COMPUTERNAME
                a = $e.Accion; r = $e.Resultado; s = [double]$e.Segundos
            }
        }
        Write-AppLog "Historial migrado a SQLite ($($script:EventHistory.Count) registros)" "INFO"
    } catch { }
}

# ============================================================================
# SECCION 48 - DIAGNOSTICO
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
    [void]$r.Add([PSCustomObject]@{Item="  SQLite"; Status=$(if($script:SqliteOk){"OK"}else{"No"}); Detail=""; Color=$(if($script:SqliteOk){$script:Colors.Ok}else{$script:Colors.Warn})})

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

    [void]$r.Add([PSCustomObject]@{Item="=== SCRIPT v8.2 ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    [void]$r.Add([PSCustomObject]@{Item="  SHA256"; Status=(Get-ScriptHash); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Config"; Status="DPAPI"; Detail=$script:ConfigDir; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  REST"; Status=$(if($script:CfgRESTEnabled){"$($script:CfgRESTPort)"}else{"off"}); Detail=$(if($script:UseHTTPS){"HTTPS"}else{"HTTP"}); Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Telegram"; Status=$(if($script:CfgTelegramEnabled){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Firebase"; Status=$(if($script:CfgFCMEnabled){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Firmar Reportes"; Status=$(if($script:CfgSignReports){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Biometria"; Status=$(if($script:CfgBiometricKiosk){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Anomalias ML"; Status=$(if($script:CfgAnomalyEnabled){"ON"}else{"OFF"}); Detail="Z>$($script:CfgAnomalyZ)"; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Forense"; Status=$(if($script:CfgForensicMode){"ON"}else{"OFF"}); Detail=""; Color=$script:Colors.TextDiag})
    [void]$r.Add([PSCustomObject]@{Item="  Fleet"; Status=$(if($script:SqliteOk){"SQLite"}else{"off"}); Detail="$((Get-FleetComputers).Count) equipos"; Color=$script:Colors.TextDiag})
    $ad = Test-ADDisponible
    [void]$r.Add([PSCustomObject]@{Item="  AD"; Status=$(if($ad){"OK"}else{"No"}); Detail=""; Color=$(if($ad){$script:Colors.Ok}else{$script:Colors.Neutral})})
    $ev = Get-EVStatus
    [void]$r.Add([PSCustomObject]@{Item="  EV Cert"; Status=$(if($ev.EVDetectado){"Si"}else{"No"}); Detail=$ev.Detalles; Color=$(if($ev.EVDetectado){$script:Colors.Ok}else{$script:Colors.Neutral})})

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
    $lblH.Text = "DIAGNOSTICO COMPLETO v8.2"
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
    $btnAD = New-NeonButton "Active Directory" $script:Colors.AccentBlue $script:Colors.AccentBlueH 595 615 150 32
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 805 615 130 32
    $dlg.Controls.Add($btnRef); $dlg.Controls.Add($btnCopy); $dlg.Controls.Add($btnRep); $dlg.Controls.Add($btnEvents); $dlg.Controls.Add($btnAD); $dlg.Controls.Add($btnCerr)

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
        [void]$sb.AppendLine("DIAGNOSTICO - WINDOWS DEFENDER v8.2")
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
    $btnAD.Add_Click({ Show-ADDialog })
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 49 - EVENT LOG DIALOG
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
# SECCION 50 - HISTORIAL DIALOG (con Excel/CSV v8)
# ============================================================================
function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial"
    $dlg.ClientSize = New-Object System.Drawing.Size(850, 580)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    Center-FormOnActiveMonitor -Form $dlg

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "HISTORIAL v8.2"
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
    $lv.Size = New-Object System.Drawing.Size(820, 440)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 170)
    [void]$lv.Columns.Add("Accion", 150)
    [void]$lv.Columns.Add("Resultado", 350)
    [void]$lv.Columns.Add("Seg", 70)
    $dlg.Controls.Add($lv)

    $rows = $script:EventHistory
    if ($script:SqliteOk) {
        $dbRows = Invoke-Sqlite "SELECT Fecha,Accion,Resultado,Segundos FROM Historial ORDER BY Id DESC LIMIT 100"
        if ($dbRows) { $rows = $dbRows }
    }
    foreach ($e in $rows) {
        $hora = if ($e.Fecha) { [DateTime]::Parse($e.Fecha) } else { $e.Hora }
        $it = New-Object System.Windows.Forms.ListViewItem($hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$it.SubItems.Add($e.Accion)
        [void]$it.SubItems.Add($e.Resultado)
        [void]$it.SubItems.Add(("{0:N2}" -f [double]$e.Segundos))
        if ($e.Resultado -match "OK|activado|desactivado") { $it.ForeColor = $script:Colors.Ok }
        elseif ($e.Resultado -match "parcial|ERROR") { $it.ForeColor = $script:Colors.Bad }
        [void]$lv.Items.Add($it)
    }

    $btnExcel = New-NeonButton "Exportar Excel" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 520 170 34
    $btnCsv = New-NeonButton "Exportar CSV" $script:Colors.AccentCyan $script:Colors.AccentCyanH 195 520 150 34
    $btnClose = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 685 520 150 34
    $dlg.Controls.Add($btnExcel); $dlg.Controls.Add($btnCsv); $dlg.Controls.Add($btnClose)

    $btnExcel.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "Excel (*.xlsx)|*.xlsx"
        $sd.FileName = "Historial_{0:yyyyMMdd_HHmmss}.xlsx" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            if (Export-HistoryToExcel -Path $sd.FileName) {
                [System.Windows.Forms.MessageBox]::Show("Exportado: $($sd.FileName)","OK","OK","Information") | Out-Null
            }
        }
    })
    $btnCsv.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "CSV (*.csv)|*.csv"
        $sd.FileName = "Historial_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            if (Export-HistoryToCsv -Path $sd.FileName) {
                [System.Windows.Forms.MessageBox]::Show("Exportado: $($sd.FileName)","OK","OK","Information") | Out-Null
            }
        }
    })
    $btnClose.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 51 - DEEP REPAIR
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
    $dlg.ClientSize = New-Object System.Drawing.Size(960, 760)
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
    $lblH.Text = "REPARACION PROFUNDA v8.2"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblH)

    $console = New-Object System.Windows.Forms.TextBox
    $console.Multiline = $true; $console.ScrollBars = "Vertical"
    $console.WordWrap = $true; $console.AcceptsReturn = $true; $console.ReadOnly = $true
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.Location = New-Object System.Drawing.Point(15, 75)
    $console.Size = New-Object System.Drawing.Size(930, 490)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)
    $script:RepairConsole = $console

    $btnReg  = New-NeonButton "1. Borrar Politicas"    $script:Colors.AccentRed    $script:Colors.AccentRedH    15  580 165 34
    $btnSvc  = New-NeonButton "2. Servicios"           $script:Colors.AccentAmber  $script:Colors.AccentAmberH  190 580 175 34
    $btnGpu  = New-NeonButton "3. gpupdate"            $script:Colors.AccentPurple $script:Colors.AccentPurpH   375 580 130 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"        $script:Colors.AccentBlue   $script:Colors.AccentBlueH   515 580 140 34
    $btnDISM = New-NeonButton "5. DISM Restore"        $script:Colors.AccentCyan   $script:Colors.AccentCyanH   665 580 140 34
    $btnKill = New-NeonButton "Matar MsMpEng"          $script:Colors.AccentRed    $script:Colors.AccentRedH    815 580 130 34
    $btnFirmas = New-NeonButton "REPARAR FIRMAS"       $script:Colors.AccentGreen  $script:Colors.AccentGreenH  15  625 230 40
    $btnTodo   = New-NeonButton "REPARAR TODO"         $script:Colors.AccentGreen  $script:Colors.AccentGreenH  255 625 230 40
    $btnADInv  = New-NeonButton "AD Inventory"         $script:Colors.AccentBlue   $script:Colors.AccentBlueH   495 625 160 40
    $btnCert   = New-NeonButton "Guia Certificados"    $script:Colors.AccentPurple $script:Colors.AccentPurpH   665 625 160 40
    $btnCerr   = New-NeonButton "Cerrar"               $script:Colors.Neutral      $script:Colors.TextMuted     835 625 110 40

    foreach ($b in @($btnReg,$btnSvc,$btnGpu,$btnSFC,$btnDISM,$btnKill,$btnFirmas,$btnTodo,$btnADInv,$btnCert,$btnCerr)) { $dlg.Controls.Add($b) }

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
        Add-HistoryDB -Accion "Reparar Firmas" -Resultado "OK" -Segundos 0
    })
    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("==============================================`r`n")
        $c.AppendText("      REPARACION AUTOMATICA COMPLETA v8.2`r`n")
        $c.AppendText("==============================================`r`n")
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`" /f"
        Invoke-ConsoleCmd "gpupdate /force"
        foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
            Invoke-ConsoleCmd "sc config $s start= auto"
            Invoke-ConsoleCmd "sc start $s"
        }
        try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue } catch { }
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Invoke-ConsoleCmd "sfc /scannow"
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("`r`n[OK] REINICIA EL EQUIPO.`r`n")
        Add-HistoryDB -Accion "Reparacion Completa" -Resultado "OK" -Segundos 0
    })
    $btnADInv.Add_Click({ Show-ADDialog })
    $btnCert.Add_Click({ Show-CertificateGuide })
    $btnCerr.Add_Click({ $dlg.Close() })

    $console.AppendText("Consola de reparacion v8.2 lista.`r`n")
    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ============================================================================
# SECCION 52 - SCHEDULER
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
# SECCION 53 - SERVICE INSTALL
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
# SECCION 54 - KIOSCO PASSWORD
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
# SECCION 55 - CONFIGURACION v8.2 COMPLETA
# ============================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion v8.2"
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 900)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.MinimumSize = New-Object System.Drawing.Size(720, 500)
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "CONFIGURACION v8.2 ULTIMATE"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    # Panel con scroll
    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location = New-Object System.Drawing.Point(0, 50)
    $scrollPanel.Size = New-Object System.Drawing.Size(720, 800)
    $scrollPanel.AutoScroll = $true
    $scrollPanel.Anchor = "Top,Left,Right,Bottom"
    $scrollPanel.BackColor = $script:Colors.Bg
    $dlg.Controls.Add($scrollPanel)

    $y = 10
    function New-CheckBox($Texto, $Checked, $Y, $Parent) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $Texto; $c.Checked = $Checked
        $c.Location = New-Object System.Drawing.Point(20, $Y)
        $c.Size = New-Object System.Drawing.Size(650, 25)
        $c.ForeColor = $script:Colors.Text
        $Parent.Controls.Add($c)
        return $c
    }

    # --- Checks basicos ---
    $chkAutoRepair      = New-CheckBox "Auto-reparar firmas al iniciar (>30 dias)" $script:CfgAutoRepair $y $scrollPanel; $y += 25
    $chkAutoCleanup     = New-CheckBox "Limpiar logs de mas de 30 dias" $script:CfgAutoCleanup $y $scrollPanel; $y += 25
    $chkThemeFollow     = New-CheckBox "Seguir tema del sistema automaticamente" $script:CfgThemeFollow $y $scrollPanel; $y += 25
    $chkThresholdAlert  = New-CheckBox "Alertar si Defender lleva >X horas desactivado" $script:CfgThresholdAlert $y $scrollPanel; $y += 25
    $chkResidentAgent   = New-CheckBox "Agente residente (monitor WMI de cambios)" $script:CfgResidentAgent $y $scrollPanel; $y += 25
    $chkREST            = New-CheckBox "API REST local" $script:CfgRESTEnabled $y $scrollPanel; $y += 25
    $chkKiosk           = New-CheckBox ("Modo kiosco (pedir " + (T "Password") + ")") $script:IsKioskMode $y $scrollPanel; $y += 25
    $chkEmail           = New-CheckBox "Enviar reportes por email (SMTP)" $script:CfgEmailEnabled $y $scrollPanel; $y += 25
    $chkTelegram        = New-CheckBox "Notificaciones por Telegram" $script:CfgTelegramEnabled $y $scrollPanel; $y += 25
    $chkForensic        = New-CheckBox "Modo forense (screenshot antes de cambios)" $script:CfgForensicMode $y $scrollPanel; $y += 25
    $chkMultiMon        = New-CheckBox "Abrir dialogos en el monitor activo" $script:CfgMultiMonitor $y $scrollPanel; $y += 25
    $chkParental        = New-CheckBox "Modo tutela (bloqueo parental)" $script:CfgParentalMode $y $scrollPanel; $y += 25
    $chkCloud           = New-CheckBox "Backup automatico a la nube" $script:CfgCloudBackup $y $scrollPanel; $y += 25
    $chkHTTPS           = New-CheckBox "Usar HTTPS en API REST (requiere reinicio)" $script:UseHTTPS $y $scrollPanel; $y += 25

    # --- v8.1 checks ---
    $chkSignReports     = New-CheckBox "Firmar reportes con Authenticode" $script:CfgSignReports $y $scrollPanel; $y += 25
    $chkBiometricKiosk  = New-CheckBox "Kiosco biometrico (Windows Hello)" $script:CfgBiometricKiosk $y $scrollPanel; $y += 25
    $chkFCM             = New-CheckBox "Notificaciones Push Firebase (FCM v1)" $script:CfgFCMEnabled $y $scrollPanel; $y += 25
    $chkAnomaly         = New-CheckBox "Deteccion de anomalias (ML Z-score)" $script:CfgAnomalyEnabled $y $scrollPanel; $y += 25
    $y += 10

    # Helper: label + textbox
    function New-FormField {
        param($Parent, $Label, $Value, [ref]$YRef)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Label; $lbl.ForeColor = $script:Colors.Text
        $lbl.Location = New-Object System.Drawing.Point(20, $YRef.Value); $lbl.Size = New-Object System.Drawing.Size(160, 25)
        $Parent.Controls.Add($lbl)
        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = $Value
        $txt.Location = New-Object System.Drawing.Point(185, $YRef.Value); $txt.Size = New-Object System.Drawing.Size(480, 25)
        $txt.BackColor = $script:Colors.BgSecondary; $txt.ForeColor = $script:Colors.Text
        $Parent.Controls.Add($txt)
        $YRef.Value += 30
        return $txt
    }

    # --- Password ---
    $txtPwd = New-FormField $scrollPanel ((T "Password") + ":") "" ([ref]$y)

    # --- Telegram ---
    $txtTgToken = New-FormField $scrollPanel "Telegram Token:" $script:CfgTelegramToken ([ref]$y)
    $txtTgChat = New-FormField $scrollPanel "Telegram Chat ID:" $script:CfgTelegramChatId ([ref]$y)

    # --- FCM ---
    $txtFCMProj = New-FormField $scrollPanel "FCM Project ID:" $script:CfgFCMProjectId ([ref]$y)

    # FCM Service JSON con browse
    $lblFCMJson = New-Object System.Windows.Forms.Label
    $lblFCMJson.Text = "Service Account JSON:"; $lblFCMJson.ForeColor = $script:Colors.Text
    $lblFCMJson.Location = New-Object System.Drawing.Point(20, $y); $lblFCMJson.Size = New-Object System.Drawing.Size(160, 25)
    $scrollPanel.Controls.Add($lblFCMJson)
    $txtFCMJson = New-Object System.Windows.Forms.TextBox
    $txtFCMJson.Text = $script:CfgFCMServiceJson
    $txtFCMJson.Location = New-Object System.Drawing.Point(185, $y); $txtFCMJson.Size = New-Object System.Drawing.Size(420, 25)
    $txtFCMJson.BackColor = $script:Colors.BgSecondary; $txtFCMJson.ForeColor = $script:Colors.Text
    $scrollPanel.Controls.Add($txtFCMJson)
    $btnBrowseJson = New-Object System.Windows.Forms.Button
    $btnBrowseJson.Text = "..."; $btnBrowseJson.Location = New-Object System.Drawing.Point(610, $y)
    $btnBrowseJson.Size = New-Object System.Drawing.Size(55, 25)
    $btnBrowseJson.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "JSON (*.json)|*.json"
        if ($ofd.ShowDialog() -eq "OK") { $txtFCMJson.Text = $ofd.FileName }
    })
    $scrollPanel.Controls.Add($btnBrowseJson)
    $y += 30

    # --- Cloud ---
    $txtCloud = New-FormField $scrollPanel "Ruta nube:" $script:CfgCloudPath ([ref]$y)

    # --- GitHub ---
    $txtGitHub = New-FormField $scrollPanel "GitHub Repo (user/repo):" $script:CfgGitHubRepo ([ref]$y)
    $y += 10

    # --- Botones fila 1 ---
    $btnSave      = New-NeonButton "Guardar"            $script:Colors.AccentGreen  $script:Colors.AccentGreenH  20  $y 140 34
    $btnCancel    = New-NeonButton "Cancelar"           $script:Colors.Neutral      $script:Colors.TextMuted    170 $y 140 34
    $btnInstall   = New-NeonButton "Instalar Servicio"  $script:Colors.AccentPurple $script:Colors.AccentPurpH  320 $y 160 34
    $btnUninstall = New-NeonButton "Desinstalar"        $script:Colors.AccentRed    $script:Colors.AccentRedH   490 $y 180 34
    $scrollPanel.Controls.Add($btnSave); $scrollPanel.Controls.Add($btnCancel)
    $scrollPanel.Controls.Add($btnInstall); $scrollPanel.Controls.Add($btnUninstall)
    $y += 45

    # --- Botones fila 2 ---
    $btnScheduler   = New-NeonButton "Programar Tareas"   $script:Colors.AccentAmber  $script:Colors.AccentAmberH 20  $y 200 34
    $btnRestoreReg  = New-NeonButton "Restaurar Registro" $script:Colors.AccentAmber  $script:Colors.AccentAmberH 230 $y 200 34
    $btnTestTelegram= New-NeonButton "Probar Telegram"    $script:Colors.AccentCyan   $script:Colors.AccentCyanH  440 $y 200 34
    $scrollPanel.Controls.Add($btnScheduler); $scrollPanel.Controls.Add($btnRestoreReg); $scrollPanel.Controls.Add($btnTestTelegram)
    $y += 45

    # --- Botones fila 3 (v8) ---
    $btnExportExcel = New-NeonButton "Exportar Excel"    $script:Colors.AccentGreen $script:Colors.AccentGreenH 20  $y 200 34
    $btnExportCsv   = New-NeonButton "Exportar CSV"      $script:Colors.AccentCyan  $script:Colors.AccentCyanH  230 $y 200 34
    $btnCheckUpdate = New-NeonButton "Buscar Update"     $script:Colors.AccentPurple $script:Colors.AccentPurpH 440 $y 200 34
    $scrollPanel.Controls.Add($btnExportExcel); $scrollPanel.Controls.Add($btnExportCsv); $scrollPanel.Controls.Add($btnCheckUpdate)
    $y += 45

    # --- Botones fila 4 (v8) ---
    $btnMSI         = New-NeonButton "Generar MSI"       $script:Colors.AccentAmber $script:Colors.AccentAmberH 20  $y 200 34
    $btnDocker      = New-NeonButton "Generar Docker"    $script:Colors.AccentBlue  $script:Colors.AccentBlueH  230 $y 200 34
    $btnCertGuide   = New-NeonButton "Guia Certificados" $script:Colors.AccentCyan  $script:Colors.AccentCyanH  440 $y 200 34
    $scrollPanel.Controls.Add($btnMSI); $scrollPanel.Controls.Add($btnDocker); $scrollPanel.Controls.Add($btnCertGuide)
    $y += 45

    # --- Botones fila 5 (v8) ---
    $btnADInv       = New-NeonButton "Active Directory"  $script:Colors.AccentBlue  $script:Colors.AccentBlueH  20  $y 200 34
    $btnAnomalyTest = New-NeonButton "Probar Anomalias"  $script:Colors.AccentPurple $script:Colors.AccentPurpH 230 $y 200 34
    $btnCloseBottom = New-NeonButton "Cerrar"            $script:Colors.Neutral     $script:Colors.TextMuted    440 $y 200 34
    $scrollPanel.Controls.Add($btnADInv); $scrollPanel.Controls.Add($btnAnomalyTest); $scrollPanel.Controls.Add($btnCloseBottom)

    # --- Handlers ---
    $btnSave.Add_Click({
        $script:CfgAutoRepair      = $chkAutoRepair.Checked
        $script:CfgAutoCleanup     = $chkAutoCleanup.Checked
        $script:CfgThemeFollow     = $chkThemeFollow.Checked
        $script:CfgThresholdAlert  = $chkThresholdAlert.Checked
        $script:CfgResidentAgent   = $chkResidentAgent.Checked
        $script:CfgRESTEnabled     = $chkREST.Checked
        $script:CfgEmailEnabled    = $chkEmail.Checked
        $script:CfgTelegramEnabled = $chkTelegram.Checked
        $script:CfgForensicMode    = $chkForensic.Checked
        $script:CfgMultiMonitor    = $chkMultiMon.Checked
        $script:CfgParentalMode    = $chkParental.Checked
        $script:CfgCloudBackup     = $chkCloud.Checked
        $script:UseHTTPS           = $chkHTTPS.Checked
        $script:UseHTTP            = -not $chkHTTPS.Checked
        $script:CfgSignReports     = $chkSignReports.Checked
        $script:CfgBiometricKiosk  = $chkBiometricKiosk.Checked
        $script:CfgFCMEnabled      = $chkFCM.Checked
        $script:CfgAnomalyEnabled  = $chkAnomaly.Checked
        $script:CfgTelegramToken   = $txtTgToken.Text
        $script:CfgTelegramChatId  = $txtTgChat.Text
        $script:CfgFCMProjectId    = $txtFCMProj.Text
        $script:CfgFCMServiceJson  = $txtFCMJson.Text
        $script:CfgCloudPath       = $txtCloud.Text
        $script:CfgGitHubRepo      = $txtGitHub.Text
        $script:IsKioskMode        = $chkKiosk.Checked
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
        $ok = Send-TelegramNotification "Test desde DefenderTray v8.2"
        if ($ok) { [System.Windows.Forms.MessageBox]::Show("Enviado.","OK","OK","Information") | Out-Null }
        else { [System.Windows.Forms.MessageBox]::Show("Fallo. Revisa token y chat id.","Error","OK","Error") | Out-Null }
    })
    $btnExportExcel.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "Excel (*.xlsx)|*.xlsx"
        $sd.FileName = "Historial_{0:yyyyMMdd_HHmmss}.xlsx" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            if (Export-HistoryToExcel -Path $sd.FileName) {
                [System.Windows.Forms.MessageBox]::Show("Exportado: $($sd.FileName)","OK","OK","Information") | Out-Null
            }
        }
    })
    $btnExportCsv.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "CSV (*.csv)|*.csv"
        $sd.FileName = "Historial_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            if (Export-HistoryToCsv -Path $sd.FileName) {
                [System.Windows.Forms.MessageBox]::Show("Exportado: $($sd.FileName)","OK","OK","Information") | Out-Null
            }
        }
    })
    $btnCheckUpdate.Add_Click({ Show-UpdateDialog })
    $btnMSI.Add_Click({
        $res = New-WixInstallerPackage
        [System.Windows.Forms.MessageBox]::Show($res,"MSI","OK","Information") | Out-Null
    })
    $btnDocker.Add_Click({
        $res = New-DockerPackage
        [System.Windows.Forms.MessageBox]::Show($res,"Docker","OK","Information") | Out-Null
    })
    $btnCertGuide.Add_Click({ Show-CertificateGuide })
    $btnADInv.Add_Click({ Show-ADDialog })
    $btnAnomalyTest.Add_Click({
        $m = Get-SystemMetrics
        $msg = "Metricas actuales:`r`n"
        foreach ($k in $m.Keys) { $msg += "  $k = $($m[$k])`r`n" }
        $msg += "`r`nAnomalias:"
        $found = $false
        foreach ($k in $m.Keys) {
            $a = Test-Anomaly -Metrica $k -Valor $m[$k]
            if ($a) { $msg += "`r`n  [ANOMALIA] $k Z=$($a.Z) Severidad=$($a.Severidad)"; $found = $true }
        }
        if (-not $found) { $msg += "`r`n  (ninguna detectada)" }
        Show-ResultDialog -Titulo "Test Anomalias ML" -Mensaje (Normalize-LineEndings $msg) -Tipo "Info"
    })
    $btnCloseBottom.Add_Click({ $dlg.Close() })

    Center-FormOnActiveMonitor -Form $dlg
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 56 - AYUDA
# ============================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(820, 660)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "AYUDA - v8.2 ULTIMATE"
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
    $txt.Size = New-Object System.Drawing.Size(790, 540)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.Anchor = "Top,Left,Right,Bottom"
    $txt.Text = (Normalize-LineEndings @'
DEFENDER CONTROL v8.2 ULTIMATE
================================

NOVEDADES v8.2
--------------
 1. UN SOLO CLIC: activar/desactivar completo, sin confirmaciones
 2. Desactivacion TOTAL (fix de Set-MpPreference: 15+ protecciones)
 3. Activacion TOTAL con verificacion de tiempo real
 4. Tamper Protection guiada (ya no bloquea la operacion)
 5. Estado real DESACTIVADO + aviso de reinicio pendiente
 6. Politicas completas: ExploitGuard, PUA, SmartScreen, RTP
 7. CLI: -action toggle

Hereda de la v8.1: SQLite cifrado, MSI WiX, FCM v1, Fleet Console,
ML Z-score, Active Directory, GraphQL, PWA, kiosco biometrico,
webhooks, Excel/CSV, Dashboard SSE, auto-update y Docker.

ENDPOINTS REST/GRAPHQL
----------------------
Por defecto: http://127.0.0.1:9182
Con HTTPS:   https://127.0.0.1:9182

  GET  /                -> Dashboard tiempo real
  GET  /status          -> Estado JSON
  GET  /enable          -> Instrucciones activar
  GET  /disable         -> Instrucciones desactivar
  GET  /emergency       -> Activacion inmediata
  GET  /diagnostic      -> Info general
  GET  /fleet           -> Fleet Console HTML
  GET  /fleet/computers -> Equipos registrados
  POST /fleet/command   -> Enviar comando {host,action}
  POST /fleet/broadcast -> Comando a todos {action}
  POST /graphql         -> Query GraphQL {"query":"..."}
  GET  /sse/stream      -> Server-Sent Events
  GET  /pwa/            -> PWA instalable
  GET  /pwa/manifest.json
  GET  /pwa/sw.js
  GET  /pwa/icon-192.png

EJEMPLO GRAPHQL
---------------
  POST http://127.0.0.1:9182/graphql
  Body: {"query":"{ status { estado servicio motor } }"}

AUTO-UPDATE
-----------
1. Sube el script a GitHub Releases (tag v8.2)
2. Añade asset .ps1 + .sha256 (opcional)
3. Settings -> Buscar Update

DOCKER
------
New-DockerPackage genera:
  Dockerfile
  docker-compose.yml
  README.md
Uso: docker-compose up -d --build

FIRMA EV
--------
Ver Settings -> Guia Certificados
Requiere cert EV + token USB SafeNet

ARGUMENTOS
----------
  -silent     Sin dialogos
  -portable   Datos en carpeta del script
  -audit      Solo registra, no aplica
  -norest     Sin API REST
  -https      Usar HTTPS (autofirmado)
  -action     enable | disable
  -autoupdate Solo verifica update

ATAJOS
------
  F1   Ayuda
  F5   Refrescar
  Esc  Cerrar

(c) 2026 - Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801 / +53 5 9860911
'@)
    $dlg.Controls.Add($txt)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 660 615 145 30
    $btnCerr.Anchor = "Bottom,Right"
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    Center-FormOnActiveMonitor -Form $dlg
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 57 - ESTADISTICAS
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
    Center-FormOnActiveMonitor -Form $dlg
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ============================================================================
# SECCION 58 - PANEL PRINCIPAL
# ============================================================================
$script:PanelForm          = $null
$script:PanelHeader        = $null
$script:PanelLblValor      = $null
$script:PanelLblDet1       = $null
$script:PanelLblDet2       = $null
$script:PanelLblDet3       = $null
$script:PanelLblReloj      = $null
$script:PanelLblTimer      = $null
$script:PanelBtnToggle      = $null
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
                if ($b.Tag) {
                    $b.BackColor = $b.Tag.Normal
                    $b.ForeColor = [System.Drawing.Color]::White
                    $b.Cursor = "Hand"
                }
            }
        }
    }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

function Set-ToggleButtonLook {
    # v8.2: el boton unico adapta texto y color a la accion que disparara.
    param([string]$Modo)
    $b = $script:PanelBtnToggle
    if ($null -eq $b) { return }
    $txt = T "ToggleDisable"; $n = $script:Colors.AccentRed; $h = $script:Colors.AccentRedH
    if ($Modo -eq "Enable") { $txt = T "ToggleEnable"; $n = $script:Colors.AccentGreen; $h = $script:Colors.AccentGreenH }
    elseif ($Modo -eq "FinishOff") { $txt = T "ToggleFinishOff"; $n = $script:Colors.AccentAmber; $h = $script:Colors.AccentAmberH }
    elseif ($Modo -eq "FinishOn") { $txt = T "ToggleFinishOn"; $n = $script:Colors.AccentAmber; $h = $script:Colors.AccentAmberH }
    $b.Text = $txt
    $b.Tag = @{ Normal = $n; Hover = $h }
    try { Set-NeonButtonState -Boton $b -Habilitado (-not $script:IsBusy) } catch { }
}

function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $s = Get-QuickStatus
    $diag = "Svc:$($s.ServiceRunning) | Motor:$($s.EngineRunning) | RTP:$($s.RealTimeProtectionEnabled) | Pol:$($s.HasPolicy)"
    if ($s.PendingReboot) { $diag = "$diag | REINICIO PENDIENTE" }

    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-ToggleButtonLook -Modo "Disable"
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "ACTIVADO"; $script:PanelStatusLabel.ForeColor = $script:Colors.Ok }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        if ($s.HasPolicy -or $s.ServicesDisabled) {
            $script:PanelLblDet1.Text = "Usa ACTIVAR para restaurar o UN CLIC para seguir desactivando."
            Set-ToggleButtonLook -Modo "FinishOff"
        } else {
            $script:PanelLblDet1.Text = "Usa ACTIVAR para restaurar o UN CLIC para terminar de activar."
            Set-ToggleButtonLook -Modo "FinishOn"
        }
        $script:PanelLblDet2.Text = $diag
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "PARCIAL"; $script:PanelStatusLabel.ForeColor = $script:Colors.Warn }
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        if ($s.PendingReboot) {
            $script:PanelLblDet1.Text = "Desactivado al 100%. Reinicia el equipo para hacerlo efectivo."
        } else {
            $script:PanelLblDet1.Text = "El antivirus esta inactivo."
        }
        $script:PanelLblDet2.Text = $diag
        Set-ToggleButtonLook -Modo "Enable"
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
    if (-not (Test-KioskAuth)) { return }

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
    $miAlternar = New-Object System.Windows.Forms.ToolStripMenuItem; $miAlternar.Text = "Alternar ON/OFF (1 clic)"
    $miAlternar.Add_Click({ Invoke-ToggleProtection })
    $miAct = New-Object System.Windows.Forms.ToolStripMenuItem; $miAct.Text = "Activar"
    $miAct.Add_Click({ Invoke-EnableProtection -Accion "Activar" })
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
            Add-HistoryDB -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
        } finally { $script:IsBusy = $false; Stop-ActionTimer | Out-Null; Set-PanelBusy $false }
    })
    $miEmerg = New-Object System.Windows.Forms.ToolStripMenuItem; $miEmerg.Text = "EMERGENCIA"
    $miEmerg.Add_Click({ Invoke-EmergencyActivation })
    $miVer = New-Object System.Windows.Forms.ToolStripMenuItem; $miVer.Text = "Verificar"; $miVer.Add_Click({ Show-DiagnosticsDialog })
    [void]$mAcciones.DropDownItems.Add($miAlternar)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
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
    $miFleet = New-Object System.Windows.Forms.ToolStripMenuItem; $miFleet.Text = "Fleet Console"; $miFleet.Add_Click({
        try { Start-Process "http://127.0.0.1:$($script:CfgRESTPort)/fleet" } catch { }
    })
    $miAD = New-Object System.Windows.Forms.ToolStripMenuItem; $miAD.Text = "Active Directory"; $miAD.Add_Click({ Show-ADDialog })
    $miConf = New-Object System.Windows.Forms.ToolStripMenuItem; $miConf.Text = "Configuracion"; $miConf.Add_Click({ Show-SettingsDialog })
    [void]$mHerram.DropDownItems.Add($miRep)
    [void]$mHerram.DropDownItems.Add($miHist)
    [void]$mHerram.DropDownItems.Add($miStats)
    [void]$mHerram.DropDownItems.Add($miEvents)
    [void]$mHerram.DropDownItems.Add($miFleet)
    [void]$mHerram.DropDownItems.Add($miAD)
    [void]$mHerram.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHerram.DropDownItems.Add($miConf)

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"; $mAyuda.ForeColor = $script:Colors.Text
    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem; $miAy.Text = "Ayuda (F1)"; $miAy.Add_Click({ Show-HelpDialog })
    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem; $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v8.2 ULTIMATE`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911`n`nSistema: $($script:OSProductType)`nSHA256: $($script:ScriptHash)"
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
    $lblSubH.Text = "v8.2 ULTIMATE - $($script:OSProductType)"
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
    $btnToggle      = New-NeonButton (T "ToggleDisable") $script:Colors.AccentRed    $script:Colors.AccentRedH   15  282 470 42
    $btnActivate    = New-NeonButton (T "Activar")       $script:Colors.AccentGreen  $script:Colors.AccentGreenH 15  327 470 36
    $btnReparar     = New-NeonButton (T "Reparar")      $script:Colors.AccentAmber  $script:Colors.AccentAmberH 15  368 470 36
    $btnEmerg       = New-NeonButton (T "Emergencia")   $script:Colors.AccentRed    $script:Colors.AccentRedH   15  409 230 32
    $btnEventos     = New-NeonButton "Event Log"        $script:Colors.AccentPurple $script:Colors.AccentPurpH  255 409 230 32
    $btnHistorial   = New-NeonButton (T "Historial")    $script:Colors.AccentBlue   $script:Colors.AccentBlueH  15  448 110 32
    $btnConfig      = New-NeonButton (T "Config")       $script:Colors.AccentBlue   $script:Colors.AccentBlueH  135 448 110 32
    $btnAyuda       = New-NeonButton (T "Ayuda")        $script:Colors.AccentBlue   $script:Colors.AccentBlueH  255 448 110 32
    $btnSalir       = New-NeonButton (T "Salir")        $script:Colors.AccentRed    $script:Colors.AccentRedH   375 448 110 32

    $script:PanelAllButtons = @($btnDiagnostico,$btnToggle,$btnActivate,$btnReparar,$btnEmerg,$btnEventos,$btnHistorial,$btnConfig,$btnAyuda,$btnSalir)
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

    $script:PanelForm = $form
    $script:PanelHeader = $header
    $script:PanelLblValor = $lblValor
    $script:PanelLblDet1 = $lblDet1
    $script:PanelLblDet2 = $lblDet2
    $script:PanelLblDet3 = $lblDet3
    $script:PanelLblReloj = $lblReloj
    $script:PanelLblTimer = $lblTimer
    $script:PanelBtnToggle = $btnToggle

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
    $btnActivate.Add_Click({ Invoke-EnableProtection -Accion "Activar" })

    $btnToggle.Add_Click({ Invoke-ToggleProtection })

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
# SECCION 59 - REST API v8.2 COMPLETA
# ============================================================================
$script:RESTJob = $null

function Initialize-RESTApi {
    if (-not $script:CfgRESTEnabled) { return }
    if ($null -ne $script:RESTJob -and $script:RESTJob.State -eq 'Running') { return }

    $puerto = $script:CfgRESTPort
    $protocolo = if ($script:UseHTTPS) { "https" } else { "http" }
    $prefix = "${protocolo}://127.0.0.1:${puerto}/"

    if (Test-Admin) {
        try {
            $null = & netsh.exe http delete urlacl url="$prefix" 2>&1
            $null = & netsh.exe http add urlacl url="$prefix" user="$env:USERDOMAIN\$env:USERNAME" 2>&1
            Write-AppLog "URL ACL reservada: $prefix" "INFO"
        } catch { Write-AppLog "URL ACL error: $($_.Exception.Message)" "WARN" }
    }

    if ($script:UseHTTPS -and (Test-Admin)) {
        try {
            $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=DefenderTray Localhost" } | Select-Object -First 1
            if ($null -eq $cert) {
                $cert = New-SelfSignedCertificate -DnsName "127.0.0.1","localhost" -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "DefenderTray Localhost" -NotAfter (Get-Date).AddYears(5)
            }
            $null = & netsh.exe http delete sslcert ipport="127.0.0.1:$puerto" 2>&1
            $null = & netsh.exe http add sslcert ipport="127.0.0.1:$puerto" certhash="$($cert.Thumbprint)" appid="{00112233-4455-6677-8899-aabbccddeeff}" 2>&1
            Write-AppLog "HTTPS bind OK cert=$($cert.Thumbprint)" "INFO"
        } catch {
            Write-AppLog "Error HTTPS bind: $($_.Exception.Message)" "WARN"
            $script:UseHTTPS = $false
            $protocolo = "http"; $prefix = "http://127.0.0.1:${puerto}/"
        }
    }

    # Preparar recursos
    $htmlDashboard = Get-SSEDashboardHtml
    $htmlPwa = Get-PWAHtml
    $pwaManifest = Get-PWAManifest
    $pwaSw = Get-PWAServiceWorker
    $fleetHtml = Get-FleetHtmlConsole
    $icon192 = $null; $icon512 = $null
    try { $icon192 = Get-PWAIcon -Size 192 } catch { }
    try { $icon512 = Get-PWAIcon -Size 512 } catch { }

    $script:RESTJob = Start-Job -ScriptBlock {
        param($Puerto,$Protocolo,$ScriptPath,$HtmlDash,$HtmlPwa,$Manifest,$Sw,$Icon192,$Icon512,$Fleet)

        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("${Protocolo}://127.0.0.1:${Puerto}/")
        try { $listener.Start() } catch { return "ERR: $($_.Exception.Message)" }

        # Fallback PNG 1x1 transparente
        $fallbackPng = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

        function Get-StatusJson {
            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
            $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
            $rtp = "DESCONOCIDO"
            try { $rtp = if((Get-MpComputerStatus).RealTimeProtectionEnabled){"ACTIVADO"}else{"DESACTIVADO"} } catch { }
            $estado = if ($svc -and $svc.Status -eq "Running" -and $null -ne $proc -and $rtp -eq "ACTIVADO") {"ACTIVO"}
                      elseif ($null -eq $proc) {"DESACTIVADO"}
                      else {"PARCIAL"}
            return @{
                estado = $estado
                servicio = if ($svc) { $svc.Status.ToString() } else { "Unknown" }
                motor = if ($proc) { "Running" } else { "Stopped" }
                tiempoReal = $rtp
                fecha = (Get-Date).ToString("s")
                host = $env:COMPUTERNAME
            }
        }

        while ($listener.IsListening) {
            try {
                $ctx = $listener.GetContext()
                $req = $ctx.Request
                $res = $ctx.Response
                $path = $req.Url.AbsolutePath.ToLower()
                $method = $req.HttpMethod.ToUpper()
                $body = ""
                $ct = "application/json"
                $skipGeneric = $false

                switch -Regex ($path) {
                    "^/$"              { $body = $HtmlDash; $ct = "text/html; charset=utf-8" }
                    "^/pwa/?$"         { $body = $HtmlPwa; $ct = "text/html; charset=utf-8" }
                    "^/pwa/manifest\.json$" { $body = $Manifest; $ct = "application/manifest+json" }
                    "^/pwa/sw\.js$"    { $body = $Sw; $ct = "application/javascript" }
                    "^/pwa/icon-192\.png$" {
                        $img = if ($Icon192) { $Icon192 } else { $fallbackPng }
                        $res.ContentType = "image/png"
                        $res.ContentLength64 = $img.Length
                        $res.OutputStream.Write($img, 0, $img.Length)
                        $res.Close()
                        $skipGeneric = $true
                    }
                    "^/pwa/icon-512\.png$" {
                        $img = if ($Icon512) { $Icon512 } else { $fallbackPng }
                        $res.ContentType = "image/png"
                        $res.ContentLength64 = $img.Length
                        $res.OutputStream.Write($img, 0, $img.Length)
                        $res.Close()
                        $skipGeneric = $true
                    }
                    "^/fleet/?$"       { $body = $Fleet; $ct = "text/html; charset=utf-8" }
                    "^/status$"        { $body = (Get-StatusJson) | ConvertTo-Json }
                    "^/enable$"        { $body = @{ result = "powershell -File '$ScriptPath' -silent -action enable" } | ConvertTo-Json }
                    "^/disable$"       { $body = @{ result = "powershell -File '$ScriptPath' -silent -action disable" } | ConvertTo-Json }
                    "^/emergency$"     {
                        Start-Process powershell -ArgumentList "-File `"$ScriptPath`" -silent -action enable" -WindowStyle Hidden
                        $body = @{ result = "Activacion de emergencia lanzada" } | ConvertTo-Json
                    }
                    "^/diagnostic$"    {
                        $body = @{
                            version = "8.2"
                            autor = "Ing. Yosvany Hernandez Quintero"
                            movil = "+53 5 2160801 / +53 5 9860911"
                            fecha = (Get-Date).ToString("s")
                            sqlite = $true; fleet = $true; graphql = $true; sse = $true; pwa = $true
                        } | ConvertTo-Json
                    }
                    "^/fleet/computers$" {
                        $st = Get-StatusJson
                        $body = @(@{
                            Nombre = $env:COMPUTERNAME
                            IP = "127.0.0.1"
                            Version = "8.2"
                            Estado = $st.estado
                            UltimoContacto = $st.fecha
                        }) | ConvertTo-Json
                    }
                    "^/fleet/command$" {
                        try {
                            $rd = New-Object IO.StreamReader($req.InputStream); $raw = $rd.ReadToEnd(); $rd.Close()
                            $data = $raw | ConvertFrom-Json
                            Start-Process powershell -ArgumentList "-File `"$ScriptPath`" -silent -action $($data.action)" -WindowStyle Hidden
                            $body = @{ result = "Comando $($data.action) enviado a $($data.host)" } | ConvertTo-Json
                        } catch { $body = @{ error = $_.Exception.Message } | ConvertTo-Json }
                    }
                    "^/fleet/broadcast$" {
                        try {
                            $rd = New-Object IO.StreamReader($req.InputStream); $raw = $rd.ReadToEnd(); $rd.Close()
                            $data = $raw | ConvertFrom-Json
                            $body = @{ result = "Broadcast $($data.action) enviado" } | ConvertTo-Json
                        } catch { $body = @{ error = $_.Exception.Message } | ConvertTo-Json }
                    }
                    "^/graphql$" {
                        try {
                            $rd = New-Object IO.StreamReader($req.InputStream); $raw = $rd.ReadToEnd(); $rd.Close()
                            $obj = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                            $queryStr = if ($obj.query) { $obj.query } else { $raw }
                            $data = @{}
                            if ($queryStr -match "status") {
                                $st = Get-StatusJson
                                $data.status = @{ estado=$st.estado; servicio=$st.servicio; motor=$st.motor; tiempoReal=$st.tiempoReal }
                            }
                            if ($queryStr -match "equipos|fleet") {
                                $data.equipos = @(@{ Nombre=$env:COMPUTERNAME; Estado=(Get-StatusJson).estado })
                            }
                            if ($queryStr -match "config") {
                                $data.config = @{ version="8.2"; host=$env:COMPUTERNAME }
                            }
                            $body = @{ data = $data; errors = @() } | ConvertTo-Json -Depth 8 -Compress
                        } catch { $body = @{ data=$null; errors=@($_.Exception.Message) } | ConvertTo-Json }
                    }
                    "^/sse/stream$" {
                        $res.ContentType = "text/event-stream"
                        $res.Headers.Add("Cache-Control", "no-cache")
                        $res.Headers.Add("Access-Control-Allow-Origin", "*")
                        $st = Get-StatusJson
                        $data = @{ estado=$st.estado; servicio=$st.servicio; motor=$st.motor; tiempoReal=$st.tiempoReal } | ConvertTo-Json -Compress
                        $msg = "event: status`ndata: $data`n`n"
                        $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
                        $res.ContentLength64 = $bytes.Length
                        $res.OutputStream.Write($bytes, 0, $bytes.Length)
                        $res.Close()
                        $skipGeneric = $true
                    }
                    default {
                        $body = '{"error":"not found"}'
                        $res.StatusCode = 404
                    }
                }

                if (-not $skipGeneric) {
                    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                    $res.ContentType = $ct
                    $res.ContentLength64 = $bytes.Length
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    $res.Close()
                }
            } catch {
                Start-Sleep -Milliseconds 100
            }
        }
        $listener.Stop()
    } -ArgumentList $puerto,$protocolo,$script:ScriptPath,$htmlDashboard,$htmlPwa,$pwaManifest,$pwaSw,$icon192,$icon512,$fleetHtml

    Start-Sleep -Seconds 2
    if ($script:RESTJob.State -eq 'Running') {
        Write-AppLog "REST/GraphQL/Fleet/SSE/PWA escuchando en $prefix" "INFO"
    } else {
        try {
            $err = Receive-Job $script:RESTJob -Keep 2>&1 | Out-String
            Write-AppLog "REST fallo: $err" "WARN"
        } catch { Write-AppLog "REST no arranco" "WARN" }
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
# SECCION 60 - AGENTE RESIDENTE WMI
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
# SECCION 61 - THRESHOLD MONITOR
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
                        Send-AllNotifications -Mensaje $msg -Severidad "warning"
                        $script:DisabledSince = Get-Date
                    }
                }
            } else { $script:DisabledSince = $null }
        } catch { }
    })
    $script:ThresholdTimer.Start()
}

# ============================================================================
# SECCION 62 - ARRANQUE v8.2
# ============================================================================
Get-ScriptHash | Out-Null
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v8.2 ULTIMATE iniciado" "INFO"
Write-AppLog "OS: $($script:OSProductType)" "INFO"
Write-AppLog "SHA256: $($script:ScriptHash)" "INFO"
Write-AppLog "HTTPS: $($script:UseHTTPS)" "INFO"
Write-AppLog "AuditMode: $($script:AuditMode)" "INFO"
Write-AppLog "=============================================" "INFO"

# SQLite
if (Initialize-Sqlite) {
    $null = Open-SqliteDB
    Migrate-HistoryToSqlite
    Get-WebhooksFromDB
    Register-FleetComputer
    Write-AppLog "SQLite OK" "INFO"
} else {
    Write-AppLog "SQLite NO disponible - usando JSON" "WARN"
}

if (Test-Admin) {
    Write-AppLog "Admin: SI" "INFO"
    try { Add-MpPreference -ExclusionPath $script:ScriptDir -ErrorAction SilentlyContinue } catch { }
} else {
    Write-AppLog "Admin: NO" "WARN"
}

Clear-OldLogs
Load-History

if (-not $script:AuditMode) { Invoke-StartupAutoRepair }

# -action enable/disable
if ($args -contains "-action") {
    $idx = [array]::IndexOf($args, "-action")
    if ($idx -ge 0 -and $idx + 1 -lt $args.Count) {
        $actionArg = $args[$idx + 1]
        if ($actionArg -eq "disable") {
            $null = Disable-Defender
            Add-HistoryDB -Accion "Desactivar (CLI)" -Resultado (Get-QuickStatus).Estado -Segundos 0
            exit 0
        }
        elseif ($actionArg -eq "enable") {
            $null = Enable-Defender
            Add-HistoryDB -Accion "Activar (CLI)" -Resultado (Get-QuickStatus).Estado -Segundos 0
            exit 0
        }
        elseif ($actionArg -eq "toggle") {
            $accion = Get-ToggleAction
            if ($accion -eq "Activar") { $null = Enable-Defender } else { $null = Disable-Defender }
            Add-HistoryDB -Accion "$accion (CLI toggle)" -Resultado (Get-QuickStatus).Estado -Segundos 0
            exit 0
        }
    }
}

# -autoupdate
if ($script:AutoUpdate) {
    $upd = Test-UpdateAvailable
    if ($upd) { Write-AppLog "Update disponible: v$($upd.Version)" "INFO" }
}

$initQuick = Get-QuickStatus

# ============================================================================
# SECCION 63 - BANDEJA Y MENU
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

$miToggle = Add-MenuItem "UN CLIC: Activar/Desactivar" { Invoke-ToggleProtection }
[void]$menu.Items.Add($miToggle)
[void]$menu.Items.Add((Add-MenuItem "Abrir panel" { Show-DefenderPanel }))
[void]$menu.Items.Add((Add-MenuItem "Diagnostico" { Show-DiagnosticsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Emergencia" { Invoke-EmergencyActivation }))
[void]$menu.Items.Add((Add-MenuItem "Event Log" { Show-EventLogDialog }))
[void]$menu.Items.Add((Add-MenuItem "Reparar Firmas" {
    $log = Repair-DefenderSignatures
    Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $log -Tipo "Success"
}))
[void]$menu.Items.Add((Add-MenuItem "Reparacion Profunda" { Show-DeepRepairDialog }))
[void]$menu.Items.Add((Add-MenuItem "Fleet Console" {
    try { Start-Process "http://127.0.0.1:$($script:CfgRESTPort)/fleet" } catch { }
}))
[void]$menu.Items.Add((Add-MenuItem "Active Directory" { Show-ADDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((Add-MenuItem "Historial" { Show-HistoryDialog }))
[void]$menu.Items.Add((Add-MenuItem "Estadisticas" { Show-StatsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Configuracion" { Show-SettingsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Buscar Actualizacion" { Show-UpdateDialog }))
[void]$menu.Items.Add((Add-MenuItem "Ayuda" { Show-HelpDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miAct = Add-MenuItem "Activar Defender" {
    Invoke-EnableProtection -Accion "Activar (menu)"
}
$miDes = Add-MenuItem "Desactivar Defender" {
    if (-not (Test-Admin)) { return }
    $null = Disable-Defender
    $s = Get-QuickStatus
    Add-HistoryDB -Accion "Desactivar (menu)" -Resultado $s.Estado -Segundos 0
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
    if ($null -ne $script:AnomalyTimer) { try { $script:AnomalyTimer.Stop(); $script:AnomalyTimer.Dispose() } catch { } }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) { try { $script:PanelForm.Close() } catch { } }
    Close-SqliteDB
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}))

$menu.Add_Opening({
    $s = Get-QuickStatus
    if ($s.Estado -eq "ACTIVO") {
        $miToggle.Text = "UN CLIC: Desactivar COMPLETO"
        $miAct.Enabled = $false; $miDes.Enabled = $true
    } elseif ($s.Estado -eq "DESACTIVADO") {
        $miToggle.Text = "UN CLIC: Activar COMPLETO"
        $miAct.Enabled = $true; $miDes.Enabled = $false
    } else {
        if ((Get-ToggleAction -Estado $s) -eq "Desactivar") { $miToggle.Text = "UN CLIC: Terminar de DESACTIVAR" }
        else { $miToggle.Text = "UN CLIC: Terminar de ACTIVAR" }
        $miAct.Enabled = $true; $miDes.Enabled = $true
    }
})

$script:notifyIcon.ContextMenuStrip = $menu
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-DefenderPanel }
})

# ============================================================================
# SECCION 64 - SERVICIOS BACKGROUND
# ============================================================================
if ($script:CfgResidentAgent) { Start-ResidentAgent }
if ($script:CfgRESTEnabled -and -not $script:NoRESTApi) { Initialize-RESTApi }
if ($script:CfgThresholdAlert) { Start-ThresholdMonitor }
if ($script:CfgAnomalyEnabled) { Start-AnomalyMonitor }

Write-AppLog "Bandeja v8.2 lista. Estado: $($initQuick.Estado)" "INFO"
Write-AppLog "Fleet registrado: $env:COMPUTERNAME" "INFO"

# ============================================================================
# SECCION 65 - BUCLE PRINCIPAL
# ============================================================================
[System.Windows.Forms.Application]::Run()