$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$installer = Join-Path $repoRoot "scripts\install_iris_windows.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iris-installer-path-" + [System.Guid]::NewGuid().ToString("N"))
$profileRoot = Join-Path $testRoot "profile"
$localAppDataRoot = Join-Path $profileRoot "AppData\Local"
$appDataRoot = Join-Path $profileRoot "AppData\Roaming"
$tempRoot = Join-Path $profileRoot "AppData\Local\Temp"
$junctionRoot = Join-Path $localAppDataRoot "Programs\Redirected"
$externalTarget = Join-Path $testRoot "external-target"
$externalSentinel = Join-Path $externalTarget "must-survive.txt"
$engine = if ($PSVersionTable.PSVersion.Major -ge 6) {
    (Get-Command pwsh.exe).Source
} else {
    (Get-Command powershell.exe).Source
}

function Invoke-RejectedInstallRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $engine
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -InstallRoot `"$InstallRoot`" -NonInteractive -SkipShortcuts -SkipSelfCheck"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables["USERPROFILE"] = $profileRoot
    $startInfo.EnvironmentVariables["LOCALAPPDATA"] = $localAppDataRoot
    $startInfo.EnvironmentVariables["APPDATA"] = $appDataRoot
    $startInfo.EnvironmentVariables["TEMP"] = $tempRoot
    $startInfo.EnvironmentVariables["TMP"] = $tempRoot

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit(5000)
        $process.Dispose()
        throw "Installer path-safety scenario '$Name' timed out."
    }
    $process.WaitForExit()
    $output = @(
        $outputTask.GetAwaiter().GetResult(),
        $errorTask.GetAwaiter().GetResult()
    ) -join "`n"
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($exitCode -eq 0 -or
        -not $output.Contains("InstallRoot must be a dedicated child directory")) {
        throw "Installer path-safety scenario '$Name' was not rejected by the containment boundary: $output"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $localAppDataRoot, $appDataRoot, $tempRoot | Out-Null
    Invoke-RejectedInstallRoot -Name "exact-user-profile" -InstallRoot $profileRoot
    Invoke-RejectedInstallRoot -Name "exact-local-app-data" -InstallRoot $localAppDataRoot
    Invoke-RejectedInstallRoot -Name "exact-roaming-app-data" -InstallRoot $appDataRoot
    Invoke-RejectedInstallRoot -Name "exact-temp-root" -InstallRoot $tempRoot
    Invoke-RejectedInstallRoot `
        -Name "sibling-prefix-lookalike" `
        -InstallRoot (Join-Path $testRoot "profile-sibling\Iris")

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $junctionRoot), $externalTarget | Out-Null
    Set-Content -LiteralPath $externalSentinel -Value "outside install boundary" -Encoding utf8
    New-Item -ItemType Junction -Path $junctionRoot -Target $externalTarget | Out-Null
    Invoke-RejectedInstallRoot `
        -Name "junction-escape" `
        -InstallRoot (Join-Path $junctionRoot "Iris")
    if (-not (Test-Path -LiteralPath $externalSentinel -PathType Leaf) -or
        (Get-Content -LiteralPath $externalSentinel -Raw).Trim() -ne "outside install boundary") {
        throw "Installer junction-escape rejection mutated data outside the managed install boundary."
    }

    Write-Host "Windows installer strict path-containment test passed under $($PSVersionTable.PSEdition)."
} finally {
    if (Test-Path -LiteralPath $junctionRoot) {
        # Directory.Delete removes the junction itself without recursively
        # traversing its target.
        [System.IO.Directory]::Delete($junctionRoot)
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove installer path-safety test directory outside temp: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
