[CmdletBinding()]
param(
    [string]$TargetPath = 'C:\DefenderTray_8.4_Pro.ps1',
    [string]$Repository = 'yhquintero/DefenderTray',
    [string]$Branch = 'main'
)

# Recovery bootstrap for a broken DefenderTray .ps1. This file is independent
# of the application so it still runs when the application itself cannot parse.
$ErrorActionPreference = 'Stop'
$scriptPath = 'versiones/8/DefenderTray_8.4_Pro.ps1'
$tempPath = $null
$exitCode = 0

function Get-GitBlobSha1 {
    param([byte[]]$Bytes)
    $header = [System.Text.Encoding]::ASCII.GetBytes(("blob {0}`0" -f $Bytes.Length))
    [byte[]]$blob = $header + $Bytes
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        return ([BitConverter]::ToString($sha1.ComputeHash($blob)).Replace('-', '').ToLowerInvariant())
    } finally { $sha1.Dispose() }
}

function Get-NormalizedContentSha256 {
    param([string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant())
    } finally { $sha256.Dispose() }
}

function Get-GitHubScript {
    param([string]$Repo, [string]$Ref, [string]$Path)
    if ($Repo -notmatch '^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$') {
        throw 'Repository must have the format owner/repo.'
    }
    if ([string]::IsNullOrWhiteSpace($Ref)) { throw 'Branch/ref cannot be empty.' }
    $parts = $Repo -split '/', 2
    $refUrl = [Uri]::EscapeDataString($Ref)
    $uri = "https://api.github.com/repos/$($parts[0])/$($parts[1])/contents/$Path?ref=$refUrl"

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $headers = @{
        'User-Agent' = 'DefenderTray-Recovery'
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    if ($response.type -ne 'file' -or $response.path -ne $Path) {
        throw 'GitHub did not return the expected DefenderTray script.'
    }
    if ($response.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace([string]$response.content)) {
        throw 'GitHub did not return the script as base64; nothing was changed.'
    }

    $bytes = [Convert]::FromBase64String(([string]$response.content -replace '\s', ''))
    $gitSha = Get-GitBlobSha1 -Bytes $bytes
    if ([string]::IsNullOrWhiteSpace([string]$response.sha) -or
        $gitSha -ne ([string]$response.sha).ToLowerInvariant()) {
        throw 'Git blob SHA-1 mismatch; nothing was changed.'
    }
    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $content = $utf8Strict.GetString($bytes)
    if ([string]::IsNullOrWhiteSpace($content) -or $content[0] -eq [char]0xFEFF) {
        throw 'Downloaded script is empty or has an unsupported BOM.'
    }

    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $first = $parseErrors[0]
        throw "Downloaded script fails the PowerShell parser at line $($first.Extent.StartLineNumber): $($first.Message)"
    }
    $match = [regex]::Match($content, '(?m)^\$script:CurrentVersion\s*=\s*"(?<version>\d+(?:\.\d+){1,3})"\s*$')
    if (-not $match.Success) { throw 'Downloaded script has no valid CurrentVersion.' }
    $version = $match.Groups['version'].Value
    $null = [version]$version

    return [pscustomobject]@{
        Version = $version
        Content = $content
        Sha256 = (Get-NormalizedContentSha256 -Text $content)
        GitBlobSha = $gitSha
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { throw 'TargetPath cannot be empty.' }
    if ([IO.Path]::GetExtension($TargetPath) -ine '.ps1') { throw 'TargetPath must name a .ps1 file.' }
    $targetFullPath = [IO.Path]::GetFullPath($TargetPath)
    $targetDirectory = [IO.Path]::GetDirectoryName($targetFullPath)
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        throw "Target folder does not exist: $targetDirectory"
    }

    $source = Get-GitHubScript -Repo $Repository -Ref $Branch -Path $scriptPath
    $tempName = '.DefenderTray_Recovery_' + [guid]::NewGuid().ToString('N') + '.ps1'
    $tempPath = Join-Path $targetDirectory $tempName
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $normalized = $source.Content -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    $normalized = $normalized.Replace("`n", "`r`n")
    [IO.File]::WriteAllText($tempPath, $normalized, $utf8NoBom)

    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($tempPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw 'Staged script failed the PowerShell parser; the target was not changed.'
    }
    $staged = [IO.File]::ReadAllText($tempPath, [System.Text.Encoding]::UTF8)
    if ((Get-NormalizedContentSha256 -Text $staged) -ne $source.Sha256) {
        throw 'Staged script SHA-256 mismatch; the target was not changed.'
    }

    $backupPath = $null
    if (Test-Path -LiteralPath $targetFullPath -PathType Leaf) {
        $backupPath = '{0}.{1}.bak' -f $targetFullPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
        if (Test-Path -LiteralPath $backupPath) {
            $backupPath = '{0}.{1}.bak' -f $targetFullPath, [guid]::NewGuid().ToString('N')
        }
        Copy-Item -LiteralPath $targetFullPath -Destination $backupPath -Force -ErrorAction Stop | Out-Null
    }
    Move-Item -LiteralPath $tempPath -Destination $targetFullPath -Force -ErrorAction Stop | Out-Null
    $tempPath = $null

    Write-Host "Repaired DefenderTray to v$($source.Version)." -ForegroundColor Green
    Write-Host "SHA-256 (LF normalized): $($source.Sha256)"
    if ($backupPath) { Write-Host "Backup: $backupPath" }
    Write-Host 'Close and relaunch DefenderTray to use the repaired script.'
} catch {
    [Console]::Error.WriteLine("Repair failed: $($_.Exception.Message)")
    $exitCode = 1
} finally {
    if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

if ($exitCode -ne 0) { exit $exitCode }
