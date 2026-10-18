<#
.SYNOPSIS
    Reparador automatico de DefenderTray_4.1.ps1
.DESCRIPTION
    Aplica las siguientes correcciones al archivo:
      1. Reemplaza notacion de punto por indice en asignaciones a $script:AppConfig.
      2. Valida sintaxis final con el Parser de PowerShell.
      3. Crea backup automatico con timestamp.
      4. Muestra un informe detallado de los cambios.
.NOTES
    Ejecutar como Administrador (opcional pero recomendado).
    Autor: Ing. Yosvany Hernandez Quintero
    Movil: +53 5 2160801 / +53 5 9860911
#>

# ==================================================================
# 1. CONFIGURACION
# ==================================================================
$ErrorActionPreference = "Stop"

# Detectar ruta del archivo
$RutasPosibles = @(
    "C:\DefenderTray_4.1.ps1",
    "$env:USERPROFILE\Desktop\DefenderTray_4.1.ps1",
    "$env:USERPROFILE\Downloads\DefenderTray_4.1.ps1",
    ".\DefenderTray_4.1.ps1"
)

$RutaArchivo = $null
foreach ($r in $RutasPosibles) {
    if (Test-Path $r) {
        $RutaArchivo = (Resolve-Path $r).Path
        break
    }
}

if ($null -eq $RutaArchivo) {
    Write-Host ""
    Write-Host "ERROR: No se encontro DefenderTray_4.1.ps1" -ForegroundColor Red
    Write-Host "Buscado en:" -ForegroundColor Yellow
    foreach ($r in $RutasPosibles) { Write-Host "  - $r" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "Arrastra el archivo sobre este script o edita la variable `$RutasPosibles." -ForegroundColor Yellow
    Read-Host "Pulsa Enter para salir"
    exit 1
}

# Si se paso un argumento, usarlo
if ($args.Count -gt 0 -and (Test-Path $args[0])) {
    $RutaArchivo = (Resolve-Path $args[0]).Path
}

# ==================================================================
# 2. BANNER
# ==================================================================
Clear-Host
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   REPARADOR - DefenderTray 4.1" -ForegroundColor Cyan
Write-Host "   Ing. Yosvany Hernandez Quintero" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Archivo objetivo:" -ForegroundColor Yellow
Write-Host "  $RutaArchivo" -ForegroundColor White
Write-Host ""

# ==================================================================
# 3. VERIFICAR QUE EL ARCHIVO EXISTE Y ES LEGIBLE
# ==================================================================
if (-not (Test-Path $RutaArchivo)) {
    Write-Host "ERROR: Archivo no accesible." -ForegroundColor Red
    Read-Host "Pulsa Enter para salir"
    exit 1
}

$info = Get-Item $RutaArchivo
Write-Host "Tamano original: $([math]::Round($info.Length/1KB, 2)) KB" -ForegroundColor Gray
Write-Host ""

# ==================================================================
# 4. CREAR BACKUP
# ==================================================================
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$BackupPath = "$RutaArchivo.backup_$timestamp.bak"
try {
    Copy-Item -Path $RutaArchivo -Destination $BackupPath -Force
    Write-Host "[1/5] Backup creado:" -ForegroundColor Green
    Write-Host "      $BackupPath" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "[1/5] ERROR al crear backup: $($_.Exception.Message)" -ForegroundColor Red
    $r = Read-Host "Continuar sin backup? (s/n)"
    if ($r -ne "s") { exit 1 }
}

# ==================================================================
# 5. LEER CONTENIDO
# ==================================================================
Write-Host "[2/5] Leyendo archivo..." -ForegroundColor Green
$Contenido = Get-Content -Path $RutaArchivo -Raw -Encoding UTF8
if ([string]::IsNullOrEmpty($Contenido)) {
    Write-Host "ERROR: El archivo esta vacio." -ForegroundColor Red
    Read-Host "Pulsa Enter para salir"
    exit 1
}
$lineasOriginales = ($Contenido -split "`n").Count
Write-Host "      $lineasOriginales lineas leidas." -ForegroundColor Gray
Write-Host ""

# ==================================================================
# 6. APLICAR CORRECCIONES
# ==================================================================
Write-Host "[3/5] Aplicando correcciones..." -ForegroundColor Green
Write-Host ""

$Cambios = 0

# ------------------------------------------------------------------
# Fix 1: Notacion de punto -> indice en asignaciones a AppConfig
# ------------------------------------------------------------------
$pattern = '\$script:AppConfig\.([A-Za-z_][A-Za-z0-9_]*)(\s*)='
$ContenidoNuevo = [regex]::Replace($Contenido, $pattern, {
    param($m)
    "`$script:AppConfig['$($m.Groups[1].Value)']$($m.Groups[2].Value)="
})

if ($ContenidoNuevo -ne $Contenido) {
    # Contar cuantas veces se reemplazo
    $matches = [regex]::Matches($Contenido, $pattern)
    $Cambios += $matches.Count
    Write-Host "  [FIX 1] Notacion de punto -> indice" -ForegroundColor White
    Write-Host "          Reemplazos aplicados: $($matches.Count)" -ForegroundColor Gray
    foreach ($m in $matches) {
        Write-Host "          Linea: $($m.Value)" -ForegroundColor DarkGray
    }
    $Contenido = $ContenidoNuevo
} else {
    Write-Host "  [FIX 1] Notacion de punto: ya estaba correcta o no aplica." -ForegroundColor DarkGray
}

Write-Host ""

# ------------------------------------------------------------------
# Fix 2: Asegurar encoding UTF-8 sin BOM
# ------------------------------------------------------------------
$utf8SinBom = New-Object System.Text.UTF8Encoding($false)
Write-Host "  [FIX 2] Encoding UTF-8 sin BOM: aplicado." -ForegroundColor White

Write-Host ""

# ------------------------------------------------------------------
# Fix 3: Validar que no queden mas asignaciones con punto
# ------------------------------------------------------------------
$restantes = [regex]::Matches($Contenido, '\$script:AppConfig\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[^=]')
if ($restantes.Count -gt 0) {
    Write-Host "  [FIX 3] AVISO: quedan $($restantes.Count) asignaciones sin corregir:" -ForegroundColor Yellow
    foreach ($m in $restantes) {
        Write-Host "          $($m.Value)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  [FIX 3] No quedan asignaciones problematicas." -ForegroundColor Green
}

Write-Host ""

# ==================================================================
# 7. GUARDAR ARCHIVO CORREGIDO
# ==================================================================
Write-Host "[4/5] Guardando archivo corregido..." -ForegroundColor Green
try {
    [System.IO.File]::WriteAllText($RutaArchivo, $Contenido, $utf8SinBom)
    $infoNuevo = Get-Item $RutaArchivo
    Write-Host "      Guardado correctamente." -ForegroundColor Gray
    Write-Host "      Tamano nuevo: $([math]::Round($infoNuevo.Length/1KB, 2)) KB" -ForegroundColor Gray
} catch {
    Write-Host "ERROR al guardar: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Restaurando backup..." -ForegroundColor Yellow
    Copy-Item -Path $BackupPath -Destination $RutaArchivo -Force
    Read-Host "Pulsa Enter para salir"
    exit 1
}
Write-Host ""

# ==================================================================
# 8. VALIDAR SINTAXIS
# ==================================================================
Write-Host "[5/5] Validando sintaxis del archivo corregido..." -ForegroundColor Green
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($RutaArchivo, [ref]$null, [ref]$errors)

if ($errors -and $errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  ADVERTENCIA: se encontraron $($errors.Count) errores de sintaxis." -ForegroundColor Yellow
    Write-Host ""
    foreach ($e in $errors) {
        Write-Host "    Linea $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  El archivo se guardo igual. Puedes restaurar el backup si es necesario:" -ForegroundColor Yellow
    Write-Host "    Copy-Item `"$BackupPath`" `"$RutaArchivo`" -Force" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "  OK: sin errores de sintaxis." -ForegroundColor Green
}

Write-Host ""

# ==================================================================
# 9. RESUMEN
# ==================================================================
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   REPARACION COMPLETADA" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Cambios aplicados: $Cambios" -ForegroundColor White
Write-Host "  Backup en: $BackupPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  Para ejecutar la app:" -ForegroundColor Yellow
Write-Host "    powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RutaArchivo`"" -ForegroundColor White
Write-Host ""
Write-Host "  Si algo sale mal, restaura el backup con:" -ForegroundColor Yellow
Write-Host "    Copy-Item `"$BackupPath`" `"$RutaArchivo`" -Force" -ForegroundColor White
Write-Host ""

$r = Read-Host "Ejecutar la app ahora? (s/n)"
if ($r -eq "s") {
    Write-Host ""
    Write-Host "Lanzando DefenderTray_4.1..." -ForegroundColor Green
    Start-Process "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RutaArchivo`""
    Write-Host "Aplicacion lanzada en segundo plano." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Pulsa Enter para salir." -ForegroundColor Cyan
Read-Host