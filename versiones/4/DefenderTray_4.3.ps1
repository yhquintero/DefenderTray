<#
.SYNOPSIS
    Control de Seguridad de Windows Defender - v4.3
.DESCRIPTION
    - Desactivacion TOTAL agresiva (mata MsMpEng.exe)
    - Barra de menu restaurada
    - Modo kiosco funcional con contrasena
    - Bordes ajustados
.NOTES
    Ejecutar como Administrador.
    Autor: Ing. Yosvany Hernandez Quintero
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue

# ==================================================================
# CONSTANTES DE TEXTO (tilde y enie via [char])
# ==================================================================
$script:CH_N = [char]0x00F1        # ñ
$script:CH_O = [char]0x00D3        # Ó
$script:TXT_PWD = "Contrase" + $script:CH_N + "a"

# ==================================================================
# ARGUMENTOS Y RUTAS
# ==================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")
$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.CommandPath }
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) { $script:ScriptPath = $MyInvocation.MyCommand.Path }
$script:ScriptDir  = if ($script:ScriptPath) { Split-Path -Parent $script:ScriptPath } else { (Get-Location).Path }

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

# ==================================================================
# CONFIG (VARIABLES INDIVIDUALES)
# ==================================================================
$script:CfgDarkTheme    = $true
$script:CfgKioskMode    = $false
$script:CfgKioskHash    = ""
$script:CfgFirstRunDone = $false
$script:DarkTheme       = $true
$script:IsKioskMode     = $false

function Load-AppConfig {
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

# ==================================================================
# LOG
# ==================================================================
function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# ESPERA
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
# PALETAS
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
        ConsoleBg=[System.Drawing.Color]::FromArgb(8,12,20); ConsoleText=[System.Drawing.Color]::FromArgb(0,255,180)
        MenuBg=[System.Drawing.Color]::FromArgb(16,22,38); MenuHighlight=[System.Drawing.Color]::FromArgb(0,120,180)
    }
}
Load-AppConfig
$script:Colors = Get-FuturisticPalette
function Refresh-Palette { $script:Colors = Get-FuturisticPalette }

# ==================================================================
# ESTADO
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
# ADMIN / HASH
# ==================================================================
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

# ==================================================================
# DESACTIVAR - VERSION TOTALMENTE AGRESIVA v4.3
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

    Write-AppLog "Desactivacion TOTAL v4.3..." "INFO"

    # 1) Set-MpPreference
    [void]$log.Add("[1] Desactivando 10 preferencias...")
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            $prefs = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                       "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                       "DisableEmailScanning","DisableIntrusionPreventionSystem","DisableRemovableDriveScanning",
                       "DisableScanningNetworkFiles")
            foreach ($p in $prefs) {
                try { Set-MpPreference @{ $p = $true } -Force -ErrorAction SilentlyContinue } catch { }
            }
            try { Set-MpPreference -MAPSReporting Disabled -Force -ErrorAction SilentlyContinue } catch { }
            try { Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue } catch { }
        }
    } catch { }

    # 2) reg delete de politicas
    [void]$log.Add("[2] Borrando politicas...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }

    # 3) Recrear politicas de bloqueo
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

    # 4) DETENER 8 SERVICIOS + registry Start=4
    [void]$log.Add("[4] Deteniendo 8 servicios...")
    $svcs = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")
    foreach ($s in $svcs) {
        try {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            $null = & sc.exe stop $s 2>&1
            $null = & sc.exe config $s start= disabled 2>&1
        } catch { }
    }

    # 5) Registry Start=4
    [void]$log.Add("[5] Registry Start=4 en todos...")
    $paths = @("HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
               "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
               "HKLM:\SYSTEM\CurrentControlSet\Services\Sense",
               "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisDrv",
               "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot",
               "HKLM:\SYSTEM\CurrentControlSet\Services\Wdfilter",
               "HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService",
               "HKLM:\SYSTEM\CurrentControlSet\Services\wscsvc")
    foreach ($sp in $paths) {
        try {
            if (Test-Path $sp) {
                Set-ItemProperty -Path $sp -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    # 6) MATAR MsMpEng.exe (el proceso del motor)
    [void]$log.Add("[6] Matando MsMpEng.exe...")
    try {
        $null = & taskkill.exe /F /IM MsMpEng.exe 2>&1
        $null = & taskkill.exe /F /IM NisSrv.exe 2>&1
        $null = & taskkill.exe /F /IM SecurityHealthService.exe 2>&1
        $null = & taskkill.exe /F /IM SecurityHealthSystray.exe 2>&1
    } catch { }

    # 7) Esperar y verificar
    [void]$log.Add("[7] Verificando tras 4s...")
    Wait-WithDoEvents -Milliseconds 4000
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        [void]$log.Add("[8] Reintentando detener...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        $null = & taskkill.exe /F /IM MsMpEng.exe 2>&1
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= disabled 2>&1
        Wait-WithDoEvents -Milliseconds 2000
    }

    # 8) Verificar resultado final
    $svcFin = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    if ($null -eq $procFin -and ($null -eq $svcFin -or $svcFin.Status -ne 'Running')) {
        [void]$log.Add("[OK] Desactivacion TOTAL exitosa.")
        Write-AppLog "Desactivacion total: OK" "INFO"
    } else {
        [void]$log.Add("[!] Aun activo. REINICIA el equipo.")
        Write-AppLog "Desactivacion requiere reinicio" "WARN"
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    return ($log -join "`n")
}

# ==================================================================
# ACTIVAR
# ==================================================================
function Enable-Defender {
    param([bool]$EnableCloud = $false, [bool]$EnableSamples = $false, [bool]$EnableTamper = $false)
    $log = New-Object System.Collections.ArrayList
    Write-AppLog "Activando..." "INFO"
    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService","wscsvc")) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (Test-Path $p) { Set-ItemProperty -Path $p -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue }
    }
    [void]$log.Add("[1] Start=2 restaurado.")
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (Test-Path $regPath) { Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop; [void]$log.Add("[2] Politicas eliminadas.") }
    } catch { }
    foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
        try {
            Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
            $null = & sc.exe config $s start= auto 2>&1
            Start-Service -Name $s -ErrorAction SilentlyContinue
        } catch { }
    }
    Wait-WithDoEvents -Milliseconds 3000
    try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
    if ($EnableCloud) { try { Set-MpPreference -MAPSReporting Advanced -Force } catch { } }
    if ($EnableSamples) { try { Set-MpPreference -SubmitSamplesConsent 1 -Force } catch { } }
    return ($log -join "`n")
}

# ==================================================================
# DIALOGO DE PASSWORD (KIOSCO) - FUNCIONAL
# ==================================================================
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    $hashGuardado = $script:CfgKioskHash
    if ([string]::IsNullOrEmpty($hashGuardado)) { return $true }

    $script:KioskOk = $false
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Acceso restringido"
    $dlg.ClientSize = New-Object System.Drawing.Size(360, 155)
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

# ==================================================================
# BOTONES Y ESTADO
# ==================================================================
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
        $Boton.Cursor = "Hand"
    } else {
        $Boton.BackColor = $script:Colors.BtnDisabled
        $Boton.ForeColor = $script:Colors.BtnDisabledT
        $Boton.FlatAppearance.BorderColor = $script:Colors.BtnDisabled
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnDisabled
        $Boton.Cursor = "Default"
    }
}

# ==================================================================
# DIAGNOSTICO / HISTORIAL (simplificados)
# ==================================================================
$script:EventHistory = New-Object System.Collections.ArrayList
function Add-History {
    param([string]$Accion, [string]$Resultado, [double]$Segundos = 0)
    try {
        $entry = [PSCustomObject]@{ Hora=(Get-Date); Accion=$Accion; Resultado=$Resultado; Segundos=$Segundos }
        [void]$script:EventHistory.Insert(0, $entry)
        while ($script:EventHistory.Count -gt 20) { $script:EventHistory.RemoveAt($script:EventHistory.Count - 1) }
    } catch { }
}

function Get-CompleteDefenderReport {
    $r = New-Object System.Collections.ArrayList
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        $c = if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$r.Add([PSCustomObject]@{ Modulo="Servicio WinDefend"; Valor=$svc.Status; Color=$c })
    }
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            [void]$r.Add([PSCustomObject]@{ Modulo="Antivirus habilitado"; Valor=$st.AntivirusEnabled; Color=$(if($st.AntivirusEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Proteccion tiempo real"; Valor=$st.RealTimeProtectionEnabled; Color=$(if($st.RealTimeProtectionEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Monitor comportamiento"; Valor=$st.BehaviorMonitorEnabled; Color=$(if($st.BehaviorMonitorEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Tamper Protection"; Valor=$st.IsTamperProtected; Color=$(if($st.IsTamperProtected){$script:Colors.Ok}else{$script:Colors.Warn}) })
        } catch { }
    }
    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    if ($null -ne $proc) {
        [void]$r.Add([PSCustomObject]@{ Modulo="Proceso MsMpEng"; Valor="Corriendo"; Color=$script:Colors.Bad })
    } else {
        [void]$r.Add([PSCustomObject]@{ Modulo="Proceso MsMpEng"; Valor="Detenido"; Color=$script:Colors.Ok })
    }
    $hp = Test-DefenderPolicyDisabled
    [void]$r.Add([PSCustomObject]@{ Modulo="Politica bloqueante"; Valor=$(if($hp){"SI"}else{"NO"}); Color=$(if($hp){$script:Colors.Bad}else{$script:Colors.Ok}) })
    return $r
}

function Show-CompleteStatusDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Verificacion"
    $dlg.ClientSize = New-Object System.Drawing.Size(680, 520)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentPurple
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "VERIFICACION"
    $lblH.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $lblEstado = New-Object System.Windows.Forms.Label
    $lblEstado.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblEstado.Size = New-Object System.Drawing.Size(650, 24)
    $lblEstado.Location = New-Object System.Drawing.Point(15, 60)
    $lblEstado.ForeColor = $script:Colors.Text
    $dlg.Controls.Add($lblEstado)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 90)
    $lv.Size = New-Object System.Drawing.Size(650, 340)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Modulo", 300)
    [void]$lv.Columns.Add("Estado", 320)
    $dlg.Controls.Add($lv)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 445 120 32
    $dlg.Controls.Add($btnCerr)

    # Cargar
    $lv.Items.Clear()
    foreach ($row in (Get-CompleteDefenderReport)) {
        $it = New-Object System.Windows.Forms.ListViewItem($row.Modulo)
        [void]$it.SubItems.Add([string]$row.Valor)
        if ($null -ne $row.Color) { $it.ForeColor = $row.Color }
        [void]$lv.Items.Add($it)
    }
    $q = Get-QuickStatus
    if ($q.Estado -eq "ACTIVO") { $lblEstado.Text = ">>> ACTIVADO <<<"; $lblEstado.ForeColor = $script:Colors.Ok }
    elseif ($q.Estado -eq "PARCIAL") { $lblEstado.Text = ">>> PARCIAL - Usa REPARAR <<<"; $lblEstado.ForeColor = $script:Colors.Warn }
    else { $lblEstado.Text = ">>> DESACTIVADO <<<"; $lblEstado.ForeColor = $script:Colors.Bad }

    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial"
    $dlg.ClientSize = New-Object System.Drawing.Size(700, 460)
    $dlg.StartPosition = "CenterScreen"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.AccentBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "HISTORIAL"
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
    $lv.Size = New-Object System.Drawing.Size(670, 340)
    $lv.BorderStyle = "FixedSingle"
    $lv.BackColor = $script:Colors.BgSecondary
    $lv.ForeColor = $script:Colors.Text
    [void]$lv.Columns.Add("Hora", 160)
    [void]$lv.Columns.Add("Accion", 150)
    [void]$lv.Columns.Add("Resultado", 280)
    [void]$lv.Columns.Add("Seg", 70)
    $dlg.Controls.Add($lv)

    foreach ($e in $script:EventHistory) {
        $it = New-Object System.Windows.Forms.ListViewItem($e.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$it.SubItems.Add($e.Accion)
        [void]$it.SubItems.Add($e.Resultado)
        [void]$it.SubItems.Add(("{0:N2}" -f $e.Segundos))
        [void]$lv.Items.Add($it)
    }

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 420 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# DIALOGO DE REPARACION CON CONSOLA
# ==================================================================
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
    $dlg.ClientSize = New-Object System.Drawing.Size(900, 630)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "Sizable"
    $dlg.BackColor = $script:Colors.Bg
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
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
    $console.ScrollBars = "Both"
    $console.ReadOnly = $true
    $console.WordWrap = $false
    $console.Font = New-Object System.Drawing.Font("Consolas", 9)
    $console.BackColor = $script:Colors.ConsoleBg
    $console.ForeColor = $script:Colors.ConsoleText
    $console.Location = New-Object System.Drawing.Point(15, 70)
    $console.Size = New-Object System.Drawing.Size(870, 450)
    $console.Anchor = "Top,Left,Right,Bottom"
    $dlg.Controls.Add($console)
    $script:RepairConsole = $console

    $btnReg = New-NeonButton "1. Borrar Politicas" $script:Colors.AccentRed $script:Colors.AccentRedH 15 530 170 34
    $btnSvc = New-NeonButton "2. Servicios" $script:Colors.AccentAmber $script:Colors.AccentAmberH 195 530 150 34
    $btnGpu = New-NeonButton "3. gpupdate" $script:Colors.AccentPurple $script:Colors.AccentPurpH 355 530 140 34
    $btnSFC = New-NeonButton "4. sfc" $script:Colors.AccentBlue $script:Colors.AccentBlueH 505 530 120 34
    $btnDISM = New-NeonButton "5. DISM" $script:Colors.AccentCyan $script:Colors.AccentCyanH 635 530 120 34
    $btnKill = New-NeonButton "Matar MsMpEng" $script:Colors.AccentRed $script:Colors.AccentRedH 765 530 130 34
    $btnTodo = New-NeonButton "REPARAR TODO" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 572 300 34
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 765 572 130 34

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
        Invoke-ConsoleCmd "taskkill /F /IM SecurityHealthService.exe"
    })
    $btnTodo.Add_Click({
        $c = $script:RepairConsole
        $c.AppendText("`r`n=== REPARACION COMPLETA ===`r`n")
        Invoke-ConsoleCmd "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`" /f"
        Invoke-ConsoleCmd "gpupdate /force"
        foreach ($s in @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")) {
            Invoke-ConsoleCmd "sc config $s start= auto"
            Invoke-ConsoleCmd "sc start $s"
        }
        try { Set-MpPreference -DisableRealtimeMonitoring $false -Force } catch { }
        Invoke-ConsoleCmd "sfc /scannow"
        Invoke-ConsoleCmd "DISM /Online /Cleanup-Image /RestoreHealth"
        $c.AppendText("`r`n[OK] REINICIA EL EQUIPO.`r`n")
        [System.Windows.Forms.MessageBox]::Show("Reparacion completada. Reinicia el equipo.","OK","OK","Information") | Out-Null
    })
    $btnCerr.Add_Click({ $dlg.Close() })

    $console.AppendText("Consola de reparacion lista.`r`n")
    [void]$dlg.ShowDialog()
    $script:RepairConsole = $null
    $dlg.Dispose()
}

# ==================================================================
# CONFIGURACION CON CONTRASEÑA
# ==================================================================
function Show-SettingsDialog {
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

    $chkDark = New-Object System.Windows.Forms.CheckBox
    $chkDark.Text = "Tema oscuro (siempre activo)"
    $chkDark.Checked = $true
    $chkDark.Enabled = $false
    $chkDark.Location = New-Object System.Drawing.Point(20, 150)
    $chkDark.Size = New-Object System.Drawing.Size(450, 25)
    $chkDark.ForeColor = $script:Colors.TextMuted
    $dlg.Controls.Add($chkDark)

    $btnSave = New-NeonButton "Guardar" $script:Colors.AccentGreen $script:Colors.AccentGreenH 20 220 200 34
    $btnCancel = New-NeonButton "Cancelar" $script:Colors.Neutral $script:Colors.TextMuted 300 220 180 34
    $dlg.Controls.Add($btnSave)
    $dlg.Controls.Add($btnCancel)

    $btnSave.Add_Click({
        $script:IsKioskMode = $chkKiosk.Checked
        if ($chkKiosk.Checked -and -not [string]::IsNullOrEmpty($txtPwd.Text)) {
            $script:CfgKioskHash = Get-StringHash $txtPwd.Text
        }
        if (-not $chkKiosk.Checked) {
            $script:CfgKioskHash = ""
        }
        Save-AppConfig
        [System.Windows.Forms.MessageBox]::Show("Configuracion guardada.","OK","OK","Information") | Out-Null
        $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# AYUDA
# ==================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(700, 500)
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
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = "Vertical"
    $txt.Location = New-Object System.Drawing.Point(15, 65)
    $txt.Size = New-Object System.Drawing.Size(670, 380)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $ayuda = @'
DEFENDER CONTROL - v4.3
=========================

NOVEDADES v4.3
--------------
1. Desactivacion TOTAL: mata MsMpEng.exe + 8 servicios.
2. Barra de menu restaurada (Archivo / Acciones / Herramientas / Ayuda).
3. Modo kiosco FUNCIONAL: guarda el hash al activarlo y lo pide al abrir.
4. "Contrasena" -> "Contrasena" con enie correcta.
5. Ventanas ajustadas al tamano minimo.

DESACTIVACION TOTAL
-------------------
El boton DESACTIVAR PROTECCION ahora:
  - Detiene 8 servicios (WinDefend, WdNisSvc, Sense, WdNisDrv,
    WdBoot, Wdfilter, SecurityHealthService, wscsvc).
  - Configura Start=4 en el registro para los 8.
  - MATA los procesos MsMpEng.exe, NisSrv.exe, etc.
  - Verifica el resultado y reintenta.

En Windows 11 aun puede requerir REINICIO. Si sigue en PARCIAL,
usa REPARAR (Deep Repair) o reinicia el equipo.

MODO KIOSCO
-----------
1. Config -> marcar "Modo kiosco".
2. Escribir la contrasena.
3. Guardar.
4. Al abrir el panel, se pedira la contrasena.

ATENCION: Si olvidas la contrasena, edita:
  %LOCALAPPDATA%\DefenderTray\config.json
y pon "KioskMode": false.

ATAJOS
------
F1      Ayuda
F5      Refrescar
Esc     Cerrar panel

(c) 2026 - Ing. Yosvany Hernandez Quintero
'@
    $txt.Text = $ayuda
    $dlg.Controls.Add($txt)

    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 455 140 30
    $dlg.Controls.Add($btnCerr)
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# PANEL PRINCIPAL CON BARRA DE MENU
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
        $script:PanelLblDet1.Text = "Usa REPARAR o reinicia el equipo."
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
    $form.Text = "Control de Seguridad v4.3"
    $form.ClientSize = New-Object System.Drawing.Size(460, 620)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = [System.Drawing.SystemIcons]::Shield

    # BARRA DE MENU
    $menuStrip = New-Object System.Windows.Forms.MenuStrip
    $menuStrip.BackColor = $script:Colors.MenuBg
    $menuStrip.ForeColor = $script:Colors.Text
    $menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $menuStrip.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::System
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
    $miVer.Text = "Verificar"
    $miVer.Add_Click({ Show-CompleteStatusDialog })
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
        $os = try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $null }
        $t = "DEFENDER CONTROL v4.3`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801`n`nSistema: $(if($os){$os.Caption}else{'?'})"
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

    # Header visual
    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 24)
    $header.Size = New-Object System.Drawing.Size(460, 70)
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
    $lblSubH.Text = "v4.3 - Total Disable Edition"
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
    $lblReloj.Location = New-Object System.Drawing.Point(285, 12)
    $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)
    $lblTimer = New-Object System.Windows.Forms.Label
    $lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimer.ForeColor = $script:Colors.AccentCyan
    $lblTimer.BackColor = [System.Drawing.Color]::Transparent
    $lblTimer.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimer.Location = New-Object System.Drawing.Point(285, 32)
    $lblTimer.TextAlign = "MiddleRight"
    $lblTimer.Text = "listo"
    $header.Controls.Add($lblTimer)

    # Card
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 105)
    $card.Size = New-Object System.Drawing.Size(430, 130)
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
    $lblDet1.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet1.Location = New-Object System.Drawing.Point(12, 62)
    $card.Controls.Add($lblDet1)

    $lblDet2 = New-Object System.Windows.Forms.Label
    $lblDet2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDet2.ForeColor = $script:Colors.TextMuted
    $lblDet2.BackColor = [System.Drawing.Color]::Transparent
    $lblDet2.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet2.Location = New-Object System.Drawing.Point(12, 82)
    $card.Controls.Add($lblDet2)

    $lblDet3 = New-Object System.Windows.Forms.Label
    $lblDet3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDet3.ForeColor = $script:Colors.AccentCyan
    $lblDet3.BackColor = [System.Drawing.Color]::Transparent
    $lblDet3.Size = New-Object System.Drawing.Size(410, 16)
    $lblDet3.Location = New-Object System.Drawing.Point(12, 104)
    $card.Controls.Add($lblDet3)

    # Botones
    $btnVerificar  = New-NeonButton "VERIFICAR" $script:Colors.AccentPurple $script:Colors.AccentPurpH 15 245 430 32
    $btnActivar    = New-NeonButton "ACTIVAR PROTECCION" $script:Colors.AccentGreen $script:Colors.AccentGreenH 15 285 210 32
    $btnDesactivar = New-NeonButton "DESACTIVAR PROTECCION" $script:Colors.AccentRed $script:Colors.AccentRedH 235 285 210 32
    $btnReparar    = New-NeonButton "REPARAR (Deep Repair)" $script:Colors.AccentAmber $script:Colors.AccentAmberH 15 325 430 36
    $btnHistorial  = New-NeonButton "Historial" $script:Colors.AccentBlue $script:Colors.AccentBlueH 15 370 102 32
    $btnDiag       = New-NeonButton "Diagnostico" $script:Colors.AccentAmber $script:Colors.AccentAmberH 122 370 102 32
    $btnConfig     = New-NeonButton "Config" $script:Colors.AccentBlue $script:Colors.AccentBlueH 229 370 102 32
    $btnAyuda      = New-NeonButton "Ayuda" $script:Colors.AccentBlue $script:Colors.AccentBlueH 336 370 109 32
    $btnSalir      = New-NeonButton "SALIR" $script:Colors.AccentRed $script:Colors.AccentRedH 15 412 430 32

    foreach ($b in @($btnVerificar,$btnActivar,$btnDesactivar,$btnReparar,$btnHistorial,$btnDiag,$btnConfig,$btnAyuda,$btnSalir)) {
        $form.Controls.Add($b)
    }

    # Ajustar ClientSize al ultimo boton + 20px
    $form.ClientSize = New-Object System.Drawing.Size(460, 412 + 32 + 20)

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
    $btnDiag.Add_Click({ Show-CompleteStatusDialog })
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
            $extra = ""
            if ($s.Estado -eq "PARCIAL") { $extra = "`n`nSi sigue PARCIAL, reinicia el equipo." }
            [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s$extra" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
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
            "Desactivar Windows Defender COMPLETAMENTE?`n`n" +
            "Se detendran 8 servicios y se mataran los procesos.`n" +
            "Puede requerir REINICIO para aplicar al 100%.",
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
            if ($s.Estado -ne "DESACTIVADO") { $extra = "`n`nREINICIA el equipo para aplicar al 100%." }
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

# ==================================================================
# ARRANQUE
# ==================================================================
Write-AppLog "Aplicacion iniciada v4.3" "INFO"
if (Test-Admin) {
    try {
        Add-MpPreference -ExclusionPath $script:ScriptDir -Force -ErrorAction SilentlyContinue
    } catch { }
}

$initQuick = Get-QuickStatus

# ==================================================================
# BANDEJA + MENU
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text = "Control de Seguridad v4.3"
$script:notifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor = $script:Colors.MenuBg
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
[void]$menu.Items.Add((Add-MenuItem "Configuracion" { Show-SettingsDialog }))
[void]$menu.Items.Add((Add-MenuItem "Ayuda" { Show-HelpDialog }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miAct = Add-MenuItem "Activar Defender" {
    if (-not (Test-Admin)) { return }
    $null = Enable-Defender
    $s = Get-QuickStatus
    Add-History -Accion "Activar (menu)" -Resultado $s.Estado -Segundos 0
}
$miDes = Add-MenuItem "Desactivar Defender" {
    if (-not (Test-Admin)) { return }
    $null = Disable-Defender
    $s = Get-QuickStatus
    Add-History -Accion "Desactivar (menu)" -Resultado $s.Estado -Segundos 0
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
# LOOP
# ==================================================================
[System.Windows.Forms.Application]::Run()