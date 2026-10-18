"""Static safety contracts; no Defender/PowerShell/registry execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'versiones/8/DefenderTray_8.2_Pro.ps1'
SOURCE = SCRIPT.read_text(encoding='utf-8')


def function(name):
    match = re.search(rf'^function {name} \{{\n(.*?)^\}}', SOURCE, re.M | re.S)
    assert match, name
    return match.group(1)


class ProtectionContracts(unittest.TestCase):
    def test_no_destructive_commands_in_maintained_version(self):
        self.assertNotRegex(SOURCE.lower(), r'-removedefinitions|taskkill|reg delete|-updateinterval')
        self.assertNotRegex(function('Disable-Defender'),
                            r'Stop-Service|Stop-Process|Set-ItemProperty|sc\.exe|Remove-Item')
        self.assertIn('Set-MpPrefValue -Nombre DisableRealtimeMonitoring -Valor $true',
                      function('Disable-Defender'))

    def test_signature_repair_is_update_only(self):
        repair = function('Repair-DefenderSignatures')
        self.assertIn('Update-MpSignature -ErrorAction Stop', repair)
        self.assertIn('-SignatureUpdate', repair)
        self.assertIn('$LASTEXITCODE', repair)
        self.assertNotIn('Stop-Service', repair)
        self.assertIn('Test-DefenderSignaturesHealthy', repair)
        self.assertIn('0.0.0.0', function('Test-DefenderSignaturesHealthy'))

    def test_migration_preserves_policy_branches(self):
        cleanup = function('Restore-LegacyDefenderConfiguration')
        self.assertIn('Remove-ItemProperty', cleanup)
        self.assertNotRegex(cleanup, r'\bRemove-Item\s|\b-Recurse\b')
        self.assertNotRegex(cleanup, r'"[^"\n]*Signature Updates"\s*=')
        self.assertIn('Backup-DefenderRegistry', function('Enable-Defender'))
        self.assertIn('Test-RTPDisabled -PolicyOnly', function('Enable-Defender'))
        self.assertNotIn('Test-RTPDisabled', function('Get-QuickStatus'))

    def test_original_button_layout_and_actual_disabling(self):
        for pattern in (r'\$btnActivate\s*=.*15\s+285\s+230\s+32',
                        r'\$btnToggle\s*=.*255\s+285\s+230\s+32'):
            self.assertRegex(SOURCE, pattern)
        self.assertIn('$Boton.Enabled = $Habilitado', function('Set-NeonButtonState'))
        self.assertIn('if (-not $Busy) { Update-PanelStatusUI }', function('Set-PanelBusy'))
        self.assertIn('Update-ProtectionButtons -Estado $s', function('Update-PanelStatusUI'))
        self.assertIn('Invoke-ToggleProtection -Accion "Desactivar"', SOURCE)

    def test_audit_and_provider_checks(self):
        for name in ('Disable-Defender', 'Enable-Defender', 'Repair-DefenderSignatures',
                     'Restore-LegacyDefenderConfiguration', 'Invoke-StartupAutoRepair'):
            self.assertIn('$script:AuditMode', function(name), name)
        status = function('Get-QuickStatus')
        self.assertIn('Get-MpComputerStatus -ErrorAction Stop', status)
        self.assertIn('$known -and', status)
        self.assertIn('$estado = "PARCIAL"', status)
        self.assertIn('ErrorAction = "Stop"', function('Set-MpPrefValue'))

    def test_powershell_file_format(self):
        for path in (SCRIPT, ROOT / 'tests/Protection.Tests.ps1'):
            data = path.read_bytes()
            self.assertFalse(data.startswith(b'\xef\xbb\xbf'), str(path))
            self.assertNotRegex(data, rb'(?<!\r)\n', str(path))
            # The maintained file already embeds HTML with these legacy
            # characters. New test code and protection strings stay ASCII.
            allowed = {'—', '¿', 'ñ'} if path == SCRIPT else set()
            self.assertFalse(set(data.decode('utf-8')) - set(map(chr, range(128))) - allowed,
                             str(path))


if __name__ == '__main__':
    unittest.main()
