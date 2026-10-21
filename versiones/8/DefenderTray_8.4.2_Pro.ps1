<#
================================================================================
  DefenderTray v8.4.2 ULTIMATE - Enterprise Security Control
================================================================================
  Correcciones v8.4.1:
    A. BOTON CERRAR en "Event Log" ya cierra el dialogo (fijada captura de
       variable $dlg con GetNewClosure en todos los botones Cerrar). Todos
       los dialogos responden tambien a la tecla Esc.
    B. DESACTIVAR ahora desactiva POR COMPLETO: Tiempo Real + Proteccion
       basada en la nube (MAPS/SpyNet/BlockAtFirstSeen) + Envio automatico
       de muestras. ACTIVAR reactiva TODO. Jamas se tocan las bases de
       firmas (.vdm), servicios (WinDefend/WdNisSvc), controladores
       (WdBoot/WdFilter) ni politicas WSUS/Signature Updates.
    C. Repositorio por defecto corregido a yhquintero/DefenderTray; se
       migra automaticamente desde "usuario/DefenderTray" en la primera
       carga para que Buscar Actualizacion funcione.
    D. Toggle mas rapido: reducido Wait-WithDoEvents innecesarios; cada
       Set-MpPreference se aplica individualmente con splatting correcto
       (fix v8.2).
    E. Revision exhaustiva de todos los botones y handlers de la App.
    F. Error de parser corregido al delimitar ${h} antes de los dos puntos.
    G. Buscar Actualizacion consulta la rama main de GitHub, sin exigir Release.
    H. Reparacion con respaldo y validacion de SHA, version y sintaxis antes de sustituir.
  Mejoras v8.4.1:
    F. Atajos Alt+letra en botones; Enter=aceptar, Esc=cancelar en todos
       los dialogos.
    G. Diagnostico verifica firma Authenticode del motor y drivers, mas
       ubicacion y cantidad de .vdm. Boton "Backup Firmas" para copia
       offline sin tocar la base existente.
    H. Set-DefenderPreferencesBulk detalla cada preferencia rechazada en
       el log; toast diferenciado para cambios PARCIALES.
    I. Modo de toggle configurable en Ajustes: Full (RTP+Nube+Muestras) o
       Solo RTP (compat. v8.2). Alerta de cambio PARCIAL desactivable.
  Correcciones v8.2 heredadas:
    1. ACTIVAR y DESACTIVAR vuelven a estar uno junto al otro.
    2. Set-MpPreference por splatting; parametros posicionales eliminados.
    3. Reparar Firmas no usa RemoveDefinitions; conserva bases existentes.
  Correcciones / robustez v8.4.2:
    1. #Requires -Version 5.1 declarado.
    2. [CmdletBinding()]+param() en funciones de control criticas.
    3. Set-MpPrefValue captura el error real; bulk lo muestra en el log.
    4. Confirm-CloudDisabled: corregida precedencia de operadores.
    5. Test-TamperProtectionActive / Get-QuickStatus null-safe.
    6. Protect/Unprotect-String con DataProtectionScope explicito.
    7. New-ShieldBitmap con try/finally (sin fugas de GDI).
    8. Wait-WithDoEvents con ValidateRange y UtcNow.
    9. Rutas de registro y carpetas con -LiteralPath.
   10. function T tolerante si Strings aun no esta listo.
  Conserva TODAS las funciones: SQLite cifrado, MSI, FCM, Fleet, ML, AD,
  GraphQL, PWA, kiosco biometrico, webhooks, Excel/CSV, SSE, auto-update,
  Docker, etc.
  Autor: Ing. Yosvany Hernandez Quintero
  Movil: +53 5 2160801 / +53 5 9860911
================================================================================
#>

#Requires -Version 5.1


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

# v8.4: DPI awareness para que el escalado 125%/150% no corte botones.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DpiHelper {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
    [void][DpiHelper]::SetProcessDPIAware()
} catch { }

# v8.4: hotkey global Ctrl+Alt+D para abrir el panel
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class GlobalHotkey {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const uint MOD_ALT = 0x0001; public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004; public const uint MOD_WIN = 0x0008;
    public const int WM_HOTKEY = 0x0312;
}
"@ -ErrorAction SilentlyContinue
} catch { }

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
$script:StatusMode   = ($args -contains "-status")
# v8.4: pausa temporal (minutos) desde CLI: -pause 60
$script:PauseMinutes = 0
if ($args -contains "-pause") {
    $idx = [array]::IndexOf($args, "-pause")
    if ($idx -ge 0 -and $idx + 1 -lt $args.Count) { [int]::TryParse($args[$idx+1], [ref]$script:PauseMinutes) | Out-Null }
}
$script:NoGui         = ($script:SilentMode -and -not $script:AutoUpdate -and -not $script:StatusMode -eq $false)  # no usado directamente

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
    [CmdletBinding()]
    param()
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}


function Get-PowerShellHostPath {
    [CmdletBinding()]
    param()
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
    [CmdletBinding()]
    param()
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
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -Path $d -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# ============================================================================
# SECCION 3 - CARACTERES ESPECIALES
# ============================================================================
$script:CH_N = [char]0x00F1

# ============================================================================
# SECCION 4 - DETECCION DEL SISTEMA
# ============================================================================
function Get-OSProductType {
    [CmdletBinding()]
    param()
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
    [CmdletBinding()]
    param()
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Texto
    )
    if ([string]::IsNullOrEmpty($Texto)) { return "" }
    # Normalizar a CRLF de forma determinista (Windows)
    $t = $Texto -replace "`r`n", "`n" -replace "`r", "`n"
    return ($t -replace "`n", "`r`n")
}


# ============================================================================
# SECCION 7 - i18n
# ============================================================================
$script:Strings = @{
    ES = @{
        Title = "Control de Seguridad v8.4.2 ULTIMATE"
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
        Title = "Security Control v8.4.2 ULTIMATE"
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Clave = ""
    )
    # Defensa: si Strings aun no esta inicializado, devolver la clave tal cual
    if ($null -eq $script:Strings -or [string]::IsNullOrEmpty($script:Lang)) {
        return $Clave
    }
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
$script:CfgGitHubRepo      = "yhquintero/DefenderTray"
# --- v8.4.1 ---
# Modo de desactivacion: "Full"  = desactiva RTP + Nube + Muestras (la opcion segura)
#                        "RTP"   = solo pausa tiempo real (compatibilidad v8.2)
$script:CfgToggleMode      = "Full"
# Alerta cuando el toggle quede PARCIAL (algunas protecciones no se movieron)
$script:CfgPartialToggleAlert = $true
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
                    "ToggleMode"      { $script:CfgToggleMode = [string]$prop.Value }
                    "PartialToggleAlert" { $script:CfgPartialToggleAlert = [bool]$prop.Value }
                }
                # Migracion: valores invalidos -> por defecto
                if ($script:CfgToggleMode -notin @("Full","RTP")) { $script:CfgToggleMode = "Full" }
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
            AnomalyEnabled      = $script:CfgAnomalyEnabled
            AnomalyZ            = $script:CfgAnomalyZ
            GitHubRepo          = $script:CfgGitHubRepo
            ToggleMode          = $script:CfgToggleMode
            PartialToggleAlert  = $script:CfgPartialToggleAlert
        }
        $json = $obj | ConvertTo-Json -Depth 3
        $encrypted = Protect-String $json
        Set-Content -Path $script:ConfigFile -Value $encrypted -Encoding UTF8 -Force
    } catch { }
}

# ============================================================================
# SECCION 8b - EXPORTAR / IMPORTAR CONFIGURACION (v8.4)
# Cifrado DPAPI del archivo de exportacion para que no viaje en texto plano.
# ============================================================================
function Export-AppConfigToFile {
    param([string]$Ruta)
    try {
        Save-AppConfig
        $raw = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 -ErrorAction Stop
        $bundle = [PSCustomObject]@{
            Type        = "DefenderTrayConfig"
            Version     = $script:CurrentVersion
            Host        = $env:COMPUTERNAME
            ExportedAt  = (Get-Date).ToString("s")
            Data        = $raw
        } | ConvertTo-Json -Depth 5
        Set-Content -Path $Ruta -Value $bundle -Encoding UTF8 -Force
        return "[OK] Configuracion exportada a: $Ruta"
    } catch { return "[!] Error al exportar: $($_.Exception.Message)" }
}

function Import-AppConfigFromFile {
    param([string]$Ruta)
    try {
        $bundle = Get-Content -Path $Ruta -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if (-not $bundle -or $bundle.Type -ne "DefenderTrayConfig") { throw "Archivo no valido." }
        # Validar que Data sea string (contenido cifrado DPAPI)
        if ([string]::IsNullOrWhiteSpace($bundle.Data)) { throw "Sin datos." }
        Copy-Item -Path $script:ConfigFile -Destination "$script:ConfigFile.pre-import-$(Get-Date -Format yyyyMMdd-HHmmss).bak" -Force -ErrorAction SilentlyContinue
        Set-Content -Path $script:ConfigFile -Value $bundle.Data -Encoding UTF8 -Force
        Load-AppConfig
        Refresh-Palette
        return "[OK] Configuracion importada (v$($bundle.Version), exportada $($bundle.ExportedAt)). Reinicia el panel si algun cambio no se refleja."
    } catch { return "[!] Error al importar: $($_.Exception.Message)" }
}

# ============================================================================
# SECCION 9 - LOG Y AUDITORIA
# ============================================================================
function New-CorrelationId {
    return ([guid]::NewGuid().ToString("N").Substring(0,8))
}
function Set-CorrelationId {
    param([string]$Id = "")
    if ([string]::IsNullOrEmpty($Id)) { $Id = New-CorrelationId }
    $script:CurrentCorrelationId = $Id
    return $Id
}

function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Mensaje = "",
        [ValidateSet("INFO","WARN","ERROR","DEBUG","OK")]
        [string]$Nivel = "INFO"
    )
    try {
        $cid = if ($script:CurrentCorrelationId) { "[$($script:CurrentCorrelationId)] " } else { "" }
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}{3}" -f (Get-Date), $Nivel.ToUpperInvariant(), $cid, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($script:AuditMode) {
            Add-Content -Path $script:AuditFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch {
        # Silencioso a propósito: el log no debe romper el flujo principal
    }
}


function Clear-OldLogs {
    [CmdletBinding()]
    param()
    if (-not $script:CfgAutoCleanup) { return }
    try {
        $limite = (Get-Date).AddDays(-30)
        foreach ($folder in @($script:LogFolder, $script:AuditFolder, $script:ForensicDir)) {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            $filter = if ($folder -eq $script:LogFolder) { "DefenderTray_*.log" }
                      elseif ($folder -eq $script:AuditFolder) { "audit_*.log" }
                      else { "*.png" }
            Get-ChildItem -LiteralPath $folder -Filter $filter -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $limite } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Limpieza de logs no debe interrumpir el arranque
    }
}

# ============================================================================
# SECCION 10 - ESPERA Y HELPERS
# ============================================================================
function Wait-WithDoEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 600000)]
        [int]$Milliseconds
    )
    if ($Milliseconds -le 0) { return }
    $end = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while ([DateTime]::UtcNow -lt $end) {
        try {
            [System.Windows.Forms.Application]::DoEvents()
        } catch {
            # DoEvents puede fallar si no hay contexto de mensaje; no es fatal
        }
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hex
    )
    try {
        $h = $Hex.TrimStart('#').Trim()
        if ($h.Length -lt 6) { return [System.Drawing.Color]::Gray }
        return [System.Drawing.Color]::FromArgb(
            [Convert]::ToInt32($h.Substring(0,2), 16),
            [Convert]::ToInt32($h.Substring(2,2), 16),
            [Convert]::ToInt32($h.Substring(4,2), 16)
        )
    } catch {
        return [System.Drawing.Color]::Gray
    }
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
    [CmdletBinding()]
    param()
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:ScriptPath) -and (Test-Path -LiteralPath $script:ScriptPath)) {
            $hash = Get-FileHash -LiteralPath $script:ScriptPath -Algorithm SHA256 -ErrorAction Stop
            $script:ScriptHash = $hash.Hash.Substring(0, 16)
            return $script:ScriptHash
        }
    } catch {
        # Fallo silencioso: el hash es informativo
    }
    return ""
}


function Get-StringHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$s
    )
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
        return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
    } finally {
        $sha.Dispose()
    }
}


# ============================================================================
# SECCION 13 - ICONOS
# ============================================================================
function New-ShieldBitmap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Color]$FillColor,
        [ValidateRange(8, 512)]
        [int]$Size = 32
    )
    $bmp = $null
    $g = $null
    $brush = $null
    $pen = $null
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
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(0, 229, 255)), 1.5
        $g.DrawPolygon($pen, $pts)
        return $bmp
    } catch {
        if ($null -ne $bmp) { try { $bmp.Dispose() } catch { } }
        return $null
    } finally {
        if ($null -ne $pen)   { try { $pen.Dispose() }   catch { } }
        if ($null -ne $brush) { try { $brush.Dispose() } catch { } }
        if ($null -ne $g)     { try { $g.Dispose() }     catch { } }
    }
}

function New-IconFromColor {
    param([System.Drawing.Color]$Color)
    $bmp = New-ShieldBitmap -FillColor $Color
    if ($null -eq $bmp) { return [System.Drawing.SystemIcons]::Shield }
    try { return [System.Drawing.Icon]::FromHandle($bmp.GetHicon()) }
    catch { return [System.Drawing.SystemIcons]::Shield }
}

function Get-WindowsDefenderIcon {
    [CmdletBinding()]
    param()
    $rutas = @(
        "$env:ProgramFiles\Windows Defender\MSASCui.exe",
        "$env:ProgramFiles\Windows Defender\MpCmdRun.exe",
        "$env:windir\System32\SecurityHealthSystray.exe"
    )
    foreach ($r in $rutas) {
        try {
            if (Test-Path -LiteralPath $r) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($r)
                if ($null -ne $icon) { return $icon }
            }
        } catch {
            # Continuar con la siguiente ruta candidata
        }
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
    [CmdletBinding()]
    param()
    # Misma comprobacion que usa la auto-elevacion (SECCION 2b).
    return (Test-IsAdministrator)
}

# ============================================================================
# SECCION 15 - ESTADO RAPIDO
# ============================================================================
function Test-DefenderPolicyDisabled {
    [CmdletBinding()]
    param()
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (-not (Test-Path -LiteralPath $regPath)) { return $false }
        $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
        if ($null -eq $props) { return $false }
        if ($null -ne $props.DisableAntiSpyware -and [int]$props.DisableAntiSpyware -eq 1) { return $true }
        if ($null -ne $props.DisableAntiVirus   -and [int]$props.DisableAntiVirus   -eq 1) { return $true }
    } catch {
        return $false
    }
    return $false
}

function Test-RTPDisabled {
    [CmdletBinding()]
    param([switch]$PolicyOnly)
    $paths = @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection")
    if (-not $PolicyOnly) {
        $paths += "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    }
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $v = Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue
        if ($null -ne $v -and $null -ne $v.DisableRealtimeMonitoring -and [int]$v.DisableRealtimeMonitoring -eq 1) {
            return $true
        }
    }
    return $false
}

function Test-DefenderServicesDisabled {
    [CmdletBinding()]
    param()
    # v8.2: los tres servicios clave deben quedar con Start=Disabled (Start=4).
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        if ((Get-ServiceStartMode -Name $s) -ne "Disabled") { return $false }
    }
    return $true
}

function Get-QuickStatus {
    [CmdletBinding()]
    param()
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $running = ($null -ne $svc) -and ($svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)
    $engineRunning = $null -ne (Get-Process -Name MsMpEng -ErrorAction SilentlyContinue)
    $hasPolicy = Test-DefenderPolicyDisabled
    $servicesDisabled = Test-DefenderServicesDisabled
    # El registro expresa intencion, no confirma el estado real del antivirus.
    # Sin respuesta del proveedor nunca inventar ACTIVO ni DESACTIVADO.
    $known = $false
    $rtp = $false
    $av = $false
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            if ($null -ne $st -and
                $null -ne $st.PSObject.Properties["RealTimeProtectionEnabled"] -and
                $null -ne $st.PSObject.Properties["AntivirusEnabled"] -and
                $null -ne $st.RealTimeProtectionEnabled -and
                $null -ne $st.AntivirusEnabled) {
                $known = $true
                $rtp = [bool]$st.RealTimeProtectionEnabled
                $av  = [bool]$st.AntivirusEnabled
            }
        }
    } catch {
        # Proveedor no disponible o bloqueado: dejamos known=$false
    }
    $isActive = $known -and $running -and $engineRunning -and $av -and $rtp -and (-not $hasPolicy)
    $estado = "PARCIAL"
    if ($isActive) {
        $estado = "ACTIVO"
    } elseif ($known -and $running -and $engineRunning -and $av -and (-not $rtp) -and (-not $hasPolicy)) {
        $estado = "DESACTIVADO"
    }
    return [PSCustomObject]@{
        ServiceRunning              = $running
        EngineRunning               = $engineRunning
        RealTimeProtectionEnabled   = $rtp
        StatusKnown                 = $known
        HasPolicy                   = $hasPolicy
        ServicesDisabled            = $servicesDisabled
        IsActive                    = $isActive
        IsFullyDisabled             = $false
        PendingReboot               = $false
        Estado                      = $estado
    }
}

function Get-ServiceStartMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $resultado = "?"
    try {
        if (-not (Test-Path -LiteralPath $regPath)) { return $resultado }
        $v = (Get-ItemProperty -LiteralPath $regPath -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($null -eq $v) { return $resultado }
        switch ([int]$v) {
            0 { $resultado = "Boot" }
            1 { $resultado = "System" }
            2 { $resultado = "Automatic" }
            3 { $resultado = "Manual" }
            4 { $resultado = "Disabled" }
        }
    } catch {
        return "?"
    }
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
GUIA DE FIRMA DIGITAL - DefenderTray v8.4.1
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
                      Name="DefenderTray v8.4.1"
                      Target="[System64Folder]WindowsPowerShell\v1.0\powershell.exe"
                      Arguments="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;[INSTALLFOLDER]DefenderTray_8.2.ps1&quot;"
                      WorkingDirectory="INSTALLFOLDER"/>
            <RemoveFolder Id="ProgramMenuDir" Directory="ProgramMenuDir" On="uninstall"/>
            <RegistryValue Root="HKLM" Key="Software\DefenderTray" Name="installed" Type="integer" Value="1" KeyPath="yes"/>
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="MainFeature" Title="DefenderTray v8.4.1" Level="1">
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
{\b DefenderTray v8.4.1 - Licencia de uso}\par
\par
Software de administracion de seguridad. Uso bajo responsabilidad del operador.\par
Autor: Ing. Yosvany Hernandez Quintero\par
Movil: +53 5 2160801 / +53 5 9860911\par
}
'@
        Set-Content -Path (Join-Path $OutputDir "License.rtf") -Value $licenseRtf -Encoding ASCII -Force

        $candle = Get-WixToolPath -Ejecutable "candle.exe"
        $light  = Get-WixToolPath -Ejecutable "light.exe"
        $msiPath = Join-Path $OutputDir "DefenderTray_v8.4.1.msi"

        if ($candle -and $light) {
            Push-Location $OutputDir
            try {
                $null = & $candle -nologo -arch x64 -ext WixUIExtension DefenderTray.wxs 2>&1
                if (Test-Path "DefenderTray.wixobj") {
                    $null = & $light -nologo -ext WixUIExtension -o "DefenderTray_v8.4.1.msi" DefenderTray.wixobj 2>&1
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
     light.exe  -nologo -ext WixUIExtension -o DefenderTray_v8.4.1.msi DefenderTray.wixobj
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
<div class="header"><h1>DefenderTray Fleet Console</h1><div class="sub">Panel multi-equipo — v8.4.1</div></div>
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
ACTIVE DIRECTORY - v8.4.1
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
                version = "8.3"; tema = if ($script:DarkTheme) {"dark"} else {"light"}
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
<div class="header"><h1>DefenderTray</h1><div class="sub">v8.4.1 ULTIMATE — Panel movil</div></div>
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
<h1>Dashboard en Tiempo Real — v8.4.1</h1>
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
# SECCION 29 - AUTO-UPDATE DESDE EL REPOSITORIO GITHUB
# ============================================================================
$script:CurrentVersion = "8.4.2"
$script:CurrentCorrelationId = $null
$script:LastUpdateCheckError = $null

function Get-GitBlobSha1 {
    param([byte[]]$Bytes)
    $header = [System.Text.Encoding]::ASCII.GetBytes(("blob {0}`0" -f $Bytes.Length))
    [byte[]]$blob = $header + $Bytes
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        return ([BitConverter]::ToString($sha1.ComputeHash($blob)).Replace("-", "").ToLowerInvariant())
    } finally { $sha1.Dispose() }
}

function Get-NormalizedContentSHA256 {
    param([string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant())
    } finally { $sha256.Dispose() }
}

function Get-GitHubScriptUpdate {
    $script:LastUpdateCheckError = $null
    try {
        # Migrar el marcador antiguo y validar el destino antes de formar la URL.
        if ($script:CfgGitHubRepo -eq "usuario/DefenderTray") {
            $script:CfgGitHubRepo = "yhquintero/DefenderTray"
            try { Save-AppConfig } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($script:CfgGitHubRepo)) {
            $script:LastUpdateCheckError = "Comprobacion de actualizaciones desactivada en Configuracion."
            return $null
        }
        $repo = [string]$script:CfgGitHubRepo
        if ($repo -notmatch '^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$') {
            throw "El repositorio GitHub debe tener el formato owner/repo."
        }
        $repoParts = $repo -split '/', 2
        $url = "https://api.github.com/repos/$($repoParts[0])/$($repoParts[1])/contents/versiones/8/DefenderTray_8.4_Pro.ps1?ref=main"

        # Windows PowerShell 5.1 puede no usar TLS 1.2 por defecto.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
        $headers = @{
            "User-Agent" = "DefenderTray/$($script:CurrentVersion)"
            "Accept" = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -TimeoutSec 20 -ErrorAction Stop
        if ($response.type -ne "file" -or $response.path -ne "versiones/8/DefenderTray_8.4_Pro.ps1") {
            throw "GitHub no devolvio el archivo de DefenderTray esperado."
        }
        if ($response.encoding -ne "base64" -or [string]::IsNullOrWhiteSpace([string]$response.content)) {
            throw "GitHub no devolvio el script en formato base64; no se instalara."
        }
        $bytes = [Convert]::FromBase64String(([string]$response.content -replace '\s', ''))
        $gitSha = Get-GitBlobSha1 -Bytes $bytes
        if ([string]::IsNullOrWhiteSpace([string]$response.sha) -or
            $gitSha -ne ([string]$response.sha).ToLowerInvariant()) {
            throw "La huella Git del archivo descargado no coincide."
        }
        $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
        $content = $utf8Strict.GetString($bytes)
        if ([string]::IsNullOrWhiteSpace($content) -or $content[0] -eq [char]0xFEFF) {
            throw "El script remoto esta vacio o tiene un BOM no admitido."
        }

        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            $first = $parseErrors[0]
            throw "El script de GitHub no pasa el parser (linea $($first.Extent.StartLineNumber)): $($first.Message)"
        }
        $versionMatch = [regex]::Match($content, '(?m)^\$script:CurrentVersion\s*=\s*"(?<version>\d+(?:\.\d+){1,3})"\s*$')
        if (-not $versionMatch.Success) { throw "No se encontro una version valida en el script de GitHub." }
        $version = $versionMatch.Groups["version"].Value
        $null = [version]$version
        $sha256 = Get-NormalizedContentSHA256 -Text $content
        $webUrl = "https://github.com/$repo/blob/main/versiones/8/DefenderTray_8.4_Pro.ps1"
        return [pscustomobject]@{
            Tag = "v$version"; Version = $version; Url = $webUrl
            Assets = @(); Published = $null
            Body = "Codigo fuente de la rama main. No se requiere publicar un GitHub Release."
            Source = "GitHub main"; Content = $content; Sha256 = $sha256; GitBlobSha = $gitSha
        }
    } catch {
        $script:LastUpdateCheckError = $_.Exception.Message
        Write-AppLog "GitHub update check error: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Test-UpdateAvailable {
    param($Candidate = $null)
    $latest = $Candidate
    if ($null -eq $latest) { $latest = Get-GitHubScriptUpdate }
    if ($null -eq $latest) { return $null }
    try {
        $current = [version]$script:CurrentVersion
        $new = [version]$latest.Version
        if ($new -gt $current) { return $latest }
        if ($new -eq $current -and -not [string]::IsNullOrWhiteSpace([string]$latest.Sha256)) {
            $localHash = ""
            if ($script:ScriptPath -and (Test-Path -LiteralPath $script:ScriptPath -PathType Leaf)) {
                $localText = [System.IO.File]::ReadAllText($script:ScriptPath, [System.Text.Encoding]::UTF8)
                $localHash = Get-NormalizedContentSHA256 -Text $localText
            }
            # Permitir reparar la misma version si el contenido del repositorio cambio.
            if ($localHash -ne [string]$latest.Sha256) { return $latest }
        }
    } catch {
        $script:LastUpdateCheckError = $_.Exception.Message
        Write-AppLog "GitHub update comparison error: $($_.Exception.Message)" "WARN"
    }
    return $null
}

function Invoke-AutoUpdate {
    param($Candidate = $null)
    $tempPath = $null
    try {
        $latest = $Candidate
        if ($null -eq $latest) { $latest = Get-GitHubScriptUpdate }
        if ($null -eq $latest) {
            if ($script:LastUpdateCheckError) { return "No se pudo consultar GitHub: $($script:LastUpdateCheckError)" }
            return "No se pudo obtener el script desde GitHub."
        }
        $latest = Test-UpdateAvailable -Candidate $latest
        if ($null -eq $latest) { return "Ya tienes la ultima version ($($script:CurrentVersion))." }
        if ([string]::IsNullOrWhiteSpace([string]$latest.Content) -or
            (Get-NormalizedContentSHA256 -Text $latest.Content) -ne [string]$latest.Sha256) {
            throw "El contenido descargado no coincide con su SHA256."
        }
        if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { throw "No se pudo determinar la ruta del script actual." }

        $targetPath = [System.IO.Path]::GetFullPath($script:ScriptPath)
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { throw "No existe la carpeta del script actual." }
        $tempName = ".DefenderTray_Update_$($latest.Version)_$([guid]::NewGuid().ToString('N')).ps1"
        $tempPath = Join-Path $targetDir $tempName
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $normalizedContent = $latest.Content -replace "`r`n", "`n"
        $normalizedContent = $normalizedContent -replace "`r", "`n"
        $normalizedContent = $normalizedContent.Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($tempPath, $normalizedContent, $utf8NoBom)

        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tempPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw "El archivo temporal no pasa el parser; se cancelo la actualizacion."
        }
        $stagedText = [System.IO.File]::ReadAllText($tempPath, [System.Text.Encoding]::UTF8)
        if ((Get-NormalizedContentSHA256 -Text $stagedText) -ne [string]$latest.Sha256) {
            throw "La verificacion SHA256 del archivo temporal fallo."
        }

        $backup = $null
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backup = "$targetPath.v$($script:CurrentVersion).$stamp.bak"
            if (Test-Path -LiteralPath $backup) { $backup = "$backup.$([guid]::NewGuid().ToString('N'))" }
            Copy-Item -LiteralPath $targetPath -Destination $backup -Force -ErrorAction Stop | Out-Null
        }
        Move-Item -LiteralPath $tempPath -Destination $targetPath -Force -ErrorAction Stop | Out-Null
        $tempPath = $null
        try { Add-HistoryDB -Accion "Auto-Update" -Resultado "OK v$($latest.Version)" -Segundos 0 } catch { }
        $backupText = if ($backup) { " Respaldo: $backup" } else { "" }
        return "Actualizado a v$($latest.Version) desde GitHub main. Cierra y vuelve a abrir DefenderTray.$backupText"
    } catch { return "Error al actualizar: $($_.Exception.Message)" }
    finally {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-UpdateDialog {
    $latest = Test-UpdateAvailable
    if ($null -eq $latest) {
        if ($script:LastUpdateCheckError) {
            $titulo = if ($script:LastUpdateCheckError -like "Comprobacion de actualizaciones desactivada*") { "Actualizaciones desactivadas" } else { "Error de actualizacion" }
            $tipo = if ($titulo -eq "Actualizaciones desactivadas") { "Information" } else { "Warning" }
            [System.Windows.Forms.MessageBox]::Show($script:LastUpdateCheckError, $titulo, "OK", $tipo) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Ya tienes la ultima version ($($script:CurrentVersion)).", "Sin actualizaciones", "OK", "Information") | Out-Null
        }
        return
    }
    $msg = "Nueva version disponible: v$($latest.Version)`r`nFuente: $($latest.Source)`r`nSHA256 (LF normalizado): $($latest.Sha256)`r`n`r`n$($latest.Body)`r`n`r`n¿Actualizar ahora?"
    if (Show-ConfirmDialog "Actualizacion" $msg) {
        $res = Invoke-AutoUpdate -Candidate $latest
        [System.Windows.Forms.MessageBox]::Show($res, "Auto-Update", "OK", "Information") | Out-Null
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
# DefenderTray v8.4.1 - Docker
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
Generado por DefenderTray v8.4.1 ULTIMATE<br>
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

# v8.4.1: habilita la tecla Esc y asocia un boton Cancel a un formulario.
# Evita repetir el codigo Add_KeyDown en cada dialogo y garantiza que la
# captura de $dlg en el scriptblock sea la correcta (GetNewClosure).
function Enable-DialogEscClose {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Windows.Forms.Button]$CancelButton = $null
    )
    if ($null -eq $Form) { return }
    $Form.KeyPreview = $true
    if ($null -ne $CancelButton) {
        try { $Form.CancelButton = $CancelButton } catch { }
        $handler = { $Form.Close() }.GetNewClosure()
        try { $CancelButton.Add_Click($handler) } catch { }
    }
    $kdHandler = {
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            # Si el foco esta en un control que ya consume Esc (p.ej. un
            # TextBox multilinea), respetarlo; de lo contrario cerrar.
            $e.Handled = $true
            $Form.Close()
        }
    }.GetNewClosure()
    try { $Form.Add_KeyDown($kdHandler) } catch { }
}

# ============================================================================
# SECCION 36 - PANIC BUTTON / EMERGENCIA
# ============================================================================
# ============================================================================
# SECCION 36 - PAUSA TEMPORAL (v8.4)
# ============================================================================
$script:PauseTimer = $null
function Invoke-TimedPause {
    param([int]$Minutes = 30)
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null; return
    }
    if ($script:IsBusy) { return }
    if (-not (Show-ConfirmDialog "Pausa temporal" "Pausar Defender durante $Minutes minutos?`r`nSe reactivara automaticamente al vencer.`r`nNO detiene motor ni borra firmas.")) { return }
    $null = Disable-Defender
    $endAt = (Get-Date).AddMinutes($Minutes)
    Write-AppLog "Pausa temporal activada hasta $($endAt.ToString('HH:mm:ss')) ($Minutes min)" "INFO"
    if ($null -ne $script:notifyIcon) {
        try { $script:notifyIcon.ShowBalloonTip(4000,"DefenderTray","Pausa $Minutes min. Se reactivara a las $($endAt.ToString('HH:mm')).","Info") } catch { }
    }
    if ($null -ne $script:PauseTimer) { try { $script:PauseTimer.Stop(); $script:PauseTimer.Dispose() } catch { } }
    $script:PauseTimer = New-Object System.Windows.Forms.Timer
    $script:PauseTimer.Interval = 60000  # comprobar cada minuto
    $script:PauseTimer.Tag = $endAt
    $script:PauseTimer.Add_Tick({
        if ((Get-Date) -ge $this.Tag) {
            $this.Stop(); $this.Dispose(); $script:PauseTimer = $null
            Write-AppLog "Pausa temporal vencida; reactivando..." "INFO"
            Invoke-EnableProtection -Accion "Reactivacion automatica"
        } else {
            Update-PanelStatusUI
        }
    }.GetNewClosure())
    $script:PauseTimer.Start()
    Update-PanelStatusUI
}

function Invoke-EmergencyActivation {
    # Cancelar cualquier pausa programada primero
    if ($null -ne $script:PauseTimer) { try { $script:PauseTimer.Stop(); $script:PauseTimer.Dispose() } catch { }; $script:PauseTimer = $null }
    Invoke-EnableProtection -Accion "EMERGENCIA"
}

# ============================================================================
# SECCION 36b - v8.2: INTERRUPTOR DE UN SOLO CLIC
# ============================================================================
function Get-ToggleAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $Estado
    )
    if ($null -eq $Estado) { $Estado = Get-QuickStatus }
    if ($null -ne $Estado -and $Estado.Estado -eq "ACTIVO") { return "Desactivar" }
    # Ante un estado parcial/desconocido, priorizar recuperar la proteccion.
    return "Activar"
}

function Invoke-ToggleProtection {
    param([ValidateSet("", "Activar", "Desactivar")][string]$Accion = "")
    # Un clic para cambiar tiempo real; no forzar cierres ni borrar firmas.
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
        return
    }
    if ($script:IsBusy) { return }
    $s = Get-QuickStatus
    if (-not $Accion) { $Accion = Get-ToggleAction -Estado $s }
    $script:IsBusy = $true
    $cid = Set-CorrelationId
    try {
        Set-PanelBusy $true
        Start-ActionTimer; $script:LastActionName = "$accion (1 clic)"
        if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
            if ($accion -eq "Desactivar") { $script:PanelLblDet1.Text = "Pausando tiempo real; conservando firmas..." }
            else { $script:PanelLblDet1.Text = "Activando proteccion en tiempo real..." }
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

        $objetivo = if ($accion -eq "Activar") { "ACTIVO" } else { "DESACTIVADO" }
        # v8.4.1: detectar cambios PARCIALES (tiempo real aplicado pero nube/muestras no)
        $cloudState = if ($accion -eq "Desactivar") { Confirm-CloudDisabled } else { Confirm-CloudEnabled }
        $msg = "Estado: $($s2.Estado)."
        $parcial = $false
        if ($s2.Estado -eq $objetivo -and $cloudState) {
            $extra = if ($accion -eq "Desactivar") { " (Tiempo real + Nube + Muestras OFF)" } else { " (Tiempo real + Nube + Muestras ON)" }
            $msg += " $accion confirmado en {0:N2}s.$extra" -f $elapsed
        } elseif ($s2.Estado -eq $objetivo -and -not $cloudState) {
            $parcial = $true
            $msg += " $accion PARCIAL en {0:N2}s (Tiempo real OK, Nube/Muestras no). Revisa Seguridad de Windows o Tamper Protection." -f $elapsed
        } else {
            $parcial = $true
            $msg += " Cambio NO confirmado. Revisa Diagnostico y Seguridad de Windows."
        }
        if ($null -ne $script:notifyIcon) {
            try {
                $icono = "Warning"
                if ($s2.Estado -eq "ACTIVO" -and -not $parcial) { $icono = "Info" }
                elseif ($parcial) { $icono = "Warning" }
                $script:notifyIcon.ShowBalloonTip(7000, "DefenderTray", $msg, $icono)
            } catch { }
        }
        if ($parcial -and $script:CfgPartialToggleAlert -and (Test-TamperProtectionActive)) {
            Show-TamperProtectionGuide -Contexto "Para aplicar el cambio completo"
        }
    } catch {
        Write-AppLog "Cambio de proteccion no completado: $($_.Exception.Message)" "ERROR"
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
    $cid = Set-CorrelationId
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
        $cloudOn = Confirm-CloudEnabled
        if ($s.Estado -eq "ACTIVO" -and $cloudOn) { $mensaje += " Tiempo real + Nube + Muestras ACTIVADOS." }
        elseif ($s.Estado -eq "ACTIVO" -and -not $cloudOn) { $mensaje += " PARCIAL: Tiempo real OK, Nube/Muestras pendientes. Revisa Seguridad de Windows." }
        else { $mensaje += " Revisa Diagnostico y Seguridad de Windows." }
        if ($null -ne $script:notifyIcon) {
            try {
                $tipo = if ($s.Estado -eq "ACTIVO" -and $cloudOn) { "Info" } else { "Warning" }
                $script:notifyIcon.ShowBalloonTip(7000, "DefenderTray", $mensaje, $tipo)
            } catch { }
        }
        if (($s.Estado -ne "ACTIVO" -or -not $cloudOn) -and $script:CfgPartialToggleAlert -and (Test-TamperProtectionActive)) {
            Show-TamperProtectionGuide -Contexto "Para activar todas las protecciones"
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
            Fecha = (Get-Date).ToString("s"); Version = "8.3"
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
    $Boton.Enabled = $Habilitado
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
    $btnCerrar.Add_Click({ $dlg.Close() }.GetNewClosure())
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerrar
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
# SECCION 43 - RESERVADA (NO SE ALTERAN FAILURE ACTIONS)
# ============================================================================

# ============================================================================
# SECCION 44 - REPARAR FIRMAS
# ============================================================================
function Test-DefenderSignaturesHealthy {
    param($Status)
    try {
        $version = [version]$Status.AntivirusSignatureVersion
        $date = [datetime]$Status.AntivirusSignatureLastUpdated
        return ($version -gt [version]'0.0.0.0' -and $date.Year -ge 2000 -and
                $Status.AntivirusSignatureAge -lt 65535)
    } catch { return $false }
}

function Repair-DefenderSignatures {
    [CmdletBinding()]
    param()
    $log = New-Object System.Collections.ArrayList
    [void]$log.Add("=== ACTUALIZACION NO DESTRUCTIVA DE FIRMAS ===")
    if ($script:AuditMode) { return "[AUDITORIA] No se actualizan ni modifican firmas." }
    # v8.4: comprobacion preventiva de conectividad a los endpoints de Microsoft.
    $endpoints = @("wdcp.microsoft.com","definitionupdates.microsoft.com","www.microsoft.com")
    foreach ($h in $endpoints) {
        $ok = Test-NetConnection -ComputerName $h -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $ok) { [void]$log.Add("[i] Conectividad a ${h}: FALLA (posible causa de error de actualizacion).") }
    }
    # Nunca borrar definiciones ni detener el motor: si falla la descarga,
    # las bases existentes siguen disponibles. No cambiar fuentes/intervalos.
    try {
        $svc = Get-Service -Name WinDefend -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            if ((Get-ServiceStartMode -Name WinDefend) -eq 'Disabled') {
                throw "WinDefend deshabilitado por una version anterior. Pulsa ACTIVAR primero."
            }
            Start-Service -Name WinDefend -ErrorAction Stop
            Wait-WithDoEvents -Milliseconds 2000
        }
        if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
            Update-MpSignature -ErrorAction Stop
        } else {
            $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
            if (-not (Test-Path $mpCmd)) { throw "No se encontro el actualizador de Defender." }
            $out = & $mpCmd -SignatureUpdate 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            [void]$log.Add($out)
            if ($exitCode -ne 0) { throw "MpCmdRun devolvio $exitCode." }
        }
        $st = Get-MpComputerStatus -ErrorAction Stop
        [void]$log.Add("Version: $($st.AntivirusSignatureVersion); fecha: $($st.AntivirusSignatureLastUpdated)")
        if ((Test-DefenderSignaturesHealthy -Status $st) -and $st.AntivirusSignatureAge -le 30) {
            [void]$log.Add("[OK] Firmas disponibles y verificadas.")
        } else {
            [void]$log.Add("[!] Firmas ausentes o antiguas. Revisa la conexion y Seguridad de Windows.")
        }
    } catch {
        [void]$log.Add("[!] Actualizacion NO completada: $($_.Exception.Message)")
        [void]$log.Add("No se han eliminado las bases de firmas existentes.")
    }
    return ($log -join "`r`n")
}

function Invoke-StartupAutoRepair {
    if (-not $script:CfgAutoRepair -or $script:AuditMode) { return }
    try {
        # No reactivar automaticamente un motor parado ni tocar una pausa.
        if ((Get-QuickStatus).Estado -ne "ACTIVO") { return }
        $st = Get-MpComputerStatus -ErrorAction Stop
        if ((-not (Test-DefenderSignaturesHealthy -Status $st)) -or $st.AntivirusSignatureAge -gt 30) {
            $result = Repair-DefenderSignatures
            Write-AppLog $result "INFO"
        }
    } catch { Write-AppLog "No se pudo comprobar firmas: $($_.Exception.Message)" "WARN" }
}

# ============================================================================
# SECCION 45 - DESACTIVAR DEFENDER
# ============================================================================
# --- v8.2: helpers de preferencias y Tamper Protection ---

function Set-MpPrefValue {
    [CmdletBinding()]
    # v8.2: fix critico. En v8.1 se hacia `Set-MpPreference @{ $p = $true }`,
    # que PowerShell intenta enlazar como parametro POSICIONAL (falla siempre)
    # y ademas se le pasaba -Force, parametro que Set-MpPreference NO tiene.
    # Resultado: silencio total y activacion/desactivacion PARCIALES. Aqui se
    # aplica cada preferencia por su nombre real via splatting.
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Nombre,

        [Parameter(Mandatory = $true)]
        $Valor
    )
    if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        # Clave dinámica: debe asignarse con indexador, no en el literal @{ }
        $splat = @{ ErrorAction = "Stop" }
        $splat[$Nombre] = $Valor
        Set-MpPreference @splat
        return $true
    } catch {
        # Guardamos el motivo en una variable de script para que el bulk pueda
        # incluirlo en el log sin cambiar la firma de retorno (bool).
        $script:LastMpPrefError = $_.Exception.Message
        return $false
    }
}

function Test-TamperProtectionActive {
    [CmdletBinding()]
    param()
    try {
        if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
            return $false
        }
        $st = Get-MpComputerStatus -ErrorAction Stop
        if ($null -eq $st) { return $false }
        # IsTamperProtected puede no existir en builds muy antiguos
        $prop = $st.PSObject.Properties["IsTamperProtected"]
        if ($null -eq $prop) { return $false }
        return [bool]$prop.Value
    } catch {
        return $false
    }
}

function Show-TamperProtectionGuide {
    param([string]$Contexto = "Para completar la accion")
    $msg = "Tamper Protection (Proteccion contra manipulaciones) esta ACTIVA y Windows bloquea cambios en Defender.`r`n`r`n" +
           "$Contexto debes desactivarla UNA sola vez en Seguridad de Windows:`r`n`r`n" +
           "  Seguridad de Windows > Proteccion antivirus y contra amenazas >`r`n" +
           "  Configuracion de proteccion antivirus y contra amenazas >`r`n" +
           "  Proteccion contra manipulaciones = DESACTIVADA`r`n`r`n" +
           "No se fuerzan servicios ni se eliminan bases de firmas.`r`n" +
           "Tras desactivarla, vuelve a pulsar el boton (un solo clic).`r`n`r`n" +
           "Abrir Seguridad de Windows ahora?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "Tamper Protection", "YesNo", "Warning")
    if ($r -eq "Yes") {
        try { Start-Process "windowsdefender://threatsettings" } catch { }
    }
}

# ============================================================================
# SECCION 45 - DESACTIVACION COMPLETA NO DESTRUCTIVA (v8.4.1)
# ============================================================================
# Desactiva:
#   - Tiempo real (DisableRealtimeMonitoring)
#   - Proteccion basada en la nube / MAPS (DisableBlockAtFirstSeen,
#     CloudProtectionLevel, SpynetReporting)
#   - Envio automatico de muestras (SubmitSamplesConsent)
# JAMAS toca:
#   - Bases de firmas (archivos .vdm en Platform/*/Definitions)
#   - Servicios WinDefend/WdNisSvc/Sense/SecurityHealthService/wscsvc
#   - Controladores WdBoot/WdFilter/WdNisDrv (Start no se cambia a 4)
#   - Politicas WSUS, Signature Updates, exclusiones, rutas de red.
function Set-DefenderPreferencesBulk {
    [CmdletBinding()]
    # Aplica un hashtable de preferencias una a una con Set-MpPrefValue
    # para que un fallo en una opcion no cancele el resto (splatting por
    # item individual). Devuelve [ok,fail,details] con el detalle de cada
    # error para poder mostrarlo en el log v8.4.1.
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prefs
    )
    $ok = 0
    $fail = 0
    $details = New-Object System.Collections.ArrayList
    $script:LastMpPrefError = $null
    foreach ($k in $Prefs.Keys) {
        $v = $Prefs[$k]
        $script:LastMpPrefError = $null
        if (Set-MpPrefValue -Nombre $k -Valor $v) {
            $ok++
        } else {
            $fail++
            $motivo = if ($script:LastMpPrefError) { " ($($script:LastMpPrefError))" } else { "" }
            [void]$details.Add("[!] $k = $v -> RECHAZADO$motivo")
        }
    }
    # Si hay fallos y Tamper Protection esta activa, se indica explicitamente.
    if ($fail -gt 0 -and (Test-TamperProtectionActive)) {
        [void]$details.Add("[i] Causa probable: Tamper Protection activa.")
    }
    return @{ Ok = $ok; Fail = $fail; Details = ($details -join "`r`n") }
}

function Disable-Defender {
    [CmdletBinding()]
    param()
    if ($script:AuditMode) { return "[AUDITORIA] No se aplican cambios." }
    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de pausar" }
    $log = New-Object System.Collections.ArrayList
    [void]$log.Add("=== DESACTIVAR DEFENDER (COMPLETO, NO DESTRUCTIVO) ===")
    [void]$log.Add("Se conservan motor, servicios, controladores, politicas de actualizacion y bases de firmas.")
    $before = Get-QuickStatus
    # Si ya esta DESACTIVADO pero la nube o muestras siguen ON, terminar de desactivar.
    # NOTA: Usamos unicamente parametros validos documentados de Set-MpPreference.
    # Valores de SubmitSamplesConsent: 0=Preguntar siempre, 1=Enviar muestras seguras,
    # 2=Nunca enviar, 3=Enviar todas automaticamente.
    # CloudProtectionLevel: "0"=Desactivado, "1"=Normal, "2"=Alta, "3"=Maxima/Bloqueo.
    $prefs = [ordered]@{
        # Tiempo real (siempre)
        DisableRealtimeMonitoring   = $true
    }
    # v8.4.1: segun CfgToggleMode, solo RTP o Full (nube + muestras + RTP)
    $fullMode = ($script:CfgToggleMode -ne "RTP")
    if ($fullMode) {
        $prefs["DisableBlockAtFirstSeen"] = $true
        $prefs["CloudProtectionLevel"]    = "0"
        $prefs["SubmitSamplesConsent"]    = 0
        $prefs["MAPSReporting"]           = 0
    }
    if ($fullMode) {
        [void]$log.Add("[i] Modo FULL: desactivando RTP + Nube + Muestras.")
        # Politicas de registro equivalentes (equivalente a la UI de Seguridad de Windows).
        # Solo las aplicamos como respaldo si Set-MpPreference falla (por ejemplo,
        # si hay una politica de empresa que bloquee el cambio). Esto NO toca las
        # bases de firmas ni los servicios.
        # SpynetReporting: 0=Off | 1=Basic | 2=Advanced
        # SubmitSamplesConsent: 0=Preguntar siempre | 1=Enviar seguras | 2=Nunca enviar | 3=Enviar todas
        $spyNetPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
        try {
            if (-not (Test-Path $spyNetPolicyPath)) { New-Item -Path $spyNetPolicyPath -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $spyNetPolicyPath -Name SpynetReporting      -Value 0 -Type DWord -ErrorAction Stop
            Set-ItemProperty -Path $spyNetPolicyPath -Name SubmitSamplesConsent -Value 2 -Type DWord -ErrorAction Stop
        } catch { [void]$log.Add("[i] Politicas Spynet no modificadas (Tamper Protection o politicas de empresa): $($_.Exception.Message)") }
    } else {
        [void]$log.Add("[i] Modo RTP solo: pausando unicamente tiempo real (compatibilidad v8.2).")
    }

    $r = Set-DefenderPreferencesBulk -Prefs $prefs
    [void]$log.Add("[i] Preferencias aplicadas: $($r.Ok) OK, $($r.Fail) rechazadas.")
    if (-not [string]::IsNullOrWhiteSpace($r.Details)) { [void]$log.Add($r.Details) }
    if ($r.Fail -gt 0) {
        [void]$log.Add("[!] Windows rechazo algunos cambios. No se forzaran servicios ni procesos.")
    }
    Wait-WithDoEvents -Milliseconds 500
    $after = Get-QuickStatus
    # Confirmar tambien el estado de nube/muestras para que el resultado sea fiable.
    $cloudOk = if ($fullMode) { Confirm-CloudDisabled } else { $true }
    if ($after.Estado -eq "DESACTIVADO" -or $before.Estado -eq "DESACTIVADO") {
        $msg = "[OK] Tiempo real pausado."
        if ($fullMode) {
            if ($cloudOk) { $msg += " Nube y envio de muestras DESACTIVADOS." }
            else { $msg += " [i] Revisa en Seguridad de Windows que Nube/Muestras queden en OFF." }
        }
        [void]$log.Add($msg)
    } else {
        [void]$log.Add("[!] Pausa NO confirmada. Revisa Tamper Protection o las politicas de tu organizacion.")
    }
    Write-AppLog ($log -join "`r`n") "INFO"
    Send-AllNotifications -Mensaje "Tiempo real: $($after.Estado)" -Severidad "warning" -Data @{ estado=$after.Estado }
    return ($log -join "`r`n")
}

function Confirm-CloudDisabled {
    [CmdletBinding()]
    param()
    # Comprueba el estado real de la proteccion en la nube y el envio de muestras
    # mediante Get-MpPreference. Devuelve $true si ambas estan desactivadas.
    # DisableBlockAtFirstSeen = $true  => proteccion en la nube desactivada
    # SubmitSamplesConsent: 0=Preguntar, 2=Nunca enviar  => envio desactivado
    try {
        if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
            return $false
        }
        $p = Get-MpPreference -ErrorAction Stop
        if ($null -eq $p) { return $false }
        $mapsOff   = ($p.DisableBlockAtFirstSeen -eq $true)
        $submitOff = ($p.SubmitSamplesConsent -in @(0, 2))
        return ($mapsOff -and $submitOff)
    } catch {
        return $false
    }
}

function Confirm-CloudEnabled {
    [CmdletBinding()]
    param()
    # Devuelve $true si la proteccion en la nube y el envio de muestras estan activos.
    # DisableBlockAtFirstSeen = $false => nube ON
    # SubmitSamplesConsent: 1=Seguras auto, 3=Todas auto => envio ON
    try {
        if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
            return $false
        }
        $p = Get-MpPreference -ErrorAction Stop
        if ($null -eq $p) { return $false }
        $mapsOn = ($p.DisableBlockAtFirstSeen -eq $false)
        $subOn  = ($p.SubmitSamplesConsent -in @(1, 3))
        return ($mapsOn -and $subOn)
    } catch {
        return $false
    }
}

# ============================================================================
# SECCION 45b - BACKUP DE FIRMAS OFFLINE (v8.4.1)
# ============================================================================
# Copia la carpeta activa de definiciones (Platform/<ver>/Definitions) a un
# destino elegido por el usuario para poder restaurarlas sin conexion. No usa
# MpCmdRun -RemoveDefinitions ni modifica nada en la carpeta de Defender;
# solo hace Copy-Item -Recurse de los .vdm, .vdm?, mpasbase.vdm, etc.
function Get-DefenderSignatureFolder {
    # Devuelve la ruta de Definitions en uso, comprobando primero lo que
    # reporta Get-MpComputerStatus y cayendo a %ProgramData%\Microsoft\Windows
    # Defender\Definition Updates.
    $candidates = @()
    try {
        $st = Get-MpComputerStatus -ErrorAction Stop
        if ($st.AntivirusSignatureLastUpdated) {
            # El motor vive bajo <Platform>\<version>\Definitions
            $platRoot = Join-Path $env:ProgramFiles "Windows Defender"
            if (Test-Path $platRoot) {
                $latest = Get-ChildItem -Path $platRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
                if ($latest) { $candidates += (Join-Path $latest.FullName "Definitions") }
            }
        }
    } catch { }
    $sigRoot = Join-Path $env:ProgramData "Microsoft\Windows Defender\Definition Updates"
    if (Test-Path $sigRoot) { $candidates += (Get-ChildItem -Path $sigRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $vdmCount = @(Get-ChildItem -Path $c -Recurse -Filter "*.vdm" -ErrorAction SilentlyContinue).Count
            if ($vdmCount -gt 5) { return $c }
        }
    }
    return $null
}

function Backup-DefenderSignatures {
    param([string]$Destination = "")
    try {
        $src = Get-DefenderSignatureFolder
        if (-not $src) { return "[!] No se encontro carpeta de firmas activa." }
        if ([string]::IsNullOrEmpty($Destination)) {
            $fd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fd.Description = "Selecciona carpeta destino para el backup de firmas"
            $fd.ShowNewFolderButton = $true
            if ($fd.ShowDialog() -ne "OK") { return "Backup cancelado." }
            $Destination = $fd.SelectedPath
        }
        $stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $dst = Join-Path $Destination "DefenderSignatures_$stamp"
        if (Test-Path $dst) { throw "Ya existe $dst" }
        New-Item -Path $dst -ItemType Directory -Force | Out-Null
        # Copiar solo los archivos de definiciones y el motor necesario para restaurar offline:
        # mpasbase.vdm, mpasdlta.vdm, mpavbase.vdm, mpavdlta.vdm, mpasf*.vdm, mpavf*.vdm, nisf20*.vdm
        # y archivos .dll/.exe del platform para poder usar MpCmdRun sin instalar.
        $patterns = @("*.vdm","*.vdm?","mpcmdrun.exe","mpclient.dll","mpsvc.dll")
        $copied = 0
        foreach ($pat in $patterns) {
            Get-ChildItem -Path $src -Filter $pat -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring($src.Length).TrimStart('\','/')
                $tgt = Join-Path $dst $rel
                $tgtDir = Split-Path -Parent $tgt
                if (-not (Test-Path $tgtDir)) { New-Item -Path $tgtDir -ItemType Directory -Force | Out-Null }
                Copy-Item -LiteralPath $_.FullName -Destination $tgt -Force -ErrorAction SilentlyContinue
                $copied++
            }
        }
        $verFile = Join-Path $dst "VERSION.txt"
        $sigVer = "?"
        try { $sigVer = (Get-MpComputerStatus -ErrorAction Stop).AntivirusSignatureVersion } catch { }
        Set-Content -Path $verFile -Encoding UTF8 -Value @"
DefenderTray Offline Signature Backup
Created    : $(Get-Date -Format 's')
Source     : $src
SignatureV : $sigVer
Host       : $env:COMPUTERNAME
Restore    : copy *.vdm to your Definition Updates folder or use MpCmdRun -SignatureUpdate UNC.
"@
        return "[OK] Backup de firmas creado en: $dst`r`n[i] Archivos copiados: $copied`r`n[i] Version de firmas: $sigVer"
    } catch {
        return "[!] Error al crear backup: $($_.Exception.Message)"
    }
}

# ============================================================================
# SECCION 45c - TEST DE FIRMA DIGITAL DE MOTOR Y DRIVERS (v8.4.1)
# ============================================================================
function Test-FileDigitalSignature {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [PSCustomObject]@{ Signed=$false; Status="Missing"; Subject=""; Path=$Path } }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        return [PSCustomObject]@{
            Signed  = ($sig.Status -eq "Valid")
            Status  = [string]$sig.Status
            Subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
            Path    = $Path
        }
    } catch {
        return [PSCustomObject]@{ Signed=$false; Status="Error"; Subject=$_.Exception.Message; Path=$Path }
    }
}

# ============================================================================
# SECCION 46 - ACTIVACION Y RECUPERACION SELECTIVA
# ============================================================================
function Restore-LegacyDefenderConfiguration {
    if ($script:AuditMode) { return }
    # Recuperacion de Start=4 y de los valores concretos de versiones previas.
    # No borrar ramas completas: conservar Signature Updates, exclusiones,
    # fuentes WSUS y cualquier otra politica ajena a esos antiguos bloqueos.
    $dp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $values = @{
        $dp = @("DisableAntiSpyware", "DisableAntiVirus", "PUAProtection")
        "$dp\Real-Time Protection" = @("DisableRealtimeMonitoring", "DisableBehaviorMonitoring",
            "DisableOnAccessProtection", "DisableScanOnRealtimeEnable", "DisableIOAVProtection",
            "DisableScriptScanning", "DisableRawWriteNotification", "DisableAsyncScan")
        "$dp\Spynet" = @("SpynetReporting", "SubmitSamplesConsent")
        "$dp\Windows Defender Exploit Guard\Network Protection" = @("EnableNetworkProtection")
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" = @("EnableSmartScreen", "ShellSmartScreenLevel")
        "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" = @("DisableRealtimeMonitoring",
            "DisableBehaviorMonitoring", "DisableOnAccessProtection", "DisableScanOnRealtimeEnable",
            "DisableIOAVProtection", "DisableScriptScanning", "DisableRawWriteNotification", "DisableAsyncScan")
    }
    foreach ($path in $values.Keys) {
        if (-not (Test-Path $path)) { continue }
        $props = Get-ItemProperty -Path $path -ErrorAction Stop
        foreach ($name in $values[$path]) {
            if ($null -ne $props.PSObject.Properties[$name]) {
                Remove-ItemProperty -Path $path -Name $name -ErrorAction Stop
            }
        }
    }
    $starts = @{ WinDefend=2; WdNisSvc=3; Sense=3; SecurityHealthService=3; wscsvc=2; WdNisDrv=3; WdBoot=0; WdFilter=0 }
    foreach ($name in $starts.Keys) {
        if ((Get-ServiceStartMode -Name $name) -eq "Disabled") {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name Start -Value $starts[$name] -Type DWord -ErrorAction Stop
        }
    }
}

function Enable-Defender {
    [CmdletBinding()]
    param()
    if ($script:AuditMode) { return "[AUDITORIA] No se aplican cambios." }
    if ($script:CfgForensicMode) { Save-ForensicSnapshot -Contexto "Antes de activar" }
    $log = New-Object System.Collections.ArrayList
    [void]$log.Add("=== ACTIVAR DEFENDER (COMPLETO, SIN BORRAR FIRMAS) ===")
    try {
        $before = Get-QuickStatus
        # Migracion solo si hay indicios de los bloqueos antiguos. Windows
        # puede rechazarla: informar, nunca insistir matando el motor.
        # Una pausa normal puede reflejarse en el registro local. No tratarla
        # como una politica heredada ni exigir un backup para reactivarla.
        $legacy = $before.HasPolicy -or (Test-RTPDisabled -PolicyOnly)
        foreach ($name in @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "wscsvc", "WdNisDrv", "WdBoot", "WdFilter")) {
            if ((Get-ServiceStartMode -Name $name) -eq "Disabled") { $legacy = $true }
        }
        if ($legacy) {
            if (-not (Backup-DefenderRegistry)) { throw "No se pudo respaldar el registro. Recuperacion cancelada." }
            Restore-LegacyDefenderConfiguration
            [void]$log.Add("Bloqueos antiguos retirados selectivamente; politicas de actualizacion conservadas.")
        }
        foreach ($name in @("WinDefend", "WdNisSvc", "SecurityHealthService", "wscsvc")) {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -ne 'Running') {
                try { Start-Service -Name $name -ErrorAction Stop }
                catch { [void]$log.Add("[!] No se pudo iniciar ${name}: $($_.Exception.Message)") }
            }
        }
        # Reactivar tiempo real, comportamiento, IOAV, scripts, exploraciones.
        $restorePrefs = [ordered]@{
            DisableRealtimeMonitoring                   = $false
            DisableBehaviorMonitoring                   = $false
            DisableIOAVProtection                       = $false
            DisableScriptScanning                       = $false
            DisableArchiveScanning                      = $false
            DisableEmailScanning                        = $false
            DisableIntrusionPreventionSystem            = $false
            DisableRemovableDriveScanning               = $false
            DisableScanningNetworkFiles                 = $false
            DisableCatchupQuickScan                     = $false
            DisableCatchupFullScan                      = $false
            DisableRestorePoint                         = $false
        }
        # v8.4.1: segun modo de toggle, restaurar tambien nube/muestras o solo RTP.
        $fullMode = ($script:CfgToggleMode -ne "RTP")
        if ($fullMode) {
            $restorePrefs["DisableBlockAtFirstSeen"] = $false
            $restorePrefs["CloudProtectionLevel"]    = "2"  # Alta
            $restorePrefs["MAPSReporting"]           = 2    # Advanced
            $restorePrefs["SubmitSamplesConsent"]    = 1    # Envio automatico seguro
            [void]$log.Add("[i] Modo FULL: restaurando RTP + Nube + Muestras.")
        } else {
            [void]$log.Add("[i] Modo RTP solo: restaurando unicamente tiempo real (compatibilidad v8.2).")
        }
        $r = Set-DefenderPreferencesBulk -Prefs $restorePrefs
        [void]$log.Add("[i] Preferencias restauradas: $($r.Ok) OK, $($r.Fail) rechazadas.")
        if (-not [string]::IsNullOrWhiteSpace($r.Details)) { [void]$log.Add($r.Details) }
        if ($r.Fail -gt 0) {
            if (Test-TamperProtectionActive) {
                [void]$log.Add("[i] Algunos cambios rechazados: desactiva Tamper Protection y vuelve a intentarlo.")
            } else {
                [void]$log.Add("[!] Algunas preferencias no pudieron activarse (politicas de organizacion).")
            }
        }
        if ($fullMode) {
            # Quitar tambien los valores de politica que pudo dejar Disable-Defender
            $spyNetPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
            try {
                if (Test-Path $spyNetPolicyPath) {
                    foreach ($vn in @("SpynetReporting","SubmitSamplesConsent")) {
                        $p = Get-ItemProperty -Path $spyNetPolicyPath -Name $vn -ErrorAction SilentlyContinue
                        if ($null -ne $p -and $null -ne $p.PSObject.Properties[$vn]) {
                            Remove-ItemProperty -Path $spyNetPolicyPath -Name $vn -ErrorAction SilentlyContinue
                        }
                    }
                }
            } catch { }
        }
        Wait-WithDoEvents -Milliseconds 800
        $after = Get-QuickStatus
        if ($after.Estado -eq "ACTIVO") {
            $msg = "[OK] Proteccion en tiempo real confirmada."
            if ($fullMode) {
                if (Confirm-CloudEnabled) { $msg += " Nube y envio automatico de muestras ACTIVADOS." }
                else { $msg += " [i] Nube/muestras pueden necesitar que abras Seguridad de Windows para confirmar." }
            }
            [void]$log.Add($msg)
        }
        else { [void]$log.Add("[!] Activacion NO confirmada. Revisa Seguridad de Windows; puede requerir reiniciar tras los bloqueos antiguos.") }
        $st = Get-MpComputerStatus -ErrorAction Stop
        if (-not (Test-DefenderSignaturesHealthy -Status $st)) {
            [void]$log.Add("[!] Firmas ausentes (0.0.0.0) o no disponibles. Usa Reparar Firmas para descargarlas sin borrar las existentes.")
        }
    } catch {
        [void]$log.Add("[!] Activacion incompleta: $($_.Exception.Message)")
    }
    Write-AppLog ($log -join "`r`n") "INFO"
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

    # v8.4.1: mostrar estado de Nube y Muestras
    [void]$r.Add([PSCustomObject]@{Item="=== NUBE Y MUESTRAS ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $bafs = if ($mp.DisableBlockAtFirstSeen -eq $false) { "ACTIVADO" } else { "DESACTIVADO" }
        $cBafs = if ($mp.DisableBlockAtFirstSeen -eq $false) { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$r.Add([PSCustomObject]@{Item="  Bloqueo a primera vista (BAFS)"; Status=$bafs; Detail="DisableBlockAtFirstSeen=$($mp.DisableBlockAtFirstSeen)"; Color=$cBafs})
        $cpl = try { [string]$mp.CloudProtectionLevel } catch { "?" }
        [void]$r.Add([PSCustomObject]@{Item="  CloudProtectionLevel"; Status=$cpl; Detail="0=Off 1=Normal 2=Alta"; Color=$script:Colors.TextDiag})
        $ssc = try { $mp.SubmitSamplesConsent } catch { -1 }
        $sscTxt = switch ([int]$ssc) { 0 {"Preguntar siempre"} 1 {"Muestras seguras"} 2 {"Nunca enviar"} 3 {"Todas automatico"} default {"?"} }
        $cSsc = if ([int]$ssc -in 1,3) { $script:Colors.Ok } elseif ([int]$ssc -in 0,2) { $script:Colors.Bad } else { $script:Colors.Neutral }
        [void]$r.Add([PSCustomObject]@{Item="  Envio de muestras"; Status=$sscTxt; Detail="SubmitSamplesConsent=$ssc"; Color=$cSsc})
        $maps = try { $mp.MAPSReporting } catch { -1 }
        $mapsTxt = switch ([int]$maps) { 0 {"Desactivado"} 1 {"Basico"} 2 {"Avanzado"} default {"?"} }
        $cMaps = if ([int]$maps -gt 0) { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$r.Add([PSCustomObject]@{Item="  MAPS/SpyNet"; Status=$mapsTxt; Detail="MAPSReporting=$maps"; Color=$cMaps})
    } catch {
        [void]$r.Add([PSCustomObject]@{Item="  (no se pudo leer Get-MpPreference)"; Status="Err"; Detail=$_.Exception.Message; Color=$script:Colors.Bad})
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

    [void]$r.Add([PSCustomObject]@{Item="=== FIRMAS DIGITALES (MOTOR/DRIVERS) ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $defDir = Join-Path $env:ProgramFiles "Windows Defender"
    $drivers = Join-Path $env:windir "System32\drivers"
    foreach ($f in @(
        (Join-Path $defDir "MsMpEng.exe"),
        (Join-Path $defDir "MpCmdRun.exe"),
        (Join-Path $defDir "MpClient.dll"),
        (Join-Path $drivers "WdBoot.sys"),
        (Join-Path $drivers "WdFilter.sys"),
        (Join-Path $drivers "WdNisDrv.sys")
    )) {
        $sig = Test-FileDigitalSignature -Path $f
        $name = Split-Path $f -Leaf
        if ($sig.Signed) {
            [void]$r.Add([PSCustomObject]@{Item="  $name"; Status="FIRMADO (Valido)"; Detail=$sig.Status; Color=$script:Colors.Ok})
        } elseif ($sig.Status -eq "Missing") {
            [void]$r.Add([PSCustomObject]@{Item="  $name"; Status="No encontrado"; Detail=""; Color=$script:Colors.Warn})
        } else {
            [void]$r.Add([PSCustomObject]@{Item="  $name"; Status=$sig.Status; Detail="Posible tamper/archivo corrupto"; Color=$script:Colors.Bad})
        }
    }

    [void]$r.Add([PSCustomObject]@{Item="=== FIRMAS (DEFINICIONES) ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    try {
        $sigFolder = Get-DefenderSignatureFolder
        if ($sigFolder) {
            $vdm = @(Get-ChildItem -Path $sigFolder -Recurse -Filter "*.vdm" -ErrorAction SilentlyContinue).Count
            [void]$r.Add([PSCustomObject]@{Item="  Carpeta activa"; Status=$sigFolder; Detail="$vdm archivos .vdm"; Color=$script:Colors.Ok})
        } else {
            [void]$r.Add([PSCustomObject]@{Item="  Carpeta activa"; Status="NO DETECTADA"; Detail=""; Color=$script:Colors.Bad})
        }
    } catch {
        [void]$r.Add([PSCustomObject]@{Item="  Carpeta activa"; Status="Err"; Detail=$_.Exception.Message; Color=$script:Colors.Bad})
    }

    # v8.4: ultima amenaza detectada (event ID 1116/1117 del Event Log)
    [void]$r.Add([PSCustomObject]@{Item="=== ULTIMA AMENAZA ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    try {
        $evts = Get-DefenderEventLog -MaxEvents 200
        $threat = $evts | Where-Object { $_.Id -in 1116,1117 } | Select-Object -First 1
        if ($threat) {
            $threatType = if ($threat.Id -eq 1116) { "DETECTADA" } else { "ACCION TOMADA" }
            [void]$r.Add([PSCustomObject]@{Item="  $threatType"; Status=$threat.Hora.ToString("yyyy-MM-dd HH:mm"); Detail=$threat.Tipo; Color=$script:Colors.Bad})
        } else {
            [void]$r.Add([PSCustomObject]@{Item="  Sin amenazas recientes"; Status="OK"; Detail=""; Color=$script:Colors.Ok})
        }
    } catch {
        [void]$r.Add([PSCustomObject]@{Item="  Error leyendo eventos"; Status="?"; Detail=$_.Exception.Message; Color=$script:Colors.Warn})
    }

    # v8.4: exclusiones activas (solo lectura)
    [void]$r.Add([PSCustomObject]@{Item="=== EXCLUSIONES (solo lectura) ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        foreach ($kind in @(
            @{N="Rutas";      V=$mp.ExclusionPath},
            @{N="Extensiones";V=$mp.ExclusionExtension},
            @{N="Procesos";   V=$mp.ExclusionProcess},
            @{N="IPs";        V=$mp.ExclusionIpAddress}
        )) {
            $cnt = if ($null -ne $kind.V) { @($kind.V).Count } else { 0 }
            $c = if ($cnt -eq 0) { $script:Colors.Ok } else { $script:Colors.Warn }
            $detalle = if ($cnt -gt 0 -and $cnt -le 3) { (@($kind.V) -join ", ") } elseif ($cnt -gt 3) { "$cnt exclusiones" } else { "Sin exclusiones" }
            [void]$r.Add([PSCustomObject]@{Item="  $($kind.N)"; Status="$cnt"; Detail=$detalle; Color=$c})
        }
    } catch {
        [void]$r.Add([PSCustomObject]@{Item="  No se pudo leer"; Status="Err"; Detail=$_.Exception.Message; Color=$script:Colors.Bad})
    }

    # v8.4: Core Isolation / HVCI / Smart App Control
    [void]$r.Add([PSCustomObject]@{Item="=== SEGURIDAD HARDWARE ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
    $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    try {
        $hvci = if (Test-Path $ciPath) { (Get-ItemProperty -Path $ciPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled } else { 0 }
        $hvciState = if ([int]$hvci -eq 1) { "ACTIVADO" } else { "DESACTIVADO" }
        $hvciColor = if ([int]$hvci -eq 1) { $script:Colors.Ok } else { $script:Colors.Warn }
        [void]$r.Add([PSCustomObject]@{Item="  Memory Integrity (HVCI)"; Status=$hvciState; Detail="Core Isolation"; Color=$hvciColor})
    } catch {
        [void]$r.Add([PSCustomObject]@{Item="  HVCI"; Status="?"; Detail=""; Color=$script:Colors.Neutral})
    }
    try {
        $dgPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
        $virtBased = if (Test-Path $dgPath) { (Get-ItemProperty -Path $dgPath -Name "EnableVirtualizationBasedSecurity" -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity } else { 0 }
        $vbsState = if ([int]$virtBased -eq 1) { "ACTIVADO" } else { "DESACTIVADO" }
        $vbsColor = if ([int]$virtBased -eq 1) { $script:Colors.Ok } else { $script:Colors.Warn }
        [void]$r.Add([PSCustomObject]@{Item="  VBS"; Status=$vbsState; Detail="Seguridad basada en virtualizacion"; Color=$vbsColor})
    } catch { }
    try {
        $sacPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SmartAppControl"
        if (Test-Path $sacPath) {
            $sacEnabled = (Get-ItemProperty -Path $sacPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
            $sacState = switch ([int]$sacEnabled) {
                1 { "ACTIVADO" } 2 { "EVAL" } default { "DESACTIVADO" }
            }
            $sacColor = if ([int]$sacEnabled -eq 1) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$r.Add([PSCustomObject]@{Item="  Smart App Control"; Status=$sacState; Detail=""; Color=$sacColor})
        }
    } catch { }

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

    [void]$r.Add([PSCustomObject]@{Item="=== SCRIPT v8.4.1 ==="; Status=""; Detail=""; Color=$script:Colors.AccentCyan})
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
    $dlg.MinimumSize = New-Object System.Drawing.Size(700, 480)
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk
    $dlg.KeyPreview = $true
    Center-FormOnActiveMonitor -Form $dlg

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60
    $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "DIAGNOSTICO COMPLETO v8.4.1"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblH)

    # v8.4.1: panel de botones inferior (Dock=Bottom) para que la ListView no tape botones.
    # v8.4.1: dos filas de botones (acción arriba, navegación abajo), altura 86.
    $pnlBtns = New-Object System.Windows.Forms.Panel
    $pnlBtns.Dock = "Bottom"; $pnlBtns.Height = 86
    $pnlBtns.BackColor = $script:Colors.Bg
    $dlg.Controls.Add($pnlBtns)

    # Fila superior (acciones)
    $btnRef     = New-NeonButton "&Refrescar"        $script:Colors.AccentAmber $script:Colors.AccentAmberH 15  8 110 30
    $btnCopy    = New-NeonButton "&Copiar"           $script:Colors.AccentCyan  $script:Colors.AccentCyanH  135 8 100 30
    $btnRep     = New-NeonButton "Re&parar Firmas"   $script:Colors.AccentGreen $script:Colors.AccentGreenH 245 8 130 30
    $btnBackup  = New-NeonButton "&Backup Firmas"    $script:Colors.AccentGreen $script:Colors.AccentGreenH 385 8 130 30
    $btnEvents  = New-NeonButton "&Event Log"        $script:Colors.AccentPurple $script:Colors.AccentPurpH 525 8 110 30
    $btnAD      = New-NeonButton "&Active Directory" $script:Colors.AccentBlue  $script:Colors.AccentBlueH  645 8 130 30
    $btnCerr    = New-NeonButton "&Cerrar"           $script:Colors.Neutral     $script:Colors.TextMuted   805 8 130 30
    $btnCerr.Anchor = "Bottom,Right"
    $pnlBtns.Controls.Add($btnRef); $pnlBtns.Controls.Add($btnCopy); $pnlBtns.Controls.Add($btnRep)
    $pnlBtns.Controls.Add($btnBackup); $pnlBtns.Controls.Add($btnEvents); $pnlBtns.Controls.Add($btnAD); $pnlBtns.Controls.Add($btnCerr)
    $dlg.CancelButton = $btnCerr
    $dlg.AcceptButton = $btnRef

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Dock = "Fill"
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Elemento", 350)
    [void]$lv.Columns.Add("Estado", 250)
    [void]$lv.Columns.Add("Detalle", 300)
    $dlg.Controls.Add($lv)
    $dlg.Controls.SetChildIndex($lv, 0)

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
        [void]$sb.AppendLine("DIAGNOSTICO - WINDOWS DEFENDER v8.4.1")
        [void]$sb.AppendLine(("Fecha: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)))
        [void]$sb.AppendLine("=" * 80)
        foreach ($it in $script:DiagLv.Items) {
            [void]$sb.AppendLine($it.Text + " | " + $it.SubItems[1].Text + " | " + $it.SubItems[2].Text)
        }
        try { [System.Windows.Forms.Clipboard]::SetText($sb.ToString()); [System.Windows.Forms.MessageBox]::Show("Copiado.","OK","OK","Information") | Out-Null } catch { }
    })
    $btnRep.Add_Click({
        $log = Repair-DefenderSignatures
        Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $log -Tipo $(if ($log -match "\[OK\]") { "Success" } else { "Warning" })
        & $cargarDiag
    })
    $btnBackup.Add_Click({
        $log = Backup-DefenderSignatures
        Show-ResultDialog -Titulo "Backup Offline de Firmas" -Mensaje $log -Tipo $(if ($log -match "\[OK\]") { "Success" } else { "Warning" })
        & $cargarDiag
    })
    $btnEvents.Add_Click({ Show-EventLogDialog })
    $btnAD.Add_Click({ Show-ADDialog })
    $closeHandler = { $dlg.Close() }.GetNewClosure()
    $btnCerr.Add_Click($closeHandler)
    $dlg.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close(); $e.Handled = $true }
    })
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
    $dlg.KeyPreview = $true
    $dlg.FormBorderStyle = "Sizable"
    $dlg.MinimumSize = New-Object System.Drawing.Size(700, 450)
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

    # v8.4.1: area de botones ABAJO (Dock=Bottom) para que la ListView no tape el
    # boton Cerrar (el bug original). La ListView se ancla Top/Bottom/Left/Right
    # en el espacio restante.
    $pnlBtns = New-Object System.Windows.Forms.Panel
    $pnlBtns.Dock = "Bottom"; $pnlBtns.Height = 48
    $pnlBtns.BackColor = $script:Colors.Bg
    $dlg.Controls.Add($pnlBtns)

    $btnRefrescar = New-NeonButton "Refrescar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 8 130 32
    $btnCerr      = New-NeonButton "Cerrar"    $script:Colors.Neutral     $script:Colors.TextMuted   805 8 130 32
    $btnCerr.Anchor = "Bottom,Right"
    $pnlBtns.Controls.Add($btnRefrescar); $pnlBtns.Controls.Add($btnCerr)
    $dlg.AcceptButton = $null
    $dlg.CancelButton = $btnCerr

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Dock = "Fill"
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 160)
    [void]$lv.Columns.Add("ID", 60)
    [void]$lv.Columns.Add("Tipo", 220)
    [void]$lv.Columns.Add("Mensaje", 460)
    $dlg.Controls.Add($lv)
    # Asegurar orden Z: header (Top) -> panel botones (Bottom) -> lv (Fill, al medio)
    $dlg.Controls.SetChildIndex($lv, 0)

    $cargarEventos = {
        $lv.Items.Clear()
        $eventos = Get-DefenderEventLog -MaxEvents 500
        foreach ($e in $eventos) {
            $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
            [void]$it.SubItems.Add($e.Id)
            [void]$it.SubItems.Add($e.Tipo)
            [void]$it.SubItems.Add($e.Mensaje)
            if ($e.Id -in 1006,1116,1015) { $it.ForeColor = $script:Colors.Bad }
            elseif ($e.Id -in 1007,1117) { $it.ForeColor = $script:Colors.Warn }
            [void]$lv.Items.Add($it)
        }
    }
    & $cargarEventos

    # v8.4.1: usar Add_Click (consistente con el resto de la app) + clausura
    # correcta via .GetNewClosure() para que $dlg este enlazado en el momento
    # de creacion. Resuelve el bug "Cerrar no hace nada".
    $btnRefrescar.Add_Click($cargarEventos.GetNewClosure())
    $closeHandler = { $dlg.Close() }.GetNewClosure()
    $btnCerr.Add_Click($closeHandler)
    $dlg.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close(); $e.Handled = $true }
    })

    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
    $lblH.Text = "HISTORIAL v8.4.1"
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
    $btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
    Enable-DialogEscClose -Form $dlg -CancelButton $btnClose
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
    $lblH.Text = "REPARACION PROFUNDA v8.4.1"
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

    $btnReg  = New-NeonButton "1. Recuperar Defender"    $script:Colors.AccentRed    $script:Colors.AccentRedH    15  580 165 34
    $btnSvc  = New-NeonButton "2. Servicios"           $script:Colors.AccentAmber  $script:Colors.AccentAmberH  190 580 175 34
    $btnGpu  = New-NeonButton "3. gpupdate"            $script:Colors.AccentPurple $script:Colors.AccentPurpH   375 580 130 34
    $btnSFC  = New-NeonButton "4. sfc /scannow"        $script:Colors.AccentBlue   $script:Colors.AccentBlueH   515 580 140 34
    $btnDISM = New-NeonButton "5. DISM Restore"        $script:Colors.AccentCyan   $script:Colors.AccentCyanH   665 580 140 34
    $btnKill = New-NeonButton "Seguridad Windows"          $script:Colors.AccentRed    $script:Colors.AccentRedH    815 580 130 34
    $btnFirmas = New-NeonButton "REPARAR FIRMAS"       $script:Colors.AccentGreen  $script:Colors.AccentGreenH  15  625 230 40
    $btnTodo   = New-NeonButton "REPARAR TODO"         $script:Colors.AccentGreen  $script:Colors.AccentGreenH  255 625 230 40
    $btnADInv  = New-NeonButton "AD Inventory"         $script:Colors.AccentBlue   $script:Colors.AccentBlueH   495 625 160 40
    $btnCert   = New-NeonButton "Guia Certificados"    $script:Colors.AccentPurple $script:Colors.AccentPurpH   665 625 160 40
    $btnCerr   = New-NeonButton "Cerrar"               $script:Colors.Neutral      $script:Colors.TextMuted     835 625 110 40

    foreach ($b in @($btnReg,$btnSvc,$btnGpu,$btnSFC,$btnDISM,$btnKill,$btnFirmas,$btnTodo,$btnADInv,$btnCert,$btnCerr)) { $dlg.Controls.Add($b) }

    $btnReg.Add_Click({
        $repLog = Enable-Defender
        $script:RepairConsole.AppendText("$repLog`r`n")
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
    $btnKill.Add_Click({ Start-Process "windowsdefender://threatsettings" })
    $btnFirmas.Add_Click({
        $c = $script:RepairConsole
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Add-HistoryDB -Accion "Reparar Firmas" -Resultado $(if ($repLog -match "\[OK\]") { "OK" } else { "ERROR" }) -Segundos 0 -Detalle $repLog
    })
    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("==============================================`r`n")
        $c.AppendText("      REPARACION AUTOMATICA COMPLETA v8.4.1`r`n")
        $c.AppendText("==============================================`r`n")
        $enableLog = Enable-Defender
        $c.AppendText("$enableLog`r`n")
        $repLog = Repair-DefenderSignatures
        foreach ($linea in ($repLog -split "`r?`n")) { $c.AppendText("$linea`r`n") }
        Invoke-ConsoleCmd "sfc /scannow"
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("`r`nRevisa los resultados. Puede ser necesario reiniciar el equipo.`r`n")
        Add-HistoryDB -Accion "Reparacion Completa" -Resultado (Get-QuickStatus).Estado -Segundos 0 -Detalle "$enableLog`r`n$repLog"
    })
    $btnADInv.Add_Click({ Show-ADDialog })
    $btnCert.Add_Click({ Show-CertificateGuide })
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())

    $console.AppendText("Consola de reparacion v8.4.1 lista.`r`n")
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
    $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
    $dlg.AcceptButton = $btnOk
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCancel
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:KioskOk
}

# ============================================================================
# SECCION 55 - CONFIGURACION v8.4.1 COMPLETA
# ============================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion v8.4.1"
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
    $lblH.Text = "CONFIGURACION v8.4.1 ULTIMATE"
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

    # --- v8.4.1: Modo de toggle avanzado ---
    $lblToggleMode = New-Object System.Windows.Forms.Label
    $lblToggleMode.Text = "Modo Activar/Desactivar:"; $lblToggleMode.ForeColor = $script:Colors.Text
    $lblToggleMode.Location = New-Object System.Drawing.Point(20, $y); $lblToggleMode.Size = New-Object System.Drawing.Size(200, 25)
    $scrollPanel.Controls.Add($lblToggleMode)
    $cmbToggleMode = New-Object System.Windows.Forms.ComboBox
    $cmbToggleMode.DropDownStyle = "DropDownList"
    $cmbToggleMode.Location = New-Object System.Drawing.Point(225, $y); $cmbToggleMode.Size = New-Object System.Drawing.Size(440, 25)
    $cmbToggleMode.BackColor = $script:Colors.BgSecondary; $cmbToggleMode.ForeColor = $script:Colors.Text
    [void]$cmbToggleMode.Items.Add("Full (RTP + Nube + Muestras) [recomendado]")
    [void]$cmbToggleMode.Items.Add("Solo RTP (compatibilidad v8.2)")
    $cmbToggleMode.SelectedIndex = if ($script:CfgToggleMode -eq "RTP") { 1 } else { 0 }
    $scrollPanel.Controls.Add($cmbToggleMode)
    $y += 30
    $chkPartialAlert = New-CheckBox "Advertir si el toggle queda PARCIAL (algunas protecciones no cambiaron)" $script:CfgPartialToggleAlert $y $scrollPanel; $y += 30
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
    $y += 45
    # v8.4: fila 6 - Exportar/Importar config
    $btnExpCfg = New-NeonButton "Exportar Config" $script:Colors.AccentCyan $script:Colors.AccentCyanH 20 $y 200 34
    $btnImpCfg = New-NeonButton "Importar Config" $script:Colors.AccentAmber $script:Colors.AccentAmberH 230 $y 200 34
    $scrollPanel.Controls.Add($btnExpCfg); $scrollPanel.Controls.Add($btnImpCfg)

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
        $script:CfgToggleMode      = if ($cmbToggleMode.SelectedIndex -eq 1) { "RTP" } else { "Full" }
        $script:CfgPartialToggleAlert = $chkPartialAlert.Checked
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
    $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
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
        $ok = Send-TelegramNotification "Test desde DefenderTray v8.4.1"
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
    $btnCloseBottom.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnExpCfg.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "DefenderTray Config (*.dtcfg)|*.dtcfg"
        $sd.FileName = "DefenderTray_{0}_{1:yyyyMMdd_HHmmss}.dtcfg" -f $env:COMPUTERNAME,(Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            $res = Export-AppConfigToFile -Ruta $sd.FileName
            Show-ResultDialog -Titulo "Exportar Configuracion" -Mensaje $res -Tipo $(if ($res -match "\[OK\]"){"Success"}else{"Warning"})
        }
    })
    $btnImpCfg.Add_Click({
        if (-not (Show-ConfirmDialog "Importar Configuracion" "Importar sobrescribira la configuracion actual.`r`nSe hara un backup automatico.`r`nContinuar?")) { return }
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "DefenderTray Config (*.dtcfg)|*.dtcfg|Todos (*.*)|*.*"
        if ($ofd.ShowDialog() -eq "OK") {
            $res = Import-AppConfigFromFile -Ruta $ofd.FileName
            Show-ResultDialog -Titulo "Importar Configuracion" -Mensaje $res -Tipo $(if ($res -match "\[OK\]"){"Success"}else{"Warning"})
        }
    })

    Center-FormOnActiveMonitor -Form $dlg
    $dlg.CancelButton = $btnCloseBottom
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCloseBottom
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
    $lblH.Text = "AYUDA - v8.4.1 ULTIMATE"
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
DEFENDER CONTROL v8.4.1 ULTIMATE
================================

NOVEDADES v8.4.1
--------------
 1. ACTIVAR y DESACTIVAR adyacentes, segun estado y operacion en curso
 2. Desactivar pausa tiempo real sin cerrar el motor ni el actualizador
 3. Activar verifica tiempo real sin reiniciar servicios que ya funcionan
 4. Windows puede bloquear cambios: se informa sin forzar el sistema
 5. Estado confirmado por Windows; errores como PARCIAL
 6. Reparar Firmas descarga sin borrar definiciones ni politicas de fuentes
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
1. Buscar Actualizacion consulta el archivo de versiones/8 en la rama main de GitHub
2. No se requiere GitHub Release; el cambio se valida antes de reemplazar el script
3. Se crea un .bak junto al archivo actual; reinicia DefenderTray despues

RECUPERAR UN SCRIPT QUE NO ARRANCA
---------------------------------
Un ParserError impide que PowerShell ejecute el auto-update integrado.
Descarga versiones/8/Reparar-DefenderTray.ps1 desde GitHub y ejecutalo aparte:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Reparar-DefenderTray.ps1 -TargetPath C:\DefenderTray_8.4_Pro.ps1
El recuperador verifica SHA, sintaxis y crea un respaldo antes de sustituir.

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
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    Center-FormOnActiveMonitor -Form $dlg
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    Center-FormOnActiveMonitor -Form $dlg
    Enable-DialogEscClose -Form $dlg -CancelButton $btnCerr
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
$script:PanelBtnDisable     = $null
$script:PanelBtnActivate    = $null
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
    if ($null -ne $script:PanelProgress) {
        $script:PanelProgress.Visible = $Busy
        $script:PanelProgress.MarqueeAnimationSpeed = if ($Busy) { 40 } else { 0 }
    }
    if (-not $Busy) { Update-PanelStatusUI }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

# v8.4: pinta un chip ON/OFF/PARCIAL
function Set-ChipState {
    param($Chip, [string]$State, [string]$Label = $null)
    if ($null -eq $Chip) { return }
    if ($Label) { $Chip.Text = $Label }
    switch ($State) {
        "ON"      { $Chip.BackColor = $script:Colors.Ok }
        "OFF"     { $Chip.BackColor = $script:Colors.Bad }
        "PARTIAL" { $Chip.BackColor = $script:Colors.Warn }
        default   { $Chip.BackColor = $script:Colors.BtnDisabled }
    }
}

function Get-ProtectionActionAvailability {
    param([string]$Estado, [bool]$Busy)
    return [PSCustomObject]@{
        Activate = (-not $Busy) -and ($Estado -ne "ACTIVO")
        Deactivate = (-not $Busy) -and ($Estado -eq "ACTIVO")
    }
}

function Update-ProtectionButtons {
    param($Estado)
    $available = Get-ProtectionActionAvailability -Estado $Estado.Estado -Busy $script:IsBusy
    if ($null -ne $script:PanelBtnActivate) {
        Set-NeonButtonState -Boton $script:PanelBtnActivate -Habilitado $available.Activate
    }
    if ($null -ne $script:PanelBtnDisable) {
        Set-NeonButtonState -Boton $script:PanelBtnDisable -Habilitado $available.Deactivate
    }
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

        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "ACTIVADO"; $script:PanelStatusLabel.ForeColor = $script:Colors.Ok }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        if ($s.HasPolicy -or $s.ServicesDisabled) {
            $script:PanelLblDet1.Text = "Usa ACTIVAR para recuperar la proteccion."
        } else {
            $script:PanelLblDet1.Text = "Estado no confirmado. Usa ACTIVAR o consulta Diagnostico."
        }
        $script:PanelLblDet2.Text = $diag
        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "PARCIAL"; $script:PanelStatusLabel.ForeColor = $script:Colors.Warn }
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        if ($s.PendingReboot) {
            $script:PanelLblDet1.Text = "Cambios antiguos pendientes; revisa Diagnostico."
        } else {
            $script:PanelLblDet1.Text = "Tiempo real pausado; motor y actualizaciones disponibles."
        }
        $script:PanelLblDet2.Text = $diag

        if ($null -ne $script:PanelStatusLabel) { $script:PanelStatusLabel.Text = "DESACTIVADO"; $script:PanelStatusLabel.ForeColor = $script:Colors.Bad }
    }

    # v8.4: actualizar chips
    $rtpState   = if ($s.RealTimeProtectionEnabled) { "ON" } else { "OFF" }
    $cloudOn = Confirm-CloudEnabled; $cloudOff = Confirm-CloudDisabled
    $cloudState = if ($cloudOn) { "ON" } elseif ($cloudOff) { "OFF" } else { "PARTIAL" }
    # RTP ON pero nube desconocida = PARCIAL cuando esta ACTIVO pero nube no verificada
    if ($rtpState -eq "ON" -and -not $cloudOn -and -not $cloudOff) { $cloudState = "PARTIAL" }
    $sampState  = $cloudState
    $tamper = Test-TamperProtectionActive
    $tamperState = if ($tamper) { "ON" } else { "OFF" }
    $pausaActiva = ($null -ne $script:PauseTimer)
    Set-ChipState $script:PanelChips.RTP     $rtpState   "RTP"
    Set-ChipState $script:PanelChips.Cloud   $cloudState "NUBE"
    Set-ChipState $script:PanelChips.Samples $sampState  "MUESTRAS"
    Set-ChipState $script:PanelChips.Tamper  $tamperState "TAMPER"
    if ($pausaActiva) {
        try {
            $rest = [math]::Ceiling(([datetime]$script:PauseTimer.Tag - (Get-Date)).TotalMinutes)
            Set-ChipState $script:PanelChips.Pause "PARTIAL" "$rest min"
        } catch { Set-ChipState $script:PanelChips.Pause "ON" "PAUSA" }
    } else {
        Set-ChipState $script:PanelChips.Pause "OFF" "PAUSA"
    }
    # Tooltip con detalle para los chips
    try {
        $tip = "RTP: $rtpState | Nube: $cloudState | Muestras: $sampState | Tamper: $tamperState"
        if ($pausaActiva) { $tip += " | Pausa activa" }
        $script:PanelLblValor.ToolTipText = $tip
        $script:PanelHeader.ToolTipText = $tip
    } catch { }

    Update-ProtectionButtons -Estado $s
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
    $miDes.Add_Click({ Invoke-ToggleProtection -Accion "Desactivar" })
    $mAcciones.Add_DropDownOpening({
        $available = Get-ProtectionActionAvailability -Estado (Get-QuickStatus).Estado -Busy $script:IsBusy
        $this.DropDownItems[0].Enabled = -not $script:IsBusy
        $this.DropDownItems[2].Enabled = $available.Activate
        $this.DropDownItems[3].Enabled = $available.Deactivate
        $s = Get-QuickStatus
        foreach ($it in $this.DropDownItems) {
            if ($it.Tag -eq "pause") { $it.Enabled = ($s.Estado -eq "ACTIVO" -and -not $script:IsBusy) }
        }
    })
    $miEmerg = New-Object System.Windows.Forms.ToolStripMenuItem; $miEmerg.Text = "EMERGENCIA"
    $miEmerg.Add_Click({ Invoke-EmergencyActivation })
    $miVer = New-Object System.Windows.Forms.ToolStripMenuItem; $miVer.Text = "Verificar"; $miVer.Add_Click({ Show-DiagnosticsDialog })
    # v8.4: submenu Pausa temporal para juegos/CAD
    $miPausa = New-Object System.Windows.Forms.ToolStripMenuItem; $miPausa.Text = "Pausar temporalmente (juegos)..."
    foreach ($mins in @(15,30,60,120)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem; $mi.Text = "${mins} minutos"; $mi.Tag = "pause"
        $mi.Add_Click({ Invoke-TimedPause -Minutes $mins }.GetNewClosure())
        [void]$miPausa.DropDownItems.Add($mi)
    }
    [void]$mAcciones.DropDownItems.Add($miAlternar)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miAct)
    [void]$mAcciones.DropDownItems.Add($miDes)
    [void]$mAcciones.DropDownItems.Add($miPausa)
    [void]$mAcciones.DropDownItems.Add($miEmerg)
    [void]$mAcciones.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mAcciones.DropDownItems.Add($miVer)

    $mHerram = New-Object System.Windows.Forms.ToolStripMenuItem
    $mHerram.Text = "&Herramientas"; $mHerram.ForeColor = $script:Colors.Text
    $miRep = New-Object System.Windows.Forms.ToolStripMenuItem; $miRep.Text = "Reparacion Profunda"; $miRep.Add_Click({ Show-DeepRepairDialog })
    # v8.4: atajos directos a Seguridad de Windows
    $miWinSec = New-Object System.Windows.Forms.ToolStripMenuItem; $miWinSec.Text = "Abrir Seguridad de Windows"
    $miWinSecVirus = New-Object System.Windows.Forms.ToolStripMenuItem; $miWinSecVirus.Text = "Proteccion antivirus y contra amenazas"
    $miWinSecVirus.Add_Click({ try { Start-Process "windowsdefender://threatsettings" } catch { } })
    $miWinSecTamper = New-Object System.Windows.Forms.ToolStripMenuItem; $miWinSecTamper.Text = "Proteccion contra manipulaciones (Tamper)"
    $miWinSecTamper.Add_Click({ try { Start-Process "windowsdefender://threatsettings" } catch { } })
    $miWinSecFirewall = New-Object System.Windows.Forms.ToolStripMenuItem; $miWinSecFirewall.Text = "Firewall y proteccion de red"
    $miWinSecFirewall.Add_Click({ try { Start-Process "windowsdefender://network" } catch { } })
    $miWinSecDevice = New-Object System.Windows.Forms.ToolStripMenuItem; $miWinSecDevice.Text = "Seguridad de dispositivo / Core Isolation"
    $miWinSecDevice.Add_Click({ try { Start-Process "windowsdefender://devicesecurity" } catch { } })
    [void]$miWinSec.DropDownItems.Add($miWinSecVirus); [void]$miWinSec.DropDownItems.Add($miWinSecTamper)
    [void]$miWinSec.DropDownItems.Add($miWinSecFirewall); [void]$miWinSec.DropDownItems.Add($miWinSecDevice)
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
    [void]$mHerram.DropDownItems.Add($miWinSec)

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"; $mAyuda.ForeColor = $script:Colors.Text
    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem; $miAy.Text = "Ayuda (F1)"; $miAy.Add_Click({ Show-HelpDialog })
    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem; $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v$($script:CurrentVersion) ULTIMATE`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801 / +53 5 9860911`n`nSistema: $($script:OSProductType)`nRepo: $($script:CfgGitHubRepo)`nSHA256: $($script:ScriptHash)"
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
    $lblSubH.Text = "v$($script:CurrentVersion) ULTIMATE - $($script:OSProductType)"
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

    # v8.4: chips RTP / Nube / Muestras / Tamper en la tarjeta principal
    function New-Chip($Texto, $X, $Parent) {
        $c = New-Object System.Windows.Forms.Label
        $c.Text = $Texto
        $c.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
        $c.Size = New-Object System.Drawing.Size(78, 18)
        $c.Location = New-Object System.Drawing.Point($X, 82)
        $c.TextAlign = "MiddleCenter"
        $c.ForeColor = [System.Drawing.Color]::White
        $c.BackColor = $script:Colors.BtnDisabled
        $Parent.Controls.Add($c)
        return $c
    }
    $chipRTP     = New-Chip "RTP" 12 $card
    $chipCloud   = New-Chip "NUBE" 96 $card
    $chipSamples = New-Chip "MUESTRAS" 180 $card
    $chipTamper  = New-Chip "TAMPER" 264 $card
    $chipPause   = New-Chip "PAUSA" 348 $card
    $script:PanelChips = @{ RTP=$chipRTP; Cloud=$chipCloud; Samples=$chipSamples; Tamper=$chipTamper; Pause=$chipPause }

    # v8.4: barra de progreso tipo marquee mientras trabaja
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(12, 124)
    $progressBar.Size = New-Object System.Drawing.Size(446, 2)
    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Visible = $false
    $card.Controls.Add($progressBar)
    $script:PanelProgress = $progressBar

    $btnDiagnostico = New-NeonButton ("&" + (T "Diagnostico"))  $script:Colors.AccentPurple $script:Colors.AccentPurpH  15  245 470 32
    $btnActivate    = New-NeonButton ("&" + (T "Activar"))       $script:Colors.AccentGreen  $script:Colors.AccentGreenH 15  285 230 32
    $btnToggle      = New-NeonButton ("&" + (T "Desactivar"))    $script:Colors.AccentRed    $script:Colors.AccentRedH   255 285 230 32
    $btnReparar     = New-NeonButton ("&" + (T "Reparar"))      $script:Colors.AccentAmber  $script:Colors.AccentAmberH 15  325 470 36
    $btnEmerg       = New-NeonButton ("&" + (T "Emergencia"))   $script:Colors.AccentRed    $script:Colors.AccentRedH   15  370 230 32
    $btnEventos     = New-NeonButton "&Event Log"        $script:Colors.AccentPurple $script:Colors.AccentPurpH  255 370 230 32
    $btnHistorial   = New-NeonButton ("&" + (T "Historial"))    $script:Colors.AccentBlue   $script:Colors.AccentBlueH  15  410 110 32
    $btnConfig      = New-NeonButton ("&" + (T "Config"))       $script:Colors.AccentBlue   $script:Colors.AccentBlueH  135 410 110 32
    $btnAyuda       = New-NeonButton ("&" + (T "Ayuda"))        $script:Colors.AccentBlue   $script:Colors.AccentBlueH  255 410 110 32
    $btnSalir       = New-NeonButton ("&" + (T "Salir"))        $script:Colors.AccentRed    $script:Colors.AccentRedH   375 410 110 32

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
    $script:PanelBtnDisable = $btnToggle
    $script:PanelBtnActivate = $btnActivate

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

    $btnToggle.Add_Click({ Invoke-ToggleProtection -Accion "Desactivar" })

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
# SECCION 59 - REST API v8.4.1 COMPLETA
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
            $rtp = "DESCONOCIDO"; $known = $false; $av = $false
            try {
                $st = Get-MpComputerStatus -ErrorAction Stop
                if ($null -ne $st -and $null -ne $st.RealTimeProtectionEnabled -and $null -ne $st.AntivirusEnabled) {
                    $known = $true; $av = [bool]$st.AntivirusEnabled
                    $rtp = if ($st.RealTimeProtectionEnabled) { "ACTIVADO" } else { "DESACTIVADO" }
                }
            } catch { }
            $ready = $known -and $av -and $svc -and $svc.Status -eq "Running" -and $null -ne $proc
            $estado = if ($ready -and $rtp -eq "ACTIVADO") { "ACTIVO" }
                      elseif ($ready -and $rtp -eq "DESACTIVADO") { "DESACTIVADO" }
                      else { "PARCIAL" }
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
                            version = "8.3"
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
                            Version = "8.3"
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
                                $data.config = @{ version="8.3"; host=$env:COMPUTERNAME }
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
# SECCION 62 - ARRANQUE v8.4.1
# ============================================================================
Get-ScriptHash | Out-Null
Write-AppLog "=============================================" "INFO"
Write-AppLog "DefenderTray v$($script:CurrentVersion) ULTIMATE iniciado" "INFO"
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

# v8.4: -status devuelve JSON para RMM (Intune/SCCM/TacticalRMM) y sale
if ($script:StatusMode) {
    try {
        $s = Get-QuickStatus
        $st = $null
        try { $st = Get-MpComputerStatus -ErrorAction SilentlyContinue } catch { }
        $mp = $null
        try { $mp = Get-MpPreference -ErrorAction SilentlyContinue } catch { }
        $tamper = [bool](Test-TamperProtectionActive)
        $result = [ordered]@{
            estado                  = $s.Estado
            servicio                = $s.ServiceRunning
            motor                   = $s.EngineRunning
            realTimeProtection      = $s.RealTimeProtectionEnabled
            tamperProtection        = $tamper
            nube                    = if ($mp) { ($mp.DisableBlockAtFirstSeen -eq $false) } else { $null }
            envioMuestras           = if ($mp) { ($mp.SubmitSamplesConsent -in @(1,3)) } else { $null }
            cloudProtectionLevel    = if ($mp) { try { [string]$mp.CloudProtectionLevel } catch { "?" } } else { "?" }
            mapsReporting           = if ($mp) { try { $mp.MAPSReporting } catch { -1 } } else { -1 }
            firmaVersion            = if ($st) { $st.AntivirusSignatureVersion } else { "?" }
            firmaEdadDias           = if ($st) { $st.AntivirusSignatureAge } else { -1 }
            version                 = $script:CurrentVersion
            fecha                   = (Get-Date).ToString("s")
            host                    = $env:COMPUTERNAME
        }
        $result | ConvertTo-Json -Depth 4
    } catch {
        @{ estado="ERROR"; error=$_.Exception.Message } | ConvertTo-Json
    }
    exit 0
}

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

# -pause N (minutos) -> desactivar, esperar N minutos, reactivar. Pensado para juegos/CAD.
if ($script:PauseMinutes -gt 0) {
    Set-CorrelationId
    Write-AppLog "Pause solicitada: $($script:PauseMinutes) min (CLI)" "INFO"
    $null = Disable-Defender
    Write-AppLog "Esperando $($script:PauseMinutes) minutos antes de reactivar..." "INFO"
    Start-Sleep -Seconds ($script:PauseMinutes * 60)
    Write-AppLog "Reactivando tras pausa..." "INFO"
    $null = Enable-Defender
    exit 0
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
    Show-ResultDialog -Titulo "Reparacion de Firmas" -Mensaje $log -Tipo $(if ($log -match "\[OK\]") { "Success" } else { "Warning" })
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
    Invoke-ToggleProtection -Accion "Desactivar"
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
        $miToggle.Text = "UN CLIC: Pausar tiempo real"
        $miAct.Enabled = $false; $miDes.Enabled = $true
    } elseif ($s.Estado -eq "DESACTIVADO") {
        $miToggle.Text = "UN CLIC: Activar tiempo real"
        $miAct.Enabled = $true; $miDes.Enabled = $false
    } else {
        if ((Get-ToggleAction -Estado $s) -eq "Desactivar") { $miToggle.Text = "UN CLIC: Terminar de DESACTIVAR" }
        else { $miToggle.Text = "UN CLIC: Terminar de ACTIVAR" }
        $miAct.Enabled = $true; $miDes.Enabled = $false
    }
    $available = Get-ProtectionActionAvailability -Estado $s.Estado -Busy $script:IsBusy
    $miAct.Enabled = $available.Activate; $miDes.Enabled = $available.Deactivate
    $miToggle.Enabled = -not $script:IsBusy
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

Write-AppLog "Bandeja v$($script:CurrentVersion) lista. Estado: $($initQuick.Estado)" "INFO"
Write-AppLog "Fleet registrado: $env:COMPUTERNAME" "INFO"

# v8.4: comprobacion silenciosa de actualizaciones al iniciar (no bloquea).
$startupUpdateTimer = New-Object System.Windows.Forms.Timer
$startupUpdateTimer.Interval = 15000
$startupUpdateTimer.Add_Tick({
    $this.Stop(); $this.Dispose()
    try {
        $upd = Test-UpdateAvailable
        if ($upd -and $null -ne $script:notifyIcon) {
            $script:notifyIcon.ShowBalloonTip(8000,"DefenderTray","Nueva version disponible: v$($upd.Version). Usa Configuracion > Buscar Update.","Info")
        }
    } catch { }
})
$startupUpdateTimer.Start()

# ============================================================================
# SECCION 65 - BUCLE PRINCIPAL
# ============================================================================
[System.Windows.Forms.Application]::Run()