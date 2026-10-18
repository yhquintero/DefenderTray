<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    Version 3.12 - Sistema de ayuda en tiempo real + mejoras profesionales.
    - Tooltips en todos los controles
    - Barra de estado con ayuda contextual
    - Ayuda F1 con pestanas tematicas
    - Asistente de primera ejecucion
    - Auto-inicio con Windows
    - Atajos de teclado (F1, F5, Ctrl+R, Esc)
.NOTES
    Ejecutar como Administrador.
    Creado por: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
    Version: 3.12
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================================================================
# 2. ARGUMENTOS Y RUTA DEL SCRIPT
# ==================================================================
$script:SilentMode = $false
if ($args -contains "-silent") { $script:SilentMode = $true }

$script:ScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
    $script:ScriptPath = $MyInvocation.MyCommand.Path
}

# ==================================================================
# 3. TEXTOS ASCII
# ==================================================================
$script:O_ACCENT       = [char]0x00D3
$script:TXT_PROTECCION = "PROTECCI" + $script:O_ACCENT + "N"
$script:TXT_ACTIVAR    = "ACTIVAR " + $script:TXT_PROTECCION
$script:TXT_DESACTIVAR = "DESACTIVAR " + $script:TXT_PROTECCION

# ==================================================================
# 4. LOG
# ==================================================================
$script:LogFolder = Join-Path $env:LOCALAPPDATA "DefenderTray\Logs"
$script:LogFile   = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))
$script:CsvFile   = Join-Path $script:LogFolder ("DefenderTray_Eventos_{0:yyyy-MM-dd}.csv" -f (Get-Date))
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
# 5. HISTORIAL
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
    } catch { }
}

# ==================================================================
# 6. ESPERA NO BLOQUEANTE
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
function Get-LightPalette {
    return @{
        HeaderOk=[System.Drawing.Color]::FromArgb(34,139,34); HeaderWarn=[System.Drawing.Color]::FromArgb(178,34,34)
        HeaderPartial=[System.Drawing.Color]::FromArgb(200,130,0); HeaderUnknown=[System.Drawing.Color]::FromArgb(70,70,70)
        Background=[System.Drawing.Color]::FromArgb(245,247,250); CardBg=[System.Drawing.Color]::White
        TextMuted=[System.Drawing.Color]::FromArgb(108,117,125); TextDiag=[System.Drawing.Color]::FromArgb(80,80,80)
        BtnGreen=[System.Drawing.Color]::FromArgb(40,167,69); BtnGreenHover=[System.Drawing.Color]::FromArgb(33,136,56)
        BtnRed=[System.Drawing.Color]::FromArgb(220,53,69); BtnRedHover=[System.Drawing.Color]::FromArgb(178,40,54)
        BtnGray=[System.Drawing.Color]::FromArgb(210,210,210); BtnGrayText=[System.Drawing.Color]::FromArgb(130,130,130)
        BtnBlue=[System.Drawing.Color]::FromArgb(0,123,255); BtnBlueHover=[System.Drawing.Color]::FromArgb(0,98,204)
        BtnDarkGray=[System.Drawing.Color]::FromArgb(108,117,125); BtnDarkGrayHov=[System.Drawing.Color]::FromArgb(84,91,98)
        BtnTeal=[System.Drawing.Color]::FromArgb(23,162,184); BtnTealHover=[System.Drawing.Color]::FromArgb(17,122,139)
        BtnPurple=[System.Drawing.Color]::FromArgb(111,66,193); BtnPurpleHover=[System.Drawing.Color]::FromArgb(90,52,158)
        Ok=[System.Drawing.Color]::FromArgb(34,139,34); Bad=[System.Drawing.Color]::FromArgb(200,40,40)
        Warn=[System.Drawing.Color]::FromArgb(200,130,0); Neutral=[System.Drawing.Color]::FromArgb(90,90,90)
        StatusBg=[System.Drawing.Color]::FromArgb(230,235,240)
    }
}
function Get-DarkPalette {
    return @{
        HeaderOk=[System.Drawing.Color]::FromArgb(30,120,30); HeaderWarn=[System.Drawing.Color]::FromArgb(140,30,30)
        HeaderPartial=[System.Drawing.Color]::FromArgb(150,100,0); HeaderUnknown=[System.Drawing.Color]::FromArgb(40,40,40)
        Background=[System.Drawing.Color]::FromArgb(30,30,30); CardBg=[System.Drawing.Color]::FromArgb(45,45,45)
        TextMuted=[System.Drawing.Color]::FromArgb(180,180,180); TextDiag=[System.Drawing.Color]::FromArgb(210,210,210)
        BtnGreen=[System.Drawing.Color]::FromArgb(30,130,60); BtnGreenHover=[System.Drawing.Color]::FromArgb(25,100,45)
        BtnRed=[System.Drawing.Color]::FromArgb(180,45,55); BtnRedHover=[System.Drawing.Color]::FromArgb(140,35,45)
        BtnGray=[System.Drawing.Color]::FromArgb(70,70,70); BtnGrayText=[System.Drawing.Color]::FromArgb(150,150,150)
        BtnBlue=[System.Drawing.Color]::FromArgb(0,100,200); BtnBlueHover=[System.Drawing.Color]::FromArgb(0,80,170)
        BtnDarkGray=[System.Drawing.Color]::FromArgb(70,70,70); BtnDarkGrayHov=[System.Drawing.Color]::FromArgb(95,95,95)
        BtnTeal=[System.Drawing.Color]::FromArgb(18,130,150); BtnTealHover=[System.Drawing.Color]::FromArgb(14,105,120)
        BtnPurple=[System.Drawing.Color]::FromArgb(90,55,155); BtnPurpleHover=[System.Drawing.Color]::FromArgb(70,42,125)
        Ok=[System.Drawing.Color]::FromArgb(80,200,80); Bad=[System.Drawing.Color]::FromArgb(230,80,80)
        Warn=[System.Drawing.Color]::FromArgb(230,180,50); Neutral=[System.Drawing.Color]::FromArgb(170,170,170)
        StatusBg=[System.Drawing.Color]::FromArgb(50,50,50)
    }
}

$script:DarkTheme = $false
try {
    $regTheme = Get-ItemProperty -Path "HKCU:\Software\DefenderTray" -Name "DarkTheme" -ErrorAction SilentlyContinue
    if ($null -ne $regTheme) { $script:DarkTheme = [bool]$regTheme.DarkTheme }
} catch { }

function Get-PreferredPalette { if ($script:DarkTheme) { return Get-DarkPalette }; return Get-LightPalette }
$script:Colors = Get-PreferredPalette

# ==================================================================
# 8. ESTADO RAPIDO
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
                foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                                 "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
                    if ($null -ne $rtProps.$n -and [int]$rtProps.$n -eq 1) { return $true }
                }
            }
        }
    } catch { }
    return $false
}
function Test-RTPDisabled {
    $paths = @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
               "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection")
    foreach ($p in $paths) {
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
    $estado = "UNKNOWN"
    if ($isActive) { $estado = "ACTIVO" } elseif (-not $running) { $estado = "DESACTIVADO" } else { $estado = "PARCIAL" }
    return [PSCustomObject]@{ ServiceRunning=$running; RealTimeProtectionEnabled=-not $rtpDisabled; HasPolicy=$hasPolicy; IsActive=$isActive; Estado=$estado }
}

# ==================================================================
# 9. CACHE
# ==================================================================
$script:CachedFullStatus = $null
$script:CachedFullStatusTime = [DateTime]::MinValue
function Clear-StatusCache { $script:CachedFullStatus = $null; $script:CachedFullStatusTime = [DateTime]::MinValue }

# ==================================================================
# 10. INFORME COMPLETO
# ==================================================================
function Get-SafeProp { param($Obj,[string]$Name); try { $v = $Obj.$Name; if ($null -eq $v) { return "(no disponible)" }; return $v } catch { return "(no disponible)" } }
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
            [void]$report.Add([PSCustomObject]@{ Modulo="Monitor de comportamiento"; Valor=(Get-SafeProp $st "BehaviorMonitorEnabled"); Color=(Get-ColorForBool $st.BehaviorMonitorEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="IOAV Protection"; Valor=(Get-SafeProp $st "IoavProtectionEnabled"); Color=(Get-ColorForBool $st.IoavProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="On-Access Protection"; Valor=(Get-SafeProp $st "OnAccessProtectionEnabled"); Color=(Get-ColorForBool $st.OnAccessProtectionEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Inspeccion de red (NIS)"; Valor=(Get-SafeProp $st "NISEnabled"); Color=(Get-ColorForBool $st.NISEnabled) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Tamper Protection"; Valor=(Get-SafeProp $st "IsTamperProtected"); Color=(Get-ColorForBool $st.IsTamperProtected) })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version del motor"; Valor=(Get-SafeProp $st "AMEngineVersion"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Version de firma"; Valor=(Get-SafeProp $st "AntivirusSignatureVersion"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Edad de firma (dias)"; Valor=(Get-SafeProp $st "AntivirusSignatureAge"); Color=$null })
            [void]$report.Add([PSCustomObject]@{ Modulo="Firma actualizada"; Valor=(Get-SafeProp $st "AntivirusSignatureLastUpdated"); Color=$null })
        } catch {
            [void]$report.Add([PSCustomObject]@{ Modulo="Get-MpComputerStatus"; Valor="ERROR: $($_.Exception.Message)"; Color=$script:Colors.Bad })
        }
    }
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        try {
            $p = Get-MpPreference -ErrorAction Stop
            $maps = switch ([int]$p.MAPSReporting) { 0 {"Desactivado"} 1 {"Basico"} 2 {"Avanzado"} default {"Desconocido"} }
            $mapsColor = if ([int]$p.MAPSReporting -eq 2) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Proteccion en la nube (MAPS)"; Valor=$maps; Color=$mapsColor })
            $samples = switch ([int]$p.SubmitSamplesConsent) { 0 {"Preguntar siempre"} 1 {"Enviar muestras seguras"} 2 {"Nunca enviar"} 3 {"Enviar siempre"} default {"Desconocido"} }
            $samplesColor = if ([int]$p.SubmitSamplesConsent -in 1,3) { $script:Colors.Ok } else { $script:Colors.Warn }
            [void]$report.Add([PSCustomObject]@{ Modulo="Envio de muestras"; Valor=$samples; Color=$samplesColor })
        } catch { }
    }
    $hasPolicy = Test-DefenderPolicyDisabled
    $polColor  = if ($hasPolicy) { $script:Colors.Bad } else { $script:Colors.Ok }
    [void]$report.Add([PSCustomObject]@{ Modulo="Politica de grupo bloqueante"; Valor=$(if($hasPolicy){"SI"}else{"NO"}); Color=$polColor })
    return $report
}

# ==================================================================
# 11. VISTA COMPLETA
# ==================================================================
function Update-CompleteStatusView {
    param([System.Windows.Forms.ListView]$ListView, [System.Windows.Forms.Label]$StatusLabel)
    if ($null -eq $ListView -or $ListView.IsDisposed) { return }
    if ($null -eq $StatusLabel -or $StatusLabel.IsDisposed) { return }
    Clear-StatusCache
    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        foreach ($row in (Get-CompleteDefenderReport)) {
            $item = New-Object System.Windows.Forms.ListViewItem($row.Modulo)
            [void]$item.SubItems.Add([string]$row.Valor)
            if ($null -ne $row.Color) { $item.ForeColor = $row.Color }
            [void]$ListView.Items.Add($item)
        }
    } finally { $ListView.EndUpdate() }
    $q = Get-QuickStatus
    if ($q.Estado -eq "ACTIVO") { $StatusLabel.Text = ">>> ESTADO GLOBAL: ACTIVADO <<<"; $StatusLabel.ForeColor = $script:Colors.Ok }
    elseif ($q.Estado -eq "PARCIAL") { $StatusLabel.Text = ">>> ESTADO GLOBAL: PROTECCION PARCIAL <<<"; $StatusLabel.ForeColor = $script:Colors.Warn }
    else { $StatusLabel.Text = ">>> ESTADO GLOBAL: DESACTIVADO <<<"; $StatusLabel.ForeColor = $script:Colors.Bad }
}

# ==================================================================
# 12. AYUDA CONTEXTUAL (BARRA DE ESTADO)
# ==================================================================
function Get-ContextualHelpText {
    $s = Get-QuickStatus
    switch ($s.Estado) {
        "ACTIVO"      { return "[ACTIVADO] El antivirus esta protegiendo el equipo. Puedes desactivarlo, verificar sus modulos o ajustar preferencias." }
        "PARCIAL"     { return "[PARCIAL] El servicio corre pero falta proteccion real. Pulsa DESACTIVAR para corregir o VERIFICAR ESTADO COMPLETO para ver el diagnostico." }
        "DESACTIVADO" { return "[DESACTIVADO] El antivirus esta inactivo. Pulsa ACTIVAR para restaurar la proteccion del equipo." }
        default       { return "[DESCONOCIDO] No se pudo consultar el estado. Pulsa VERIFICAR ESTADO COMPLETO." }
    }
}

function Update-ContextualHelp {
    if ($null -eq $script:StatusLabel -or $script:StatusLabel.IsDisposed) { return }
    try {
        $script:StatusLabel.Text = Get-ContextualHelpText
        $script:StatusLabel.ForeColor = $script:Colors.TextDiag
    } catch { }
}

# ==================================================================
# 13. TOOLTIPS
# ==================================================================
$script:MainToolTip = New-Object System.Windows.Forms.ToolTip
$script:MainToolTip.AutoPopDelay = 10000
$script:MainToolTip.InitialDelay = 400
$script:MainToolTip.ReshowDelay = 100
$script:MainToolTip.ShowAlways = $true
$script:MainToolTip.IsBalloon = $false

function Set-HelpOnControl {
    param(
        [System.Windows.Forms.Control]$Control,
        [string]$ToolTip,
        [string]$StatusText
    )
    if ($null -eq $Control) { return }
    try { $script:MainToolTip.SetToolTip($Control, $ToolTip) } catch { }
    if (-not [string]::IsNullOrEmpty($StatusText)) {
        $Control.Add_MouseEnter({
            if ($null -ne $script:StatusLabel -and -not $script:StatusLabel.IsDisposed) {
                $script:StatusLabel.Text = $StatusText
                $script:StatusLabel.ForeColor = $script:Colors.BtnBlue
            }
        }.GetNewClosure())
        $Control.Add_MouseLeave({ Update-ContextualHelp })
    }
}

# ==================================================================
# 14. DIÁLOGO DE AYUDA (F1)
# ==================================================================
function Show-HelpDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ayuda - Control de Seguridad de Windows"
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 580)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55
    $header.BackColor = $script:Colors.BtnBlue
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Ayuda - Como usar esta aplicacion"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblH)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"
    $tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Controls.Add($tabs)

    # Tab 1: Introduccion
    $tab1 = New-Object System.Windows.Forms.TabPage
    $tab1.Text = "Introduccion"; $tab1.BackColor = $script:Colors.Background; $tab1.Padding = New-Object System.Windows.Forms.Padding(15)
    $txt1 = New-Object System.Windows.Forms.TextBox
    $txt1.Multiline = $true; $txt1.ReadOnly = $true; $txt1.ScrollBars = "Vertical"
    $txt1.Dock = "Fill"; $txt1.BorderStyle = "None"
    $txt1.BackColor = $script:Colors.Background; $txt1.ForeColor = $script:Colors.TextDiag
    $txt1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txt1.Text = @"
QUE HACE ESTA APLICACION
=========================

Esta aplicacion te permite ACTIVAR o DESACTIVAR Windows Defender
desde la bandeja del sistema, con un panel de control visual
y opciones avanzadas. Ademas:

- Muestra el estado en tiempo real de 18 modulos de Defender.
- Detecta la Proteccion contra alteraciones (Tamper Protection).
- Agrega exclusiones para que Defender no bloquee este script.
- Guarda un log detallado de todas las operaciones.
- Expone un historial exportable a CSV.

COMO SE USA
===========

1. La aplicacion vive en la BANDEJA DEL SISTEMA (junto al reloj).
2. Clic IZQUIERDO en el icono  ->  abre el panel de control.
3. Clic DERECHO en el icono    ->  abre el menu contextual.
4. Dentro del panel, cada boton tiene un tooltip al pasar el mouse.
5. La BARRA DE ESTADO del pie te indica que hacer segun el estado.

REQUISITOS
==========

- Debe ejecutarse como Administrador (para poder modificar
  servicios y registro de Windows).
- Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).

SOBRE EL AUTOR
==============

Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

Version 3.12 - 2026
"@
    $tab1.Controls.Add($txt1)
    [void]$tabs.TabPages.Add($tab1)

    # Tab 2: Estados
    $tab2 = New-Object System.Windows.Forms.TabPage
    $tab2.Text = "Estados"; $tab2.BackColor = $script:Colors.Background; $tab2.Padding = New-Object System.Windows.Forms.Padding(15)
    $txt2 = New-Object System.Windows.Forms.TextBox
    $txt2.Multiline = $true; $txt2.ReadOnly = $true; $txt2.ScrollBars = "Vertical"
    $txt2.Dock = "Fill"; $txt2.BorderStyle = "None"
    $txt2.BackColor = $script:Colors.Background; $txt2.ForeColor = $script:Colors.TextDiag
    $txt2.Text = @"
QUE SIGNIFICAN LOS ESTADOS
==========================

[VERDE] ACTIVADO
----------------
Windows Defender esta protegiendo el equipo al 100%:
- Servicio WinDefend corriendo.
- Proteccion en tiempo real habilitada.
- Sin politicas de grupo que lo bloqueen.

Acciones disponibles: DESACTIVAR, VERIFICAR, VER HISTORIAL.

[NARANJA] PROTECCION PARCIAL
----------------------------
Windows cree que Defender esta "activo" pero en realidad
algun modulo importante no funciona. Causas comunes:
- El servicio esta corriendo pero la proteccion en tiempo real
  esta desactivada (por una politica de grupo).
- Una directiva fuerza el arranque del servicio pero bloquea
  las protecciones internas.

Recomendacion: pulsa DESACTIVAR y luego reinicia el equipo.

[ROJO] DESACTIVADO
------------------
Windows Defender esta completamente inactivo.
- Servicio WinDefend detenido.
- Proteccion en tiempo real desactivada.
- Politicas de bloqueo presentes.

Acciones disponibles: ACTIVAR, VERIFICAR.

[GRIS] DESCONOCIDO
------------------
No se pudo consultar el estado. Suele ocurrir si:
- El sistema esta en un estado transitorio.
- WMI no responde (raro).
Pulsa VERIFICAR ESTADO COMPLETO para reintentar.
"@
    $tab2.Controls.Add($txt2)
    [void]$tabs.TabPages.Add($tab2)

    # Tab 3: Acciones
    $tab3 = New-Object System.Windows.Forms.TabPage
    $tab3.Text = "Acciones"; $tab3.BackColor = $script:Colors.Background; $tab3.Padding = New-Object System.Windows.Forms.Padding(15)
    $txt3 = New-Object System.Windows.Forms.TextBox
    $txt3.Multiline = $true; $txt3.ReadOnly = $true; $txt3.ScrollBars = "Vertical"
    $txt3.Dock = "Fill"; $txt3.BorderStyle = "None"
    $txt3.BackColor = $script:Colors.Background; $txt3.ForeColor = $script:Colors.TextDiag
    $txt3.Text = @"
BOTONES DEL PANEL
=================

[VERIFICAR ESTADO COMPLETO]  (Morado)
-------------------------------------
Abre un panel con la lista detallada de los 18 modulos de
Windows Defender, incluyendo:
- Servicio WinDefend y servicios auxiliares.
- Proteccion en tiempo real, comportamiento, IOAV, NIS.
- Tamper Protection.
- Version y antiguedad de las firmas.
- Estado de la nube (MAPS) y envio de muestras.
- Politicas de grupo bloqueantes.

Desde ese panel puedes COPIAR el informe al portapapeles.

[ACTIVAR PROTECCION]  (Verde)
-----------------------------
Restaura Windows Defender:
1. Elimina las politicas de bloqueo.
2. Reinicia los servicios WdNisSvc, Sense y WinDefend.
3. Reactiva la proteccion en tiempo real.
4. Abre un dialogo con opciones avanzadas (opcionales):
   - Proteccion basada en la nube (MAPS Advanced).
   - Envio automatico de muestras.
   - Proteccion contra alteraciones (Tamper).

[DESACTIVAR PROTECCION]  (Rojo)
-------------------------------
Desactiva Windows Defender por completo usando un metodo
agresivo de 7 pasos:
1. Desactiva 10 preferencias de proteccion.
2. Borra politicas de grupo con reg delete /f (4 rutas).
3. Recrea politicas de bloqueo permanentes.
4. Detiene y deshabilita 7 servicios con sc config.
5. Escribe Start=4 en el registro de 6 servicios.
6. Espera 5 segundos y verifica.
7. Reintenta si Windows reinicio el servicio.

En Windows 11 puede requerir REINICIO para aplicar al 100%.

[VER HISTORIAL]  (Azul)
-----------------------
Muestra las ultimas 20 operaciones con hora, accion, resultado
y duracion. Puedes abrir el CSV del dia desde ahi.

[VER REGISTRO]  (Turquesa)
--------------------------
Abre el log completo en formato consola.
Botones disponibles: Refrescar, Guardar TXT, Exportar CSV,
Abrir carpeta, Cerrar.

[ACERCA DE]  (Gris oscuro)
--------------------------
Informacion del autor y del sistema operativo.

[SALIR]  (Gris oscuro)
----------------------
Cierra la aplicacion. El icono desaparece de la bandeja.
"@
    $tab3.Controls.Add($txt3)
    [void]$tabs.TabPages.Add($tab3)

    # Tab 4: Atajos
    $tab4 = New-Object System.Windows.Forms.TabPage
    $tab4.Text = "Atajos"; $tab4.BackColor = $script:Colors.Background; $tab4.Padding = New-Object System.Windows.Forms.Padding(15)
    $txt4 = New-Object System.Windows.Forms.TextBox
    $txt4.Multiline = $true; $txt4.ReadOnly = $true; $txt4.ScrollBars = "Vertical"
    $txt4.Dock = "Fill"; $txt4.BorderStyle = "None"
    $txt4.BackColor = $script:Colors.Background; $txt4.ForeColor = $script:Colors.TextDiag
    $txt4.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txt4.Text = @"
ATAJOS DE TECLADO
=================

F1              Abre esta ventana de ayuda.
F5              Refresca el estado actual.
Ctrl+R          Refresca el estado actual (alternativo).
Esc             Cierra el panel principal.
Tab             Navega entre los botones.
Enter / Space   Pulsa el boton seleccionado.

MOUSE
=====

Clic izquierdo en icono de bandeja
                Abre el panel de control (si ya esta abierto,
                lo trae al frente).
Clic derecho en icono de bandeja
                Abre el menu contextual con todas las acciones.
Hover sobre boton
                Muestra el tooltip y actualiza la barra de estado
                del pie con informacion detallada.

DENTRO DEL PANEL
================

- La barra de estado del pie muestra ayuda contextual
  que cambia segun el estado actual.
- Al pasar el mouse sobre cualquier boton, la barra cambia
  para explicar que hace ese boton.
- El reloj de la cabecera muestra la hora actual.
- El cronometro (debajo del reloj) muestra el tiempo
  transcurrido durante una operacion.
"@
    $tab4.Controls.Add($txt4)
    [void]$tabs.TabPages.Add($tab4)

    # Tab 5: Solucion de problemas
    $tab5 = New-Object System.Windows.Forms.TabPage
    $tab5.Text = "Problemas"; $tab5.BackColor = $script:Colors.Background; $tab5.Padding = New-Object System.Windows.Forms.Padding(15)
    $txt5 = New-Object System.Windows.Forms.TextBox
    $txt5.Multiline = $true; $txt5.ReadOnly = $true; $txt5.ScrollBars = "Vertical"
    $txt5.Dock = "Fill"; $txt5.BorderStyle = "None"
    $txt5.BackColor = $script:Colors.Background; $txt5.ForeColor = $script:Colors.TextDiag
    $txt5.Text = @"
SOLUCION DE PROBLEMAS
=====================

"NO SE PUEDE DESACTIVAR - TAMPER PROTECTION ACTIVA"
----------------------------------------------------
Windows bloquea por diseno cualquier cambio si la Proteccion
contra alteraciones esta activa. Debes:
1. Abrir Seguridad de Windows.
2. Ir a "Proteccion antivirus y contra amenazas".
3. Entrar en "Administrar la configuracion".
4. Desactivar "Proteccion contra alteraciones".
5. Volver a intentar la desactivacion.

"DESACTIVACION SOLO PARCIAL"
----------------------------
Windows 11 reinicia el servicio WinDefend automaticamente
en algunos casos. Soluciones:
1. Pulsa DESACTIVAR y espera 10 segundos.
2. Si sigue en PARCIAL, REINICIA EL EQUIPO.
3. Al reiniciar, Windows leera Start=4 del registro y no
   arrancara el servicio.

"NO SE PUEDE ACTIVAR - PROTECCION PARCIAL PERSISTENTE"
-------------------------------------------------------
1. Pulsa VERIFICAR ESTADO COMPLETO.
2. Si el diagnostico muestra "Politica: SI", pulsa DESACTIVAR
   y luego ACTIVAR.
3. Si persiste, reinicia el equipo y vuelve a intentarlo.

"EL ICONO DESAPARECIO DE LA BANDEJA"
-------------------------------------
Windows oculta iconos por defecto. Solucion:
1. Clic en la flecha "^" junto al reloj.
2. Arrastra el icono de escudo fuera de la carpeta.
O bien:
1. Configuracion -> Personalizacion -> Barra de tareas.
2. "Seleccionar los iconos que aparecen en la barra".
3. Activa el icono de "Control de Seguridad de Windows".

"NO RESPONDE A CLIC"
---------------------
La aplicacion debe ejecutarse como Administrador para hacer
cambios. Si solo la ejecutaste como usuario normal:
1. Cierra el script actual (Salir en el menu).
2. Clic derecho en el .ps1 -> Ejecutar como administrador.
O crea un acceso directo con "Ejecutar como administrador".
"@
    $tab5.Controls.Add($txt5)
    [void]$tabs.TabPages.Add($tab5)

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text = "Cerrar (Esc)"
    $btnCerrar.Size = New-Object System.Drawing.Size(150, 36)
    $btnCerrar.Location = New-Object System.Drawing.Point(555, 528)
    $btnCerrar.Anchor = "Bottom,Right"
    $btnCerrar.FlatStyle = "Flat"; $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.BackColor = $script:Colors.BtnDarkGray
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.Cursor = "Hand"; $btnCerrar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCerrar)
    $btnCerrar.BringToFront()

    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close() }
    }.GetNewClosure())
    $btnCerrar.Add_Click({ $dlg.Close() }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 15. ASISTENTE DE PRIMERA EJECUCION
# ==================================================================
function Test-FirstRun {
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\DefenderTray" -Name "FirstRunDone" -ErrorAction SilentlyContinue
        if ($null -ne $reg -and [int]$reg.FirstRunDone -eq 1) { return $false }
    } catch { }
    return $true
}
function Set-FirstRunDone {
    try {
        if (-not (Test-Path "HKCU:\Software\DefenderTray")) {
            New-Item -Path "HKCU:\Software\DefenderTray" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\DefenderTray" -Name "FirstRunDone" -Value 1 -Type DWord -Force
    } catch { }
}
function Show-FirstRunWizard {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Bienvenido - Control de Seguridad de Windows"
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 440)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 70
    $header.BackColor = $script:Colors.BtnGreen
    $dlg.Controls.Add($header)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Bienvenido"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White
    $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true
    $lblH.Location = New-Object System.Drawing.Point(20, 10)
    $header.Controls.Add($lblH)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Control de Seguridad de Windows Defender"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(220, 240, 220)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(22, 40)
    $header.Controls.Add($lblSub)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = "Vertical"
    $txt.Location = New-Object System.Drawing.Point(20, 85)
    $txt.Size = New-Object System.Drawing.Size(520, 290)
    $txt.BorderStyle = "FixedSingle"
    $txt.BackColor = $script:Colors.CardBg; $txt.ForeColor = $script:Colors.TextDiag
    $txt.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txt.Text = @"
Esta es la primera vez que ejecutas la aplicacion. Aqui tienes
una guia rapida de como usarla.

QUE HACE
========
Permite ACTIVAR o DESACTIVAR Windows Defender desde la
bandeja del sistema (junto al reloj), con un panel visual.

DONDE ESTA
==========
Busca el icono de ESCUDO junto al reloj. Si no lo ves,
pulsa la flecha "^" para ver los iconos ocultos.

COMO SE USA
===========
  * Clic IZQUIERDO en el icono  ->  abre el panel de control.
  * Clic DERECHO en el icono    ->  abre el menu contextual.
  * Dentro del panel, cada boton tiene un tooltip al pasar
    el mouse. La barra de estado del pie explica que hace
    cada boton.

ATAJOS
======
  * F1  ->  Abre la ventana de ayuda completa.
  * F5  ->  Refresca el estado.
  * Esc ->  Cierra el panel.

RECOMENDACIONES
===============
  * Ejecuta siempre como Administrador (ya lo estas).
  * Antes de DESACTIVAR, crea un punto de restauracion.
  * Si la desactivacion queda parcial, reinicia el equipo.
  * Revisa el historial (menu contextual) para ver que
    operaciones se han hecho.

Para mas informacion, pulsa el boton "Ayuda (F1)" dentro
del panel o presiona F1 en cualquier momento.
"@
    $dlg.Controls.Add($txt)

    $chkNoShow = New-Object System.Windows.Forms.CheckBox
    $chkNoShow.Text = "No volver a mostrar este mensaje"
    $chkNoShow.Checked = $true
    $chkNoShow.Location = New-Object System.Drawing.Point(20, 385)
    $chkNoShow.Size = New-Object System.Drawing.Size(280, 22)
    $chkNoShow.ForeColor = $script:Colors.TextDiag
    $dlg.Controls.Add($chkNoShow)

    $btnEntendido = New-Object System.Windows.Forms.Button
    $btnEntendido.Text = "Entendido"
    $btnEntendido.Size = New-Object System.Drawing.Size(140, 34)
    $btnEntendido.Location = New-Object System.Drawing.Point(400, 380)
    $btnEntendido.FlatStyle = "Flat"; $btnEntendido.FlatAppearance.BorderSize = 0
    $btnEntendido.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGreenHover
    $btnEntendido.BackColor = $script:Colors.BtnGreen
    $btnEntendido.ForeColor = [System.Drawing.Color]::White
    $btnEntendido.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnEntendido.Cursor = "Hand"; $btnEntendido.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnEntendido)

    $btnAyudaCompleta = New-Object System.Windows.Forms.Button
    $btnAyudaCompleta.Text = "Ver ayuda completa"
    $btnAyudaCompleta.Size = New-Object System.Drawing.Size(180, 34)
    $btnAyudaCompleta.Location = New-Object System.Drawing.Point(210, 380)
    $btnAyudaCompleta.FlatStyle = "Flat"; $btnAyudaCompleta.FlatAppearance.BorderSize = 0
    $btnAyudaCompleta.BackColor = $script:Colors.BtnBlue
    $btnAyudaCompleta.ForeColor = [System.Drawing.Color]::White
    $btnAyudaCompleta.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnAyudaCompleta.Cursor = "Hand"; $btnAyudaCompleta.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnAyudaCompleta)

    $btnEntendido.Add_Click({
        if ($chkNoShow.Checked) { Set-FirstRunDone }
        $dlg.Close()
    }.GetNewClosure())
    $btnAyudaCompleta.Add_Click({
        if ($chkNoShow.Checked) { Set-FirstRunDone }
        Show-HelpDialog
        $dlg.Close()
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 16. AUTOSTART
# ==================================================================
function Get-AutoStartEnabled {
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        $v = Get-ItemProperty -Path $runKey -Name "DefenderTray" -ErrorAction SilentlyContinue
        return ($null -ne $v)
    } catch { return $false }
}
function Set-AutoStart {
    param([bool]$Enable)
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        if ($Enable) {
            if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
                return $false
            }
            $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:ScriptPath)`""
            Set-ItemProperty -Path $runKey -Name "DefenderTray" -Value $cmd -Force
            Write-AppLog "Autostart habilitado." "INFO"
            return $true
        } else {
            Remove-ItemProperty -Path $runKey -Name "DefenderTray" -Force -ErrorAction SilentlyContinue
            Write-AppLog "Autostart deshabilitado." "INFO"
            return $true
        }
    } catch {
        Write-AppLog "Error autostart: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ==================================================================
# 17. DESACTIVAR (AGRESSIVO)
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tp = Get-MpComputerStatus -ErrorAction Stop
            if ($tp.IsTamperProtected) {
                [void]$log.Add("ERROR: Tamper Protection ACTIVA.")
                [void]$log.Add("Desactivala en: Seguridad de Windows > Proteccion antivirus > Administrar la configuracion.")
                Write-AppLog "Desactivacion bloqueada: Tamper activo." "ERROR"
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Iniciando desactivacion AGRESIVA..." "INFO"

    [void]$log.Add("[1] Desactivando preferencias de proteccion...")
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            $prefs = @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableIOAVProtection",
                       "DisableScriptScanning","DisableBlockAtFirstSeen","DisableArchiveScanning",
                       "DisableEmailScanning","DisableIntrusionPreventionSystem","DisableRemovableDriveScanning",
                       "DisableScanningNetworkFiles")
            foreach ($pref in $prefs) {
                try { Set-MpPreference @{ $pref = $true } -Force -ErrorAction SilentlyContinue } catch { }
            }
            try { Set-MpPreference -MAPSReporting Disabled -Force -ErrorAction SilentlyContinue } catch { }
            try { Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue } catch { }
            [void]$log.Add("     OK.")
        }
    } catch { [void]$log.Add("     Aviso: $($_.Exception.Message)") }

    [void]$log.Add("[2] Eliminando politicas de grupo (reg delete)...")
    $gpPaths = @(
        "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
        "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies"
    )
    foreach ($p in $gpPaths) {
        try {
            $null = & reg.exe delete $p /f 2>&1
            [void]$log.Add("     OK: $p")
        } catch { [void]$log.Add("     Aviso: $p") }
    }

    [void]$log.Add("[3] Recreando politicas de desactivacion...")
    $defPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $defPol)) { New-Item -Path $defPol -Force | Out-Null }
    Set-ItemProperty -Path $defPol -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $defPol -Name "DisableAntiVirus" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $rtPol = "$defPol\Real-Time Protection"
    if (-not (Test-Path $rtPol)) { New-Item -Path $rtPol -Force | Out-Null }
    foreach ($v in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                     "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
        Set-ItemProperty -Path $rtPol -Name $v -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    [void]$log.Add("     OK.")

    [void]$log.Add("[4] Deteniendo servicios...")
    $svcList = @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter","SecurityHealthService")
    foreach ($s in $svcList) {
        try {
            $null = & sc.exe stop $s 2>&1
            $null = & sc.exe config $s start= disabled 2>&1
            [void]$log.Add("     ${s}: OK")
        } catch { [void]$log.Add("     ${s}: (no existe)") }
    }

    [void]$log.Add("[5] Modificando Start=4 en registro...")
    $svcPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Sense",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisDrv",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot",
        "HKLM:\SYSTEM\CurrentControlSet\Services\Wdfilter"
    )
    foreach ($sp in $svcPaths) {
        try {
            if (Test-Path $sp) {
                Set-ItemProperty -Path $sp -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
                [void]$log.Add("     $sp -> Start=4")
            }
        } catch { }
    }

    [void]$log.Add("[6] Verificando tras 5 segundos...")
    Wait-WithDoEvents -Milliseconds 5000
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        [void]$log.Add("[7] Windows reinicio WinDefend. Reintentando...")
        $null = & sc.exe stop WinDefend 2>&1
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        $null = & sc.exe config WinDefend start= disabled 2>&1
        Wait-WithDoEvents -Milliseconds 3000
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq 'Running') {
            [void]$log.Add("     ADVERTENCIA: Sigue corriendo. REINICIA EL EQUIPO.")
        } else {
            [void]$log.Add("     OK. Detenido tras reintento.")
        }
    } else {
        [void]$log.Add("[7] WinDefend detenido correctamente.")
    }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2} segundos" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog ("Desactivacion completada en {0:N2}s" -f $sw.Elapsed.TotalSeconds) "INFO"
    Clear-StatusCache
    return ($log -join "`n")
}

# ==================================================================
# 18. ACTIVAR
# ==================================================================
function Enable-Defender {
    param([bool]$EnableCloud = $false, [bool]$EnableSamples = $false, [bool]$EnableTamper = $false)
    $log = New-Object System.Collections.ArrayList
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    Write-AppLog "Iniciando activacion..." "INFO"

    foreach ($s in @("WinDefend","WdNisSvc","Sense","WdNisDrv","WdBoot","Wdfilter")) {
        try {
            $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
            if (Test-Path $svcPath) {
                Set-ItemProperty -Path $svcPath -Name "Start" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    [void]$log.Add("[1] Registros Start=2 restaurados.")

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            [void]$log.Add("[2] Politicas eliminadas.")
        } else { [void]$log.Add("[2] No habia politicas.") }
    } catch {
        Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus" -Force -ErrorAction SilentlyContinue
        [void]$log.Add("[2] Politicas eliminadas (fallback).")
    }

    $rtWk = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    try {
        if (Test-Path $rtWk) {
            foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring","DisableOnAccessProtection",
                             "DisableScanOnRealtimeEnable","DisableIOAVProtection","DisableScriptScanning")) {
                Remove-ItemProperty -Path $rtWk -Name $n -Force -ErrorAction SilentlyContinue
            }
            [void]$log.Add("[3] Claves RTP limpiadas.")
        }
    } catch { }

    foreach ($s in @("WdNisSvc","Sense")) {
        try {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
                $null = & sc.exe config $s start= auto 2>&1
                Start-Service -Name $s -ErrorAction SilentlyContinue
                [void]$log.Add("[4] Servicio ${s}: INICIADO")
            }
        } catch { }
    }
    try {
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
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
        try { Set-MpPreference -MAPSReporting Advanced -Force -ErrorAction Stop; [void]$log.Add("[7] Nube (MAPS): ACTIVADO") }
        catch { [void]$log.Add("[7] Error nube: $($_.Exception.Message)") }
    } else { [void]$log.Add("[7] Nube: omitida.") }

    if ($EnableSamples -and (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        try { Set-MpPreference -SubmitSamplesConsent 1 -Force -ErrorAction Stop; [void]$log.Add("[8] Muestras: ACTIVADO") }
        catch { [void]$log.Add("[8] Error muestras: $($_.Exception.Message)") }
    } else { [void]$log.Add("[8] Muestras: omitido.") }

    if ($EnableTamper) {
        try {
            $tpPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
            $writeOk = $false
            try {
                if (-not (Test-Path $tpPath)) { New-Item -Path $tpPath -Force | Out-Null }
                Set-ItemProperty -Path $tpPath -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction Stop
                Set-ItemProperty -Path $tpPath -Name "TamperProtectionSource" -Value 1 -Type String -Force -ErrorAction Stop
                $writeOk = $true
                [void]$log.Add("[9] Registro Tamper escrito.")
            } catch { [void]$log.Add("[9] No se pudo escribir TP: $($_.Exception.Message)") }
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
            if ($verify) { [void]$log.Add("[9] Tamper: CONFIRMADO.") }
            else { [void]$log.Add("[9] Tamper: RECHAZADO por Windows. Activalo manualmente.") }
        } catch { [void]$log.Add("[9] Error TP: $($_.Exception.Message)") }
    } else { [void]$log.Add("[9] Tamper: omitido.") }

    $sw.Stop()
    [void]$log.Add("[OK] Tiempo total: {0:N2} segundos" -f $sw.Elapsed.TotalSeconds)
    Write-AppLog ("Activacion completada en {0:N2}s" -f $sw.Elapsed.TotalSeconds) "INFO"
    Clear-StatusCache
    return ($log -join "`n")
}

# ==================================================================
# 19. ADMIN / OS / EXCLUSION
# ==================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-OSInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{ Caption=$os.Caption; Version=$os.Version; BuildNumber=$os.BuildNumber }
    } catch { return [PSCustomObject]@{ Caption="Desconocido"; Version="Desconocido"; BuildNumber="Desconocido" } }
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
    } catch { Write-AppLog "Error exclusion: $($_.Exception.Message)" "ERROR" }
    return $false
}

# ==================================================================
# 20. ICONOS DINAMICOS
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
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 1.5
        $g.DrawPolygon($pen, $pts)
        $g.Dispose(); $brush.Dispose(); $pen.Dispose()
        return $bmp
    } catch { return $null }
}
$script:IconBmpOk      = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(40, 167, 69))
$script:IconBmpBad     = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(220, 53, 69))
$script:IconBmpPartial = New-ShieldBitmap -FillColor ([System.Drawing.Color]::FromArgb(230, 160, 0))
$script:IconOk      = if ($null -ne $script:IconBmpOk)      { [System.Drawing.Icon]::FromHandle($script:IconBmpOk.GetHicon()) }      else { [System.Drawing.SystemIcons]::Shield }
$script:IconBad     = if ($null -ne $script:IconBmpBad)     { [System.Drawing.Icon]::FromHandle($script:IconBmpBad.GetHicon()) }     else { [System.Drawing.SystemIcons]::Error }
$script:IconPartial = if ($null -ne $script:IconBmpPartial) { [System.Drawing.Icon]::FromHandle($script:IconBmpPartial.GetHicon()) } else { [System.Drawing.SystemIcons]::Warning }

# ==================================================================
# 21. BOTONES
# ==================================================================
function New-ColorButton {
    param([string]$Texto, [System.Drawing.Color]$Color, [System.Drawing.Color]$Hover, [int]$Y, [int]$Ancho = 390, [int]$Alto = 32)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Texto
    $b.Size = New-Object System.Drawing.Size($Ancho, $Alto)
    $b.Location = New-Object System.Drawing.Point(15, $Y)
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Color
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Color; $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
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
        $Boton.Cursor = "Hand"; $Boton.Tag.Habilitado = $true
    } else {
        $Boton.BackColor = $script:Colors.BtnGray
        $Boton.ForeColor = $script:Colors.BtnGrayText
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGray
        $Boton.Cursor = "Default"; $Boton.Tag.Habilitado = $false
    }
}

# ==================================================================
# 22. VISOR DE LOG
# ==================================================================
function Update-LogViewContent {
    param([System.Windows.Forms.TextBox]$TextBox)
    if ($null -eq $TextBox -or $TextBox.IsDisposed) { return }
    if (Test-Path $script:LogFile) {
        $c = Get-Content -Path $script:LogFile -Raw -ErrorAction SilentlyContinue
        $TextBox.Text = if ([string]::IsNullOrEmpty($c)) { "(Vacio)" } else { $c }
    } else { $TextBox.Text = "(Sin log todavia)`r`n$($script:LogFile)" }
    $TextBox.SelectionStart = $TextBox.Text.Length; $TextBox.ScrollToCaret()
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
    $lbl.ForeColor = [System.Drawing.Color]::White; $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoSize = $true; $lbl.Location = New-Object System.Drawing.Point(15, 13)
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
    $btnRefresh.Text = "Refrescar"; $btnRefresh.Size = New-Object System.Drawing.Size(110, 34)
    $btnRefresh.Location = New-Object System.Drawing.Point(15, 10)
    $btnRefresh.FlatStyle = "Flat"; $btnRefresh.FlatAppearance.BorderSize = 0
    $btnRefresh.BackColor = $script:Colors.BtnBlue
    $btnRefresh.ForeColor = [System.Drawing.Color]::White
    $btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefresh.Cursor = "Hand"
    $pBot.Controls.Add($btnRefresh)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Guardar TXT"; $btnSave.Size = New-Object System.Drawing.Size(120, 34)
    $btnSave.Location = New-Object System.Drawing.Point(135, 10)
    $btnSave.FlatStyle = "Flat"; $btnSave.FlatAppearance.BorderSize = 0
    $btnSave.BackColor = $script:Colors.BtnGreen
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnSave.Cursor = "Hand"
    $pBot.Controls.Add($btnSave)

    $btnCsv = New-Object System.Windows.Forms.Button
    $btnCsv.Text = "Exportar CSV"; $btnCsv.Size = New-Object System.Drawing.Size(120, 34)
    $btnCsv.Location = New-Object System.Drawing.Point(265, 10)
    $btnCsv.FlatStyle = "Flat"; $btnCsv.FlatAppearance.BorderSize = 0
    $btnCsv.BackColor = $script:Colors.BtnPurple
    $btnCsv.ForeColor = [System.Drawing.Color]::White
    $btnCsv.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCsv.Cursor = "Hand"
    $pBot.Controls.Add($btnCsv)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Abrir carpeta"; $btnOpen.Size = New-Object System.Drawing.Size(120, 34)
    $btnOpen.Location = New-Object System.Drawing.Point(395, 10)
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

    $btnRefresh.Add_Click({ Update-LogViewContent -TextBox $txt }.GetNewClosure())
    $btnSave.Add_Click({
        $sdlg = New-Object System.Windows.Forms.SaveFileDialog
        $sdlg.Filter = "Texto (*.txt)|*.txt"; $sdlg.FileName = "DefenderTray_Log_{0:yyyy-MM-dd_HHmmss}.txt" -f (Get-Date)
        if ($sdlg.ShowDialog() -eq "OK") {
            try {
                if (Test-Path $script:LogFile) { Copy-Item $script:LogFile $sdlg.FileName -Force }
                else { $txt.Text | Out-File $sdlg.FileName -Encoding UTF8 }
                [System.Windows.Forms.MessageBox]::Show("Guardado:`n$($sdlg.FileName)","OK","OK","Information") | Out-Null
            } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Error","OK","Error") | Out-Null }
        }
    }.GetNewClosure())
    $btnCsv.Add_Click({
        $sdlg = New-Object System.Windows.Forms.SaveFileDialog
        $sdlg.Filter = "CSV (*.csv)|*.csv"; $sdlg.FileName = "DefenderTray_Eventos_{0:yyyy-MM-dd_HHmmss}.csv" -f (Get-Date)
        if ($sdlg.ShowDialog() -eq "OK") {
            try {
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine('"Fecha","Accion","Resultado","Segundos"')
                foreach ($e in $script:EventHistory) {
                    [void]$sb.AppendLine('"{0:yyyy-MM-dd HH:mm:ss}","{1}","{2}","{3:N2}"' -f $e.Hora, $e.Accion, $e.Resultado, $e.Segundos)
                }
                $sb.ToString() | Out-File -FilePath $sdlg.FileName -Encoding UTF8
                [System.Windows.Forms.MessageBox]::Show("CSV exportado:`n$($sdlg.FileName)","OK","OK","Information") | Out-Null
            } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Error","OK","Error") | Out-Null }
        }
    }.GetNewClosure())
    $btnOpen.Add_Click({ Start-Process "explorer.exe" -ArgumentList $script:LogFolder })
    $btnClose.Add_Click({ $frm.Close() }.GetNewClosure())

    [void]$frm.ShowDialog()
}

# ==================================================================
# 23. HISTORIAL
# ==================================================================
function Show-HistoryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Historial de operaciones"
    $dlg.ClientSize = New-Object System.Drawing.Size(640, 460)
    $dlg.StartPosition = "CenterScreen"
    $dlg.Icon = [System.Drawing.SystemIcons]::Application
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 50
    $header.BackColor = $script:Colors.BtnBlue
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Historial de operaciones (ultimas 20)"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 13)
    $header.Controls.Add($lblH)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"; $lv.FullRowSelect = $true; $lv.GridLines = $true
    $lv.HeaderStyle = "Nonclickable"; $lv.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lv.Location = New-Object System.Drawing.Point(15, 65)
    $lv.Size = New-Object System.Drawing.Size(610, 340)
    $lv.BorderStyle = "FixedSingle"
    [void]$lv.Columns.Add("Hora", 150); [void]$lv.Columns.Add("Accion", 130)
    [void]$lv.Columns.Add("Resultado", 200); [void]$lv.Columns.Add("Segundos", 90)
    $dlg.Controls.Add($lv)

    foreach ($entry in $script:EventHistory) {
        $item = New-Object System.Windows.Forms.ListViewItem($entry.Hora.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$item.SubItems.Add($entry.Accion)
        [void]$item.SubItems.Add($entry.Resultado)
        [void]$item.SubItems.Add(("{0:N2}" -f $entry.Segundos))
        if ($entry.Resultado -match "OK|activado correctamente|desactivado correctamente") { $item.ForeColor = $script:Colors.Ok }
        elseif ($entry.Resultado -match "parcial|ERROR") { $item.ForeColor = $script:Colors.Bad }
        [void]$lv.Items.Add($item)
    }

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text = "Cerrar"; $btnCerrar.Size = New-Object System.Drawing.Size(150, 36)
    $btnCerrar.Location = New-Object System.Drawing.Point(475, 415)
    $btnCerrar.FlatStyle = "Flat"; $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.BackColor = $script:Colors.BtnDarkGray
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.Cursor = "Hand"; $btnCerrar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCerrar)

    $btnAbrirCsv = New-Object System.Windows.Forms.Button
    $btnAbrirCsv.Text = "Abrir CSV"; $btnAbrirCsv.Size = New-Object System.Drawing.Size(150, 36)
    $btnAbrirCsv.Location = New-Object System.Drawing.Point(15, 415)
    $btnAbrirCsv.FlatStyle = "Flat"; $btnAbrirCsv.FlatAppearance.BorderSize = 0
    $btnAbrirCsv.BackColor = $script:Colors.BtnTeal
    $btnAbrirCsv.ForeColor = [System.Drawing.Color]::White
    $btnAbrirCsv.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnAbrirCsv.Cursor = "Hand"; $btnAbrirCsv.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnAbrirCsv)

    $btnCerrar.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnAbrirCsv.Add_Click({
        if (Test-Path $script:CsvFile) { Start-Process "notepad.exe" -ArgumentList $script:CsvFile }
        else { [System.Windows.Forms.MessageBox]::Show("Aun no hay eventos registrados.","Historial","OK","Information") | Out-Null }
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

# ==================================================================
# 24. OPCIONES AVANZADAS
# ==================================================================
function Show-AdvancedActivationDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Opciones de activacion"
    $dlg.ClientSize = New-Object System.Drawing.Size(440, 400)
    $dlg.StartPosition = "CenterScreen"; $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $script:Colors.Background
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.Icon = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.BtnGreen
    $dlg.Controls.Add($header)
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = "Opciones avanzadas de activacion"
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lblH.ForeColor = [System.Drawing.Color]::White; $lblH.BackColor = [System.Drawing.Color]::Transparent
    $lblH.AutoSize = $true; $lblH.Location = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblH)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Selecciona los servicios adicionales a activar:"
    $lblInfo.AutoSize = $true; $lblInfo.ForeColor = $script:Colors.TextDiag
    $lblInfo.Location = New-Object System.Drawing.Point(15, 70)
    $dlg.Controls.Add($lblInfo)

    $cloud = -1; $samples = -1; $tamper = $false
    try {
        if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
            $p = Get-MpPreference -ErrorAction SilentlyContinue
            if ($null -ne $p) {
                if ($null -ne $p.MAPSReporting) { $cloud = [int]$p.MAPSReporting }
                if ($null -ne $p.SubmitSamplesConsent) { $samples = [int]$p.SubmitSamplesConsent }
            }
        }
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $st = Get-MpComputerStatus -ErrorAction Stop
            $tamper = [bool]$st.IsTamperProtected
        }
    } catch { }

    $chkCloud = New-Object System.Windows.Forms.CheckBox
    $chkCloud.Text = "Proteccion basada en la nube (MAPS Advanced)"
    $chkCloud.Location = New-Object System.Drawing.Point(20, 100)
    $chkCloud.Size = New-Object System.Drawing.Size(400, 24)
    $chkCloud.ForeColor = $script:Colors.TextDiag
    if ($cloud -eq 2) { $chkCloud.Checked = $true; $chkCloud.Enabled = $false; $chkCloud.Text += "  [ya activado]"; $chkCloud.ForeColor = $script:Colors.TextMuted }
    else { $chkCloud.Checked = $true }
    $dlg.Controls.Add($chkCloud)

    $lblCloudInfo = New-Object System.Windows.Forms.Label
    $lblCloudInfo.Text = "Envia informacion a Microsoft para analisis en tiempo real."
    $lblCloudInfo.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblCloudInfo.ForeColor = $script:Colors.TextMuted
    $lblCloudInfo.Size = New-Object System.Drawing.Size(400, 15)
    $lblCloudInfo.Location = New-Object System.Drawing.Point(40, 124)
    $dlg.Controls.Add($lblCloudInfo)

    $chkSamples = New-Object System.Windows.Forms.CheckBox
    $chkSamples.Text = "Envio automatico de muestras (Safe samples)"
    $chkSamples.Location = New-Object System.Drawing.Point(20, 150)
    $chkSamples.Size = New-Object System.Drawing.Size(400, 24)
    $chkSamples.ForeColor = $script:Colors.TextDiag
    if ($samples -in 1,3) { $chkSamples.Checked = $true; $chkSamples.Enabled = $false; $chkSamples.Text += "  [ya activado]"; $chkSamples.ForeColor = $script:Colors.TextMuted }
    else { $chkSamples.Checked = $true }
    $dlg.Controls.Add($chkSamples)

    $lblSamplesInfo = New-Object System.Windows.Forms.Label
    $lblSamplesInfo.Text = "Envia muestras sospechosas a Microsoft."
    $lblSamplesInfo.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Italic)
    $lblSamplesInfo.ForeColor = $script:Colors.TextMuted
    $lblSamplesInfo.Size = New-Object System.Drawing.Size(400, 15)
    $lblSamplesInfo.Location = New-Object System.Drawing.Point(40, 174)
    $dlg.Controls.Add($lblSamplesInfo)

    $chkTamper = New-Object System.Windows.Forms.CheckBox
    $chkTamper.Text = "Proteccion contra alteraciones (Tamper Protection)"
    $chkTamper.Location = New-Object System.Drawing.Point(20, 200)
    $chkTamper.Size = New-Object System.Drawing.Size(400, 24)
    $chkTamper.ForeColor = $script:Colors.TextDiag
    if ($tamper) { $chkTamper.Checked = $true; $chkTamper.Enabled = $false; $chkTamper.Text += "  [ya activado]"; $chkTamper.ForeColor = $script:Colors.TextMuted }
    else { $chkTamper.Checked = $true }
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
    $pInfo.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 220); $pInfo.BorderStyle = "FixedSingle"
    $dlg.Controls.Add($pInfo)

    $lblNota = New-Object System.Windows.Forms.Label
    $lblNota.Text = "NOTA: Microsoft bloquea Tamper Protection via script.`n" +
                    "Activalo manualmente en: Seguridad de Windows ->`n" +
                    "Proteccion antivirus -> Administrar la configuracion."
    $lblNota.Font = New-Object System.Drawing.Font("Segoe UI", 7)
    $lblNota.ForeColor = [System.Drawing.Color]::FromArgb(150, 100, 0)
    $lblNota.Size = New-Object System.Drawing.Size(400, 55)
    $lblNota.Location = New-Object System.Drawing.Point(8, 4)
    $pInfo.Controls.Add($lblNota)

    $btnAceptar = New-Object System.Windows.Forms.Button
    $btnAceptar.Text = "Aceptar y Activar"; $btnAceptar.Size = New-Object System.Drawing.Size(200, 40)
    $btnAceptar.Location = New-Object System.Drawing.Point(15, 325)
    $btnAceptar.FlatStyle = "Flat"; $btnAceptar.FlatAppearance.BorderSize = 0
    $btnAceptar.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGreenHover
    $btnAceptar.BackColor = $script:Colors.BtnGreen; $btnAceptar.ForeColor = [System.Drawing.Color]::White
    $btnAceptar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnAceptar.Cursor = "Hand"; $btnAceptar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnAceptar)

    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = "Cancelar"; $btnCancelar.Size = New-Object System.Drawing.Size(180, 40)
    $btnCancelar.Location = New-Object System.Drawing.Point(230, 325)
    $btnCancelar.FlatStyle = "Flat"; $btnCancelar.FlatAppearance.BorderSize = 0
    $btnCancelar.FlatAppearance.MouseOverBackColor = $script:Colors.BtnDarkGrayHov
    $btnCancelar.BackColor = $script:Colors.BtnDarkGray; $btnCancelar.ForeColor = [System.Drawing.Color]::White
    $btnCancelar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.Cursor = "Hand"; $btnCancelar.UseVisualStyleBackColor = $false
    $dlg.Controls.Add($btnCancelar)

    $script:DlgResult = [PSCustomObject]@{ Apply=$false; EnableCloud=$false; EnableSamples=$false; EnableTamper=$false }

    $btnAceptar.Add_Click({
        $script:DlgResult = [PSCustomObject]@{
            Apply = $true
            EnableCloud = ($chkCloud.Enabled -and $chkCloud.Checked)
            EnableSamples = ($chkSamples.Enabled -and $chkSamples.Checked)
            EnableTamper = ($chkTamper.Enabled -and $chkTamper.Checked)
        }
        $dlg.Close()
    }.GetNewClosure())
    $btnCancelar.Add_Click({
        $script:DlgResult = [PSCustomObject]@{ Apply=$false; EnableCloud=$false; EnableSamples=$false; EnableTamper=$false }
        $dlg.Close()
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return $script:DlgResult
}

# ==================================================================
# 25. ESTADO GLOBAL DEL PANEL
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
$script:StatusLabel        = $null
$script:ShortcutLabel      = $null
$script:IsBusy             = $false
$script:ActionStartTime    = $null
$script:ActionName         = ""
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
            default       { $script:notifyIcon.Icon = $script:IconPartial; $script:notifyIcon.Text = "Windows Defender - ?" }
        }
    } catch { }
}

function Update-PanelStatusUI {
    if ($null -eq $script:PanelForm -or $script:PanelForm.IsDisposed) { return }
    $s = Get-QuickStatus
    $diag = "Servicio:{0}  TiempoReal:{1}  Politica:{2}" -f `
        $(if($s.ServiceRunning){'ON'}else{'OFF'}), `
        $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'}), `
        $(if($s.HasPolicy){'SI'}else{'NO'})

    if ($s.Estado -eq "ACTIVO") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderOk
        $script:PanelLblValor.Text = "ACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderOk
        $script:PanelLblDetalle1.Text = "El antivirus esta protegiendo este equipo."
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar -Habilitado $false
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } elseif ($s.Estado -eq "PARCIAL") {
        $script:PanelHeader.BackColor = $script:Colors.HeaderPartial
        $script:PanelLblValor.Text = "PROTECCION PARCIAL"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderPartial
        if ($s.HasPolicy -and -not $s.RealTimeProtectionEnabled) { $script:PanelLblDetalle1.Text = "Politica bloquea Defender y RTP inactivo." }
        elseif ($s.HasPolicy) { $script:PanelLblDetalle1.Text = "Politica de grupo bloquea Defender." }
        else { $script:PanelLblDetalle1.Text = "Proteccion en tiempo real desactivada." }
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $true
    } else {
        $script:PanelHeader.BackColor = $script:Colors.HeaderWarn
        $script:PanelLblValor.Text = "DESACTIVADO"
        $script:PanelLblValor.ForeColor = $script:Colors.HeaderWarn
        $script:PanelLblDetalle1.Text = "El antivirus esta inactivo. Sin proteccion."
        $script:PanelLblDetalle1.ForeColor = $script:Colors.TextDiag
        $script:PanelLblDetalle2.Text = $diag
        Set-ButtonVisualState -Boton $script:PanelBtnActivar -Habilitado $true
        Set-ButtonVisualState -Boton $script:PanelBtnDesactivar -Habilitado $false
    }

    if ($script:LastActionTime -gt 0) {
        $script:PanelLblDetalle3.Text = "Ultima operacion: $($script:LastActionName) en {0:N2}s" -f $script:LastActionTime
    } else {
        $script:PanelLblDetalle3.Text = "Listo para operar. F1 Ayuda | F5 Refrescar"
    }

    Update-ContextualHelp

    if ($s.Estado -ne $script:LastKnownEstado) {
        Update-TrayIcon -Estado $s.Estado
        if ($script:LastKnownEstado -ne "UNKNOWN" -and -not $script:SilentMode) {
            try { $script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado cambio a: $($s.Estado)", "Info") } catch { }
        }
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
            $script:PanelLblTimerH.Text = "{0:N2}s" -f $el
        } else { $script:PanelLblTimerH.Text = "espera" }
        if (-not $script:IsBusy -and $null -eq $script:ActionStartTime) {
            try { Update-PanelStatusUI } catch { }
        }
    })
    $script:PanelTimer.Start()
}

# ==================================================================
# 26. MOSTRAR PANEL
# ==================================================================
function Show-DefenderPanel {
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

    $script:IsBusy = $false; $script:ActionStartTime = $null; $script:ActionName = ""
    $script:LastActionTime = 0; $script:LastActionName = ""

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Control de Seguridad de Windows"
    $form.ClientSize = New-Object System.Drawing.Size(420, 505)
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.KeyPreview = $true
    $form.BackColor = $script:Colors.Background
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = [System.Drawing.SystemIcons]::Shield

    # Header
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 55; $header.BackColor = $script:Colors.HeaderUnknown
    $form.Controls.Add($header)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "Windows Defender"
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true; $lblHeader.Location = New-Object System.Drawing.Point(15, 14)
    $header.Controls.Add($lblHeader)

    $lblReloj = New-Object System.Windows.Forms.Label
    $lblReloj.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblReloj.ForeColor = [System.Drawing.Color]::FromArgb(220, 235, 220)
    $lblReloj.BackColor = [System.Drawing.Color]::Transparent
    $lblReloj.AutoSize = $false; $lblReloj.Size = New-Object System.Drawing.Size(160, 20)
    $lblReloj.Location = New-Object System.Drawing.Point(245, 8); $lblReloj.TextAlign = "MiddleRight"
    $header.Controls.Add($lblReloj)

    $lblTimerH = New-Object System.Windows.Forms.Label
    $lblTimerH.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $lblTimerH.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 120)
    $lblTimerH.BackColor = [System.Drawing.Color]::Transparent
    $lblTimerH.AutoSize = $false; $lblTimerH.Size = New-Object System.Drawing.Size(160, 20)
    $lblTimerH.Location = New-Object System.Drawing.Point(245, 28); $lblTimerH.TextAlign = "MiddleRight"
    $lblTimerH.Text = "00:00.00s"
    $header.Controls.Add($lblTimerH)

    # Status Strip (barra de estado inferior)
    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusStrip.SizingGrip = $false
    $statusStrip.BackColor = $script:Colors.StatusBg
    $statusStrip.Font = New-Object System.Drawing.Font("Segoe UI", 8)

    $script:StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:StatusLabel.Text = "Iniciando..."
    $script:StatusLabel.Spring = $true
    $script:StatusLabel.TextAlign = "MiddleLeft"
    $script:StatusLabel.ForeColor = $script:Colors.TextDiag
    [void]$statusStrip.Items.Add($script:StatusLabel)

    $script:ShortcutLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:ShortcutLabel.Text = "F1 Ayuda | F5 Refrescar | Esc Cerrar"
    $script:ShortcutLabel.ForeColor = $script:Colors.TextMuted
    [void]$statusStrip.Items.Add($script:ShortcutLabel)

    $form.Controls.Add($statusStrip)

    # Card
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 65)
    $card.Size = New-Object System.Drawing.Size(390, 128)
    $card.BackColor = $script:Colors.CardBg; $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)

    $lblEstadoTag = New-Object System.Windows.Forms.Label
    $lblEstadoTag.Text = "Estado actual"
    $lblEstadoTag.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEstadoTag.ForeColor = $script:Colors.TextMuted
    $lblEstadoTag.AutoSize = $true; $lblEstadoTag.Location = New-Object System.Drawing.Point(12, 6)
    $card.Controls.Add($lblEstadoTag)

    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize = $true; $lblValor.Location = New-Object System.Drawing.Point(12, 24)
    $card.Controls.Add($lblValor)

    $lblDetalle1 = New-Object System.Windows.Forms.Label
    $lblDetalle1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDetalle1.ForeColor = $script:Colors.TextDiag
    $lblDetalle1.AutoSize = $false; $lblDetalle1.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle1.Location = New-Object System.Drawing.Point(12, 62)
    $card.Controls.Add($lblDetalle1)

    $lblDetalle2 = New-Object System.Windows.Forms.Label
    $lblDetalle2.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblDetalle2.ForeColor = $script:Colors.TextDiag
    $lblDetalle2.AutoSize = $false; $lblDetalle2.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle2.Location = New-Object System.Drawing.Point(12, 80)
    $card.Controls.Add($lblDetalle2)

    $lblDetalle3 = New-Object System.Windows.Forms.Label
    $lblDetalle3.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblDetalle3.ForeColor = $script:Colors.TextMuted
    $lblDetalle3.AutoSize = $false; $lblDetalle3.Size = New-Object System.Drawing.Size(370, 16)
    $lblDetalle3.Location = New-Object System.Drawing.Point(12, 100)
    $card.Controls.Add($lblDetalle3)

    # Botones
    $btnVerificar  = New-ColorButton "VERIFICAR ESTADO COMPLETO" $script:Colors.BtnPurple   $script:Colors.BtnPurpleHover  200 390 30
    $btnActivar    = New-ColorButton $script:TXT_ACTIVAR        $script:Colors.BtnGreen    $script:Colors.BtnGreenHover  234 390 30
    $btnDesactivar = New-ColorButton $script:TXT_DESACTIVAR     $script:Colors.BtnRed      $script:Colors.BtnRedHover    268 390 30
    $btnHistorial  = New-ColorButton "Ver Historial"            $script:Colors.BtnBlue     $script:Colors.BtnBlueHover   302 190 30
    $btnLog        = New-ColorButton "Ver Registro"             $script:Colors.BtnTeal     $script:Colors.BtnTealHover   302 190 30
    $btnAyuda      = New-ColorButton "Ayuda (F1)"               $script:Colors.BtnBlue     $script:Colors.BtnBlueHover   336 190 30
    $btnAcerca     = New-ColorButton "Acerca de..."             $script:Colors.BtnDarkGray $script:Colors.BtnDarkGrayHov 336 190 30
    $btnSalir      = New-ColorButton "SALIR"                    $script:Colors.BtnDarkGray $script:Colors.BtnDarkGrayHov 370 390 32

    $btnLog.Location = New-Object System.Drawing.Point(215, 302)
    $btnAcerca.Location = New-Object System.Drawing.Point(215, 336)

    $form.Controls.Add($btnVerificar)
    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnHistorial)
    $form.Controls.Add($btnLog)
    $form.Controls.Add($btnAyuda)
    $form.Controls.Add($btnAcerca)
    $form.Controls.Add($btnSalir)

    # Tooltips + help on hover (barra de estado)
    Set-HelpOnControl -Control $btnVerificar -ToolTip "Abre un panel con el estado de los 18 modulos de Windows Defender.`nPuedes copiar el informe al portapapeles." -StatusText "VERIFICAR ESTADO COMPLETO: abre el diagnostico detallado de los 18 modulos."
    Set-HelpOnControl -Control $btnActivar   -ToolTip "Restaura Windows Defender: elimina politicas, reinicia servicios`ny abre un dialogo con opciones avanzadas (nube, muestras, tamper)." -StatusText "ACTIVAR PROTECCION: restaura servicios, politicas y proteccion en tiempo real."
    Set-HelpOnControl -Control $btnDesactivar -ToolTip "Desactiva Windows Defender por completo con un metodo agresivo de 7 pasos.`nEn Windows 11 puede requerir REINICIAR el equipo." -StatusText "DESACTIVAR PROTECCION: detiene servicios, borra politicas y aplica bloqueo permanente."
    Set-HelpOnControl -Control $btnHistorial -ToolTip "Muestra las ultimas 20 operaciones con hora, accion, resultado y duracion." -StatusText "VER HISTORIAL: lista las 20 operaciones mas recientes. Puedes abrir el CSV del dia."
    Set-HelpOnControl -Control $btnLog       -ToolTip "Abre el log completo en formato consola.`nPermite Refrescar, Guardar TXT, Exportar CSV y Abrir carpeta." -StatusText "VER REGISTRO: log completo con opciones de exportacion a TXT y CSV."
    Set-HelpOnControl -Control $btnAyuda     -ToolTip "Abre esta misma ventana de ayuda (tambien con F1)." -StatusText "AYUDA (F1): guia completa de uso, estados, acciones, atajos y solucion de problemas."
    Set-HelpOnControl -Control $btnAcerca    -ToolTip "Informacion del autor, version y sistema operativo." -StatusText "ACERCA DE: informacion del autor y del sistema operativo."
    Set-HelpOnControl -Control $btnSalir     -ToolTip "Cierra el panel. La aplicacion sigue en la bandeja." -StatusText "SALIR: cierra el panel. La aplicacion sigue activa en la bandeja (clic derecho para salir del todo)."

    # Asignar al scope script
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

    # Atajos
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F1) {
            Show-HelpDialog
            $e.Handled = $true
        } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
            Update-PanelStatusUI
            $e.Handled = $true
        } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::R) {
            Update-PanelStatusUI
            $e.Handled = $true
        } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
            $script:PanelForm.Close()
            $e.Handled = $true
        }
    })

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
            $script:IsBusy = $true; $script:ActionStartTime = Get-Date; $script:ActionName = "Activar"
            $script:PanelLblDetalle1.Text = "Activando... espere."
            $script:PanelLblDetalle1.ForeColor = $script:Colors.HeaderPartial
            [System.Windows.Forms.Application]::DoEvents()
            $log = Enable-Defender -EnableCloud $opts.EnableCloud -EnableSamples $opts.EnableSamples -EnableTamper $opts.EnableTamper
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed; $script:LastActionName = "Activar"
            $script:ActionStartTime = $null; $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            if ($s.Estado -eq "ACTIVO") { Add-History -Accion "Activar" -Resultado "OK - activado" -Segundos $elapsed }
            else { Add-History -Accion "Activar" -Resultado "Parcial: $($s.Estado)" -Segundos $elapsed }
            if (-not $script:SilentMode) {
                if ($s.Estado -eq "ACTIVO") {
                    [System.Windows.Forms.MessageBox]::Show("Windows Defender ACTIVADO.`n`nTiempo: {0:N2}s`n`n$log" -f $elapsed,"Listo","OK","Information") | Out-Null
                } else {
                    $msg = "Activacion parcial.`nTiempo: {0:N2}s`n`n" -f $elapsed
                    $msg += "Servicio: $(if($s.ServiceRunning){'ON'}else{'OFF'})`nTiempoReal: $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'})`nPolitica: $(if($s.HasPolicy){'SI'}else{'NO'})`n`n$log"
                    [System.Windows.Forms.MessageBox]::Show($msg,"Verificacion","OK","Warning") | Out-Null
                }
            }
        } finally { $script:IsBusy = $false; $script:ActionStartTime = $null }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        if (-not $script:SilentMode) {
            $c = [System.Windows.Forms.MessageBox]::Show(
                "Vas a DESACTIVAR Windows Defender COMPLETAMENTE.`n`nEsta operacion elimina todas las politicas de grupo y deshabilita el servicio. Continuar?",
                "Confirmar", "YesNo", "Warning")
            if ($c -ne "Yes") { return }
        }
        try {
            $script:IsBusy = $true; $script:ActionStartTime = Get-Date; $script:ActionName = "Desactivar"
            $script:PanelLblDetalle1.Text = "Desactivando AGRESIVAMENTE... espere."
            $script:PanelLblDetalle1.ForeColor = $script:Colors.HeaderPartial
            [System.Windows.Forms.Application]::DoEvents()
            $log = Disable-Defender
            $elapsed = ((Get-Date) - $script:ActionStartTime).TotalSeconds
            $script:LastActionTime = $elapsed; $script:LastActionName = "Desactivar"
            $script:ActionStartTime = $null; $script:IsBusy = $false
            Update-PanelStatusUI
            $s = Get-QuickStatus
            if ($s.Estado -eq "DESACTIVADO") { Add-History -Accion "Desactivar" -Resultado "OK - desactivado" -Segundos $elapsed }
            else { Add-History -Accion "Desactivar" -Resultado "Parcial: $($s.Estado) - requiere REINICIO" -Segundos $elapsed }
            if (-not $script:SilentMode) {
                if ($s.Estado -eq "DESACTIVADO") {
                    [System.Windows.Forms.MessageBox]::Show("Windows Defender DESACTIVADO por completo.`n`nTiempo: {0:N2}s`n`n$log" -f $elapsed,"Listo","OK","Information") | Out-Null
                } else {
                    $msg = "Desactivacion PARCIAL.`nTiempo: {0:N2}s`n`n" -f $elapsed
                    $msg += "Servicio: $(if($s.ServiceRunning){'AUN CORRIENDO'}else{'DETENIDO'})`nTiempoReal: $(if($s.RealTimeProtectionEnabled){'AUN ACTIVO'}else{'INACTIVO'})`nPolitica: $(if($s.HasPolicy){'AUN PRESENTE'}else{'ELIMINADA'})`n`n"
                    $msg += "IMPORTANTE: Windows 11 puede reiniciar WinDefend automaticamente.`nREINICIA EL EQUIPO para que la desactivacion se aplique al 100%.`n`n$log"
                    [System.Windows.Forms.MessageBox]::Show($msg,"Verificacion - Requiere reinicio","OK","Warning") | Out-Null
                }
            }
        } finally { $script:IsBusy = $false; $script:ActionStartTime = $null }
    })

    $btnHistorial.Add_Click({ Show-HistoryDialog })
    $btnLog.Add_Click({ Show-LogViewer })
    $btnAyuda.Add_Click({ Show-HelpDialog })

    $btnAcerca.Add_Click({
        $osInfo = Get-OSInfo
        $txt = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.12
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

------------------------------------
Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Carpeta de logs:
$($script:LogFolder)

Atajos:
- F1:  Ayuda
- F5:  Refrescar
- Ctrl+R: Refrescar
- Esc: Cerrar panel

Novedades v3.12:
- Tooltips en todos los controles
- Barra de estado con ayuda contextual
- Ayuda F1 con pestanas
- Asistente de primera ejecucion
- Auto-inicio con Windows
- F5 / Esc / Ctrl+R
------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($txt,"Acerca de...","OK","Information") | Out-Null
    })

    $btnSalir.Add_Click({
        if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
        if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) { $script:PanelForm.Close() }
    })

    $form.Add_FormClosed({
        if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
        $script:PanelForm = $null
    })

    $form.Add_Shown({ Update-PanelStatusUI; Start-PanelTimer })
    $form.Show()
}

# ==================================================================
# 27. ARRANQUE
# ==================================================================
Write-AppLog "====================================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v3.12" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "SilentMode: $($script:SilentMode)" "INFO"
Write-AppLog "====================================================" "INFO"

if (Test-Admin) { Write-AppLog "Ejecutando como Administrador: SI" "INFO" }
else { Write-AppLog "Ejecutando como Administrador: NO" "WARN" }

if (Test-Admin) { Add-DefenderExclusion | Out-Null }

$initQuick = Get-QuickStatus
$script:LastKnownEstado = $initQuick.Estado

if ($initQuick.Estado -eq "ACTIVO") { $estadoInicial = "ACTIVADO"; $detalleInicial = "El antivirus esta protegiendo el equipo." }
elseif ($initQuick.Estado -eq "PARCIAL") { $estadoInicial = "PROTECCION PARCIAL"; $detalleInicial = "Falta proteccion real (RTP o politica)." }
else { $estadoInicial = "DESACTIVADO"; $detalleInicial = "El antivirus esta inactivo." }
Write-AppLog "Estado inicial: $estadoInicial" "INFO"

# Mostrar asistente si es primera ejecucion
if (-not $script:SilentMode -and (Test-FirstRun)) {
    Show-FirstRunWizard
} elseif (-not $script:SilentMode) {
    $osInfoInit = Get-OSInfo
    $mensajeInicial = @"
VERIFICACION INICIAL COMPLETADA

Sistema Operativo:
  $($osInfoInit.Caption)
  Version $($osInfoInit.Version)  (Build $($osInfoInit.BuildNumber))

Estado de Windows Defender:
  >>> $estadoInicial <<<

$detalleInicial

Atajos:
- Clic IZQUIERDO en icono: abrir panel (unico).
- Clic DERECHO: menu contextual.
- F1 en el panel: ayuda completa.
- F5 en el panel: refrescar.
- Esc en el panel: cerrar.

Registros en:
$($script:LogFolder)
"@
    [System.Windows.Forms.MessageBox]::Show($mensajeInicial, "Verificacion inicial - Windows Defender", "OK", "Information") | Out-Null
}

# ==================================================================
# 28. BANDEJA + MENU
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = $script:IconPartial
$script:notifyIcon.Text = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true
Update-TrayIcon -Estado $initQuick.Estado

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

$miVerificar = New-Object System.Windows.Forms.ToolStripMenuItem
$miVerificar.Text = "Verificar estado completo"
$miVerificar.Add_Click({ Show-CompleteStatusDialog })

$miHistorial = New-Object System.Windows.Forms.ToolStripMenuItem
$miHistorial.Text = "Ver historial"
$miHistorial.Add_Click({ Show-HistoryDialog })

$miAyuda = New-Object System.Windows.Forms.ToolStripMenuItem
$miAyuda.Text = "Ayuda (F1)"
$miAyuda.Add_Click({ Show-HelpDialog })

$miActivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miActivar.Text = "Activar Windows Defender"
$miActivar.Add_Click({
    if (-not (Test-Admin)) { [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null; return }
    $opts = Show-AdvancedActivationDialog
    if (-not $opts.Apply) { return }
    $swT = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Enable-Defender -EnableCloud $opts.EnableCloud -EnableSamples $opts.EnableSamples -EnableTamper $opts.EnableTamper
    $swT.Stop()
    $s = Get-QuickStatus
    Add-History -Accion "Activar (menu)" -Resultado $s.Estado -Segundos $swT.Elapsed.TotalSeconds
    Update-TrayIcon -Estado $s.Estado
    if ($s.Estado -eq "ACTIVO") { $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Activado correctamente.","Info") }
    else { $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Activacion parcial.","Warning") }
})

$miDesactivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miDesactivar.Text = "Desactivar Windows Defender"
$miDesactivar.Add_Click({
    if (-not (Test-Admin)) { [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null; return }
    $swT = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Disable-Defender
    $swT.Stop()
    $s = Get-QuickStatus
    Add-History -Accion "Desactivar (menu)" -Resultado $s.Estado -Segundos $swT.Elapsed.TotalSeconds
    Update-TrayIcon -Estado $s.Estado
    if ($s.Estado -eq "DESACTIVADO") { $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Desactivado.","Info") }
    else { $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Parcial. Requiere reinicio.","Warning") }
})

$miLog = New-Object System.Windows.Forms.ToolStripMenuItem
$miLog.Text = "Ver Registro"
$miLog.Add_Click({ Show-LogViewer })

$miTema = New-Object System.Windows.Forms.ToolStripMenuItem
$miTema.Text = "Tema oscuro"
$miTema.CheckOnClick = $true
$miTema.Checked = $script:DarkTheme
$miTema.Add_Click({
    $script:DarkTheme = $miTema.Checked
    try {
        if (-not (Test-Path "HKCU:\Software\DefenderTray")) { New-Item -Path "HKCU:\Software\DefenderTray" -Force | Out-Null }
        Set-ItemProperty -Path "HKCU:\Software\DefenderTray" -Name "DarkTheme" -Value ([int]$script:DarkTheme) -Type DWord -Force
    } catch { }
    $script:Colors = Get-PreferredPalette
    $script:notifyIcon.ShowBalloonTip(2000, "Tema", $(if($script:DarkTheme){"Tema oscuro activado (reabre el panel)."}else{"Tema claro activado."}), "Info")
})

$miAutostart = New-Object System.Windows.Forms.ToolStripMenuItem
$miAutostart.Text = "Iniciar con Windows"
$miAutostart.CheckOnClick = $true
$miAutostart.Checked = Get-AutoStartEnabled
$miAutostart.Add_Click({
    $ok = Set-AutoStart -Enable $miAutostart.Checked
    if ($ok) {
        $script:notifyIcon.ShowBalloonTip(2500, "Auto-inicio",
            $(if($miAutostart.Checked){"La aplicacion se iniciara con Windows."}else{"Auto-inicio desactivado."}), "Info")
    } else {
        [System.Windows.Forms.MessageBox]::Show("No se pudo cambiar la configuracion de auto-inicio.`nPuede requerir Administrador.","Error","OK","Error") | Out-Null
    }
})

$miAcerca = New-Object System.Windows.Forms.ToolStripMenuItem
$miAcerca.Text = "Acerca de..."
$miAcerca.Add_Click({
    $osInfo = Get-OSInfo
    $txt = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.12
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Logs: $($script:LogFolder)
CSV:  $($script:CsvFile)
"@
    [System.Windows.Forms.MessageBox]::Show($txt,"Acerca de...","OK","Information") | Out-Null
})

$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    Write-AppLog "Aplicacion cerrada." "INFO"
    if ($null -ne $script:PanelTimer) { try { $script:PanelTimer.Stop(); $script:PanelTimer.Dispose() } catch { }; $script:PanelTimer = $null }
    if ($null -ne $script:PanelForm -and -not $script:PanelForm.IsDisposed) { try { $script:PanelForm.Close() } catch { } }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add($miVerificar)
[void]$menu.Items.Add($miHistorial)
[void]$menu.Items.Add($miAyuda)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miLog)
[void]$menu.Items.Add($miTema)
[void]$menu.Items.Add($miAutostart)
[void]$menu.Items.Add($miAcerca)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

$menu.Add_Opening({
    $s = Get-QuickStatus
    if ($s.Estado -eq "ACTIVO") { $miActivar.Enabled = $false; $miDesactivar.Enabled = $true }
    else { $miActivar.Enabled = $true; $miDesactivar.Enabled = $false }
})

$script:notifyIcon.ContextMenuStrip = $menu

$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-DefenderPanel }
})

if (-not $script:SilentMode) {
    $script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estadoInicial", "Info")
}

# ==================================================================
# 29. LOOP
# ==================================================================
[System.Windows.Forms.Application]::Run()