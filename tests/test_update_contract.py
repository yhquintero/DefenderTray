"""Static safety contracts for GitHub update and broken-script recovery."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP_PATH = ROOT / "versiones/8/DefenderTray_8.4_Pro.ps1"
RECOVERY_PATH = ROOT / "versiones/8/Reparar-DefenderTray.ps1"
APP = APP_PATH.read_text(encoding="utf-8")
RECOVERY = RECOVERY_PATH.read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    match = re.search(
        rf"^function {re.escape(name)} \{{\n(.*?)^\}}",
        source,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError(f"Missing PowerShell function: {name}")
    return match.group(1)


class UpdateContracts(unittest.TestCase):
    def test_reported_parser_error_is_fixed(self):
        self.assertIn('Conectividad a ${h}: FALLA', APP)
        self.assertNotIn('Conectividad a $h: FALLA', APP)

    def test_updater_reads_and_validates_the_main_branch_script(self):
        fetch = function_body(APP, "Get-GitHubScriptUpdate")
        self.assertIn("/contents/versiones/8/DefenderTray_8.4_Pro.ps1?ref=main", fetch)
        self.assertIn("Get-GitBlobSha1", fetch)
        self.assertIn("Parser]::ParseInput", fetch)
        self.assertIn("Comprobacion de actualizaciones desactivada", fetch)
        self.assertIn('CurrentVersion = "8.4.1"', APP)

        check = function_body(APP, "Test-UpdateAvailable")
        self.assertIn("$new -eq $current", check)
        self.assertIn("$latest.Sha256", check)

    def test_updater_validates_before_backing_up_and_replacing(self):
        update = function_body(APP, "Invoke-AutoUpdate")
        parse = update.index("Parser]::ParseFile")
        backup = update.index("Copy-Item -LiteralPath $targetPath")
        replace = update.index("Move-Item -LiteralPath $tempPath")
        self.assertLess(parse, backup)
        self.assertLess(backup, replace)
        self.assertIn("Get-NormalizedContentSHA256", update)
        self.assertIn(".bak", update)

    def test_recovery_bootstrap_is_independent_and_never_executes_downloaded_code(self):
        self.assertIn("C:\\DefenderTray_8.4_Pro.ps1", RECOVERY)
        self.assertIn("contents/$Path", RECOVERY)
        self.assertIn("Parser]::ParseInput", RECOVERY)
        self.assertIn("Parser]::ParseFile", RECOVERY)
        self.assertIn("Copy-Item -LiteralPath $targetFullPath", RECOVERY)
        self.assertIn("Move-Item -LiteralPath $tempPath", RECOVERY)
        self.assertNotRegex(RECOVERY, r"(?i)\b(Invoke-Expression|IEX)\b")

    def test_powerShell_update_files_are_utf8_without_bom_and_crlf(self):
        for path in (APP_PATH, RECOVERY_PATH):
            data = path.read_bytes()
            self.assertFalse(data.startswith(b"\xef\xbb\xbf"), str(path))
            self.assertNotRegex(data, rb"(?<!\r)\n", str(path))


if __name__ == "__main__":
    unittest.main()
