$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $repoRoot "scripts\test_windows_msix_lifecycle_guest.ps1"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing guest MSIX lifecycle gauntlet: $scriptPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    $messages = @($parseErrors | ForEach-Object Message) -join "; "
    throw "Guest MSIX lifecycle gauntlet has PowerShell parse errors: $messages"
}

$source = Get-Content -LiteralPath $scriptPath -Raw
foreach ($requiredFragment in @(
        "ConfirmDisposableTestGuest",
        "^iris-disposable-guest-[0-9a-fA-F]{32}$",
        "Refusing to run outside a recognized virtual machine",
        "Refusing to replace an existing",
        "Refusing to touch pre-existing Iris user state",
        "requires IRIS_DATA_ROOT to be unset",
        "Get-VerifiedMsixIdentity",
        "AppxSignature.p7x",
        "SignerCertificate.Subject",
        "TimeStamperCertificate",
        "virtual_machine",
        "WackReportPath",
        "appcert.exe",
        "-appxpackagepath",
        "Get-VerifiedWackReport",
        "DtdProcessing",
        "REPORT.OVERALL_RESULT",
        "wack_package_sha256",
        "wack_report_sha256",
        "wack_report_length_bytes",
        "schema = 3",
        "Refusing to overwrite an existing WACK report",
        "[System.StringComparison]::OrdinalIgnoreCase",
        "WackReportPath and EvidencePath must be different files",
        "Refusing to overwrite existing lifecycle evidence",
        "EvidencePath must remain outside the Iris state root",
        "IApplicationActivationManager",
        "PackageFamilyName",
        "AppUserModelId",
        "--msix-lifecycle-probe",
        "Registered Iris activation did not create its lifecycle state probe",
        "release_version",
        "release_sha256",
        "install_succeeded",
        "activation_succeeded",
        "uninstall_succeeded",
        "state_probe_sha256",
        "state_probe_content_base64",
        "state_survived",
        "Release evidence:",
        "[System.IO.File]::WriteAllText",
        "Iris-created lifecycle state did not survive uninstall",
        "State preserved intentionally at:"
    )) {
    if (-not $source.Contains($requiredFragment)) {
        throw "Guest MSIX lifecycle gauntlet is missing required safety behavior: $requiredFragment"
    }
}

foreach ($obsoleteFragment in @(
        "BaselineMsixPath",
        "TargetMsixPath",
        "BaselineVersion",
        "TargetVersion",
        "baseline_state_probe_sha256",
        "target_state_probe_sha256",
        "upgrade_succeeded",
        "-ForceUpdateFromAnyVersion",
        "Package.InstallLocation"
    )) {
    if ($source.Contains($obsoleteFragment)) {
        throw "First production release lifecycle must not use an artificial lower version or direct package path: $obsoleteFragment"
    }
}

$commands = @(
    $ast.FindAll(
        {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        },
        $true
    )
)
$commandNames = @($commands | ForEach-Object { $_.GetCommandName() })
foreach ($requiredCommand in @(
        "Add-AppxPackage",
        "Get-AppxPackage",
        "Remove-AppxPackage",
        "Get-AuthenticodeSignature",
        "Get-CimInstance",
        "Test-Path"
    )) {
    if ($commandNames -notcontains $requiredCommand) {
        throw "Guest MSIX lifecycle gauntlet does not invoke required command: $requiredCommand"
    }
}
foreach ($forbiddenCommand in @(
        "Remove-Item",
        "Clear-Content",
        "Move-Item"
    )) {
    if ($commandNames -contains $forbiddenCommand) {
        throw "Guest MSIX lifecycle gauntlet must not mutate user state with: $forbiddenCommand"
    }
}
if ($source -match "\[System\.IO\.(File|Directory)\]::Delete") {
    throw "Guest MSIX lifecycle gauntlet must not delete files or directories."
}
if ($source.Contains("-AllUsers")) {
    throw "Guest MSIX lifecycle gauntlet must remain scoped to the disposable test user."
}

$addCommands = @($commands | Where-Object { $_.GetCommandName() -eq "Add-AppxPackage" })
if ($addCommands.Count -ne 1) {
    throw "First production release gauntlet must install exactly one real signed MSIX."
}
$removeCommands = @($commands | Where-Object { $_.GetCommandName() -eq "Remove-AppxPackage" })
if ($removeCommands.Count -ne 2) {
    throw "Guest MSIX lifecycle gauntlet must have one planned uninstall and one failure-cleanup path."
}
foreach ($removeCommand in $removeCommands) {
    $removeSource = $removeCommand.Extent.Text
    if (-not $removeSource.Contains("-PreserveApplicationData") -or
        -not $removeSource.Contains("PackageFullName")) {
        throw "Every guest MSIX removal must target the exact package and preserve application data."
    }
}

$guardRejected = $false
try {
    & $scriptPath `
        -MsixPath "missing-release.msix" `
        -ExpectedPublisher "CN=Iris Static Test" `
        -ExpectedVersion "1.0.0.0" `
        -TestContextId "iris-disposable-guest-00000000000000000000000000000000" `
        -WackReportPath "missing-wack.xml" `
        -EvidencePath "missing-evidence.json"
} catch {
    if (-not $_.Exception.Message.Contains("-ConfirmDisposableTestGuest")) {
        throw "Guest gauntlet did not fail first on its explicit disposable-guest confirmation: $($_.Exception.Message)"
    }
    $guardRejected = $true
}
if (-not $guardRejected) {
    throw "Guest gauntlet ran without explicit disposable-guest confirmation."
}

Write-Host "Windows signed production MSIX guest lifecycle static safety test passed."
