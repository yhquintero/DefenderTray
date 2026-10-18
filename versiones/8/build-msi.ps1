<#
.SYNOPSIS
    Compila el instalador MSI de DefenderTray con WiX Toolset v3.

.DESCRIPTION
    Deja todo listo para compilar sin errores ICE:

      1. Anade WiX Toolset v3 al PATH de la sesion (y, con -PersistPath, al
         PATH guardado de Windows: "C:\Program Files (x86)\WiX Toolset v3.11\bin").
      2. Copia el script con el nombre que espera el .wxs (DefenderTray_8.2.ps1).
      3. Adapta la plantilla DefenderTray.wxs a la version pedida.
      4. Ejecuta candle.exe y light.exe y comprueba el resultado.

    El .wxs ya viene corregido: Platform="x64" y Win64="yes" para que no
    salte ICE80, el componente del acceso directo dentro de ProgramMenuDir
    con RemoveFolder Directory="ProgramMenuDir" para que no salte ICE64, y la
    clave de registro en HKLM para que el componente sea por maquina.

.PARAMETER Version
    Version a compilar: 8.0, 8.1, 8.2... (por defecto, la del repositorio).

.PARAMETER OutputDir
    Carpeta donde se genera el MSI. Por defecto,
    %USERPROFILE%\Desktop\DefenderTray_v<version>_MSI.

.PARAMETER PersistPath
    Ademas de la sesion actual, guarda la carpeta de WiX en el PATH de
    Windows del usuario (-PathScope Machine lo hace para todo el equipo y
    exige ejecutar como Administrador).

.PARAMETER PathScope
    Ambito del PATH guardado cuando se usa -PersistPath: User o Machine.

.EXAMPLE
    .\build-msi.ps1
    Compila el MSI de la 8.2 en el Escritorio.

.EXAMPLE
    .\build-msi.ps1 -Version 8.1 -PersistPath -PathScope Machine
    Compila el MSI de la 8.1 y deja WiX en el PATH de la maquina.

.NOTES
    Requiere WiX Toolset v3 (https://wixtoolset.org/releases/). Con WiX v4 el
    .wxs no es compatible: hay que migrarlo a authoring v4.
#>
[CmdletBinding()]
param(
    [string]$Version = "8.2",
    [string]$OutputDir = "",
    [switch]$PersistPath,
    [ValidateSet("User", "Machine")][string]$PathScope = "User"
)

$ErrorActionPreference = "Stop"

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ---------------------------------------------------------------------------
# 1) WiX Toolset en el PATH
# ---------------------------------------------------------------------------
$scriptAddWiX = Join-Path $raiz "Add-WiXToPath.ps1"
if (Test-Path $scriptAddWiX) {
    . $scriptAddWiX -SessionOnly
} else {
    Write-Warning "No se encuentra Add-WiXToPath.ps1: se usa el PATH tal cual esta."
}

if ($PersistPath) {
    . $scriptAddWiX -Scope $PathScope
}

$candle = Get-Command candle.exe -ErrorAction SilentlyContinue
$light  = Get-Command light.exe -ErrorAction SilentlyContinue
if (-not $candle -or -not $light) {
    throw "No se encuentra candle.exe/light.exe. Instala WiX Toolset v3.11 y ejecuta .\Add-WiXToPath.ps1 (o .\Add-WiXToPath.ps1 -Scope Machine como Administrador)."
}
Write-Host "candle.exe: $($candle.Source)"
Write-Host "light.exe : $($light.Source)"

# ---------------------------------------------------------------------------
# 2) Ficheros de origen
# ---------------------------------------------------------------------------
$origen = Join-Path $raiz ("DefenderTray_{0}_Pro.ps1" -f $Version)
if (-not (Test-Path $origen)) {
    throw "No se encuentra el script $origen"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $env:USERPROFILE ("Desktop\DefenderTray_v{0}_MSI" -f $Version)
}
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}
Write-Host "Carpeta de compilacion: $OutputDir"

# El .wxs espera el nombre "DefenderTray_<version>.ps1" (sin _Pro).
$nombreInstalado = "DefenderTray_{0}.ps1" -f $Version
Copy-Item -Path $origen -Destination (Join-Path $OutputDir $nombreInstalado) -Force

# ---------------------------------------------------------------------------
# 3) Plantilla WiX adaptada a la version
# ---------------------------------------------------------------------------
$plantilla = Join-Path $raiz "DefenderTray.wxs"
if (-not (Test-Path $plantilla)) {
    throw "No se encuentra la plantilla $plantilla"
}

$wxs = Get-Content -Path $plantilla -Raw
$wxs = $wxs -replace 'DefenderTray_8\.2\.ps1', $nombreInstalado
$wxs = $wxs -replace 'Version="8\.2\.0\.0"', ("Version=`"{0}.0.0`"" -f $Version)
$wxs = $wxs -replace 'DefenderTray 8\.2', ("DefenderTray {0}" -f $Version)
$wxs = $wxs -replace 'v8\.2', ("v{0}" -f $Version)
Set-Content -Path (Join-Path $OutputDir "DefenderTray.wxs") -Value $wxs -Encoding UTF8 -Force

$license = Join-Path $raiz "License.rtf"
if (Test-Path $license) {
    Copy-Item -Path $license -Destination (Join-Path $OutputDir "License.rtf") -Force
}

# ---------------------------------------------------------------------------
# 4) candle.exe + light.exe
# ---------------------------------------------------------------------------
$msi = "DefenderTray_v{0}.msi" -f $Version
Push-Location $OutputDir
try {
    Write-Host ""
    Write-Host "> candle.exe -nologo -arch x64 -ext WixUIExtension DefenderTray.wxs" -ForegroundColor Cyan
    & candle.exe -nologo -arch x64 -ext WixUIExtension DefenderTray.wxs
    if ($LASTEXITCODE -ne 0) { throw "candle.exe termino con codigo $LASTEXITCODE" }
    if (-not (Test-Path "DefenderTray.wixobj")) { throw "candle.exe no genero DefenderTray.wixobj" }

    Write-Host ""
    Write-Host "> light.exe -nologo -ext WixUIExtension -o $msi DefenderTray.wixobj" -ForegroundColor Cyan
    & light.exe -nologo -ext WixUIExtension -o $msi DefenderTray.wixobj
    if ($LASTEXITCODE -ne 0) { throw "light.exe termino con codigo $LASTEXITCODE" }
    if (-not (Test-Path $msi)) { throw "light.exe no genero $msi" }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "MSI generado: $(Join-Path $OutputDir $msi)" -ForegroundColor Green
Write-Host "El script instalado se auto-eleva a Administrador: el acceso directo del menu Inicio"
Write-Host "funciona sin permisos y el UAC aparece solo la primera vez."
