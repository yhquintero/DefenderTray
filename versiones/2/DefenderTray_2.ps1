<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Icono en la bandeja con menu contextual en texto plano (sin caracteres especiales).
    - Modal visual compacto y colorido con botones para Activar / Desactivar / Salir.
    - Verificacion del estado tras cada accion.
.NOTES
    Ejecutar como Administrador.
    Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).
#>

# ──────────────────────────────────────────────
# 1. Ensamblados
# ──────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ──────────────────────────────────────────────
# 2. Paleta de colores (tema)
# ──────────────────────────────────────────────
$script:Colors = @{
    HeaderOk      = [System.Drawing.Color]::FromArgb(34, 139, 34)     # Verde
    HeaderWarn    = [System.Drawing.Color]::FromArgb(178, 34, 34)     # Rojo
    HeaderUnknown = [System.Drawing.Color]::FromArgb(70, 70, 70)      # Gris
    Background    = [System.Drawing.Color]::FromArgb(245, 247, 250)
    CardBg        = [System.Drawing.Color]::White
    TextDark      = [System.Drawing.Color]::FromArgb(33, 37, 41)
    TextMuted     = [System.Drawing.Color]::FromArgb(108, 117, 125)
    BtnGreen      = [System.Drawing.Color]::FromArgb(40, 167, 69)
    BtnGreenHover = [System.Drawing.Color]::FromArgb(33, 136, 56)
    BtnRed        = [System.Drawing.Color]::FromArgb(220, 53, 69)
    BtnRedHover   = [System.Drawing.Color]::FromArgb(178, 40, 54)
    BtnGray       = [System.Drawing.Color]::FromArgb(108, 117, 125)
    BtnGrayHover  = [System.Drawing.Color]::FromArgb(84, 91, 98)
    Border        = [System.Drawing.Color]::FromArgb(222, 226, 230)
}

# ──────────────────────────────────────────────
# 3. Estado de Defender
# ──────────────────────────────────────────────
function Get-DefenderStatus {
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $status = Get-MpComputerStatus -ErrorAction Stop
            return [PSCustomObject]@{
                AntivirusEnabled          = [bool]$status.AntivirusEnabled
                RealTimeProtectionEnabled = [bool]$status.RealTimeProtectionEnabled
                AMServiceEnabled          = [bool]$status.AMServiceEnabled
                IsTamperProtected         = [bool]$status.IsTamperProtected
                Source                    = "Get-MpComputerStatus"
            }
        } else {
            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                AntivirusEnabled          = ($svc.Status -eq 'Running')
                RealTimeProtectionEnabled = ($svc.Status -eq 'Running')
                AMServiceEnabled          = ($svc.Status -eq 'Running')
                IsTamperProtected         = $false
                Source                    = "Service WinDefend"
            }
        }
    } catch {
        return $null
    }
}

# ──────────────────────────────────────────────
# 4. Desactivar Defender
# ──────────────────────────────────────────────
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: DESACTIVADO")
        }
    } catch { [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)") }

    try {
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service  -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: DETENIDO / DESHABILITADO")
    } catch { [void]$log.Add("Aviso (servicio): $($_.Exception.Message)") }

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    try {
        New-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: = 1")
    } catch { [void]$log.Add("Aviso (registro): $($_.Exception.Message)") }

    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
            [void]$log.Add("Servicio ${svcName}: DETENIDO / DESHABILITADO")
        } catch { }
    }
    return ($log -join "`n")
}

# ──────────────────────────────────────────────
# 5. Activar Defender
# ──────────────────────────────────────────────
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    try {
        Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Force -ErrorAction SilentlyContinue
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: ELIMINADOS")
    } catch { [void]$log.Add("Aviso (registro): $($_.Exception.Message)") }

    try {
        Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: INICIADO / AUTOMATICO")
    } catch { [void]$log.Add("Aviso (servicio): $($_.Exception.Message)") }

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: ACTIVADO")
        }
    } catch { [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)") }

    return ($log -join "`n")
}

# ──────────────────────────────────────────────
# 6. Comprobacion de permisos
# ──────────────────────────────────────────────
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ──────────────────────────────────────────────
# 7. Modal visual (formulario)
# ──────────────────────────────────────────────
function Show-DefenderPanel {

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.Size            = New-Object System.Drawing.Size(340, 340)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = $script:Colors.Background
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon            = [System.Drawing.SystemIcons]::Shield

    # ── Cabecera coloreada ──
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock    = "Top"
    $header.Height  = 60
    $header.BackColor = $script:Colors.HeaderUnknown
    $form.Controls.Add($header)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text      = "Windows Defender"
    $lblHeader.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize  = $true
    $lblHeader.Location  = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblHeader)

    # ── Tarjeta de estado ──
    $card = New-Object System.Windows.Forms.Panel
    $card.Location    = New-Object System.Drawing.Point(15, 75)
    $card.Size        = New-Object System.Drawing.Size(295, 80)
    $card.BackColor   = $script:Colors.CardBg
    $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)

    $lblEstado = New-Object System.Windows.Forms.Label
    $lblEstado.Text      = "Estado actual"
    $lblEstado.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEstado.ForeColor = $script:Colors.TextMuted
    $lblEstado.AutoSize  = $true
    $lblEstado.Location  = New-Object System.Drawing.Point(12, 10)
    $card.Controls.Add($lblEstado)

    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize  = $true
    $lblValor.Location  = New-Object System.Drawing.Point(12, 30)
    $card.Controls.Add($lblValor)

    $lblDetalle = New-Object System.Windows.Forms.Label
    $lblDetalle.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDetalle.ForeColor = $script:Colors.TextMuted
    $lblDetalle.AutoSize  = $true
    $lblDetalle.Location  = New-Object System.Drawing.Point(12, 58)
    $card.Controls.Add($lblDetalle)

    # ── Botones ──
    function New-ColorButton {
        param($Texto, $Color, $Hover, $Y, $Ancho = 295)
        $b = New-Object System.Windows.Forms.Button
        $b.Text      = $Texto
        $b.Size      = New-Object System.Drawing.Size($Ancho, 38)
        $b.Location  = New-Object System.Drawing.Point(15, $Y)
        $b.FlatStyle = "Flat"
        $b.FlatAppearance.BorderSize = 0
        $b.BackColor = $Color
        $b.ForeColor = [System.Drawing.Color]::White
        $b.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
        $b.Cursor    = "Hand"
        $b.Add_MouseEnter({ $this.BackColor = $Hover })
        $b.Add_MouseLeave({ $this.BackColor = $Color })
        return $b
    }

    $btnActivar    = New-ColorButton "ACTIVAR PROTECCION"    $script:Colors.BtnGreen $script:Colors.BtnGreenHover 165
    $btnDesactivar = New-ColorButton "DESACTIVAR PROTECCION" $script:Colors.BtnRed   $script:Colors.BtnRedHover   210
    $btnSalir      = New-ColorButton "SALIR"                 $script:Colors.BtnGray  $script:Colors.BtnGrayHover  255

    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnSalir)

    # ── Refrescar estado visual ──
    function Update-StatusUI {
        $s = Get-DefenderStatus
        if ($null -eq $s) {
            $header.BackColor = $script:Colors.HeaderUnknown
            $lblValor.Text    = "DESCONOCIDO"
            $lblValor.ForeColor = $script:Colors.HeaderUnknown
            $lblDetalle.Text  = "No se pudo consultar el estado."
            return
        }
        if ($s.AntivirusEnabled) {
            $header.BackColor   = $script:Colors.HeaderOk
            $lblValor.Text      = "ACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderOk
            $lblDetalle.Text    = "Tiempo real: $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'})  |  Tamper: $(if($s.IsTamperProtected){'ON'}else{'OFF'})"
        } else {
            $header.BackColor   = $script:Colors.HeaderWarn
            $lblValor.Text      = "DESACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderWarn
            $lblDetalle.Text    = "Antivirus inactivo. Sistema sin proteccion."
        }
    }

    # ── Eventos ──
    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
            return
        }
        $btnActivar.Enabled = $false; $btnDesactivar.Enabled = $false
        $lblDetalle.Text = "Activando..."
        $form.Refresh()
        $log = Enable-Defender
        Start-Sleep -Seconds 2
        Update-StatusUI
        $btnActivar.Enabled = $true; $btnDesactivar.Enabled = $true

        $s = Get-DefenderStatus
        if ($s -and $s.AntivirusEnabled) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender ACTIVADO correctamente.`n`n$log", "Listo", "OK", "Information") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la activacion. Reinicia el equipo o desactiva Tamper Protection.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
        }
    })

    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
            return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Vas a DESACTIVAR Windows Defender. El equipo quedara sin proteccion antivirus.`n`n¿Continuar?",
            "Confirmar", "YesNo", "Warning")
        if ($confirm -ne "Yes") { return }

        $btnActivar.Enabled = $false; $btnDesactivar.Enabled = $false
        $lblDetalle.Text = "Desactivando..."
        $form.Refresh()
        $log = Disable-Defender
        Start-Sleep -Seconds 2
        Update-StatusUI
        $btnActivar.Enabled = $true; $btnDesactivar.Enabled = $true

        $s = Get-DefenderStatus
        if ($s -and -not $s.AntivirusEnabled) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender DESACTIVADO correctamente.`n`n$log", "Listo", "OK", "Information") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la desactivacion. Desactiva Tamper Protection e intentalo de nuevo.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
        }
    })

    $btnSalir.Add_Click({ $form.Close() })

    # Refrescar al mostrar
    $form.Add_Shown({ Update-StatusUI })

    [void]$form.ShowDialog()
}

# ──────────────────────────────────────────────
# 8. Icono en la bandeja del sistema
# ──────────────────────────────────────────────
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

# ──────────────────────────────────────────────
# 9. Menu contextual (SOLO TEXTO PLANO, sin Unicode)
# ──────────────────────────────────────────────
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

$miActivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miActivar.Text = "Activar Windows Defender"
$miActivar.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
        return
    }
    $script:notifyIcon.Text = "Activando..."
    $null = Enable-Defender
    Start-Sleep -Seconds 2
    $s = Get-DefenderStatus
    if ($s -and $s.AntivirusEnabled) {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "Activado correctamente.", "Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "No se pudo confirmar la activacion.", "Warning")
    }
    $script:notifyIcon.Text = "Control de Seguridad de Windows"
})

$miDesactivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miDesactivar.Text = "Desactivar Windows Defender"
$miDesactivar.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
        return
    }
    $script:notifyIcon.Text = "Desactivando..."
    $null = Disable-Defender
    Start-Sleep -Seconds 2
    $s = Get-DefenderStatus
    if ($s -and -not $s.AntivirusEnabled) {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "Desactivado correctamente.", "Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "No se pudo confirmar la desactivacion.", "Warning")
    }
    $script:notifyIcon.Text = "Control de Seguridad de Windows"
})

$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

$script:notifyIcon.ContextMenuStrip = $menu

# Clic izquierdo -> abre el panel visual
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

# ──────────────────────────────────────────────
# 10. Tooltip inicial
# ──────────────────────────────────────────────
$init = Get-DefenderStatus
if ($init) {
    $estado = if ($init.AntivirusEnabled) { "ACTIVADO" } else { "DESACTIVADO" }
    $script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estado", "Info")
}

# ──────────────────────────────────────────────
# 11. Bucle de mensajes
# ──────────────────────────────────────────────
[System.Windows.Forms.Application]::Run()