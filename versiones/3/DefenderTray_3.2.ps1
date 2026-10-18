<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Verificacion INICIAL del estado al arrancar (obligatoria).
    - Icono en la bandeja con menu contextual en texto plano.
    - Panel visual con 5 botones siempre visibles:
        ACTIVAR PROTECCION / DESACTIVAR PROTECCION / Ver Registro /
        Acerca de... / SALIR.
    - Los botones cambian de color segun el estado.
    - Visor de registro integrado en la propia app.
    - Guardado automatico de log en %LOCALAPPDATA%\DefenderTray\Logs\.
    - Exclusion automatica en Windows Defender.
    - Detecta Tamper Protection y explica como desactivarla.
.NOTES
    Ejecutar como Administrador.
    Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).
    Creado por: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
    Version: 3.2
#>

# ==================================================================
# 1. ENSAMBLADOS NECESARIOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================================================================
# 2. CONSTANTES DE TEXTO
#    La letra O con tilde se construye con [char]0x00D3 para que
#    el archivo .ps1 pueda guardarse como ASCII puro y no se
#    corrompa al ser leido por Windows PowerShell 5.1.
# ==================================================================
$script:O_ACCENT       = [char]0x00D3
$script:TXT_PROTECCION = "PROTECCI" + $script:O_ACCENT + "N"
$script:TXT_ACTIVAR    = "ACTIVAR " + $script:TXT_PROTECCION
$script:TXT_DESACTIVAR = "DESACTIVAR " + $script:TXT_PROTECCION

# ==================================================================
# 3. RUTAS DEL SISTEMA DE LOG
# ==================================================================
$script:LogFolder = Join-Path $env:LOCALAPPDATA "DefenderTray\Logs"
$script:LogFile   = Join-Path $script:LogFolder ("DefenderTray_{0:yyyy-MM-dd}.log" -f (Get-Date))

# Crear la carpeta de logs si no existe
if (-not (Test-Path $script:LogFolder)) {
    New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
}

# ==================================================================
# 4. FUNCION: ESCRIBIR EN EL REGISTRO
#    Guarda la linea en el archivo de log. Nunca lanza error.
# ==================================================================
function Write-AppLog {
    param(
        [string]$Mensaje,
        [string]$Nivel = "INFO"
    )
    try {
        $linea = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Nivel, $Mensaje
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# ==================================================================
# 5. PALETA DE COLORES
# ==================================================================
$script:Colors = @{
    HeaderOk       = [System.Drawing.Color]::FromArgb(34, 139, 34)
    HeaderWarn     = [System.Drawing.Color]::FromArgb(178, 34, 34)
    HeaderUnknown  = [System.Drawing.Color]::FromArgb(70, 70, 70)
    Background     = [System.Drawing.Color]::FromArgb(245, 247, 250)
    CardBg         = [System.Drawing.Color]::White
    TextDark       = [System.Drawing.Color]::FromArgb(33, 37, 41)
    TextMuted      = [System.Drawing.Color]::FromArgb(108, 117, 125)
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
    Border         = [System.Drawing.Color]::FromArgb(222, 226, 230)
}

# ==================================================================
# 6. FUNCION: OBTENER ESTADO DE WINDOWS DEFENDER
# ==================================================================
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

# ==================================================================
# 7. FUNCION: DESACTIVAR WINDOWS DEFENDER
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList

    # Verificar Tamper Protection
    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tpStatus = Get-MpComputerStatus -ErrorAction Stop
            if ($tpStatus.IsTamperProtected) {
                $msg = "Tamper Protection ACTIVA: no se puede desactivar Defender."
                [void]$log.Add("ERROR: La Proteccion contra alteraciones (Tamper Protection) esta ACTIVADA.")
                [void]$log.Add("")
                [void]$log.Add("Pasos para desactivarla manualmente:")
                [void]$log.Add("  1. Abre Seguridad de Windows.")
                [void]$log.Add("  2. Ve a Proteccion antivirus y contra amenazas.")
                [void]$log.Add("  3. Entra en 'Administrar la configuracion'.")
                [void]$log.Add("  4. Desactiva 'Proteccion contra alteraciones'.")
                [void]$log.Add("  5. Vuelve a intentar desactivar el antivirus.")
                Write-AppLog $msg "ERROR"
                return ($log -join "`n")
            }
        }
    } catch {}

    Write-AppLog "Iniciando desactivacion de Windows Defender..." "INFO"

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: DESACTIVADO")
            Write-AppLog "Monitoreo en tiempo real desactivado." "INFO"
        }
    } catch {
        [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)")
        Write-AppLog "Error al desactivar monitoreo: $($_.Exception.Message)" "WARN"
    }

    try {
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service  -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: DETENIDO / DESHABILITADO")
        Write-AppLog "Servicio WinDefend detenido y deshabilitado." "INFO"
    } catch {
        [void]$log.Add("Aviso (servicio): $($_.Exception.Message)")
        Write-AppLog "Error al detener WinDefend: $($_.Exception.Message)" "WARN"
    }

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    try {
        New-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: = 1")
        Write-AppLog "Claves de registro establecidas a 1." "INFO"
    } catch {
        [void]$log.Add("Aviso (registro): $($_.Exception.Message)")
        Write-AppLog "Error al escribir registro: $($_.Exception.Message)" "WARN"
    }

    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
            [void]$log.Add("Servicio ${svcName}: DETENIDO / DESHABILITADO")
            Write-AppLog "Servicio $svcName detenido y deshabilitado." "INFO"
        } catch { }
    }

    return ($log -join "`n")
}

# ==================================================================
# 8. FUNCION: ACTIVAR WINDOWS DEFENDER
# ==================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    Write-AppLog "Iniciando activacion de Windows Defender..." "INFO"

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tpStatus = Get-MpComputerStatus -ErrorAction Stop
            if ($tpStatus.IsTamperProtected) {
                [void]$log.Add("ADVERTENCIA: Tamper Protection ACTIVA. Los cambios podrian no aplicarse por completo.")
                Write-AppLog "Tamper Protection activa durante activacion." "WARN"
            }
        }
    } catch {}

    try {
        Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Force -ErrorAction SilentlyContinue
        [void]$log.Add("Registro DisableAntiSpyware/AntiVirus: ELIMINADOS")
        Write-AppLog "Claves de registro eliminadas." "INFO"
    } catch {
        [void]$log.Add("Aviso (registro): $($_.Exception.Message)")
        Write-AppLog "Error al eliminar registro: $($_.Exception.Message)" "WARN"
    }

    try {
        Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: INICIADO / AUTOMATICO")
        Write-AppLog "Servicio WinDefend iniciado." "INFO"
    } catch {
        [void]$log.Add("Aviso (servicio): $($_.Exception.Message)")
        Write-AppLog "Error al iniciar WinDefend: $($_.Exception.Message)" "WARN"
    }

    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction Stop
            [void]$log.Add("Monitoreo en tiempo real: ACTIVADO")
            Write-AppLog "Monitoreo en tiempo real reactivado." "INFO"
        }
    } catch {
        [void]$log.Add("Aviso (monitoreo): $($_.Exception.Message)")
        Write-AppLog "Error al reactivar monitoreo: $($_.Exception.Message)" "WARN"
    }

    return ($log -join "`n")
}

# ==================================================================
# 9. FUNCION: COMPROBAR PERMISOS DE ADMINISTRADOR
# ==================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ==================================================================
# 10. FUNCION: OBTENER INFORMACION DEL SISTEMA OPERATIVO
# ==================================================================
function Get-OSInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [PSCustomObject]@{
            Caption     = $os.Caption
            Version     = $os.Version
            BuildNumber = $os.BuildNumber
        }
    } catch {
        return [PSCustomObject]@{
            Caption     = "Desconocido"
            Version     = "Desconocido"
            BuildNumber = "Desconocido"
        }
    }
}

# ==================================================================
# 11. FUNCION: AGREGAR EXCLUSION EN WINDOWS DEFENDER
#     Usa $PSScriptRoot, que siempre apunta a la carpeta del script.
# ==================================================================
function Add-DefenderExclusion {
    try {
        $scriptPath = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = (Get-Location).Path
        }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $scriptPath -Force -ErrorAction Stop
            Write-AppLog "Exclusion agregada: $scriptPath" "INFO"
            return $true
        } else {
            Write-AppLog "Windows 7 no soporta exclusiones via PowerShell." "WARN"
            return $false
        }
    } catch {
        Write-AppLog "Error al agregar exclusion: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ==================================================================
# 12. FUNCION AUXILIAR: CREAR UN BOTON CON COLOR PERSONALIZADO
#     Nunca se deshabilita con Enabled=$false (que en WinForms pinta
#     el texto blanco sobre fondo claro y lo vuelve invisible).
#     En su lugar se cambia el color y se controla la accion desde
#     el Click.
# ==================================================================
function New-ColorButton {
    param(
        [string]$Texto,
        [System.Drawing.Color]$Color,
        [System.Drawing.Color]$Hover,
        [int]$Y,
        [int]$Ancho = 320,
        [int]$Alto  = 36
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
    $b.Tag = @{ Normal = $Color; Hover = $Hover; Habilitado = $true }
    return $b
}

# ==================================================================
# 13. FUNCION: APLICAR ESTADO VISUAL A UN BOTON
# ==================================================================
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
# 14. FUNCION: VISOR DE REGISTRO (LOG)
# ==================================================================
function Show-LogViewer {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text            = "Registro de Actividad - DefenderTray"
    $frm.ClientSize      = New-Object System.Drawing.Size(760, 520)
    $frm.StartPosition   = "CenterScreen"
    $frm.Icon            = [System.Drawing.SystemIcons]::Shield
    $frm.BackColor       = $script:Colors.Background
    $frm.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    # Cabecera
    $pHeader = New-Object System.Windows.Forms.Panel
    $pHeader.Dock = "Top"
    $pHeader.Height = 50
    $pHeader.BackColor = $script:Colors.BtnTeal
    $frm.Controls.Add($pHeader)

    $lblTitulo = New-Object System.Windows.Forms.Label
    $lblTitulo.Text = "Registro de Actividad"
    $lblTitulo.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitulo.ForeColor = [System.Drawing.Color]::White
    $lblTitulo.BackColor = [System.Drawing.Color]::Transparent
    $lblTitulo.AutoSize = $true
    $lblTitulo.Location = New-Object System.Drawing.Point(15, 13)
    $pHeader.Controls.Add($lblTitulo)

    # Caja de texto con el log
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline  = $true
    $txt.ScrollBars = "Both"
    $txt.ReadOnly   = $true
    $txt.WordWrap   = $false
    $txt.Dock       = "Fill"
    $txt.Font       = New-Object System.Drawing.Font("Consolas", 9)
    $txt.BackColor  = [System.Drawing.Color]::FromArgb(28, 32, 38)
    $txt.ForeColor  = [System.Drawing.Color]::FromArgb(130, 230, 130)
    $txt.BorderStyle = "None"

    # Panel contenedor para dar margen
    $pBody = New-Object System.Windows.Forms.Panel
    $pBody.Dock = "Fill"
    $pBody.Padding = New-Object System.Windows.Forms.Padding(10)
    $pBody.Controls.Add($txt)
    $frm.Controls.Add($pBody)
    $pBody.BringToFront()

    # Panel inferior con botones
    $pBottom = New-Object System.Windows.Forms.Panel
    $pBottom.Dock = "Bottom"
    $pBottom.Height = 55
    $pBottom.BackColor = $script:Colors.Background
    $frm.Controls.Add($pBottom)

    $btnRefrescar = New-Object System.Windows.Forms.Button
    $btnRefrescar.Text = "Refrescar"
    $btnRefrescar.Size = New-Object System.Drawing.Size(120, 34)
    $btnRefrescar.Location = New-Object System.Drawing.Point(15, 10)
    $btnRefrescar.FlatStyle = "Flat"
    $btnRefrescar.FlatAppearance.BorderSize = 0
    $btnRefrescar.BackColor = $script:Colors.BtnBlue
    $btnRefrescar.ForeColor = [System.Drawing.Color]::White
    $btnRefrescar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefrescar.Cursor = "Hand"
    $pBottom.Controls.Add($btnRefrescar)

    $btnGuardar = New-Object System.Windows.Forms.Button
    $btnGuardar.Text = "Guardar copia..."
    $btnGuardar.Size = New-Object System.Drawing.Size(140, 34)
    $btnGuardar.Location = New-Object System.Drawing.Point(145, 10)
    $btnGuardar.FlatStyle = "Flat"
    $btnGuardar.FlatAppearance.BorderSize = 0
    $btnGuardar.BackColor = $script:Colors.BtnGreen
    $btnGuardar.ForeColor = [System.Drawing.Color]::White
    $btnGuardar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnGuardar.Cursor = "Hand"
    $pBottom.Controls.Add($btnGuardar)

    $btnAbrirCarpeta = New-Object System.Windows.Forms.Button
    $btnAbrirCarpeta.Text = "Abrir carpeta"
    $btnAbrirCarpeta.Size = New-Object System.Drawing.Size(130, 34)
    $btnAbrirCarpeta.Location = New-Object System.Drawing.Point(295, 10)
    $btnAbrirCarpeta.FlatStyle = "Flat"
    $btnAbrirCarpeta.FlatAppearance.BorderSize = 0
    $btnAbrirCarpeta.BackColor = $script:Colors.BtnTeal
    $btnAbrirCarpeta.ForeColor = [System.Drawing.Color]::White
    $btnAbrirCarpeta.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnAbrirCarpeta.Cursor = "Hand"
    $pBottom.Controls.Add($btnAbrirCarpeta)

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text = "Cerrar"
    $btnCerrar.Size = New-Object System.Drawing.Size(100, 34)
    $btnCerrar.Location = New-Object System.Drawing.Point(645, 10)
    $btnCerrar.Anchor = "Top,Right"
    $btnCerrar.FlatStyle = "Flat"
    $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.BackColor = $script:Colors.BtnDarkGray
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.Cursor = "Hand"
    $pBottom.Controls.Add($btnCerrar)

    # Cargar el log
    function RefrescarLog {
        if (Test-Path $script:LogFile) {
            $contenido = Get-Content -Path $script:LogFile -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($contenido)) {
                $txt.Text = "(Archivo de log vacio)"
            } else {
                $txt.Text = $contenido
            }
        } else {
            $txt.Text = "(No se ha creado el archivo de log todavia.)`r`nUbicacion: $($script:LogFile)"
        }
        $txt.SelectionStart = $txt.Text.Length
        $txt.ScrollToCaret()
    }

    RefrescarLog

    $btnRefrescar.Add_Click({ RefrescarLog })
    $btnGuardar.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = "Guardar copia del registro"
        $dlg.Filter = "Archivos de texto (*.txt)|*.txt|Todos los archivos (*.*)|*.*"
        $dlg.FileName = "DefenderTray_Log_{0:yyyy-MM-dd_HHmmss}.txt" -f (Get-Date)
        if ($dlg.ShowDialog() -eq "OK") {
            try {
                if (Test-Path $script:LogFile) {
                    Copy-Item -Path $script:LogFile -Destination $dlg.FileName -Force
                } else {
                    $txt.Text | Out-File -FilePath $dlg.FileName -Encoding UTF8
                }
                [System.Windows.Forms.MessageBox]::Show("Registro guardado en:`n$($dlg.FileName)", "Guardado", "OK", "Information") | Out-Null
                Write-AppLog "Log exportado a: $($dlg.FileName)" "INFO"
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error al guardar: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
            }
        }
    })
    $btnAbrirCarpeta.Add_Click({
        Start-Process "explorer.exe" -ArgumentList $script:LogFolder
    })
    $btnCerrar.Add_Click({ $frm.Close() })

    [void]$frm.ShowDialog()
}

# ==================================================================
# 15. FUNCION: MOSTRAR PANEL DE CONTROL VISUAL
# ==================================================================
function Show-DefenderPanel {

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.ClientSize      = New-Object System.Drawing.Size(360, 460)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = $script:Colors.Background
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon            = [System.Drawing.SystemIcons]::Shield

    # Cabecera
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

    # Tarjeta de estado
    $card = New-Object System.Windows.Forms.Panel
    $card.Location    = New-Object System.Drawing.Point(15, 72)
    $card.Size        = New-Object System.Drawing.Size(330, 82)
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
    $lblValor.Location  = New-Object System.Drawing.Point(12, 28)
    $card.Controls.Add($lblValor)

    $lblDetalle = New-Object System.Windows.Forms.Label
    $lblDetalle.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDetalle.ForeColor = $script:Colors.TextMuted
    $lblDetalle.AutoSize  = $true
    $lblDetalle.Location  = New-Object System.Drawing.Point(12, 58)
    $card.Controls.Add($lblDetalle)

    # Botones (5 botones, Y = 165, 208, 251, 294, 337)
    $btnActivar    = New-ColorButton $script:TXT_ACTIVAR    $script:Colors.BtnGreen    $script:Colors.BtnGreenHover  165
    $btnDesactivar = New-ColorButton $script:TXT_DESACTIVAR $script:Colors.BtnRed      $script:Colors.BtnRedHover    208
    $btnLog        = New-ColorButton "Ver Registro"         $script:Colors.BtnTeal     $script:Colors.BtnTealHover   251
    $btnAcerca     = New-ColorButton "Acerca de..."         $script:Colors.BtnBlue     $script:Colors.BtnBlueHover   294
    $btnSalir      = New-ColorButton "SALIR"                $script:Colors.BtnDarkGray $script:Colors.BtnDarkGrayHov 337

    $form.Controls.Add($btnActivar)
    $form.Controls.Add($btnDesactivar)
    $form.Controls.Add($btnLog)
    $form.Controls.Add($btnAcerca)
    $form.Controls.Add($btnSalir)

    # Actualizar interfaz segun estado
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
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $false
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
        } else {
            $header.BackColor     = $script:Colors.HeaderWarn
            $lblValor.Text        = "DESACTIVADO"
            $lblValor.ForeColor   = $script:Colors.HeaderWarn
            $lblDetalle.Text      = "Antivirus inactivo. Sistema sin proteccion."
            $lblDetalle.ForeColor = $script:Colors.TextMuted
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $false
        }
    }

    # Evento: Activar
    $btnActivar.Add_Click({
        if ($btnActivar.Tag.Habilitado -eq $false) {
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
            Write-AppLog "Defender activado correctamente." "INFO"
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la activacion.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
            Write-AppLog "Fallo al confirmar activacion de Defender." "WARN"
        }
    })

    # Evento: Desactivar
    $btnDesactivar.Add_Click({
        if ($btnDesactivar.Tag.Habilitado -eq $false) {
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
            "Vas a DESACTIVAR Windows Defender. El equipo quedara sin proteccion antivirus.`n`nContinuar?",
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
            Write-AppLog "Defender desactivado correctamente." "INFO"
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la desactivacion.`n`n$log", "Verificacion", "OK", "Warning") | Out-Null
            Write-AppLog "Fallo al confirmar desactivacion de Defender." "WARN"
        }
    })

    # Evento: Ver Registro
    $btnLog.Add_Click({ Show-LogViewer })

    # Evento: Acerca de...
    $btnAcerca.Add_Click({
        $osInfo = Get-OSInfo
        $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.2
Autor: Ing. Yosvany Hernandez Quintero
Movil: +53 5 2160801
Movil: +53 5 9860911

------------------------------------
Sistema Operativo: $($osInfo.Caption)
Version: $($osInfo.Version)
Build: $($osInfo.BuildNumber)

Carpeta de logs:
$($script:LogFolder)

Descripcion:
Utilidad de bandeja del sistema para activar
o desactivar Windows Defender de forma rapida
y visual. Incluye verificacion automatica del
estado, visor de registro y exclusion para
evitar que el antivirus detenga la aplicacion.

Compatible con:
Windows 7, 8, 8.1, 10 y 11
(hasta 24H2, 25H2 y 26H2)
------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($acercaTexto, "Acerca de...", "OK", "Information") | Out-Null
    })

    # Evento: Salir
    $btnSalir.Add_Click({ $form.Close() })

    $form.Add_Shown({ Update-StatusUI })
    [void]$form.ShowDialog()
}

# ==================================================================
# 16. VERIFICACION INICIAL (al arrancar la app)
# ==================================================================
Write-AppLog "====================================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v3.2" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "====================================================" "INFO"

# Permisos de administrador
if (Test-Admin) {
    Write-AppLog "Ejecutando como Administrador: SI" "INFO"
} else {
    Write-AppLog "Ejecutando como Administrador: NO (acciones limitadas)" "WARN"
}

# Exclusion en Defender
if (Test-Admin) {
    Add-DefenderExclusion | Out-Null
}

# Estado inicial
$script:InitialStatus = Get-DefenderStatus
if ($null -eq $script:InitialStatus) {
    $estadoInicial  = "DESCONOCIDO"
    $detalleInicial = "No se pudo consultar el estado."
} elseif ($script:InitialStatus.AntivirusEnabled) {
    $estadoInicial  = "ACTIVADO"
    $detalleInicial = "Tiempo real: $(if($script:InitialStatus.RealTimeProtectionEnabled){'ON'}else{'OFF'})  |  Tamper: $(if($script:InitialStatus.IsTamperProtected){'ON'}else{'OFF'})"
    Write-AppLog "Estado inicial: ACTIVADO | $detalleInicial" "INFO"
} else {
    $estadoInicial  = "DESACTIVADO"
    $detalleInicial = "El antivirus esta inactivo."
    Write-AppLog "Estado inicial: DESACTIVADO" "WARN"
}

# MessageBox con la verificacion inicial
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
- Clic IZQUIERDO en el icono: abrir el panel.
- Clic DERECHO en el icono: ver el menu de opciones.

Los registros se guardan en:
$($script:LogFolder)
"@

[System.Windows.Forms.MessageBox]::Show(
    $mensajeInicial,
    "Verificacion inicial - Windows Defender",
    "OK",
    "Information") | Out-Null

# ==================================================================
# 17. CREAR ICONO EN LA BANDEJA DEL SISTEMA
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

# ==================================================================
# 18. MENU CONTEXTUAL (CLIC DERECHO)
# ==================================================================
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

$miLog = New-Object System.Windows.Forms.ToolStripMenuItem
$miLog.Text = "Ver Registro"
$miLog.Add_Click({ Show-LogViewer })

$miAcerca = New-Object System.Windows.Forms.ToolStripMenuItem
$miAcerca.Text = "Acerca de..."
$miAcerca.Add_Click({
    $osInfo = Get-OSInfo
    $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.2
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

Compatible con:
Windows 7, 8, 8.1, 10 y 11
(hasta 24H2, 25H2 y 26H2)
"@
    [System.Windows.Forms.MessageBox]::Show($acercaTexto, "Acerca de...", "OK", "Information") | Out-Null
})

$miSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$miSalir.Text = "Salir"
$miSalir.Add_Click({
    Write-AppLog "Aplicacion cerrada por el usuario." "INFO"
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

[void]$menu.Items.Add($miPanel)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miActivar)
[void]$menu.Items.Add($miDesactivar)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miLog)
[void]$menu.Items.Add($miAcerca)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($miSalir)

$menu.Add_Opening({
    $s = Get-DefenderStatus
    if ($null -eq $s) {
        $miActivar.Enabled    = $true
        $miDesactivar.Enabled = $true
    } elseif ($s.AntivirusEnabled) {
        $miActivar.Enabled    = $false
        $miDesactivar.Enabled = $true
    } else {
        $miActivar.Enabled    = $true
        $miDesactivar.Enabled = $false
    }
})

$script:notifyIcon.ContextMenuStrip = $menu

# ==================================================================
# 19. EVENTO: CLIC IZQUIERDO EN EL ICONO
# ==================================================================
$script:notifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-DefenderPanel
    }
})

# ==================================================================
# 20. TOOLTIP INICIAL
# ==================================================================
$script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estadoInicial", "Info")

# ==================================================================
# 21. BUCLE DE MENSAJES
# ==================================================================
[System.Windows.Forms.Application]::Run()