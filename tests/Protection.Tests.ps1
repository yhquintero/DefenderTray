# Safe regression suite. Load ONLY function definitions via AST, never the app.
# Run with Windows PowerShell 5.1: powershell -NoProfile -File tests/Protection.Tests.ps1
$ErrorActionPreference = 'Stop'
if ($env:OS -eq 'Windows_NT') {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
$path = Join-Path $PSScriptRoot '../versiones/8/DefenderTray_8.2_Pro.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$names = @('Get-QuickStatus', 'Get-ToggleAction', 'Set-MpPrefValue',
    'Test-DefenderSignaturesHealthy', 'Repair-DefenderSignatures', 'Invoke-StartupAutoRepair',
    'Disable-Defender', 'Enable-Defender', 'Restore-LegacyDefenderConfiguration',
    'Get-ProtectionActionAvailability', 'Update-ProtectionButtons', 'Set-PanelBusy', 'Set-NeonButtonState')
$defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($name in $names) {
    $def = @($defs | Where-Object Name -eq $name)
    if ($def.Count -ne 1) { throw "Missing/duplicate function: $name" }
    . ([scriptblock]::Create($def[0].Extent.Text))
}
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:Assertions++
}
$script:Assertions = 0
$script:AuditMode = $false
$script:CfgForensicMode = $false
$script:CfgAutoRepair = $true
$script:Rtp = $true
$script:Av = $true
$script:ProviderFails = $false
$script:SvcRunning = $true
$script:EngineRunning = $true
$script:Policy = $false
$script:RtpRegistry = $false
$script:StartDisabled = $false
$script:Blocked = $false
$script:DownloadFails = $false
$script:Version = '1.421.123.0'
$script:Date = Get-Date
$script:Age = 0
$script:Calls = New-Object System.Collections.ArrayList
# Mocks: no command below can access Windows Defender, registry or network.
function Get-Service { param($Name); [pscustomobject]@{Status=$(if($script:SvcRunning){'Running'}else{'Stopped'})} }
function Get-Process { param($Name); if ($script:EngineRunning) { [pscustomobject]@{Name=$Name} } }
function Test-DefenderPolicyDisabled { $script:Policy }
function Test-DefenderServicesDisabled { $script:StartDisabled }
function Test-RTPDisabled { param([switch]$PolicyOnly); return ($script:RtpRegistry -and (-not $PolicyOnly)) }
function Get-ServiceStartMode { param($Name); if($script:StartDisabled){'Disabled'}else{'Automatic'} }
function Get-MpComputerStatus {
    [CmdletBinding()]param()
    if ($script:ProviderFails) { throw 'Provider unavailable' }
    [pscustomobject]@{ RealTimeProtectionEnabled=$script:Rtp; AntivirusEnabled=$script:Av
        AntivirusSignatureVersion=$script:Version; AntivirusSignatureLastUpdated=$script:Date; AntivirusSignatureAge=$script:Age }
}
function Set-MpPreference {
    [CmdletBinding()]param([bool]$DisableRealtimeMonitoring)
    [void]$script:Calls.Add('Preference')
    # Non-terminating error must be caught by -ErrorAction Stop in the helper.
    if ($script:Blocked) { Write-Error 'Tamper protection'; return }
    $script:Rtp = -not $DisableRealtimeMonitoring
}
function Update-MpSignature {
    [CmdletBinding()]param()
    [void]$script:Calls.Add('Download')
    if ($script:DownloadFails) { throw 'Offline' }
}
function Start-Service { param($Name); [void]$script:Calls.Add("Start:$Name") }
function Wait-WithDoEvents { param($Milliseconds); }
function Write-AppLog { param($Mensaje, $Nivel); }
function Send-AllNotifications { param($Mensaje, $Severidad, $Data); }
function Backup-DefenderRegistry { [void]$script:Calls.Add('Backup'); return $false }
# Dangerous commands must not be reachable in a regression, even in tests.
function Stop-Service { throw 'Forbidden service stop' }
function Stop-Process { throw 'Forbidden process kill' }
function Remove-Item { throw 'Forbidden recursive delete' }
function Remove-ItemProperty { param($Path,$Name); [void]$script:Calls.Add("Remove:$Path|$Name") }
function Set-ItemProperty { param($Path,$Name,$Value,$Type); [void]$script:Calls.Add("Set:$Path|$Name|$Value") }
function Test-Path { param($Path); return $true }
function Get-ItemProperty {
    [pscustomobject]@{ DisableAntiSpyware=1; DisableAntiVirus=1; DisableRealtimeMonitoring=1
        SignatureUpdateInterval=3; ExclusionPath='C:\keep'; UnrelatedPolicy=42 }
}

# Real provider status wins over a running process/registry intent.
Assert ((Get-QuickStatus).Estado -eq 'ACTIVO') 'healthy state'
$null = Disable-Defender
Assert ((Get-QuickStatus).Estado -eq 'DESACTIVADO') 'pause confirmed with motor still running'
Assert ($script:SvcRunning -and $script:EngineRunning) 'pause preserves engine and service'
Assert (($script:Calls -join ',') -eq 'Preference') 'pause only changes RTP'
$script:RtpRegistry = $true
$null = Enable-Defender
Assert ((Get-QuickStatus).Estado -eq 'ACTIVO') 'enable after pause ignores stale local registry'
$script:RtpRegistry = $false
Assert (($script:Calls -join ',') -eq 'Preference,Preference') 'enable never restarts running services or downloads'
$script:Blocked = $true
Assert (-not (Set-MpPrefValue -Nombre DisableRealtimeMonitoring -Valor $true)) 'non-terminating failures are failures'
$log = Disable-Defender
Assert ((Get-QuickStatus).Estado -eq 'ACTIVO') 'blocked pause remains active'
Assert ($log -match 'NO confirmada') 'no false success for blocked operation'
$script:Blocked = $false
$script:ProviderFails = $true
Assert ((Get-QuickStatus).Estado -eq 'PARCIAL') 'unknown provider is never active'
$script:Calls.Clear(); $null = Disable-Defender
Assert ($script:Calls.Count -eq 0) 'unknown status cannot start pause'
Assert ((Get-ToggleAction -Estado (Get-QuickStatus)) -eq 'Activar') 'unknown toggle recovers protection'
$script:ProviderFails = $false
$script:Policy = $true; $script:StartDisabled = $true
Assert ((Get-QuickStatus).Estado -eq 'PARCIAL') 'legacy policy/start disabled is not completed disable'
$log = Enable-Defender
Assert ($log -match 'Recuperacion cancelada') 'failed backup blocks legacy edits'
$script:Calls.Clear()
Restore-LegacyDefenderConfiguration
Assert (@($script:Calls | Where-Object { $_ -match 'Signature Updates|SignatureUpdateInterval|ExclusionPath|UnrelatedPolicy' }).Count -eq 0) 'legacy cleanup preserves signatures, exclusions and unrelated values'
Assert (@($script:Calls | Where-Object { $_ -like 'Remove:*' }).Count -gt 0) 'legacy cleanup actually removes named blocks'
Assert (@($script:Calls | Where-Object { $_ -like 'Set:*' }).Count -eq 8) 'legacy disabled services/drivers recovered selectively'
$script:Policy = $false; $script:StartDisabled = $false
$script:SvcRunning = $false; $script:EngineRunning = $false
Assert ((Get-QuickStatus).Estado -eq 'PARCIAL') 'stopped engine is not a safe pause'
$script:SvcRunning = $true; $script:EngineRunning = $true
$script:Av = $false
Assert ((Get-QuickStatus).Estado -eq 'PARCIAL') 'passive/disabled antivirus is not active'
$script:Av = $true

# No download, service, preference or registry writes in audit mode.
$script:AuditMode = $true; $script:Calls.Clear()
$null = Disable-Defender; $null = Enable-Defender; $null = Repair-DefenderSignatures
Invoke-StartupAutoRepair; Restore-LegacyDefenderConfiguration
Assert ($script:Calls.Count -eq 0) 'audit has no side effects'
$script:AuditMode = $false

# Existing definitions survive a failed update. Version/date, not just age=0.
$script:Calls.Clear(); $script:DownloadFails = $true
$log = Repair-DefenderSignatures
Assert ($log -match 'NO completada' -and $log -notmatch '\[OK\]') 'offline update reports failure'
Assert ($script:Version -eq '1.421.123.0') 'offline update keeps old definitions'
Assert (($script:Calls -join ',') -eq 'Download') 'repair never stops/restarts services'
$script:DownloadFails = $false; $script:Version = '0.0.0.0'
Assert (-not (Test-DefenderSignaturesHealthy -Status (Get-MpComputerStatus))) 'zero version rejected even at age zero'
Assert ((Repair-DefenderSignatures) -notmatch '\[OK\]') 'zero version is not successful repair'
$script:Version = '1.421.123.0'; $script:Date = [datetime]'1970-01-01'
Assert (-not (Test-DefenderSignaturesHealthy -Status (Get-MpComputerStatus))) 'epoch date rejected'
$script:Date = Get-Date; $script:Age = 31
$script:Rtp = $false; $script:Calls.Clear(); Invoke-StartupAutoRepair
Assert ($script:Calls.Count -eq 0) 'startup repair respects paused protection'
$script:Rtp = $true; Invoke-StartupAutoRepair
Assert (($script:Calls -join ',') -eq 'Download') 'startup updates stale definitions non-destructively'
$script:Age = 0
Assert ((Repair-DefenderSignatures) -match '\[OK\]') 'verified update succeeds'

# Button truth table, including the sequence active -> paused -> active.
foreach ($state in @('ACTIVO','DESACTIVADO','PARCIAL','ACTIVO')) {
    $a = Get-ProtectionActionAvailability -Estado $state -Busy $false
    Assert ($a.Activate -eq ($state -ne 'ACTIVO')) "enable availability: $state"
    Assert ($a.Deactivate -eq ($state -eq 'ACTIVO')) "disable availability: $state"
    $a = Get-ProtectionActionAvailability -Estado $state -Busy $true
    Assert (-not $a.Activate -and -not $a.Deactivate) "busy disables both: $state"
}
if ($env:OS -eq 'Windows_NT') {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $script:Colors = @{BtnDisabled=[Drawing.Color]::Gray; BtnDisabledT=[Drawing.Color]::DarkGray}
    $script:PanelBtnActivate = New-Object Windows.Forms.Button
    $script:PanelBtnDisable = New-Object Windows.Forms.Button
    $script:PanelAllButtons = @($script:PanelBtnActivate,$script:PanelBtnDisable)
    foreach ($b in $script:PanelAllButtons) { $b.Tag = @{Normal=[Drawing.Color]::Green; Hover=[Drawing.Color]::Lime} }
    function Update-PanelStatusUI { Update-ProtectionButtons -Estado (Get-QuickStatus) }
    $script:IsBusy = $true; Set-PanelBusy $true
    Assert (-not $script:PanelBtnActivate.Enabled -and -not $script:PanelBtnDisable.Enabled) 'real buttons disabled while busy'
    $script:IsBusy = $false; Set-PanelBusy $false
    Assert (-not $script:PanelBtnActivate.Enabled -and $script:PanelBtnDisable.Enabled) 'finally restores active-state buttons, not both'
    $script:Rtp = $false; Set-PanelBusy $false
    Assert ($script:PanelBtnActivate.Enabled -and -not $script:PanelBtnDisable.Enabled) 'real paused-state buttons'
    foreach ($b in $script:PanelAllButtons) { $b.Dispose() }
}

# Guard the whole maintained script, including deep repair, against reintroduction.
$source = [IO.File]::ReadAllText($path)
Assert ($source -notmatch '(?i)-RemoveDefinitions|taskkill|reg delete|-UpdateInterval') 'no destructive legacy commands'
$cleanup = ($defs | Where-Object Name -eq 'Restore-LegacyDefenderConfiguration').Extent.Text
Assert ($cleanup -notmatch '(?im)\bRemove-Item\s|Signature Updates"\s*=') 'no branch deletion or signature-policy cleanup'
Assert ($source -match '\$Boton.Enabled = \$Habilitado') 'button state changes Enabled, not just paint'
Assert ($source -match 'AccentGreenH 15  285 230 32' -and $source -match 'AccentRedH   255 285 230 32') 'original side-by-side layout'
"PASS: $script:Assertions assertions. App never executed; Defender calls mocked."
