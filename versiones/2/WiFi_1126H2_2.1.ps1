# ============================================================================
#  GESTOR DE HOTSPOT WIFI - Version 2.1
#  - Compatible: Windows PowerShell 5.1+ / PowerShell 7.x
#  - Requiere: Ejecutar como Administrador
#  - NUEVO v2.1: Activa el hotspot aunque no haya Internet activo
#  - Codificacion: UTF-8 con BOM (recomendado) o ANSI
# ============================================================================

# ---[ ELEVACION DE PRIVILEGIOS ]---------------------------------------------
function Request-Admin {
    param([string]$ScriptPath)
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "PowerShell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $psi.Verb = "RunAs"
        $psi.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        Write-Host "ERROR: Elevacion cancelada." -ForegroundColor Red
        Start-Sleep 3
    }
    return $false
}
if (-not (Request-Admin -ScriptPath $MyInvocation.MyCommand.Path)) { exit }

# ---[ POLITICA DE EJECUCION ]------------------------------------------------
try { Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop } catch {}

# ---[ CONFIGURACION GLOBAL ]-------------------------------------------------
$Script:AppName     = "Gestor Hotspot WiFi"
$Script:Version     = "2.1"
$Script:LogFile     = Join-Path $PSScriptRoot "hotspot.log"
$Script:ProfileFile = Join-Path $PSScriptRoot "hotspot.profile.json"
$Script:UwpReady    = $false

# ---[ UTILIDADES DE UI ]-----------------------------------------------------
function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts][$Level] $Msg" | Out-File -FilePath $Script:LogFile -Append -Encoding UTF8
    } catch {}
}
function Write-Line    { param([string]$c = "Gray")   Write-Host ("-" * 62) -ForegroundColor $c }
function Write-Double  { param([string]$c = "Cyan")   Write-Host ("=" * 62) -ForegroundColor $c }
function Write-Ok      { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green;    Write-Log $m "OK" }
function Write-Bad     { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red;      Write-Log $m "ERR" }
function Write-Warn    { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow;   Write-Log $m "WARN" }
function Write-Info    { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan;     Write-Log $m "INFO" }
function Write-Step    { param([string]$m) Write-Host "  >> $m" -ForegroundColor Magenta }

function Pause-Any {
    Write-Host ""
    Write-Host "  Presione cualquier tecla para continuar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
function Clear-Scr { Clear-Host }

# ---[ BANNER ]---------------------------------------------------------------
function Show-Banner {
    Clear-Scr
    Write-Host ""
    Write-Double "Cyan"
    Write-Host  "         __      __ ___ ___ _    ___   _  _  ___ _____ ___ _____ " -ForegroundColor Cyan
    Write-Host  "         \ \    / /| __|_ _| |  |_ _| | \| |/ _ \_   _| __|_   _|" -ForegroundColor Cyan
    Write-Host  "          \ \/\/ / | _| | || |__ | |  | .  | (_) || | | _|  | |  " -ForegroundColor Cyan
    Write-Host  "           \_/\_/  |_| |___|____|___| |_|\_|\___/ |_| |___| |_|  " -ForegroundColor Cyan
    Write-Host  "                              " -NoNewline
    Write-Host "GESTOR DE HOTSPOT" -ForegroundColor Yellow
    Write-Double "Cyan"
    $mode = if ($Script:UwpReady) { "UWP - Compatibilidad Completa" } else { "LEGACY - Modo Basico" }
    $col  = if ($Script:UwpReady) { "Green" } else { "Yellow" }
    Write-Host ("  Version {0}  |  Modo: {1}" -f $Script:Version, $mode) -ForegroundColor $col
    Write-Host ("  PowerShell: {0}  |  Host: {1}" -f $PSVersionTable.PSVersion, $env:COMPUTERNAME) -ForegroundColor DarkGray
    Write-Host ""
}

# ---[ DETECCION DE POWERSHELL ]----------------------------------------------
function Get-PSType {
    $v = $PSVersionTable.PSVersion
    if ($PSVersionTable.PSEdition -eq "Core" -and $v.Major -ge 7) { return "Core" }
    if ($v.Major -ge 5) { return "Desktop" }
    throw "PowerShell no soportado. Requiere 5.1 o superior."
}

# ---[ INIT UWP ]-------------------------------------------------------------
function Init-Uwp {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $types = @(
            "Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime",
            "Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime",
            "Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime",
            "Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime"
        )
        foreach ($t in $types) { if (-not [Type]::GetType($t)) { return $false } }
        return $true
    } catch { return $false }
}

# ---[ AWAIT HELPERS ]--------------------------------------------------------
$Script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                   $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$Script:asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                   -not $_.IsGenericMethod })[0]

function Await {
    param($Task, $ResultType)
    $m = $Script:asTaskGeneric.MakeGenericMethod($ResultType)
    $t = $m.Invoke($null, @($Task))
    $t.Wait(-1) | Out-Null
    return $t.Result
}
function AwaitAction {
    param($Action)
    $t = $Script:asTaskAction.Invoke($null, @($Action))
    $t.Wait(-1) | Out-Null
}

# ---[ VERIFICACION / ACTIVACION DE WIFI ]------------------------------------
function Test-WiFi {
    Write-Step "Buscando adaptadores Wi-Fi..."

    $all = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.PhysicalMediaType -eq "802.11" -or
        $_.InterfaceDescription -match "wireless|wifi|802\.11" -or
        $_.Name -match "wi-?fi|wlan"
    }

    if (-not $all) {
        Write-Bad "No existe ningun adaptador Wi-Fi en el sistema."
        return $false
    }

    Write-Host "  Adaptadores detectados:" -ForegroundColor DarkGray
    $all | ForEach-Object {
        Write-Host ("   - {0,-25} [{1}]" -f $_.Name, $_.Status) -ForegroundColor DarkGray
    }

    # 1) Si ya hay uno Up, listo
    $up = $all | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($up) {
        Write-Ok "Wi-Fi ya activo: $($up.Name)"
        return $true
    }

    # 2) Recorrer y habilitar
    foreach ($a in $all) {
        if ($a.Status -eq "Disconnected") {
            Write-Ok "Adaptador '$($a.Name)' listo (sin red, pero utilizable para hotspot)."
            return $true
        }

        Write-Warn "Adaptador '$($a.Name)' en estado '$($a.Status)'. Intentando habilitar..."
        try {
            Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue

            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Milliseconds 400
                $now = Get-NetAdapter -Name $a.Name -ErrorAction SilentlyContinue
                if ($now -and ($now.Status -eq "Up" -or $now.Status -eq "Disconnected")) {
                    Write-Ok "Adaptador '$($a.Name)' operativo ($($now.Status))."
                    return $true
                }
            }
        } catch {
            Write-Warn "No se pudo habilitar '$($a.Name)': $($_.Exception.Message)"
        }
    }

    Write-Bad "Ningun adaptador Wi-Fi quedo operativo."
    return $false
}

# ---[ OBTENER TETHERING MANAGER SIN INTERNET ]-------------------------------
function Get-TetheringManager {
    if (-not $Script:UwpReady) { return $null }

    function _ResolveProfile {
        # a) Perfil con Internet activo
        $p = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
        if ($p) { return @{ Profile = $p; Source = "InternetConnectionProfile" } }

        # b) Cualquier perfil guardado (aunque este desconectado)
        $all = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetConnectionProfiles()
        if ($all -and $all.Count -gt 0) {
            $wlan = $all | Where-Object { $_.IsWlanConnectionProfile }     | Select-Object -First 1
            if ($wlan) { return @{ Profile = $wlan; Source = "SavedWlanProfile" } }
            $eth  = $all | Where-Object { $_.IsEthernetConnectionProfile } | Select-Object -First 1
            if ($eth)  { return @{ Profile = $eth;  Source = "SavedEthernetProfile" } }
            $wwan = $all | Where-Object { $_.IsWwanConnectionProfile }     | Select-Object -First 1
            if ($wwan) { return @{ Profile = $wwan; Source = "SavedWwanProfile" } }
            return @{ Profile = $all[0]; Source = "FirstAvailableProfile" }
        }
        return $null
    }

    # Intento 1
    $r = _ResolveProfile

    # Intento 2: activar Wi-Fi y reintentar
    if (-not $r) {
        Write-Warn "Sin perfiles de red. Activando adaptador Wi-Fi y reintentando..."
        Test-WiFi | Out-Null
        Start-Sleep 3
        $r = _ResolveProfile
    }

    # Intento 3: reiniciar WlanSvc y reintentar
    if (-not $r) {
        Write-Warn "Reiniciando servicio WLAN AutoConfig..."
        try {
            Restart-Service -Name WlanSvc -Force -ErrorAction SilentlyContinue
            Start-Sleep 4
            $r = _ResolveProfile
        } catch {}
    }

    if (-not $r) {
        throw "No hay ningun perfil de red disponible. Conecte Wi-Fi o Ethernet al menos una vez y reintente."
    }

    Write-Info "Perfil usado: $($r.Source)"
    $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($r.Profile)
    if ($null -eq $tm) { throw "No se pudo crear el gestor de tethering con ese perfil." }
    return $tm
}

# ---[ PERFILES - Guardar / Cargar ]------------------------------------------
function Save-Profile {
    param($Ssid, $Pass, $Band)
    $obj = [ordered]@{ Ssid = $Ssid; Pass = $Pass; Band = $Band; Saved = (Get-Date).ToString("s") }
    try {
        $obj | ConvertTo-Json | Out-File -FilePath $Script:ProfileFile -Encoding UTF8 -Force
        Write-Ok "Perfil guardado en: $($Script:ProfileFile)"
    } catch { Write-Bad "No se pudo guardar perfil: $($_.Exception.Message)" }
}
function Load-Profile {
    if (-not (Test-Path $Script:ProfileFile)) { return $null }
    try { return Get-Content $Script:ProfileFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

# ---[ QR CODE ]--------------------------------------------------------------
function Show-QRCode {
    param([string]$Ssid, [string]$Pass)
    $data = "WIFI:T:WPA;S:$Ssid;P:$Pass;;"
    $enc  = [uri]::EscapeDataString($data)
    $url  = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$enc"
    Write-Info "Abriendo QR en el navegador para escanear con el movil..."
    Write-Host "  $url" -ForegroundColor DarkCyan
    try { Start-Process $url } catch { Write-Warn "No se pudo abrir el navegador." }
}

# ---[ ACCION: ESTADO ]-------------------------------------------------------
function Action-Status {
    Show-Banner
    Write-Host "  ESTADO ACTUAL DEL HOTSPOT" -ForegroundColor Cyan
    Write-Line
    try {
        $tm = Get-TetheringManager
        if (-not $tm) { Write-Warn "Modo Legacy - usando netsh"; netsh wlan show hostednetwork; Pause-Any; return }

        $state    = [int]$tm.TetheringOperationalState
        $stateTxt = switch ($state) { 0 {"Desconocido"} 1 {"ACTIVADO"} 2 {"Desactivado"} 3 {"En transicion"} default {"?"} }
        $stateCol = if ($state -eq 1) { "Green" } else { "Red" }
        $cfg      = $tm.GetCurrentAccessPointConfiguration()
        $bandTxt  = switch ([int]$cfg.Band) { 0 {"Auto"} 1 {"2.4 GHz"} 2 {"5 GHz"} 3 {"6 GHz"} default {"?"} }

        Write-Host "  Estado        : " -NoNewline -ForegroundColor Gray; Write-Host $stateTxt -ForegroundColor $stateCol
        Write-Host "  SSID          : " -NoNewline -ForegroundColor Gray; Write-Host $cfg.Ssid -ForegroundColor White
        Write-Host "  Contrasena    : " -NoNewline -ForegroundColor Gray; Write-Host $cfg.Passphrase -ForegroundColor White
        Write-Host "  Banda         : " -NoNewline -ForegroundColor Gray; Write-Host $bandTxt -ForegroundColor White
        Write-Host "  Max clientes  : " -NoNewline -ForegroundColor Gray; Write-Host $tm.MaxClientCount -ForegroundColor White
        Write-Host "  Conectados    : " -NoNewline -ForegroundColor Gray; Write-Host $tm.ClientCount -ForegroundColor White
        Write-Line

        $clients = $tm.GetTetheringClients()
        if ($clients.Count -gt 0) {
            Write-Host "  DISPOSITIVOS CONECTADOS:" -ForegroundColor Cyan
            Write-Host "  ----------------------------------------------" -ForegroundColor DarkGray
            foreach ($c in $clients) {
                $mac   = $c.MacAddress
                $hosts = ($c.HostNames | ForEach-Object { $_.Value }) -join ", "
                if (-not $hosts) { $hosts = "Sin nombre" }
                Write-Host ("   MAC: {0,-20} Host: {1}" -f $mac, $hosts) -ForegroundColor White
            }
        } else {
            Write-Host "  Sin dispositivos conectados." -ForegroundColor DarkGray
        }
    } catch { Write-Bad $_.Exception.Message }
    Pause-Any
}

# ---[ ACCION: ACTIVAR ]------------------------------------------------------
function Action-Activate {
    Show-Banner
    Write-Host "  ACTIVAR HOTSPOT" -ForegroundColor Cyan
    Write-Line
    try {
        $tm = Get-TetheringManager
        if (-not $tm) { Write-Warn "Modo Legacy: use 'netsh wlan start hostednetwork'"; Pause-Any; return }
        if ([int]$tm.TetheringOperationalState -eq 1) { Write-Warn "Ya esta activado."; Pause-Any; return }
        Write-Step "Iniciando..."
        $res = Await ($tm.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        if ([int]$res.Status -eq 0) { Write-Ok "Hotspot activado correctamente." }
        else { Write-Bad "Error al activar. Codigo: $($res.Status) - $($res.AdditionalErrorMessage)" }
    } catch { Write-Bad $_.Exception.Message }
    Pause-Any
}

# ---[ ACCION: DESACTIVAR ]---------------------------------------------------
function Action-Deactivate {
    Show-Banner
    Write-Host "  DESACTIVAR HOTSPOT" -ForegroundColor Cyan
    Write-Line
    try {
        $tm = Get-TetheringManager
        if (-not $tm) { Write-Warn "Modo Legacy."; Pause-Any; return }
        if ([int]$tm.TetheringOperationalState -ne 1) { Write-Warn "Ya esta desactivado."; Pause-Any; return }
        Write-Step "Deteniendo..."
        $res = Await ($tm.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        if ([int]$res.Status -eq 0) { Write-Ok "Hotspot desactivado." }
        else { Write-Bad "Error al desactivar. Codigo: $($res.Status)" }
    } catch { Write-Bad $_.Exception.Message }
    Pause-Any
}

# ---[ ACCION: CONFIGURAR ]---------------------------------------------------
function Action-Configure {
    Show-Banner
    Write-Host "  CONFIGURAR HOTSPOT" -ForegroundColor Cyan
    Write-Line
    try {
        $tm = Get-TetheringManager
        if (-not $tm) { Write-Warn "Modo Legacy."; Pause-Any; return }

        $ssid = $null; $pass = $null; $band = $null

        $prof = Load-Profile
        if ($prof) {
            Write-Host ("  Perfil guardado: SSID='{0}' Banda={1}" -f $prof.Ssid, $prof.Band) -ForegroundColor DarkGray
            $use = Read-Host "  Usar perfil guardado? (S/n)"
            if ($use -ne "n" -and $use -ne "N") {
                $ssid = $prof.Ssid; $pass = $prof.Pass; $band = [int]$prof.Band
            }
        }

        if (-not $ssid) {
            Write-Host "  Nuevo SSID: " -NoNewline -ForegroundColor Yellow
            $ssid = Read-Host
            if ([string]::IsNullOrWhiteSpace($ssid)) { throw "SSID vacio." }

            Write-Host "  Nueva contrasena (8-63 chars): " -NoNewline -ForegroundColor Yellow
            $pass = Read-Host
            if ($pass.Length -lt 8 -or $pass.Length -gt 63) { throw "Contrasena debe tener entre 8 y 63 caracteres." }

            Write-Host "  Banda [0=Auto 1=2.4G 2=5G 3=6G]: " -NoNewline -ForegroundColor Yellow
            $band = [int](Read-Host)
            if ($band -notin 0..3) { throw "Banda invalida." }
        }

        $cfg = New-Object Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration
        $cfg.Ssid = $ssid
        $cfg.Passphrase = $pass

        Write-Step "Verificando banda..."
        $ok = Await ($cfg.IsBandSupportedAsync($band)) ([bool])
        if (-not $ok) { throw "Banda $band no soportada por el adaptador." }
        $cfg.Band = $band

        Write-Step "Aplicando configuracion..."
        AwaitAction ($tm.ConfigureAccessPointAsync($cfg))
        Write-Ok "Configuracion aplicada."
        Save-Profile -Ssid $ssid -Pass $pass -Band $band

        Write-Host ""
        Write-Host "  Generar QR para conectar? (s/N): " -NoNewline -ForegroundColor Yellow
        $resp = Read-Host
        if ($resp -eq "s" -or $resp -eq "S") { Show-QRCode -Ssid $ssid -Pass $pass }
    } catch { Write-Bad $_.Exception.Message }
    Pause-Any
}

# ---[ ACCION: INFO DEL SISTEMA ]---------------------------------------------
function Action-SysInfo {
    Show-Banner
    Write-Host "  INFORMACION DEL SISTEMA" -ForegroundColor Cyan
    Write-Line

    Write-Host "  Adaptadores Wi-Fi:" -ForegroundColor Yellow
    $ads = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.PhysicalMediaType -eq "802.11" -or $_.InterfaceDescription -match "wireless|wifi"
    }
    if ($ads) { $ads | Select-Object Name, Status, InterfaceDescription | Format-Table -AutoSize | Out-String | Write-Host }
    else      { Write-Host "   (ninguno)" -ForegroundColor DarkGray }
    Write-Line

    Write-Host "  Driver Wi-Fi:" -ForegroundColor Yellow
    try {
        $d = netsh wlan show drivers | Select-String "Hosted network supported"
        if ($d) { Write-Host "   $d" -ForegroundColor White } else { Write-Host "   (no soportado)" -ForegroundColor DarkGray }
    } catch { Write-Host "   (no disponible)" -ForegroundColor DarkGray }
    Write-Line

    Write-Host ("  PowerShell   : {0}" -f $PSVersionTable.PSVersion) -ForegroundColor White
    Write-Host ("  Windows      : {0}" -f [Environment]::OSVersion.VersionString) -ForegroundColor White
    $arch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
    Write-Host ("  Arquitectura : {0}" -f $arch) -ForegroundColor White
    Write-Host ("  UWP Ready    : {0}" -f $Script:UwpReady) -ForegroundColor White
    Write-Host ("  Log          : {0}" -f $Script:LogFile) -ForegroundColor DarkGray
    Pause-Any
}

# ---[ ACCION: EXPORTAR ]-----------------------------------------------------
function Action-Export {
    Show-Banner
    Write-Host "  EXPORTAR CONFIGURACION" -ForegroundColor Cyan
    Write-Line
    try {
        $tm = Get-TetheringManager
        if (-not $tm) { Write-Warn "No disponible en modo Legacy."; Pause-Any; return }
        $cfg = $tm.GetCurrentAccessPointConfiguration()
        $out = [ordered]@{
            Generado    = (Get-Date).ToString("s")
            SSID        = $cfg.Ssid
            Pass        = $cfg.Passphrase
            Banda       = [int]$cfg.Band
            Estado      = [int]$tm.TetheringOperationalState
            MaxClientes = $tm.MaxClientCount
            Conectados  = $tm.ClientCount
        }
        $file = Join-Path $PSScriptRoot ("hotspot-export-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        $out | ConvertTo-Json | Out-File -FilePath $file -Encoding UTF8
        Write-Ok "Exportado a: $file"
    } catch { Write-Bad $_.Exception.Message }
    Pause-Any
}

# ---[ ACCION: VER LOG ]------------------------------------------------------
function Action-ViewLog {
    Show-Banner
    Write-Host "  ULTIMAS LINEAS DEL LOG" -ForegroundColor Cyan
    Write-Line
    if (Test-Path $Script:LogFile) {
        Get-Content $Script:LogFile -Tail 40 -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
    } else { Write-Warn "Log vacio o inexistente." }
    Pause-Any
}

# ---[ MENU PRINCIPAL ]-------------------------------------------------------
function Show-Menu {
    while ($true) {
        Show-Banner
        Write-Host "  MENU PRINCIPAL" -ForegroundColor Cyan
        Write-Line
        Write-Host "   1) " -NoNewline -ForegroundColor DarkGray; Write-Host "Ver estado del hotspot"        -ForegroundColor White
        Write-Host "   2) " -NoNewline -ForegroundColor DarkGray; Write-Host "Activar hotspot"               -ForegroundColor White
        Write-Host "   3) " -NoNewline -ForegroundColor DarkGray; Write-Host "Desactivar hotspot"            -ForegroundColor White
        Write-Host "   4) " -NoNewline -ForegroundColor DarkGray; Write-Host "Configurar SSID/Pass/Banda"    -ForegroundColor White
        Write-Host "   5) " -NoNewline -ForegroundColor DarkGray; Write-Host "Exportar configuracion (JSON)" -ForegroundColor White
        Write-Host "   6) " -NoNewline -ForegroundColor DarkGray; Write-Host "Informacion del sistema"       -ForegroundColor White
        Write-Host "   7) " -NoNewline -ForegroundColor DarkGray; Write-Host "Ver log"                       -ForegroundColor White
        Write-Host "   0) " -NoNewline -ForegroundColor DarkGray; Write-Host "Salir"                         -ForegroundColor Red
        Write-Line
        Write-Host "  Opcion: " -NoNewline -ForegroundColor Cyan
        switch (Read-Host) {
            "1" { Action-Status }
            "2" { Action-Activate }
            "3" { Action-Deactivate }
            "4" { Action-Configure }
            "5" { Action-Export }
            "6" { Action-SysInfo }
            "7" { Action-ViewLog }
            "0" { Clear-Scr; Write-Host "`n  Hasta pronto.`n" -ForegroundColor Cyan; exit 0 }
            default { Write-Warn "Opcion invalida."; Start-Sleep 1 }
        }
    }
}

# ---[ ARRANQUE ]-------------------------------------------------------------
$Script:UwpReady = Init-Uwp

try {
    Show-Banner
    Write-Step "Verificando politica de ejecucion...";    Write-Ok "Bypass (Scope Process)"
    Write-Step "Detectando version de PowerShell...";     Write-Ok ("{0} ({1})" -f $PSVersionTable.PSVersion, (Get-PSType))

    Write-Step "Inicializando componentes UWP..."
    if ($Script:UwpReady) { Write-Ok "APIs UWP cargadas correctamente." }
    else                  { Write-Warn "UWP no disponible. Se usara modo Legacy (netsh)." }

    Write-Step "Verificando adaptador Wi-Fi..."
    $wifiOk = Test-WiFi

    if (-not $wifiOk) {
        Write-Warn "Wi-Fi no operativo. El hotspot podria fallar."
        Write-Host "  Desea continuar de todas formas? (s/N): " -NoNewline -ForegroundColor Yellow
        $resp = Read-Host
        if ($resp -ne "s" -and $resp -ne "S") {
            Write-Bad "Operacion cancelada por el usuario."
            Pause-Any
            exit 1
        }
        Write-Info "Continuando en modo forzado..."
    }

    Write-Line
    Write-Host "  Todo listo. Iniciando menu..." -ForegroundColor Green
    Start-Sleep 1
    Show-Menu
} catch {
    Write-Bad "Error critico: $($_.Exception.Message)"
    Write-Log "FATAL: $($_.Exception.Message)" "FATAL"
    Pause-Any
    exit 1
}