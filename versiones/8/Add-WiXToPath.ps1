<#
.SYNOPSIS
    Anade WiX Toolset v3 al PATH de Windows para poder compilar el MSI.

.DESCRIPTION
    La instalacion de WiX Toolset v3.11 deja candle.exe y light.exe en
    "C:\Program Files (x86)\WiX Toolset v3.11\bin", pero esa carpeta no forma
    parte del PATH: sin ella, "candle.exe" y "light.exe" no se encuentran y el
    instalador no se puede generar. Este script localiza la instalacion de
    WiX y anade su carpeta "bin" al PATH.

    -Scope User    solo para el usuario actual (no hace falta ser Administrador).
    -Scope Machine para todos los usuarios (exige ejecutar como Administrador).
    -SessionOnly  solo en la sesion actual de PowerShell: no toca el PATH
                   guardado en el registro de Windows.
    -Remove       quita la carpeta del PATH guardado.

.PARAMETER Scope
    Ambito del PATH guardado: User (por defecto) o Machine.

.PARAMETER SessionOnly
    Solo actualiza el PATH de la sesion actual de PowerShell.

.PARAMETER Remove
    Quita la carpeta de WiX del PATH en lugar de anadirla.

.EXAMPLE
    .\Add-WiXToPath.ps1
    Anade "C:\Program Files (x86)\WiX Toolset v3.11\bin" al PATH del usuario.

.EXAMPLE
    .\Add-WiXToPath.ps1 -Scope Machine
    Anade la carpeta al PATH de la maquina (ejecutar como Administrador).

.EXAMPLE
    .\Add-WiXToPath.ps1 -Remove
    Quita la carpeta de WiX del PATH guardado.

.NOTES
    Los cambios guardados en el registro no se ven hasta que se abre una
    consola nueva. En la consola actual se puede forzar con:
        $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
#>
[CmdletBinding()]
param(
    [ValidateSet("User", "Machine")][string]$Scope = "User",
    [switch]$SessionOnly,
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

function Get-WiXBinPath {
    # Localiza la carpeta "bin" de WiX Toolset v3 (la que tiene candle.exe y
    # light.exe). Primero mira las instalaciones conocidas y luego cualquier
    # "WiX Toolset v*" de Program Files.
    param([string]$Preferido = "C:\Program Files (x86)\WiX Toolset v3.11\bin")

    $candidatos = New-Object System.Collections.ArrayList
    [void]$candidatos.Add($Preferido)
    [void]$candidatos.Add("C:\Program Files\WiX Toolset v3.11\bin")

    foreach ($base in @("C:\Program Files (x86)", "C:\Program Files")) {
        if (-not (Test-Path $base)) { continue }
        $instalaciones = Get-ChildItem -Path $base -Directory -Filter "WiX Toolset v*" -ErrorAction SilentlyContinue |
            Sort-Object -Property Name -Descending
        foreach ($dir in $instalaciones) {
            [void]$candidatos.Add((Join-Path $dir.FullName "bin"))
        }
    }

    foreach ($dir in $candidatos) {
        if ((Test-Path -LiteralPath (Join-Path $dir "candle.exe")) -and
            (Test-Path -LiteralPath (Join-Path $dir "light.exe"))) {
            return $dir
        }
    }
    return $null
}

function Test-RutaEnPath {
    param([string]$Ruta, [string[]]$Partes)
    $objetivo = $Ruta.TrimEnd("\")
    foreach ($p in $Partes) {
        if ($p.TrimEnd("\") -eq $objetivo) { return $true }
    }
    return $false
}

$bin = Get-WiXBinPath
if (-not $bin) {
    throw "No se encuentra WiX Toolset v3. Descargalo de https://wixtoolset.org/releases/ e instalalo antes de compilar el MSI."
}

Write-Host "WiX Toolset v3 localizado en: $bin"

# 1) PATH de la sesion actual de PowerShell
$sesion = @($env:PATH -split ";" | Where-Object { $_ -ne "" })
if ($Remove) {
    $sesion = @($sesion | Where-Object { -not (Test-RutaEnPath -Ruta $_ -Partes @($bin)) })
} else {
    if (-not (Test-RutaEnPath -Ruta $bin -Partes $sesion)) { $sesion = @($bin) + $sesion }
}
$env:PATH = ($sesion -join ";")

if ($SessionOnly) {
    Write-Host "PATH de la sesion actualizado. No se ha tocado el PATH guardado de Windows."
    return
}

# 2) PATH guardado en Windows (registro)
$guardado = [Environment]::GetEnvironmentVariable("Path", $Scope)
if ($null -eq $guardado) { $guardado = "" }
$partes = @($guardado -split ";" | Where-Object { $_ -ne "" })
if ($Remove) {
    $partes = @($partes | Where-Object { -not (Test-RutaEnPath -Ruta $_ -Partes @($bin)) })
} else {
    if (-not (Test-RutaEnPath -Ruta $bin -Partes $partes)) { $partes = @($bin) + $partes }
}

try {
    [Environment]::SetEnvironmentVariable("Path", ($partes -join ";"), $Scope)
} catch {
    throw "No se pudo escribir el PATH de ambito $Scope : $($_.Exception.Message). Ejecuta el script como Administrador para usar -Scope Machine."
}

if ($Remove) {
    Write-Host "Carpeta de WiX quitada del PATH ($Scope)."
} else {
    Write-Host "Carpeta de WiX anadida al PATH ($Scope): $bin"
}
Write-Host "Abre una consola nueva para que el PATH guardado surta efecto."
Write-Host "Comprobacion: candle.exe -?  /  light.exe -?"
