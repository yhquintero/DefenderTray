<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Verificacion INICIAL del estado al arrancar (obligatoria, con mensaje claro).
    - Icono en la bandeja con menu contextual en texto plano.
    - Panel visual compacto con los 4 botones SIEMPRE visibles:
        ACTIVAR PROTECCION / DESACTIVAR PROTECCION / Acerca de... / SALIR.
    - Los botones cambian de color segun el estado (verde/rojo = accion disponible,
      gris = accion no aplicable).
    - Al hacer clic en un boton no aplicable, se informa al usuario con un mensaje.
    - Verificacion del estado tras cada accion.
    - Agrega una exclusion en Windows Defender para que el script no sea detenido.
    - Detecta y avisa si la Proteccion contra alteraciones (Tamper Protection)
      esta activa y explica como desactivarla.
    - Ventana "Acerca de..." con datos del autor y sistema operativo.
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
    HeaderOk        = [System.Drawing.Color]::FromArgb(34, 139, 34)     # Verde
    HeaderWarn      = [System.Drawing.Color]::FromArgb(178, 34, 34)     # Rojo
    HeaderUnknown   = [System.Drawing.Color]::FromArgb(70, 70, 70)      # Gris
    Background      = [System.Drawing.Color]::FromArgb(245, 247, 250)
    CardBg          = [System.Drawing.Color]::White
    TextDark        = [System.Drawing.Color]::FromArgb(33, 37, 41)
    TextMuted       = [System.Drawing.Color]::FromArgb(108, 117, 125)
    BtnGreen        = [System.Drawing.Color]::FromArgb(40, 167, 69)
    BtnGreenHover   = [System.Drawing.Color]::FromArgb(33, 136, 56)
    BtnRed          = [System.Drawing.Color]::FromArgb(220, 53, 69)
    BtnRedHover     = [System.Drawing.Color]::FromArgb(178, 40, 54)
    BtnGray         = [System.Drawing.Color]::FromArgb(200, 200, 200)
    BtnGrayText     = [System.Drawing.Color]::FromArgb(120, 120, 120)
    BtnGrayHover    = [System.Drawing.Color]::FromArgb(180, 180, 180)
    BtnBlue         = [System.Drawing.Color]::FromArgb(0, 123, 255)
    BtnBlueHover    = [System.Drawing.Color]::FromArgb(0, 98, 204)
    BtnDarkGray     = [System.Drawing.Color]::FromArgb(108, 117, 125)
    BtnDarkGrayHov  = [System.Drawing.Color]::FromArgb(84, 91, 98)
    Border          = [System.Drawing.Color]::FromArgb(222, 226, 230)
}

# ══════════════════════════════════════════════════════════════════
# 3. FUNCION: OBTENER ESTADO DE WINDOWS DEFENDER
#    Devuelve un objeto con:
#       AntivirusEnabled, RealTimeProtectionEnabled,
#       AMServiceEnabled, IsTamperProtected, Source.
#    Si no se puede consultar, devuelve $null.
# ══════════════════════════════════════════════════════════════════
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
        }
        else {
            # Fallback para Windows 7/8/8.1
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
#    Si Tamper Protection esta activa, NO intenta nada y devuelve
#    un mensaje explicativo. En caso contrario, detiene el servicio,
#    deshabilita el inicio automatico, desactiva el monitoreo en
#    tiempo real y crea las claves de registro de politica.
# ══════════════════════════════════════════════════════════════════
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList

    # 4.0 Verificar Tamper Protection (bloquea cambios por diseno)
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tpStatus = Get-MpComputerStatus -ErrorAction Stop
            if ($tpStatus.IsTamperProtected) {
                [void]$log.Add("ERROR: La Proteccion contra alteraciones (Tamper Protection) esta ACTIVADA.")
                [void]$log.Add("")
                [void]$log.Add("Pasos para desactivarla manualmente:")
                [void]$log.Add("  1. Abre Seguridad de Windows.")
                [void]$log.Add("  2. Ve a Proteccion antivirus y contra amenazas.")
                [void]$log.Add("  3. Entra en 'Administrar la configuracion'.")
                [void]$log.Add("  4. Desactiva 'Proteccion contra alteraciones'.")
                [void]$log.Add("  5. Vuelve a intentar desactivar el antivirus.")
                return ($log -join "`n")
            }
        }
    } catch {}

    # 4.1 Desactivar monitoreo en tiempo real
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

    # 4.4 Detener servicios relacionados
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
# ══════════════════════════════════════════════════════════════════
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    # 5.0 Avisar si Tamper Protection esta activa
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tpStatus = Get-MpComputerStatus -ErrorAction Stop
            if ($tpStatus.IsTamperProtected) {
                [void]$log.Add("ADVERTENCIA: La Proteccion contra alteraciones (Tamper Protection) esta ACTIVADA.")
                [void]$log.Add("Los cambios podrian no aplicarse completamente.")
                [void]$log.Add("")
            }
        }
    } catch {}

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

    # 5.3 Reactivar monitoreo en tiempo real
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
# ══════════════════════════════════════════════════════════════════
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ══════════════════════════════════════════════════════════════════
# 7. FUNCION: OBTENER INFORMACION DEL SISTEMA OPERATIVO
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
#    Evita que Defender detenga o elimine el script.
# ══════════════════════════════════════════════════════════════════
function Add-DefenderExclusion {
    try {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = (Get-Location).Path
        }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $scriptPath -Force -ErrorAction Stop
            Write-Host "Exclusion agregada correctamente para: $scriptPath" -ForegroundColor Green
            return $true
        }
        else {
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
# 9. FUNCION AUXILIAR: CREAR UN BOTON CON COLOR PERSONALIZADO
#    Usa FlatStyle para pintar el fondo y el texto.
#    IMPORTANTE: Nunca se deshabilita (Enabled siempre $true) para
#    evitar que Windows lo pinte invisible (texto blanco sobre
#    fondo claro). En su lugar, se cambia el color y se controla
#    la accion desde el Click.
# ══════════════════════════════════════════════════════════════════
function New-ColorButton {
    param(
        [string]$Texto,
        [System.Drawing.Color]$Color,
        [System.Drawing.Color]$Hover,
        [int]$Y,
        [int]$Ancho = 320,
        [int]$Alto  = 38
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Texto
    $b.Size      = New-Object System.Drawing.Size($Ancho, $Alto)
    $b.Location  = New-Object System.Drawing.Point(15, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Color
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $b.Cursor    = "Hand"
    # Guardamos los colores originales en el Tag para poder restaurarlos
    $b.Tag = @{ Normal = $Color; Hover = $Hover; Enabled = $true }
    return $b
}

# ══════════════════════════════════════════════════════════════════
# 10. FUNCION: APLICAR ESTADO VISUAL A UN BOTON
#     enabled = $true  -> color normal (verde/rojo/azul) y clicable
#     enabled = $false -> color gris claro y clic ignorado
# ══════════════════════════════════════════════════════════════════
function Set-ButtonVisualState {
    param(
        [System.Windows.Forms.Button]$Boton,
        [bool]$Habilitado
    )
    if ($Habilitado) {
        $Boton.BackColor = $Boton.Tag.Normal
        $Boton.ForeColor = [System.Drawing.Color]::White
        $Boton.FlatAppearance.MouseOverBackColor = $Boton.Tag.Hover
        $Boton.Cursor = "Hand"
        $Boton.Tag.Enabled = $true
    }
    else {
        $Boton.BackColor = $script:Colors.BtnGray
        $Boton.ForeColor = $script:Colors.BtnGrayText
        $Boton.FlatAppearance.MouseOverBackColor = $script:Colors.BtnGray
        $Boton.Cursor = "Default"
        $Boton.Tag.Enabled = $false
    }
}

# ══════════════════════════════════════════════════════════════════
# 11. FUNCION: MOSTRAR PANEL DE CONTROL VISUAL
# ══════════════════════════════════════════════════════════════════
function Show-DefenderPanel {

    # ── Formulario principal ──
    # ClientSize define el area util (sin bordes). 360x440 es
    # suficiente para los 4 botones incluso con DPI 125%-150%.
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.ClientSize      = New-Object System.Drawing.Size(360, 440)
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
    $card.Location    = New-Object System.Drawing.Point(15, 72)
    $card.Size        = New-Object System.Drawing.Size(330, 85)
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

    # ── Botones (SIEMPRE visibles, en posiciones fijas) ──
    #    Y: 175, 220, 265, 310  (alto 38, separacion 7)
    $btnActivar    = New-ColorButton "ACTIVAR PROTECCIÓN"    $script:Colors.BtnGreen     $script:Colors.BtnGreenHover 175
    $btnDesactivar = New-ColorButton "DESACTIVAR PROTECCIÓN" $script:Colors.BtnRed       $script:Colors.BtnRedHover   220
    $btnAcerca     = New-ColorButton "Acerca de..."          $script:Colors.BtnBlue      $script:Colors.BtnBlueHover  265
    $btnSalir      = New-ColorButton "SALIR"                 $script:Colors.BtnDarkGray  $script:Colors.BtnDarkGrayHov 310

    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnAcerca)
    $form.Controls.Add($btnSalir)

    # ── Funcion interna: actualizar interfaz segun estado ──
    #    - Cambia color de cabecera.
    #    - Actualiza etiquetas.
    #    - Aplica estado visual a los botones (gris si no aplica).
    function Update-StatusUI {
        $s = Get-DefenderStatus

        if ($null -eq $s) {
            $header.BackColor     = $script:Colors.HeaderUnknown
            $lblValor.Text        = "DESCONOCIDO"
            $lblValor.ForeColor   = $script:Colors.HeaderUnknown
            $lblDetalle.Text      = "No se pudo consultar el estado."
            $lblDetalle.ForeColor = $script:Colors.TextMuted
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
            return
        }

        if ($s.AntivirusEnabled) {
            $header.BackColor   = $script:Colors.HeaderOk
            $lblValor.Text      = "ACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderOk
            $detalle = "Tiempo real: $(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'})  |  Tamper: $(if($s.IsTamperProtected){'ON'}else{'OFF'})"
            if ($s.IsTamperProtected) {
                $lblDetalle.ForeColor = [System.Drawing.Color]::OrangeRed
            } else {
                $lblDetalle.ForeColor = $script:Colors.TextMuted
            }
            $lblDetalle.Text = $detalle
            # ACTIVAR no aplica (ya esta activo) -> gris
            # DESACTIVAR si aplica -> rojo
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $false
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
        }
        else {
            $header.BackColor     = $script:Colors.HeaderWarn
            $lblValor.Text        = "DESACTIVADO"
            $lblValor.ForeColor   = $script:Colors.HeaderWarn
            $lblDetalle.Text      = "Antivirus inactivo. Sistema sin proteccion."
            $lblDetalle.ForeColor = $script:Colors.TextMuted
            # ACTIVAR si aplica -> verde
            # DESACTIVAR no aplica (ya esta inactivo) -> gris
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $false
        }
    }

    # ── Evento: boton ACTIVAR PROTECCION ──
    $btnActivar.Add_Click({
        # Si el boton esta en estado "gris", informar y salir
        if ($btnActivar.Tag.Enabled -eq $false) {
            [System.Windows.Forms.MessageBox]::Show(
                "Windows Defender ya esta ACTIVADO.`nNo es necesario activarlo de nuevo.",
                "Informacion", "OK", "Information") | Out-Null
            return
        }
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
            return
        }
        $lblDetalle.Text = "Activando..."
        $lblDetalle.ForeColor = $script:Colors.TextMuted
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
        # Si el boton esta en estado "gris", informar y salir
        if ($btnDesactivar.Tag.Enabled -eq $false) {
            [System.Windows.Forms.MessageBox]::Show(
                "Windows Defender ya esta DESACTIVADO.`nNo es necesario desactivarlo de nuevo.",
                "Informacion", "OK", "Information") | Out-Null
            return
        }
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.", "Permisos", "OK", "Warning") | Out-Null
            return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Vas a DESACTIVAR Windows Defender. El equipo quedara sin proteccion antivirus.`n`n¿Continuar?",
            "Confirmar", "YesNo", "Warning")
        if ($confirm -ne "Yes") { return }

        $lblDetalle.Text = "Desactivando..."
        $lblDetalle.ForeColor = $script:Colors.TextMuted
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
        $osInfo = Get-OSInfo
        # Guiones ASCII simples para evitar problemas de codificacion
        $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.1
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

------------------------------------
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
------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($acercaTexto, "Acerca de...", "OK", "Information") | Out-Null
    })

    # ── Evento: boton SALIR ──
    $btnSalir.Add_Click({ $form.Close() })

    # ── Refrescar interfaz al mostrar el formulario ──
    $form.Add_Shown({ Update-StatusUI })

    # ── Mostrar formulario como dialogo modal ──
    [void]$form.ShowDialog()
}

# ══════════════════════════════════════════════════════════════════
# 12. VERIFICACION INICIAL OBLIGATORIA
#     ANTES de cualquier otra cosa, se consulta el estado de
#     Windows Defender y se muestra al usuario con claridad.
#     Esto garantiza que la app arranque siempre con informacion
#     correcta sobre el estado real del sistema.
# ══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Control de Seguridad de Windows Defender v3.1" -ForegroundColor Cyan
Write-Host "  Ing. Yosvany Hernandez Quintero" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Verificando permisos de Administrador..." -ForegroundColor Yellow
if (Test-Admin) {
    Write-Host "      OK - Ejecutando como Administrador." -ForegroundColor Green
} else {
    Write-Host "      ADVERTENCIA - No se ejecuta como Administrador." -ForegroundColor Red
    Write-Host "      Las acciones de activar/desactivar pueden fallar." -ForegroundColor Red
}

Write-Host "[2/3] Agregando exclusion en Windows Defender..." -ForegroundColor Yellow
if (Test-Admin) {
    Add-DefenderExclusion | Out-Null
} else {
    Write-Host "      Omitido (se requiere Administrador)." -ForegroundColor Yellow
}

Write-Host "[3/3] Consultando estado inicial de Windows Defender..." -ForegroundColor Yellow
$script:InitialStatus = Get-DefenderStatus

if ($null -eq $script:InitialStatus) {
    Write-Host "      No se pudo determinar el estado de Defender." -ForegroundColor Red
    $estadoInicial = "DESCONOCIDO"
    $detalleInicial = "No se pudo consultar el estado."
    $colorInicial = [System.Drawing.Color]::Gray
}
elseif ($script:InitialStatus.AntivirusEnabled) {
    Write-Host "      Estado: ACTIVADO" -ForegroundColor Green
    $estadoInicial = "ACTIVADO"
    $detalleInicial = "Tiempo real: $(if($script:InitialStatus.RealTimeProtectionEnabled){'ON'}else{'OFF'})  |  Tamper: $(if($script:InitialStatus.IsTamperProtected){'ON'}else{'OFF'})"
    $colorInicial = [System.Drawing.Color]::ForestGreen
}
else {
    Write-Host "      Estado: DESACTIVADO" -ForegroundColor Red
    $estadoInicial = "DESACTIVADO"
    $detalleInicial = "El antivirus esta inactivo."
    $colorInicial = [System.Drawing.Color]::Firebrick
}
Write-Host ""

# Mensaje emergente con el estado inicial
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
Haz clic IZQUIERDO en el icono para abrir el panel.
Haz clic DERECHO para ver el menu de opciones.
"@

[System.Windows.Forms.MessageBox]::Show(
    $mensajeInicial,
    "Verificacion inicial - Windows Defender",
    "OK",
    "Information") | Out-Null

# ══════════════════════════════════════════════════════════════════
# 13. CREAR ICONO EN LA BANDEJA DEL SISTEMA
# ══════════════════════════════════════════════════════════════════
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

# ══════════════════════════════════════════════════════════════════
# 14. MENU CONTEXTUAL (CLIC DERECHO)
#     Las opciones Activar/Desactivar se habilitan o deshabilitan
#     dinamicamente al abrir el menu (evento Opening).
# ══════════════════════════════════════════════════════════════════
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# 14.1 Abrir panel de control
$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

# 14.2 Activar Windows Defender
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

# 14.3 Desactivar Windows Defender
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

# 14.4 Acerca de...
$miAcerca = New-Object System.Windows.Forms.ToolStripMenuItem
$miAcerca.Text = "Acerca de..."
$miAcerca.Add_Click({
    $osInfo = Get-OSInfo
    $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.1
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

------------------------------------
Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)
------------------------------------

Compatible con:
Windows 7, 8, 8.1, 10 y 11
(hasta 24H2, 25H2 y 26H2)
"@
    [System.Windows.Forms.MessageBox]::Show($acercaTexto, "Acerca de...", "OK", "Information") | Out-Null
})

# 14.5 Salir
$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# Agregar elementos al menu
[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miAcerca)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

# ── EVENTO OPENING: ajustar opciones del menu segun estado ──
$menu.Add_Opening({
    $s = Get-DefenderStatus
    if ($null -eq $s) {
        $miActivar.Enabled    = $true
        $miDesactivar.Enabled = $true
    }
    elseif ($s.AntivirusEnabled) {
        $miActivar.Enabled    = $false   # Ya esta activado
        $miDesactivar.Enabled = $true
    }
    else {
        $miActivar.Enabled    = $true
        $miDesactivar.Enabled = $false   # Ya esta desactivado
    }
})

$script:notifyIcon.ContextMenuStrip = $menu

# ══════════════════════════════════════════════════════════════════
# 15. EVENTO: CLIC IZQUIERDO EN EL ICONO (abre el panel)
# ══════════════════════════════════════════════════════════════════
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

# ══════════════════════════════════════════════════════════════════
# 16. TOOLTIP INICIAL EN LA BANDEJA
# ══════════════════════════════════════════════════════════════════
$script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estadoInicial", "Info")

# ══════════════════════════════════════════════════════════════════
# 17. BUCLE DE MENSAJES (MANTIENE LA APP EN EJECUCION)
# ══════════════════════════════════════════════════════════════════
[System.Windows.Forms.Application]::Run()