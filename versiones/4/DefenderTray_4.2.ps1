<#
.SYNOPSIS
    Control de Seguridad de Windows Defender - Futuristic Edition.
.DESCRIPTION
    Version 4.2 - Con modulo de Reparacion Profunda integrado.
    - Nuevo dialogo "Reparacion Profunda" con consola log en vivo.
    - Ejecuta reg delete, sc config, gpupdate, sfc, DISM.
    - Fix de todas las asignaciones a AppConfig con notacion de indice.
.NOTES
    Ejecutar como Administrador.
    Autor: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
    Version: 4.2
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue

# ==================================================================
# 2. ARGUMENTOS Y RUTAS
# ==================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")
$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir  = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

# ==================================================================
# 3. TEXTOS CON TILDE
# ==================================================================
$script:O_ACCENT       = [char]0x00D3
$script:TXT_PROTECCION = "PROTECCI" + $script:O_ACCENT + "N"
$script:TXT_ACTIVAR    = "ACTIVAR " + $script:TXT_PROTECCION
$script:TXT_DESACTIVAR = "DESACTIVAR " + $script:TXT_PROTECCION

# ==================================================================
# 4. RUTAS DE TRABAJO
# ==================================================================
if ($script:PortableMode) {
    $script:ConfigDir = Join-Path $script:ScriptDir "DefenderTrayData"
} else {
    $script:ConfigDir = Join-Path $env:LOCALAPPDATA "DefenderTray"
}
$script:LogFolder   = Join-Path $script:ConfigDir "Logs"
$script:BackupDir   = Join-Path $script:ConfigDir "Backups"
$script:LogFile     = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:CsvFile     = Join-Path $script:LogFolder ("DefenderTray_Eventos_{0:yyyy-MM-dd}.csv" -f (Get-Date))
$script:ConfigFile  = Join-Path $script:ConfigDir "config.json"
$script:HistoryFile = Join-Path $script:ConfigDir "historial_diario.json"

foreach ($d in @($script:ConfigDir, $script:LogFolder, $script:BackupDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ==================================================================
# 5. STRINGS
# ==================================================================
$script:S = @{
    Activo      = "ACTIVADO"
    Parcial     = "PROTECCION PARCIAL"
    Desactivado = "DESACTIVADO"
}

# ==================================================================
# 6. LOG
# ==================================================================
function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# 7. INTEGRIDAD
# ==================================================================
$script:ScriptHash = ""
function Test-ScriptIntegrity {
    try {
        if (Test-Path $script:ScriptPath) {
            $hash = Get-FileHash -Path $script:ScriptPath -Algorithm SHA256 -ErrorAction Stop
            $script:ScriptHash = $hash.Hash.Substring(0, 16)
            return $true
        }
    } catch { }
    return $false
}

# ==================================================================
# 8. CONFIG (con notacion de indice SIEMPRE)
# ==================================================================
$script:AppConfig = @{
    Version      = "4.2"
    DarkTheme    = $true
    Lang         = "ES"
    AutoStart    = $false
    KioskMode    = $false
    KioskHash    = ""
    FirstRunDone = $false
    LastProfile  = "Personalizado"
}
function Load-AppConfig {
    try {
        if (Test-Path $script:ConfigFile) {
            $json = Get-Content $script:ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) {
                if ($script:AppConfig.ContainsKey($p.Name)) { $script:AppConfig[$p.Name] = $p.Value }
            }
        }
    } catch { }
    $script:DarkTheme   = [bool]$script:AppConfig['DarkTheme']
    $script:IsKioskMode = [bool]$script:AppConfig['KioskMode']
}
function Save-AppConfig {
    try {
        $script:AppConfig['DarkTheme'] = $script:DarkTheme
        $script:AppConfig['KioskMode'] = $script:IsKioskMode
        $script:AppConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8 -Force
    } catch { }
}

# ==================================================================
# 9. HISTORIAL
# ==================================================================
$script:EventHistory = New-Object System.Collections.ArrayList
function Add-History {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    $entry = [PSCustomObject]@{ Hora=(Get-Date); Accion=$Accion; Resultado=$Resultado; Segundos=$Segundos }
    [void]$script:EventHistory.Insert(0, $entry)
    while ($script:EventHistory.Count -gt 20) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
    try {
        if (-not (Test-Path $script:CsvFile)) {
            Add-Content -Path $script:CsvFile -Value '"Fecha","Accion","Resultado","Segundos"' -Encoding UTF8
        }
        Add-Content -Path $script:CsvFile -Value ('"{0:yyyy-MM-dd HH:mm:ss}","{1}","{2}","{3:N2}"' -f $entry.Hora, $Accion, $Resultado, $Segundos) -Encoding UTF8 -ErrorAction SilentlyContinue
        $script:EventHistory | ConvertTo-Json -Depth 3 | Set-Content -Path $script:HistoryFile -Encoding UTF8 -Force
    } catch { }
}
function Load-History {
    try {
        if (Test-Path $script:HistoryFile) {
            $data = Get-Content $script:HistoryFile -Raw -ErrorAction Stop | ConvertFrom-Json
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

# ==================================================================
# 10. ESPERA NO BLOQUEANTE
# ==================================================================
function Wait-WithDoEvents {
    param([int]$Milliseconds)
    $end = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $end) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        Start-Sleep -Milliseconds 50
    }
}

# ==================================================================
# 11. PALETAS
# ==================================================================
function Get-FuturisticPalette {
    return @{
        Bg=[System.Drawing.Color]::FromArgb(10,14,26); BgSecondary=[System.Drawing.Color]::FromArgb(20,27,46)
        CardBg=[System.Drawing.Color]::FromArgb(24,32,52); CardBorder=[System.Drawing.Color]::FromArgb(0,180,220)
        Text=[System.Drawing.Color]::FromArgb(224,230,240); TextMuted=[System.Drawing.Color]::FromArgb(107,122,153)
        TextDiag=[System.Drawing.Color]::FromArgb(180,200,220)
        AccentCyan=[System.Drawing.Color]::FromArgb(0,229,255); AccentCyanH=[System.Drawing.Color]::FromArgb(0,180,200)
        AccentPurple=[System.Drawing.Color]::FromArgb(177,78,255); AccentPurpH=[System.Drawing.Color]::FromArgb(140,60,200)
        AccentGreen=[System.Drawing.Color]::FromArgb(0,200,108); AccentGreenH=[System.Drawing.Color]::FromArgb(0,160,86)
        AccentRed=[System.Drawing.Color]::FromArgb(255,51,102); AccentRedH=[System.Drawing.Color]::FromArgb(200,40,80)
        AccentAmber=[System.Drawing.Color]::FromArgb(255,170,0); AccentAmberH=[System.Drawing.Color]::FromArgb(200,130,0)
        AccentBlue=[System.Drawing.Color]::FromArgb(0,140,255); AccentBlueH=[System.Drawing.Color]::FromArgb(0,110,200)
        BtnDisabled=[System.Drawing.Color]::FromArgb(45,55,75); BtnDisabledT=[System.Drawing.Color]::FromArgb(100,115,140)
        HeaderOk=[System.Drawing.Color]::FromArgb(0,150,80); HeaderWarn=[System.Drawing.Color]::FromArgb(180,30,60)
        HeaderPart=[System.Drawing.Color]::FromArgb(180,110,0); HeaderUnk=[System.Drawing.Color]::FromArgb(45,55,75)
        Ok=[System.Drawing.Color]::FromArgb(0,230,120); Bad=[System.Drawing.Color]::FromArgb(255,80,110)
        Warn=[System.Drawing.Color]::FromArgb(255,180,50); Neutral=[System.Drawing.Color]::FromArgb(120,135,160)
        GridLine=[System.Drawing.Color]::FromArgb(40,50,75)
        ConsoleBg=[System.Drawing.Color]::FromArgb(8,12,20); ConsoleText=[System.Drawing.Color]::FromArgb(0,255,180)
        ConsoleCmd=[System.Drawing.Color]::FromArgb(255,220,120); ConsoleErr=[System.Drawing.Color]::FromArgb(255,100,120)
    }
}
function Get-LightPalette {
    return @{
        Bg=[System.Drawing.Color]::FromArgb(240,245,250); BgSecondary=[System.Drawing.Color]::FromArgb(255,255,255)
        CardBg=[System.Drawing.Color]::White; CardBorder=[System.Drawing.Color]::FromArgb(0,140,180)
        Text=[System.Drawing.Color]::FromArgb(20,30,50); TextMuted=[System.Drawing.Color]::FromArgb(100,115,140)
        TextDiag=[System.Drawing.Color]::FromArgb(60,80,105)
        AccentCyan=[System.Drawing.Color]::FromArgb(0,150,200); AccentCyanH=[System.Drawing.Color]::FromArgb(0,120,160)
        AccentPurple=[System.Drawing.Color]::FromArgb(120,60,200); AccentPurpH=[System.Drawing.Color]::FromArgb(90,45,160)
        AccentGreen=[System.Drawing.Color]::FromArgb(20,180,90); AccentGreenH=[System.Drawing.Color]::FromArgb(15,145,70)
        AccentRed=[System.Drawing.Color]::FromArgb(220,45,80); AccentRedH=[System.Drawing.Color]::FromArgb(180,35,65)
        AccentAmber=[System.Drawing.Color]::FromArgb(220,140,0); AccentAmberH=[System.Drawing.Color]::FromArgb(180,110,0)
        AccentBlue=[System.Drawing.Color]::FromArgb(0,110,220); AccentBlueH=[System.Drawing.Color]::FromArgb(0,85,180)
        BtnDisabled=[System.Drawing.Color]::FromArgb(210,210,210); BtnDisabledT=[System.Drawing.Color]::FromArgb(130,130,130)
        HeaderOk=[System.Drawing.Color]::FromArgb(20,170,80); HeaderWarn=[System.Drawing.Color]::FromArgb(200,40,70)
        HeaderPart=[System.Drawing.Color]::FromArgb(200,130,0); HeaderUnk=[System.Drawing.Color]::FromArgb(80,90,110)
        Ok=[System.Drawing.Color]::FromArgb(20,170,80); Bad=[System.Drawing.Color]::FromArgb(200,40,70)
        Warn=[System.Drawing.Color]::FromArgb(200,130,0); Neutral=[System.Drawing.Color]::FromArgb(100,110,130)
        GridLine=[System.Drawing.Color]::FromArgb(220,225,235)
        ConsoleBg=[System.Drawing.Color]::FromArgb(20,25,35); ConsoleText=[System.Drawing.Color]::FromArgb(0,180,120)
        ConsoleCmd=[System.Drawing.Color]::FromArgb(200,150,0); ConsoleErr=[System.Drawing.Color]::FromArgb(200,40,60)
    }
}
Load-AppConfig
$script:Colors = if ($script:DarkTheme) { Get-FuturisticPalette } else { Get-LightPalette }
function Refresh-Palette { $script:Colors = if ($script:DarkTheme) { Get-FuturisticPalette } else { Get-LightPalette } }

# ==================================================================
# 12. ESTADO RAPIDO
# ==================================================================
function Test-DefenderPolicyDisabled {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (-not (Test-Path $regPath)) { return $false }
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($null -ne $props) {
            if ($null -ne $props.DisableAntiSpyware -and [int]$props.DisableAntiSpyware -eq 1) { return $true }
            if ($null -ne $props.DisableAntiVirus   -and [int]$props.DisableAntiVirus   -eq 1) { return $true }
        }
        $rt = Join-Path $regPath "Real-Time Protection"
        if (Test-Path $rt) {
            $r = Get-ItemProperty -Path $rt -ErrorAction SilentlyContinue
            if ($null -ne $r) {
                foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                                 "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
                    if ($null -ne $r.$n -and [int]$r.$n -eq 1) { return $true }
                }
            }
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
    $rtpDisabled = Test-RTPDisabled
    $hasPolicy = Test-DefenderPolicyDisabled
    $isActive = $running -and (-not $rtpDisabled) -and (-not $hasPolicy)
    $estado = if ($isActive) { "ACTIVO" } elseif (-not $running) { "DESACTIVADO" } else { "PARCIAL" }
    return [PSCustomObject]@{ ServiceRunning=$running; RealTimeProtectionEnabled=-not $rtpDisabled; HasPolicy=$hasPolicy; IsActive=$isActive; Estado=$estado }
}

# ==================================================================
# 13. INFORME COMPLETO
# ==================================================================
function Get-SafeProp { param($Obj,[string]$Name); try { $v = $Obj.$Name; if ($null -eq $v) { return "(n/d)" }; return $v } catch { return "(n/d)" } }
function Get-ColorForBool { param($Value); if ($Value -eq $true) { return $script:Colors.Ok }; if ($Value -eq $false) { return $script:Colors.Bad }; return $script:Colors.Neutral }

function Get-CompleteDefenderReport {
    $report = New-Object System.Collections.ArrayList
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        $c = if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$report.Add([PSCustomObject]@{ Modulo="Servicio WinDefend"; Valor=$svc.Status; Color=$c })
    }
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            [void]$report.Add([PSCustomObject]@{ Modulo="Antivirus habilitado"; Valor=(Get-SafeProp $st "AntivirusEnabled"); Color=(Get-ColorForBool $st.AntivirusEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Antispyware habilitado"; Valor=(Get-SafeProp $st "AntispywareEnabled"); Color=(Get-ColorForBool $st.AntispywareEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Servicio AM"; Valor=(Get-SafeProp $st "AMServiceEnabled"); Color=(Get-ColorForBool $st.AMServiceEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Proteccion tiempo real"; Valor=(Get-SafeProp $st "RealTimeProtectionEnabled"); Color=(Get-ColorForBool $st.RealTimeProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Monitor comportamiento"; Valor=(Get-SafeProp $st "BehaviorMonitorEnabled"); Color=(Get-ColorForBool $st.BehaviorMonitorEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="IOAV Protection"; Valor=(Get-SafeProp $st "IoavProtectionEnabled"); Color=(Get-ColorForBool $st.IoavProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="On-Access Protection"; Valor=(Get-SafeProp $st "OnAccessProtectionEnabled"); Color=(Get-ColorForBool $st.OnAccessProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Inspeccion red (NIS)"; Valor=(Get-SafeProp $st "NISEnabled"); Color=(Get-ColorForBool $st.NISEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Tamper Protection"; Valor=(Get-SafeProp $st "IsTamperProtected"); Color=(Get-ColorForBool $st.IsTamperProtected) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version motor"; Valor=(Get-SafeProp $st "AMEngineVersion"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version firma"; Valor=(Get-SafeProp $st "AntivirusSignatureVersion"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Edad firma (dias)"; Valor=(Get-SafeProp $st "AntivirusSignatureAge"); Color=$null })
        } catch { }
    }
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        try {
            $p = Get-MpPreference -ErrorAction Stop
            $maps = switch ([int]$p.MAPSReporting) { 0 {"Desactivado"} 1 {"Basico"} 2 {"Avanzado"} default {"Desconocido"} }
            $mc = if ([int]$p.MAPSReporting -eq 2) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Nube (MAPS)"; Valor=$maps; Color=$mc })
            $sm = switch ([int]$p.SubmitSamplesConsent) { 0 {"Preguntar"} 1 {"Enviar seguras"} 2 {"Nunca"} 3 {"Siempre"} default {"?"} }
            $sc = if ([int]$p.SubmitSamplesConsent -in 1,3) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Envio muestras"; Valor=$sm; Color=$sc })
        } catch { }
    }
    $hp = Test-DefenderPolicyDisabled
    $pc = if ($hp) { $script:Colors.Bad } else { $script:Colors.Ok }
    [void]$report.Add([PSCustomObject]@{ Modulo="Politica bloqueante"; Valor=$(if($hp){"SI"}else{"NO"}); Color=$pc })
    return $report
}

# ==================================================================
# 14. AUTODIAGNOSTICO
# ==================================================================
function Get-DiagnosticReport {
    $r = New-Object System.Collections.ArrayList
    $pv = $PSVersionTable.PSVersion
    if ($pv.Major -ge 5) { [void]$r.Add([PSCustomObject]@{Item="PowerShell"; Status="OK"; Detail="$($pv.Major).$($pv.Minor)"; Color=$script:Colors.Ok}) }
    else { [void]$r.Add([PSCustomObject]@{Item="PowerShell"; Status="FALLA"; Detail="Se requiere 5.1+"; Color=$script:Colors.Bad}) }
    try { $nv = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop).Version; [void]$r.Add([PSCustomObject]@{Item=".NET Framework"; Status="OK"; Detail=$nv; Color=$script:Colors.Ok}) }
    catch { [void]$r.Add([PSCustomObject]@{Item=".NET Framework"; Status="AVISO"; Detail="No detectado"; Color=$script:Colors.Warn}) }
    if (Test-Admin) { [void]$r.Add([PSCustomObject]@{Item="Permisos"; Status="OK"; Detail="Administrador"; Color=$script:Colors.Ok}) }
    else { [void]$r.Add([PSCustomObject]@{Item="Permisos"; Status="FALLA"; Detail="No es Administrador"; Color=$script:Colors.Bad}) }
    try { $null = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; [void]$r.Add([PSCustomObject]@{Item="WMI"; Status="OK"; Detail="Funcionando"; Color=$script:Colors.Ok}) }
    catch { [void]$r.Add([PSCustomObject]@{Item="WMI"; Status="FALLA"; Detail="No responde"; Color=$script:Colors.Bad}) }
    try {
        $d = Get-PSDrive C -ErrorAction Stop
        $freeGB = [math]::Round($d.Free / 1GB, 1)
        if ($freeGB -gt 5) { [void]$r.Add([PSCustomObject]@{Item="Disco C:"; Status="OK"; Detail="$freeGB GB"; Color=$script:Colors.Ok}) }
        else { [void]$r.Add([PSCustomObject]@{Item="Disco C:"; Status="AVISO"; Detail="$freeGB GB"; Color=$script:Colors.Warn}) }
    } catch { }
    try { [void]$r.Add([PSCustomObject]@{Item="ExecutionPolicy"; Status="INFO"; Detail=(Get-ExecutionPolicy); Color=$script:Colors.TextDiag}) } catch { }
    if (Test-ScriptIntegrity) { [void]$r.Add([PSCustomObject]@{Item="Integridad SHA256"; Status="OK"; Detail=$script:ScriptHash; Color=$script:Colors.Ok}) }
    else { [void]$r.Add([PSCustomObject]@{Item="Integridad"; Status="AVISO"; Detail="No verificable"; Color=$script:Colors.Warn}) }
    return $r
}

# ==================================================================
# 15. PERFILES
# ==================================================================
function Apply-Profile {
    param([string]$Nombre)
    $profiles = @{
        "Gaming" = @{ RTP=$false; MAPS="Advanced"; Samples=1 }
        "Desarrollo" = @{ RTP=$true; MAPS="Advanced"; Samples=3 }
        "Maxima Seguridad" = @{ RTP=$true; MAPS="Advanced"; Samples=1 }
        "Personalizado" = @{ RTP=$null; MAPS=$null; Samples=$null }
    }
    if (-not $profiles.ContainsKey($Nombre)) { return "Perfil no encontrado." }
    $p = $profiles[$Nombre]
    try {
        if ($null -ne $p.RTP -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
            Set-MpPreference -DisableRealtimeMonitoring (-not [bool]$p.RTP) -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $p.MAPS -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
            Set-MpPreference -MAPSReporting $p.MAPS -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $p.Samples -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
            Set-MpPreference -SubmitSamplesConsent $p.Samples -Force -ErrorAction SilentlyContinue
        }
        return "Perfil '$Nombre' aplicado."
    } catch { return "Error: $($_.Exception.Message)" }
}

# ==================================================================
# 16. BACKUP
# ==================================================================
function Export-ConfigBackup {
    param([string]$Destino)
    try {
        $data = @{ Fecha=(Get-Date).ToString("s"); Version="4.2"; AppConfig=$script:AppConfig }
        $data | ConvertTo-Json -Depth 6 | Set-Content -Path $Destino -Encoding UTF8 -Force
        return $true
    } catch { return $false }
}

# ==================================================================
# 17. SCHEDULER
# ==================================================================
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
function Unregister-TrayTask { param([string]$Nombre)
    try { Unregister-ScheduledTask -TaskName "DefenderTray_$Nombre" -Confirm:$false -ErrorAction Stop; return $true } catch { return $false }
}
function Get-TrayTasks {
    try { return Get-ScheduledTask -TaskName "DefenderTray_*" -ErrorAction SilentlyContinue } catch { return @() }
}

# ==================================================================
# 18. FIRMAS
# ==================================================================
function Update-DefenderSignatures {
    param([System.Windows.Forms.ProgressBar]$ProgressBar = $null)
    try {
        if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) { return "No disponible." }
        $job = Start-Job -ScriptBlock { Update-MpSignature -ErrorAction SilentlyContinue }
        $max = 0
        while ($job.State -eq 'Running') {
            $max = [math]::Min(95, $max + 2)
            if ($null -ne $ProgressBar -and -not $ProgressBar.IsDisposed) { $ProgressBar.Value = $max }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 300
        }
        if ($null -ne $ProgressBar -and -not $ProgressBar.IsDisposed) { $ProgressBar.Value = 100 }
        $null = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return "Firmas actualizadas."
    } catch { return "Error: $($_.Exception.Message)" }
}

# ==================================================================
# 19. EVENTOS
# ==================================================================
function Get-DefenderEvents {
    $result = New-Object System.Collections.ArrayList
    try {
        $events = Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents 100 -ErrorAction Stop
        foreach ($e in $events) {
            $tipo = switch ($e.Id) {
                1006 { "Malware detectado" }; 1007 { "Accion realizada" }; 1008 { "Accion fallida" }
                1009 { "Cuarentena restaurada" }; 1015 { "Comportamiento sospechoso" }
                1116 { "Deteccion" }; 1117 { "Accion aplicada" }
                default { "Evento $($e.Id)" }
            }
            [void]$result.Add([PSCustomObject]@{ Hora=$e.TimeCreated; Id=$e.Id; Tipo=$tipo; Mensaje=($e.Message -split "`n")[0] })
        }
    } catch { }
    return $result
}

# ==================================================================
# 20. TOAST
# ==================================================================
function Show-Toast {
    param([string]$Titulo, [string]$Mensaje, [string]$Tipo = "Info")
    if ($script:SilentMode) { return }
    try {
        $icon = switch ($Tipo) { "Warning" { [System.Windows.Forms.ToolTipIcon]::Warning } "Error" { [System.Windows.Forms.ToolTipIcon]::Error } default { [System.Windows.Forms.ToolTipIcon]::Info } }
        if ($null -ne $script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(4000, $Titulo, $Mensaje, $icon) }
    } catch { }
}

# ==================================================================
# 21. HASH / KIOSCO
# ==================================================================
function Get-StringHash {
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
}
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    $hashGuardado = $script:AppConfig['KioskHash']
    if ([string]::IsNullOrEmpty($hashGuardado)) { return $true }
    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"; $dlg.ClientSize = New-Object System.Drawing.Size(340, 160)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Contrasena:"; $lbl.Location = New-Object System.Drawing.Point(15, 20)
    $lbl.Size = New-Object System.Drawing.Size(300, 20); $lbl.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.PasswordChar = '*'; $txt.Location = New-Object System.Drawing.Point(15, 50); $txt.Size = New-Object System.Drawing.Size(300, 25)
    $txt.BackColor = $script:Colors.BgSecondary; $txt.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txt)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Acceder"; $btn.Location = New-Object System.Drawing.Point(215, 90); $btn.Size = New-Object System.Drawing.Size(100, 30)
    $btn.FlatStyle = "Flat"; $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $script:Colors.AccentCyan; $btn.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btn)
    $btn.Add_Click({
        $h = Get-StringHash $txt.Text
        if ($h -eq $hashGuardado) { $script:KioskOk = $true; $dlg.Close() }
    }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:KioskOk
}

# ==================================================================
# 22. DESACTIVAR
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                return ($log -join "`n")
            }
        }
    } catch {}
    Write-AppLog "Iniciando desactivacion..." "INFO"
    [void]$log.Add("[1] Preferencias...")
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            foreach ($pref in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                               "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                               "DisableEmailScanning","DisableIntrusionPreventionSystem","DisableRemovableDriveScanning",
                               "DisableScanningNetworkFiles")) {
                try { Set-MpPreference @{ $pref = $true } -Force -ErrorAction SilentlyContinue } catch { }
            }
            try { Set-MpPreference -MAPSReporting Disabled -Force -ErrorAction SilentlyContinue } catch { }
            try { Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue } catch { }
        }
    } catch { }
    [void]$log.Add("[2] Politicas (reg delete)...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }
    [void]$log.Add("[3] Recreando politicas...")
    $dp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $dp)) { New-Item -Path $dp -Force | Out-Null }
    Set-ItemProperty -Path $dp -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dp -Name "DisableAntiVirus" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $rtp = "$dp\Real-Time Protection"
    if (-not (Test-Path $rtp)) { New-Item -Path $rtp -Force | Out-Null }
    foreach ($v in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                     "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
        Set-ItemProperty -Path $rtp -Name $v -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    [void]$log.Add("[4] Servicios...")
    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService")) {
        try { $null = & sc.exe stop $s 2>&1; $null = & sc.exe config $s start= disabled 2>&1 } catch { }
    }
    [void]$log.Add("[5] Registro Start=4...")
    foreach ($sp in @("HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
                      "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
                      "HKLM:\SYSTEM\CurrentControlSet\Services\Sense")) {
        if (Test-Path $sp) { Set-ItemProperty -Path $sp -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue }
    }
    [void]$log.Add("[6] Verificando...")
    Wait-WithDoEvents -Milliseconds 3000
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        [void]$log.Add("[7] Reintentando...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= disabled 2>&1
    }
    $sw.Stop()
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    return ($log -join "`n")
}

# ==================================================================
# 23. ACTIVAR
# ==================================================================
function Enable-Defender {
    param([bool]$EnableCloud = $false, [bool]$EnableSamples = $false, [bool]$EnableTamper = $false)
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AppLog "Iniciando activacion..." "INFO"
    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter")) {
        $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (Test-Path $svcPath) { Set-ItemProperty -Path $svcPath -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue }
    }
    [void]$log.Add("[1] Start=2 restaurado.")
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (Test-Path $regPath) { Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop; [void]$log.Add("[2] Politicas eliminadas.") }
        else { [void]$log.Add("[2] Sin politicas.") }
    } catch { [void]$log.Add("[2] Fallback.") }
    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    if (Test-Path $rtWk) {
        foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                         "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
            Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue
        }
    }
    [void]$log.Add("[3] RTP limpiadas.")
    foreach ($s in @("WdNisSvc","Sense")) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
            $null = & sc.exe config $s start= auto 2>&1
            Start-Service -Name $s -ErrorAction SilentlyContinue
            [void]$log.Add("[4] $s INICIADO")
        }
    }
    try {
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= auto 2>&1
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("[5] WinDefend INICIADO")
    } catch { }
    Wait-WithDoEvents -Milliseconds 3000
    try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
    Wait-WithDoEvents -Milliseconds 1000
    try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
    if ($EnableCloud -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try { Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction Stop; [void]$log.Add("[7] MAPS ACTIVADO") }
        catch { [void]$log.Add("[7] Error nube") }
    }
    if ($EnableSamples -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try { Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction Stop; [void]$log.Add("[8] Muestras ACTIVADO") }
        catch { [void]$log.Add("[8] Error muestras") }
    }
    if ($EnableTamper) {
        $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        try {
            if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
            Set-ItemProperty -Path $tpPath -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tpPath -Name "TamperProtectionSource" -Value 1 -Type String -Force -ErrorAction SilentlyContinue
            [void]$log.Add("[9] Registro Tamper escrito.")
        } catch { }
    }
    $sw.Stop()
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    return ($log -join "`n")
}

# ==================================================================
# 24. ADMIN / OS / EXCLUSION / AUTOSTART / SERVICIO
# ==================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-OSInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{ Caption=$os.Caption; Version=$os.Version; BuildNumber=$os.BuildNumber }
    } catch { return [PSCustomObject]@{ Caption="Desconocido"; Version="?"; BuildNumber="?" } }
}
function Add-DefenderExclusion {
    try {
        $sp = $PSScriptRoot; if ([string]::IsNullOrWhiteSpace($sp)) { $sp = (Get-Location).Path }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $sp -Force -ErrorAction Stop
            return $true
        }
    } catch { }
    return $false
}
function Get-AutoStartEnabled {
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try { return ($null -ne (Get-ItemProperty -Path $runKey -Name "DefenderTray" -ErrorAction SilentlyContinue)) } catch { return $false }
}
function Set-AutoStart {
    param([bool]$Enable)
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        if ($Enable) {
            if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { return $false }
            $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
            Set-ItemProperty -Path $runKey -Name "DefenderTray" -Value $cmd -Force
            $script:AppConfig['AutoStart'] = $true
        } else {
            Remove-ItemProperty -Path $runKey -Name "DefenderTray" -Force -ErrorAction SilentlyContinue
            $script:AppConfig['AutoStart'] = $false
        }
        Save-AppConfig
        return $true
    } catch { return $false }
}
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

# ==================================================================
# 25. ICONOS
# ==================================================================
function New-ShieldBitmap {
    param([System.Drawing.Color]$FillColor, [int]$Size = 32)
    try {
        $bmp = New-Object System.Drawing.Bitmap $Size, $Size
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $pts = New-Object 'System.Drawing.Point[]' 6
        $pts[0] = New-Object System.Drawing.Point ([int]($Size*0.5)), ([int]($Size*0.05))
        $pts[1] = New-Object System.Drawing.Point ([int]($Size*0.9)), ([int]($Size*0.25))
        $pts[2] = New-Object System.Drawing.Point ([int]($Size*0.9)), ([int]($Size*0.55))
        $pts[3] = New-Object System.Drawing.Point ([int]($Size*0.5)), ([int]($Size*0.95))
        $pts[4] = New-Object System.Drawing.Point ([int]($Size*0.1)), ([int]($Size*0.55))
        $pts[5] = New-Object System.Drawing.Point ([int]($Size*0.1)), ([int]($Size*0.25))
        $brush = New-Object System.Drawing.SolidBrush $FillColor
        $g.FillPolygon($brush, $pts)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(0,229,255)), 1.5
        $g.DrawPolygon($pen, $pts)
        $g.Dispose(); $brush.Dispose(); $pen.Dispose()
        return $bmp
    } catch { return $null }
}
$script:IconBmpOk      = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(0, 200, 100))
$script:IconBmpBad     = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(220, 40, 80))
$script:IconBmpPartial = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(220, 140, 0))
$script:IconOk      = if ($null -ne $script:IconBmpOk)      { [System.Drawing.Icon]::FromHandle($script:IconBmpOk.GetHicon()) }      else { [System.Drawing.SystemIcons]::Shield }
$script:IconBad     = if ($null -ne $script:IconBmpBad)     { [System.Drawing.Icon]::FromHandle($script:IconBmpBad.GetHicon()) }     else { [System.Drawing.SystemIcons]::Error }
$script:IconPartial = if ($null -ne $script:IconBmpPartial) { [System.Drawing.Icon]::FromHandle($script:IconBmpPartial.GetHicon()) } else { [System.Drawing.SystemIcons]::Warning }

# ==================================================================
# 26. CONTROLES
# ==================================================================
function New-NeonButton {
    param([string]$Texto, [System.Drawing.Color]$Color, [System.Drawing.Color]$Hover,
          [int]$X, [int]$Y, [int]$Ancho = 180, [int]$Alto = 30)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Texto
    $b.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $Color
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Color
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Color; $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = "Hand"
    $b.Tag = @{ Normal = $Color; Hover = $Hover; Habilitado = $true }
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
        $Boton.Cursor = "Hand"; $Boton.Tag.Habilitado = $true
    } else {
        $Boton.BackColor = $script:Colors.BtnDisabled
        $Boton.ForeColor = $script:Colors.BtnDisabledT
        $Boton.FlatAppearance.BorderColor = $script:Colors.BtnDisabled
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnDisabled
        $Boton.Cursor = "Default"; $Boton.Tag.Habilitado = $false
    }
}

# ==================================================================
# 27. TOOLTIP
# ==================================================================
$script:Tooltip = New-Object System.Windows.Forms.ToolTip
$script:Tooltip.AutoPopDelay = 10000; $script:Tooltip.InitialDelay = 400; $script:Tooltip.ReshowDelay = 100; $script:Tooltip.ShowAlways = $true
function Set-Help {
    param([System.Windows.Forms.Control]$C, [string]$Tip)
    if ($null -eq $C) { return }
    try { $script:Tooltip.SetToolTip($C, $Tip) } catch { }
}

# ==================================================================
# 28. CONSOLA DE REPARACION - EJECUTOR EN TIEMPO REAL
# ==================================================================
function Invoke-ConsoleCommand {
    param(
        [System.Windows.Forms.TextBox]$Console,
        [string]$Comando,
        [string]$Titulo = ""
    )
    if ($null -eq $Console -or $Console.IsDisposed) { return 0 }

    # Encabezado
    $header = "`r`n=== $Titulo ===`r`n> $Comando`r`n"
    $Console.AppendText($header)
    $Console.SelectionStart = $Console.Text.Length
    $Console.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()

    # Guardar color actual
    $colorAnterior = $Console.ForeColor

    # Ejecutar comando
    try {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = "cmd.exe"
        $proc.StartInfo.Arguments = "/c $Comando"
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.CreateNoWindow = $true
        $proc.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(850)

        $proc.Start() | Out-Null

        # Leer salida en tiempo real
        while (-not $proc.HasExited) {
            if (-not $proc.StandardOutput.EndOfStream) {
                $linea = $proc.StandardOutput.ReadLine()
                if ($null -ne $linea) {
                    $Console.AppendText("$linea`r`n")
                    $Console.SelectionStart = $Console.Text.Length
                    $Console.ScrollToCaret()
                }
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }

        # Leer restantes
        $outRestante = $proc.StandardOutput.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($outRestante)) {
            $Console.AppendText($outRestante)
        }
        $errRestante = $proc.StandardError.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($errRestante)) {
            $Console.ForeColor = $script:Colors.ConsoleErr
            $Console.AppendText($errRestante)
            $Console.ForeColor = $colorAnterior
        }

        $exitCode = $proc.ExitCode
        $proc.Dispose()

        $Console.AppendText("[ExitCode: $exitCode]`r`n")
        $Console.SelectionStart = $Console.Text.Length
        $Console.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        return $exitCode
    } catch {
        $Console.ForeColor = $script:Colors.ConsoleErr
        $Console.AppendText("ERROR: $($_.Exception.Message)`r`n")
        $Console.ForeColor = $colorAnterior
        return -1
    }
}

# ==================================================================
# 29. DIALOGO DE REPARACION PROFUNDA
# ==================================================================
function Show-DeepRepairDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Reparacion Profunda - Windows Defender"
    $dlg.ClientSize = New-Object System.Drawing.Size(900, 680)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.MinimumSize = New-Object System.Drawing.Size(700, 500)
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconPartial

    # Header
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
    $lblH.Location = New-Object System.Drawing.Point(15, 10)
    $header.Controls.Add($lblH)
    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Ejecuta todos los comandos para restaurar Windows Defender"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 245, 220)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(17, 38)
    $header.Controls.Add($lblSub)

    # Consola
    $console = New-Object System.Windows.Forms.TextBox
    $console.Multiline = $true
    $console.ScrollBars = "Both"
    $console.ReadOnly = $true
    $console.WordWrap = $false
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.BorderStyle = "FixedSingle"
    $console.Location = New-Object System.Drawing.Point(15, 75)
    $console.Size = New-Object System.Drawing.Size(870, 480)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)

    # Panel de botones
    $pBotones = New-Object System.Windows.Forms.Panel
    $pBotones.Location = New-Object System.Drawing.Point(0, 565)
    $pBotones.Size = New-Object System.Drawing.Size(900, 110)
    $pBotones.Anchor = "Bottom,Left,Right"
    $pBotones.BackColor = $script:Colors.Bg
    $dlg.Controls.Add($pBotones)

    # Fila 1: comandos individuales
    $btnReg = New-NeonButton "1. Borrar Politicas" $script:Colors.AccentRed $script:Colors.AccentRedH 15 10 160 34
    $btnSvc = New-NeonButton "2. Reiniciar Servicios" $script:Colors.AccentAmber $script:Colors.AccentAmberH 185 10 180 34
    $btnGpu = New-NeonButton "3. gpupdate /force" $script:Colors.AccentPurple $script:Colors.AccentPurpH 375 10 160 34
    $btnSFC = New-NeonButton "4. sfc /scannow" $script:Colors.AccentBlue $script:Colors.AccentBlueH 545 10 150 34
    $btnDISM = New-NeonButton "5. DISM Restore" $script:Colors.AccentTeal $script:Colors.AccentCyanH 705 10 170 34
    $pBotones.Controls.Add($btnReg)
    $pBotones.Controls.Add($btnSvc)
    $pBotones.Controls.Add($btnGpu)
    $pBotones.Controls.Add($btnSFC)
    $pBotones.Controls.Add($btnDISM)

    # Fila 2: acciones compuestas
    $btnTodo = New-NeonButton "REPARAR TODO AUTOMATICAMENTE" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 55 350 40
    $btnVerificar = New-NeonButton "Verificar Estado" $script:Colors.AccentCyan $script:Colors.AccentCyanH 375 55 180 40
    $btnLimpiar = New-NeonButton "Limpiar Consola" $script:Colors.Neutral $script:Colors.TextMuted 565 55 140 40
    $btnCerrar = New-NeonButton "Cerrar" $script:Colors.AccentRed $script:Colors.AccentRedH 715 55 160 40
    $pBotones.Controls.Add($btnTodo)
    $pBotones.Controls.Add($btnVerificar)
    $pBotones.Controls.Add($btnLimpiar)
    $pBotones.Controls.Add($btnCerrar)

    # =============================================================
    # FUNCIONES INTERNAS (definidas antes de los handlers)
    # =============================================================
    $script:RepairBusy = $false

    function Set-RepairBusy {
        param([bool]$Estado)
        $script:RepairBusy = $Estado
        $btnReg.Enabled = -not $Estado
        $btnSvc.Enabled = -not $Estado
        $btnGpu.Enabled = -not $Estado
        $btnSFC.Enabled = -not $Estado
        $btnDISM.Enabled = -not $Estado
        $btnTodo.Enabled = -not $Estado
        $btnCerrar.Enabled = -not $Estado
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Write-Console {
        param([string]$Texto, [System.Drawing.Color]$Color = $null)
        if ($null -eq $Color) { $Color = $script:Colors.ConsoleText }
        $console.ForeColor = $Color
        $console.AppendText($Texto)
        $console.SelectionStart = $console.Text.Length
        $console.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    # =============================================================
    # COMANDO 1: BORRAR POLITICAS DE GRUPO
    # =============================================================
    $btnReg.Add_Click({
        Set-RepairBusy $true
        try {
            Write-Console "`r`n##########################################`r`n" $script:Colors.AccentRed
            Write-Console "# PASO 1: ELIMINANDO POLITICAS DE GRUPO #`r`n" $script:Colors.AccentRed
            Write-Console "##########################################`r`n" $script:Colors.AccentRed
            $rutas = @(
                "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies"
            )
            foreach ($r in $rutas) {
                Invoke-ConsoleCommand -Console $console -Comando "reg delete `"$r`" /f" -Titulo "Borrar: $r"
                Write-AppLog "reg delete $r" "INFO"
            }
            Write-Console "`r`n[OK] Politicas eliminadas.`r`n" $script:Colors.Ok
            Add-History -Accion "Reparacion: Politicas" -Resultado "OK" -Segundos 0
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # COMANDO 2: REINICIAR SERVICIOS
    # =============================================================
    $btnSvc.Add_Click({
        Set-RepairBusy $true
        try {
            Write-Console "`r`n##########################################`r`n" $script:Colors.AccentAmber
            Write-Console "# PASO 2: REINICIANDO SERVICIOS          #`r`n" $script:Colors.AccentAmber
            Write-Console "##########################################`r`n" $script:Colors.AccentAmber
            $servicios = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService")
            foreach ($s in $servicios) {
                Invoke-ConsoleCommand -Console $console -Comando "sc config $s start= auto" -Titulo "Config: $s"
                Invoke-ConsoleCommand -Console $console -Comando "sc start $s" -Titulo "Start: $s"
            }
            Write-Console "`r`n[OK] Servicios reiniciados.`r`n" $script:Colors.Ok
            Add-History -Accion "Reparacion: Servicios" -Resultado "OK" -Segundos 0
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # COMANDO 3: GPUPDATE /FORCE
    # =============================================================
    $btnGpu.Add_Click({
        Set-RepairBusy $true
        try {
            Write-Console "`r`n##########################################`r`n" $script:Colors.AccentPurple
            Write-Console "# PASO 3: GPUPDATE /FORCE                #`r`n" $script:Colors.AccentPurple
            Write-Console "##########################################`r`n" $script:Colors.AccentPurple
            Invoke-ConsoleCommand -Console $console -Comando "gpupdate /force" -Titulo "gpupdate"
            Write-Console "`r`n[OK] Politicas actualizadas.`r`n" $script:Colors.Ok
            Add-History -Accion "Reparacion: gpupdate" -Resultado "OK" -Segundos 0
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # COMANDO 4: SFC /SCANNOW
    # =============================================================
    $btnSFC.Add_Click({
        Set-RepairBusy $true
        try {
            Write-Console "`r`n##########################################`r`n" $script:Colors.AccentBlue
            Write-Console "# PASO 4: SFC /SCANNOW (puede tardar)    #`r`n" $script:Colors.AccentBlue
            Write-Console "##########################################`r`n" $script:Colors.AccentBlue
            Invoke-ConsoleCommand -Console $console -Comando "sfc /scannow" -Titulo "SFC"
            Write-Console "`r`n[OK] SFC completado.`r`n" $script:Colors.Ok
            Add-History -Accion "Reparacion: SFC" -Resultado "OK" -Segundos 0
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # COMANDO 5: DISM RESTORE
    # =============================================================
    $btnDISM.Add_Click({
        Set-RepairBusy $true
        try {
            Write-Console "`r`n##########################################`r`n" $script:Colors.AccentCyan
            Write-Console "# PASO 5: DISM RESTORE HEALTH            #`r`n" $script:Colors.AccentCyan
            Write-Console "##########################################`r`n" $script:Colors.AccentCyan
            Invoke-ConsoleCommand -Console $console -Comando "DISM /Online /Cleanup-Image /RestoreHealth" -Titulo "DISM"
            Write-Console "`r`n[OK] DISM completado.`r`n" $script:Colors.Ok
            Add-History -Accion "Reparacion: DISM" -Resultado "OK" -Segundos 0
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # REPARAR TODO
    # =============================================================
    $btnTodo.Add_Click({
        Set-RepairBusy $true
        $swTotal = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Console "`r`n" $script:Colors.Text
            Write-Console "====================================================`r`n" $script:Colors.AccentGreen
            Write-Console "      REPARACION AUTOMATICA COMPLETA                 `r`n" $script:Colors.AccentGreen
            Write-Console "====================================================`r`n" $script:Colors.AccentGreen
            Write-Console "Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n" $script:Colors.TextDiag

            # PASO 1
            Write-Console "`r`n[PASO 1] Eliminando politicas de grupo...`r`n" $script:Colors.AccentRed
            $rutas = @(
                "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies"
            )
            foreach ($r in $rutas) {
                Invoke-ConsoleCommand -Console $console -Comando "reg delete `"$r`" /f" -Titulo "Borrar"
            }

            # PASO 2
            Write-Console "`r`n[PASO 2] Reiniciando servicios...`r`n" $script:Colors.AccentAmber
            $servicios = @("WinDefend","WdNisSvc","Sense")
            foreach ($s in $servicios) {
                Invoke-ConsoleCommand -Console $console -Comando "sc config $s start= auto" -Titulo "Config $s"
                Invoke-ConsoleCommand -Console $console -Comando "sc start $s" -Titulo "Start $s"
            }

            # PASO 3
            Write-Console "`r`n[PASO 3] gpupdate /force...`r`n" $script:Colors.AccentPurple
            Invoke-ConsoleCommand -Console $console -Comando "gpupdate /force" -Titulo "gpupdate"

            # PASO 4: Aplicar Set-MpPreference
            Write-Console "`r`n[PASO 4] Reactivando protecciones via PowerShell...`r`n" $script:Colors.AccentGreen
            try {
                if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
                    Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
                    Set-MpPreference -DisableBehaviorMonitoring $false -Force -ErrorAction SilentlyContinue
                    Set-MpPreference -DisableIOAVProtection $false -Force -ErrorAction SilentlyContinue
                    Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
                    Write-Console "  [OK] Preferencias aplicadas.`r`n" $script:Colors.Ok
                }
            } catch { Write-Console "  [ERR] $($_.Exception.Message)`r`n" $script:Colors.Bad }

            # PASO 5: SFC
            Write-Console "`r`n[PASO 5] sfc /scannow (puede tardar varios minutos)...`r`n" $script:Colors.AccentBlue
            Invoke-ConsoleCommand -Console $console -Comando "sfc /scannow" -Titulo "SFC"

            # PASO 6: DISM
            Write-Console "`r`n[PASO 6] DISM RestoreHealth...`r`n" $script:Colors.AccentCyan
            Invoke-ConsoleCommand -Console $console -Comando "DISM /Online /Cleanup-Image /RestoreHealth" -Titulo "DISM"

            # Verificacion final
            Write-Console "`r`n[VERIFICACION FINAL]`r`n" $script:Colors.AccentPurple
            Wait-WithDoEvents -Milliseconds 2000
            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Write-Console "  WinDefend: $($svc.Status)`r`n" $(if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad })
            }
            try {
                $st = Get-MpComputerStatus -ErrorAction Stop
                Write-Console "  AntivirusEnabled: $($st.AntivirusEnabled)`r`n" $(if ($st.AntivirusEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
                Write-Console "  RealTimeProtection: $($st.RealTimeProtectionEnabled)`r`n" $(if ($st.RealTimeProtectionEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
                Write-Console "  Tamper: $($st.IsTamperProtected)`r`n" $script:Colors.TextDiag
            } catch {
                Write-Console "  Get-MpComputerStatus: $($_.Exception.Message)`r`n" $script:Colors.Bad
            }

            $swTotal.Stop()
            Write-Console "`r`n" $script:Colors.Text
            Write-Console "====================================================`r`n" $script:Colors.AccentGreen
            Write-Console "  REPARACION COMPLETADA EN $([math]::Round($swTotal.Elapsed.TotalSeconds,1))s`r`n" $script:Colors.AccentGreen
            Write-Console "  Reinicia el equipo para aplicar todos los cambios.`r`n" $script:Colors.Warn
            Write-Console "====================================================`r`n" $script:Colors.AccentGreen

            Add-History -Accion "Reparacion Completa" -Resultado "OK" -Segundos $swTotal.Elapsed.TotalSeconds
            Write-AppLog "Reparacion completa en $([math]::Round($swTotal.Elapsed.TotalSeconds,1))s" "INFO"

            [System.Windows.Forms.MessageBox]::Show(
                "Reparacion completada.`n`nReinicia el equipo para aplicar todos los cambios.",
                "Reparacion Finalizada", "OK", "Information") | Out-Null
        } catch {
            Write-Console "`r`n[ERROR] $($_.Exception.Message)`r`n" $script:Colors.Bad
        } finally { Set-RepairBusy $false }
    }.GetNewClosure())

    # =============================================================
    # VERIFICAR ESTADO
    # =============================================================
    $btnVerificar.Add_Click({
        Write-Console "`r`n--- VERIFICACION DE ESTADO ---`r`n" $script:Colors.AccentCyan
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            Write-Console "  WinDefend: $($svc.Status)`r`n" $(if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad })
        }
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            Write-Console "  AntivirusEnabled:      $($st.AntivirusEnabled)`r`n" $(if ($st.AntivirusEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
            Write-Console "  RealTimeProtection:    $($st.RealTimeProtectionEnabled)`r`n" $(if ($st.RealTimeProtectionEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
            Write-Console "  BehaviorMonitor:       $($st.BehaviorMonitorEnabled)`r`n" $(if ($st.BehaviorMonitorEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
            Write-Console "  IoavProtection:        $($st.IoavProtectionEnabled)`r`n" $(if ($st.IoavProtectionEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
            Write-Console "  OnAccessProtection:    $($st.OnAccessProtectionEnabled)`r`n" $(if ($st.OnAccessProtectionEnabled) { $script:Colors.Ok } else { $script:Colors.Bad })
            Write-Console "  Tamper:                $($st.IsTamperProtected)`r`n" $script:Colors.TextDiag
        } catch {
            Write-Console "  Error: $($_.Exception.Message)`r`n" $script:Colors.Bad
        }
        $hp = Test-DefenderPolicyDisabled
        Write-Console "  Politica bloqueante:   $(if($hp){'SI'}else{'NO'})`r`n" $(if($hp){$script:Colors.Bad}else{$script:Colors.Ok})
    }.GetNewClosure())

    # =============================================================
    # LIMPIAR CONSOLA
    # =============================================================
    $btnLimpiar.Add_Click({ $console.Text = "" }.GetNewClosure())

    # =============================================================
    # CERRAR
    # =============================================================
    $btnCerrar.Add_Click({ $dlg.Close() }.GetNewClosure())

    # Encabezado inicial en consola
    Write-Console "====================================================`r`n" $script:Colors.AccentAmber
    Write-Console "  CONSOLA DE REPARACION - DefenderTray v4.2         `r`n" $script:Colors.AccentAmber
    Write-Console "====================================================`r`n" $script:Colors.AccentAmber
    Write-Console "`r`nPuedes ejecutar cada paso individualmente o pulsar`r`n" $script:Colors.Text
    Write-Console "`"REPARAR TODO AUTOMATICAMENTE`" para ejecutar todo.`r`n`r`n" $script:Colors.Text
    Write-Console "Los comandos se ejecutan en tiempo real en esta consola.`r`n" $script:Colors.TextDiag

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 30. VERIFICACION COMPLETA
# ==================================================================
function Update-CompleteStatusView {
    param([System.Windows.Forms.ListView]$ListView, [System.Windows.Forms.Label]$StatusLabel)
    if ($null -eq $ListView -or $ListView.IsDisposed) { return }
    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        foreach ($row in (Get-CompleteDefenderReport)) {
            $it = New-Object System.Windows.Forms.ListViewItem($row.Modulo)
            [void]$it.SubItems.Add([string]$row.Valor)
            if ($null -ne $row.Color) { $it.ForeColor = $row.Color }
            [void]$ListView.Items.Add($it)
        }
    } finally { $ListView.EndUpdate() }
    $q = Get-QuickStatus
    if ($q.Estado -eq "ACTIVO") {
        $StatusLabel.Text = ">>> " + $script:S.Activo + " <<<"
        $StatusLabel.ForeColor = $script:Colors.Ok
    } elseif ($q.Estado -eq "PARCIAL") {
        $StatusLabel.Text = ">>> " + $script:S.Parcial + " <<<"
        $StatusLabel.ForeColor = $script:Colors.Warn
    } else {
        $StatusLabel.Text = ">>> " + $script:S.Desactivado + " <<<"
        $StatusLabel.ForeColor = $script:Colors.Bad
    }
}
function Show-CompleteStatusDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Verificacion completa"
    $dlg.ClientSize = New-Object System.Drawing.Size(680, 600)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60; $header.BackColor = $script:Colors.AccentPurple
    $dlg.Controls.Add($header)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "VERIFICACION COMPLETA"
    $lbl.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::White; $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoSize = $true; $lbl.Location = New-Object System.Drawing.Point(15, 18)
    $header.Controls.Add($lbl)
    $lblEstado = New-Object System.Windows.Forms.Label
    $lblEstado.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblEstado.AutoSize = $false; $lblEstado.Size = New-Object System.Drawing.Size(650, 24)
    $lblEstado.Location = New-Object System.Drawing.Point(15, 68); $lblEstado.TextAlign = "MiddleLeft"
    $lblEstado.BackColor = [System.Drawing.Color]::Transparent; $lblEstado.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lblEstado)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true; $lv.GridLines = $false
    $lv.HeaderStyle = "Nonclickable"; $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 100); $lv.Size = New-Object System.Drawing.Size(650, 430)
    $lv.BorderStyle = "FixedSingle"; $lv.BackColor = $script:Colors.BgSecondary; $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Modulo", 300); [void]$lv.Columns.Add("Estado", 320)
    $dlg.Controls.Add($lv)
    $btnRef = New-NeonButton "Refrescar" $script:Colors.AccentPurple $script:Colors.AccentPurpH 15 545 140 32
    $btnRep = New-NeonButton "REPARAR" $script:Colors.AccentAmber $script:Colors.AccentAmberH 165 545 160 32
    $btnCop = New-NeonButton "Copiar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 335 545 140 32
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 525 545 140 32
    $dlg.Controls.Add($btnRef); $dlg.Controls.Add($btnRep); $dlg.Controls.Add($btnCop); $dlg.Controls.Add($btnCerr)
    Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado
    $btnRef.Add_Click({ Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado }.GetNewClosure())
    $btnRep.Add_Click({ Show-DeepRepairDialog }.GetNewClosure())
    $btnCop.Add_Click({
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("VERIFICACION COMPLETA - WINDOWS DEFENDER")
        [void]$sb.AppendLine(("Fecha: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)))
        [void]$sb.AppendLine("Estado: $($lblEstado.Text)")
        [void]$sb.AppendLine("------------------------------------")
        foreach ($it in $lv.Items) { [void]$sb.AppendLine(("{0,-40} {1}" -f $it.Text, $it.SubItems[1].Text)) }
        try { [System.Windows.Forms.Clipboard]::SetText($sb.ToString()); [System.Windows.Forms.MessageBox]::Show("Copiado.","OK","OK","Information") | Out-Null } catch { }
    }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 31. HISTORIAL
# ==================================================================
function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial"; $dlg.ClientSize = New-Object System.Drawing.Size(700, 500)
    $dlg.StartPosition = "CenterScreen"; $dlg.Icon = $script:IconOk
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "HISTORIAL"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true; $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 70); $lv.Size = New-Object System.Drawing.Size(670, 380)
    $lv.BorderStyle = "FixedSingle"; $lv.BackColor = $script:Colors.BgSecondary; $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 160); [void]$lv.Columns.Add("Accion", 130)
    [void]$lv.Columns.Add("Resultado", 280); [void]$lv.Columns.Add("Seg", 80)
    foreach ($e in $script:EventHistory) {
        $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$it.SubItems.Add($e.Accion); [void]$it.SubItems.Add($e.Resultado); [void]$it.SubItems.Add(("{0:N2}" -f $e.Segundos))
        if ($e.Resultado -match "OK|activado|desactivado") { $it.ForeColor = $script:Colors.Ok }
        elseif ($e.Resultado -match "parcial|ERROR") { $it.ForeColor = $script:Colors.Bad }
        [void]$lv.Items.Add($it)
    }
    $dlg.Controls.Add($lv)
    $btnCsv = New-NeonButton "Abrir CSV" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 460 140 30
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 460 140 30
    $dlg.Controls.Add($btnCsv); $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnCsv.Add_Click({
        if (Test-Path $script:CsvFile) { Start-Process "notepad.exe" -ArgumentList $script:CsvFile }
    }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 32. EVENTOS
# ==================================================================
function Show-EventsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Eventos"; $dlg.ClientSize = New-Object System.Drawing.Size(820, 600)
    $dlg.StartPosition = "CenterScreen"; $dlg.Icon = $script:IconOk
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentRed
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "EVENTOS"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $lblBuscar = New-Object System.Windows.Forms.Label
    $lblBuscar.Text = "Filtrar:"; $lblBuscar.ForeColor = $script:Colors.Text
    $lblBuscar.Location = New-Object System.Drawing.Point(15, 70); $lblBuscar.Size = New-Object System.Drawing.Size(60, 25)
    $dlg.Controls.Add($lblBuscar)
    $txtBuscar = New-Object System.Windows.Forms.TextBox
    $txtBuscar.Location = New-Object System.Drawing.Point(80, 68); $txtBuscar.Size = New-Object System.Drawing.Size(720, 25)
    $txtBuscar.BackColor = $script:Colors.BgSecondary; $txtBuscar.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($txtBuscar)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true; $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 105); $lv.Size = New-Object System.Drawing.Size(790, 440)
    $lv.BorderStyle = "FixedSingle"; $lv.BackColor = $script:Colors.BgSecondary; $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 160); [void]$lv.Columns.Add("ID", 60); [void]$lv.Columns.Add("Tipo", 220); [void]$lv.Columns.Add("Mensaje", 320)
    $dlg.Controls.Add($lv)
    $script:AllEvents = Get-DefenderEvents
    $script:RefrescarEventos = {
        $filtro = $txtBuscar.Text
        $lv.Items.Clear()
        foreach ($e in $script:AllEvents) {
            if (-not [string]::IsNullOrEmpty($filtro)) {
                if (-not ($e.Tipo -match $filtro -or $e.Mensaje -match $filtro -or "$($e.Id)" -match $filtro)) { continue }
            }
            $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
            [void]$it.SubItems.Add($e.Id); [void]$it.SubItems.Add($e.Tipo); [void]$it.SubItems.Add($e.Mensaje)
            if ($e.Id -in 1006,1116,1015) { $it.ForeColor = $script:Colors.Bad }
            elseif ($e.Id -in 1007,1117) { $it.ForeColor = $script:Colors.Warn }
            else { $it.ForeColor = $script:Colors.TextDiag }
            [void]$lv.Items.Add($it)
        }
    }
    & $script:RefrescarEventos
    $btnFiltrar = New-NeonButton "Filtrar" $script:Colors.AccentBlue $script:Colors.AccentBlueH 15 555 140 30
    $btnRecargar = New-NeonButton "Recargar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 165 555 140 30
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 665 555 140 30
    $dlg.Controls.Add($btnFiltrar); $dlg.Controls.Add($btnRecargar); $dlg.Controls.Add($btnCerr)
    $btnFiltrar.Add_Click($script:RefrescarEventos)
    $btnRecargar.Add_Click({
        $script:AllEvents = Get-DefenderEvents
        & $script:RefrescarEventos
    }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 33. CHART
# ==================================================================
function Show-ChartDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Estadisticas"; $dlg.ClientSize = New-Object System.Drawing.Size(780, 540)
    $dlg.StartPosition = "CenterScreen"; $dlg.Icon = $script:IconOk
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "ESTADISTICAS"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    try {
        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Location = New-Object System.Drawing.Point(15, 70); $chart.Size = New-Object System.Drawing.Size(750, 420)
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
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 625 500 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 34. PERFILES
# ==================================================================
function Show-ProfilesDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Perfiles"; $dlg.ClientSize = New-Object System.Drawing.Size(560, 460)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentGreen
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "PERFILES"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $rbGaming = New-Object System.Windows.Forms.RadioButton
    $rbGaming.Text = "Gaming"; $rbGaming.Location = New-Object System.Drawing.Point(20, 100)
    $rbGaming.Size = New-Object System.Drawing.Size(520, 40); $rbGaming.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($rbGaming)
    $rbDev = New-Object System.Windows.Forms.RadioButton
    $rbDev.Text = "Desarrollo"; $rbDev.Location = New-Object System.Drawing.Point(20, 150)
    $rbDev.Size = New-Object System.Drawing.Size(520, 40); $rbDev.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($rbDev)
    $rbMax = New-Object System.Windows.Forms.RadioButton
    $rbMax.Text = "Maxima Seguridad"; $rbMax.Location = New-Object System.Drawing.Point(20, 200)
    $rbMax.Size = New-Object System.Drawing.Size(520, 40); $rbMax.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($rbMax)
    $rbPers = New-Object System.Windows.Forms.RadioButton
    $rbPers.Text = "Personalizado"; $rbPers.Location = New-Object System.Drawing.Point(20, 250)
    $rbPers.Size = New-Object System.Drawing.Size(520, 40); $rbPers.ForeColor = $script:Colors.Text
    $rbPers.Checked = $true; $dlg.Controls.Add($rbPers)
    $btnAplicar = New-NeonButton "Aplicar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 400 200 34
    $btnCancelar = New-NeonButton "Cancelar" $script:Colors.Neutral $script:Colors.TextMuted 380 400 140 34
    $dlg.Controls.Add($btnAplicar); $dlg.Controls.Add($btnCancelar)
    $btnCancelar.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnAplicar.Add_Click({
        $nombre = "Personalizado"
        if ($rbGaming.Checked) { $nombre = "Gaming" }
        elseif ($rbDev.Checked) { $nombre = "Desarrollo" }
        elseif ($rbMax.Checked) { $nombre = "Maxima Seguridad" }
        $log = Apply-Profile -Nombre $nombre
        [System.Windows.Forms.MessageBox]::Show($log, "Perfil", "OK", "Information") | Out-Null
        Add-History -Accion "Perfil: $nombre" -Resultado "OK" -Segundos 0
        $dlg.Close()
    }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 35. BACKUP
# ==================================================================
function Show-BackupDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Backup"; $dlg.ClientSize = New-Object System.Drawing.Size(560, 340)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentCyan
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "BACKUP"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $btnExport = New-NeonButton "EXPORTAR" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 150 200 40
    $btnImport = New-NeonButton "ABRIR CARPETA" $script:Colors.AccentCyan $script:Colors.AccentCyanH 240 150 200 40
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 240 210 200 40
    $dlg.Controls.Add($btnExport); $dlg.Controls.Add($btnImport); $dlg.Controls.Add($btnCerr)
    $btnExport.Add_Click({
        $nombre = "backup_{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date)
        $dst = Join-Path $script:BackupDir $nombre
        if (Export-ConfigBackup -Destino $dst) {
            [System.Windows.Forms.MessageBox]::Show("Backup creado:`n$dst","OK","OK","Information") | Out-Null
        }
    }.GetNewClosure())
    $btnImport.Add_Click({ Start-Process "explorer.exe" -ArgumentList $script:BackupDir }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 36. SCHEDULER
# ==================================================================
function Show-SchedulerDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Programador"; $dlg.ClientSize = New-Object System.Drawing.Size(620, 480)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentPurple
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "PROGRAMADOR"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text = "Desactivar:"; $lbl1.ForeColor = $script:Colors.Text
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
    $lbl2.Text = "Activar:"; $lbl2.ForeColor = $script:Colors.Text
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
    $btnGuardar = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 405 180 34
    $btnEliminar = New-NeonButton "Eliminar" $script:Colors.AccentRed $script:Colors.AccentRedH 210 405 180 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 420 405 180 34
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
        [System.Windows.Forms.MessageBox]::Show("Tareas programadas.","Programador","OK","Information") | Out-Null
    }.GetNewClosure())
    $btnEliminar.Add_Click({
        Unregister-TrayTask -Nombre "Desactivar" | Out-Null
        Unregister-TrayTask -Nombre "Activar" | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Tareas eliminadas.","Programador","OK","Information") | Out-Null
        $dlg.Close()
    }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 37. FIRMAS
# ==================================================================
function Show-SignaturesDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Firmas"; $dlg.ClientSize = New-Object System.Drawing.Size(520, 240)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentCyan
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "ACTUALIZAR FIRMAS"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $progBar = New-Object System.Windows.Forms.ProgressBar
    $progBar.Location = New-Object System.Drawing.Point(20, 110); $progBar.Size = New-Object System.Drawing.Size(480, 25)
    $dlg.Controls.Add($progBar)
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Listo."; $lblStatus.ForeColor = $script:Colors.TextMuted
    $lblStatus.Location = New-Object System.Drawing.Point(20, 140); $lblStatus.Size = New-Object System.Drawing.Size(480, 25)
    $dlg.Controls.Add($lblStatus)
    $btnUpd = New-NeonButton "Actualizar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 175 200 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 320 175 180 34
    $dlg.Controls.Add($btnUpd); $dlg.Controls.Add($btnCerr)
    $btnUpd.Add_Click({
        $lblStatus.Text = "Actualizando..."
        $r = Update-DefenderSignatures -ProgressBar $progBar
        $lblStatus.Text = $r
        Add-History -Accion "Update Firmas" -Resultado "OK" -Segundos 0
    }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 38. DIAGNOSTICO
# ==================================================================
function Show-DiagnosticsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Diagnostico"; $dlg.ClientSize = New-Object System.Drawing.Size(680, 520)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentAmber
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "DIAGNOSTICO"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true; $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 70); $lv.Size = New-Object System.Drawing.Size(650, 400)
    $lv.BorderStyle = "FixedSingle"; $lv.BackColor = $script:Colors.BgSecondary; $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Componente", 200); [void]$lv.Columns.Add("Estado", 100); [void]$lv.Columns.Add("Detalle", 340)
    foreach ($d in (Get-DiagnosticReport)) {
        $it = New-Object System.Windows.Forms.ListViewItem($d.Item)
        [void]$it.SubItems.Add($d.Status); [void]$it.SubItems.Add($d.Detail)
        $it.ForeColor = $d.Color
        [void]$lv.Items.Add($it)
    }
    $dlg.Controls.Add($lv)
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 480 120 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 39. CONFIGURACION
# ==================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"; $dlg.ClientSize = New-Object System.Drawing.Size(560, 560)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "CONFIGURACION"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $chkDark = New-Object System.Windows.Forms.CheckBox
    $chkDark.Text = "Tema oscuro"; $chkDark.Checked = $script:DarkTheme
    $chkDark.Location = New-Object System.Drawing.Point(20, 80); $chkDark.Size = New-Object System.Drawing.Size(500, 25)
    $chkDark.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkDark)
    $chkAuto = New-Object System.Windows.Forms.CheckBox
    $chkAuto.Text = "Iniciar con Windows"; $chkAuto.Checked = (Get-AutoStartEnabled)
    $chkAuto.Location = New-Object System.Drawing.Point(20, 115); $chkAuto.Size = New-Object System.Drawing.Size(500, 25)
    $chkAuto.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkAuto)
    $chkKiosk = New-Object System.Windows.Forms.CheckBox
    $chkKiosk.Text = "Modo kiosco"; $chkKiosk.Checked = $script:IsKioskMode
    $chkKiosk.Location = New-Object System.Drawing.Point(20, 150); $chkKiosk.Size = New-Object System.Drawing.Size(500, 25)
    $chkKiosk.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkKiosk)
    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = "Contrasena:"; $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(40, 185); $lblPwd.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblPwd)
    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'; $txtPwd.Location = New-Object System.Drawing.Point(160, 183)
    $txtPwd.Size = New-Object System.Drawing.Size(340, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary; $txtPwd.ForeColor = $script:Colors.Text
    $txtPwd.Enabled = $script:IsKioskMode
    $dlg.Controls.Add($txtPwd)
    $btnInstallSvc = New-NeonButton "Instalar servicio" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 260 200 34
    $btnUninstallSvc = New-NeonButton "Desinstalar" $script:Colors.AccentRed $script:Colors.AccentRedH 240 260 200 34
    $dlg.Controls.Add($btnInstallSvc); $dlg.Controls.Add($btnUninstallSvc)
    $btnRestore = New-NeonButton "Restaurar" $script:Colors.AccentRed $script:Colors.AccentRedH 20 320 200 34
    $btnSave = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 240 320 200 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 240 370 200 34
    $btnHelp = New-NeonButton "Ayuda" $script:Colors.AccentBlue $script:Colors.AccentBlueH 20 370 200 34
    $dlg.Controls.Add($btnRestore); $dlg.Controls.Add($btnSave)
    $dlg.Controls.Add($btnCerr); $dlg.Controls.Add($btnHelp)
    $chkKiosk.Add_CheckedChanged({ $txtPwd.Enabled = $chkKiosk.Checked }.GetNewClosure())
    $btnSave.Add_Click({
        $script:DarkTheme = $chkDark.Checked
        $script:IsKioskMode = $chkKiosk.Checked
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:AppConfig['KioskHash'] = Get-StringHash $txtPwd.Text
        }
        Set-AutoStart -Enable $chkAuto.Checked | Out-Null
        Save-AppConfig
        Refresh-Palette
        [System.Windows.Forms.MessageBox]::Show("Guardado.","OK","OK","Information") | Out-Null
    }.GetNewClosure())
    $btnRestore.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show("Restaurar?","Confirmar","YesNo","Warning") -eq "Yes") {
            $script:AppConfig['DarkTheme'] = $true; $script:AppConfig['KioskMode'] = $false
            $script:AppConfig['KioskHash'] = ""; $script:AppConfig['AutoStart'] = $false
            Set-AutoStart -Enable $false | Out-Null; Save-AppConfig
        }
    }.GetNewClosure())
    $btnInstallSvc.Add_Click({
        $r = Install-AsService
        [System.Windows.Forms.MessageBox]::Show($r, "Instalar", "OK", "Information") | Out-Null
    }.GetNewClosure())
    $btnUninstallSvc.Add_Click({
        $r = Uninstall-AsService
        [System.Windows.Forms.MessageBox]::Show($r, "Desinstalar", "OK", "Information") | Out-Null
    }.GetNewClosure())
    $btnHelp.Add_Click({ Show-HelpDialog })
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 40. AYUDA
# ==================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(760, 600)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "AYUDA"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"; $tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Controls.Add($tabs)
    $dlg.Controls.SetChildIndex($tabs, 0)

    $txtIntro = @'
CONTROL DE SEGURIDAD - v4.2
=============================

Nueva version con modulo de REPARACION PROFUNDA integrada.

CARACTERISTICAS NUEVAS v4.2
---------------------------
- Reparacion Profunda con consola en vivo.
- Ejecuta reg delete, sc config, gpupdate, sfc, DISM.
- Todos los comandos visibles en tiempo real.
- Boton "REPARAR TODO" ejecuta la secuencia completa.

REPARACION PROFUNDA
-------------------
Accesible desde:
  * Boton "Diagnostico" del panel (dentro del dialogo)
  * Menu contextual -> "Reparacion Profunda"

Pasos disponibles:
  1. Borrar Politicas (reg delete)
  2. Reiniciar Servicios (sc config + sc start)
  3. gpupdate /force
  4. sfc /scannow
  5. DISM /Online /Cleanup-Image /RestoreHealth

FIX v4.2
--------
- AppConfig ahora usa notacion de indice (siempre funciona).
- Todos los comandos de reparacion integrados en consola.

Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801 / +53 5 9860911
'@
    $t1 = New-Object System.Windows.Forms.TabPage
    $t1.Text = "Introduccion"; $t1.BackColor = $script:Colors.Bg; $t1.Padding = New-Object System.Windows.Forms.Padding(15)
    $tb1 = New-Object System.Windows.Forms.TextBox
    $tb1.Multiline = $true; $tb1.ReadOnly = $true; $tb1.ScrollBars = "Vertical"
    $tb1.Dock = "Fill"; $tb1.BorderStyle = "None"
    $tb1.BackColor = $script:Colors.Bg; $tb1.ForeColor = $script:Colors.Text
    $tb1.Font = New-Object System.Drawing.Font("Consolas", 9); $tb1.Text = $txtIntro
    $t1.Controls.Add($tb1); [void]$tabs.TabPages.Add($t1)

    $txtRep = @'
REPARACION PROFUNDA - GUIA
==========================

Cuando usarla:
  Cuando Defender queda en estado "PROTECCION PARCIAL"
  y no se puede activar normalmente.

PASOS MANUALES
--------------
1. Borrar Politicas
   Ejecuta "reg delete" en las 4 rutas criticas que
   bloquean Defender.

2. Reiniciar Servicios
   Configura y arranca: WinDefend, WdNisSvc, Sense.

3. gpupdate /force
   Fuerza la actualizacion de politicas de grupo.

4. sfc /scannow
   Verifica y repara archivos de sistema corruptos.
   Puede tardar 5-15 minutos.

5. DISM RestoreHealth
   Repara la imagen de Windows.
   Puede tardar 10-30 minutos.

REPARACION AUTOMATICA
---------------------
El boton "REPARAR TODO AUTOMATICAMENTE" ejecuta los
5 pasos en secuencia. Los resultados se ven en la
consola en tiempo real.

IMPORTANTE
----------
- Despues de reparar, REINICIA el equipo.
- Si algun paso falla, la consola mostrara el error.
- Los comandos requieren permisos de Administrador.
'@
    $t2 = New-Object System.Windows.Forms.TabPage
    $t2.Text = "Reparacion"; $t2.BackColor = $script:Colors.Bg; $t2.Padding = New-Object System.Windows.Forms.Padding(15)
    $tb2 = New-Object System.Windows.Forms.TextBox
    $tb2.Multiline = $true; $tb2.ReadOnly = $true; $tb2.ScrollBars = "Vertical"
    $tb2.Dock = "Fill"; $tb2.BorderStyle = "None"
    $tb2.BackColor = $script:Colors.Bg; $tb2.ForeColor = $script:Colors.Text
    $tb2.Font = New-Object System.Drawing.Font("Consolas", 9); $tb2.Text = $txtRep
    $t2.Controls.Add($tb2); [void]$tabs.TabPages.Add($t2)

    $txtProblemas = @'
SOLUCION DE PROBLEMAS
=====================

ESTADO "PROTECCION PARCIAL"
---------------------------
Windows reporta que Defender esta activo pero en
realidad solo corre el servicio. Las protecciones
internas estan desactivadas.

Solucion:
  1. Abre Reparacion Profunda.
  2. Pulsa REPARAR TODO.
  3. Reinicia el equipo.

TAMPER PROTECTION ACTIVA
------------------------
Desactivala manualmente en:
  Seguridad de Windows
  -> Proteccion antivirus y contra amenazas
  -> Administrar la configuracion
  -> Proteccion contra alteraciones

ICONO NO APARECE
----------------
Arrastra desde la flecha "^" junto al reloj.

SCRIPT BLOQUEADO
----------------
Set-ExecutionPolicy Bypass -Scope Process
'@
    $t3 = New-Object System.Windows.Forms.TabPage
    $t3.Text = "Problemas"; $t3.BackColor = $script:Colors.Bg; $t3.Padding = New-Object System.Windows.Forms.Padding(15)
    $tb3 = New-Object System.Windows.Forms.TextBox
    $tb3.Multiline = $true; $tb3.ReadOnly = $true; $tb3.ScrollBars = "Vertical"
    $tb3.Dock = "Fill"; $tb3.BorderStyle = "None"
    $tb3.BackColor = $script:Colors.Bg; $tb3.ForeColor = $script:Colors.Text
    $tb3.Font = New-Object System.Drawing.Font("Consolas", 9); $tb3.Text = $txtProblemas
    $t3.Controls.Add($tb3); [void]$tabs.TabPages.Add($t3)

    $btnCerr = New-NeonButton "Cerrar (Esc)" $script:Colors.Neutral $script:Colors.TextMuted 605 560 140 30
    $dlg.Controls.Add($btnCerr); $btnCerr.BringToFront()
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($s,$e); if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close() } }.GetNewClosure())
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 41. ASISTENTE PRIMERA EJECUCION
# ==================================================================
function Show-FirstRunWizard {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Bienvenido"
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 540)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 75; $header.BackColor = $script:Colors.AccentCyan
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "BIENVENIDO"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(20, 12)
    $header.Controls.Add($lblH)
    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Control de Seguridad v4.2 - Con Reparacion Profunda"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(230, 250, 255)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true; $lblSub.Location = New-Object System.Drawing.Point(22, 45)
    $header.Controls.Add($lblSub)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = "Vertical"
    $txt.Location = New-Object System.Drawing.Point(20, 90); $txt.Size = New-Object System.Drawing.Size(520, 320)
    $txt.BorderStyle = "FixedSingle"
    $txt.BackColor = $script:Colors.BgSecondary; $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtWizard = @'
BIENVENIDO A LA VERSION 4.2
============================

NUEVO: Modulo de REPARACION PROFUNDA integrado
que ejecuta todos los comandos de reparacion
en una consola con log en tiempo real.

QUE HACE
--------
  * Activar / Desactivar Defender.
  * Reparar con reg delete, sc config, gpupdate,
    sfc /scannow, DISM RestoreHealth.
  * Verificar 18 modulos de Defender.
  * Perfiles, programador, backup, firmas.
  * Modo kiosco, portable, autostart.

DONDE ESTA
----------
Busca el ESCUDO junto al reloj. Si no lo ves, pulsa "^".

COMO REPARAR
------------
1. Clic derecho en el icono.
2. Selecciona "Reparacion Profunda".
3. Pulsa "REPARAR TODO AUTOMATICAMENTE".
4. Reinicia el equipo al terminar.

(c) 2026 - Ing. Yosvany Hernandez Quintero
'@
    $txt.Text = $txtWizard
    $dlg.Controls.Add($txt)
    $chkNo = New-Object System.Windows.Forms.CheckBox
    $chkNo.Text = "No volver a mostrar este mensaje"; $chkNo.Checked = $true
    $chkNo.Location = New-Object System.Drawing.Point(20, 425); $chkNo.Size = New-Object System.Drawing.Size(300, 25)
    $chkNo.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkNo)
    $btnAyuda = New-NeonButton "Ver ayuda" $script:Colors.AccentBlue $script:Colors.AccentBlueH 20 460 220 40
    $btnEnt = New-NeonButton "Entendido" $script:Colors.AccentGreen $script:Colors.AccentGreenH 340 460 200 40
    $dlg.Controls.Add($btnAyuda); $dlg.Controls.Add($btnEnt)
    $btnEnt.Add_Click({
        if ($chkNo.Checked) { $script:AppConfig['FirstRunDone'] = $true; Save-AppConfig }
        $dlg.Close()
    }.GetNewClosure())
    $btnAyuda.Add_Click({
        if ($chkNo.Checked) { $script:AppConfig['FirstRunDone'] = $true; Save-AppConfig }
        Show-HelpDialog
        $dlg.Close()
    }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 42. OPCIONES AVANZADAS ACTIVACION
# ==================================================================
function Show-AdvancedActivationDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Opciones de activacion"; $dlg.ClientSize = New-Object System.Drawing.Size(460, 420)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg; $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = $script:IconOk
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.AccentGreen
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "OPCIONES AVANZADAS"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 15)
    $header.Controls.Add($lblH)
    $chkCloud = New-Object System.Windows.Forms.CheckBox
    $chkCloud.Text = "Nube (MAPS Advanced)"; $chkCloud.Checked = $true
    $chkCloud.Location = New-Object System.Drawing.Point(20, 100); $chkCloud.Size = New-Object System.Drawing.Size(420, 25)
    $chkCloud.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkCloud)
    $chkSamp = New-Object System.Windows.Forms.CheckBox
    $chkSamp.Text = "Envio de muestras (Safe)"; $chkSamp.Checked = $true
    $chkSamp.Location = New-Object System.Drawing.Point(20, 145); $chkSamp.Size = New-Object System.Drawing.Size(420, 25)
    $chkSamp.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkSamp)
    $chkTamper = New-Object System.Windows.Forms.CheckBox
    $chkTamper.Text = "Tamper Protection"; $chkTamper.Checked = $true
    $chkTamper.Location = New-Object System.Drawing.Point(20, 190); $chkTamper.Size = New-Object System.Drawing.Size(420, 25)
    $chkTamper.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkTamper)
    $lblNota = New-Object System.Windows.Forms.Label
    $lblNota.Text = "Nota: si Defender esta en PARCIAL, usa Reparacion Profunda."
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblNota.ForeColor = $script:Colors.Warn; $lblNota.AutoSize = $true
    $lblNota.Location = New-Object System.Drawing.Point(20, 230); $dlg.Controls.Add($lblNota)
    $btnOk = New-NeonButton "Aceptar y Activar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 340 220 38
    $btnCancel = New-NeonButton "Cancelar" $script:Colors.Neutral $script:Colors.TextMuted 260 340 180 38
    $dlg.Controls.Add($btnOk); $dlg.Controls.Add($btnCancel)
    $script:DlgResult = [PSCustomObject]@{ Apply=$false; EnableCloud=$false; EnableSamples=$false; EnableTamper=$false }
    $btnOk.Add_Click({
        $script:DlgResult = [PSCustomObject]@{
            Apply=$true
            EnableCloud = $chkCloud.Checked
            EnableSamples = $chkSamp.Checked
            EnableTamper = $chkTamper.Checked
        }
        $dlg.Close()
    }.GetNewClosure())
    $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:DlgResult
}

# ==================================================================
# 43. LOG VIEWER
# ==================================================================
function Update-LogViewContent {
    param([System.Windows.Forms.TextBox]$TextBox)
    if ($null -eq $TextBox -or $TextBox.IsDisposed) { return }
    if (Test-Path $script:LogFile) {
        $c = Get-Content -Path $script:LogFile -Raw -ErrorAction SilentlyContinue
        $TextBox.Text = if ([string]::IsNullOrEmpty($c)) { "(Vacio)" } else { $c }
    } else { $TextBox.Text = "(Sin log todavia)" }
    $TextBox.SelectionStart = $TextBox.Text.Length; $TextBox.ScrollToCaret()
}
function Show-LogViewer {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text = "Log"; $frm.ClientSize = New-Object System.Drawing.Size(780, 540)
    $frm.StartPosition = "CenterScreen"; $frm.Icon = $script:IconOk
    $frm.BackColor = $script:Colors.Bg; $frm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $pHead = New-Object System.Windows.Forms.Panel
    $pHead.Dock = "Top"; $pHead.Height = 50; $pHead.BackColor = $script:Colors.AccentCyan
    $frm.Controls.Add($pHead)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "REGISTRO"
    $lbl.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::White; $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoSize = $true; $lbl.Location = New-Object System.Drawing.Point(15, 13)
    $pHead.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ScrollBars = "Both"; $txt.ReadOnly = $true
    $txt.WordWrap = $false; $txt.Dock = "Fill"
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor = $script:Colors.ConsoleBg
    $txt.ForeColor = $script:Colors.ConsoleText
    $pBody = New-Object System.Windows.Forms.Panel
    $pBody.Dock = "Fill"; $pBody.Padding = New-Object System.Windows.Forms.Padding(10)
    $pBody.Controls.Add($txt); $frm.Controls.Add($pBody); $pBody.BringToFront()
    $pBot = New-Object System.Windows.Forms.Panel
    $pBot.Dock = "Bottom"; $pBot.Height = 55; $pBot.BackColor = $script:Colors.Bg
    $frm.Controls.Add($pBot)
    $btnR = New-NeonButton "Refrescar" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 10 110 34
    $btnS = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 135 10 110 34
    $btnX = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 645 10 120 34
    $btnX.Anchor = "Top,Right"
    $pBot.Controls.Add($btnR); $pBot.Controls.Add($btnS); $pBot.Controls.Add($btnX)
    Update-LogViewContent -TextBox $txt
    $btnR.Add_Click({ Update-LogViewContent -TextBox $txt }.GetNewClosure())
    $btnS.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "Texto (*.txt)|*.txt"; $sd.FileName = "Log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date)
        if ($sd.ShowDialog() -eq "OK") {
            if (Test-Path $script:LogFile) { Copy-Item $script:LogFile $sd.FileName -Force }
            [System.Windows.Forms.MessageBox]::Show("Guardado.","OK","OK","Information") | Out-Null
        }
    }.GetNewClosure())
    $btnX.Add_Click({ $frm.Close() }.GetNewClosure())
    [void]$frm.ShowDialog()
}

# ==================================================================
# 44. ESTADO PANEL
# ==================================================================
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
$script:IsBusy             = $false
$script:ActionStartTime    = $null
$script:LastActionTime     = 0
$script:LastActionName     = ""
$script:LastKnownEstado    = "UNKNOWN"
$script:IsKioskMode        = $false

function Update-TrayIcon {
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

function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $s = Get-QuickStatus
    $diag = "Servicio:$($s.ServiceRunning) | RTP:$($s.RealTimeProtectionEnabled) | Politica:$($s.HasPolicy)"
    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = $script:S.Activo
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $false
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = $script:S.Parcial
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Falta proteccion real. Usa REPARAR."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = $script:S.Desactivado
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        $script:PanelLblDet1.Text = "El antivirus esta inactivo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $false
    }
    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDet3.Text = "Ultima: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDet3.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    }
    if ($s.Estado -ne $script:LastKnownEstado) {
        Update-TrayIcon -Estado $s.Estado
        if ($script:LastKnownEstado -ne "UNKNOWN") { Show-Toast "Windows Defender" "Estado: $($s.Estado)" "Info" }
        $script:LastKnownEstado = $s.Estado
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
        if ($null -ne $script:ActionStartTime) {
            $el = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:PanelLblTimer.Text = "{0:N2}s" -f $el
        } else { $script:PanelLblTimer.Text = "listo" }
        if (-not $script:IsBusy -and $null -eq $script:ActionStartTime) {
            try { Update-PanelStatusUI } catch { }
        }
    })
    $script:PanelTimer.Start()
}

# ==================================================================
# 45. PANEL PRINCIPAL
# ==================================================================
function Show-DefenderPanel {
    if ($script:IsKioskMode -and -not (Test-KioskPassword)) { return }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try {
            if ($script:PanelForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                $script:PanelForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            }
            $script:PanelForm.Show(); $script:PanelForm.BringToFront()
            $script:PanelForm.Activate(); $script:PanelForm.Focus()
        } catch { }
        return
    }
    Refresh-Palette
    $script:IsBusy = $false; $script:ActionStartTime = $null
    $script:LastActionTime = 0; $script:LastActionName = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Control de Seguridad v4.2"
    $form.ClientSize = New-Object System.Drawing.Size(460, 700)
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = $script:IconOk

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 70; $header.BackColor = $script:Colors.HeaderUnk
    $form.Controls.Add($header)
    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "DEFENDER CONTROL"
    $lblHeader.Font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White; $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true; $lblHeader.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblHeader)
    $lblSubH = New-Object System.Windows.Forms.Label
    $lblSubH.Text = "v4.2 - Deep Repair Edition"
    $lblSubH.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblSubH.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
    $lblSubH.BackColor = [System.Drawing.Color]::Transparent
    $lblSubH.AutoSize = $true; $lblSubH.Location = New-Object System.Drawing.Point(17, 44)
    $header.Controls.Add($lblSubH)
    $lblReloj = New-Object System.Windows.Forms.Label
    $lblReloj.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lblReloj.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
    $lblReloj.BackColor = [System.Drawing.Color]::Transparent
    $lblReloj.AutoSize = $false; $lblReloj.Size = New-Object System.Drawing.Size(160, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(285, 12); $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)
    $lblTimer = New-Object System.Windows.Forms.Label
    $lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimer.ForeColor = $script:Colors.AccentCyan; $lblTimer.BackColor = [System.Drawing.Color]::Transparent
    $lblTimer.AutoSize = $false; $lblTimer.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimer.Location = New-Object System.Drawing.Point(285, 32); $lblTimer.TextAlign = "MiddleRight"
    $lblTimer.Text = "listo"
    $header.Controls.Add($lblTimer)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 85)
    $card.Size = New-Object System.Drawing.Size(430, 140)
    $card.BackColor = $script:Colors.CardBg; $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)
    $lblTag = New-Object System.Windows.Forms.Label
    $lblTag.Text = "ESTADO ACTUAL"
    $lblTag.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
    $lblTag.ForeColor = $script:Colors.TextMuted; $lblTag.BackColor = [System.Drawing.Color]::Transparent
    $lblTag.AutoSize = $true; $lblTag.Location = New-Object System.Drawing.Point(12, 6)
    $card.Controls.Add($lblTag)
    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize = $true; $lblValor.Location = New-Object System.Drawing.Point(12, 26)
    $lblValor.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($lblValor)
    $lblDet1 = New-Object System.Windows.Forms.Label
    $lblDet1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDet1.ForeColor = $script:Colors.TextDiag; $lblDet1.BackColor = [System.Drawing.Color]::Transparent
    $lblDet1.AutoSize = $false; $lblDet1.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet1.Location = New-Object System.Drawing.Point(12, 68)
    $card.Controls.Add($lblDet1)
    $lblDet2 = New-Object System.Windows.Forms.Label
    $lblDet2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDet2.ForeColor = $script:Colors.TextMuted; $lblDet2.BackColor = [System.Drawing.Color]::Transparent
    $lblDet2.AutoSize = $false; $lblDet2.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet2.Location = New-Object System.Drawing.Point(12, 88)
    $card.Controls.Add($lblDet2)
    $lblDet3 = New-Object System.Windows.Forms.Label
    $lblDet3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDet3.ForeColor = $script:Colors.AccentCyan; $lblDet3.BackColor = [System.Drawing.Color]::Transparent
    $lblDet3.AutoSize = $false; $lblDet3.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet3.Location = New-Object System.Drawing.Point(12, 112)
    $card.Controls.Add($lblDet3)

    $btnVerificar  = New-NeonButton "VERIFICAR" $script:Colors.AccentPurple $script:Colors.AccentPurpH 15 240 430 32
    $btnActivar    = New-NeonButton "ACTIVAR PROTECCION" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 280 210 32
    $btnDesactivar = New-NeonButton "DESACTIVAR PROTECCION" $script:Colors.AccentRed $script:Colors.AccentRedH 235 280 210 32
    $btnReparar    = New-NeonButton "REPARAR (Deep Repair)" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15 320 430 36
    $btnHistorial  = New-NeonButton "Historial" $script:Colors.AccentBlue $script:Colors.AccentBlueH 15 365 102 32
    $btnPerfiles   = New-NeonButton "Perfiles" $script:Colors.AccentGreen $script:Colors.AccentGreenH 122 365 102 32
    $btnProg       = New-NeonButton "Programador" $script:Colors.AccentPurple $script:Colors.AccentPurpH 229 365 102 32
    $btnBackup     = New-NeonButton "Backup" $script:Colors.AccentCyan $script:Colors.AccentCyanH 336 365 109 32
    $btnFirmas     = New-NeonButton "Firmas" $script:Colors.AccentCyan $script:Colors.AccentCyanH 15 405 102 32
    $btnEventos    = New-NeonButton "Eventos" $script:Colors.AccentRed $script:Colors.AccentRedH 122 405 102 32
    $btnChart      = New-NeonButton "Estadisticas" $script:Colors.AccentAmber $script:Colors.AccentAmberH 229 405 102 32
    $btnDiag       = New-NeonButton "Diagnostico" $script:Colors.AccentAmber $script:Colors.AccentAmberH 336 405 109 32
    $btnAyuda      = New-NeonButton "Ayuda (F1)" $script:Colors.AccentBlue $script:Colors.AccentBlueH 15 445 102 32
    $btnConfig     = New-NeonButton "Config" $script:Colors.AccentBlue $script:Colors.AccentBlueH 122 445 102 32
    $btnLog        = New-NeonButton "Ver Log" $script:Colors.AccentCyan $script:Colors.AccentCyanH 229 445 102 32
    $btnAcerca     = New-NeonButton "Acerca" $script:Colors.Neutral $script:Colors.TextMuted 336 445 109 32
    $btnSalir      = New-NeonButton "SALIR" $script:Colors.AccentRed $script:Colors.AccentRedH 15 485 430 36

    foreach ($b in @($btnVerificar,$btnActivar,$btnDesactivar,$btnReparar,$btnHistorial,$btnPerfiles,
                     $btnProg,$btnBackup,$btnFirmas,$btnEventos,$btnChart,$btnDiag,$btnAyuda,
                     $btnConfig,$btnLog,$btnAcerca,$btnSalir)) {
        $form.Controls.Add($b)
    }

    Set-Help $btnVerificar "Verifica 18 modulos de Defender"
    Set-Help $btnActivar   "Activa Defender con opciones"
    Set-Help $btnDesactivar "Desactiva Defender"
    Set-Help $btnReparar   "REPARACION PROFUNDA: reg delete, servicios, gpupdate, sfc, DISM"
    Set-Help $btnHistorial "Historial de operaciones"
    Set-Help $btnPerfiles  "Perfiles"
    Set-Help $btnProg      "Programador"
    Set-Help $btnBackup    "Backup"
    Set-Help $btnFirmas    "Actualizar firmas"
    Set-Help $btnEventos   "Visor de eventos"
    Set-Help $btnChart     "Estadisticas"
    Set-Help $btnDiag      "Diagnostico"
    Set-Help $btnAyuda     "Ayuda (F1)"
    Set-Help $btnConfig    "Configuracion"
    Set-Help $btnLog       "Ver log"
    Set-Help $btnAcerca    "Acerca de"
    Set-Help $btnSalir     "Cerrar panel"

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

    $btnVerificar.Add_Click({ Show-CompleteStatusDialog })
    $btnReparar.Add_Click({ Show-DeepRepairDialog })
    $btnHistorial.Add_Click({ Show-HistoryDialog })
    $btnPerfiles.Add_Click({ Show-ProfilesDialog })
    $btnProg.Add_Click({ Show-SchedulerDialog })
    $btnBackup.Add_Click({ Show-BackupDialog })
    $btnFirmas.Add_Click({ Show-SignaturesDialog })
    $btnEventos.Add_Click({ Show-EventsDialog })
    $btnChart.Add_Click({ Show-ChartDialog })
    $btnDiag.Add_Click({ Show-DiagnosticsDialog })
    $btnAyuda.Add_Click({ Show-HelpDialog })
    $btnConfig.Add_Click({ Show-SettingsDialog })
    $btnLog.Add_Click({ Show-LogViewer })

    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $opts = Show-AdvancedActivationDialog
        if (-not $opts.Apply) { return }
        try {
            $script:IsBusy = $true; $script:ActionStartTime = Get-Date; $script:LastActionName = "Activar"
            $lblDet1.Text = "Activando..."
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender -EnableCloud $opts.EnableCloud -EnableSamples $opts.EnableSamples -EnableTamper $opts.EnableTamper
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null; $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Activar" -Resultado $s.Estado -Segundos $elapsed
            if (-not $script:SilentMode) {
                $extra = ""
                if ($s.Estado -eq "PARCIAL") { $extra = "`n`nSigue en PARCIAL. Usa REPARAR (Deep Repair)." }
                [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s$extra`n`n$log" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
            }
        } finally {
            $script:IsBusy = $false; $script:ActionStartTime = $null
        }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        if (-not $script:SilentMode) {
            $c = [System.Windows.Forms.MessageBox]::Show("Desactivar Windows Defender?","Confirmar","YesNo","Warning")
            if ($c -ne "Yes") { return }
        }
        try {
            $script:IsBusy = $true; $script:ActionStartTime = Get-Date; $script:LastActionName = "Desactivar"
            $lblDet1.Text = "Desactivando..."
            [System.Windows.Forms.Application]::DoEvents()
            $log = Disable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:ActionStartTime = $null; $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            Add-History -Accion "Desactivar" -Resultado $s.Estado -Segundos $elapsed
            if (-not $script:SilentMode) {
                [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s`n`n$log" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
            }
        } finally {
            $script:IsBusy = $false; $script:ActionStartTime = $null
        }
    })

    $btnAcerca.Add_Click({
        $osInfo = Get-OSInfo
        $txt = @"
DEFENDER CONTROL - v4.2
============================================

Autor:  Ing. Yosvany Hernandez Quintero
Movil:  +53 5 2160801
Movil:  +53 5 9860911

--------------------------------------------
Sistema: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)
PowerShell: $($PSVersionTable.PSVersion)
SHA256: $($script:ScriptHash)
--------------------------------------------

DATOS: $($script:ConfigDir)
LOGS:  $($script:LogFolder)
BACKUPS: $($script:BackupDir)
--------------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($txt,"Acerca de","OK","Information") | Out-Null
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

# ==================================================================
# 46. ARRANQUE
# ==================================================================
Write-AppLog "====================================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v4.2" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "====================================================" "INFO"

Test-ScriptIntegrity | Out-Null
Load-History

if (Test-Admin) { Write-AppLog "Admin: SI" "INFO" } else { Write-AppLog "Admin: NO" "WARN" }
if (Test-Admin) { Add-DefenderExclusion | Out-Null }

if ($args -contains "-action") {
    $idx = [array]::IndexOf($args, "-action")
    if ($idx -ge 0 -and $idx + 1 -lt $args.Count) {
        $actionArg = $args[$idx + 1]
        if ($actionArg -eq "disable") { $null = Disable-Defender; exit 0 }
        elseif ($actionArg -eq "enable") { $null = Enable-Defender; exit 0 }
    }
}

$initQuick = Get-QuickStatus
$script:LastKnownEstado = $initQuick.Estado
if ($initQuick.Estado -eq "ACTIVO") { $estadoInicial = "ACTIVADO" }
elseif ($initQuick.Estado -eq "PARCIAL") { $estadoInicial = "PROTECCION PARCIAL" }
else { $estadoInicial = "DESACTIVADO" }

if (-not $script:SilentMode -and -not $script:AppConfig['FirstRunDone']) {
    Show-FirstRunWizard
}

# ==================================================================
# 47. BANDEJA + MENU
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = $script:IconPartial
$script:notifyIcon.Text = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true
Update-TrayIcon -Estado $initQuick.Estado

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor = $script:Colors.BgSecondary
$menu.ForeColor = $script:Colors.Text

function Add-MenuItem {
    param([string]$Texto, [scriptblock]$Accion)
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $Texto
    $mi.ForeColor = $script:Colors.Text
    $mi.Add_Click($Accion)
    return $mi
}

[void]$menu.Items.Add((Add-MenuItem "Abrir panel" { Show-DefenderPanel }))
[void]$menu.Items.Add((Add-MenuItem "Verificar estado" { Show-CompleteStatusDialog }))
[void]$menu.Items.Add((Add-MenuItem "REPARACION PROFUNDA" { Show-DeepRepairDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((Add-MenuItem "Historial" { Show-HistoryDialog }))
[void]$menu.Items.Add((Add-MenuItem "Perfiles" { Show-ProfilesDialog }))
[void]$menu.Items.Add((Add-MenuItem "Programador" { Show-SchedulerDialog }))
[void]$menu.Items.Add((Add-MenuItem "Backup/Restore" { Show-BackupDialog }))
[void]$menu.Items.Add((Add-MenuItem "Actualizar firmas" { Show-SignaturesDialog }))
[void]$menu.Items.Add((Add-MenuItem "Eventos" { Show-EventsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Estadisticas" { Show-ChartDialog }))
[void]$menu.Items.Add((Add-MenuItem "Diagnostico" { Show-DiagnosticsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Ayuda (F1)" { Show-HelpDialog }))
[void]$menu.Items.Add((Add-MenuItem "Configuracion" { Show-SettingsDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miAct = Add-MenuItem "Activar Defender" {
    if (-not (Test-Admin)) { return }
    $opts = Show-AdvancedActivationDialog
    if (-not $opts.Apply) { return }
    $null = Enable-Defender -EnableCloud $opts.EnableCloud -EnableSamples $opts.EnableSamples -EnableTamper $opts.EnableTamper
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

$miLog2 = Add-MenuItem "Ver Log" { Show-LogViewer }
[void]$menu.Items.Add($miLog2)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

[void]$menu.Items.Add((Add-MenuItem "Salir" {
    Write-AppLog "Cierre." "INFO"
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

if (-not $script:SilentMode) {
    $script:notifyIcon.ShowBalloonTip(3000, "Control de Seguridad v4.2", "Estado: $estadoInicial", "Info")
}

# ==================================================================
# 48. LOOP PRINCIPAL
# ==================================================================
[System.Windows.Forms.Application]::Run()