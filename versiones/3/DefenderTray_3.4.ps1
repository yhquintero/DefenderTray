<#
.SYNOPSIS
    Control visual de Windows Defender desde la bandeja del sistema.
.DESCRIPTION
    - Verificacion INICIAL estricta del estado al arrancar.
    - Estado ACTIVADO solo si:
        * Servicio WinDefend corriendo
        * RealTimeProtectionEnabled = True
        * Sin politicas DisableAntiSpyware/DisableAntiVirus activas
    - Panel con 5 botones siempre visibles.
    - Visor de registro integrado.
    - Log automatico en %LOCALAPPDATA%\DefenderTray\Logs\.
    - Exclusion automatica en Windows Defender.
.NOTES
    Ejecutar como Administrador.
    Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).
    Creado por: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
    Version: 3.4
#>

# ==================================================================
# 1. ENSAMBLADOS
# ==================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================================================================
# 2. CONSTANTES DE TEXTO (100% ASCII)
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
# 4. PALETA DE COLORES
# ==================================================================
$script:Colors = @{
    HeaderOk       = [System.Drawing.Color]::FromArgb(34, 139, 34)
    HeaderWarn     = [System.Drawing.Color]::FromArgb(178, 34, 34)
    HeaderPartial  = [System.Drawing.Color]::FromArgb(200, 130, 0)
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
}

# ==================================================================
# 5. FUNCION: LEER CLAVES DE POLITICA DE DEFENDER
#    Devuelve $true si hay politica activa que desactiva Defender.
# ==================================================================
function Test-DefenderPolicyDisabled {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (-not (Test-Path $regPath)) { return $false }

        # Valores directos que desactivan Defender
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($null -ne $props) {
            if ($null -ne $props.DisableAntiSpyware -and [int]$props.DisableAntiSpyware -eq 1) { return $true }
            if ($null -ne $props.DisableAntiVirus   -and [int]$props.DisableAntiVirus   -eq 1) { return $true }
        }

        # Subclave Real-Time Protection
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

# ==================================================================
# 6. FUNCION: OBTENER ESTADO DE WINDOWS DEFENDER
#    IsActive = Servicio + RTP + Sin politica
#    Tambien devuelve HasPolicy y ServiceRunning para diagnostico.
# ==================================================================
function Get-DefenderStatus {
    $result = [PSCustomObject]@{
        AntivirusEnabled          = $false
        RealTimeProtectionEnabled = $false
        AMServiceEnabled          = $false
        IsTamperProtected         = $false
        ServiceRunning            = $false
        HasPolicy                 = $false
        IsActive                  = $false
        Source                    = "N/A"
    }

    # 6.1 Cmdlet si existe
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $status = Get-MpComputerStatus -ErrorAction Stop
            $result.AntivirusEnabled          = [bool]$status.AntivirusEnabled
            $result.RealTimeProtectionEnabled = [bool]$status.RealTimeProtectionEnabled
            $result.AMServiceEnabled          = [bool]$status.AMServiceEnabled
            $result.IsTamperProtected         = [bool]$status.IsTamperProtected
            $result.Source                    = "Get-MpComputerStatus"
        } catch {
            $result.Source = "Get-MpComputerStatus (fallo)"
        }
    }

    # 6.2 Servicio WinDefend (fuente mas confiable)
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        $result.ServiceRunning = ($svc.Status -eq 'Running')
    }

    # 6.3 Politica de grupo
    $result.HasPolicy = Test-DefenderPolicyDisabled

    # 6.4 Decision final
    #     ACTIVO solo si las tres condiciones se cumplen
    $result.IsActive = $result.ServiceRunning -and `
                       $result.RealTimeProtectionEnabled -and `
                       (-not $result.HasPolicy)

    return $result
}

# ==================================================================
# 7. FUNCION: DESACTIVAR WINDOWS DEFENDER
# ==================================================================
function Disable-Defender {
    $log = New-Object System.Collections.ArrayList

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
                Write-AppLog "Desactivacion bloqueada: Tamper Protection activa." "ERROR"
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
    }

    try {
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service  -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: DETENIDO / DESHABILITADO")
        Write-AppLog "Servicio WinDefend detenido y deshabilitado." "INFO"
    } catch {
        [void]$log.Add("Aviso (servicio): $($_.Exception.Message)")
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
#    Elimina TODA la rama de politicas recursivamente y restaura
#    servicio + RTP + preferencias.
# ==================================================================
function Enable-Defender {
    $log = New-Object System.Collections.ArrayList

    Write-AppLog "Iniciando activacion de Windows Defender..." "INFO"

    try {
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $tpStatus = Get-MpComputerStatus -ErrorAction Stop
            if ($tpStatus.IsTamperProtected) {
                [void]$log.Add("ADVERTENCIA: Tamper Protection ACTIVA. Los cambios podrian no aplicarse.")
                Write-AppLog "Tamper Protection activa durante activacion." "WARN"
            }
        }
    } catch {}

    # 8.1 Borrar TODA la rama de politicas recursivamente
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    try {
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            [void]$log.Add("Rama de politicas eliminada: HKLM\SOFTWARE\Policies\Microsoft\Windows Defender")
            Write-AppLog "Rama de politicas eliminada recursivamente." "INFO"
        } else {
            [void]$log.Add("No existia la rama de politicas (OK).")
        }
    } catch {
        # Intento alternativo: borrar valores uno por uno
        try {
            Remove-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name "DisableAntiVirus"   -Force -ErrorAction SilentlyContinue
            [void]$log.Add("Politicas eliminadas valor por valor (fallback).")
        } catch {
            [void]$log.Add("Aviso (registro): $($_.Exception.Message)")
        }
    }

    # 8.2 Borrar tambien la clave de Real-Time Protection si quedo
    $rtPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    try {
        if (Test-Path $rtPath) {
            foreach ($n in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
                             "DisableOnAccessProtection","DisableScanOnRealtimeEnable",
                             "DisableIOAVProtection","DisableScriptScanning")) {
                Remove-ItemProperty -Path $rtPath -Name $n -Force -ErrorAction SilentlyContinue
            }
            [void]$log.Add("Claves Real-Time Protection limpiadas.")
        }
    } catch { }

    # 8.3 Reactivar servicios relacionados
    foreach ($svcName in @("WdNisSvc", "Sense")) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Set-Service  -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                [void]$log.Add("Servicio ${svcName}: INICIADO / AUTOMATICO")
                Write-AppLog "Servicio $svcName reactivado." "INFO"
            }
        } catch { }
    }

    # 8.4 Reactivar WinDefend
    try {
        Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$log.Add("Servicio WinDefend: INICIADO / AUTOMATICO")
        Write-AppLog "Servicio WinDefend iniciado." "INFO"
    } catch {
        [void]$log.Add("Aviso (servicio): $($_.Exception.Message)")
    }

    # 8.5 Esperar a que el servicio arranque
    Start-Sleep -Seconds 5

    # 8.6 Reactivar todas las protecciones
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
            Set-MpPreference -DisableBehaviorMonitoring  $false -Force -ErrorAction SilentlyContinue
            Set-MpPreference -DisableIOAVProtection      $false -Force -ErrorAction SilentlyContinue
            Set-MpPreference -DisableScriptScanning      $false -Force -ErrorAction SilentlyContinue
            [void]$log.Add("Preferencias de proteccion restauradas.")
            Write-AppLog "Set-MpPreference aplicado (RTP + Behavior + IOAV + Script)." "INFO"
        }
    } catch {
        [void]$log.Add("Aviso (preferencias): $($_.Exception.Message)")
    }

    # 8.7 Refrescar firmas para forzar re-evaluacion de politicas
    try {
        if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
            Update-MpSignature -ErrorAction SilentlyContinue
            [void]$log.Add("Firmas actualizadas (fuerza re-evaluacion).")
        }
    } catch { }

    # 8.8 Segunda pasada por si el servicio tardo en arrancar
    Start-Sleep -Seconds 3
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    return ($log -join "`n")
}

# ==================================================================
# 9. ADMIN
# ==================================================================
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ==================================================================
# 10. OS INFO
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
        return [PSCustomObject]@{ Caption="Desconocido"; Version="Desconocido"; BuildNumber="Desconocido" }
    }
}

# ==================================================================
# 11. EXCLUSION
# ==================================================================
function Add-DefenderExclusion {
    try {
        $scriptPath = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = (Get-Location).Path }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $scriptPath -Force -ErrorAction Stop
            Write-AppLog "Exclusion agregada: $scriptPath" "INFO"
            return $true
        }
    } catch {
        Write-AppLog "Error al agregar exclusion: $($_.Exception.Message)" "ERROR"
    }
    return $false
}

# ==================================================================
# 12. BOTON COLOR
# ==================================================================
function New-ColorButton {
    param([string]$Texto, [System.Drawing.Color]$Color, [System.Drawing.Color]$Hover, [int]$Y, [int]$Ancho = 320, [int]$Alto = 36)
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
# 13. ESTADO VISUAL BOTON
# ==================================================================
function Set-ButtonVisualState {
    param([System.Windows.Forms.Button]$Boton, [bool]$Habilitado)
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
# 14. VISOR DE LOG
# ==================================================================
function Show-LogViewer {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text            = "Registro de Actividad - DefenderTray"
    $frm.ClientSize      = New-Object System.Drawing.Size(760, 520)
    $frm.StartPosition   = "CenterScreen"
    $frm.Icon            = [System.Drawing.SystemIcons]::Shield
    $frm.BackColor       = $script:Colors.Background
    $frm.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    $pHeader = New-Object System.Windows.Forms.Panel
    $pHeader.Dock = "Top"; $pHeader.Height = 50
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

    $pBottom = New-Object System.Windows.Forms.Panel
    $pBottom.Dock = "Bottom"; $pBottom.Height = 55
    $pBottom.BackColor = $script:Colors.Background
    $frm.Controls.Add($pBottom)

    $btnRefrescar = New-Object System.Windows.Forms.Button
    $btnRefrescar.Text = "Refrescar"; $btnRefrescar.Size = New-Object System.Drawing.Size(120, 34)
    $btnRefrescar.Location = New-Object System.Drawing.Point(15, 10)
    $btnRefrescar.FlatStyle = "Flat"; $btnRefrescar.FlatAppearance.BorderSize = 0
    $btnRefrescar.BackColor = $script:Colors.BtnBlue
    $btnRefrescar.ForeColor = [System.Drawing.Color]::White
    $btnRefrescar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnRefrescar.Cursor = "Hand"
    $pBottom.Controls.Add($btnRefrescar)

    $btnGuardar = New-Object System.Windows.Forms.Button
    $btnGuardar.Text = "Guardar copia..."; $btnGuardar.Size = New-Object System.Drawing.Size(140, 34)
    $btnGuardar.Location = New-Object System.Drawing.Point(145, 10)
    $btnGuardar.FlatStyle = "Flat"; $btnGuardar.FlatAppearance.BorderSize = 0
    $btnGuardar.BackColor = $script:Colors.BtnGreen
    $btnGuardar.ForeColor = [System.Drawing.Color]::White
    $btnGuardar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnGuardar.Cursor = "Hand"
    $pBottom.Controls.Add($btnGuardar)

    $btnAbrirCarpeta = New-Object System.Windows.Forms.Button
    $btnAbrirCarpeta.Text = "Abrir carpeta"; $btnAbrirCarpeta.Size = New-Object System.Drawing.Size(130, 34)
    $btnAbrirCarpeta.Location = New-Object System.Drawing.Point(295, 10)
    $btnAbrirCarpeta.FlatStyle = "Flat"; $btnAbrirCarpeta.FlatAppearance.BorderSize = 0
    $btnAbrirCarpeta.BackColor = $script:Colors.BtnTeal
    $btnAbrirCarpeta.ForeColor = [System.Drawing.Color]::White
    $btnAbrirCarpeta.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnAbrirCarpeta.Cursor = "Hand"
    $pBottom.Controls.Add($btnAbrirCarpeta)

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text = "Cerrar"; $btnCerrar.Size = New-Object System.Drawing.Size(100, 34)
    $btnCerrar.Location = New-Object System.Drawing.Point(645, 10); $btnCerrar.Anchor = "Top,Right"
    $btnCerrar.FlatStyle = "Flat"; $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.BackColor = $script:Colors.BtnDarkGray
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.Cursor = "Hand"
    $pBottom.Controls.Add($btnCerrar)

    function RefrescarLog {
        if (Test-Path $script:LogFile) {
            $c = Get-Content -Path $script:LogFile -Raw -ErrorAction SilentlyContinue
            $txt.Text = if ([string]::IsNullOrEmpty($c)) { "(Archivo vacio)" } else { $c }
        } else {
            $txt.Text = "(No hay log todavia.)`r`n$($script:LogFile)"
        }
        $txt.SelectionStart = $txt.Text.Length; $txt.ScrollToCaret()
    }

    RefrescarLog
    $btnRefrescar.Add_Click({ RefrescarLog })
    $btnGuardar.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "Texto (*.txt)|*.txt|Todos (*.*)|*.*"
        $dlg.FileName = "DefenderTray_Log_{0:yyyy-MM-dd_HHmmss}.txt" -f (Get-Date)
        if ($dlg.ShowDialog() -eq "OK") {
            try {
                if (Test-Path $script:LogFile) { Copy-Item $script:LogFile $dlg.FileName -Force }
                else { $txt.Text | Out-File $dlg.FileName -Encoding UTF8 }
                [System.Windows.Forms.MessageBox]::Show("Guardado en:`n$($dlg.FileName)","OK","OK","Information") | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Error","OK","Error") | Out-Null
            }
        }
    })
    $btnAbrirCarpeta.Add_Click({ Start-Process "explorer.exe" -ArgumentList $script:LogFolder })
    $btnCerrar.Add_Click({ $frm.Close() })

    [void]$frm.ShowDialog()
}

# ==================================================================
# 15. PANEL PRINCIPAL
# ==================================================================
function Show-DefenderPanel {

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Control de Seguridad de Windows"
    $form.ClientSize      = New-Object System.Drawing.Size(360, 470)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.BackColor       = $script:Colors.Background
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon            = [System.Drawing.SystemIcons]::Shield

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"; $header.Height = 60
    $header.BackColor = $script:Colors.HeaderUnknown
    $form.Controls.Add($header)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Text = "Windows Defender"
    $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $lblHeader.ForeColor = [System.Drawing.Color]::White
    $lblHeader.BackColor = [System.Drawing.Color]::Transparent
    $lblHeader.AutoSize = $true
    $lblHeader.Location = New-Object System.Drawing.Point(15, 16)
    $header.Controls.Add($lblHeader)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(15, 72)
    $card.Size = New-Object System.Drawing.Size(330, 82)
    $card.BackColor = $script:Colors.CardBg
    $card.BorderStyle = "FixedSingle"
    $form.Controls.Add($card)

    $lblEstado = New-Object System.Windows.Forms.Label
    $lblEstado.Text = "Estado actual"
    $lblEstado.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEstado.ForeColor = $script:Colors.TextMuted
    $lblEstado.AutoSize = $true
    $lblEstado.Location = New-Object System.Drawing.Point(12, 10)
    $card.Controls.Add($lblEstado)

    $lblValor = New-Object System.Windows.Forms.Label
    $lblValor.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold)
    $lblValor.AutoSize = $true
    $lblValor.Location = New-Object System.Drawing.Point(12, 28)
    $card.Controls.Add($lblValor)

    $lblDetalle = New-Object System.Windows.Forms.Label
    $lblDetalle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDetalle.ForeColor = $script:Colors.TextMuted
    $lblDetalle.AutoSize = $true
    $lblDetalle.Location = New-Object System.Drawing.Point(12, 58)
    $card.Controls.Add($lblDetalle)

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

    function Update-StatusUI {
        $s = Get-DefenderStatus

        $header.BackColor = $script:Colors.HeaderUnknown
        $lblValor.Text = "..."
        $lblValor.ForeColor = $script:Colors.TextMuted
        $lblDetalle.Text = "Consultando estado..."
        $lblDetalle.ForeColor = $script:Colors.TextMuted

        if ($null -eq $s) {
            $lblValor.Text = "DESCONOCIDO"
            $lblDetalle.Text = "No se pudo consultar el estado."
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
            return
        }

        # Detalle de diagnosticos
        $diag = "Servicio:$(if($s.ServiceRunning){'ON'}else{'OFF'})  " +
                "TiempoReal:$(if($s.RealTimeProtectionEnabled){'ON'}else{'OFF'})  " +
                "Politica:$(if($s.HasPolicy){'SI'}else{'NO'})"

        if ($s.IsActive) {
            # ACTIVADO PLENO
            $header.BackColor = $script:Colors.HeaderOk
            $lblValor.Text = "ACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderOk
            $lblDetalle.Text = $diag
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $false
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
        }
        elseif ($s.ServiceRunning -and ($s.HasPolicy -or -not $s.RealTimeProtectionEnabled)) {
            # PARCIAL: servicio corriendo pero politica o RTP bloquean
            $header.BackColor = $script:Colors.HeaderPartial
            $lblValor.Text = "PROTECCION PARCIAL"
            $lblValor.ForeColor = $script:Colors.HeaderPartial
            if ($s.HasPolicy) {
                $lblDetalle.Text = "Politica de grupo bloquea Defender.  $diag"
            } else {
                $lblDetalle.Text = "Proteccion en tiempo real desactivada.  $diag"
            }
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $true
        }
        else {
            # DESACTIVADO
            $header.BackColor = $script:Colors.HeaderWarn
            $lblValor.Text = "DESACTIVADO"
            $lblValor.ForeColor = $script:Colors.HeaderWarn
            $lblDetalle.Text = $diag
            Set-ButtonVisualState -Boton $btnActivar    -Habilitado $true
            Set-ButtonVisualState -Boton $btnDesactivar -Habilitado $false
        }
    }

    # BOTON ACTIVAR
    $btnActivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $lblDetalle.Text = "Activando..."
        $form.Refresh()
        $log = Enable-Defender
        Start-Sleep -Seconds 3
        Update-StatusUI

        $s = Get-DefenderStatus
        Write-AppLog ("Post-activacion: IsActive={0} Servicio={1} RTP={2} Politica={3}" -f `
            $s.IsActive, $s.ServiceRunning, $s.RealTimeProtectionEnabled, $s.HasPolicy) "INFO"

        if ($s.IsActive) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender ACTIVADO correctamente.`n`n$log","Listo","OK","Information") | Out-Null
        } else {
            $msg = "No se pudo activar por completo.`n`n"
            $msg += "Estado actual:`n"
            $msg += "  Servicio WinDefend: $(if($s.ServiceRunning){'CORRIENDO'}else{'DETENIDO'})`n"
            $msg += "  Tiempo real:        $(if($s.RealTimeProtectionEnabled){'ACTIVO'}else{'INACTIVO'})`n"
            $msg += "  Politica de grupo:  $(if($s.HasPolicy){'BLOQUEANDO'}else{'LIBRE'})`n`n"
            if ($s.HasPolicy) {
                $msg += "La politica de grupo sigue bloqueando Defender.`n"
                $msg += "Reinicia el equipo y vuelve a intentarlo, o verifica:`n"
                $msg += "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender"
            }
            $msg += "`n`n$log"
            [System.Windows.Forms.MessageBox]::Show($msg,"Verificacion","OK","Warning") | Out-Null
        }
    })

    # BOTON DESACTIVAR
    $btnDesactivar.Add_Click({
        if (-not (Test-Admin)) {
            [System.Windows.Forms.MessageBox]::Show("Ejecuta el script como Administrador.","Permisos","OK","Warning") | Out-Null
            return
        }
        $c = [System.Windows.Forms.MessageBox]::Show(
            "Vas a DESACTIVAR Windows Defender. Continuar?","Confirmar","YesNo","Warning")
        if ($c -ne "Yes") { return }

        $lblDetalle.Text = "Desactivando..."
        $form.Refresh()
        $log = Disable-Defender
        Start-Sleep -Seconds 3
        Update-StatusUI

        $s = Get-DefenderStatus
        Write-AppLog ("Post-desactivacion: IsActive={0} Servicio={1} RTP={2} Politica={3}" -f `
            $s.IsActive, $s.ServiceRunning, $s.RealTimeProtectionEnabled, $s.HasPolicy) "INFO"

        if (-not $s.IsActive) {
            [System.Windows.Forms.MessageBox]::Show("Windows Defender DESACTIVADO.`n`n$log","Listo","OK","Information") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("No se pudo confirmar la desactivacion.`n`n$log","Verificacion","OK","Warning") | Out-Null
        }
    })

    $btnLog.Add_Click({ Show-LogViewer })

    $btnAcerca.Add_Click({
        $osInfo = Get-OSInfo
        $acercaTexto = @"
CONTROL DE SEGURIDAD DE WINDOWS DEFENDER

Version: 3.4
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
Detecta correctamente el estado real de Defender
comprobando servicio + proteccion en tiempo real
+ politicas de grupo.

Compatible con:
Windows 7, 8, 8.1, 10 y 11
(hasta 24H2, 25H2 y 26H2)
------------------------------------

(c) 2026 - Todos los derechos reservados
"@
        [System.Windows.Forms.MessageBox]::Show($acercaTexto,"Acerca de...","OK","Information") | Out-Null
    })

    $btnSalir.Add_Click({ $form.Close() })

    $form.Add_Shown({ Update-StatusUI })
    [void]$form.ShowDialog()
}

# ==================================================================
# 16. ARRANQUE
# ==================================================================
Write-AppLog "====================================================" "INFO"
Write-AppLog "Aplicacion iniciada - DefenderTray v3.4" "INFO"
Write-AppLog "Autor: Ing. Yosvany Hernandez Quintero" "INFO"
Write-AppLog "====================================================" "INFO"

if (Test-Admin) {
    Write-AppLog "Ejecutando como Administrador: SI" "INFO"
} else {
    Write-AppLog "Ejecutando como Administrador: NO (acciones limitadas)" "WARN"
}

if (Test-Admin) { Add-DefenderExclusion | Out-Null }

$script:InitialStatus = Get-DefenderStatus
if ($null -eq $script:InitialStatus) {
    $estadoInicial  = "DESCONOCIDO"
    $detalleInicial = "No se pudo consultar el estado."
    Write-AppLog "Estado inicial: DESCONOCIDO" "WARN"
} elseif ($script:InitialStatus.IsActive) {
    $estadoInicial  = "ACTIVADO"
    $detalleInicial = "Servicio:ON  TiempoReal:ON  Politica:NO"
    Write-AppLog ("Estado inicial: ACTIVADO | Servicio={0} RTP={1} Politica={2}" -f `
        $script:InitialStatus.ServiceRunning, $script:InitialStatus.RealTimeProtectionEnabled, `
        $script:InitialStatus.HasPolicy) "INFO"
} elseif ($script:InitialStatus.ServiceRunning) {
    $estadoInicial  = "PROTECCION PARCIAL"
    $detalleInicial = "Servicio corriendo, pero falta proteccion real."
    Write-AppLog ("Estado inicial: PARCIAL | Servicio={0} RTP={1} Politica={2}" -f `
        $script:InitialStatus.ServiceRunning, $script:InitialStatus.RealTimeProtectionEnabled, `
        $script:InitialStatus.HasPolicy) "WARN"
} else {
    $estadoInicial  = "DESACTIVADO"
    $detalleInicial = "El antivirus esta inactivo."
    Write-AppLog ("Estado inicial: DESACTIVADO | Servicio={0} RTP={1} Politica={2}" -f `
        $script:InitialStatus.ServiceRunning, $script:InitialStatus.RealTimeProtectionEnabled, `
        $script:InitialStatus.HasPolicy) "WARN"
}

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
- Clic IZQUIERDO: abrir el panel.
- Clic DERECHO:  ver el menu de opciones.

Registros en:
$($script:LogFolder)
"@

[System.Windows.Forms.MessageBox]::Show($mensajeInicial, "Verificacion inicial - Windows Defender", "OK", "Information") | Out-Null

# ==================================================================
# 17. BANDEJA
# ==================================================================
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = [System.Drawing.SystemIcons]::Shield
$script:notifyIcon.Text    = "Control de Seguridad de Windows"
$script:notifyIcon.Visible = $true

# ==================================================================
# 18. MENU CONTEXTUAL
# ==================================================================
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miPanel.Text = "Abrir panel de control"
$miPanel.Add_Click({ Show-DefenderPanel })

$miActivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miActivar.Text = "Activar Windows Defender"
$miActivar.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
        return
    }
    $null = Enable-Defender
    Start-Sleep -Seconds 3
    $s = Get-DefenderStatus
    if ($s.IsActive) {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Activado correctamente.","Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","No se pudo confirmar la activacion.","Warning")
    }
})

$miDesactivar = New-Object System.Windows.Forms.ToolStripMenuItem
$miDesactivar.Text = "Desactivar Windows Defender"
$miDesactivar.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Ejecuta como Administrador.","Permisos","OK","Warning") | Out-Null
        return
    }
    $null = Disable-Defender
    Start-Sleep -Seconds 3
    $s = Get-DefenderStatus
    if (-not $s.IsActive) {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","Desactivado correctamente.","Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(4000,"Windows Defender","No se pudo confirmar la desactivacion.","Warning")
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

Version: 3.4
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
# 19. BUCLE
# ==================================================================
[System.Windows.Forms.Application]::Run()