<#
.SYNOPSIS
    Utilidad de bandeja del sistema para activar/desactivar Windows Defender.
.DESCRIPTION
    Crea un icono en la bandeja del sistema con menú contextual para:
      - Desactivar Windows Defender (servicio, tiempo real y registro).
      - Activar Windows Defender (revertir cambios).
      - Salir de la aplicación.
    Verifica el estado después de cada acción y muestra una notificación.
.NOTES
    Ejecutar como Administrador.
    Compatible con Windows 7, 8, 8.1, 10 y 11 (24H2, 25H2, 26H2).
#>

# ──────────────────────────────────────────────
# 1. Cargar ensamblados necesarios para WinForms
# ──────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ──────────────────────────────────────────────
# 2. Función para verificar el estado de Defender
# ──────────────────────────────────────────────
function Get-DefenderStatus {
    try {
        # En Windows 10/11 se puede usar Get-MpComputerStatus
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $status = Get-MpComputerStatus -ErrorAction Stop
            return [PSCustomObject]@{
                AntivirusEnabled          = $status.AntivirusEnabled
                RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
                AMServiceEnabled          = $status.AMServiceEnabled
                IsTamperProtected         = $status.IsTamperProtected
            }
        }
        else {
            # Fallback para Windows 7/8/8.1: consultar el servicio
            $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                AntivirusEnabled          = ($svc.Status -eq 'Running')
                RealTimeProtectionEnabled = ($svc.Status -eq 'Running')
                AMServiceEnabled          = ($svc.Status -eq 'Running')
                IsTamperProtected         = $false
            }
        }
    }
    catch {
        return $null
    }
}

# ──────────────────────────────────────────────
# 3. Función para desactivar Windows Defender
# ──────────────────────────────────────────────
function Disable-Defender {
    $result = [System.Collections.ArrayList]@()

    # 3.1 Desactivar monitoreo en tiempo real (Windows 8/10/11)
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction Stop
            [void]$result.Add("Monitoreo en tiempo real desactivado.")
        }
    } catch { [void]$result.Add("Error al desactivar monitoreo: $_") }

    # 3.2 Detener y deshabilitar el servicio WinDefend
    try {
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        [void]$result.Add("Servicio WinDefend detenido y deshabilitado.")
    } catch { [void]$result.Add("Error al detener servicio: $_") }

    # 3.3 Crear claves de registro para desactivación permanente
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    )
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }

    try {
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" `
            -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" `
            -Name "DisableAntiVirus" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        [void]$result.Add("Claves de registro DisableAntiSpyware/DisableAntiVirus establecidas a 1.")
    } catch { [void]$result.Add("Error al escribir registro: $_") }

    # 3.4 Detener servicios relacionados (si existen)
    $svcList = @("WdNisSvc", "Sense")
    foreach ($svcName in $svcList) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
            [void]$result.Add("Servicio $svcName detenido/deshabilitado.")
        } catch { }
    }

    return $result -join "`n"
}

# ──────────────────────────────────────────────
# 4. Función para activar Windows Defender
# ──────────────────────────────────────────────
function Enable-Defender {
    $result = [System.Collections.ArrayList]@()

    # 4.1 Eliminar claves de registro que bloquean Defender
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" `
            -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" `
            -Name "DisableAntiVirus" -Force -ErrorAction SilentlyContinue
        [void]$result.Add("Claves de registro DisableAntiSpyware/DisableAntiVirus eliminadas.")
    } catch { [void]$result.Add("Error al eliminar claves: $_") }

    # 4.2 Reactivar el servicio WinDefend
    try {
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        [void]$result.Add("Servicio WinDefend reactivado.")
    } catch { [void]$result.Add("Error al reactivar servicio: $_") }

    # 4.3 Reactivar monitoreo en tiempo real (Windows 8/10/11)
    try {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -Force -ErrorAction Stop
            [void]$result.Add("Monitoreo en tiempo real reactivado.")
        }
    } catch { [void]$result.Add("Error al reactivar monitoreo: $_") }

    return $result -join "`n"
}

# ──────────────────────────────────────────────
# 5. Crear el icono de la bandeja del sistema
# ──────────────────────────────────────────────
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield   # Icono de escudo
$script:notifyIcon.Text = "Control de Windows Defender"
$script:notifyIcon.Visible = $true

# ──────────────────────────────────────────────
# 6. Crear el menú contextual (clic derecho)
# ──────────────────────────────────────────────
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# 6.1 Elemento: Desactivar Defender
$menuDisable = New-Object System.Windows.Forms.ToolStripMenuItem
$menuDisable.Text = "❌ Desactivar Windows Defender"
$menuDisable.Add_Click({
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show("Este script debe ejecutarse como Administrador.", "Permisos insuficientes", "OK", "Warning")
        return
    }

    $script:notifyIcon.Text = "Desactivando Defender..."
    $msg = Disable-Defender
    Start-Sleep -Seconds 2   # Dar tiempo a que se apliquen los cambios

    $status = Get-DefenderStatus
    if ($status -and $status.AntivirusEnabled -eq $false) {
        $script:notifyIcon.ShowBalloonTip(5000, "Defender Desactivado", "Windows Defender se ha desactivado correctamente.`n$msg", "Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(5000, "Verificación", "Es posible que Defender siga activo. Revisa la Protección contra alteraciones.`n$msg", "Warning")
    }
    $script:notifyIcon.Text = "Control de Windows Defender"
})

# 6.2 Elemento: Activar Defender
$menuEnable = New-Object System.Windows.Forms.ToolStripMenuItem
$menuEnable.Text = "✅ Activar Windows Defender"
$menuEnable.Add_Click({
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show("Este script debe ejecutarse como Administrador.", "Permisos insuficientes", "OK", "Warning")
        return
    }

    $script:notifyIcon.Text = "Activando Defender..."
    $msg = Enable-Defender
    Start-Sleep -Seconds 2

    $status = Get-DefenderStatus
    if ($status -and $status.AntivirusEnabled -eq $true) {
        $script:notifyIcon.ShowBalloonTip(5000, "Defender Activado", "Windows Defender se ha activado correctamente.`n$msg", "Info")
    } else {
        $script:notifyIcon.ShowBalloonTip(5000, "Verificación", "Es posible que Defender no se haya activado por completo. Reinicia el equipo.`n$msg", "Warning")
    }
    $script:notifyIcon.Text = "Control de Windows Defender"
})

# 6.3 Elemento: Salir
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuExit.Text = "🚪 Salir"
$menuExit.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# Añadir elementos al menú
$contextMenu.Items.Add($menuDisable) | Out-Null
$contextMenu.Items.Add($menuEnable)  | Out-Null
$contextMenu.Items.Add($menuExit)    | Out-Null

# Asignar menú al icono
$script:notifyIcon.ContextMenuStrip = $contextMenu

# ──────────────────────────────────────────────
# 7. Mostrar estado inicial en un tooltip (opcional)
# ──────────────────────────────────────────────
$initialStatus = Get-DefenderStatus
if ($initialStatus) {
    $estado = if ($initialStatus.AntivirusEnabled) { "ACTIVADO" } else { "DESACTIVADO" }
    $script:notifyIcon.ShowBalloonTip(3000, "Windows Defender", "Estado actual: $estado", "Info")
}

# ──────────────────────────────────────────────
# 8. Mantener el script en ejecución (bucle de mensajes)
# ──────────────────────────────────────────────
[System.Windows.Forms.Application]::Run()