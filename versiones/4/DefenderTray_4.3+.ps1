<#
.SYNOPSIS
    Control de Seguridad de Windows Defender - v4.3 Final
.DESCRIPTION
    - Iconos dinamicos por estado (verde/rojo/naranja).
    - Desactivacion TOTAL (8 servicios + MsMpEng.exe).
    - Barra de estado restaurada.
    - Modo kiosco con contrasena.
    - Bordes ajustados.
.NOTES
    Ejecutar como Administrador.
    Autor: Ing. Yosvany Hernandez Quintero
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================================================================
# 2. ARGUMENTOS Y RUTAS
# ==================================================================
$script:SilentMode   = ($args -contains "-silent")
$script:PortableMode = ($args -contains "-portable")
$script:ScriptPath = $PSCommandPath
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
# 3. TEXTO CON Ñ
# ==================================================================
$script:CH_N = [char]0x00F1
$script:TXT_PWD = "Contrase" + $script:CH_N + "a"

# ==================================================================
# 4. CONFIG
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
# 5. LOG
# ==================================================================
function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# 6. ESPERA
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
# 7. PALETA
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
        MenuBg=[System.Drawing.Color]::FromArgb(16,22,38)
    }
}
Load-AppConfig
$script:Colors = Get-FuturisticPalette

# ==================================================================
# 8. ICONOS DINAMICOS (SEGUN ESTADO)
# ==================================================================
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
    try {
        $hicon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hicon)
        return $icon
    } catch { return [System.Drawing.SystemIcons]::Shield }
}

$script:IconOk      = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(0, 200, 100))
$script:IconBad     = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 40, 80))
$script:IconPartial = New-IconFromColor -Color ([System.Drawing.Color]::FromArgb(220, 140, 0))

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

# ==================================================================
# 9. ESTADO RAPIDO
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
    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    $engineRunning = ($null -ne $proc)

    $rtpDisabled = Test-RTPDisabled
    $hasPolicy = Test-DefenderPolicyDisabled

    # ACTIVO solo si servicio + motor corriendo + RTP ON + sin politica
    $isActive = $running -and $engineRunning -and (-not $rtpDisabled) -and (-not $hasPolicy)

    # DESACTIVADO total si servicio detenido Y motor detenido
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

# ==================================================================
# 10. ADMIN / HASH
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
# 11. DESACTIVAR TOTAL
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA. Desactivala manualmente.")
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Desactivacion TOTAL..." "INFO"

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
    [void]$log.Add("[2] Borrando politicas de grupo...")
    foreach ($p in @("HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
                     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
                     "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies")) {
        try { $null = & reg.exe delete $p /f 2>&1 } catch { }
    }

    # 3) Recrear politicas de bloqueo
    [void]$log.Add("[3] Recreando politicas de bloqueo...")
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

    # 4) Detener 8 servicios
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
    [void]$log.Add("[5] Escribiendo Start=4 en registro...")
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

    # 6) Matar procesos
    [void]$log.Add("[6] Matando MsMpEng.exe + NisSrv.exe...")
    foreach ($proc in @("MsMpEng.exe","NisSrv.exe","SecurityHealthService.exe","SecurityHealthSystray.exe","MpCmdRun.exe")) {
        try { $null = & taskkill.exe /F /IM $proc 2>&1 } catch { }
    }

    # 7) Verificar
    [void]$log.Add("[7] Verificando...")
    Wait-WithDoEvents -Milliseconds 4000

    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue

    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        [void]$log.Add("[8] Reintentando detener WinDefend...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        $null = & taskkill.exe /F /IM MsMpEng.exe 2>&1
        try {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch { }
        $null = & sc.exe config WinDefend start= disabled 2>&1
        Wait-WithDoEvents -Milliseconds 2000
    }

    # Resultado final
    $svcFin = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $procFin = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue

    if (($null -eq $svcFin -or $svcFin.Status -ne 'Running') -and ($null -eq $procFin)) {
        [void]$log.Add("[OK] Desactivacion TOTAL EXITOSA.")
    } else {
        [void]$log.Add("[!] Aun activo. REINICIA EL EQUIPO para completar.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo: {0:N2}s" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog "Desactivacion terminada" "INFO"
    return ($log -join "`n")
}

# ==================================================================
# 12. ACTIVAR
# ==================================================================
function Enable-Defender {
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
    [void]$log.Add("[3] Servicios iniciados.")
    Wait-WithDoEvents -Milliseconds 3000
    try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-MpPreference -DisableBehaviorMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-MpPreference -DisableIOAVProtection $false -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction SilentlyContinue } catch { }
    [void]$log.Add("[4] Preferencias reactivadas.")
    return ($log -join "`n")
}

# ==================================================================
# 13. DIALOGO KIOSCO
# ==================================================================
function Test-KioskPassword {
    if (-not $script:IsKioskMode) { return $true }
    if ([string]::IsNullOrEmpty($script:CfgKioskHash)) { return $true }

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
# 14. BOTON NEON
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

# ==================================================================
# 15. HISTORIAL
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

# ==================================================================
# 16. INFORME COMPLETO
# ==================================================================
function Get-CompleteDefenderReport {
    $r = New-Object System.Collections.ArrayList
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        $c = if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$r.Add([PSCustomObject]@{ Modulo="Servicio WinDefend"; Valor=$svc.Status; Color=$c })
    }
    $proc = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
    if ($null -ne $proc) {
        [void]$r.Add([PSCustomObject]@{ Modulo="Proceso MsMpEng"; Valor="Corriendo"; Color=$script:Colors.Bad })
    } else {
        [void]$r.Add([PSCustomObject]@{ Modulo="Proceso MsMpEng"; Valor="Detenido"; Color=$script:Colors.Ok })
    }
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            [void]$r.Add([PSCustomObject]@{ Modulo="Antivirus habilitado"; Valor=$st.AntivirusEnabled; Color=$(if($st.AntivirusEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Proteccion tiempo real"; Valor=$st.RealTimeProtectionEnabled; Color=$(if($st.RealTimeProtectionEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Monitor comportamiento"; Valor=$st.BehaviorMonitorEnabled; Color=$(if($st.BehaviorMonitorEnabled){$script:Colors.Ok}else{$script:Colors.Bad}) })
            [void]$r.Add([PSCustomObject]@{ Modulo="Tamper Protection"; Valor=$st.IsTamperProtected; Color=$(if($st.IsTamperProtected){$script:Colors.Warn}else{$script:Colors.Ok}) })
        } catch { }
    }
    $hp = Test-DefenderPolicyDisabled
    [void]$r.Add([PSCustomObject]@{ Modulo="Politica bloqueante"; Valor=$(if($hp){"SI"}else{"NO"}); Color=$(if($hp){$script:Colors.Bad}else{$script:Colors.Ok}) })
    return $r
}

# ==================================================================
# 17. DIALOGO VERIFICACION
# ==================================================================
function Show-CompleteStatusDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Verificacion"
    $dlg.ClientSize = New-Object System.Drawing.Size(680, 520)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
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

    $btnRef = New-NeonButton "Refrescar" $script:Colors.AccentPurple $script:Colors.AccentPurpH 15 445 140 32
    $btnCerr = New-NeonButton "Cerrar" $script:Colors.Neutral $script:Colors.TextMuted 545 445 120 32
    $dlg.Controls.Add($btnRef)
    $dlg.Controls.Add($btnCerr)

    $script:VerifLv = $lv
    $script:VerifLbl = $lblEstado

    function Refresh-Verif {
        $script:VerifLv.Items.Clear()
        foreach ($row in (Get-CompleteDefenderReport)) {
            $it = New-Object System.Windows.Forms.ListViewItem($row.Modulo)
            [void]$it.SubItems.Add([string]$row.Valor)
            if ($null -ne $row.Color) { $it.ForeColor = $row.Color }
            [void]$script:VerifLv.Items.Add($it)
        }
        $q = Get-QuickStatus
        if ($q.Estado -eq "ACTIVO") { $script:VerifLbl.Text = ">>> ACTIVADO <<<"; $script:VerifLbl.ForeColor = $script:Colors.Ok }
        elseif ($q.Estado -eq "PARCIAL") { $script:VerifLbl.Text = ">>> PARCIAL - Usa REPARAR <<<"; $script:VerifLbl.ForeColor = $script:Colors.Warn }
        else { $script:VerifLbl.Text = ">>> DESACTIVADO <<<"; $script:VerifLbl.ForeColor = $script:Colors.Bad }
    }

    Refresh-Verif
    $btnRef.Add_Click({ Refresh-Verif })
    $btnCerr.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 18. DIALOGO HISTORIAL
# ==================================================================
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
# 19. REPARACION PROFUNDA
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
# 20. CONFIGURACION
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

    $lblNota = New-Object System.Windows.Forms.Label
    $lblNota.Text = "Si olvidas la " + $script:TXT_PWD + ", edita config.json y pon KioskMode: false"
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblNota.ForeColor = $script:Colors.TextMuted
    $lblNota.Location = New-Object System.Drawing.Point(20, 150)
    $lblNota.Size = New-Object System.Drawing.Size(470, 40)
    $dlg.Controls.Add($lblNota)

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
# 21. AYUDA
# ==================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda"
    $dlg.ClientSize = New-Object System.Drawing.Size(700, 500)
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
    $txt.Size = New-Object System.Drawing.Size(670, 380)
    $txt.BackColor = $script:Colors.BgSecondary
    $txt.ForeColor = $script:Colors.Text
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $ayuda = @'
DEFENDER CONTROL - v4.3 FINAL
===============================

ICONOS DINAMICOS
----------------
El icono en la bandeja cambia de color segun el estado:
  * VERDE    -> Defender ACTIVADO y protegiendo.
  * ROJO     -> Defender DESACTIVADO completamente.
  * NARANJA  -> Estado PARCIAL (falta algo).

DESACTIVACION TOTAL
-------------------
El boton DESACTIVAR PROTECCION ahora:
  1. Desactiva 10 preferencias.
  2. Borra politicas de grupo (reg delete).
  3. Recrea politicas de bloqueo.
  4. Detiene 8 servicios.
  5. Escribe Start=4 en registro.
  6. MATA MsMpEng.exe, NisSrv.exe y otros.
  7. Verifica y reintenta.

En Windows 11 22H2+ puede requerir REINICIO.
Si sigue en PARCIAL, reinicia el equipo.

BARRA DE ESTADO
---------------
En la parte inferior del panel muestra:
  * Texto contextual segun el estado actual.
  * Atajos disponibles.

MODO KIOSCO
-----------
1. Config -> marcar "Modo kiosco".
2. Escribir contrasena.
3. Guardar.
4. Al abrir el panel pedira la contrasena.

Si olvidas la contrasena, edita:
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
# 22. PANEL PRINCIPAL
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
$script:PanelStatusLabel   = $null
$script:IsBusy             = $false
$script:ActionStartTime    = $null
$script:LastActionTime     = 0
$script:LastActionName     = ""

function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $s = Get-QuickStatus
    $diag = "Servicio:$($s.ServiceRunning) | Motor:$($s.EngineRunning) | RTP:$($s.RealTimeProtectionEnabled) | Politica:$($s.HasPolicy)"

    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Ok
        $script:PanelLblDet1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $false
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "ACTIVADO: Defender protegiendo. Puedes desactivarlo o verificar modulos."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Ok
        }
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPart
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.Warn
        $script:PanelLblDet1.Text = "Falta proteccion real. Pulsa REPARAR o reinicia."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $true
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "PARCIAL: falta proteccion real. Pulsa REPARAR o reinicia el equipo."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Warn
        }
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.Bad
        $script:PanelLblDet1.Text = "El antivirus esta completamente inactivo."
        $script:PanelLblDet2.Text = $diag
        Set-NeonButtonState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-NeonButtonState -Boton $script:PanelBtnDesactivar -Habilitado $false
        if ($null -ne $script:PanelStatusLabel) {
            $script:PanelStatusLabel.Text = "DESACTIVADO: antivirus inactivo. Pulsa ACTIVAR para restaurar."
            $script:PanelStatusLabel.ForeColor = $script:Colors.Bad
        }
    }

    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDet3.Text = "Ultima: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDet3.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    }

    # Actualizar icono de bandeja
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
    $form.ClientSize = New-Object System.Drawing.Size(460, 480)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Bg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = $script:IconOk

    # MENU
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

    $mAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
    $mAyuda.Text = "A&yuda"
    $mAyuda.ForeColor = $script:Colors.Text

    $miAy = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAy.Text = "Ayuda (F1)"
    $miAy.Add_Click({ Show-HelpDialog })

    $miAc = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAc.Text = "Acerca de..."
    $miAc.Add_Click({
        $t = "DEFENDER CONTROL v4.3`n`nAutor: Ing. Yosvany Hernandez Quintero`nMovil: +53 5 2160801"
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

    # HEADER visual
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
    $lblSubH.Text = "v4.3 Final - Total Disable"
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

    # CARD
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

    # BOTONES
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

    # BARRA DE ESTADO
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
    $statusShortcuts.Text = "F1 | F5 | Esc"
    $statusShortcuts.ForeColor = $script:Colors.TextMuted
    [void]$statusStrip.Items.Add($statusShortcuts)

    $form.Controls.Add($statusStrip)
    $script:PanelStatusLabel = $statusLabel

    # SCOPE SCRIPT PARA HANDLERS
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

    # Atajos
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

    # Eventos de botones
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
            [System.Windows.Forms.MessageBox]::Show("Estado: $($s.Estado)`nTiempo: {0:N2}s" -f $elapsed, "Resultado", "OK", "Information") | Out-Null
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
            "Desactivar Windows Defender COMPLETAMENTE?`n`nSe detendran 8 servicios y se mataran los procesos.",
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
            if ($s.Estado -ne "DESACTIVADO") { $extra = "`n`nREINICIA el equipo para completar al 100%." }
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
# 23. ARRANQUE
# ==================================================================
Write-AppLog "Aplicacion iniciada v4.3 Final" "INFO"
if (Test-Admin) {
    try {
        Add-MpPreference -ExclusionPath $script:ScriptDir -Force -ErrorAction SilentlyContinue
    } catch { }
}

$initQuick = Get-QuickStatus

# ==================================================================
# 24. ICONO BANDEJA + MENU CONTEXTUAL
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = "Control de Seguridad v4.3"
$script:notifyIcon.Visible = $true
Update-TrayIcon -Estado $initQuick.Estado

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
# 25. LOOP
# ==================================================================
[System.Windows.Forms.Application]::Run()