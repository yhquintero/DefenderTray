<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Version 3.10 con scoping corregido (sin funciones anidadas en eventos).
    - Verificacion completa de 18 modulos de Defender.
    - Panel unico (singleton).
    - Dialogo de opciones avanzadas al activar (nube, muestras, tamper).
    - Timer a 5 segundos con consultas ligeras.
    - Log en %LOCALAPPDATA%\DefenderTray\Logs\.
.NOTES
    Ejecutar como Administrador.
    Creado por: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
    Version: 3.10
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================================================================
# 2. TEXTOS ASCII
# ==================================================================
$script:O_ACCENT       = [char]0x00D3
$script:TXT_PROTECCION = "PROTECCI" + $script:O_ACCENT + "N"
$script:TXT_ACTIVAR    = "ACTIVAR " + $script:TXT_PROTECCION
$script:TXT_DESACTIVAR = "DESACTIVAR " + $script:TXT_PROTECCION

# ==================================================================
# 3. LOG
# ==================================================================
$script:LogFolder = Join-Path $env:LOCALAPPDATA "DefenderTray\Logs"
$script:LogFile   = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
if (-not (Test-Path $script:LogFolder)) {
    New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
}

function Write-AppLog {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# 4. ESPERA SIN BLOQUEAR UI
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
# 5. PALETA
# ==================================================================
$script:Colors = @{
    HeaderOk       = [System.Drawing.Color]::FromArgb(34, 139, 34)
    HeaderWarn     = [System.Drawing.Color]::FromArgb(178, 34, 34)
    HeaderPartial  = [System.Drawing.Color]::FromArgb(200, 130, 0)
    HeaderUnknown  = [System.Drawing.Color]::FromArgb(70, 70, 70)
    Background     = [System.Drawing.Color]::FromArgb(245, 247, 250)
    CardBg         = [System.Drawing.Color]::White
    TextMuted      = [System.Drawing.Color]::FromArgb(108, 117, 125)
    TextDiag       = [System.Drawing.Color]::FromArgb(80, 80, 80)
    BtnGreen       = [System.Drawing.Color]::FromArgb(40, 167, 69)
    BtnGreenHover  = [System.Drawing.Color]::FromArgb(33, 136, 56)
    BtnRed         = [System.Drawing.Color]::FromArgb(220, 53, 69)
    BtnRedHover    = [System.Drawing.Color]::FromArgb(178, 40, 54)
    BtnGray        = [System.Drawing.Color]::FromArgb(210, 210, 210)
    BtnGrayText    = [System.Drawing.Color]::FromArgb(130, 130, 130)
    BtnBlue        = [System.Drawing.Color]::FromArgb(0, 123, 255)
    BtnBlueHover   = [System.Drawing.Color]::FromArgb(0, 98, 204)
    BtnDarkGray    = [System.Drawing.Color]::FromArgb(108, 117, 125)
    BtnDarkGrayHov = [System.Drawing.Color]::FromArgb(84, 91, 98)
    BtnTeal        = [System.Drawing.Color]::FromArgb(23, 162, 184)
    BtnTealHover   = [System.Drawing.Color]::FromArgb(17, 122, 139)
    BtnPurple      = [System.Drawing.Color]::FromArgb(111, 66, 193)
    BtnPurpleHover = [System.Drawing.Color]::FromArgb(90, 52, 158)
    Ok             = [System.Drawing.Color]::FromArgb(34, 139, 34)
    Bad            = [System.Drawing.Color]::FromArgb(200, 40, 40)
    Warn           = [System.Drawing.Color]::FromArgb(200, 130, 0)
    Neutral        = [System.Drawing.Color]::FromArgb(90, 90, 90)
}

# ==================================================================
# 6. ESTADO RAPIDO (sin WMI pesado)
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
        $rtPath = Join-Path $regPath "Real-Time Protection"
        if (Test-Path $rtPath) {
            $rtProps = Get-ItemProperty -Path $rtPath -ErrorAction SilentlyContinue
            if ($null -ne $rtProps) {
                foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
                                 "DisableOnAccessProtection","DisableScanOnRealtimeEnable",
                                 "DisableIOAVProtection","DisableScriptScanning")) {
                    if ($null -ne $rtProps.$n -and [int]$rtProps.$n -eq 1) { return $true }
                }
            }
        }
    } catch { }
    return $false
}

function Test-RTPDisabled {
    $paths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
        "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $v = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($null -ne $v -and $null -ne $v.DisableRealtimeMonitoring) {
                if ([int]$v.DisableRealtimeMonitoring -eq 1) { return $true }
            }
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
    return [PSCustomObject]@{
        ServiceRunning            = $running
        RealTimeProtectionEnabled = -not $rtpDisabled
        HasPolicy                 = $hasPolicy
        IsActive                  = $isActive
    }
}

# ==================================================================
# 7. CACHE
# ==================================================================
$script:CachedFullStatus     = $null
$script:CachedFullStatusTime = [DateTime]::MinValue

function Clear-StatusCache {
    $script:CachedFullStatus = $null
    $script:CachedFullStatusTime = [DateTime]::MinValue
}

# ==================================================================
# 8. INFORME COMPLETO
# ==================================================================
function Get-SafeProp {
    param($Obj, [string]$Name)
    try {
        $v = $Obj.$Name
        if ($null -eq $v) { return "(no disponible)" }
        return $v
    } catch { return "(no disponible)" }
}

function Get-ColorForBool {
    param($Value)
    if ($Value -eq $true)  { return $script:Colors.Ok }
    if ($Value -eq $false) { return $script:Colors.Bad }
    return $script:Colors.Neutral
}

function Get-CompleteDefenderReport {
    $report = New-Object System.Collections.ArrayList

    # Servicio
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        $c = if ($svc.Status -eq 'Running') { $script:Colors.Ok } else { $script:Colors.Bad }
        [void]$report.Add([PSCustomObject]@{ Modulo="Servicio WinDefend"; Valor=$svc.Status; Color=$c })
    }

    # Get-MpComputerStatus
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop

            [void]$report.Add([PSCustomObject]@{ Modulo="Antivirus habilitado";       Valor=(Get-SafeProp $st "AntivirusEnabled");          Color=(Get-ColorForBool $st.AntivirusEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Antispyware habilitado";     Valor=(Get-SafeProp $st "AntispywareEnabled");        Color=(Get-ColorForBool $st.AntispywareEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Servicio AM";                Valor=(Get-SafeProp $st "AMServiceEnabled");          Color=(Get-ColorForBool $st.AMServiceEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Proteccion tiempo real";     Valor=(Get-SafeProp $st "RealTimeProtectionEnabled"); Color=(Get-ColorForBool $st.RealTimeProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Monitor de comportamiento";  Valor=(Get-SafeProp $st "BehaviorMonitorEnabled");    Color=(Get-ColorForBool $st.BehaviorMonitorEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="IOAV Protection";            Valor=(Get-SafeProp $st "IoavProtectionEnabled");     Color=(Get-ColorForBool $st.IoavProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="On-Access Protection";       Valor=(Get-SafeProp $st "OnAccessProtectionEnabled"); Color=(Get-ColorForBool $st.OnAccessProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Inspeccion de red (NIS)";    Valor=(Get-SafeProp $st "NISEnabled");                Color=(Get-ColorForBool $st.NISEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Tamper Protection";          Valor=(Get-SafeProp $st "IsTamperProtected");         Color=(Get-ColorForBool $st.IsTamperProtected) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version del motor";          Valor=(Get-SafeProp $st "AMEngineVersion");           Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version de firma";           Valor=(Get-SafeProp $st "AntivirusSignatureVersion"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Edad de firma (dias)";       Valor=(Get-SafeProp $st "AntivirusSignatureAge");     Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Firma actualizada";          Valor=(Get-SafeProp $st "AntivirusSignatureLastUpdated"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Ultimo scan rapido";         Valor=(Get-SafeProp $st "QuickScanStartTime");        Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Ultimo scan completo";       Valor=(Get-SafeProp $st "FullScanStartTime");         Color=$null })
        } catch {
            [void]$report.Add([PSCustomObject]@{ Modulo="Get-MpComputerStatus"; Valor="ERROR: $($_.Exception.Message)"; Color=$script:Colors.Bad })
        }
    }

    # Get-MpPreference
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        try {
            $p = Get-MpPreference -ErrorAction Stop

            $maps = switch ([int]$p.MAPSReporting) {
                0 { "Desactivado" }
                1 { "Basico" }
                2 { "Avanzado" }
                default { "Desconocido ($($p.MAPSReporting))" }
            }
            $mapsColor = if ([int]$p.MAPSReporting -eq 2) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Proteccion en la nube (MAPS)"; Valor=$maps; Color=$mapsColor })

            $samples = switch ([int]$p.SubmitSamplesConsent) {
                0 { "Preguntar siempre" }
                1 { "Enviar muestras seguras" }
                2 { "Nunca enviar" }
                3 { "Enviar siempre" }
                default { "Desconocido ($($p.SubmitSamplesConsent))" }
            }
            $samplesColor = if ([int]$p.SubmitSamplesConsent -in 1,3) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Envio de muestras"; Valor=$samples; Color=$samplesColor })
        } catch { }
    }

    # Politica
    $hasPolicy = Test-DefenderPolicyDisabled
    $polColor  = if ($hasPolicy) { $script:Colors.Bad } else { $script:Colors.Ok }
    [void]$report.Add([PSCustomObject]@{ Modulo="Politica de grupo bloqueante"; Valor=$(if($hasPolicy){"SI"}else{"NO"}); Color=$polColor })

    return $report
}

# ==================================================================
# 9. FUNCION DE ACTUALIZACION DE LA VISTA DE ESTADO COMPLETO
#    *** Ahora es de SCOPE SCRIPT con parametros ***
#    *** Esto resuelve el error Load-List ***
# ==================================================================
function Update-CompleteStatusView {
    param(
        [System.Windows.Forms.ListView]$ListView,
        [System.Windows.Forms.Label]$StatusLabel
    )
    if ($null -eq $ListView -or $ListView.IsDisposed) { return }
    if ($null -eq $StatusLabel -or $StatusLabel.IsDisposed) { return }

    Clear-StatusCache
    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        $report = Get-CompleteDefenderReport
        foreach ($row in $report) {
            $item = New-Object System.Windows.Forms.ListViewItem($row.Modulo)
            [void]$item.SubItems.Add([string]$row.Valor)
            if ($null -ne $row.Color) { $item.ForeColor = $row.Color }
            [void]$ListView.Items.Add($item)
        }
    } finally {
        $ListView.EndUpdate()
    }

    $q = Get-QuickStatus
    if ($q.IsActive) {
        $StatusLabel.Text = ">>> ESTADO GLOBAL: ACTIVADO <<<"
        $StatusLabel.ForeColor = $script:Colors.Ok
    } elseif ($q.ServiceRunning) {
        $StatusLabel.Text = ">>> ESTADO GLOBAL: PROTECCION PARCIAL <<<"
        $StatusLabel.ForeColor = $script:Colors.Warn
    } else {
        $StatusLabel.Text = ">>> ESTADO GLOBAL: DESACTIVADO <<<"
        $StatusLabel.ForeColor = $script:Colors.Bad
    }
}

# ==================================================================
# 10. DIALOGO VERIFICACION COMPLETA
# ==================================================================
function Show-CompleteStatusDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Verificacion completa - Windows Defender"
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 580)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.BtnPurple
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Estado completo de Windows Defender"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblH)

    $lblEstado = New-Object System.Windows.Forms.Label
    $lblEstado.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $lblEstado.AutoSize = $false
    $lblEstado.Size = New-Object System.Drawing.Size(590, 24)
    $lblEstado.Location = New-Object System.Drawing.Point(15, 62)
    $lblEstado.TextAlign = "MiddleLeft"
    $dlg.Controls.Add($lblEstado)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.HeaderStyle = "Nonclickable"
    $lv.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 92)
    $lv.Size = New-Object System.Drawing.Size(590, 410)
    $lv.BorderStyle = "FixedSingle"
    [void]$lv.Columns.Add("Modulo", 260)
    [void]$lv.Columns.Add("Estado", 305)
    $dlg.Controls.Add($lv)

    # Botones
    $btnRefrescar = New-Object System.Windows.Forms.Button
    $btnRefrescar.Text = "Refrescar"
    $btnRefrescar.Size = New-Object System.Drawing.Size(150, 36)
    $btnRefrescar.Location = New-Object System.Drawing.Point(15, 515)
    $btnRefrescar.FlatStyle = "Flat"; $btnRefrescar.FlatAppearance.BorderSize = 0
    $btnRefrescar.BackColor = $script:Colors.BtnPurple
    $btnRefrescar.ForeColor = [System.Drawing.Color]::White
    $btnRefrescar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefrescar.Cursor = "Hand"; $btnRefrescar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnRefrescar)

    $btnCopiar = New-Object System.Windows.Forms.Button
    $btnCopiar.Text = "Copiar al portapapeles"
    $btnCopiar.Size = New-Object System.Drawing.Size(190, 36)
    $btnCopiar.Location = New-Object System.Drawing.Point(175, 515)
    $btnCopiar.FlatStyle = "Flat"; $btnCopiar.FlatAppearance.BorderSize = 0
    $btnCopiar.BackColor = $script:Colors.BtnTeal
    $btnCopiar.ForeColor = [System.Drawing.Color]::White
    $btnCopiar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCopiar.Cursor = "Hand"; $btnCopiar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCopiar)

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text = "Cerrar"
    $btnCerrar.Size = New-Object System.Drawing.Size(150, 36)
    $btnCerrar.Location = New-Object System.Drawing.Point(455, 515)
    $btnCerrar.FlatStyle = "Flat"; $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.BackColor = $script:Colors.BtnDarkGray
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.Cursor = "Hand"; $btnCerrar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCerrar)

    # Cargar vista inicial
    Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado

    # *** Eventos usando .GetNewClosure() SOLO para capturar $lv, $lblEstado, $dlg ***
    # *** Las funciones llamadas (Update-CompleteStatusView) son de scope script ***
    $btnRefrescar.Add_Click({
        Update-CompleteStatusView -ListView $lv -StatusLabel $lblEstado
    }.GetNewClosure())

    $btnCopiar.Add_Click({
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("VERIFICACION COMPLETA - WINDOWS DEFENDER")
        [void]$sb.AppendLine(("Fecha: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)))
        [void]$sb.AppendLine("Estado: $($lblEstado.Text)")
        [void]$sb.AppendLine("----------------------------------------")
        foreach ($it in $lv.Items) {
            [void]$sb.AppendLine(("{0,-40} {1}" -f $it.Text, $it.SubItems[1].Text))
        }
        try {
            [System.Windows.Forms.Clipboard]::SetText($sb.ToString())
            [System.Windows.Forms.MessageBox]::Show("Informe copiado al portapapeles.","Copiado","OK","Information") | Out-Null
        } catch { }
    }.GetNewClosure())

    $btnCerrar.Add_Click({ $dlg.Close() }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 11. DIALOGO OPCIONES AVANZADAS
# ==================================================================
function Show-AdvancedActivationDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Opciones de activacion"
    $dlg.ClientSize = New-Object System.Drawing.Size(440, 400)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.BtnGreen
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Opciones avanzadas de activacion"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblH)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Selecciona los servicios adicionales que deseas activar:"
    $lblInfo.AutoSize = $true
    $lblInfo.ForeColor = $script:Colors.TextDiag
    $lblInfo.Location = New-Object System.Drawing.Point(15, 70)
    $dlg.Controls.Add($lblInfo)

    # Estado actual
    $cloud = -1; $samples = -1; $tamper = $false
    try {
        if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
            $p = Get-MpPreference -ErrorAction SilentlyContinue
            if ($null -ne $p) {
                if ($null -ne $p.MAPSReporting)        { $cloud   = [int]$p.MAPSReporting }
                if ($null -ne $p.SubmitSamplesConsent) { $samples = [int]$p.SubmitSamplesConsent }
            }
        }
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $tamper = [bool]$st.IsTamperProtected
        }
    } catch { }

    # Cloud
    $chkCloud = New-Object System.Windows.Forms.CheckBox
    $chkCloud.Text = "Proteccion basada en la nube (MAPS Advanced)"
    $chkCloud.Location = New-Object System.Drawing.Point(20, 100)
    $chkCloud.Size = New-Object System.Drawing.Size(400, 24)
    $chkCloud.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkCloud.ForeColor = $script:Colors.TextDiag
    if ($cloud -eq 2) {
        $chkCloud.Checked = $true; $chkCloud.Enabled = $false
        $chkCloud.Text += "   [ya activado]"
        $chkCloud.ForeColor = $script:Colors.TextMuted
    } else { $chkCloud.Checked = $true }
    $dlg.Controls.Add($chkCloud)

    $lblCloudInfo = New-Object System.Windows.Forms.Label
    $lblCloudInfo.Text = "Envia informacion a Microsoft para analisis en tiempo real."
    $lblCloudInfo.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblCloudInfo.ForeColor = $script:Colors.TextMuted
    $lblCloudInfo.Size = New-Object System.Drawing.Size(400, 15)
    $lblCloudInfo.Location = New-Object System.Drawing.Point(40, 124)
    $dlg.Controls.Add($lblCloudInfo)

    # Samples
    $chkSamples = New-Object System.Windows.Forms.CheckBox
    $chkSamples.Text = "Envio automatico de muestras (Safe samples)"
    $chkSamples.Location = New-Object System.Drawing.Point(20, 150)
    $chkSamples.Size = New-Object System.Drawing.Size(400, 24)
    $chkSamples.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkSamples.ForeColor = $script:Colors.TextDiag
    if ($samples -in 1,3) {
        $chkSamples.Checked = $true; $chkSamples.Enabled = $false
        $chkSamples.Text += "   [ya activado]"
        $chkSamples.ForeColor = $script:Colors.TextMuted
    } else { $chkSamples.Checked = $true }
    $dlg.Controls.Add($chkSamples)

    $lblSamplesInfo = New-Object System.Windows.Forms.Label
    $lblSamplesInfo.Text = "Envia muestras sospechosas a Microsoft para mejorar la deteccion."
    $lblSamplesInfo.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblSamplesInfo.ForeColor = $script:Colors.TextMuted
    $lblSamplesInfo.Size = New-Object System.Drawing.Size(400, 15)
    $lblSamplesInfo.Location = New-Object System.Drawing.Point(40, 174)
    $dlg.Controls.Add($lblSamplesInfo)

    # Tamper
    $chkTamper = New-Object System.Windows.Forms.CheckBox
    $chkTamper.Text = "Proteccion contra alteraciones (Tamper Protection)"
    $chkTamper.Location = New-Object System.Drawing.Point(20, 200)
    $chkTamper.Size = New-Object System.Drawing.Size(400, 24)
    $chkTamper.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkTamper.ForeColor = $script:Colors.TextDiag
    if ($tamper) {
        $chkTamper.Checked = $true; $chkTamper.Enabled = $false
        $chkTamper.Text += "   [ya activado]"
        $chkTamper.ForeColor = $script:Colors.TextMuted
    } else { $chkTamper.Checked = $true }
    $dlg.Controls.Add($chkTamper)

    $lblTamperInfo = New-Object System.Windows.Forms.Label
    $lblTamperInfo.Text = "Impide cambios no autorizados. Windows puede requerir activacion manual."
    $lblTamperInfo.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblTamperInfo.ForeColor = $script:Colors.TextMuted
    $lblTamperInfo.Size = New-Object System.Drawing.Size(400, 15)
    $lblTamperInfo.Location = New-Object System.Drawing.Point(40, 224)
    $dlg.Controls.Add($lblTamperInfo)

    $pInfo = New-Object System.Windows.Forms.Panel
    $pInfo.Location = New-Object System.Drawing.Point(15, 250)
    $pInfo.Size = New-Object System.Drawing.Size(410, 60)
    $pInfo.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 220)
    $pInfo.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($pInfo)

    $lblNota = New-Object System.Windows.Forms.Label
    $lblNota.Text = "NOTA: Microsoft bloquea la activacion de Tamper Protection via script." + "`n" +
                    "Si no se activa, hazlo manualmente en: Seguridad de Windows ->" + "`n" +
                    "Proteccion antivirus -> Administrar la configuracion."
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 7)
    $lblNota.ForeColor = [System.Drawing.Color]::FromArgb(150, 100, 0)
    $lblNota.Size = New-Object System.Drawing.Size(400, 55)
    $lblNota.Location = New-Object System.Drawing.Point(8, 4)
    $pInfo.Controls.Add($lblNota)

    $btnAceptar = New-Object System.Windows.Forms.Button
    $btnAceptar.Text = "Aceptar y Activar"
    $btnAceptar.Size = New-Object System.Drawing.Size(200, 40)
    $btnAceptar.Location = New-Object System.Drawing.Point(15, 325)
    $btnAceptar.FlatStyle = "Flat"; $btnAceptar.FlatAppearance.BorderSize = 0
    $btnAceptar.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGreenHover
    $btnAceptar.BackColor = $script:Colors.BtnGreen
    $btnAceptar.ForeColor = [System.Drawing.Color]::White
    $btnAceptar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnAceptar.Cursor = "Hand"; $btnAceptar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnAceptar)

    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = "Cancelar"
    $btnCancelar.Size = New-Object System.Drawing.Size(180, 40)
    $btnCancelar.Location = New-Object System.Drawing.Point(230, 325)
    $btnCancelar.FlatStyle = "Flat"; $btnCancelar.FlatAppearance.BorderSize = 0
    $btnCancelar.FlatAppearance.MouseOverBackColor = $script:Colors.BtnDarkGrayHov
    $btnCancelar.BackColor = $script:Colors.BtnDarkGray
    $btnCancelar.ForeColor = [System.Drawing.Color]::White
    $btnCancelar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.Cursor = "Hand"; $btnCancelar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCancelar)

    $script:DlgResult = [PSCustomObject]@{
        Apply = $false; EnableCloud = $false; EnableSamples = $false; EnableTamper = $false
    }

    $btnAceptar.Add_Click({
        $script:DlgResult = [PSCustomObject]@{
            Apply         = $true
            EnableCloud   = ($chkCloud.Enabled   -and $chkCloud.Checked)
            EnableSamples = ($chkSamples.Enabled -and $chkSamples.Checked)
            EnableTamper  = ($chkTamper.Enabled  -and $chkTamper.Checked)
        }
        $dlg.Close()
    }.GetNewClosure())

    $btnCancelar.Add_Click({
        $script:DlgResult = [PSCustomObject]@{
            Apply = $false; EnableCloud = $false; EnableSamples = $false; EnableTamper = $false
        }
        $dlg.Close()
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:DlgResult
}

# ==================================================================
# 12. DESACTIVAR
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA. Desactivala desde Seguridad de Windows.")
                Write-AppLog "Desactivacion bloqueada: Tamper Protection activa." "ERROR"
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Iniciando desactivacion..." "INFO"

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction SilentlyContinue
            [void]$log.Add("[1] Preferencias RTP: DESACTIVADAS")
        }
    } catch { [void]$log.Add("[1] Aviso: $($_.Exception.Message)") }

    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
            [void]$log.Add("[2] Servicio ${svcName}: DETENIDO")
        } catch { }
    }

    Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
    Set-Service  -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
    $null = & sc.exe config WinDefend start= disabled 2>&1
    $null = & sc.exe stop WinDefend 2>&1

    try {
        $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend"
        if (Test-Path $svcRegPath) {
            Set-ItemProperty -Path $svcRegPath -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
            [void]$log.Add("[3] Registro WinDefend\Start = 4")
        }
    } catch { }

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    New-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    $rtPath = Join-Path $regPath "Real-Time Protection"
    if (-not (Test-Path $rtPath)) { New-Item -Path $rtPath -Force | Out-Null }
    New-ItemProperty -Path $rtPath -Name "DisableRealtimeMonitoring" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    [void]$log.Add("[4] Politicas de registro establecidas.")

    Wait-WithDoEvents -Milliseconds 2500
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        [void]$log.Add("[5] Windows reinicio el servicio. Reintentando...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        try {
            $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend"
            Set-ItemProperty -Path $svcRegPath -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch { }
        Wait-WithDoEvents -Milliseconds 1500
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2} segundos" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog ("Desactivacion completada en {0:N2}s" -f $sw.Elapsed.TotalSeconds) "INFO"
    Clear-StatusCache
    return ($log -join "`n")
}

# ==================================================================
# 13. ACTIVAR
# ==================================================================
function Enable-Defender {
    param(
        [bool]$EnableCloud   = $false,
        [bool]$EnableSamples = $false,
        [bool]$EnableTamper  = $false
    )
    $log = New-Object System.Collections.ArrayList
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AppLog "Iniciando activacion..." "INFO"

    try {
        $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend"
        if (Test-Path $svcRegPath) {
            Set-ItemProperty -Path $svcRegPath -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            [void]$log.Add("[1] Registro WinDefend\Start = 2")
        }
    } catch { }

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            [void]$log.Add("[2] Rama de politicas eliminada.")
        } else {
            [void]$log.Add("[2] No habia politicas.")
        }
    } catch {
        Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Force -ErrorAction SilentlyContinue
        [void]$log.Add("[2] Politicas eliminadas (fallback).")
    }

    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    try {
        if (Test-Path $rtWk) {
            foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
                             "DisableOnAccessProtection","DisableScanOnRealtimeEnable",
                             "DisableIOAVProtection","DisableScriptScanning")) {
                Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue
            }
            [void]$log.Add("[3] Claves RTP limpiadas.")
        }
    } catch { }

    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Set-Service  -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
                $null = & sc.exe config $svcName start= auto 2>&1
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                [void]$log.Add("[4] Servicio ${svcName}: INICIADO")
            }
        } catch { }
    }

    try {
        Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= auto 2>&1
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("[5] Servicio WinDefend: INICIADO")
    } catch { [void]$log.Add("[5] Aviso: $($_.Exception.Message)") }

    Wait-WithDoEvents -Milliseconds 3000

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
            [void]$log.Add("[6] RTP: ACTIVADO")
        }
    } catch { }
    Wait-WithDoEvents -Milliseconds 1000
    try { Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue } catch { }

    if ($EnableCloud -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try {
            Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction Stop
            [void]$log.Add("[7] Nube (MAPS): ACTIVADO")
        } catch { [void]$log.Add("[7] Error nube: $($_.Exception.Message)") }
    } else { [void]$log.Add("[7] Nube: omitida.") }

    if ($EnableSamples -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try {
            Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction Stop
            [void]$log.Add("[8] Muestras: ACTIVADO")
        } catch { [void]$log.Add("[8] Error muestras: $($_.Exception.Message)") }
    } else { [void]$log.Add("[8] Muestras: omitido.") }

    if ($EnableTamper) {
        try {
            $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
            $writeOk = $false
            try {
                if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
                Set-ItemProperty -Path $tpPath -Name "TamperProtection"       -Value 5 -Type DWord  -Force -ErrorAction Stop
                Set-ItemProperty -Path $tpPath -Name "TamperProtectionSource" -Value 1 -Type String -Force -ErrorAction Stop
                $writeOk = $true
                [void]$log.Add("[9] Registro TamperProtection escrito.")
            } catch {
                [void]$log.Add("[9] No se pudo escribir TP: $($_.Exception.Message)")
            }
            if ($writeOk) {
                try {
                    Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
                    Wait-WithDoEvents -Milliseconds 800
                    Start-Service -Name WinDefend -ErrorAction SilentlyContinue
                } catch { }
                Wait-WithDoEvents -Milliseconds 3000
            }
            $verify = $false
            try {
                if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
                    $st = Get-MpComputerStatus -ErrorAction Stop
                    $verify = [bool]$st.IsTamperProtected
                }
            } catch { }
            if ($verify) {
                [void]$log.Add("[9] Tamper Protection: CONFIRMADO ACTIVO.")
            } else {
                [void]$log.Add("[9] Tamper Protection: RECHAZADO por Windows.")
                [void]$log.Add("     Activalo manualmente en Seguridad de Windows.")
            }
        } catch {
            [void]$log.Add("[9] Error TP: $($_.Exception.Message)")
        }
    } else { [void]$log.Add("[9] Tamper Protection: omitido.") }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2} segundos" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog ("Activacion completada en {0:N2}s" -f $sw.Elapsed.TotalSeconds) "INFO"
    Clear-StatusCache
    return ($log -join "`n")
}

# ==================================================================
# 14. ADMIN / OS / EXCLUSION
# ==================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OSInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{ Caption=$os.Caption; Version=$os.Version; BuildNumber=$os.BuildNumber }
    } catch {
        return [PSCustomObject]@{ Caption="Desconocido"; Version="Desconocido"; BuildNumber="Desconocido" }
    }
}

function Add-DefenderExclusion {
    try {
        $sp = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($sp)) { $sp = (Get-Location).Path }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $sp -Force -ErrorAction Stop
            Write-AppLog "Exclusion agregada: $sp" "INFO"
            return $true
        }
    } catch {
        Write-AppLog "Error exclusion: $($_.Exception.Message)" "ERROR"
    }
    return $false
}

# ==================================================================
# 15. BOTONES
# ==================================================================
function New-ColorButton {
    param([string]$Texto, [System.Drawing.Color]$Color, [System.Drawing.Color]$Hover, [int]$Y, [int]$Ancho = 390, [int]$Alto = 34)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Texto
    $b.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $b.Location = New-Object System.Drawing.Point(15, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Color
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = "Hand"
    $b.Tag = @{ Normal = $Color; Hover = $Hover; Habilitado = $true }
    return $b
}

function Set-ButtonVisualState {
    param([System.Windows.Forms.Button]$Boton, [bool]$Habilitado)
    if ($null -eq $Boton) { return }
    if ($Habilitado) {
        $Boton.BackColor = $Boton.Tag.Normal
        $Boton.ForeColor = [System.Drawing.Color]::White
        $Boton.FlatAppearance.MouseOverBackColor = $Boton.Tag.Hover
        $Boton.Cursor = "Hand"
        $Boton.Tag.Habilitado = $true
    } else {
        $Boton.BackColor = $script:Colors.BtnGray
        $Boton.ForeColor = $script:Colors.BtnGrayText
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGray
        $Boton.Cursor = "Default"
        $Boton.Tag.Habilitado = $false
    }
}

# ==================================================================
# 16. VISOR DE LOG
#    *** Update-LogViewContent es de SCOPE SCRIPT con parametros ***
# ==================================================================
function Update-LogViewContent {
    param([System.Windows.Forms.TextBox]$TextBox)
    if ($null -eq $TextBox -or $TextBox.IsDisposed) { return }

    if (Test-Path $script:LogFile) {
        $c = Get-Content -Path $script:LogFile -Raw -ErrorAction SilentlyContinue
        $TextBox.Text = if ([string]::IsNullOrEmpty($c)) { "(Vacio)" } else { $c }
    } else {
        $TextBox.Text = "(Sin log todavia)`r`n$($script:LogFile)"
    }
    $TextBox.SelectionStart = $TextBox.Text.Length
    $TextBox.ScrollToCaret()
}

function Show-LogViewer {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text = "Registro de Actividad - DefenderTray"
    $frm.ClientSize = New-Object System.Drawing.Size(760, 520)
    $frm.StartPosition = "CenterScreen"
    $frm.Icon = [System.Drawing.SystemIcons]::Shield
    $frm.BackColor = $script:Colors.Background
    $frm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $pHead = New-Object System.Windows.Forms.Panel
    $pHead.Dock = "Top"; $pHead.Height = 50; $pHead.BackColor = $script:Colors.BtnTeal
    $frm.Controls.Add($pHead)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Registro de Actividad"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(15, 13)
    $pHead.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ScrollBars = "Both"; $txt.ReadOnly = $true
    $txt.WordWrap = $false; $txt.Dock = "Fill"
    $txt.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 38)
    $txt.ForeColor = [System.Drawing.Color]::FromArgb(130, 230, 130)
    $txt.BorderStyle = "None"

    $pBody = New-Object System.Windows.Forms.Panel
    $pBody.Dock = "Fill"; $pBody.Padding = New-Object System.Windows.Forms.Padding(10)
    $pBody.Controls.Add($txt)
    $frm.Controls.Add($pBody); $pBody.BringToFront()

    $pBot = New-Object System.Windows.Forms.Panel
    $pBot.Dock = "Bottom"; $pBot.Height = 55; $pBot.BackColor = $script:Colors.Background
    $frm.Controls.Add($pBot)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refrescar"; $btnRefresh.Size = New-Object System.Drawing.Size(120, 34)
    $btnRefresh.Location = New-Object System.Drawing.Point(15, 10)
    $btnRefresh.FlatStyle = "Flat"; $btnRefresh.FlatAppearance.BorderSize = 0
    $btnRefresh.BackColor = $script:Colors.BtnBlue
    $btnRefresh.ForeColor = [System.Drawing.Color]::White
    $btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefresh.Cursor = "Hand"
    $pBot.Controls.Add($btnRefresh)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Guardar copia..."; $btnSave.Size = New-Object System.Drawing.Size(140, 34)
    $btnSave.Location = New-Object System.Drawing.Point(145, 10)
    $btnSave.FlatStyle = "Flat"; $btnSave.FlatAppearance.BorderSize = 0
    $btnSave.BackColor = $script:Colors.BtnGreen
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnSave.Cursor = "Hand"
    $pBot.Controls.Add($btnSave)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Abrir carpeta"; $btnOpen.Size = New-Object System.Drawing.Size(130, 34)
    $btnOpen.Location = New-Object System.Drawing.Point(295, 10)
    $btnOpen.FlatStyle = "Flat"; $btnOpen.FlatAppearance.BorderSize = 0
    $btnOpen.BackColor = $script:Colors.BtnTeal
    $btnOpen.ForeColor = [System.Drawing.Color]::White
    $btnOpen.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnOpen.Cursor = "Hand"
    $pBot.Controls.Add($btnOpen)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Cerrar"; $btnClose.Size = New-Object System.Drawing.Size(100, 34)
    $btnClose.Location = New-Object System.Drawing.Point(645, 10); $btnClose.Anchor = "Top,Right"
    $btnClose.FlatStyle = "Flat"; $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.BackColor = $script:Colors.BtnDarkGray
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnClose.Cursor = "Hand"
    $pBot.Controls.Add($btnClose)

    Update-LogViewContent -TextBox $txt

    $btnRefresh.Add_Click({
        Update-LogViewContent -TextBox $txt
    }.GetNewClosure())

    $btnSave.Add_Click({
        $sdlg = New-Object System.Windows.Forms.SaveFileDialog
        $sdlg.Filter = "Texto (*.txt)|*.txt|Todos (*.*)|*.*"
        $sdlg.FileName = "DefenderTray_Log_{0:yyyy-MM-dd_HHmmss}.txt" -f (Get-Date)
        if ($sdlg.ShowDialog() -eq "OK") {
            try {
                if (Test-Path $script:LogFile) { Copy-Item $script:LogFile $sdlg.FileName -Force }
                else { $txt.Text | Out-File $sdlg.FileName -Encoding UTF8 }
                [System.Windows.Forms.MessageBox]::Show("Guardado en:`n$($sdlg.FileName)","OK","OK","Information") | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Error","OK","Error") | Out-Null
            }
        }
    }.GetNewClosure())

    $btnOpen.Add_Click({ Start-Process "explorer.exe" -ArgumentList $script:LogFolder })
    $btnClose.Add_Click({ $frm.Close() }.GetNewClosure())

    [void]$frm.ShowDialog()
}

# ==================================================================
# 17. ESTADO GLOBAL DEL PANEL (SCOPE SCRIPT)
# ==================================================================
$script:PanelForm          = $null
$script:PanelHeader        = $null
$script:PanelLblValor      = $null
$script:PanelLblDetalle1   = $null
$script:PanelLblDetalle2   = $null
$script:PanelLblDetalle3   = $null
$script:PanelLblReloj      = $null
$script:PanelLblTimerH     = $null
$script:PanelBtnActivar    = $null
$script:PanelBtnDesactivar = $null
$script:PanelTimer         = $null
$script:IsBusy             = $false
$script:ActionStartTime    = $null
$script:ActionName         = ""
$script:LastActionTime     = 0
$script:LastActionName     = ""

# ==================================================================
# 18. ACTUALIZAR UI DEL PANEL (SCOPE SCRIPT)
# ==================================================================
function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }

    $s = Get-QuickStatus
    $diag = "Servicio:{0}  TiempoReal:{1}  Politica:{2}" -f `
        $(if($s.ServiceRunning){'ON'}else{'OFF'}), `
        $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'}), `
        $(if($s.HasPolicy){'SI'}else{'NO'})

    if ($s.IsActive) {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderOk
        $script:PanelLblDetalle1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar    -Habilitado $false
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $true
    }
    elseif ($s.ServiceRunning -and ($s.HasPolicy -or -not $s.RealTimeProtectionEnabled)) {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPartial
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderPartial
        if ($s.HasPolicy -and -not $s.RealTimeProtectionEnabled) {
            $script:PanelLblDetalle1.Text = "Politica bloquea Defender y RTP inactivo."
        } elseif ($s.HasPolicy) {
            $script:PanelLblDetalle1.Text = "Politica de grupo bloquea Defender."
        } else {
            $script:PanelLblDetalle1.Text = "Proteccion en tiempo real desactivada."
        }
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $true
    }
    else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderWarn
        $script:PanelLblDetalle1.Text = "El antivirus esta inactivo. Sin proteccion."
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar    -Habilitado $true
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $false
    }

    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDetalle3.Text = "Ultima operacion: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDetalle3.Text = "Listo para operar."
    }
}

# ==================================================================
# 19. TIMER DEL PANEL (SCOPE SCRIPT)
# ==================================================================
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
            $script:PanelLblTimerH.Text = "{0:N2}s" -f $el
        } else {
            $script:PanelLblTimerH.Text = "espera"
        }
        if (-not $script:IsBusy -and $null -eq $script:ActionStartTime) {
            try { Update-PanelStatusUI } catch { }
        }
    })
    $script:PanelTimer.Start()
}

# ==================================================================
# 20. MOSTRAR PANEL (SINGLETON)
# ==================================================================
function Show-DefenderPanel {
    # Singleton: si ya existe, traer al frente
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try {
            if ($script:PanelForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                $script:PanelForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            }
            $script:PanelForm.Show()
            $script:PanelForm.BringToFront()
            $script:PanelForm.Activate()
            $script:PanelForm.Focus()
        } catch { }
        return
    }

    # Reset
    $script:IsBusy          = $false
    $script:ActionStartTime = $null
    $script:ActionName      = ""
    $script:LastActionTime  = 0
    $script:LastActionName  = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.ClientSize      = New-Object System.Drawing.Size(420, 500)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = $script:Colors.Background
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon            = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.HeaderUnknown
    $form.Controls.Add($header)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "Windows Defender"
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true
    $lblHeader.Location = New-Object System.Drawing.Point(15, 14)
    $header.Controls.Add($lblHeader)

    $lblReloj = New-Object System.Windows.Forms.Label
    $lblReloj.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblReloj.ForeColor = [System.Drawing.Color]::FromArgb(220, 235, 220)
    $lblReloj.BackColor = [System.Drawing.Color]::Transparent
    $lblReloj.AutoSize = $false
    $lblReloj.Size = New-Object System.Drawing.Size(160, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(245, 8)
    $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)

    $lblTimerH = New-Object System.Windows.Forms.Label
    $lblTimerH.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimerH.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 120)
    $lblTimerH.BackColor = [System.Drawing.Color]::Transparent
    $lblTimerH.AutoSize = $false
    $lblTimerH.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimerH.Location = New-Object System.Drawing.Point(245, 28)
    $lblTimerH.TextAlign = "MiddleRight"
    $lblTimerH.Text = "00:00.00s"
    $header.Controls.Add($lblTimerH)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 65)
    $card.Size = New-Object System.Drawing.Size(390, 130)
    $card.BackColor = $script:Colors.CardBg
    $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)

    $lblEstadoTag = New-Object System.Windows.Forms.Label
    $lblEstadoTag.Text = "Estado actual"
    $lblEstadoTag.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEstadoTag.ForeColor = $script:Colors.TextMuted
    $lblEstadoTag.AutoSize = $true
    $lblEstadoTag.Location = New-Object System.Drawing.Point(12, 6)
    $card.Controls.Add($lblEstadoTag)

    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize = $true
    $lblValor.Location = New-Object System.Drawing.Point(12, 24)
    $card.Controls.Add($lblValor)

    $lblDetalle1 = New-Object System.Windows.Forms.Label
    $lblDetalle1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDetalle1.ForeColor = $script:Colors.TextDiag
    $lblDetalle1.AutoSize = $false
    $lblDetalle1.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle1.Location = New-Object System.Drawing.Point(12, 62)
    $card.Controls.Add($lblDetalle1)

    $lblDetalle2 = New-Object System.Windows.Forms.Label
    $lblDetalle2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDetalle2.ForeColor = $script:Colors.TextDiag
    $lblDetalle2.AutoSize = $false
    $lblDetalle2.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle2.Location = New-Object System.Drawing.Point(12, 80)
    $card.Controls.Add($lblDetalle2)

    $lblDetalle3 = New-Object System.Windows.Forms.Label
    $lblDetalle3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDetalle3.ForeColor = $script:Colors.TextMuted
    $lblDetalle3.AutoSize = $false
    $lblDetalle3.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle3.Location = New-Object System.Drawing.Point(12, 100)
    $card.Controls.Add($lblDetalle3)

    $btnVerificar  = New-ColorButton "VERIFICAR ESTADO COMPLETO" $script:Colors.BtnPurple   $script:Colors.BtnPurpleHover  205
    $btnActivar    = New-ColorButton $script:TXT_ACTIVAR        $script:Colors.BtnGreen    $script:Colors.BtnGreenHover  243
    $btnDesactivar = New-ColorButton $script:TXT_DESACTIVAR     $script:Colors.BtnRed      $script:Colors.BtnRedHover    281
    $btnLog        = New-ColorButton "Ver Registro"             $script:Colors.BtnTeal     $script:Colors.BtnTealHover   319
    $btnAcerca     = New-ColorButton "Acerca de..."             $script:Colors.BtnBlue     $script:Colors.BtnBlueHover   357
    $btnSalir      = New-ColorButton "SALIR"                    $script:Colors.BtnDarkGray $script:Colors.BtnDarkGrayHov 395

    $form.Controls.Add($btnVerificar)
    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnLog)
    $form.Controls.Add($btnAcerca)
    $form.Controls.Add($btnSalir)

    # Asignar a scope script
    $script:PanelForm          = $form
    $script:PanelHeader        = $header
    $script:PanelLblValor      = $lblValor
    $script:PanelLblDetalle1   = $lblDetalle1
    $script:PanelLblDetalle2   = $lblDetalle2
    $script:PanelLblDetalle3   = $lblDetalle3
    $script:PanelLblReloj      = $lblReloj
    $script:PanelLblTimerH     = $lblTimerH
    $script:PanelBtnActivar    = $btnActivar
    $script:PanelBtnDesactivar = $btnDesactivar

    # Eventos
    $btnVerificar.Add_Click({
        try {
            if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
                $script:PanelForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            }
            [System.Windows.Forms.Application]::DoEvents()
            Show-CompleteStatusDialog
        } finally {
            if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
                $script:PanelForm.Cursor = [System.Windows.Forms.Cursors]::Default
            }
        }
    })

    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $opts = Show-AdvancedActivationDialog
        if (-not $opts.Apply) { return }

        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:ActionName = "Activar"
            $script:PanelLblDetalle1.Text = "Activando... espere por favor."
            $script:PanelLblDetalle1.ForeColor = $script:Colors.HeaderPartial
            [System.Windows.Forms.Application]::DoEvents()

            $log = Enable-Defender -EnableCloud $opts.EnableCloud `
                                   -EnableSamples $opts.EnableSamples `
                                   -EnableTamper $opts.EnableTamper

            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:LastActionName = "Activar"
            $script:ActionStartTime = $null
            $script:IsBusy = $false

            Update-PanelStatusUI
            $s = Get-QuickStatus
            Write-AppLog ("Post-activacion: IsActive={0} Servicio={1} RTP={2} Politica={3} Tiempo={4:N2}s" -f `
                $s.IsActive, $s.ServiceRunning, $s.RealTimeProtectionEnabled, $s.HasPolicy, $elapsed) "INFO"

            if ($s.IsActive) {
                [System.Windows.Forms.MessageBox]::Show("Windows Defender ACTIVADO correctamente.`n`nTiempo: {0:N2} segundos`n`n$log" -f $elapsed,"Listo","OK","Information") | Out-Null
            } else {
                $msg = "Activacion parcial.`nTiempo: {0:N2} segundos`n`n" -f $elapsed
                $msg += "Diagnostico:`n"
                $msg += "  Servicio WinDefend: $(if($s.ServiceRunning){'CORRIENDO'}else{'DETENIDO'})`n"
                $msg += "  Tiempo real:        $(if($s.RealTimeProtectionEnabled){'ACTIVO'}else{'INACTIVO'})`n"
                $msg += "  Politica de grupo:  $(if($s.HasPolicy){'BLOQUEANDO'}else{'LIBRE'})`n`n"
                if ($s.HasPolicy) { $msg += "La politica sigue presente. Reinicia el equipo.`n" }
                $msg += "`n$log"
                [System.Windows.Forms.MessageBox]::Show($msg,"Verificacion","OK","Warning") | Out-Null
            }
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $c = [System.Windows.Forms.MessageBox]::Show(
            "Vas a DESACTIVAR Windows Defender. Continuar?","Confirmar","YesNo","Warning")
        if ($c -ne "Yes") { return }

        try {
            $script:IsBusy = $true
            $script:ActionStartTime = Get-Date
            $script:ActionName = "Desactivar"
            $script:PanelLblDetalle1.Text = "Desactivando... espere por favor."
            $script:PanelLblDetalle1.ForeColor = $script:Colors.HeaderPartial
            [System.Windows.Forms.Application]::DoEvents()

            $log = Disable-Defender

            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed
            $script:LastActionName = "Desactivar"
            $script:ActionStartTime = $null
            $script:IsBusy = $false

            Update-PanelStatusUI
            $s = Get-QuickStatus
            Write-AppLog ("Post-desactivacion: IsActive={0} Servicio={1} RTP={2} Politica={3} Tiempo={4:N2}s" -f `
                $s.IsActive, $s.ServiceRunning, $s.RealTimeProtectionEnabled, $s.HasPolicy, $elapsed) "INFO"

            if (-not $s.IsActive) {
                [System.Windows.Forms.MessageBox]::Show("Windows Defender DESACTIVADO.`n`nTiempo: {0:N2} segundos`n`n$log" -f $elapsed,"Listo","OK","Information") | Out-Null
            } else {
                $msg = "Desactivacion parcial.`nTiempo: {0:N2} segundos`n`n" -f $elapsed
                $msg += "  Servicio WinDefend: $(if($s.ServiceRunning){'AUN CORRIENDO'}else{'DETENIDO'})`n"
                $msg += "  Tiempo real:        $(if($s.RealTimeProtectionEnabled){'AUN ACTIVO'}else{'INACTIVO'})`n"
                $msg += "  Politica de grupo:  $(if($s.HasPolicy){'ESTABLECIDA'}else{'AUSENTE'})`n`n"
                if ($s.ServiceRunning) { $msg += "Windows reinicio el servicio. Reinicia el equipo.`n" }
                $msg += "`n$log"
                [System.Windows.Forms.MessageBox]::Show($msg,"Verificacion","OK","Warning") | Out-Null
            }
        } finally {
            $script:IsBusy = $false
            $script:ActionStartTime = $null
        }
    })

    $btnLog.Add_Click({ Show-LogViewer })

    $btnAcerca.Add_Click({
        $osInfo = Get-OSInfo
        $txt = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.10 (Scoping corregido)
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

------------------------------------
Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Carpeta de logs:
$($script:LogFolder)
------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($txt,"Acerca de...","OK","Information") | Out-Null
    })

    $btnSalir.Add_Click({
        if ($null -ne $script:PanelTimer) {
            try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
            $script:PanelTimer = $null
        }
        if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
            $script:PanelForm.Close()
        }
    })

    $form.Add_FormClosed({
        if ($null -ne $script:PanelTimer) {
            try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
            $script:PanelTimer = $null
        }
        $script:PanelForm = $null
    })

    $form.Add_Shown({
        Update-PanelStatusUI
        Start-PanelTimer
    })

    $form.Show()
}

# ==================================================================
# 21. ARRANQUE
# ==================================================================
Write-AppLog "====================================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v3.10" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "====================================================" "INFO"

if (Test-Admin) {
    Write-AppLog "Ejecutando como Administrador: SI" "INFO"
} else {
    Write-AppLog "Ejecutando como Administrador: NO" "WARN"
}

if (Test-Admin) { Add-DefenderExclusion | Out-Null }

$initQuick = Get-QuickStatus
if ($initQuick.IsActive) {
    $estadoInicial = "ACTIVADO"
    $detalleInicial = "El antivirus esta protegiendo el equipo."
} elseif ($initQuick.ServiceRunning) {
    $estadoInicial = "PROTECCION PARCIAL"
    $detalleInicial = "Falta proteccion real (RTP o politica)."
} else {
    $estadoInicial = "DESACTIVADO"
    $detalleInicial = "El antivirus esta inactivo."
}
Write-AppLog "Estado inicial: $estadoInicial" "INFO"

$osInfoInit = Get-OSInfo
$mensajeInicial = @"
VERIFICACION INICIAL COMPLETADA

Sistema Operativo:
  $($osInfoInit.Caption)
  Version $($osInfoInit.Version)  (Build $($osInfoInit.BuildNumber))

Estado de Windows Defender:
  >>> $estadoInicial <<<

$detalleInicial

La aplicacion se encuentra en la bandeja del sistema.
- Clic IZQUIERDO: abrir el panel (unico).
- Clic DERECHO:  ver el menu de opciones.

Registros en:
$($script:LogFolder)
"@

[System.Windows.Forms.MessageBox]::Show($mensajeInicial, "Verificacion inicial - Windows Defender", "OK", "Information") | Out-Null

# ==================================================================
# 22. BANDEJA + MENU
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

$miVerificar = New-Object System.Windows.Forms.ToolStripMenuItem
$miVerificar.Text = "Verificar estado completo"
$miVerificar.Add_Click({ Show-CompleteStatusDialog })

$miActivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miActivar.Text = "Activar Windows Defender"
$miActivar.Add_Click({
    if (-not (Test-Admin)) { [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null; return }
    $opts = Show-AdvancedActivationDialog
    if (-not $opts.Apply) { return }
    $null = Enable-Defender -EnableCloud $opts.EnableCloud `
                            -EnableSamples $opts.EnableSamples `
                            -EnableTamper $opts.EnableTamper
    $s = Get-QuickStatus
    if ($s.IsActive) {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Activado correctamente.","Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Activacion parcial.","Warning")
    }
})

$miDesactivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miDesactivar.Text = "Desactivar Windows Defender"
$miDesactivar.Add_Click({
    if (-not (Test-Admin)) { [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null; return }
    $null = Disable-Defender
    $s = Get-QuickStatus
    if (-not $s.IsActive) {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Desactivado correctamente.","Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Desactivacion parcial.","Warning")
    }
})

$miLog = New-Object System.Windows.Forms.ToolStripMenuItem
$miLog.Text = "Ver Registro"
$miLog.Add_Click({ Show-LogViewer })

$miAcerca = New-Object System.Windows.Forms.ToolStripMenuItem
$miAcerca.Text = "Acerca de..."
$miAcerca.Add_Click({
    $osInfo = Get-OSInfo
    $txt = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.10
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Logs: $($script:LogFolder)
"@
    [System.Windows.Forms.MessageBox]::Show($txt,"Acerca de...","OK","Information") | Out-Null
})

$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    Write-AppLog "Aplicacion cerrada." "INFO"
    if ($null -ne $script:PanelTimer) {
        try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }
        $script:PanelTimer = $null
    }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) {
        try { $script:PanelForm.Close() } catch { }
    }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add($miVerificar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miLog)
[void]$menu.Items.Add($miAcerca)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

$menu.Add_Opening({
    $s = Get-QuickStatus
    if ($s.IsActive) {
        $miActivar.Enabled    = $false
        $miDesactivar.Enabled = $true
    } else {
        $miActivar.Enabled    = $true
        $miDesactivar.Enabled = $false
    }
})

$script:notifyIcon.ContextMenuStrip = $menu

$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

$script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estadoInicial", "Info")

# ==================================================================
# 23. LOOP PRINCIPAL
# ==================================================================
[System.Windows.Forms.Application]::Run()