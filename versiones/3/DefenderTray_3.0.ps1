<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Icono en la bandeja con menu contextual en texto plano (sin caracteres especiales).
    - Modal visual compacto y colorido con botones para Activar / Desactivar / Salir.
    - Los botones se habilitan o deshabilitan automaticamente segun el estado actual.
    - Verificacion del estado tras cada accion.
    - Agrega una exclusion en Windows Defender para que el script no sea detenido.
    - Ventana "Acerca de..." con datos del autor.
    - Deteccion del sistema operativo en ejecucion.
.NOTES
    Ejecutar como Administrador.
    Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).
    Creado por: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
#>

# ══════════════════════════════════════════════════════════════════
# 1. ENSAMBLADOS NECESARIOS PARA WINDOWS FORMS
# ══════════════════════════════════════════════════════════════════
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ══════════════════════════════════════════════════════════════════
# 2. PALETA DE COLORES (TEMA VISUAL)
# ══════════════════════════════════════════════════════════════════
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
    BtnBlue       = [System.Drawing.Color]::FromArgb(0, 123, 255)
    BtnBlueHover  = [System.Drawing.Color]::FromArgb(0, 98, 204)
    Border        = [System.Drawing.Color]::FromArgb(222, 226, 230)
}

# ══════════════════════════════════════════════════════════════════
# 3. FUNCION: OBTENER ESTADO DE WINDOWS DEFENDER
#    Consulta el estado actual del antivirus.
#    Devuelve un objeto con las propiedades AntivirusEnabled,
#    RealTimeProtectionEnabled, AMServiceEnabled, IsTamperProtected.
#    Si no se puede consultar, devuelve $null.
# ══════════════════════════════════════════════════════════════════
function Get-DefenderStatus {
    try {
        # En Windows 10/11 se puede usar Get-MpComputerStatus
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $status = Get-MpComputerStatus -ErrorAction Stop
            return [PSCustomObject]@{
                AntivirusEnabled          = [bool]$status.AntivirusEnabled
                RealTimeProtectionEnabled = [bool]$status.RealTimeProtectionEnabled
                AMServiceEnabled          = [bool]$status.AMServiceEnabled
                IsTamperProtected         = [bool]$status.IsTamperProtected
                Source                    = "Get-MpComputerStatus"
            }
        }
        else {
            # Fallback para Windows 7/8/8.1: consultar el servicio WinDefend
            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                AntivirusEnabled          = ($svc.Status -eq 'Running')
                RealTimeProtectionEnabled = ($svc.Status -eq 'Running')
                AMServiceEnabled          = ($svc.Status -eq 'Running')
                IsTamperProtected         = $false
                Source                    = "Service WinDefend"
            }
        }
    }
    catch {
        return $null
    }
}

# ══════════════════════════════════════════════════════════════════
# 4. FUNCION: DESACTIVAR WINDOWS DEFENDER
#    Detiene el servicio, deshabilita el inicio automatico,
#    desactiva el monitoreo en tiempo real y crea las claves
#    de registro de politica para desactivacion permanente.
#    Devuelve un log con los pasos realizados.
# ══════════════════════════════════════════════════════════════════
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList

    # 4.1 Desactivar monitoreo en tiempo real (Windows 8/10/11)
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: DESACTIVADO")
        }
    }
    catch { [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)") }

    # 4.2 Detener y deshabilitar el servicio WinDefend
    try {
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service  -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: DETENIDO / DESHABILITADO")
    }
    catch { [void]$log.Add("Aviso (servicio): $($_.Exception.Message)") }

    # 4.3 Crear claves de registro para desactivacion permanente
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    try {
        New-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: = 1")
    }
    catch { [void]$log.Add("Aviso (registro): $($_.Exception.Message)") }

    # 4.4 Detener servicios relacionados (si existen)
    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
            [void]$log.Add("Servicio ${svcName}: DETENIDO / DESHABILITADO")
        }
        catch { }
    }

    return ($log -join "`n")
}

# ══════════════════════════════════════════════════════════════════
# 5. FUNCION: ACTIVAR WINDOWS DEFENDER
#    Elimina las claves de registro de politica, reactiva el
#    servicio y vuelve a activar el monitoreo en tiempo real.
#    Devuelve un log con los pasos realizados.
# ══════════════════════════════════════════════════════════════════
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    # 5.1 Eliminar claves de registro que bloquean Defender
    try {
        Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Force -ErrorAction SilentlyContinue
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: ELIMINADOS")
    }
    catch { [void]$log.Add("Aviso (registro): $($_.Exception.Message)") }

    # 5.2 Reactivar el servicio WinDefend
    try {
        Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: INICIADO / AUTOMATICO")
    }
    catch { [void]$log.Add("Aviso (servicio): $($_.Exception.Message)") }

    # 5.3 Reactivar monitoreo en tiempo real (Windows 8/10/11)
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: ACTIVADO")
        }
    }
    catch { [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)") }

    return ($log -join "`n")
}

# ══════════════════════════════════════════════════════════════════
# 6. FUNCION: COMPROBAR PERMISOS DE ADMINISTRADOR
#    Devuelve $true si el usuario actual es Administrador.
# ══════════════════════════════════════════════════════════════════
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ══════════════════════════════════════════════════════════════════
# 7. FUNCION: OBTENER INFORMACION DEL SISTEMA OPERATIVO
#    Devuelve un objeto con Caption, Version y BuildNumber.
#    Si no se puede consultar, devuelve "Desconocido".
# ══════════════════════════════════════════════════════════════════
function Get-OSInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{
            Caption     = $os.Caption
            Version     = $os.Version
            BuildNumber = $os.BuildNumber
        }
    }
    catch {
        return [PSCustomObject]@{
            Caption     = "Desconocido"
            Version     = "Desconocido"
            BuildNumber = "Desconocido"
        }
    }
}

# ══════════════════════════════════════════════════════════════════
# 8. FUNCION: AGREGAR EXCLUSION EN WINDOWS DEFENDER
#    Agrega la carpeta del script como exclusion para que
#    Defender no lo detenga ni lo elimine.
# ══════════════════════════════════════════════════════════════════
function Add-DefenderExclusion {
    try {
        # Obtener la ruta de la carpeta donde se encuentra el script
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = (Get-Location).Path
        }

        # Verificar si Set-MpPreference esta disponible (Windows 8+)
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            # Agregar la carpeta como exclusion
            Add-MpPreference -ExclusionPath $scriptPath -Force -ErrorAction Stop
            Write-Host "Exclusion agregada correctamente para: $scriptPath" -ForegroundColor Green
            return $true
        }
        else {
            # En Windows 7 no existe Add-MpPreference
            Write-Host "Windows 7 no soporta exclusiones via PowerShell. Se omite." -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "No se pudo agregar la exclusion: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════
# 9. FUNCION: MOSTRAR PANEL DE CONTROL VISUAL
#    Crea un formulario compacto y colorido con:
#      - Cabecera que cambia de color segun el estado.
#      - Tarjeta con el estado actual y detalles.
#      - Botones para ACTIVAR, DESACTIVAR, ACERCA DE y SALIR.
#    Los botones de activar/desactivar se habilitan o deshabilitan
#    automaticamente segun el estado actual de Defender.
# ══════════════════════════════════════════════════════════════════
function Show-DefenderPanel {

    # ── Crear formulario principal ──
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.Size            = New-Object System.Drawing.Size(360, 420)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = $script:Colors.Background
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon            = [System.Drawing.SystemIcons]::Shield

    # ── Cabecera coloreada ──
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock      = "Top"
    $header.Height    = 60
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
    $card.Size        = New-Object System.Drawing.Size(315, 85)
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
    $lblDetalle.Location  = New-Object System.Drawing.Point(12, 60)
    $card.Controls.Add($lblDetalle)

    # ── Funcion auxiliar para crear botones de color ──
    function New-ColorButton {
        param($Texto, $Color, $Hover, $Y, $Ancho = 315)
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

    # ── Crear botones ──
    $btnActivar    = New-ColorButton "ACTIVAR PROTECCIÓN"    $script:Colors.BtnGreen $script:Colors.BtnGreenHover 175
    $btnDesactivar = New-ColorButton "DESACTIVAR PROTECCIÓN" $script:Colors.BtnRed   $script:Colors.BtnRedHover   220
    $btnAcerca     = New-ColorButton "Acerca de..."          $script:Colors.BtnBlue  $script:Colors.BtnBlueHover  265
    $btnSalir      = New-ColorButton "SALIR"                 $script:Colors.BtnGray  $script:Colors.BtnGrayHover  310

    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnAcerca)
    $form.Controls.Add($btnSalir)

    # ── Funcion interna: actualizar interfaz segun estado ──
    #    - Cambia color de cabecera.
    #    - Actualiza etiquetas.
    #    - Habilita/deshabilita botones segun corresponda.
    function Update-StatusUI {
        $s = Get-DefenderStatus
        if ($null -eq $s) {
            $header.BackColor   = $script:Colors.HeaderUnknown
            $lblValor.Text      = "DESCONOCIDO"
            $lblValor.ForeColor = $script:Colors.HeaderUnknown
            $lblDetalle.Text    = "No se pudo consultar el estado."
            $btnActivar.Enabled    = $false
            $btnDesactivar.Enabled = $false
            return
        }

        if ($s.AntivirusEnabled) {
            # Defender ACTIVADO: cabecera verde, boton activar deshabilitado
            $header.BackColor   = $script:Colors.HeaderOk
            $lblValor.Text      = "ACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderOk
            $lblDetalle.Text    = "Tiempo real: $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'})  |  Tamper: $(if($s.IsTamperProtected){'ON'}else{'OFF'})"
            $btnActivar.Enabled    = $false   # Ya esta activado, no se puede activar de nuevo
            $btnDesactivar.Enabled = $true    # Si se puede desactivar
        }
        else {
            # Defender DESACTIVADO: cabecera roja, boton desactivar deshabilitado
            $header.BackColor   = $script:Colors.HeaderWarn
            $lblValor.Text      = "DESACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderWarn
            $lblDetalle.Text    = "Antivirus inactivo. Sistema sin protección."
            $btnActivar.Enabled    = $true    # Si se puede activar
            $btnDesactivar.Enabled = $false   # Ya esta desactivado, no se puede desactivar de nuevo
        }
    }

    # ── Evento: boton ACTIVAR PROTECCION ──
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

        $s = Get-DefenderStatus
        if ($s -and $s.AntivirusEnabled) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender ACTIVADO correctamente.`n`n$log", "Listo", "OK", "Information") | Out-Null
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la activacion. Reinicia el equipo o desactiva Tamper Protection.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
        }
    })

    # ── Evento: boton DESACTIVAR PROTECCION ──
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

        $s = Get-DefenderStatus
        if ($s -and -not $s.AntivirusEnabled) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender DESACTIVADO correctamente.`n`n$log", "Listo", "OK", "Information") | Out-Null
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la desactivacion. Desactiva Tamper Protection e intentalo de nuevo.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
        }
    })

    # ── Evento: boton ACERCA DE... ──
    $btnAcerca.Add_Click({
        # Obtener informacion del sistema operativo
        $osInfo = Get-OSInfo

        $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 2.0
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

────────────────────────────────────
Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Descripcion:
Utilidad de bandeja del sistema para activar
o desactivar Windows Defender de forma rapida
y visual. Incluye verificacion automatica del
estado y exclusion para evitar que el antivirus
detenga la aplicacion.

Compatible con:
Windows 7, 8, 8.1, 10 y 11
(hasta 24H2, 25H2 y 26H2)
────────────────────────────────────

© 2026 - Todos los derechos reservados
"@

        [System.Windows.Forms.MessageBox]::Show(
            $acercaTexto,
            "Acerca de...",
            "OK",
            "Information"
        ) | Out-Null
    })

    # ── Evento: boton SALIR ──
    $btnSalir.Add_Click({ $form.Close() })

    # ── Refrescar interfaz al mostrar el formulario ──
    $form.Add_Shown({ Update-StatusUI })

    # ── Mostrar formulario como dialogo modal ──
    [void]$form.ShowDialog()
}

# ══════════════════════════════════════════════════════════════════
# 10. AGREGAR EXCLUSION EN WINDOWS DEFENDER AL INICIAR
#     Esto evita que Defender detenga o elimine el script.
#     Se ejecuta automaticamente al arrancar la aplicacion.
# ══════════════════════════════════════════════════════════════════
if (Test-Admin) {
    Add-DefenderExclusion
}
else {
    Write-Host "Ejecuta como Administrador para agregar la exclusion automaticamente." -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════════
# 11. CREAR ICONO EN LA BANDEJA DEL SISTEMA
# ══════════════════════════════════════════════════════════════════
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

# ══════════════════════════════════════════════════════════════════
# 12. MENU CONTEXTUAL (SOLO TEXTO PLANO, SIN UNICODE)
#     Opciones: Abrir panel, Activar, Desactivar, Acerca de, Salir.
# ══════════════════════════════════════════════════════════════════
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# 12.1 Abrir panel de control
$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

# 12.2 Activar Windows Defender
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
    }
    else {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "No se pudo confirmar la activacion.", "Warning")
    }
    $script:notifyIcon.Text = "Control de Seguridad de Windows"
})

# 12.3 Desactivar Windows Defender
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
    }
    else {
        $script:notifyIcon.ShowBalloonTip(4000, "Windows Defender", "No se pudo confirmar la desactivacion.", "Warning")
    }
    $script:notifyIcon.Text = "Control de Seguridad de Windows"
})

# 12.4 Acerca de...
$miAcerca = New-Object System.Windows.Forms.ToolStripMenuItem
$miAcerca.Text = "Acerca de..."
$miAcerca.Add_Click({
    $osInfo = Get-OSInfo
    $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.0
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Compatible con:
Windows 7, 8, 8.1, 10 y 11
"@
    [System.Windows.Forms.MessageBox]::Show($acercaTexto, "Acerca de...", "OK", "Information") | Out-Null
})

# 12.5 Salir
$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# ── Agregar elementos al menu con separadores ──
[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miAcerca)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

$script:notifyIcon.ContextMenuStrip = $menu

# ══════════════════════════════════════════════════════════════════
# 13. EVENTO: CLIC IZQUIERDO EN EL ICONO
#     Abre el panel de control visual.
# ══════════════════════════════════════════════════════════════════
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

# ══════════════════════════════════════════════════════════════════
# 14. TOOLTIP INICIAL CON EL ESTADO ACTUAL
# ══════════════════════════════════════════════════════════════════
$init = Get-DefenderStatus
if ($init) {
    $estado = if ($init.AntivirusEnabled) { "ACTIVADO" } else { "DESACTIVADO" }
    $script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estado", "Info")
}

# ══════════════════════════════════════════════════════════════════
# 15. BUCLE DE MENSAJES (MANTIENE LA APP EN EJECUCION)
# ══════════════════════════════════════════════════════════════════
[System.Windows.Forms.Application]::Run()