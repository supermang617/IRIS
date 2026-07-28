param(
    [switch]$WindowsPowerShellChild
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $WindowsPowerShellChild) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -WindowsPowerShellChild
    exit $LASTEXITCODE
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$updateScript = Join-Path $repoRoot "scripts\update_iris_windows.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-update-helper-" + [System.Guid]::NewGuid().ToString("N"))
$fakeWinget = Join-Path $testRoot "winget.exe"

function Invoke-UpdateScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$ShowCode = 0,
        [int]$ListCode = 0,
        [int]$InstallCode = 0,
        [int]$UpgradeCode = 0,
        [string[]]$Arguments = @()
    )

    $logPath = Join-Path $testRoot "$Name.log"
    $stdoutPath = Join-Path $testRoot "$Name.stdout.txt"
    $stderrPath = Join-Path $testRoot "$Name.stderr.txt"
    $scenarioLocalApp = Join-Path $testRoot "$Name-localapp"
    New-Item -ItemType Directory -Force -Path $scenarioLocalApp | Out-Null
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe).Source
    $startInfo.WorkingDirectory = $repoRoot
    $escapedScript = $updateScript.Replace('"', '\"')
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`" $($Arguments -join ' ')"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables["PATH"] = "$testRoot;$env:PATH"
    $startInfo.EnvironmentVariables["FAKE_WINGET_LOG"] = $logPath
    $startInfo.EnvironmentVariables["FAKE_SHOW_CODE"] = [string]$ShowCode
    $startInfo.EnvironmentVariables["FAKE_LIST_CODE"] = [string]$ListCode
    $startInfo.EnvironmentVariables["FAKE_INSTALL_CODE"] = [string]$InstallCode
    $startInfo.EnvironmentVariables["FAKE_UPGRADE_CODE"] = [string]$UpgradeCode
    $startInfo.EnvironmentVariables["LOCALAPPDATA"] = $scenarioLocalApp
    $startInfo.EnvironmentVariables["IRIS_DATA_ROOT"] = ""

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    if (-not $process.WaitForExit(30000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Update-helper scenario '$Name' timed out."
    }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
    Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8
    $commands = if (Test-Path -LiteralPath $logPath) {
        @(Get-Content -LiteralPath $logPath | ForEach-Object { ($_ -split "`t")[0] })
    } else {
        @()
    }
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = "$stdout`n$stderr"
        Commands = $commands
        LocalAppData = $scenarioLocalApp
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $fakeSource = @'
using System;
using System.IO;

public static class FakeWinget
{
    private static int ExitCodeFor(string command)
    {
        string key = "FAKE_" + command.ToUpperInvariant() + "_CODE";
        int value;
        return Int32.TryParse(Environment.GetEnvironmentVariable(key), out value) ? value : 0;
    }

    public static int Main(string[] args)
    {
        string command = args.Length > 0 ? args[0].ToLowerInvariant() : "";
        string log = Environment.GetEnvironmentVariable("FAKE_WINGET_LOG");
        if (!String.IsNullOrEmpty(log))
        {
            File.AppendAllText(log, command + "\t" + String.Join(" ", args) + Environment.NewLine);
        }
        return ExitCodeFor(command);
    }
}
'@
    Add-Type -TypeDefinition $fakeSource -OutputAssembly $fakeWinget -OutputType ConsoleApplication

    $noApplicationsFound = -1978335212
    $noApplicableUpdate = -1978335189

    $check = Invoke-UpdateScenario -Name "check-legacy" -ListCode $noApplicationsFound -Arguments @("-CheckOnly")
    if ($check.ExitCode -ne 0 -or
        -not $check.Output.Contains("available in WinGet") -or
        ($check.Commands -join ",") -ne "show,list") {
        throw "Check-only legacy migration scenario failed: $($check | ConvertTo-Json -Compress)"
    }

    $migrationLegacyRoot = Join-Path $testRoot "migration-localapp\Programs\Iris"
    $legacyMemory = Join-Path $migrationLegacyRoot ".iris-data\memory\approved.json"
    $legacyDiagnostic = Join-Path $migrationLegacyRoot "diagnostics\voice-events.jsonl"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyMemory), (Split-Path -Parent $legacyDiagnostic) | Out-Null
    Set-Content -LiteralPath $legacyMemory -Value '{"memory":"preserve me"}' -Encoding utf8
    Set-Content -LiteralPath $legacyDiagnostic -Value '{"event":"preserve me"}' -Encoding utf8

    $migration = Invoke-UpdateScenario -Name "migration" -ListCode $noApplicationsFound
    if ($migration.ExitCode -ne 0 -or
        -not $migration.Output.Contains("one-time migration") -or
        ($migration.Commands -join ",") -ne "show,list,install") {
        throw "Legacy-to-WinGet migration scenario failed: $($migration | ConvertTo-Json -Compress)"
    }
    $migratedMemory = Join-Path $migration.LocalAppData "Iris\.iris-data\memory\approved.json"
    $migratedDiagnostic = Join-Path $migration.LocalAppData "Iris\diagnostics\voice-events.jsonl"
    if (-not (Test-Path -LiteralPath $migratedMemory -PathType Leaf) -or
        -not (Test-Path -LiteralPath $migratedDiagnostic -PathType Leaf) -or
        -not (Test-Path -LiteralPath $legacyMemory -PathType Leaf) -or
        -not (Test-Path -LiteralPath $legacyDiagnostic -PathType Leaf)) {
        throw "Legacy-to-WinGet migration did not preserve both copied and original state."
    }
    if ((Get-Content -LiteralPath $migratedMemory -Raw) -notlike "*preserve me*" -or
        (Get-Content -LiteralPath $migratedDiagnostic -Raw) -notlike "*preserve me*") {
        throw "Legacy-to-WinGet migration changed preserved state content."
    }

    $current = Invoke-UpdateScenario -Name "already-current" -UpgradeCode $noApplicableUpdate
    if ($current.ExitCode -ne 0 -or
        -not $current.Output.Contains("already current") -or
        ($current.Commands -join ",") -ne "show,list,upgrade") {
        throw "Already-current WinGet scenario failed: $($current | ConvertTo-Json -Compress)"
    }

    $catalogMissing = Invoke-UpdateScenario -Name "catalog-missing" -ShowCode $noApplicationsFound
    if ($catalogMissing.ExitCode -eq 0 -or
        -not $catalogMissing.Output.Contains("not available from the configured WinGet sources") -or
        ($catalogMissing.Commands -join ",") -ne "show") {
        throw "Missing-catalog scenario failed: $($catalogMissing | ConvertTo-Json -Compress)"
    }

    Write-Host "Iris WinGet update-helper behavior test passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove update-helper test directory outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
