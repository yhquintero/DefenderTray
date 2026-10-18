<#
.SYNOPSIS
    Control de Seguridad de Windows Defender - v4.2 Final
.DESCRIPTION
    Version corregida: sin hashtable en scope, sin AccentTeal,
    sin funciones anidadas, config como variables individuales.
.NOTES
    Ejecutar como Administrador.
    Autor: Ing. Yosvany Hernandez Quintero
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue

# ==================================================================
# 2. ARGUMENTOS
# ==================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")
$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir  = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

# ==================================================================
# 3. TILDE
# ==================================================================
$script:O_ACCENT = [char]0x00D3

# ==================================================================
# 4. RUTAS
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
# 5. CONFIG COMO VARIABLES INDIVIDUALES (SIN HASHTABLE)
# ==================================================================
$script:CfgDarkTheme    = $true
$script:CfgKioskMode    = $false
$script:CfgKioskHash    = ""
$script:CfgFirstRunDone = $false
$script:CfgAutoStart    = $false
$script:CfgLastProfile  = "Personalizado"

$script:DarkTheme   = $true
$script:IsKioskMode = $false

function Load-AppConfig {
    try {
        if (Test-Path $script:ConfigFile) {
            $json = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $json.DarkTheme)    { $script:CfgDarkTheme    = [bool]$json.DarkTheme }
            if ($null -ne $json.KioskMode)    { $script:CfgKioskMode    = [bool]$json.KioskMode }
            if ($null -ne $json.KioskHash)    { $script:CfgKioskHash    = [string]$json.KioskHash }
            if ($null -ne $json.FirstRunDone) { $script:CfgFirstRunDone = [bool]$json.FirstRunDone }
            if ($null -ne $json.AutoStart)    { $script:CfgAutoStart    = [bool]$json.AutoStart }
            if ($null -ne $json.LastProfile)  { $script:CfgLastProfile  = [string]$json.LastProfile }
        }
    } catch { }
    $script:DarkTheme   = $script:CfgDarkTheme
    $script:IsKioskMode = $script:CfgKioskMode
}
function Save-AppConfig {
    try {
        $script:CfgDarkTheme = $script:DarkTheme
        $script:CfgKioskMode = $script:IsKioskMode
        $obj = [PSCustomObject]@{
            DarkTheme    = $script:CfgDarkTheme
            KioskMode    = $script:CfgKioskMode
            KioskHash    = $script:CfgKioskHash
            FirstRunDone = $script:CfgFirstRunDone
            AutoStart    = $script:CfgAutoStart
            LastProfile  = $script:CfgLastProfile
        }
        $obj | ConvertTo-Json -Depth 3 | Set-Content -Path $script:ConfigFile -Encoding UTF8 -Force
    } catch { }
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
# 7. HISTORIAL
# ==================================================================
$script:EventHistory = New-Object System.Collections.ArrayList
function Add-History {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    try {
        $entry = [PSCustomObject]@{ Hora=(Get-Date); Accion=$Accion; Resultado=$Resultado; Segundos=$Segundos }
        [void]$script:EventHistory.Insert(0, $entry)
        while ($script:EventHistory.Count -gt 20) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
        if (-not (Test-Path $script:CsvFile)) {
            Add-Content -Path $script:CsvFile -Value '"Fecha","Accion","Resultado","Segundos"' -Encoding UTF8
        }
        Add-Content -Path $script:CsvFile -Value ('"{0:yyyy-MM-dd HH:mm:ss}","{1}","{2}","{3:N2}"' -f $entry.Hora, $Accion, $Resultado, $Segundos) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# 8. ESPERA
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
# 9. PALETAS
# ==================================================================
function Get-FuturisticPalette {
    return @{
        Bg=[System.Drawing.Color]::FromArgb(10,14,26); BgSecondary=[System.Drawing.Color]::FromArgb(20,27,46)
        CardBg=[System.Drawing.Color]::FromArgb(24,32,52)
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
    }
}
function Get-LightPalette {
    return @{
        Bg=[System.Drawing.Color]::FromArgb(240,245,250); BgSecondary=[System.Drawing.Color]::FromArgb(255,255,255)
        CardBg=[System.Drawing.Color]::White
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
    }
}
Load-AppConfig
$script:Colors = if ($script:DarkTheme) { Get-FuturisticPalette } else { Get-LightPalette }
function Refresh-Palette { $script:Colors = if ($script:DarkTheme) { Get-FuturisticPalette } else { Get-LightPalette } }

# ==================================================================
# 10. ESTADO RAPIDO
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
# 11. INFORME
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
            [void]$report.Add([PSCustomObject]@{ Modulo="Edad firma"; Valor=(Get-SafeProp $st "AntivirusSignatureAge"); Color=$null })
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
# 12. DIAGNOSTICO (fix cast ExecutionPolicy)
# ==================================================================
function Get-DiagnosticReport {
    $r = New-Object System.Collections.ArrayList
    $pv = $PSVersionTable.PSVersion
    if ($pv.Major -ge 5) { [void]$r.Add([PSCustomObject]@{Item="PowerShell"; Status="OK"; Detail="$($pv.Major).$($pv.Minor)"; Color=$script:Colors.Ok}) }
    else { [void]$r.Add([PSCustomObject]@{Item="PowerShell"; Status="FALLA"; Detail="Se requiere 5.1+"; Color=$script:Colors.Bad}) }
    try { $nv = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop).Version; [void]$r.Add([PSCustomObject]@{Item=".NET Framework"; Status="OK"; Detail="$nv"; Color=$script:Colors.Ok}) }
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
    try {
        $epText = (Get-ExecutionPolicy).ToString()
        [void]$r.Add([PSCustomObject]@{Item="ExecutionPolicy"; Status="INFO"; Detail=$epText; Color=$script:Colors.TextDiag})
    } catch { }
    return $r
}

# ==================================================================
# 13. ADMIN / OS / EXCLUSION / AUTOSTART
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

# ==================================================================
# 14. HASH
# ==================================================================
function Get-StringHash {
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ([BitConverter]::ToString($b) -replace '-','').Substring(0,16)
}

# ==================================================================
# 15. CONTROLES (BOTON)
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
# 16. EJECUTOR DE COMANDOS EN CONSOLA
# ==================================================================
function Invoke-ConsoleCommand {
    param(
        [System.Windows.Forms.TextBox]$Console,
        [string]$Comando
    )
    if ($null -eq $Console -or $Console.IsDisposed) { return 0 }
    try {
        $Console.AppendText("`r`n> $Comando`r`n")
        $Console.SelectionStart = $Console.Text.Length
        $Console.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = "cmd.exe"
        $proc.StartInfo.Arguments = "/c $Comando"
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.CreateNoWindow = $true
        $proc.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(850)
        $proc.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(850)

        $proc.Start() | Out-Null

        while (-not $proc.HasExited) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -ne $line) {
                $Console.AppendText("$line`r`n")
                $Console.SelectionStart = $Console.Text.Length
                $Console.ScrollToCaret()
                [System.Windows.Forms.Application]::DoEvents()
            }
            Start-Sleep -Milliseconds 20
        }
        $out = $proc.StandardOutput.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($out)) { $Console.AppendText($out) }
        $err = $proc.StandardError.ReadToEnd()
        if (-not [string]::IsNullOrEmpty($err)) {
            $Console.AppendText("$err")
        }
        $exitCode = $proc.ExitCode
        $proc.Dispose()
        $Console.AppendText("[ExitCode: $exitCode]`r`n")
        $Console.SelectionStart = $Console.Text.Length
        $Console.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        return $exitCode
    } catch {
        $Console.AppendText("ERROR: $($_.Exception.Message)`r`n")
        return -1
    }
}

# ==================================================================
# 17. DIALOGO REPARACION PROFUNDA (SCOPE SCRIPT - SIN FUNCIONES ANIDADAS)
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

    # Guardar referencia global para handlers
    $script:RepairConsole = $console

    $pBotones = New-Object System.Windows.Forms.Panel
    $pBotones.Location = New-Object System.Drawing.Point(0, 565)
    $pBotones.Size = New-Object System.Drawing.Size(900, 110)
    $pBotones.Anchor = "Bottom,Left,Right"
    $pBotones.BackColor = $script:Colors.Bg
    $dlg.Controls.Add($pBotones)

    # Botones fila 1
    $btnReg = New-NeonButton "1. Borrar Politicas" $script:Colors.AccentRed $script:Colors.AccentRedH 15 10 160 34
    $btnSvc = New-NeonButton "2. Reiniciar Servicios" $script:Colors.AccentAmber $script:Colors.AccentAmberH 185 10 180 34
    $btnGpu = New-NeonButton "3. gpupdate /force" $script:Colors.AccentPurple $script:Colors.AccentPurpH 375 10 160 34
    $btnSFC = New-NeonButton "4. sfc /scannow" $script:Colors.AccentBlue $script:Colors.AccentBlueH 545 10 150 34
    $btnDISM = New-NeonButton "5. DISM Restore" $script:Colors.AccentCyan $script:Colors.AccentCyanH 705 10 170 34
    $pBotones.Controls.Add($btnReg)
    $pBotones.Controls.Add($btnSvc)
    $pBotones.Controls.Add($btnGpu)
    $pBotones.Controls.Add($btnSFC)
    $pBotones.Controls.Add($btnDISM)

    # Botones fila 2
    $btnTodo = New-NeonButton "REPARAR TODO AUTOMATICAMENTE" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 55 350 40
    $btnVerif = New-NeonButton "Verificar Estado" $script:Colors.AccentCyan $script:Colors.AccentCyanH 375 55 180 40
    $btnLimp = New-NeonButton "Limpiar" $script:Colors.Neutral $script:Colors.TextMuted 565 55 140 40
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.AccentRed $script:Colors.AccentRedH 715 55 160 40
    $pBotones.Controls.Add($btnTodo)
    $pBotones.Controls.Add($btnVerif)
    $pBotones.Controls.Add($btnLimp)
    $pBotones.Controls.Add($btnCerr)

    # Handlers (usan $script:RepairConsole)

    $btnReg.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n### PASO 1: BORRAR POLITICAS DE GRUPO ###`r`n")
        foreach ($r in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                         "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                         "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                         "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
            Invoke-ConsoleCommand -Console $c -Comando "reg delete `"$r`" /f"
        }
        $c.AppendText("[OK] Politicas eliminadas.`r`n")
        Add-History -Accion "Reparar: Politicas" -Resultado "OK" -Segundos 0
    })

    $btnSvc.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n### PASO 2: REINICIAR SERVICIOS ###`r`n")
        foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService")) {
            Invoke-ConsoleCommand -Console $c -Comando "sc config $s start= auto"
            Invoke-ConsoleCommand -Console $c -Comando "sc start $s"
        }
        $c.AppendText("[OK] Servicios reiniciados.`r`n")
        Add-History -Accion "Reparar: Servicios" -Resultado "OK" -Segundos 0
    })

    $btnGpu.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n### PASO 3: GPUPDATE /FORCE ###`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "gpupdate /force"
        $c.AppendText("[OK] Politicas actualizadas.`r`n")
        Add-History -Accion "Reparar: gpupdate" -Resultado "OK" -Segundos 0
    })

    $btnSFC.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n### PASO 4: SFC /SCANNOW (puede tardar) ###`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "sfc /scannow"
        $c.AppendText("[OK] SFC completado.`r`n")
        Add-History -Accion "Reparar: SFC" -Resultado "OK" -Segundos 0
    })

    $btnDISM.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n### PASO 5: DISM RESTORE HEALTH ###`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("[OK] DISM completado.`r`n")
        Add-History -Accion "Reparar: DISM" -Resultado "OK" -Segundos 0
    })

    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $swTotal = [System.Diagnostics.Stopwatch]::StartNew()

        $c.AppendText("`r`n====================================================`r`n")
        $c.AppendText("      REPARACION AUTOMATICA COMPLETA`r`n")
        $c.AppendText("====================================================`r`n")
        $c.AppendText("Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")

        # Paso 1
        $c.AppendText("`r`n[PASO 1] Eliminando politicas de grupo...`r`n")
        foreach ($r in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                         "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                         "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                         "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
            Invoke-ConsoleCommand -Console $c -Comando "reg delete `"$r`" /f"
        }

        # Paso 2
        $c.AppendText("`r`n[PASO 2] Reiniciando servicios...`r`n")
        foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
            Invoke-ConsoleCommand -Console $c -Comando "sc config $s start= auto"
            Invoke-ConsoleCommand -Console $c -Comando "sc start $s"
        }

        # Paso 3
        $c.AppendText("`r`n[PASO 3] gpupdate /force...`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "gpupdate /force"

        # Paso 4: Set-MpPreference
        $c.AppendText("`r`n[PASO 4] Reactivando protecciones via PowerShell...`r`n")
        try {
            if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
                Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -DisableBehaviorMonitoring $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -DisableIOAVProtection $false -Force -ErrorAction SilentlyContinue
                Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue
                $c.AppendText("  [OK] Preferencias aplicadas.`r`n")
            }
        } catch { $c.AppendText("  [ERR] $($_.Exception.Message)`r`n") }

        # Paso 5
        $c.AppendText("`r`n[PASO 5] sfc /scannow...`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "sfc /scannow"

        # Paso 6
        $c.AppendText("`r`n[PASO 6] DISM RestoreHealth...`r`n")
        Invoke-ConsoleCommand -Console $c -Comando "DISM /Online /Cleanup-Image /RestoreHealth"

        # Verificacion
        $c.AppendText("`r`n[VERIFICACION FINAL]`r`n")
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            $c.AppendText("  WinDefend: $($svc.Status)`r`n")
        }
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $c.AppendText("  AntivirusEnabled: $($st.AntivirusEnabled)`r`n")
            $c.AppendText("  RealTimeProtection: $($st.RealTimeProtectionEnabled)`r`n")
        } catch { }

        $swTotal.Stop()
        $c.AppendText("`r`n====================================================`r`n")
        $c.AppendText("  REPARACION COMPLETADA EN $([math]::Round($swTotal.Elapsed.TotalSeconds,1))s`r`n")
        $c.AppendText("  Reinicia el equipo para aplicar todos los cambios.`r`n")
        $c.AppendText("====================================================`r`n")

        Add-History -Accion "Reparacion Completa" -Resultado "OK" -Segundos $swTotal.Elapsed.TotalSeconds

        [System.Windows.Forms.MessageBox]::Show(
            "Reparacion completada.`n`nReinicia el equipo para aplicar todos los cambios.",
            "Reparacion Finalizada", "OK", "Information") | Out-Null
    })

    $btnVerif.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n--- VERIFICACION DE ESTADO ---`r`n")
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($null -ne $svc) { $c.AppendText("  WinDefend: $($svc.Status)`r`n") }
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $c.AppendText("  AntivirusEnabled: $($st.AntivirusEnabled)`r`n")
            $c.AppendText("  RealTimeProtection: $($st.RealTimeProtectionEnabled)`r`n")
            $c.AppendText("  BehaviorMonitor: $($st.BehaviorMonitorEnabled)`r`n")
            $c.AppendText("  Tamper: $($st.IsTamperProtected)`r`n")
        } catch { $c.AppendText("  Error: $($_.Exception.Message)`r`n") }
    })

    $btnLimp.Add_Click({ $script:RepairConsole.Text = "" })
    $btnCerr.Add_Click({ $dlg.Close() })

    # Encabezado inicial
    $console.AppendText("====================================================`r`n")
    $console.AppendText("  CONSOLA DE REPARACION - DefenderTray v4.2`r`n")
    $console.AppendText("====================================================`r`n")
    $console.AppendText("`r`nPuedes ejecutar cada paso individualmente o pulsar`r`n")
    $console.AppendText("'REPARAR TODO AUTOMATICAMENTE' para ejecutar todo.`r`n`r`n")
    $console.AppendText("Los comandos se ejecutan en tiempo real en esta consola.`r`n")

    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ==================================================================
# 18. VERIFICACION COMPLETA
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
        $StatusLabel.Text = ">>> ACTIVADO <<<"
        $StatusLabel.ForeColor = $script:Colors.Ok
    } elseif ($q.Estado -eq "PARCIAL") {
        $StatusLabel.Text = ">>> PROTECCION PARCIAL <<<"
        $StatusLabel.ForeColor = $script:Colors.Warn
    } else {
        $StatusLabel.Text = ">>> DESACTIVADO <<<"
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
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 525 545 140 32
    $dlg.Controls.Add($btnRef); $dlg.Controls.Add($btnRep); $dlg.Controls.Add($btnCerr)
    Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado
    $btnRef.Add_Click({ Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado }.GetNewClosure())
    $btnRep.Add_Click({ Show-DeepRepairDialog })
    $btnCerr.Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 19. HISTORIAL
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
# 20. DIAGNOSTICO DIALOGO
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
        [void]$it.SubItems.Add([string]$d.Status)
        [void]$it.SubItems.Add([string]$d.Detail)
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
# 21. CONFIGURACION
# ==================================================================
function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Configuracion"; $dlg.ClientSize = New-Object System.Drawing.Size(560, 480)
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
    $chkKiosk = New-Object System.Windows.Forms.CheckBox
    $chkKiosk.Text = "Modo kiosco"; $chkKiosk.Checked = $script:IsKioskMode
    $chkKiosk.Location = New-Object System.Drawing.Point(20, 115); $chkKiosk.Size = New-Object System.Drawing.Size(500, 25)
    $chkKiosk.ForeColor = $script:Colors.Text; $dlg.Controls.Add($chkKiosk)
    $lblPwd = New-Object System.Windows.Forms.Label
    $lblPwd.Text = "Contrasena:"; $lblPwd.ForeColor = $script:Colors.Text
    $lblPwd.Location = New-Object System.Drawing.Point(40, 150); $lblPwd.Size = New-Object System.Drawing.Size(120, 25)
    $dlg.Controls.Add($lblPwd)
    $txtPwd = New-Object System.Windows.Forms.TextBox
    $txtPwd.PasswordChar = '*'; $txtPwd.Location = New-Object System.Drawing.Point(160, 148)
    $txtPwd.Size = New-Object System.Drawing.Size(340, 25)
    $txtPwd.BackColor = $script:Colors.BgSecondary; $txtPwd.ForeColor = $script:Colors.Text
    $txtPwd.Enabled = $script:IsKioskMode
    $dlg.Controls.Add($txtPwd)
    $btnRestore = New-NeonButton "Restaurar" $script:Colors.AccentRed $script:Colors.AccentRedH 20 260 200 34
    $btnSave = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 240 260 200 34
    $btnHelp = New-NeonButton "Ayuda" $script:Colors.AccentBlue $script:Colors.AccentBlueH 20 310 200 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 240 310 200 34
    $dlg.Controls.Add($btnRestore); $dlg.Controls.Add($btnSave)
    $dlg.Controls.Add($btnHelp); $dlg.Controls.Add($btnCerr)
    $chkKiosk.Add_CheckedChanged({ $txtPwd.Enabled = $chkKiosk.Checked })
    $btnSave.Add_Click({
        $script:DarkTheme = $chkDark.Checked
        $script:IsKioskMode = $chkKiosk.Checked
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:CfgKioskHash = Get-StringHash $txtPwd.Text
        }
        Save-AppConfig
        Refresh-Palette
        [System.Windows.Forms.MessageBox]::Show("Configuracion guardada.","OK","OK","Information") | Out-Null
    })
    $btnRestore.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show("Restaurar valores?","Confirmar","YesNo","Warning") -eq "Yes") {
            $script:DarkTheme = $true; $script:IsKioskMode = $false
            $script:CfgKioskHash = ""
            Save-AppConfig
            Refresh-Palette
            [System.Windows.Forms.MessageBox]::Show("Valores restaurados.","OK","OK","Information") | Out-Null
        }
    })
    $btnHelp.Add_Click({ Show-HelpDialog })
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 22. AYUDA
# ==================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"; $dlg.ClientSize = New-Object System.Drawing.Size(760, 600)
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
CONTROL DE SEGURIDAD - v4.2 FINAL
====================================

Nueva version con REPARACION PROFUNDA integrada.

REPARACION PROFUNDA
-------------------
Accesible desde:
  - Boton "REPARAR (Deep Repair)" en el panel.
  - Menu contextual -> "REPARACION PROFUNDA".

Pasos disponibles:
  1. Borrar Politicas (reg delete).
  2. Reiniciar Servicios (sc config + sc start).
  3. gpupdate /force.
  4. sfc /scannow.
  5. DISM /Online /Cleanup-Image /RestoreHealth.

El boton REPARAR TODO ejecuta los 5 pasos con log en vivo.

FIX v4.2 FINAL
--------------
- Config con variables individuales (no hashtable).
- Panel controls en scope $script:.
- Sin funciones anidadas.
- Sin claves de paleta inexistentes.

AUTOR
-----
Ing. Yosvany Hernandez Quintero
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

    $txtProb = @'
SOLUCION DE PROBLEMAS
=====================

ESTADO "PROTECCION PARCIAL"
---------------------------
Windows reporta Defender activo pero la proteccion real
esta bloqueada. Causa: politicas de grupo residuales.

Solucion:
  1. Clic derecho en el icono.
  2. "REPARACION PROFUNDA".
  3. "REPARAR TODO AUTOMATICAMENTE".
  4. REINICIA el equipo.

TAMPER PROTECTION ACTIVA
------------------------
Desactivala manualmente en:
  Seguridad de Windows -> Proteccion antivirus y contra
  amenazas -> Administrar la configuracion -> Proteccion
  contra alteraciones.
'@
    $t2 = New-Object System.Windows.Forms.TabPage
    $t2.Text = "Problemas"; $t2.BackColor = $script:Colors.Bg; $t2.Padding = New-Object System.Windows.Forms.Padding(15)
    $tb2 = New-Object System.Windows.Forms.TextBox
    $tb2.Multiline = $true; $tb2.ReadOnly = $true; $tb2.ScrollBars = "Vertical"
    $tb2.Dock = "Fill"; $tb2.BorderStyle = "None"
    $tb2.BackColor = $script:Colors.Bg; $tb2.ForeColor = $script:Colors.Text
    $tb2.Font = New-Object System.Drawing.Font("Consolas", 9); $tb2.Text = $txtProb
    $t2.Controls.Add($tb2); [void]$tabs.TabPages.Add($t2)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 605 560 140 30
    $dlg.Controls.Add($btnCerr); $btnCerr.BringToFront()
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($s,$e); if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close() } })
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 23. OPCIONES DE ACTIVACION
# ==================================================================
function Show-AdvancedActivationDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Opciones de activacion"; $dlg.ClientSize = New-Object System.Drawing.Size(460, 400)
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
    $lblNota.Text = "Si Defender queda PARCIAL, usa Reparacion Profunda."
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblNota.ForeColor = $script:Colors.Warn; $lblNota.AutoSize = $true
    $lblNota.Location = New-Object System.Drawing.Point(20, 230); $dlg.Controls.Add($lblNota)
    $btnOk = New-NeonButton "Aceptar y Activar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 320 220 38
    $btnCancel = New-NeonButton "Cancelar" $script:Colors.Neutral $script:Colors.TextMuted 260 320 180 38
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
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:DlgResult
}

# ==================================================================
# 24. ACTIVAR / DESACTIVAR
# ==================================================================
function Enable-Defender {
    param([bool]$EnableCloud = $false, [bool]$EnableSamples = $false, [bool]$EnableTamper = $false)
    $log = New-Object System.Collections.ArrayList
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
    if ($EnableCloud -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try { Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction Stop; [void]$log.Add("[7] MAPS ACTIVADO") } catch { }
    }
    if ($EnableSamples -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try { Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction Stop; [void]$log.Add("[8] Muestras ACTIVADO") } catch { }
    }
    if ($EnableTamper) {
        $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        try {
            if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
            Set-ItemProperty -Path $tpPath -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    return ($log -join "`n")
}

function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                return ($log -join "`n")
            }
        }
    } catch {}
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            foreach ($pref in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                               "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning")) {
                try { Set-MpPreference @{ $pref = $true } -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    } catch { }
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }
    $dp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $dp)) { New-Item -Path $dp -Force | Out-Null }
    Set-ItemProperty -Path $dp -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dp -Name "DisableAntiVirus" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    foreach ($s in @("WinDefend","WdNisSvc","Sense")) {
        try { $null = & sc.exe stop $s 2>&1; $null = & sc.exe config $s start= disabled 2>&1 } catch { }
    }
    return ($log -join "`n")
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
# 26. ESTADO PANEL (SCOPE SCRIPT)
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
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $false
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Usa REPARAR (Deep Repair) para solucionar."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
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
# 27. PANEL PRINCIPAL
# ==================================================================
function Show-DefenderPanel {
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try {
            $script:PanelForm.Show(); $script:PanelForm.BringToFront()
            $script:PanelForm.Activate()
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
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true
    $lblHeader.Location = New-Object System.Drawing.Point(15, 12)
    $header.Controls.Add($lblHeader)
    $lblSubH = New-Object System.Windows.Forms.Label
    $lblSubH.Text = "v4.2 - Deep Repair"
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
    $lblReloj.AutoSize = $false
    $lblReloj.Size = New-Object System.Drawing.Size(160, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(285, 12)
    $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)
    $lblTimer = New-Object System.Windows.Forms.Label
    $lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimer.ForeColor = $script:Colors.AccentCyan
    $lblTimer.BackColor = [System.Drawing.Color]::Transparent
    $lblTimer.AutoSize = $false
    $lblTimer.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimer.Location = New-Object System.Drawing.Point(285, 32)
    $lblTimer.TextAlign = "MiddleRight"
    $lblTimer.Text = "listo"
    $header.Controls.Add($lblTimer)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 85)
    $card.Size = New-Object System.Drawing.Size(430, 140)
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
    $lblDet1.AutoSize = $false
    $lblDet1.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet1.Location = New-Object System.Drawing.Point(12, 68)
    $card.Controls.Add($lblDet1)
    $lblDet2 = New-Object System.Windows.Forms.Label
    $lblDet2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDet2.ForeColor = $script:Colors.TextMuted
    $lblDet2.BackColor = [System.Drawing.Color]::Transparent
    $lblDet2.AutoSize = $false
    $lblDet2.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet2.Location = New-Object System.Drawing.Point(12, 88)
    $card.Controls.Add($lblDet2)
    $lblDet3 = New-Object System.Windows.Forms.Label
    $lblDet3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDet3.ForeColor = $script:Colors.AccentCyan
    $lblDet3.BackColor = [System.Drawing.Color]::Transparent
    $lblDet3.AutoSize = $false
    $lblDet3.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet3.Location = New-Object System.Drawing.Point(12, 112)
    $card.Controls.Add($lblDet3)

    $btnVerificar  = New-NeonButton "VERIFICAR" $script:Colors.AccentPurple $script:Colors.AccentPurpH 15 240 430 32
    $btnActivar    = New-NeonButton "ACTIVAR PROTECCION" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 280 210 32
    $btnDesactivar = New-NeonButton "DESACTIVAR PROTECCION" $script:Colors.AccentRed $script:Colors.AccentRedH 235 280 210 32
    $btnReparar    = New-NeonButton "REPARAR (Deep Repair)" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15 320 430 36
    $btnHistorial  = New-NeonButton "Historial" $script:Colors.AccentBlue $script:Colors.AccentBlueH 15 365 102 32
    $btnDiag       = New-NeonButton "Diagnostico" $script:Colors.AccentAmber $script:Colors.AccentAmberH 122 365 102 32
    $btnConfig     = New-NeonButton "Config" $script:Colors.AccentBlue $script:Colors.AccentBlueH 229 365 102 32
    $btnAyuda      = New-NeonButton "Ayuda (F1)" $script:Colors.AccentBlue $script:Colors.AccentBlueH 336 365 109 32
    $btnSalir      = New-NeonButton "SALIR" $script:Colors.AccentRed $script:Colors.AccentRedH 15 410 430 36

    foreach ($b in @($btnVerificar,$btnActivar,$btnDesactivar,$btnReparar,$btnHistorial,$btnDiag,$btnConfig,$btnAyuda,$btnSalir)) {
        $form.Controls.Add($b)
    }

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
    $btnDiag.Add_Click({ Show-DiagnosticsDialog })
    $btnAyuda.Add_Click({ Show-HelpDialog })
    $btnConfig.Add_Click({ Show-SettingsDialog })

    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $opts = Show-AdvancedActivationDialog
        if (-not $opts.Apply) { return }
        try {
            $script:IsBusy = $true; $script:ActionStartTime = Get-Date; $script:LastActionName = "Activar"
            $script:PanelLblDet1.Text = "Activando..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
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
                if ($s.Estado -eq "PARCIAL") { $extra = "`n`nSigue PARCIAL. Usa REPARAR (Deep Repair)." }
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
            $script:PanelLblDet1.Text = "Desactivando..."
            $script:PanelLblDet1.ForeColor = $script:Colors.Warn
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
# 28. ARRANQUE
# ==================================================================
Write-AppLog "=============================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v4.2 Final" "INFO"
Write-AppLog "=============================================" "INFO"

if (Test-Admin) { Write-AppLog "Admin: SI" "INFO" } else { Write-AppLog "Admin: NO" "WARN" }
if (Test-Admin) { Add-DefenderExclusion | Out-Null }

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
$script:LastKnownEstado = $initQuick.Estado

# ==================================================================
# 29. BANDEJA + MENU
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

# ==================================================================
# 30. LOOP
# ==================================================================
[System.Windows.Forms.Application]::Run()